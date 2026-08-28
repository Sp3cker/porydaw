#pragma once

#include <QPoint>
#include <QWidget>
#include <map>
#include <optional>
#include <vector>

#include "ui/activity/trackactivity.h"

class QEvent;
class QPushButton;
class QVBoxLayout;
class SongView;

namespace songview {

class TrackHeaderRow;

class TrackHeaderPanel : public QWidget
{
  private:
    struct Geometry {
        int trackHeaderReorderIndicatorHeight;

        static Geometry resolve();
    };

    void refreshGeometry();

  public:
    explicit TrackHeaderPanel(SongView *sv);

    void rebuild();
    void cancelTransientState();
    void syncSelection();
    void beginRename(int track);
    void syncVoices();
    void syncActivity(const TrackActivity &activity, bool playing);
    bool beginRowDrag(int track);
    void dragRowTo(QPoint pos);
    void endRowDrag(bool commit);

  protected:
    bool event(QEvent *event) override;

  private:
    TrackHeaderRow *reconcileRow(int track, std::map<int, TrackHeaderRow *> &previous);
    void retireRows(const std::map<int, TrackHeaderRow *> &rows);
    void synchronizeLayout();
    std::optional<int> reorderTarget(int fromTrack, int dropSlot) const;

    SongView *m_sv;
    Geometry m_geometry;
    QVBoxLayout *m_layout;
    std::map<int, TrackHeaderRow *> m_rowByTrack;
    std::vector<TrackHeaderRow *> m_trackRows;
    QPushButton *m_addButton;
    QWidget *m_indicator = nullptr;
    int m_dragFrom = -1; // dragged engine track; -1 = no drag live
    int m_dropSlot = -1; // insertion slot the indicator marks
};

} // namespace songview
