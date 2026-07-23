#include "ui/songviewpianoroll.hpp"
#include "ui/songviewpianorollinternal.hpp"

#include <QAction>
#include <QApplication>
#include <QKeyEvent>
#include <QKeySequence>
#include <QMouseEvent>
#include <QPainter>
#include <QWheelEvent>

#include <algorithm>
#include <climits>
#include <cmath>
#include <memory>
#include <utility>

#include "core/mid2agbtables.h"
#include "core/songdocument.h"
#include "ui/songview.h"

namespace songview {

class PianoRoll::State final : public QWidget
{
public:
    State(PianoRoll *roll, SongView *songView)
        : QWidget(roll), m_sv(songView)
    {
        setObjectName(QStringLiteral("pianoRoll")); // findChild for tests
        roll->setMinimumHeight(120);
        roll->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
        setMouseTracking(true);
        setFocusPolicy(Qt::ClickFocus);
        m_commands = std::make_unique<PianoRollCommands>(
            this, m_sv, [this](QPoint globalPosition) { retargetNoteMenu(globalPosition); },
            [this](uint8_t velocity) { m_lastVelocity = velocity; });
    }

    // A mouse gesture is live (pan, note move/resize/velocity/draw, band or
    // time-selection sweep, a still-undecided press, keyboard gliss); the
    // playhead follow-scroll pauses while one runs so the view doesn't jump
    // under the cursor.
    bool gestureActive() const
    {
        return m_panning || m_drag != Drag::None || m_leftPress || m_rightPress
            || m_kbdKey >= 0;
    }
    bool event(QEvent *event) override
    {
        if (event->type() != QEvent::Type(QEvent::User + 1))
            return QWidget::event(event);
        const auto *audition =
            static_cast<const PianoRollShortcutAuditionEvent *>(event);
        auditionKey(audition->key, audition->velocity);
        return true;
    }


public:
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        p.fillRect(rect(), palette().color(QPalette::Base));
        if (!m_sv->timeline()) {
            piano_roll_rendering::drawKeyboard(p, *m_sv, height(), m_soundingKey);
            return;
        }

        const int keyH = m_sv->keyHeight();
        const QRect grid(kKeyboardW, 0, width() - kKeyboardW, height());
        p.setClipRect(grid);

        // Pitch row shading + octave boundaries.
        QColor blackRow = palette().color(QPalette::AlternateBase);
        if (blackRow == palette().color(QPalette::Base))
            blackRow = palette().color(QPalette::Window);
        const QColor octaveLine = palette().color(QPalette::Mid);
        for (int key = 0; key < 128; key++) {
            const int y = piano_roll_rendering::keyToY(*m_sv, key);
            if (y + keyH < 0 || y > height())
                continue;
            if (piano_roll_rendering::isBlackKey(key))
                p.fillRect(QRect(grid.left(), y, grid.width(), keyH), blackRow);
            if (key % 12 == 0) { // octave line under every C
                p.setPen(octaveLine);
                p.drawLine(grid.left(), y + keyH, grid.right(), y + keyH);
            }
        }

        m_sv->drawGrid(p, grid, kKeyboardW);

        // Notes: ghost pass (unselected tracks), then the selected track.
        const SongViewModel &model = m_sv->model();
        const int selected = m_sv->selectedTrack();
        drawNotes(p, model, selected, true);
        drawNotes(p, model, selected, false);
        drawDragPreview(p, model, selected);

        if (m_drag == Drag::Band) {
            const QRect band = QRect(m_pressPos, m_curPos).normalized();
            QColor c = palette().color(QPalette::Highlight);
            p.setPen(QPen(c, 1, Qt::DashLine));
            c.setAlpha(30);
            p.fillRect(band, c);
            p.drawRect(band);
        }

        piano_roll_rendering::drawOverlays(
            p, *m_sv, grid, kKeyboardW,
            m_sv->timeSelectionCoversTrack(m_sv->selectedTrack()));

        p.setClipping(false);
        piano_roll_rendering::drawKeyboard(p, *m_sv, height(), m_soundingKey);
    }

    void wheelEvent(QWheelEvent *event) override
    {
        // Reaper-style bindings: plain wheel over the notes area zooms the
        // timeline, over the keyboard column it scrolls the note range.
        // Ctrl+wheel zooms the key height (the track-height analog); Shift
        // (or a trackpad's horizontal delta) scrolls horizontally.
        const QPoint delta = event->angleDelta();
        const int d = delta.y() ? delta.y() : delta.x();
        if (event->modifiers() & Qt::ControlModifier)
            m_sv->zoomKeyHeight(d, int(event->position().y()));
        else if (event->modifiers() & Qt::ShiftModifier)
            m_sv->scrollByPx(-d);
        else if (delta.x() && !delta.y())
            m_sv->scrollByPx(-delta.x());
        else if (event->position().x() < kKeyboardW)
            m_sv->scrollRollBy(-delta.y() / 2);
        else
            m_sv->zoomAroundContentX(std::pow(1.0015, delta.y()),
                                     int(event->position().x()) - kKeyboardW);
        event->accept();
    }

    void mousePressEvent(QMouseEvent *event) override
    {
        setFocus();
        if (!m_sv->timeline())
            return;

        if (event->button() == Qt::MiddleButton) {
            // Reaper-style pan: drag scrolls the roll on both axes.
            m_panning = true;
            m_panPos = event->globalPosition().toPoint();
            setCursor(Qt::ClosedHandCursor);
            return;
        }

        // Keyboard column: audition the clicked key on the selected track.
        if (event->pos().x() < kKeyboardW) {
            if (event->button() == Qt::LeftButton) {
                m_kbdKey = piano_roll_rendering::yToKey(*m_sv, event->pos().y());
                auditionKey(m_kbdKey, 100);
            }
            return;
        }

        SongDocument *doc = m_sv->document();
        const ViewNote *hit = doc ? hitNote(event->pos()) : nullptr;

        if (event->button() == Qt::RightButton) {
            // Deferred: a drag from here rubber-band-selects (with Shift, it
            // sweeps a full-height time selection instead); releasing in
            // place context-acts on the pressed note (or on the time
            // selection under the click, or clears the selections over empty
            // space). Resolved in mouseReleaseEvent.
            if (!doc)
                return;
            m_pressPos = m_curPos = event->pos();
            m_rightPress = true;
            m_rightShift = event->modifiers() & Qt::ShiftModifier;
            m_rightAnchorTick =
                m_sv->snapTick(m_sv->tickAtContentX(event->pos().x() - kKeyboardW));
            m_rightHit = hit != nullptr;
            if (hit)
                m_rightHitId = {hit->startTick, hit->key};
            return;
        }
        if (event->button() != Qt::LeftButton)
            return;

        m_pressPos = m_curPos = event->pos();
        m_pressTick = m_sv->tickAtContentX(event->pos().x() - kKeyboardW);
        m_pressKey = piano_roll_rendering::yToKey(*m_sv, event->pos().y());
        m_dTick = 0;
        m_dKey = 0;
        m_dDur = 0;
        m_dVel = 0;

        if (hit) {
            std::vector<SongView::NoteId> ids = m_sv->selection();
            const SongView::NoteId id{hit->startTick, hit->key};
            const bool ctrlHeld = (event->modifiers() & Qt::ControlModifier) != 0;
            if (ctrlHeld) {
                if (!m_sv->isSelected(*hit))
                    m_sv->setSelection({id});
            } else if (!m_sv->isSelected(*hit)) {
                m_sv->setSelection({id});
            }
            m_sv->announceNote(*hit);
            // Reaper-style velocity latch: touching a note makes its velocity
            // the default for the next drawn note.
            m_lastVelocity = hit->velocity;
            if (ctrlHeld) {
                m_drag = Drag::Velocity;
                m_velAnchor = *hit;
                m_velAudEff = mid2agbEffectiveVelocity(hit->velocity);
            } else if (piano_roll_rendering::nearRightEdge(*m_sv, *hit, event->pos())) {
                m_drag = Drag::Resize;
                m_gripTick = hit->endTick;
                m_gripOpposite = hit->startTick;
            } else if (piano_roll_rendering::nearLeftEdge(*m_sv, *hit, event->pos())) {
                m_drag = Drag::ResizeLeft;
                m_gripTick = hit->startTick;
                m_gripOpposite = hit->endTick;
            } else if (piano_roll_rendering::nearVelocityHandle(*m_sv, *hit,
                                                                 event->pos())) {
                m_drag = Drag::Velocity;
                m_velAnchor = *hit;
                m_velAudEff = mid2agbEffectiveVelocity(hit->velocity);
            } else {
                m_drag = Drag::Move;
            }
            // Sound the grabbed note so a press gives the same pitch feedback
            // a drag already does.
            auditionKey(hit->key, hit->velocity);
            m_auditioned = true;
        } else if (doc) {
            // Empty space: deferred, Reaper-style. A horizontal drag from
            // here draws a note (resolved in mouseMoveEvent); releasing in
            // place parks the edit cursor at the click instead. A
            // double-click draws immediately (mouseDoubleClickEvent).
            m_leftPress = true;
            m_sv->clearSelection();
        } else {
            // Read-only (no document): park the edit cursor at the click,
            // like the ruler; playback follows when running.
            m_sv->commitEditCursor(m_sv->snapTick(m_pressTick));
        }
        update();
    }

    void mouseDoubleClickEvent(QMouseEvent *event) override
    {
        // Double-click on empty space drops a grid-sized note (committed on
        // release; dragging before release still sizes it); on a note it
        // deletes that note. Anywhere else a fast click-click behaves as two
        // presses — Qt replaces the second press with this event.
        SongDocument *doc = m_sv->document();
        if (event->button() == Qt::LeftButton && doc
            && event->pos().x() >= kKeyboardW) {
            setFocus();
            if (const ViewNote *hit = hitNote(event->pos())) {
                DocNote note;
                if (doc->findNote(m_sv->selectedTrack(), hit->startTick, hit->key,
                                  &note)) {
                    doc->deleteNotes({note});
                    m_sv->clearSelection();
                }
                return;
            }
            m_pressPos = m_curPos = event->pos();
            m_pressTick = m_sv->tickAtContentX(event->pos().x() - kKeyboardW);
            m_pressKey = piano_roll_rendering::yToKey(*m_sv, event->pos().y());
            beginDraw();
            return;
        }
        mousePressEvent(event);
    }

    void mouseMoveEvent(QMouseEvent *event) override
    {
        if (m_panning) {
            const QPoint pos = event->globalPosition().toPoint();
            const QPoint d = pos - m_panPos;
            m_panPos = pos;
            m_sv->scrollByPx(-d.x());
            m_sv->scrollRollBy(-d.y());
            return;
        }
        if (m_kbdKey >= 0) {
            // Keyboard column: dragging glisses — the sounding key follows
            // the cursor (the engine's mono preview releases the old key).
            const int key = piano_roll_rendering::yToKey(*m_sv, event->pos().y());
            if (key != m_kbdKey) {
                m_kbdKey = key;
                auditionKey(m_kbdKey, 100);
            }
            return;
        }
        m_curPos = event->pos();
        if (m_rightPress && m_drag == Drag::None
            && (event->pos() - m_pressPos).manhattanLength()
                >= QApplication::startDragDistance()) {
            m_drag = m_rightShift ? Drag::TimeSel : Drag::Band;
            m_bandAud.clear();
        }
        if (m_leftPress && m_drag == Drag::None
            && std::abs(event->pos().x() - m_pressPos.x())
                >= QApplication::startDragDistance()) {
            // The deferred empty-space press turns out to be a draw gesture.
            beginDraw();
        }
        if (m_drag == Drag::None) {
            updateHoverCursor(event->modifiers());
            return;
        }

        const double tick = m_sv->tickAtContentX(event->pos().x() - kKeyboardW);
        const int64_t grid =
            int64_t(m_sv->gridTicksAt(uint64_t(std::max(0.0, m_pressTick))));
        const int64_t rawD = int64_t(std::llround(tick - m_pressTick));
        const int64_t snappedD =
            m_sv->snapToGrid()
                ? (rawD >= 0 ? rawD + grid / 2 : rawD - grid / 2) / grid * grid
                : rawD;

        if (m_drag == Drag::Move) {
            const int dKey = piano_roll_rendering::yToKey(*m_sv, event->pos().y())
                             - m_pressKey;
            if (snappedD != m_dTick || dKey != m_dKey) {
                m_dTick = snappedD;
                if (dKey != m_dKey) {
                    m_dKey = dKey;
                    // Audition the new pitch while dragging vertically.
                    const std::vector<DocNote> notes = m_commands->selectedNotes();
                    if (!notes.empty()) {
                        const int key = std::clamp(int(notes.front().key) + m_dKey, 0, 127);
                        auditionKey(key, notes.front().velocity);
                        m_auditioned = true;
                    }
                }
                update();
            }
        } else if (m_drag == Drag::Resize || m_drag == Drag::ResizeLeft) {
            // The dragged edge snaps to the ruler's absolute grid lines,
            // not to grid-sized offsets from its own (possibly off-grid)
            // position. The original edge stays a candidate so a barely
            // moved grab is a no-op and the starting length remains
            // reachable mid-drag.
            const double desired = double(m_gripTick) + (tick - m_pressTick);
            // A snapped drag never collapses the grabbed note: the dragged
            // edge stops at the first grid line strictly inside the
            // opposite edge, however far the cursor overshoots. (The
            // document's own 1-tick floor stays as a backstop for the
            // other notes of a multi-selection.)
            const uint64_t snapped =
                m_drag == Drag::Resize
                    ? std::max(m_sv->snapTick(desired),
                               m_sv->snapTickUp(double(m_gripOpposite) + 1.0))
                    : std::min(m_sv->snapTick(desired),
                               m_sv->snapTickDown(double(m_gripOpposite) - 1.0));
            const int64_t d =
                std::abs(desired - double(m_gripTick)) < std::abs(desired - snapped)
                    ? 0
                    : int64_t(snapped) - int64_t(m_gripTick);
            int64_t &target = m_drag == Drag::Resize ? m_dDur : m_dTick;
            if (d != target) {
                target = d;
                update();
            }
        } else if (m_drag == Drag::Velocity) {
            const int dv = m_pressPos.y() - event->pos().y(); // up = louder
            if (dv != m_dVel) {
                m_dVel = dv;
                const int vel = std::clamp(int(m_velAnchor.velocity) + m_dVel, 1, 127);
                ViewNote preview = m_velAnchor;
                preview.velocity = uint8_t(vel);
                m_sv->announceNote(preview);
                // Re-audition whenever the effective (played) velocity moves
                // to the next mid2agb step.
                const int eff = mid2agbEffectiveVelocity(vel);
                if (eff != m_velAudEff) {
                    m_velAudEff = eff;
                    auditionKey(m_velAnchor.key, vel);
                    m_auditioned = true;
                }
                update();
            }
        } else if (m_drag == Drag::Draw) {
            // The edge under the cursor follows it: right of the anchor cell
            // the end grows (rounded up to the next grid line, never shorter
            // than one cell); left of it the start moves back (snapped down)
            // with the end pinned to the anchor cell. The key follows the
            // cursor vertically — a slight misclick on mouse-down is fixable
            // mid-gesture, with the new pitch auditioned.
            const int64_t cur = int64_t(std::llround(tick));
            const int64_t anchor = int64_t(m_drawAnchor);
            uint64_t start = m_drawAnchor;
            int64_t dur;
            if (cur >= anchor) {
                dur = std::max(grid, (cur - anchor + grid - 1) / grid * grid);
            } else {
                start = uint64_t(std::floor(std::max(0.0, tick) / double(grid))
                                 * double(grid));
                dur = anchor + grid - int64_t(start);
            }
            const int key = piano_roll_rendering::yToKey(*m_sv, event->pos().y());
            if (start != m_drawTick || dur != m_drawDur || key != m_drawKey) {
                m_drawTick = start;
                m_drawDur = dur;
                if (key != m_drawKey) {
                    m_drawKey = key;
                    auditionKey(m_drawKey, m_lastVelocity);
                    m_auditioned = true;
                }
                update();
            }
        } else if (m_drag == Drag::TimeSel) {
            // Full-height sweep: a time selection over the selected tracks
            // (notes and automation together), same scope as a ruler sweep.
            const uint64_t t = m_sv->snapTick(tick);
            SongView::TimeSelection sel;
            sel.startTick = std::min(m_rightAnchorTick, t);
            sel.endTick = std::max(m_rightAnchorTick, t);
            m_sv->setTimeSelection(sel);
        } else if (m_drag == Drag::Band) {
            auditionBandEntrants(QRect(m_pressPos, m_curPos).normalized());
            update();
        }
    }

    void mouseReleaseEvent(QMouseEvent *event) override
    {
        if (event->button() == Qt::MiddleButton && m_panning) {
            m_panning = false;
            setCursor(Qt::ArrowCursor);
            return;
        }
        if (m_kbdKey >= 0) {
            auditionKey(m_kbdKey, 0);
            m_kbdKey = -1;
        }
        if (m_auditioned) {
            auditionKey(0, 0);
            m_auditioned = false;
        }
        SongDocument *doc = m_sv->document();
        if (event->button() == Qt::RightButton && m_rightPress) {
            const Drag drag = m_drag;
            m_rightPress = false;
            m_drag = Drag::None;
            if (drag == Drag::TimeSel) {
                if (m_sv->timeSelection().active())
                    m_sv->announceTimeSelection();
                else
                    m_sv->clearTimeSelection();
            } else if (drag == Drag::Band) {
                stopBandAuditions();
                selectBand(QRect(m_pressPos, m_curPos).normalized(),
                           event->modifiers() & Qt::ControlModifier);
            } else if (doc && m_rightHit) {
                const std::vector<SongView::NoteId> &sel = m_sv->selection();
                if (std::find(sel.begin(), sel.end(), m_rightHitId) == sel.end())
                    m_sv->setSelection({m_rightHitId});
                m_commands->showMenuAt(event->globalPosition().toPoint());
            } else if (insideTimeSelection(event->pos())) {
                m_sv->showTimeSelectionContextMenu(event->globalPosition().toPoint());
            } else {
                m_sv->clearSelection();
                m_sv->clearTimeSelection();
            }
            update();
            return;
        }
        if (event->button() == Qt::LeftButton && m_leftPress) {
            m_leftPress = false;
            if (m_drag == Drag::None) {
                // Click without a drag: park the edit cursor at the click,
                // like the ruler; playback follows when running.
                m_sv->commitEditCursor(m_sv->snapTick(m_pressTick));
                update();
                return;
            }
        }
        if (event->button() != Qt::LeftButton || m_drag == Drag::None)
            return;

        const Drag drag = m_drag;
        m_drag = Drag::None;

        if (doc && drag == Drag::Draw) {
            doc->addNote(m_sv->selectedTrack(), m_drawTick, uint8_t(m_drawKey),
                         uint32_t(m_drawDur), m_lastVelocity);
            m_sv->setSelection({{uint32_t(m_drawTick), uint8_t(m_drawKey)}});
        } else if (doc && drag == Drag::Move && (m_dTick != 0 || m_dKey != 0)) {
            const std::vector<DocNote> notes = m_commands->selectedNotes();
            doc->moveNotes(notes, m_dTick, m_dKey);
            // Follow the notes with the selection.
            std::vector<SongView::NoteId> ids;
            for (const DocNote &note : notes)
                ids.push_back(
                    {uint32_t(std::max<int64_t>(0, int64_t(note.tick) + m_dTick)),
                     uint8_t(std::clamp(int(note.key) + m_dKey, 0, 127))});
            m_sv->setSelection(std::move(ids));
        } else if (doc && drag == Drag::Resize && m_dDur != 0) {
            doc->resizeNotes(m_commands->selectedNotes(), m_dDur);
        } else if (doc && drag == Drag::ResizeLeft && m_dTick != 0) {
            const std::vector<DocNote> notes = m_commands->selectedNotes();
            doc->resizeNotesLeft(notes, m_dTick);
            // Selection ids key on the start tick, which just moved; follow
            // it (same clamp as the document: the note-off pins the drag).
            std::vector<SongView::NoteId> ids;
            for (const DocNote &note : notes) {
                const int64_t maxTick = note.unterminated()
                                            ? INT64_MAX
                                            : int64_t(note.tick + note.duration) - 1;
                ids.push_back({uint32_t(std::clamp<int64_t>(
                                   int64_t(note.tick) + m_dTick, 0, maxTick)),
                               note.key});
            }
            m_sv->setSelection(std::move(ids));
        } else if (doc && drag == Drag::Velocity && m_dVel != 0) {
            doc->nudgeNotesVelocity(m_commands->selectedNotes(), m_dVel);
            // Latch the dragged note's final velocity for the next draw.
            m_lastVelocity =
                uint8_t(std::clamp(int(m_velAnchor.velocity) + m_dVel, 1, 127));
        }
        m_dTick = 0;
        m_dKey = 0;
        m_dDur = 0;
        m_dVel = 0;
        update();
    }

    void keyPressEvent(QKeyEvent *event) override
    {
        if (event->modifiers().testFlag(Qt::KeypadModifier)) {
            Qt::KeyboardModifiers modifiers = event->modifiers();
            modifiers.setFlag(Qt::KeypadModifier, false);
            const QKeySequence normalized(
                QKeyCombination(modifiers, Qt::Key(event->key())));
            for (QAction *action : actions()) {
                if (!action->shortcuts().contains(normalized))
                    continue;
                action->trigger();
                event->accept();
                return;
            }
        }
        if (event->key() != Qt::Key_Escape) {
            QWidget::keyPressEvent(event);
            updateHoverCursor(event->modifiers());
            return;
        }
        m_drag = Drag::None;
        m_leftPress = false;
        m_rightPress = false;
        stopBandAuditions();
        m_sv->clearSelection();
        m_sv->clearTimeSelection();
        update();
        event->accept();
    }

    void keyReleaseEvent(QKeyEvent *event) override
    {
        // End the transpose audition when the shortcut's keys come up.
        // Autorepeat releases are skipped so a held Up keeps sounding the
        // moving pitch; the Drag::None guard keeps a stray key release
        // from cutting a mouse gesture's preview short.
        if (!event->isAutoRepeat() && m_auditioned && m_drag == Drag::None) {
            auditionKey(0, 0);
            m_auditioned = false;
        }
        QWidget::keyReleaseEvent(event);
        updateHoverCursor(event->modifiers());
    }

    void updateHoverCursor(Qt::KeyboardModifiers modifiers = QApplication::keyboardModifiers())
    {
        if (m_drag != Drag::None)
            return;
        const ViewNote *hit = m_sv->document() && m_curPos.x() >= kKeyboardW
                                  ? hitNote(m_curPos)
                                  : nullptr;
        const bool ctrlHeld = (modifiers & Qt::ControlModifier) != 0;
        if (hit && ctrlHeld) {
            setCursor(Qt::SizeVerCursor);
        } else {
            setCursor(hit && (piano_roll_rendering::nearRightEdge(*m_sv, *hit, m_curPos)
                              || piano_roll_rendering::nearLeftEdge(*m_sv, *hit, m_curPos))
                          ? Qt::SizeHorCursor
                      : hit && piano_roll_rendering::nearVelocityHandle(*m_sv, *hit, m_curPos)
                          ? Qt::SizeVerCursor
                          : Qt::ArrowCursor);
        }
    }

public:
    enum class Drag {
        None,
        Band,
        TimeSel,
        Move,
        Resize,
        ResizeLeft,
        Velocity,
        Draw
    };

    // Whether pos falls inside the active time selection's band as this
    // widget draws it (the selection must cover the shown track).
    bool insideTimeSelection(QPoint pos) const
    {
        const SongView::TimeSelection &sel = m_sv->timeSelection();
        if (!sel.active() || !m_sv->timeSelectionCoversTrack(m_sv->selectedTrack()))
            return false;
        const double tick = m_sv->tickAtContentX(pos.x() - kKeyboardW);
        return tick >= double(sel.startTick) && tick < double(sel.endTick);
    }


    // All roll auditions go through here so the keyboard column can mark the
    // sounding key (velocity 0 releases and clears the mark).
    void auditionKey(int key, int velocity)
    {
        m_sv->audition(m_sv->selectedTrack(), key, velocity);
        const int sounding = velocity > 0 ? key : -1;
        if (sounding != m_soundingKey) {
            m_soundingKey = sounding;
            update(0, 0, kKeyboardW, height());
        }
    }

    // Begin the pencil gesture: a pending grid-cell note at the press
    // position that sounds while the button is held; the document note is
    // committed on release (one undo entry).
    void beginDraw()
    {
        m_drawAnchor = m_sv->snapTickDown(m_pressTick);
        m_drawTick = m_drawAnchor;
        m_drawDur = int64_t(m_sv->gridTicksAt(m_drawAnchor));
        m_drawKey = m_pressKey;
        m_drag = Drag::Draw;
        m_sv->clearSelection();
        ViewNote pending{};
        pending.startTick = uint32_t(m_drawTick);
        pending.endTick = uint32_t(m_drawTick + uint64_t(m_drawDur));
        pending.key = uint8_t(m_drawKey);
        pending.velocity = m_lastVelocity;
        pending.track = uint8_t(m_sv->selectedTrack());
        m_sv->announceNote(pending);
        auditionKey(m_drawKey, m_lastVelocity);
        m_auditioned = true;
        update();
    }


    // Topmost (last-drawn) note of the selected track under pos. The rect is
    // widened a little on both sides so the edge resize handles can be
    // grabbed from just outside the note.
    const ViewNote *hitNote(QPoint pos) const
    {
        const int selected = m_sv->selectedTrack();
        const ViewNote *hit = nullptr;
        for (const ViewNote &note : m_sv->model().notes) {
            if (note.track != selected)
                continue;
            if (piano_roll_rendering::noteRect(*m_sv, note).adjusted(-2, 0, 2, 0)
                    .contains(pos))
                hit = &note;
        }
        return hit;
    }



    void drawNotes(QPainter &p, const SongViewModel &model, int selected,
                   bool ghostPass)
    {
        const int keyH = m_sv->keyHeight();
        const bool velZoomed = keyH >= kVelHandleMinKeyH;
        if (!ghostPass && m_drag == Drag::Velocity) {
            QFont f = p.font();

            f.setPixelSize(std::clamp(keyH - 3, 7, 11));
            p.setFont(f);
        }
        for (const ViewNote &note : model.notes) {
            const bool ghost = note.track != selected;
            if (ghost != ghostPass)
                continue;
            const QRect r = displayedNoteRect(note);
            if (r.right() < kKeyboardW || r.left() > width())
                continue;
            if (r.bottom() < 0 || r.top() > height())
                continue;
            QColor c = SongView::trackColor(note.track);
            if (ghost) {
                c.setAlpha(60);
                p.fillRect(r, c);
            } else {
                int vel = note.velocity;
                if (m_drag == Drag::Velocity && m_sv->isSelected(note))
                    vel = std::clamp(int(note.velocity) + m_dVel, 1, 127);
                c.setAlpha(120 + vel); // velocity shows as opacity
                p.fillRect(r, c);
                // Velocity bar (bottom = 0, top = 127) once zoomed in enough
                // for the full-width handle; it tracks the drag preview.
                if (velZoomed) {
                    const int barH = r.height() >= 20 ? 2 : 1;
                    const int innerH = r.height() - 2;
                    const int y = std::min(r.top() + 1 + (127 - vel) * (innerH - 1) / 127,
                                           r.bottom() - barH);
                    p.fillRect(QRect(r.left() + 1, y, std::max(1, r.width() - 2), barH),
                               SongView::trackColor(note.track).darker(170));
                }
                // While a velocity drag is live, every current-track note
                // shows its (previewed) value.
                if (m_drag == Drag::Velocity) {
                    const QString text = QString::number(vel);
                    if (r.width() >= p.fontMetrics().horizontalAdvance(text) + 4) {
                        p.setPen(c.lightness() > 127 ? Qt::black : Qt::white);
                        p.drawText(r, Qt::AlignCenter, text);
                    }
                }
                if (m_sv->isSelected(note)) {
                    p.setPen(QPen(palette().color(QPalette::HighlightedText), 1));
                    p.drawRect(r.adjusted(0, 0, -1, -1));
                    p.setPen(QPen(palette().color(QPalette::Highlight), 1));
                    p.drawRect(r.adjusted(-1, -1, 0, 0));
                } else {
                    p.setPen(note.unterminated
                                 ? QPen(piano_roll_rendering::playheadColor(), 1, Qt::DashLine)
                                 : QPen(SongView::trackColor(note.track).darker(150), 1));
                    p.drawRect(r.adjusted(0, 0, -1, -1));
                }
            }
        }
    }

    // The pending note of a draw gesture, solid like the real note. (Move and
    // resize gestures need no extra pass: drawNotes paints the selected notes
    // at their dragged geometry via displayedNoteRect.)
    void drawDragPreview(QPainter &p, const SongViewModel &model, int selected)
    {
        Q_UNUSED(model);
        if (m_drag != Drag::Draw)
            return;
        const QRect r = piano_roll_rendering::noteRect(
            *m_sv, m_drawTick, m_drawTick + uint64_t(m_drawDur), m_drawKey);
        QColor c = SongView::trackColor(selected);
        c.setAlpha(120 + m_lastVelocity);
        p.fillRect(r, c);
        p.setPen(QPen(SongView::trackColor(selected).darker(150), 1));
        p.drawRect(r.adjusted(0, 0, -1, -1));
    }

    // Where the note sits on screen right now: its stored geometry, displaced
    // by the live move/resize deltas when it's part of the gesture. Mirrors
    // the clamping applied on release in mouseReleaseEvent.
    QRect displayedNoteRect(const ViewNote &note) const
    {
        const bool dragging = m_drag == Drag::Move || m_drag == Drag::Resize
                              || m_drag == Drag::ResizeLeft;
        if (!dragging || !m_sv->isSelected(note))
            return piano_roll_rendering::noteRect(*m_sv, note);
        int64_t tick, endTick;
        if (m_drag == Drag::ResizeLeft) {
            // The note-off pins the gesture; only the start moves.
            endTick = int64_t(note.endTick);
            tick = std::clamp<int64_t>(int64_t(note.startTick) + m_dTick, 0,
                                       endTick - 1);
        } else {
            tick = std::max<int64_t>(0, int64_t(note.startTick) + m_dTick);
            endTick =
                std::max<int64_t>(tick + 1, int64_t(note.endTick) + m_dTick + m_dDur);
        }
        const int key = std::clamp(int(note.key) + m_dKey, 0, 127);
        return piano_roll_rendering::noteRect(
            *m_sv, uint64_t(tick), uint64_t(endTick), key);
    }

    void retargetNoteMenu(QPoint globalPosition)
    {
        const QPoint position = mapFromGlobal(globalPosition);
        const ViewNote *hit = m_sv->document() ? hitNote(position) : nullptr;
        if (!hit)
            return;
        if (!m_sv->isSelected(*hit))
            m_sv->setSelection({{hit->startTick, hit->key}});
        m_commands->showMenuAt(globalPosition);
        update();
    }



    // Selects the selected track's notes intersecting the band rect.
    // Ableton-style sweep audition: each note sounds the moment the rubber
    // band first covers it and stops when the band leaves it (its own
    // length is the ceiling), so sweeping across a chord hears its notes
    // together without long notes ringing on. A note swept out and back in
    // re-auditions.
    void auditionBandEntrants(const QRect &band)
    {
        std::vector<SongView::NoteId> inBand;
        for (const ViewNote &note : m_sv->model().notes) {
            if (note.track != m_sv->selectedTrack()
                || !piano_roll_rendering::noteRect(*m_sv, note).intersects(band))
                continue;
            const SongView::NoteId id{note.startTick, note.key};
            if (std::find(m_bandAud.begin(), m_bandAud.end(), id) == m_bandAud.end())
                m_sv->auditionTimed(note.track, note.key, note.velocity, note.startTick,
                                    note.endTick);
            inBand.push_back(id);
        }
        for (const SongView::NoteId &old : m_bandAud) {
            if (std::find(inBand.begin(), inBand.end(), old) != inBand.end())
                continue;
            // Previews are one-per-key: keep the key sounding while the band
            // still covers another note of the same pitch.
            const bool keyCovered = std::any_of(
                inBand.begin(), inBand.end(),
                [&](const SongView::NoteId &id) { return id.key == old.key; });
            if (!keyCovered)
                m_sv->auditionTimedOff(m_sv->selectedTrack(), old.key);
        }
        m_bandAud = std::move(inBand);
    }

    // Release every preview the band still covers (drag ended or cancelled).
    void stopBandAuditions()
    {
        for (const SongView::NoteId &id : m_bandAud)
            m_sv->auditionTimedOff(m_sv->selectedTrack(), id.key);
        m_bandAud.clear();
    }

    void selectBand(const QRect &band, bool additive)
    {
        std::vector<SongView::NoteId> ids =
            additive ? m_sv->selection() : std::vector<SongView::NoteId>();
        for (const ViewNote &note : m_sv->model().notes) {
            if (note.track != m_sv->selectedTrack())
                continue;
            if (!piano_roll_rendering::noteRect(*m_sv, note).intersects(band))
                continue;
            const SongView::NoteId id{note.startTick, note.key};
            if (std::find(ids.begin(), ids.end(), id) == ids.end())
                ids.push_back(id);
        }
        m_sv->setSelection(std::move(ids));
    }

    SongView *m_sv;
    std::unique_ptr<PianoRollCommands> m_commands;
    Drag m_drag = Drag::None;
    QPoint m_pressPos;
    QPoint m_curPos;
    double m_pressTick = 0.0;
    int m_pressKey = 0;
    uint64_t m_gripTick = 0;     // edge tick grabbed by a resize drag
    uint64_t m_gripOpposite = 0; // …and the note's other edge (the pivot)
    int64_t m_dTick = 0;
    int m_dKey = 0;
    int64_t m_dDur = 0;
    int m_dVel = 0;
    uint64_t m_drawTick = 0; // pending note of a draw gesture
    int64_t m_drawDur = 0;
    int m_drawKey = 0;               // follows the cursor vertically mid-draw
    uint64_t m_drawAnchor = 0;       // grid cell pressed; drags pivot around it
    bool m_leftPress = false;        // left button held on empty space; cursor
                                     // move vs. draw undecided
    bool m_rightPress = false;       // right button held; band vs. menu undecided
    bool m_rightShift = false;       // …with Shift: drag sweeps a time selection
    uint64_t m_rightAnchorTick = 0;  // snapped tick of the right press
    bool m_rightHit = false;         // that press landed on a note…
    SongView::NoteId m_rightHitId{}; // …this one
    std::vector<SongView::NoteId> m_bandAud; // notes the band currently
                                              // covers; entrants audition
    ViewNote m_velAnchor{};       // pressed note of a velocity drag (a copy)
    int m_velAudEff = -1;         // last effective velocity auditioned mid-drag
    int m_kbdKey = -1;            // key sounding from a keyboard-column press
    int m_soundingKey = -1;       // auditioned key highlighted on the keyboard
    bool m_auditioned = false;    // a drag/draw preview note is sounding
    uint8_t m_lastVelocity = 100; // new-note default; latches to the last
                                  // clicked/velocity-edited note
    bool m_panning = false;    // middle-drag pan
    QPoint m_panPos;           // last pan sample, global coords
};

PianoRoll::PianoRoll(SongView *songView)
    : QWidget(songView), m_state(std::make_unique<State>(this, songView))
{
    m_state->setGeometry(rect());
    setFocusProxy(m_state.get());
}

PianoRoll::~PianoRoll() = default;

void PianoRoll::refresh()
{
    m_state->update();
}

bool PianoRoll::gestureActive() const
{
    return m_state->gestureActive();
}

void PianoRoll::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    m_state->setGeometry(rect());
}

} // namespace songview
