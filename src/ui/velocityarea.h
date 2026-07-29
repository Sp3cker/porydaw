#pragma once

#include <map>
#include <vector>

#include <QWidget>

#include "ui/songview.h"
#include "ui/velocityaxis.h"

namespace songview {

class VelocityArea : public QWidget {
public:
  explicit VelocityArea(SongView *sv);

  bool gestureActive() const;
  void cancelGesture();
  std::optional<uint8_t> velocityPreview(const ViewNote &note) const;

protected:
  void paintEvent(QPaintEvent *event) override;
  void mousePressEvent(QMouseEvent *event) override;
  void mouseMoveEvent(QMouseEvent *event) override;
  void mouseReleaseEvent(QMouseEvent *event) override;
  void keyPressEvent(QKeyEvent *event) override;
  void keyReleaseEvent(QKeyEvent *event) override;
  void wheelEvent(QWheelEvent *event) override;

private:
  enum class DragState {
    Idle,
    PendingHandleDrag,
    PendingBandSelect,
    RelativeDrag,
    BandSelect,
    FreehandSweep,
    MiddlePan
  };

  struct NoteIdCompare {
    bool operator()(const SongView::NoteId &a,
                    const SongView::NoteId &b) const {
      if (a.tick != b.tick)
        return a.tick < b.tick;
      return a.key < b.key;
    }
  };

  VelocityAxis displayAxis() const;
  double noteY(const ViewNote &note, int velocity,
               const VelocityAxis &axis) const;
  std::vector<SongView::NoteId> hitNotesAt(QPointF pos,
                                           const VelocityAxis &axis) const;
  std::vector<SongView::NoteId>
  bandSelection(const QRectF &band, bool additive,
                const VelocityAxis &axis) const;
  void selectBand(const QRectF &band, bool additive, const VelocityAxis &axis);
  void seedSweepAt(QPointF pos, const VelocityAxis &axis);
  void updateSweep(QPointF p0, QPointF p1, const VelocityAxis &axis);
  std::optional<int> graduationVelocityAt(QPointF pos,
                                          const VelocityAxis &axis) const;
  void setSelectedVelocities(int velocity);
  std::vector<SongView::NoteId> detentContextNotes() const;

  SongView *m_sv = nullptr;
  DragState m_dragState = DragState::Idle;
  QPoint m_panStartPos;
  QPoint m_pressPos;
  QPointF m_lastMousePos;
  int m_pressVel = 0;
  std::optional<int> m_pressLevel;
  std::optional<VelocityAxis> m_gestureAxis;
  bool m_ctrlPress = false;
  std::vector<SongView::NoteId> m_deferredHitNotes;
  std::map<SongView::NoteId, int, NoteIdCompare> m_origVelocities;
  std::map<SongView::NoteId, int, NoteIdCompare> m_previews;
  std::map<SongView::NoteId, int, NoteIdCompare> m_sweepPreviews;
};

} // namespace songview
