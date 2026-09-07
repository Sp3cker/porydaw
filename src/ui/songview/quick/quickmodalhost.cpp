#include "ui/songview/quick/quickmodalhost.h"
#include "ui/songview/quick/quickengine.h"

#include <QDebug>

#include <QEvent>
#include <QKeyEvent>
#include <QPoint>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlError>
#include <QSize>

#include <QQuickItem>
#include <QQuickWindow>
#include <QVariant>
#include <QWindow>
#include <QtMath>

namespace songview {

QuickModalHost::QuickModalHost(QQuickWindow &parentWindow, QObject *parent)
    : QObject(parent)
    , m_parentWindow(&parentWindow)
{}

QuickModalHost::~QuickModalHost()
{
    cancel();
}

bool QuickModalHost::isOpen() const noexcept
{
    return m_modalWindow && m_content;
}

QQuickWindow *QuickModalHost::modalWindow() const noexcept
{
    return m_modalWindow.data();
}

bool QuickModalHost::open(const QUrl &contentQml, QObject *bridge, const QString &title)
{
    if (!bridge || !m_parentWindow)
        return false;

    // Replacement first ends the previous owner before any new bridge is
    // published; no stale owner can act on the next dialog's content.
    cancel();

    QQmlEngine *const engine = quickEngine(m_parentWindow);
    if (!engine) {
        qWarning("QuickModalHost: parent window has no QML engine");
        return false;
    }

    auto *window = new QQuickWindow;
    static_cast<QObject *>(window)->setParent(this);
    window->setFlags(Qt::Dialog);
    window->setModality(Qt::ApplicationModal);
    for (QWindow *transientParent = m_parentWindow; transientParent;
         transientParent = transientParent->parent()) {
        if (transientParent->isTopLevel()) {
            window->setTransientParent(transientParent);
            break;
        }
    }
    window->setTitle(title);
    window->setColor(Qt::transparent);
    window->installEventFilter(this);

    QQmlComponent component(engine, contentQml, QQmlComponent::PreferSynchronous);
    if (component.isError()) {
        for (const QQmlError &error : component.errors())
            qWarning().noquote() << error.toString();
        window->deleteLater();
        return false;
    }

    QObject *const object = component.createWithInitialProperties(
        {{QStringLiteral("bridge"), QVariant::fromValue(bridge)}}, engine->rootContext());
    QQuickItem *const content = qobject_cast<QQuickItem *>(object);
    if (!content) {
        qWarning("QuickModalHost: modal QML did not produce a QQuickItem");
        delete object;
        window->deleteLater();
        return false;
    }

    m_modalWindow = window;
    m_content = content;
    m_bridge = bridge;
    // The visual parent also owns the QML object so callers can discover
    // named prompt items from modalWindow(), while this host owns the window.
    content->setParent(window->contentItem());
    content->setParentItem(window->contentItem());
    connect(content, &QQuickItem::implicitWidthChanged, this, &QuickModalHost::resizeToContent);
    connect(content, &QQuickItem::implicitHeightChanged, this, &QuickModalHost::resizeToContent);
    connect(window, &QObject::destroyed, this, [this] {
        if (m_dismissing)
            return;
        m_content = nullptr;
        m_bridge = nullptr;
        emit openChanged();
        emit cancelled();
    });
    m_bridgeDestroyed = connect(bridge, &QObject::destroyed, this, &QuickModalHost::cancel);

    resizeToContent();
    window->show();
    emit openChanged();
    return true;
}

void QuickModalHost::cancel()
{
    dismiss(true);
}

void QuickModalHost::close()
{
    dismiss(false);
}

bool QuickModalHost::eventFilter(QObject *watched, QEvent *event)
{
    if (watched != m_modalWindow.data())
        return QObject::eventFilter(watched, event);

    switch (event->type()) {
    case QEvent::ShortcutOverride:
        // The modal field owns every chord while it is open; its TextInput
        // still receives normal text and native editing shortcuts.
        static_cast<QKeyEvent *>(event)->accept();
        return false;
    case QEvent::Close:
        cancel();
        return false;
    default:
        return QObject::eventFilter(watched, event);
    }
}

void QuickModalHost::dismiss(bool cancelled)
{
    if (!isOpen() || m_dismissing)
        return;

    m_dismissing = true;
    QPointer<QQuickWindow> window = m_modalWindow;
    QPointer<QQuickItem> content = m_content;
    QObject::disconnect(m_bridgeDestroyed);
    m_bridgeDestroyed = {};
    m_modalWindow = nullptr;
    m_content = nullptr;
    m_bridge = nullptr;
    if (content) {
        content->setParentItem(nullptr);
        content->setParent(nullptr);
        content->deleteLater();
    }
    if (window) {
        QObject::disconnect(window, nullptr, this, nullptr);
        window->removeEventFilter(this);
        window->close();
        window->deleteLater();
    }
    m_dismissing = false;
    emit openChanged();
    if (cancelled)
        emit this->cancelled();
    else
        emit closed();
}

void QuickModalHost::resizeToContent()
{
    if (!m_modalWindow || !m_content)
        return;

    const QSize size = QSize(qCeil(m_content->implicitWidth()), qCeil(m_content->implicitHeight()));
    m_content->setSize(size);
    m_modalWindow->resize(size);
    if (m_parentWindow) {
        const QPoint parentCenter = m_parentWindow->mapToGlobal(
            QPoint(m_parentWindow->width() / 2, m_parentWindow->height() / 2));
        m_modalWindow->setPosition(parentCenter - QPoint(size.width() / 2, size.height() / 2));
    }
}

} // namespace songview
