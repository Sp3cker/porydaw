#include "ui/songview/quick/quickpopupsession.h"

#include "ui/layout.h"
#include "ui/songview/quick/quickwindowinput.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QDebug>
#include <QEvent>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <QVariant>
#include <algorithm>

namespace songview {

QuickPopupSession::QuickPopupSession(QQuickWindow &window, QQmlContext &pageContext,
                                     QObject *parent)
    : QObject(parent)
    , m_window(&window)
    , m_pageContext(&pageContext)
{
    // This filter remains installed after a popup closes so a window
    // deactivation, hide, or close still retires a lingering popup promptly.
    // The swallowed outside-release sequence itself lives in the window's
    // QuickWindowInput owner, never here.
    window.installEventFilter(this);
    connect(&window, &QQuickWindow::activeFocusItemChanged, this, [this] { scheduleFocusCheck(); });
    connect(&window, &QObject::destroyed, this, [this] {
        m_window = nullptr;
        end(true, false);
    });
}

QuickPopupSession::~QuickPopupSession()
{
    if (m_window)
        m_window->removeEventFilter(this);
    end(false, false);
}

bool QuickPopupSession::isOpen() const
{
    return m_kind != Kind::None;
}

QQuickWindow *QuickPopupSession::window() const
{
    return m_window.data();
}

QQuickItem *QuickPopupSession::overlayRoot() const
{
    return m_layer.data();
}

QQuickItem *QuickPopupSession::contentItem() const
{
    return isOpen() ? m_content.data() : nullptr;
}

// The page root bounds the whole popup lifecycle. Entry is refused and a
// live popup cancels without focus restoration while the page is disabled,
// hidden, or detached.
void QuickPopupSession::setPageRoot(QQuickItem *pageRoot)
{
    if (m_pageRoot.data() == pageRoot)
        return;
    for (const QMetaObject::Connection &connection : m_pageConnections)
        QObject::disconnect(connection);
    m_pageConnections.clear();
    m_pageRoot = pageRoot;
    if (m_pageRoot) {
        QQuickItem *const root = m_pageRoot.data();
        m_pageConnections = {
            connect(root, &QQuickItem::xChanged, this,
                    &QuickPopupSession::handlePageGeometryChanged),
            connect(root, &QQuickItem::yChanged, this,
                    &QuickPopupSession::handlePageGeometryChanged),
            connect(root, &QQuickItem::widthChanged, this,
                    &QuickPopupSession::handlePageGeometryChanged),
            connect(root, &QQuickItem::heightChanged, this,
                    &QuickPopupSession::handlePageGeometryChanged),
            connect(root, &QQuickItem::enabledChanged, this,
                    &QuickPopupSession::handlePageEligibilityChanged),
            connect(root, &QQuickItem::visibleChanged, this,
                    &QuickPopupSession::handlePageEligibilityChanged),
            // A destroyed root strands any open popup over a dead page.
            connect(root, &QObject::destroyed, this,
                    &QuickPopupSession::handlePageEligibilityChanged),
        };
    }
    updateLayerPageRect();
    // A replacement or clear can strand a live popup over an ineligible
    // page; eligibility loss never restores focus.
    if (isOpen() && !pageEligible())
        cancel(false);
    emit geometryChanged();
}

// The actual visible page rectangle: the page root mapped into scene space
// and intersected with every clipping ancestor and the window bounds. Empty
// when the root is unset, detached, ineligible, or clipped away entirely —
// there is deliberately no whole-window fallback.
QRectF QuickPopupSession::pageRectInScene() const
{
    QQuickItem *const root = m_pageRoot.data();
    if (!root || !m_window || root->window() != m_window.data() || !root->isEnabled() ||
        !root->isVisible())
        return {};
    QRectF visible = clippedSceneRect(*root, root->boundingRect());
    visible =
        visible.intersected(QRectF(QPointF(0, 0), QSizeF(m_window->width(), m_window->height())));
    return visible.isEmpty() ? QRectF() : visible;
}

// Scene-space union of every visible popup contributor under the overlay:
// the form container, owner-governed surface content, and each active menu
// panel's reported frame. The full-bleed underlay and full-window panel
// items themselves never contribute.
QRectF QuickPopupSession::contentRectInScene() const
{
    QRectF rect;
    if (!isOpen() || !m_layer)
        return rect;
    for (QQuickItem *child : m_layer->childItems()) {
        if (!child || child == m_underlay || !child->isVisible())
            continue;
        const QVariant frame = child->property("frameRect");
        const QRectF local = frame.canConvert<QRectF>() ? frame.value<QRectF>()
                                                        : QRectF(QPointF(0, 0), child->size());
        if (!local.isEmpty())
            rect = rect.united(child->mapRectToScene(local));
    }
    return rect;
}

void QuickPopupSession::notifyGeometryChanged()
{
    emit geometryChanged();
}

bool QuickPopupSession::owns(const QObject *object) const
{
    if (!object)
        return false;
    if (object == this || object == m_owner || object == m_layer || object == m_content)
        return true;
    if (const auto *item = qobject_cast<const QQuickItem *>(object))
        return itemBelongsToPopup(item);
    for (const QObject *current = object; current; current = current->parent()) {
        if (current == this || current == m_owner || current == m_layer || current == m_content)
            return true;
    }
    return false;
}

bool QuickPopupSession::beginMenu(QObject *owner)
{
    if (!owner || !m_window || !pageEligible())
        return false;
    // A replacement ends the old owner before this owner is published. Its
    // cancellation callbacks cannot observe or affect the new session.
    if (isOpen())
        cancel(false);
    if (!ensureLayer())
        return false;
    m_layer->setProperty("formActive", false);
    m_layer->setProperty("surfaceActive", false);

    m_kind = Kind::Menu;
    m_owner = owner;
    m_restoreFocus = m_window->activeFocusItem();
    m_ownerDestroyed = connect(owner, &QObject::destroyed, this, [this] { cancel(false); });
    emit isOpenChanged();
    return true;
}

bool QuickPopupSession::openForm(const QUrl &url, QObject *bridge)
{
    return openContent(url, bridge, Kind::Form);
}

bool QuickPopupSession::openSurface(const QUrl &url, QObject *bridge)
{
    return openContent(url, bridge, Kind::Surface);
}

bool QuickPopupSession::openContent(const QUrl &url, QObject *bridge, Kind kind)
{
    if (!bridge || !m_window || !pageEligible())
        return false;
    if (isOpen())
        cancel(false);
    const bool form = kind == Kind::Form;
    if (!ensureLayer() || (form && !m_formContainer))
        return false;

    QQmlContext *const context = creationContext();
    if (!context)
        return false;
    QQmlEngine *const engine = context->engine();
    if (!engine) {
        qWarning("QuickPopupSession: page context has no QML engine");
        return false;
    }
    QQmlComponent component(engine, url, QQmlComponent::PreferSynchronous);
    if (component.isError()) {
        for (const QQmlError &error : component.errors())
            qWarning().noquote() << error.toString();
        return false;
    }
    QObject *const object = component.createWithInitialProperties(
        {{QStringLiteral("bridge"), QVariant::fromValue(bridge)}}, context);
    QQuickItem *const content = qobject_cast<QQuickItem *>(object);
    if (!content) {
        qWarning("QuickPopupSession: popup QML did not produce a QQuickItem");
        delete object;
        return false;
    }

    m_layer->setProperty("formActive", form);
    m_layer->setProperty("surfaceActive", kind == Kind::Surface);
    m_kind = kind;
    m_owner = bridge;
    m_restoreFocus = m_window->activeFocusItem();
    m_content = content;
    content->setParent(this);
    content->setParentItem(form ? m_formContainer : m_layer);
    m_ownerDestroyed = connect(bridge, &QObject::destroyed, this, [this] { cancel(false); });
    if (form) {
        m_contentWidthChanged = connect(content, &QQuickItem::implicitWidthChanged, this,
                                        &QuickPopupSession::layoutContent);
        m_contentHeightChanged = connect(content, &QQuickItem::implicitHeightChanged, this,
                                         &QuickPopupSession::layoutContent);
        layoutContent();
    }
    emit isOpenChanged();
    if (form)
        scheduleFocusCheck();
    emit geometryChanged();
    return true;
}

void QuickPopupSession::close()
{
    end(false, false);
}

void QuickPopupSession::cancel(bool restoreFocus)
{
    end(true, restoreFocus);
}

void QuickPopupSession::outsidePressed(int button, QPointF scenePos)
{
    if (!isOpen() || !m_window)
        return;
    const Qt::MouseButton mouseButton = static_cast<Qt::MouseButton>(button);
    if (mouseButton == Qt::NoButton)
        return;
    // Record the press sequence in the window owner BEFORE retiring the
    // popup: the paired release must stay swallowed even if this page is
    // destroyed first, so a removed page cannot expose its release to a
    // sibling scene.
    QuickWindowInput::forWindow(*m_window).swallowRelease(mouseButton);
    const bool rightPressed = mouseButton == Qt::RightButton;
    // Snapshot before cancel: end() clears the owner and a cancellation
    // callback may even destroy it, yet right-press retargeting must still
    // learn which owner was dismissed so it cannot steal a newer session.
    const QPointer<QObject> dismissedOwner = m_owner;
    cancel(true);
    if (rightPressed && dismissedOwner)
        emit outsideRightPressed(dismissedOwner.data(), scenePos);
}

bool QuickPopupSession::eventFilter(QObject *watched, QEvent *event)
{
    if (watched != m_window.data() || !isOpen())
        return QObject::eventFilter(watched, event);

    switch (event->type()) {
    case QEvent::WindowDeactivate:
    case QEvent::Hide:
    case QEvent::Close:
        // These can arrive after the underlay already tore down; retire the
        // popup either way. Hide covers tab switches that hide the embedded
        // child while the top-level window stays active, so Deactivate may
        // never fire.
        cancel(false);
        return QObject::eventFilter(watched, event);
    case QEvent::ShortcutOverride:
        // An open popup owns shortcut arbitration. The following KeyPress is
        // a separate event and still reaches the focused prompt control.
        static_cast<QKeyEvent *>(event)->accept();
        return true;
    case QEvent::Resize:
        if (m_kind != Kind::Surface)
            cancel(true);
        break;
    default:
        break;
    }
    return QObject::eventFilter(watched, event);
}

bool QuickPopupSession::ensureLayer()
{
    if (m_layer)
        return true;
    if (!m_window || !m_window->contentItem())
        return false;
    QQmlContext *const context = creationContext();
    if (!context)
        return false;
    QQmlEngine *const engine = context->engine();
    if (!engine) {
        qWarning("QuickPopupSession: page context has no QML engine");
        return false;
    }
    QQmlComponent component(engine,
                            QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/QuickPopupLayer.qml")),
                            QQmlComponent::PreferSynchronous);
    if (component.isError()) {
        for (const QQmlError &error : component.errors())
            qWarning().noquote() << error.toString();
        return false;
    }
    QObject *const object = component.createWithInitialProperties(
        {{QStringLiteral("session"), QVariant::fromValue(this)}}, context);
    QQuickItem *const layer = qobject_cast<QQuickItem *>(object);
    if (!layer) {
        qWarning("QuickPopupSession: QuickPopupLayer.qml did not produce a QQuickItem");
        delete object;
        return false;
    }
    QQuickItem *const formContainer = layer->property("formContainer").value<QQuickItem *>();
    if (!formContainer) {
        qWarning("QuickPopupSession: QuickPopupLayer.qml has no formContainer");
        delete layer;
        return false;
    }
    QQuickItem *const underlay = layer->property("underlay").value<QQuickItem *>();
    if (!underlay) {
        qWarning("QuickPopupSession: QuickPopupLayer.qml has no underlay");
        delete layer;
        return false;
    }
    m_layer = layer;
    m_formContainer = formContainer;
    m_underlay = underlay;
    layer->setParent(this);
    layer->setParentItem(m_window->contentItem());
    updateLayerPageRect();
    return true;
}

QQmlContext *QuickPopupSession::creationContext() const
{
    QQmlContext *const context = m_pageContext.data();
    if (!context) {
        qWarning("QuickPopupSession: page context is gone");
        return nullptr;
    }
    return context;
}

void QuickPopupSession::end(bool wasCancelled, bool restoreFocus)
{
    if (!isOpen())
        return;

    QPointer<QQuickWindow> window = m_window;
    QPointer<QQuickItem> content = m_content;
    QPointer<QQuickItem> layer = m_layer;
    QPointer<QQuickItem> focus = m_restoreFocus;
    QObject::disconnect(m_ownerDestroyed);
    QObject::disconnect(m_contentWidthChanged);
    QObject::disconnect(m_contentHeightChanged);
    m_ownerDestroyed = {};
    m_contentWidthChanged = {};
    m_contentHeightChanged = {};
    m_kind = Kind::None;
    m_owner = nullptr;
    m_content = nullptr;
    m_restoreFocus = nullptr;
    m_seenPopupFocus = false;
    ++m_focusEpoch;
    m_focusCheckPending = false;
    if (content) {
        content->setParentItem(nullptr);
        content->setParent(nullptr);
        content->deleteLater();
    }
    if (layer) {
        layer->setParentItem(nullptr);
        layer->setParent(nullptr);
        layer->deleteLater();
    }
    m_layer = nullptr;
    m_formContainer = nullptr;
    m_underlay = nullptr;

    if (restoreFocus && window && window->isActive() && focus)
        focus->forceActiveFocus(Qt::OtherFocusReason);

    emit isOpenChanged();
    if (wasCancelled)
        emit cancelled(restoreFocus);
    emit closed();
    emit geometryChanged();
}

void QuickPopupSession::layoutContent()
{
    if (m_kind != Kind::Form || !m_window || !m_content || !m_formContainer)
        return;
    const qreal width = m_content->implicitWidth();
    const qreal height = m_content->implicitHeight();
    if (width <= 0.0 || height <= 0.0)
        return;
    m_content->setWidth(width);
    m_content->setHeight(height);
    m_content->setScale(1.0);
    m_content->setPosition(QPointF{});
    m_formContainer->setWidth(width);
    m_formContainer->setHeight(height);
    m_formContainer->setTransformOrigin(QQuickItem::TopLeft);
    const QRectF page = pageRectInScene();
    const qreal margin = layout::space(layout::Space::One);
    // Scale the panel container, not the full overlay, so its MouseArea
    // shield covers only the visible form and every outside point still
    // reaches the underlay. The center and scale budget come from the
    // visible page rect, not the window, so prompts stay inside a
    // translated or partial page slot.
    const qreal availableWidth = (std::max)(0.0, page.width() - 2.0 * margin);
    const qreal availableHeight = (std::max)(0.0, page.height() - 2.0 * margin);
    const qreal scale =
        availableWidth > 0.0 && availableHeight > 0.0
            ? (std::min)(1.0, (std::min)(availableWidth / width, availableHeight / height))
            : 1.0;
    m_formContainer->setScale(scale);
    m_formContainer->setX(page.x() + (page.width() - width * scale) / 2.0);
    m_formContainer->setY(page.y() + (page.height() - height * scale) / 2.0);
    emit geometryChanged();
}

void QuickPopupSession::scheduleFocusCheck()
{
    if (!isOpen() || m_kind == Kind::Surface || m_focusCheckPending)
        return;
    m_focusCheckPending = true;
    const quint64 epoch = ++m_focusEpoch;
    QTimer::singleShot(0, this, [this, epoch] {
        if (epoch == m_focusEpoch)
            checkFocus();
    });
}

void QuickPopupSession::checkFocus()
{
    m_focusCheckPending = false;
    if (!isOpen() || !m_window || m_kind == Kind::Surface)
        return;
    QQuickItem *const focused = m_window->activeFocusItem();
    if (itemBelongsToPopup(focused)) {
        m_seenPopupFocus = true;
        return;
    }
    // QML's Component.onCompleted/Qt.callLater initial focus runs after
    // creation. Only a later escape from an observed popup subtree cancels.
    if (m_seenPopupFocus)
        cancel(true);
}

bool QuickPopupSession::itemBelongsToPopup(const QQuickItem *item) const
{
    for (const QQuickItem *current = item; current; current = current->parentItem()) {
        if (current == m_layer || current == m_content)
            return true;
    }
    return false;
}

bool QuickPopupSession::pageEligible() const
{
    // Detached, disabled, hidden, or fully clipped-away pages refuse popup
    // entry; the visible-rect computation also rejects a stale root left
    // over from a previous host via its window match.
    return !pageRectInScene().isEmpty();
}

void QuickPopupSession::updateLayerPageRect()
{
    if (m_layer)
        m_layer->setProperty("pageRect", pageRectInScene());
}

void QuickPopupSession::handlePageGeometryChanged()
{
    updateLayerPageRect();
    if (!isOpen())
        return;
    if (pageRectInScene().isEmpty()) {
        // The visible page vanished under the popup (clipped away or
        // detached): retire it without restoring outgoing focus, matching
        // eligibility-loss semantics.
        cancel(false);
        return;
    }
    // Geometry drift keeps the popup: forms re-center in the moved page and
    // menu owners re-clamp via pageBoundsChanged. Content reporting stays
    // owner-driven (notifyGeometryChanged), so no relayout recursion.
    if (m_kind == Kind::Form)
        layoutContent();
    emit pageBoundsChanged();
}

void QuickPopupSession::handlePageEligibilityChanged()
{
    // Switching away from the page (disable/hide) retires the popup without
    // restoring outgoing focus, matching detach semantics.
    if (isOpen() && !pageEligible())
        cancel(false);
}

} // namespace songview
