#pragma once

#include <QPointF>
#include <QString>
#include <QVariantMap>

#include "ui/songview/quick/timelineinput.h"

#include <QObject>
class SongView;

namespace songview {

class TimeCamera;
class TimelineQuickScene;
class TimelineQuickView;

class OtherStrip final : public QObject, public TimelineBandInteraction
{
    Q_OBJECT
    Q_PROPERTY(bool toolTipVisible READ toolTipVisible NOTIFY toolTipChanged FINAL)
    Q_PROPERTY(QString toolTipText READ toolTipText NOTIFY toolTipChanged FINAL)
    Q_PROPERTY(QPointF toolTipPosition READ toolTipPosition NOTIFY toolTipChanged FINAL)
    Q_PROPERTY(
        QVariantMap toolTipAppearance READ toolTipAppearance NOTIFY toolTipAppearanceChanged FINAL)
  private:
    struct Geometry {
        int otherEventHitSlop;
        int otherEventMarkerHalfWidth;
        int otherEventMarkerHalfHeight;

        static Geometry resolve();
    };

  public:
    explicit OtherStrip(SongView &owner, QObject *parent = nullptr);

    void attachInputHost(TimelineInputHost &host) override;
    void detachInputHost(TimelineInputHost &host) override;
    bool pointerMove(const TimelinePointerInput &input) override;
    void pointerLeave() override;
    void inputCancelled(TimelineInputCancelReason reason) override;
    void hostAppearanceChanged() override;

    bool toolTipVisible() const { return m_toolTipVisible; }
    QString toolTipText() const { return m_toolTipText; }
    QPointF toolTipPosition() const { return m_toolTipPosition; }
    QVariantMap toolTipAppearance() const { return m_toolTipAppearance; }

  signals:
    void toolTipChanged();
    void toolTipAppearanceChanged();

  private:
    friend class TimelineQuickView;
    void rebuildQuickScene(TimelineQuickScene &scene, bool horizontalPan);
    void requestQuickUpdate();
    void updateToolTip(const QString &text, const QPointF &position);
    void clearToolTip();
    void syncToolTipAppearance();
    SongView &m_owner;
    const songview::TimeCamera &m_camera;
    TimelineInputHost *m_inputHost = nullptr;
    Geometry m_geometry;
    bool m_toolTipVisible = false;
    QString m_toolTipText;
    QPointF m_toolTipPosition;
    QVariantMap m_toolTipAppearance;
};

} // namespace songview
