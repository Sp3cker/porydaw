#pragma once

#include <QImage>
#include <QPointer>
#include <QString>
#include <QtGlobal>

#include "project/voicegroupsource.h"

#include <memory>
class SongTab;
class SongView;
class QQuickItem;

namespace checks {
class ProjectFixture;
class LoadedSong;
} // namespace checks

namespace songview {
class PianoRoll;
class TimeRuler;
class TimelineInputItem;
class TimelineQuickView;
class TrackHeaderModel;
} // namespace songview

class EventListView;
class EditorDrawer;

namespace checks::rollcheck::staticcheck {

struct Raster {
    QImage image;
    qreal dpr = 1.0;

    [[nodiscard]] bool valid() const;
    [[nodiscard]] QRgb at(qreal logicalX, qreal logicalY) const;
    [[nodiscard]] int deviceX(qreal logicalX) const;
};

[[nodiscard]] Raster captureRuler(SongView &view);
[[nodiscard]] int rulerBandHeight(const SongView &view);
[[nodiscard]] qreal rulerPlotOffset(const SongView &view);

// Owns a real production tab for transaction-only camera assertions. It uses
// SongTab's production documentChanged connection; no test-side timeline mirror.
class CameraFixture final
{
  public:
    CameraFixture(QString projectRoot, QString songLabel);
    ~CameraFixture();
    Q_DISABLE_COPY_MOVE(CameraFixture)

    [[nodiscard]] bool create(QString &error);
    [[nodiscard]] SongTab *tab() const noexcept;
    [[nodiscard]] SongView *view() const noexcept;
    [[nodiscard]] songview::PianoRoll *roll() const noexcept;
    [[nodiscard]] songview::TimelineInputItem *rollInput() const noexcept;
    [[nodiscard]] songview::TimelineInputItem *gutterInput() const noexcept;
    [[nodiscard]] int track() const noexcept;

  private:
    QString m_projectRoot;
    QString m_songLabel;
    std::unique_ptr<checks::ProjectFixture> m_project;
    std::unique_ptr<LoadedVoiceGroup> m_bank;
    std::unique_ptr<SongTab> m_tab;
    QPointer<songview::PianoRoll> m_roll;
    QPointer<songview::TimelineInputItem> m_rollInput;
    QPointer<songview::TimelineInputItem> m_gutterInput;
    int m_track = -1;
};

// A deliberately local loading-stage fixture. Geometry slots use bare SongView
// instead; only gate and readiness slots construct a transactional SongTab.
class GateFixture final
{
  public:
    GateFixture();
    ~GateFixture();
    Q_DISABLE_COPY_MOVE(GateFixture)

    [[nodiscard]] bool create(QString &error);
    [[nodiscard]] SongTab *tab() const noexcept;
    [[nodiscard]] SongView *view() const noexcept;
    [[nodiscard]] songview::TimelineInputItem *rollInput() const noexcept;
    [[nodiscard]] songview::TimelineInputItem *rulerInput() const noexcept;
    [[nodiscard]] QQuickItem *horizontalScrollbar() const noexcept;
    [[nodiscard]] QQuickItem *controls() const noexcept;
    [[nodiscard]] QQuickItem *divisionControl() const noexcept;
    [[nodiscard]] QQuickItem *feelControl() const noexcept;
    [[nodiscard]] QQuickItem *toolTip() const noexcept;
    [[nodiscard]] songview::TimeRuler *ruler() const noexcept;
    [[nodiscard]] songview::TrackHeaderModel *headers() const noexcept;
    [[nodiscard]] songview::TimelineInputItem *headersInput() const noexcept;
    [[nodiscard]] EventListView *eventList() const noexcept;
    [[nodiscard]] EditorDrawer *drawer() const noexcept;

  private:
    std::unique_ptr<SongTab> m_tab;
    QPointer<songview::TimelineInputItem> m_rollInput;
    QPointer<songview::TimelineInputItem> m_rulerInput;
    QPointer<QQuickItem> m_horizontalScrollbar;
    QPointer<QQuickItem> m_controls;
    QPointer<QQuickItem> m_divisionControl;
    QPointer<QQuickItem> m_feelControl;
    QPointer<QQuickItem> m_toolTip;
    QPointer<songview::TimeRuler> m_ruler;
    QPointer<songview::TrackHeaderModel> m_headers;
    QPointer<songview::TimelineInputItem> m_headersInput;
    QPointer<EventListView> m_eventList;
    QPointer<EditorDrawer> m_drawer;
};

} // namespace checks::rollcheck::staticcheck
