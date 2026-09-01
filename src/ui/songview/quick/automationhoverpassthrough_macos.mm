#import <AppKit/AppKit.h>

#include <QApplication>
#include <QCoreApplication>
#include <QEvent>
#include <QMouseEvent>
#include <QObject>
#include <QPointer>
#include <QRegion>
#include <QWidget>

#include "ui/editordrawer/automationcanvas.h"

namespace {

class AutomationHoverPassThrough final : public QObject
{
  public:
    AutomationHoverPassThrough(AutomationCanvas &canvas, QObject &parent)
        : QObject(&parent)
        , m_canvas(&canvas)
    {
        canvas.installEventFilter(this);
        watchTopLevel(canvas.window());
        qApp->installEventFilter(this);
        m_monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMouseMoved
                                                          handler:^NSEvent *(NSEvent *event) {
                                                            route(event);
                                                            return event;
                                                          }];
    }

    ~AutomationHoverPassThrough() override
    {
        if (m_canvas)
            m_canvas->removeEventFilter(this);
        if (m_topLevel)
            m_topLevel->removeEventFilter(this);
        qApp->removeEventFilter(this);
        if (m_monitor)
            [NSEvent removeMonitor:m_monitor];
    }

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        const bool lostInput =
            event->type() == QEvent::Hide || event->type() == QEvent::WindowDeactivate ||
            event->type() == QEvent::ApplicationDeactivate || event->type() == QEvent::UngrabMouse;
        if (watched == m_canvas) {
            if (event->type() == QEvent::MouseButtonPress ||
                event->type() == QEvent::MouseButtonDblClick) {
                m_buttonGestureActive = true;
            } else if (event->type() == QEvent::MouseButtonRelease) {
                m_buttonGestureActive =
                    static_cast<QMouseEvent *>(event)->buttons() != Qt::NoButton;
            } else if (lostInput) {
                m_buttonGestureActive = false;
                leave();
            } else if (event->type() == QEvent::Leave) {
                m_inside = false;
            }
        } else if ((watched == m_topLevel && (event->type() == QEvent::Leave || lostInput)) ||
                   (watched == qApp && event->type() == QEvent::ApplicationDeactivate)) {
            m_buttonGestureActive = false;
            leave();
        }
        return false;
    }

  private:
    void watchTopLevel(QWidget *topLevel)
    {
        if (m_topLevel == topLevel)
            return;
        if (m_topLevel)
            m_topLevel->removeEventFilter(this);
        m_topLevel = topLevel;
        if (m_topLevel)
            m_topLevel->installEventFilter(this);
    }

    void route(NSEvent *event)
    {
        if (!NSApp.active) {
            m_buttonGestureActive = false;
            leave();
            return;
        }
        if (m_buttonGestureActive || NSEvent.pressedMouseButtons != 0)
            return;
        if (!m_canvas || !m_canvas->isVisible()) {
            leave();
            return;
        }

        QWidget *const topLevel = m_canvas->window();
        watchTopLevel(topLevel);
        const WId nativeId = topLevel ? topLevel->winId() : 0;
        NSView *const contentView = nativeId ? reinterpret_cast<NSView *>(nativeId) : nil;
        if (!contentView || event.window != contentView.window) {
            leave();
            return;
        }

        const NSPoint topLevelPoint = [contentView convertPoint:event.locationInWindow
                                                       fromView:nil];
        const QPoint canvasOrigin = m_canvas->mapTo(topLevel, QPoint{});
        const QPointF canvasPosition(topLevelPoint.x - canvasOrigin.x(),
                                     topLevelPoint.y - canvasOrigin.y());
        if (!m_canvas->visibleRegion().contains(canvasPosition.toPoint())) {
            leave();
            return;
        }

        const QPointF globalPosition(m_canvas->mapToGlobal(canvasPosition.toPoint()));
        QMouseEvent mouseMove(QEvent::MouseMove, canvasPosition, globalPosition, Qt::NoButton,
                              Qt::NoButton, QApplication::keyboardModifiers());
        mouseMove.setTimestamp(quint64(event.timestamp * 1000.0));
        QCoreApplication::sendEvent(m_canvas, &mouseMove);
        m_inside = true;
    }

    void leave()
    {
        if (!m_inside || !m_canvas)
            return;
        QEvent leaveEvent(QEvent::Leave);
        QCoreApplication::sendEvent(m_canvas, &leaveEvent);
        m_inside = false;
    }

    QPointer<AutomationCanvas> m_canvas;
    QPointer<QWidget> m_topLevel;
    id m_monitor = nil;
    bool m_inside = false;
    bool m_buttonGestureActive = false;
};

} // namespace

void installMacAutomationHoverPassThrough(AutomationCanvas &canvas, QObject &owner)
{
    new AutomationHoverPassThrough(canvas, owner);
}
