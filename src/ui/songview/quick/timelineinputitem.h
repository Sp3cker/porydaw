#pragma once

#include "ui/songview/quick/timelineinput.h"

#include <QCursor>
#include <QFont>
#include <QPalette>
#include <QQuickItem>
#include <QRectF>
#include <QString>

class QEvent;
class QFocusEvent;
class QHoverEvent;
class QKeyEvent;
class QMouseEvent;
class QWheelEvent;

namespace songview {

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

    // Sole attach/detach path: returns when unchanged, detaches the old
    // interaction, then attaches the new one; nullptr only detaches.
    void setInteraction(TimelineBandInteraction *interaction);
    TimelineBandInteraction *interaction() const noexcept;
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
    TimelineBandInteraction *m_interaction = nullptr;
    QString m_accessibilityDescription;
    QFont m_hostFont;
    QPalette m_hostPalette;
};

} // namespace songview
