#pragma once

#include "ui/songview/quick/timelineinput.h"

#include <QQuickItem>

#include <functional>

class QEvent;
class QFocusEvent;
class QHoverEvent;
class QKeyEvent;
class QMouseEvent;
class QWheelEvent;

namespace songview {
// Typed root for the QML scrollbar control. Its QML implementation owns the
// native MouseArea lifecycle and publishes only actual accepted-press state;
// no reflected property lookup or QML callback bridge is needed. QML
// registration creates a derived QQmlElement, so this type stays subclassable.
class TimelineGestureScrollbar : public QQuickItem
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelineGestureScrollbar)

    Q_PROPERTY(bool gestureActive READ gestureActive WRITE setGestureActive NOTIFY
                   gestureActiveChanged FINAL)

  public:
    explicit TimelineGestureScrollbar(QQuickItem *parent = nullptr);

    bool gestureActive() const noexcept;
    void setGestureActive(bool active);

  signals:
    void gestureActiveChanged();

  private:
    bool m_gestureActive = false;
};

struct TimelineKeyPolicy {
    std::function<bool(const TimelineKeyInput &)> press;
    std::function<bool(const TimelineKeyInput &)> release;
};

// The one production TimelineInputHost: a QQuickItem that fills a converted
// band's TimelineSceneBand, normalizes raw Quick events into
// TimelinePointerInput/TimelineWheelInput/TimelineKeyInput values, and accepts
// an event only when the attached interaction handles it. It contains no hit
// testing, gesture rules, or document calls.
// Not final: every Qt 6 QML registration path instantiates the type through a
// derived QQmlElement<T> (qqmlprivate.h), so QML-created types must stay
// subclassable; Q_DISABLE_COPY_MOVE still guards the production type.
class TimelineInputItem : public QQuickItem, public TimelineInputHost
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelineInputItem)

    Q_PROPERTY(QString accessibilityDescription READ accessibilityDescription WRITE
                   setAccessibilityDescription NOTIFY accessibilityDescriptionChanged FINAL)

  public:
    explicit TimelineInputItem(QQuickItem *parent = nullptr);
    ~TimelineInputItem() override;

    // Sole attach/detach path. A forwarding secondary input leaves
    // attachHost false so it emits its own surface and host without replacing
    // the interaction's primary host.
    void setInteraction(TimelineBandInteraction *interaction,
                        TimelineInputSurface surface = TimelineInputSurface::Plot,
                        bool attachHost = true);
    TimelineBandInteraction *interaction() const noexcept;

    // Shared song keyboard policy, installed fresh by the Quick host when it
    // attaches this input and cleared before detach. Local interaction handling
    // always gets the first claim; either phase returns true only when it
    // actually consumes the normalized key event.
    void setKeyPolicy(TimelineKeyPolicy policy);
    void clearKeyPolicy();
    void notifyHostAppearanceChanged();
    void setHostAppearance(const QFont &font, const QPalette &palette);
    QString accessibilityDescription() const;

    // TimelineInputHost
    QRectF bounds() const override;
    qreal devicePixelRatio() const override;
    QFont font() const override;
    QPalette palette() const override;
    QPointF mapFromGlobal(QPointF position) const override;
    QPointF mapToGlobal(QPointF position) const override;
    void requestFocus(Qt::FocusReason reason) override;
    void setCursor(const QCursor &cursor) override;
    void clearCursor() override;
    void releasePointerGrab() override;
    void setAccessibilityDescription(const QString &description) override;

  signals:
    void accessibilityDescriptionChanged();

  protected:
    void mousePressEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void hoverMoveEvent(QHoverEvent *event) override;
    void hoverLeaveEvent(QHoverEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void keyReleaseEvent(QKeyEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void mouseUngrabEvent() override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void itemChange(ItemChange change, const ItemChangeData &data) override;

  private:
    // Buttons this item accepted a press for and still holds the grab for:
    // an involuntary ungrab arms the window owner's swallowed-release state
    // for exactly these buttons before the grab actually transfers.
    int m_grabbedButtons = 0;
    TimelineBandInteraction *m_interaction = nullptr;
    TimelineInputSurface m_surface = TimelineInputSurface::Plot;
    bool m_attachHost = true;
    bool m_attachedInputHost = false;
    TimelineKeyPolicy m_keyPolicy;
    QString m_accessibilityDescription;
    QFont m_hostFont;
    QPalette m_hostPalette;
};

} // namespace songview
