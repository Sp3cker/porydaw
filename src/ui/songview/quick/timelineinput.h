#pragma once

#include "ui/songview/timelinebandlayout.h"

#include <cstdint>

#include <QCursor>
#include <QFont>
#include <QPalette>
#include <QPointF>
#include <QRectF>
#include <QString>

namespace songview {

// Normalized band input values. Positions are logical pixels: position is
// band-local, globalPosition is screen-global. Button is the button that
// changed for press/release/double-click; buttons is the full pressed set.
struct TimelinePointerInput {
    QPointF position;
    QPointF globalPosition;
    Qt::MouseButton button;
    Qt::MouseButtons buttons;
    Qt::KeyboardModifiers modifiers;
};

// Pixel wheels deliver pixelDelta; rotary wheels deliver angleDelta. Inverted
// is QWheelEvent::inverted(): consumers that reproduce native scrolling must
// not infer scroll direction from the deltas alone.
struct TimelineWheelInput {
    QPointF position;
    QPointF globalPosition;
    QPoint pixelDelta;
    QPoint angleDelta;
    Qt::KeyboardModifiers modifiers;
    Qt::ScrollPhase phase = Qt::NoScrollPhase;
    bool inverted = false;
};

struct TimelineKeyInput {
    int key = Qt::Key_unknown;
    Qt::KeyboardModifiers modifiers;
    QString text;
    bool autoRepeat = false;
};

enum class TimelineInputCancelReason : uint8_t {
    FocusLost,
    PointerUngrabbed,
    Hidden,
    WindowDeactivated,
};

// Services the six QWidget band surfaces used to inherit: geometry, DPR, font,
// palette, coordinate mapping, focus, cursor, pointer grab, and accessibility.
// The one production implementation is TimelineInputItem; checks use an
// in-memory recorder. Bands store only this pointer and never a QQuickItem.
class TimelineInputHost
{
  public:
    virtual ~TimelineInputHost() = default;

    virtual QRectF bounds() const = 0;
    virtual qreal devicePixelRatio() const = 0;
    virtual QFont font() const = 0;
    virtual QPalette palette() const = 0;
    virtual QPointF mapFromGlobal(QPointF position) const = 0;
    virtual QPointF mapToGlobal(QPointF position) const = 0;

    virtual void requestFocus(Qt::FocusReason reason) = 0;
    virtual void setCursor(const QCursor &cursor) = 0;
    virtual void clearCursor() = 0;
    virtual void releasePointerGrab() = 0;
    virtual void setAccessibilityDescription(const QString &description) = 0;
};

// Band-owned interaction rules. TimelineInputItem forwards normalized input
// here and accepts the matching Qt event only when a method returns true.
// Override only the methods a band handles.
class TimelineBandInteraction
{
  public:
    virtual ~TimelineBandInteraction() = default;

    virtual void attachInputHost(TimelineInputHost &host) = 0;
    virtual void detachInputHost(TimelineInputHost &host) = 0;

    virtual bool pointerPress(const TimelinePointerInput &) { return false; }
    virtual bool pointerDoubleClick(const TimelinePointerInput &) { return false; }
    virtual bool pointerMove(const TimelinePointerInput &) { return false; }
    virtual bool pointerRelease(const TimelinePointerInput &) { return false; }
    virtual void pointerLeave() {}
    virtual bool wheel(const TimelineWheelInput &) { return false; }
    virtual bool keyPress(const TimelineKeyInput &) { return false; }
    virtual bool keyRelease(const TimelineKeyInput &) { return false; }
    virtual void inputCancelled(TimelineInputCancelReason) {}
    virtual void hostAppearanceChanged() {}
};

} // namespace songview
