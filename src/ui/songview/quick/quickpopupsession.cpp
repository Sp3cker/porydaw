#include "ui/songview/quick/quickpopupsession.h"

#include "ui/layout.h"
#include "ui/songview/quick/quickengine.h"

#include <QDebug>
#include <QEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <QVariant>
#include <algorithm>

#include "ui/keymap.h"

namespace {
// A focused numeric field publishes this marker (see DragInput.qml) to opt into
// the transport-chord exception handled in eventFilter below.
constexpr auto kYieldsTransportShortcut = "yieldsTransportPlayPauseShortcut";

bool focusedFieldYieldsTransportShortcut(QQuickWindow *window)
{
    QQuickItem *const focus = window ? window->activeFocusItem() : nullptr;
    return focus && focus->property(kYieldsTransportShortcut).toBool();
}
} // namespace

namespace songview {

QuickPopupSession::QuickPopupSession(QQuickWindow &window, QObject *parent)
    : QObject(parent)
    , m_window(&window)
{
    // This filter remains installed after a popup closes so an outside press
    // cannot leak its matching release through a layer queued for deletion.
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
    if (!owner || !m_window)
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
    if (!bridge || !m_window)
        return false;
    if (isOpen())
        cancel(false);
    const bool form = kind == Kind::Form;
    if (!ensureLayer() || (form && !m_formContainer))
        return false;

    QQmlEngine *const engine = quickEngine(m_window);
    if (!engine) {
        qWarning("QuickPopupSession: canvas window has no QML engine");
        return false;
    }
    QQmlComponent component(engine, url, QQmlComponent::PreferSynchronous);
    if (component.isError()) {
        for (const QQmlError &error : component.errors())
            qWarning().noquote() << error.toString();
        return false;
    }
    QObject *const object = component.createWithInitialProperties(
        {{QStringLiteral("bridge"), QVariant::fromValue(bridge)}}, engine->rootContext());
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
    if (!isOpen())
        return;
    const Qt::MouseButton mouseButton = static_cast<Qt::MouseButton>(button);
    if (mouseButton == Qt::NoButton)
        return;
    m_swallowedReleaseButton = mouseButton;
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
    if (watched != m_window.data())
        return QObject::eventFilter(watched, event);

    switch (event->type()) {
    case QEvent::MouseButtonPress: {
        const auto *const mouseEvent = static_cast<QMouseEvent *>(event);
        // A lost paired release must not consume a later independent gesture.
        if (mouseEvent->button() == m_swallowedReleaseButton)
            m_swallowedReleaseButton = Qt::NoButton;
        break;
    }
    case QEvent::MouseButtonRelease: {
        const auto *const mouseEvent = static_cast<QMouseEvent *>(event);
        if (mouseEvent->button() == m_swallowedReleaseButton) {
            m_swallowedReleaseButton = Qt::NoButton;
            return true;
        }
        break;
    }
    case QEvent::WindowDeactivate:
    case QEvent::Hide:
    case QEvent::Close:
        // These can arrive after the underlay already tore down. Discard the
        // orphaned pair either way: the window will not receive its release.
        // Hide covers tab switches that hide the embedded child while the
        // top-level window stays active, so Deactivate may never fire.
        m_swallowedReleaseButton = Qt::NoButton;
        if (isOpen())
            cancel(false);
        return QObject::eventFilter(watched, event);
    default:
        break;
    }
    if (!isOpen())
        return QObject::eventFilter(watched, event);

    switch (event->type()) {
    case QEvent::ShortcutOverride: {
        // An open popup owns shortcut arbitration, so every chord is claimed
        // here — with one exception: the transport play/pause command over a
        // focused numeric field. The field has no use for that chord, and its
        // QQuickTextInput swallows printable keys before any item handler can
        // decline them, so the session refuses the override on the field's
        // behalf and lets the window's transport action fire.
        auto *keyEvent = static_cast<QKeyEvent *>(event);
        if (focusedFieldYieldsTransportShortcut(m_window.data()) &&
            keymap::Registry::instance().matches(keyEvent,
                                                 QStringLiteral("transport.play_pause"))) {
            keyEvent->ignore();
            return true;
        }
        keyEvent->accept();
        return true;
    }
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
    QQmlEngine *const engine = quickEngine(m_window);
    if (!engine) {
        qWarning("QuickPopupSession: canvas window has no QML engine");
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
        {{QStringLiteral("session"), QVariant::fromValue(this)}}, engine->rootContext());
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
    m_layer = layer;
    m_formContainer = formContainer;
    layer->setParent(this);
    layer->setParentItem(m_window->contentItem());
    return true;
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

    if (restoreFocus && window && window->isActive() && focus)
        focus->forceActiveFocus(Qt::OtherFocusReason);

    emit isOpenChanged();
    if (wasCancelled)
        emit cancelled(restoreFocus);
    emit closed();
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
    const qreal margin = layout::space(layout::Space::One);
    // Scale the panel container, not the full overlay, so its MouseArea
    // shield covers only the visible form and every outside point still
    // reaches the underlay.
    const qreal availableWidth = (std::max)(0.0, m_window->width() - 2.0 * margin);
    const qreal availableHeight = (std::max)(0.0, m_window->height() - 2.0 * margin);
    const qreal scale =
        availableWidth > 0.0 && availableHeight > 0.0
            ? (std::min)(1.0, (std::min)(availableWidth / width, availableHeight / height))
            : 1.0;
    m_formContainer->setScale(scale);
    m_formContainer->setX((m_window->width() - width * scale) / 2.0);
    m_formContainer->setY((m_window->height() - height * scale) / 2.0);
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

} // namespace songview
