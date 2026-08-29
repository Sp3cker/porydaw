#pragma once

#include <QColor>
#include <QQuickWidget>
#include <span>

#include "ui/activity/trackactivity.h"
#include "ui/activity/trackactivityrender.h"

class QEvent;

// The retained Qt Quick activity adapter. TrackActivityPresentation selects
// it on Windows and Linux; macOS uses it only when the native path is forced off.
class TrackActivityView final : public QQuickWidget
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TrackActivityView)

  public:
    using RowGeometry = track_activity_render::RowGeometry;

    struct TrackDefinition {
        int track;
        QColor identityColor;
    };

    explicit TrackActivityView(QWidget *parent);

    void setTracks(std::span<const TrackDefinition> tracks, RowGeometry geometry);
    void present(const TrackActivity &activity, bool playing);

  protected:
    void changeEvent(QEvent *event) override;

  private:
    class Model;
    Model *m_model;
};
