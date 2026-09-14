#include "mousehints.h"

#include <QApplication>
#include <QGuiApplication>
#include <QMetaObject>
#include <QQuickItem>
#include <QQuickWindow>
#include <QThread>
#include <QWidget>
#include <QWindow>

namespace ui {

MouseHints::MouseHints(QObject *parent) : QObject(parent)
{
    // Inactive clears and rejects subsequent updates; reactivation requests
    // one coalesced resync so receivers re-evaluate their current target.
    connect(qApp, &QGuiApplication::applicationStateChanged, this,
            [this](Qt::ApplicationState state) {
                if (state == Qt::ApplicationActive) {
                    requestScopeRefresh();
                } else {
                    clearCurrentSource();
                }
            });
}

MouseHints &MouseHints::instance()
{
    static QPointer<MouseHints> service;
    // Latches once the owning QApplication emits destroyed(): children die
    // after that signal inside ~QObject, so a later instance() call during
    // teardown must not recreate the service.
    static bool tornDown = false;
    if (!service) {
        Q_ASSERT(qApp && !tornDown);
        if (!qApp || tornDown)
            qFatal("ui::MouseHints::instance() requires a live QApplication");
        service = new MouseHints(qApp);
        connect(qApp, &QObject::destroyed, [] { tornDown = true; });
    }
    return *service;
}

void MouseHints::claim(QObject *source, ui::hint_profiles::Id profile)
{
    claim(source, profile, Qt::NoModifier);
}

void MouseHints::claim(QObject *source, ui::hint_profiles::Id profile,
                       Qt::KeyboardModifiers stepModifier)
{
    Q_ASSERT(QThread::currentThread() == thread());
    if (!source || !allowsNativeInput(source))
        return;
    if (m_source != source) {
        // Ownership replaces even for an identical profile: drop the old
        // source's observations before wiring the new one, and emit only the
        // final displayed text — no intermediate empty notification.
        if (m_source)
            disconnect(m_source, nullptr, this, nullptr);
        observeSource(source);
        m_source = source;
    }
    const QString text = m_profiles.text(profile, stepModifier);
    if (m_text == text)
        return;
    m_text = text;
    emit hintChanged(m_text);
}

void MouseHints::clear(QObject *source)
{
    Q_ASSERT(QThread::currentThread() == thread());
    if (!source || m_source != source)
        return;
    clearCurrentSource();
}

bool MouseHints::allowsNativeInput(QObject *source) const
{
    if (!source || QGuiApplication::applicationState() != Qt::ApplicationActive)
        return false;

    // The source must be a live, effectively visible, windowed input target.
    if (auto *widget = qobject_cast<QWidget *>(source)) {
        if (!widget->isVisible())
            return false;
    } else if (auto *item = qobject_cast<QQuickItem *>(source)) {
        if (!item->isVisible())
            return false;
    } else {
        return false;
    }
    QWindow *window = sourceWindow(source);
    if (!window)
        return false;

    // A native popup owns input scope; tooltip windows never do. Sources
    // outside the popup are covered until it closes.
    if (QWidget *popup = QApplication::activePopupWidget();
        popup && popup->windowType() != Qt::ToolTip) {
        auto *widget = qobject_cast<QWidget *>(source);
        if (!widget || !(widget == popup || popup->isAncestorOf(widget)))
            return false;
    }

    // Qt delivers WindowBlocked/WindowUnblocked to the blocked QWindows; the
    // observer mirrors that bit as dynamic metadata. Walking the source's own
    // window and native parent chain reuses Qt's modality decision instead of
    // recreating it.
    for (QWindow *w = window; w; w = w->parent()) {
        if (w->property(nativeWindowBlockedProperty).toBool())
            return false;
    }
    return true;
}

QWindow *MouseHints::sourceWindow(QObject *source)
{
    // QWidget::windowHandle() is null for non-native child widgets; the
    // source's input arrives through its top-level widget's window.
    if (auto *widget = qobject_cast<QWidget *>(source))
        return widget->window()->windowHandle();
    if (auto *item = qobject_cast<QQuickItem *>(source))
        return item->window();
    return nullptr;
}

void MouseHints::observeSource(QObject *source)
{
    // ~QObject clears QPointer guards before emitting destroyed(), so
    // m_source is already null when the current owner dies — and non-null
    // when a replaced owner's destruction arrives late. Clearing only on a
    // null m_source satisfies both without touching the dying sender.
    connect(source, &QObject::destroyed, this, [this](QObject *) {
        if (!m_source.isNull())
            return;
        clearCurrentSource();
    });
    if (auto *item = qobject_cast<QQuickItem *>(source)) {
        // QQuickItem::visibleChanged fires on effective-visibility changes;
        // window/parent detachment also terminates the source, including
        // during a grab.
        connect(item, &QQuickItem::visibleChanged, this, [this, item] {
            if (!item->isVisible())
                clearCurrentSource();
        });
        connect(item, &QQuickItem::windowChanged, this, [this, item] {
            if (!item->window())
                clearCurrentSource();
        });
        connect(item, &QQuickItem::parentChanged, this, [this, item] {
            if (!item->window())
                clearCurrentSource();
        });
    }
}

void MouseHints::clearCurrentSource()
{
    if (m_source)
        disconnect(m_source, nullptr, this, nullptr);
    m_source = nullptr;
    if (m_text.isEmpty())
        return;
    m_text.clear();
    emit hintChanged(m_text);
}

void MouseHints::requestScopeRefresh()
{
    if (m_scopeRefreshQueued)
        return;
    m_scopeRefreshQueued = true;
    QMetaObject::invokeMethod(
        this,
        [this] {
            m_scopeRefreshQueued = false;
            emit scopeRefresh();
        },
        Qt::QueuedConnection);
}

} // namespace ui
