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
#include "ui/m4asemantics.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

namespace songview {

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
  m_pressLevel.reset();
  m_gestureAxis.reset();
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
  const VelocityAxis axis = displayAxis();
  const double availH = axis.velocityToY(1) - axis.velocityToY(127);

  std::vector<int> tickValues;
  std::vector<int> labelValues;

  const std::vector<SongView::NoteId> detentNotes = detentContextNotes();
  const auto &detentInfo = axis.detents();

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
  const std::vector<SongView::NoteId> &currentSel = m_sv->selection();

  if (!detentInfo) {
    for (int v : tickValues) {
      const double y = axis.velocityToY(v);
      const bool isMajor = (std::find(labelValues.begin(), labelValues.end(),
                                      v) != labelValues.end());
      const int tickLen = isMajor ? 6 : 4;
      p.setPen(
          QPen(themes::color(themes::Role::song_view_secondary_text), 1.0));
      p.drawLine(QLineF(sepX - tickLen, y, sepX, y));
    }

    for (int v : labelValues) {
      const double y = axis.velocityToY(v);
      const QString text = QString::number(v);
      const QRectF textBounds(sepX - 45, y - 8, 37, 16);
      p.setPen(themes::color(themes::Role::song_view_secondary_text));
      p.drawText(textBounds, Qt::AlignRight | Qt::AlignVCenter, text);
    }

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
      const double y = axis.velocityToY(v);
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
  }

  QString detentMessage;
  std::set<int> activeLevels;
  if (detentInfo) {
    const int detentCount = int(detentInfo->levels.size());
    detentMessage = SongView::tr("PSG %1 has %2 levels.")
                        .arg(m4aVoiceTypeName(detentInfo->voiceType))
                        .arg(detentCount);
    for (const SongView::NoteId &id : detentNotes) {
      int velocity = -1;
      if (const auto preview = m_previews.find(id);
          preview != m_previews.end()) {
        velocity = preview->second;
      } else if (const auto sweep = m_sweepPreviews.find(id);
                 sweep != m_sweepPreviews.end()) {
        velocity = sweep->second;
      } else {
        for (const ViewNote &note : m_sv->model().notes) {
          if (note.track != m_sv->selectedTrack() ||
              note.startTick != id.tick || note.key != id.key) {
            continue;
          }
          velocity = note.velocity;
          if (const auto preview = m_sv->noteVelocityPreview(note))
            velocity = *preview;
          break;
        }
      }
      if (velocity > 0) {
        const auto noteDetents = m_sv->velocityDetentsForNotes(
            m_sv->selectedTrack(), {id});
        if (axis.compatibleWith(noteDetents)) {
          const auto level = m_sv->noteVelocityLevel(
              m_sv->selectedTrack(), id.tick, id.key, velocity);
          if (level && *level < detentInfo->levels.size())
            activeLevels.insert(int(*level));
        }
      }
    }
  }
  const QString accessibleDescription =
      detentMessage.isEmpty() ? SongView::tr("Velocity")
                              : SongView::tr("Velocity. %1").arg(detentMessage);
  if (this->accessibleDescription() != accessibleDescription)
    setAccessibleDescription(accessibleDescription);

  if (detentInfo) {
    const int detentCount = int(detentInfo->levels.size());
    const bool staggerLabels = detentCount > 8;
    const qreal labelLeft = 8;
    const qreal labelRight = sepX - 8;
    const qreal columnGap = 4;
    const qreal labelWidth =
        staggerLabels ? (labelRight - labelLeft - columnGap) / 2
                      : labelRight - labelLeft;
    for (int level = 0; level < detentCount; ++level) {
      const double y = axis.levelToY(level);
      const VelocityDetentLevel &description =
          detentInfo->levels[std::size_t(level)];
      const bool active = activeLevels.find(level) != activeLevels.end();
      QColor color =
          themes::color(active ? themes::Role::item_selected_background
                               : themes::Role::song_view_secondary_text);
      p.setPen(QPen(color, active ? 1.5 : 1.0));
      p.drawLine(QLineF(sepX - 6, y, sepX, y));

      const int column = staggerLabels ? level % 2 : 0;
      const qreal labelX =
          staggerLabels && column == 0
              ? labelLeft + labelWidth + columnGap
              : labelLeft;
      const qreal labelY = y - 8;
      const QString label =
          SongView::tr("Volume %1 (%2)")
              .arg(level + 1)
              .arg(description.velocity);
      p.setFont(active ? typography::bold(captionFont) : captionFont);
      p.drawText(QRectF(labelX, labelY, labelWidth, 16),
                 Qt::AlignRight | Qt::AlignVCenter, label);
    }
  }

  if (!m_sv->timeline())
    return;

  p.setClipRect(plot);
  drawGrid(p, m_sv, plot, kGutterW);
  drawOverlays(p, m_sv, plot, kGutterW,
               m_sv->timeSelectionCoversTrack(m_sv->selectedTrack()));
  if (detentInfo) {
    const int detentCount = int(detentInfo->levels.size());
    for (int level = 0; level < detentCount; ++level) {
      const double y = axis.levelToY(level);
      const bool active = activeLevels.find(level) != activeLevels.end();
      QColor color =
          themes::color(active ? themes::Role::item_selected_background
                               : themes::Role::song_view_secondary_text);
      p.setPen(QPen(color, active ? 1.5 : 1.0));
      p.drawLine(QLineF(sepX, y, sepX + 6, y));
    }
  }

  // Watermark title and the active PSG hardware limit.
  const QString title = SongView::tr("Velocity");
  const qreal titleX = plot.left() + 8;
  const QFont titleFont = typography::bold(captionFont);
  p.setFont(titleFont);
  p.setPen(themes::color(themes::Role::song_view_secondary_text));
  p.drawText(QRectF(titleX, plot.top() + 4, 120, 20),
             Qt::AlignLeft | Qt::AlignTop, title);
  if (!detentMessage.isEmpty()) {
    const qreal messageX =
        titleX + QFontMetrics(titleFont).horizontalAdvance(title) + 8;
    p.setFont(captionFont);
    p.drawText(QRectF(messageX, plot.top() + 4,
                      std::max<qreal>(0, plot.right() - messageX), 20),
               Qt::AlignLeft | Qt::AlignTop, detentMessage);
  }
  const QColor nodeColor = SongView::trackColor(m_sv->selectedTrack());
  const QColor stemColor = trackStemColor(m_sv->selectedTrack());
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

    const double y = noteY(note, vel, axis);
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
    m_gestureAxis.emplace(displayAxis());
    m_dragState = DragState::MiddlePan;
    m_panStartPos = event->pos();
    return;
  }

  if (event->button() == Qt::RightButton) {
    if (event->position().x() < kGutterW || !m_sv->document())
      return;
    m_gestureAxis.emplace(displayAxis());
    m_dragState = DragState::PendingBandSelect;
    m_pressPos = event->pos();
    m_lastMousePos = event->position();
    return;
  }

  if (event->button() != Qt::LeftButton)
    return;

  if (event->position().x() < kGutterW)
    return;

  const bool canEdit = (m_sv->document() != nullptr);
  if (!canEdit)
    return;
  m_gestureAxis.emplace(displayAxis());
  const VelocityAxis &axis = *m_gestureAxis;

  const std::vector<SongView::NoteId> hitNotes =
      hitNotesAt(event->position(), axis);

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
      m_pressVel = axis.yToVelocity(event->position().y());

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
      m_pressLevel.reset();
      const SongView::NoteId &firstHit = hitNotes.front();
      for (const ViewNote &note : m_sv->model().notes) {
        if (note.track != m_sv->selectedTrack() ||
            note.startTick != firstHit.tick || note.key != firstHit.key) {
          continue;
        }
        const int velocity =
            m_sv->noteVelocityPreview(note).value_or(note.velocity);
        const auto noteDetents = m_sv->velocityDetentsForNotes(
            note.track, {{note.startTick, note.key}});
        if (axis.compatibleWith(noteDetents)) {
          if (const auto level = m_sv->noteVelocityLevel(
                  m_sv->selectedTrack(), firstHit.tick, firstHit.key,
                  velocity))
            m_pressLevel = int(*level);
        }
        break;
      }
    }
  } else {
    if (canEdit) {
      m_dragState = DragState::FreehandSweep;
      m_pressPos = event->pos();
      m_lastMousePos = event->position();
      m_sweepPreviews.clear();
      m_pressVel = axis.yToVelocity(event->position().y());
      m_pressLevel = axis.mode() == VelocityAxis::Mode::Detented
                         ? std::optional<int>(
                               axis.yToLevel(event->position().y()))
                         : std::nullopt;
      seedSweepAt(event->position(), axis);
      update();
    }
  }
}

void VelocityArea::mouseMoveEvent(QMouseEvent *event) {
  if (m_dragState == DragState::Idle)
    return;
  const VelocityAxis axis = displayAxis();
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
    const bool pixelThresholdReached =
        (event->pos() - m_pressPos).manhattanLength() >=
        QApplication::startDragDistance();
    const bool detentLevelChanged =
        m_pressLevel && axis.mode() == VelocityAxis::Mode::Detented &&
        axis.yToLevel(event->position().y()) != *m_pressLevel;
    if (pixelThresholdReached || detentLevelChanged) {
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
    const auto &detents = axis.detents();
    const bool levelGesture =
        m_pressLevel && axis.mode() == VelocityAxis::Mode::Detented;
    const int levelDelta =
        levelGesture ? axis.yToLevel(event->position().y()) - *m_pressLevel : 0;
    const int velocityDelta =
        axis.yToVelocity(event->position().y()) - m_pressVel;
    m_previews.clear();
    SongDocument *doc = m_sv->document();
    for (const auto &s : m_sv->selection()) {
      DocNote note;
      if (!doc->findNote(m_sv->selectedTrack(), s.tick, s.key, &note))
        continue;

      int origV = note.velocity;
      const auto original = m_origVelocities.find(s);
      if (original != m_origVelocities.end())
        origV = original->second;

      const auto noteDetents = m_sv->velocityDetentsForNotes(
          m_sv->selectedTrack(), {s});
      const bool categorical =
          levelGesture && axis.compatibleWith(noteDetents);
      if (categorical) {
        const auto origLevel = m_sv->noteVelocityLevel(
            m_sv->selectedTrack(), s.tick, s.key, origV);
        if (!origLevel)
          continue;
        const int requestedLevel =
            std::clamp(int(*origLevel) + levelDelta, 0,
                       int(detents->levels.size()) - 1);
        const auto velocity = m_sv->velocityForLevel(
            m_sv->selectedTrack(), s.tick, s.key, uint8_t(requestedLevel));
        if (velocity)
          m_previews[s] = *velocity;
      } else {
        m_previews[s] = m_sv->canonicalNoteVelocity(
            m_sv->selectedTrack(), s.tick, s.key, origV + velocityDelta);
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
    updateSweep(m_lastMousePos, event->position(), axis);
    m_lastMousePos = event->position();
    update();
  }
}

void VelocityArea::mouseReleaseEvent(QMouseEvent *event) {
  const VelocityAxis axis = displayAxis();
  if (m_dragState == DragState::MiddlePan) {
    cancelGesture();
    return;
  }

  if (event->button() == Qt::RightButton &&
      (m_dragState == DragState::PendingBandSelect ||
       m_dragState == DragState::BandSelect)) {
    if (m_dragState == DragState::BandSelect) {
      selectBand(QRectF(QPointF(m_pressPos), event->position()).normalized(),
                 event->modifiers() & Qt::ControlModifier, axis);
    } else {
      std::vector<SongView::NoteId> selection =
          event->modifiers() & Qt::ControlModifier
              ? m_sv->selection()
              : std::vector<SongView::NoteId>();
      for (const SongView::NoteId &hit :
           hitNotesAt(event->position(), axis)) {
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
    SongDocument *doc = m_sv->document();
    if (doc) {
      std::vector<SongDocument::NoteVelocity> edits;
      edits.reserve(m_previews.size());
      for (const auto &[id, velocity] : m_previews) {
        DocNote note;
        if (doc->findNote(m_sv->selectedTrack(), id.tick, id.key, &note) &&
            note.velocity != velocity) {
          edits.push_back({note, uint8_t(velocity)});
        }
      }
      if (!edits.empty())
        doc->setNotesVelocities(edits);
    }
    cancelGesture();
    return;
  }

  if (m_dragState == DragState::FreehandSweep) {
    SongDocument *doc = m_sv->document();
    if (doc && !m_sweepPreviews.empty()) {
      std::vector<SongDocument::NoteVelocity> edits;
      edits.reserve(m_sweepPreviews.size());
      for (const auto &pair : m_sweepPreviews) {
        DocNote note;
        if (doc->findNote(m_sv->selectedTrack(), pair.first.tick,
                          pair.first.key, &note) &&
            note.velocity != pair.second) {
          edits.push_back({note, uint8_t(pair.second)});
        }
      }
      if (!edits.empty())
        doc->setNotesVelocities(edits);
    }
    cancelGesture();
    return;
  }

  cancelGesture();
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


std::vector<SongView::NoteId> VelocityArea::detentContextNotes() const {
  std::vector<SongView::NoteId> notes;
  if (m_dragState == DragState::RelativeDrag ||
      m_dragState == DragState::PendingHandleDrag) {
    notes.reserve(m_origVelocities.size());
    for (const auto &[id, velocity] : m_origVelocities) {
      Q_UNUSED(velocity);
      notes.push_back(id);
    }
    if (!notes.empty())
      return notes;
  }
  if (m_dragState == DragState::FreehandSweep) {
    notes.reserve(m_sweepPreviews.size());
    for (const auto &[id, velocity] : m_sweepPreviews) {
      Q_UNUSED(velocity);
      notes.push_back(id);
    }
    if (!notes.empty())
      return notes;
  }
  if (!m_sv->selection().empty())
    return m_sv->selection();
  return {};
}
VelocityAxis VelocityArea::displayAxis() const {
  if (m_gestureAxis)
    return *m_gestureAxis;
  const std::vector<SongView::NoteId> notes = detentContextNotes();
  const auto detents =
      notes.empty()
          ? std::optional<VelocityDetentInfo>{}
          : m_sv->velocityDetentsForNotes(m_sv->selectedTrack(), notes);
  return VelocityAxis(double(height()), detents);
}

double VelocityArea::noteY(const ViewNote &note, int velocity,
                           const VelocityAxis &axis) const {
  const auto noteDetents = m_sv->velocityDetentsForNotes(
      note.track, {{note.startTick, note.key}});
  if (axis.compatibleWith(noteDetents)) {
    const auto level = m_sv->noteVelocityLevel(
        note.track, note.startTick, note.key, velocity);
    if (level && *level < axis.detents()->levels.size())
      return axis.levelToY(int(*level));
  }
  return axis.velocityToY(velocity);
}

std::vector<SongView::NoteId>
VelocityArea::hitNotesAt(QPointF pos, const VelocityAxis &axis) const {
  const qreal dpr = devicePixelRatioF();
  std::vector<SongView::NoteId> hits;
  for (const ViewNote &note : m_sv->model().notes) {
    if (note.track != m_sv->selectedTrack())
      continue;
    const qreal xStart = m_sv->displayX(double(note.startTick), kGutterW, dpr);
    const qreal xEnd = m_sv->displayX(double(note.endTick), kGutterW, dpr);
    const int velocity = m_sv->noteVelocityPreview(note).value_or(note.velocity);
    const double y = noteY(note, velocity, axis);
    const bool hitDot =
        std::abs(pos.x() - xStart) <= 6.0 && std::abs(pos.y() - y) <= 6.0;
    const bool hitLine = pos.x() >= xStart - 2.0 && pos.x() <= xEnd + 2.0 &&
                         std::abs(pos.y() - y) <= 4.0;
    if (hitDot || hitLine)
      hits.push_back({note.startTick, note.key});
  }
  return hits;
}

void VelocityArea::selectBand(const QRectF &band, bool additive,
                              const VelocityAxis &axis) {
  std::vector<SongView::NoteId> selection =
      additive ? m_sv->selection() : std::vector<SongView::NoteId>();
  const qreal dpr = devicePixelRatioF();
  for (const ViewNote &note : m_sv->model().notes) {
    if (note.track != m_sv->selectedTrack())
      continue;
    const qreal xStart = m_sv->displayX(double(note.startTick), kGutterW, dpr);
    const qreal xEnd = m_sv->displayX(double(note.endTick), kGutterW, dpr);
    const int velocity = m_sv->noteVelocityPreview(note).value_or(note.velocity);
    const double y = noteY(note, velocity, axis);
    const QRectF dotBox(QPointF(xStart, y) - QPointF(4.0, 4.0),
                        QSizeF(8.0, 8.0));
    const QRectF lineBox(xStart, y - 2.0, std::max<qreal>(1.0, xEnd - xStart),
                         4.0);
    const SongView::NoteId id{note.startTick, note.key};
    if ((dotBox.intersects(band) || lineBox.intersects(band)) &&
        std::find(selection.begin(), selection.end(), id) == selection.end())
      selection.push_back(id);
  }
  m_sv->setSelection(std::move(selection));
}

void VelocityArea::seedSweepAt(QPointF pos, const VelocityAxis &axis) {
  const qreal dpr = devicePixelRatioF();
  for (const ViewNote &note : m_sv->model().notes) {
    if (note.track != m_sv->selectedTrack())
      continue;
    const qreal noteX = m_sv->displayX(double(note.startTick), kGutterW, dpr);
    if (std::abs(noteX - pos.x()) > 6.0)
      continue;
    const SongView::NoteId id{note.startTick, note.key};
    const auto noteDetents =
        m_sv->velocityDetentsForNotes(note.track, {id});
    if (axis.compatibleWith(noteDetents) && !noteDetents->levels.empty()) {
      const int requestedLevel = axis.yToLevel(pos.y());
      const auto velocity = m_sv->velocityForLevel(
          note.track, note.startTick, note.key, uint8_t(requestedLevel));
      if (velocity)
        m_sweepPreviews[id] = *velocity;
    } else {
      m_sweepPreviews[id] = m_sv->canonicalNoteVelocity(
          note.track, note.startTick, note.key, axis.yToVelocity(pos.y()));
    }
  }
}

void VelocityArea::updateSweep(QPointF p0, QPointF p1,
                               const VelocityAxis &axis) {
  const qreal dpr = devicePixelRatioF();
  const qreal minX = std::min(p0.x(), p1.x());
  const qreal maxX = std::max(p0.x(), p1.x());
  for (const ViewNote &note : m_sv->model().notes) {
    if (note.track != m_sv->selectedTrack())
      continue;
    const qreal noteX = m_sv->displayX(double(note.startTick), kGutterW, dpr);
    if (noteX < minX || noteX > maxX)
      continue;
    qreal interpY = p1.y();
    if (std::abs(p1.x() - p0.x()) >= 0.001) {
      const qreal t = (noteX - p0.x()) / (p1.x() - p0.x());
      interpY = p0.y() + t * (p1.y() - p0.y());
    }
    const SongView::NoteId id{note.startTick, note.key};
    const auto noteDetents =
        m_sv->velocityDetentsForNotes(note.track, {id});
    if (axis.compatibleWith(noteDetents) && !noteDetents->levels.empty()) {
      const int requestedLevel = axis.yToLevel(interpY);
      const auto velocity = m_sv->velocityForLevel(
          note.track, note.startTick, note.key, uint8_t(requestedLevel));
      if (velocity)
        m_sweepPreviews[id] = *velocity;
    } else {
      m_sweepPreviews[id] = m_sv->canonicalNoteVelocity(
          note.track, note.startTick, note.key, axis.yToVelocity(interpY));
    }
  }
}

} // namespace songview
