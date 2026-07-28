#include "ui/velocityarea.h"

#include <QApplication>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QWheelEvent>

#include <algorithm>
#include <cmath>
#include <set>
#include <vector>

#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

namespace songview {
namespace {

constexpr double kVelocityVerticalInset = 6.0;
constexpr int kMinimumVelocity = 1;
constexpr int kMaximumVelocity = 127;

} // namespace

double velocityToY(int velocity, double height) {
  const double top = kVelocityVerticalInset;
  const double bottom = height - kVelocityVerticalInset;
  return bottom - (velocity - kMinimumVelocity) * (bottom - top) /
                      (kMaximumVelocity - kMinimumVelocity);
}

int yToVelocity(double y, double height) {
  const double top = kVelocityVerticalInset;
  const double bottom = height - kVelocityVerticalInset;
  const double clampedY = std::clamp(y, top, bottom);
  return kMinimumVelocity +
         int(std::round((bottom - clampedY) *
                        (kMaximumVelocity - kMinimumVelocity) /
                        (bottom - top)));
}

VelocityArea::VelocityArea(SongView *sv) : QWidget(nullptr), m_sv(sv) {
  setObjectName(QStringLiteral("velocityArea"));
  setMouseTracking(true);
  setFocusPolicy(Qt::ClickFocus);
}

bool VelocityArea::gestureActive() const {
  return m_dragState != DragState::Idle;
}

void VelocityArea::cancelGesture() {
  m_dragState = DragState::Idle;
  m_ctrlPress = false;
  m_deferredHitNotes.clear();
  m_origVelocities.clear();
  m_previews.clear();
  m_sweepPreviews.clear();
  update();
}

void VelocityArea::paintEvent(QPaintEvent * /*event*/) {
  QPainter p(this);
  p.setRenderHint(QPainter::Antialiasing, false);

  const QRect gutterRect(0, 0, kGutterW, height());
  const QRect plot(kGutterW, 0, width() - kGutterW, height());
  const qreal dpr = devicePixelRatioF();

  p.fillRect(plot,
             themes::color(themes::Role::song_view_piano_roll_background));
  p.fillRect(gutterRect,
             themes::color(themes::Role::song_view_timeline_chrome_background));
  p.setPen(themes::color(themes::Role::song_view_separator));
  p.drawLine(kGutterW - 1, 0, kGutterW - 1, height());

  const QColor iconColor =
      themes::color(themes::Role::song_view_secondary_text);
  p.fillRect(QRectF(10.0, 14.0, 2.5, 5.0), iconColor);
  p.fillRect(QRectF(14.5, 11.0, 2.5, 8.0), iconColor);
  p.fillRect(QRectF(19.0, 8.0, 2.5, 11.0), iconColor);

  const double areaHeight = double(height());
  const double availH = areaHeight - 2.0 * kVelocityVerticalInset;

  std::vector<int> tickValues;
  std::vector<int> labelValues;

  if (availH < 72.0) {
    labelValues = {127, 64, 1};
    tickValues = {127, 96, 64, 32, 1};
  } else if (availH < 144.0) {
    labelValues = (availH >= 100.0) ? std::vector<int>{127, 96, 64, 32, 1}
                                    : std::vector<int>{127, 64, 1};
    tickValues = {127, 112, 96, 80, 64, 48, 32, 16, 1};
  } else if (availH < 288.0) {
    labelValues = {127, 112, 96, 80, 64, 48, 32, 16, 1};
    tickValues = {127, 120, 112, 104, 96, 88, 80, 72, 64,
                  56,  48,  40,  32,  24, 16, 8,  1};
  } else {
    labelValues = {127, 120, 112, 104, 96, 88, 80, 72, 64,
                   56,  48,  40,  32,  24, 16, 8,  1};
    for (int v = 127; v >= 1; v -= 4) {
      tickValues.push_back(v == 3 ? 1 : v);
    }
  }

  const int sepX = kGutterW - 1;
  const QFont captionFont = typography::caption(p.font());
  p.setFont(captionFont);

  for (int v : tickValues) {
    const double y = velocityToY(v, areaHeight);
    const bool isMajor = (std::find(labelValues.begin(), labelValues.end(),
                                    v) != labelValues.end());
    const int tickLen = isMajor ? 6 : 4;
    p.setPen(QPen(themes::color(themes::Role::song_view_secondary_text), 1.0));
    p.drawLine(QLineF(sepX - tickLen, y, sepX, y));
  }

  for (int v : labelValues) {
    const double y = velocityToY(v, areaHeight);
    const QString text = QString::number(v);
    const QRectF textBounds(sepX - 45, y - 8, 37, 16);
    p.setPen(themes::color(themes::Role::song_view_secondary_text));
    p.drawText(textBounds, Qt::AlignRight | Qt::AlignVCenter, text);
  }

  const std::vector<SongView::NoteId> &currentSel = m_sv->selection();
  std::set<int> activeVelocities;
  if (m_dragState == DragState::RelativeDrag) {
    for (const auto &pair : m_previews)
      activeVelocities.insert(pair.second);
  } else if (m_dragState == DragState::FreehandSweep) {
    for (const auto &pair : m_sweepPreviews)
      activeVelocities.insert(pair.second);
  } else if (m_sv->timeline()) {
    for (const ViewNote &note : m_sv->model().notes) {
      if (note.track != m_sv->selectedTrack())
        continue;
      SongView::NoteId id{note.startTick, note.key};
      for (const auto &s : currentSel) {
        if (s.tick == id.tick && s.key == id.key) {
          int vel = note.velocity;
          if (const auto p = m_sv->noteVelocityPreview(note))
            vel = *p;
          activeVelocities.insert(vel);
          break;
        }
      }
    }
  }

  for (int v : activeVelocities) {
    const double y = velocityToY(v, areaHeight);
    const QColor selColor =
        themes::color(themes::Role::item_selected_background);
    p.setPen(QPen(selColor, 1.5));
    p.drawLine(QLineF(sepX - 8, y, sepX, y));
    if (std::find(labelValues.begin(), labelValues.end(), v) ==
        labelValues.end()) {
      const QString text = QString::number(v);
      const QRectF textBounds(sepX - 45, y - 8, 35, 16);
      p.setFont(typography::bold(captionFont));
      p.setPen(selColor);
      p.drawText(textBounds, Qt::AlignRight | Qt::AlignVCenter, text);
    }
  }

  if (!m_sv->timeline())
    return;

  p.setClipRect(plot);
  drawGrid(p, m_sv, plot, kGutterW);
  drawOverlays(p, m_sv, plot, kGutterW,
               m_sv->timeSelectionCoversTrack(m_sv->selectedTrack()));

  // Watermark title in plot background
  p.setFont(typography::bold(p.font()));
  p.setPen(themes::color(themes::Role::song_view_secondary_text));
  p.drawText(QRectF(plot.left() + 8, plot.top() + 4, 120, 20),
             Qt::AlignLeft | Qt::AlignTop, SongView::tr("Velocity"));
  const QColor nodeColor = SongView::trackColor(m_sv->selectedTrack());
  const QColor stemColor = mixTowardOklab(nodeColor, Qt::black, 1.0 / 3.0);
  const QColor selBgColor =
      themes::color(themes::Role::item_selected_background);
  const QColor previewOutlineColor =
      themes::color(themes::Role::song_view_edit_preview_outline);

  struct RenderNote {
    qreal xStart;
    qreal xEnd;
    double y;
    bool isSelected;
    bool hasPreview;
  };

  std::vector<RenderNote> notesToDraw;
  notesToDraw.reserve(m_sv->model().notes.size());

  for (const ViewNote &note : m_sv->model().notes) {
    if (note.track != m_sv->selectedTrack())
      continue;

    const qreal xStart = m_sv->displayX(double(note.startTick), kGutterW, dpr);
    const qreal xEnd = m_sv->displayX(double(note.endTick), kGutterW, dpr);
    if (xEnd < plot.left() - 6 || xStart > plot.right() + 6)
      continue;

    SongView::NoteId noteId{note.startTick, note.key};
    bool isSelected = false;
    for (const auto &s : currentSel) {
      if (s.tick == noteId.tick && s.key == noteId.key) {
        isSelected = true;
        break;
      }
    }

    int vel = note.velocity;
    bool hasPreview = false;

    if (m_dragState == DragState::RelativeDrag) {
      auto it = m_previews.find(noteId);
      if (it != m_previews.end()) {
        vel = it->second;
        hasPreview = true;
      }
    } else if (m_dragState == DragState::FreehandSweep) {
      auto it = m_sweepPreviews.find(noteId);
      if (it != m_sweepPreviews.end()) {
        vel = it->second;
        hasPreview = true;
      }
    } else if (const auto p = m_sv->noteVelocityPreview(note)) {
      vel = *p;
      hasPreview = true;
    }

    const double y = velocityToY(vel, areaHeight);
    notesToDraw.push_back(
        {xStart, std::max(xStart + 1.0, xEnd), y, isSelected, hasPreview});
  }

  p.setClipping(true);
  const qreal stemWidth = 2.0 / dpr;

  // Pass 1: Draw horizontal duration lines (AA off for crisp horizontal
  // strokes)
  p.setRenderHint(QPainter::Antialiasing, false);

  // Unselected lines
  for (const auto &rn : notesToDraw) {
    if (rn.isSelected || rn.hasPreview)
      continue;
    const qreal lx0 = std::max<qreal>(rn.xStart, plot.left());
    const qreal lx1 = std::min<qreal>(rn.xEnd, plot.right());
    if (lx1 >= lx0) {
      p.setPen(QPen(stemColor, stemWidth, Qt::SolidLine, Qt::FlatCap));
      p.drawLine(QLineF(lx0, rn.y, lx1, rn.y));
    }
  }

  // Selected lines
  for (const auto &rn : notesToDraw) {
    if (!rn.isSelected || rn.hasPreview)
      continue;
    const qreal lx0 = std::max<qreal>(rn.xStart, plot.left());
    const qreal lx1 = std::min<qreal>(rn.xEnd, plot.right());
    if (lx1 >= lx0) {
      p.setPen(QPen(selBgColor, stemWidth + (1.0 / dpr), Qt::SolidLine,
                    Qt::FlatCap));
      p.drawLine(QLineF(lx0, rn.y, lx1, rn.y));
    }
  }

  // Preview lines
  for (const auto &rn : notesToDraw) {
    if (!rn.hasPreview)
      continue;
    const qreal lx0 = std::max<qreal>(rn.xStart, plot.left());
    const qreal lx1 = std::min<qreal>(rn.xEnd, plot.right());
    if (lx1 >= lx0) {
      p.setPen(
          QPen(previewOutlineColor, stemWidth, Qt::SolidLine, Qt::FlatCap));
      p.drawLine(QLineF(lx0, rn.y, lx1, rn.y));
    }
  }

  // Pass 2: Draw circular node dots at (xStart, y) (AA on)
  p.setRenderHint(QPainter::Antialiasing, true);

  // Unselected nodes
  for (const auto &rn : notesToDraw) {
    if (rn.isSelected || rn.hasPreview)
      continue;
    if (rn.xStart >= plot.left() - 6 && rn.xStart <= plot.right() + 6) {
      p.setPen(QPen(Qt::black, 1.0));
      p.setBrush(nodeColor);
      p.drawEllipse(QPointF(rn.xStart, rn.y), 3.5, 3.5);
    }
  }

  // Selected nodes
  for (const auto &rn : notesToDraw) {
    if (!rn.isSelected || rn.hasPreview)
      continue;
    if (rn.xStart >= plot.left() - 6 && rn.xStart <= plot.right() + 6) {
      p.setPen(QPen(selBgColor, 2.0));
      p.setBrush(Qt::NoBrush);
      p.drawEllipse(QPointF(rn.xStart, rn.y), 4.5, 4.5);
      p.setPen(QPen(Qt::black, 1.0));
      p.setBrush(nodeColor);
      p.drawEllipse(QPointF(rn.xStart, rn.y), 3.5, 3.5);
    }
  }

  // Preview nodes
  for (const auto &rn : notesToDraw) {
    if (!rn.hasPreview)
      continue;
    if (rn.xStart >= plot.left() - 6 && rn.xStart <= plot.right() + 6) {
      p.setPen(QPen(previewOutlineColor, 1.5));
      p.setBrush(previewOutlineColor);
      p.drawEllipse(QPointF(rn.xStart, rn.y), 3.0, 3.0);
    }
  }

  p.setRenderHint(QPainter::Antialiasing, false);

  if (m_dragState == DragState::BandSelect) {
    const QRectF band =
        QRectF(QPointF(m_pressPos), m_lastMousePos).normalized();
    const QColor color = themes::color(themes::Role::song_view_selection_edge);
    p.setPen(QPen(color, 1, Qt::DashLine));
    p.setBrush(Qt::NoBrush);
    p.drawRect(band);
  }

  p.setClipping(false);
}

void VelocityArea::mousePressEvent(QMouseEvent *event) {
  if (!m_sv->timeline())
    return;

  if (event->button() == Qt::MiddleButton) {
    m_dragState = DragState::MiddlePan;
    m_panStartPos = event->pos();
    return;
  }

  if (event->button() == Qt::RightButton) {
    if (event->position().x() < kGutterW || !m_sv->document())
      return;
    m_dragState = DragState::PendingBandSelect;
    m_pressPos = event->pos();
    m_lastMousePos = event->position();
    return;
  }

  if (event->button() != Qt::LeftButton)
    return;

  if (event->position().x() < kGutterW)
    return;

  const std::vector<SongView::NoteId> hitNotes = hitNotesAt(event->position());

  const bool canEdit = (m_sv->document() != nullptr);
  if (!canEdit)
    return;

  if (!hitNotes.empty()) {
    const auto &currentSel = m_sv->selection();
    bool allHitSelected = true;
    for (const auto &hit : hitNotes) {
      bool found = false;
      for (const auto &s : currentSel) {
        if (s.tick == hit.tick && s.key == hit.key) {
          found = true;
          break;
        }
      }
      if (!found) {
        allHitSelected = false;
        break;
      }
    }

    const bool isCtrl = (event->modifiers() & Qt::ControlModifier) != 0;
    if (isCtrl) {
      m_ctrlPress = true;
      m_deferredHitNotes = hitNotes;
    } else {
      m_ctrlPress = false;
      m_deferredHitNotes = hitNotes;
      if (!allHitSelected) {
        m_sv->setSelection(hitNotes);
      }
    }

    if (canEdit) {
      m_dragState = DragState::PendingHandleDrag;
      m_pressPos = event->pos();
      m_pressVel = valueAtY(event->position().y());

      m_origVelocities.clear();
      SongDocument *doc = m_sv->document();
      for (const auto &s : m_sv->selection()) {
        DocNote note;
        if (doc->findNote(m_sv->selectedTrack(), s.tick, s.key, &note)) {
          m_origVelocities[s] = note.velocity;
        }
      }
      if (isCtrl) {
        for (const auto &hit : hitNotes) {
          DocNote note;
          if (doc->findNote(m_sv->selectedTrack(), hit.tick, hit.key, &note)) {
            m_origVelocities[hit] = note.velocity;
          }
        }
      }
    }
  } else {
    if (canEdit) {
      m_dragState = DragState::FreehandSweep;
      m_pressPos = event->pos();
      m_lastMousePos = event->position();
      m_sweepPreviews.clear();
      seedSweepAt(event->position());
      update();
    }
  }
}

void VelocityArea::mouseMoveEvent(QMouseEvent *event) {
  if (m_dragState == DragState::MiddlePan) {
    const QPoint delta = event->pos() - m_panStartPos;
    m_sv->scrollByPx(-delta.x());
    m_panStartPos = event->pos();
    return;
  }

  if (m_dragState == DragState::PendingBandSelect &&
      (event->pos() - m_pressPos).manhattanLength() >=
          QApplication::startDragDistance()) {
    m_dragState = DragState::BandSelect;
  }
  if (m_dragState == DragState::BandSelect) {
    m_lastMousePos = event->position();
    update();
    return;
  }

  if (m_dragState == DragState::PendingHandleDrag) {
    if ((event->pos() - m_pressPos).manhattanLength() >=
        QApplication::startDragDistance()) {
      if (m_ctrlPress) {
        auto newSel = m_sv->selection();
        for (const auto &hit : m_deferredHitNotes) {
          bool found = false;
          for (const auto &s : newSel) {
            if (s.tick == hit.tick && s.key == hit.key) {
              found = true;
              break;
            }
          }
          if (!found)
            newSel.push_back(hit);
        }
        m_sv->setSelection(newSel);
        m_ctrlPress = false;
      }
      m_dragState = DragState::RelativeDrag;
    }
  }

  if (m_dragState == DragState::RelativeDrag) {
    const int currentVel = valueAtY(event->position().y());
    const int delta = currentVel - m_pressVel;
    m_previews.clear();
    SongDocument *doc = m_sv->document();
    for (const auto &s : m_sv->selection()) {
      DocNote note;
      if (doc->findNote(m_sv->selectedTrack(), s.tick, s.key, &note)) {
        int origV = note.velocity;
        auto it = m_origVelocities.find(s);
        if (it != m_origVelocities.end())
          origV = it->second;
        int newV = std::clamp(origV + delta, 1, 127);
        m_previews[s] = newV;
      }
    }
    if (!m_deferredHitNotes.empty()) {
      const auto &hit = m_deferredHitNotes.front();
      const auto preview = m_previews.find(hit);
      if (preview != m_previews.end()) {
        for (const ViewNote &note : m_sv->model().notes) {
          if (note.track != m_sv->selectedTrack() ||
              note.startTick != hit.tick || note.key != hit.key)
            continue;
          ViewNote announced = note;
          announced.velocity = uint8_t(preview->second);
          m_sv->announceNote(announced);
          break;
        }
      }
    }
    update();
  } else if (m_dragState == DragState::FreehandSweep) {
    updateSweep(m_lastMousePos, event->position());
    m_lastMousePos = event->position();
    update();
  }
}

void VelocityArea::mouseReleaseEvent(QMouseEvent *event) {
  if (m_dragState == DragState::MiddlePan) {
    m_dragState = DragState::Idle;
    return;
  }

  if (event->button() == Qt::RightButton &&
      (m_dragState == DragState::PendingBandSelect ||
       m_dragState == DragState::BandSelect)) {
    if (m_dragState == DragState::BandSelect) {
      selectBand(QRectF(QPointF(m_pressPos), event->position()).normalized(),
                 event->modifiers() & Qt::ControlModifier);
    } else {
      std::vector<SongView::NoteId> selection =
          event->modifiers() & Qt::ControlModifier
              ? m_sv->selection()
              : std::vector<SongView::NoteId>();
      for (const SongView::NoteId &hit : hitNotesAt(event->position())) {
        const auto found = std::find(selection.begin(), selection.end(), hit);
        if (found != selection.end())
          selection.erase(found);
        else
          selection.push_back(hit);
      }
      m_sv->setSelection(std::move(selection));
    }
    cancelGesture();
    return;
  }

  if (m_dragState == DragState::PendingHandleDrag) {
    if (m_ctrlPress) {
      auto newSel = m_sv->selection();
      for (const auto &hit : m_deferredHitNotes) {
        auto it = std::find_if(newSel.begin(), newSel.end(),
                               [&](const SongView::NoteId &s) {
                                 return s.tick == hit.tick && s.key == hit.key;
                               });
        if (it != newSel.end()) {
          newSel.erase(it);
        } else {
          newSel.push_back(hit);
        }
      }
      m_sv->setSelection(newSel);
    }
    cancelGesture();
    return;
  }

  if (m_dragState == DragState::RelativeDrag) {
    const int currentVel = valueAtY(event->position().y());
    const int delta = currentVel - m_pressVel;
    if (delta != 0) {
      std::vector<DocNote> notes = selectedDocumentNotes(*m_sv);
      if (!notes.empty() && m_sv->document()) {
        m_sv->document()->nudgeNotesVelocity(notes, delta);
      }
    }
    cancelGesture();
    return;
  }

  if (m_dragState == DragState::FreehandSweep) {
    SongDocument *doc = m_sv->document();
    if (doc && !m_sweepPreviews.empty()) {
      std::vector<SongDocument::NoteVelocity> edits;
      for (const auto &pair : m_sweepPreviews) {
        DocNote note;
        if (doc->findNote(m_sv->selectedTrack(), pair.first.tick,
                          pair.first.key, &note)) {
          edits.push_back({note, uint8_t(pair.second)});
        }
      }
      if (!edits.empty()) {
        doc->setNotesVelocities(edits);
      }
    }
    cancelGesture();
    return;
  }

  m_dragState = DragState::Idle;
}

void VelocityArea::keyPressEvent(QKeyEvent *event) {
  if (m_sv->handleEditKey(event))
    return;
  if (event->key() == Qt::Key_Escape) {
    cancelGesture();
    event->accept();
    return;
  }
  QWidget::keyPressEvent(event);
}

void VelocityArea::keyReleaseEvent(QKeyEvent *event) {
  if (!event->isAutoRepeat())
    m_sv->releaseEditKeyAudition();
  QWidget::keyReleaseEvent(event);
}

void VelocityArea::wheelEvent(QWheelEvent *event) {
  const QPoint delta = wheelDelta(event);
  const int d = delta.y() ? delta.y() : delta.x();
  if (event->modifiers() & Qt::ShiftModifier) {
    m_sv->scrollByPx(-d);
  } else if (delta.x() && !delta.y()) {
    m_sv->scrollByPx(-delta.x());
  } else if (event->position().x() < kGutterW) {
    event->ignore();
    return;
  } else {
    const double zoomDelta = wheelAngleUnits(event);
    if (zoomDelta != 0.0)
      m_sv->zoomAroundContentX(std::pow(1.0015, zoomDelta),
                               event->position().x() - kGutterW);
  }
  event->accept();
}

int VelocityArea::valueAtY(double y) const { return yToVelocity(y, height()); }

std::vector<SongView::NoteId> VelocityArea::hitNotesAt(QPointF pos) const {
  const qreal dpr = devicePixelRatioF();
  std::vector<SongView::NoteId> hits;
  for (const ViewNote &note : m_sv->model().notes) {
    if (note.track != m_sv->selectedTrack())
      continue;
    const qreal xStart = m_sv->displayX(double(note.startTick), kGutterW, dpr);
    const qreal xEnd = m_sv->displayX(double(note.endTick), kGutterW, dpr);
    const double y = velocityToY(note.velocity, height());
    const bool hitDot =
        (std::abs(pos.x() - xStart) <= 6.0 && std::abs(pos.y() - y) <= 6.0);
    const bool hitLine = (pos.x() >= xStart - 2.0 && pos.x() <= xEnd + 2.0 &&
                          std::abs(pos.y() - y) <= 4.0);
    if (hitDot || hitLine) {
      hits.push_back({note.startTick, note.key});
    }
  }
  return hits;
}

void VelocityArea::selectBand(const QRectF &band, bool additive) {
  std::vector<SongView::NoteId> selection =
      additive ? m_sv->selection() : std::vector<SongView::NoteId>();
  const qreal dpr = devicePixelRatioF();
  for (const ViewNote &note : m_sv->model().notes) {
    if (note.track != m_sv->selectedTrack())
      continue;
    const qreal xStart = m_sv->displayX(double(note.startTick), kGutterW, dpr);
    const qreal xEnd = m_sv->displayX(double(note.endTick), kGutterW, dpr);
    const double y = velocityToY(note.velocity, height());
    const QRectF dotBox(QPointF(xStart, y) - QPointF(4.0, 4.0),
                        QSizeF(8.0, 8.0));
    const QRectF lineBox(xStart, y - 2.0, std::max<qreal>(1.0, xEnd - xStart),
                         4.0);
    const SongView::NoteId id{note.startTick, note.key};
    if ((dotBox.intersects(band) || lineBox.intersects(band)) &&
        std::find(selection.begin(), selection.end(), id) == selection.end()) {
      selection.push_back(id);
    }
  }
  m_sv->setSelection(std::move(selection));
}

void VelocityArea::seedSweepAt(QPointF pos) {
  const qreal dpr = devicePixelRatioF();
  const int vel = valueAtY(pos.y());
  for (const ViewNote &note : m_sv->model().notes) {
    if (note.track != m_sv->selectedTrack())
      continue;
    const qreal noteX = m_sv->displayX(double(note.startTick), kGutterW, dpr);
    if (std::abs(noteX - pos.x()) <= 6.0) {
      m_sweepPreviews[{note.startTick, note.key}] = vel;
    }
  }
}

void VelocityArea::updateSweep(QPointF p0, QPointF p1) {
  const qreal dpr = devicePixelRatioF();
  const qreal minX = std::min(p0.x(), p1.x());
  const qreal maxX = std::max(p0.x(), p1.x());

  for (const ViewNote &note : m_sv->model().notes) {
    if (note.track != m_sv->selectedTrack())
      continue;
    const qreal noteX = m_sv->displayX(double(note.startTick), kGutterW, dpr);
    if (noteX >= minX && noteX <= maxX) {
      qreal interpY = p1.y();
      if (std::abs(p1.x() - p0.x()) >= 0.001) {
        qreal t = (noteX - p0.x()) / (p1.x() - p0.x());
        interpY = p0.y() + t * (p1.y() - p0.y());
      }
      int vel = valueAtY(interpY);
      m_sweepPreviews[{note.startTick, note.key}] = vel;
    }
  }
}

} // namespace songview
