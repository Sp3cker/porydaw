# PianoRoll gesture-state refactor — implementation plan

Goal: decompose `PianoRoll`'s pointer-gesture handling (CC 37/56/55 across
press/move/release) into a two-channel state machine with CC ≤ 8 routers and
CC ≤ 7 leaves, behavior-preserving, gated by rollcheck at every step.

Provenance: design by qt-cpp-reviewer (`PianoRollDecomposer`); six plan slices
by parallel `plan` agents (Cutover, Press, Move, Release, Peripherals, Verify),
integrated here. Every body below is a verbatim extraction from the current
tree with only guard translations applied — line anchors refer to the
pre-refactor `fork-main` tree and drift after each commit.

This refactor also repairs seam damage from commit 40275f4 ("Refactor SongView
into focused modules"), which split the 6,777-line `songview.cpp` monolith by
line-count triage under the former 600-line hard ceiling. That is why
`beginDraw()` — a gesture-arming function — lives in `pianoroll_commands.cpp`;
Commit 5 moves gesture state and gesture arming into concept-named files: the
cohesion fix the earlier split deferred.

## Binding amendment (supersedes design §5 wording)

`beginVelocityPress()` is the **modifier-press entry only**, feeding deferred
`resolveVelocityPress`. `armNoteDrag()` arms only `Move`, `Resize`, or
`ResizeLeft`.

## State model (normative)

```cpp
// pianoroll.h (private)
enum class LeftDrag  { None, PendingDraw, PendingVelocity, Draw, Move, Resize, ResizeLeft, Velocity };
enum class RightDrag { None, PendingMenu, Band, TimeSel };
LeftDrag  m_leftDrag  = LeftDrag::None;
RightDrag m_rightDrag = RightDrag::None;
```

Replaces `Drag m_drag`, `bool m_leftPress`, `bool m_rightPress`, `bool
m_velModPress` (all deleted). Overlays `m_panning` / `m_kbdKey` and all payload
members stay flat and unchanged, including `m_modifierVelocityDrag` (no rename).

Live-token interlock — introduced as helpers in Commit 2, inlined mechanically
in Commit 1:

```cpp
bool PianoRoll::dragLive() const
{
    return m_leftDrag == LeftDrag::Draw || m_leftDrag == LeftDrag::Move ||
           m_leftDrag == LeftDrag::Resize || m_leftDrag == LeftDrag::ResizeLeft ||
           m_leftDrag == LeftDrag::Velocity || m_rightDrag == RightDrag::Band ||
           m_rightDrag == RightDrag::TimeSel;
}

void PianoRoll::activateLeftDrag(LeftDrag state)
{
    m_leftDrag = state;
    if (m_rightDrag == RightDrag::Band || m_rightDrag == RightDrag::TimeSel)
        m_rightDrag = RightDrag::PendingMenu;
}

void PianoRoll::clearLiveDragToken()
{
    if (m_leftDrag == LeftDrag::Draw || m_leftDrag == LeftDrag::Move ||
        m_leftDrag == LeftDrag::Resize || m_leftDrag == LeftDrag::ResizeLeft ||
        m_leftDrag == LeftDrag::Velocity) {
        m_leftDrag = LeftDrag::None;
    } else if (m_rightDrag == RightDrag::Band || m_rightDrag == RightDrag::TimeSel) {
        m_rightDrag = RightDrag::PendingMenu;
    }
}
```

Interlock rules:
1. Right resolution requires `!dragLive()`; pending left states do not block.
2. Left live activation demotes a live right drag (Band/TimeSel) to PendingMenu.
3. Right release clears the token: a live left drag is aborted uncommitted
   (deltas discarded, no `stopNoteAudition`) while the right-click resolution runs.
4. Left release through the main commit path clears the token (kills a live
   right drag uncommitted); the pending-click release paths do NOT clear it —
   except PendingDraw with a live right drag, which falls through to
   `commitDrag` (normative; do not "fix").

## Global invariants (every commit preserves these)

- Three distinct thresholds: right = integer manhattan ≥
  `QApplication::startDragDistance()`; draw = qreal |dx| ≥
  `lyt::space(Space::One)`; deferred velocity = integer |dy| <
  `startDragDistance()` consumes the whole move event. Never unified.
- `stopNoteAudition()` ordering differs per release path (right: never; pending
  clicks and catch-all: after projection completion; main commit: before delta
  reset). Never hoisted into a shared epilogue.
- Every release path reaches `completeProjectionGesture()`
  (`setProjectionLocked(false); flushProjectionIfDirty();` — unlock before
  flush); the router catch-all is the guarantee for stray paths.
- Selection mutates before `beginVelocityGesture(resolveSelection())`;
  `commitMoveDrag` re-selects after the doc edit; `commitDrawDrag` selects
  `insertedNoteIds` diffed against a pre-`addNote` snapshot.
- Pending-draw row glissando runs before `beginDraw()` (no-re-attack guard);
  velocity resolution re-pins hover after activation; velocity auditions only
  on effective (mid2agb) velocity steps.
- `m_curPos` is not sampled during pan/kbd early-returns; hover-key update is
  first and unconditional in `mouseMoveEvent`.
- `gestureActive()` quirk preserved: PendingVelocity reports NOT active
  (follow-scroll stays live under a held modifier press). Fixing is a separate
  sign-off, not part of this refactor.

## File plan (final state)

| File | Contents | LOC |
|---|---|---|
| `src/ui/songview/pianoroll_interaction.cpp` | 3 thin routers, double-click, leaveEvent, overlay helpers, audition primitives | ~230 |
| `src/ui/songview/pianoroll_gestures.cpp` (new) | interlock helpers, begin*/pressContent/resolve*/applyModifierVelocitySelection, beginDraw | ~285-315 |
| `src/ui/songview/pianoroll_gestures_active.cpp` (new) | update*/drawSpanAt, release*/commit*/armVelocityOneShot, completeProjectionGesture | ~250-280 |

Note: the design's original ~340 LOC single-file estimate was wrong; slice
arithmetic predicts 540-570 LOC, so the gesture code splits at the
arm-vs-actuate ownership seam into two files (Peripherals slice finding).
Register both new files in `CMakeLists.txt` beside `pianoroll_interaction.cpp`
(app list, lines ~277-284).

Header dependency: Commit 4 adds `#include "ui/songview.h"` to `pianoroll.h`
and removes the `class SongView;` forward declaration — the fixed signatures
`commitVelocityDrag(SongView::VelocityCommitResult)` and
`armVelocityOneShot(const QMouseEvent*, SongView::VelocityCommitResult)` cannot
name the nested enum through an incomplete type. No cycle: `songview.h` only
forward-declares `songview::PianoRoll`.

---

## Commit 1 — Cutover (agent: `task`)

Mechanical translation only: enums + members in, bools out, every reader/writer
translated with inline interlock semantics. No new functions, no `pianoroll_gestures.cpp`.

Suggested message: `Refactor PianoRoll gesture state to dual-channel enums`

Header: replace the `Drag` enum (~line 129) and member (~line 214); delete
`m_leftPress`/`m_rightPress`/`m_velModPress` (~lines 229-231, 239-240).

Inline predicates (Commit 1 only; Commit 2 replaces with helpers):
- left-live: `m_leftDrag ∈ {Draw, Move, Resize, ResizeLeft, Velocity}`
- right-live: `m_rightDrag ∈ {Band, TimeSel}`
- drag-live: left-live || right-live
- left activation: `m_leftDrag = LeftDrag::X; if (right-live) m_rightDrag = RightDrag::PendingMenu;`
- generic old `m_drag = Drag::None` that did not clear `m_rightPress`:
  `if (left-live) m_leftDrag = LeftDrag::None; else if (right-live) m_rightDrag = RightDrag::PendingMenu;`

### Site-by-site translation table

**pianoroll.cpp**

| Line | Old | New |
|---|---|---|
| 125 | `m_drag != Drag::None \|\| m_leftPress \|\| m_rightPress` in `gestureActive()` | `(m_leftDrag != LeftDrag::None && m_leftDrag != LeftDrag::PendingVelocity) \|\| m_rightDrag != RightDrag::None` (quirk preserved: PendingVelocity omitted) |
| 137 | `if (m_drag != Drag::Velocity && !m_velModPress) return;` | `if (m_leftDrag != LeftDrag::Velocity && m_leftDrag != LeftDrag::PendingVelocity) return;` |
| 139,141 | `m_drag = Drag::None; ... m_velModPress = false;` | `m_leftDrag = LeftDrag::None;` + live-right demotion to PendingMenu (inline `clearLiveDragToken` semantics) |
| 163 | `(m_drag == Drag::Velocity \|\| m_velModPress)` | `(m_leftDrag == LeftDrag::Velocity \|\| m_leftDrag == LeftDrag::PendingVelocity)` |

**pianoroll_interaction.cpp**

| Line | Old | New |
|---|---|---|
| 72 | `m_rightPress = true;` | `m_rightDrag = RightDrag::PendingMenu;` |
| 110 | `m_velModPress = true;` | `m_leftDrag = LeftDrag::PendingVelocity;` (pending write; does not disturb live right) |
| 147 | `m_drag = Drag::Resize;` | inline left activation `Resize` incl. live-right demotion |
| 151 | `m_drag = Drag::ResizeLeft;` | inline left activation `ResizeLeft` |
| 155 | `m_drag = Drag::Move;` | inline left activation `Move` |
| 172 | `m_leftPress = true;` | `m_leftDrag = LeftDrag::PendingDraw;` (do not touch right channel) |
| 219 | `m_drag == Drag::Velocity` | `m_leftDrag == LeftDrag::Velocity` |
| 238-242 | `m_rightPress && m_drag == Drag::None`; `m_drag = shift ? TimeSel : Band` | guard `m_rightDrag == RightDrag::PendingMenu && !(left-live)`; assign `m_rightDrag = m_rightShift ? RightDrag::TimeSel : RightDrag::Band` |
| 244 | `m_leftPress && m_drag == Drag::None` | `m_leftDrag == LeftDrag::PendingDraw && !(right-live)` |
| 254 | `m_leftPress && m_drag == Drag::None && abs(dx) >= lyt::space(One)` | `m_leftDrag == LeftDrag::PendingDraw && !(right-live) &&` unchanged threshold |
| 265 | `m_velModPress && m_drag == Drag::None` | `m_leftDrag == LeftDrag::PendingVelocity && !(right-live)` |
| 273 | `m_velModPress = false;` | `m_leftDrag = LeftDrag::None;` |
| 300 | `m_drag = Drag::Velocity;` | inline left activation `Velocity`; keep `m_modifierVelocityDrag = true` before, `cancelVelocityInteraction()` on failure after |
| 305 | `m_drag == Drag::Velocity` | `m_leftDrag == LeftDrag::Velocity` |
| 308 | `m_drag == Drag::None` | `!(drag-live)` — pending states take the idle/hover path |
| 317/340/345/353/358/377 | Move/Resize/ResizeLeft/Velocity/Draw reads | corresponding `m_leftDrag` comparisons (353: ternary target `m_dDur : m_dTick`) |
| 408 | `m_drag == Drag::TimeSel` | `m_rightDrag == RightDrag::TimeSel` |
| 415 | `m_drag == Drag::Band` | `m_rightDrag == RightDrag::Band` |
| 443 | `RightButton && m_rightPress` | `RightButton && m_rightDrag != RightDrag::None` |
| 444-446 | snapshot `m_drag`; `m_rightPress = false; m_drag = None;` | `const RightDrag drag = m_rightDrag; m_rightDrag = RightDrag::None;` then, only if left-live, `m_leftDrag = LeftDrag::None;` (rule 3) |
| 447/452 | `drag == TimeSel` / `Band` | `drag == RightDrag::TimeSel` / `RightDrag::Band` |
| 471-473 | `m_leftPress` press/clear/`m_drag == None` | `m_leftDrag == LeftDrag::PendingDraw`; `m_leftDrag = LeftDrag::None;`; `!(drag-live)` after clear (live right forces fall-through to main path) |
| 485-489 | `m_velModPress` press/clear | `m_leftDrag == LeftDrag::PendingVelocity`; `m_leftDrag = LeftDrag::None;` — NO drag-live gate (click returns without disturbing live right) |
| 507 | `button != Left \|\| m_drag == None` | `button != Left \|\| !(drag-live)` — catch-all stays last |
| 508 | `button != Left && m_drag == Velocity` | `button != Left && m_leftDrag == LeftDrag::Velocity` |
| 515 | `const Drag drag = m_drag;` | `const LeftDrag drag = m_leftDrag;` (right-owned token snapshots as None — no left branch runs) |
| 518 | `m_drag = Drag::None;` | `m_leftDrag = LeftDrag::None;` + live-right demotion to PendingMenu (inline clearLiveDragToken) |
| 520/531/537/561/563/566 | `drag == ...` commit reads | corresponding `LeftDrag::` comparisons |

**pianoroll_commands.cpp**

| Line | Old | New |
|---|---|---|
| 100-102 | Escape: `m_drag = None; m_leftPress = false; m_rightPress = false;` | `m_leftDrag = LeftDrag::None; m_rightDrag = RightDrag::None;` (hard reset of both channels) |
| 124 | `!event->isAutoRepeat() && m_drag == Drag::None` | `!event->isAutoRepeat() && !(drag-live)` (pending states must not block audition teardown) |
| 140 | `m_drag = Drag::Draw;` in `beginDraw()` | inline left activation `Draw` incl. live-right demotion |

**pianoroll_geometry.cpp**: lines 397, 402, 420 — `Move/Resize/ResizeLeft`
reads become `m_leftDrag` comparisons (bodies unchanged).

**pianoroll_paint.cpp**: line 94 `Drag::Band` → `RightDrag::Band`; 113, 115
`Drag::Velocity` → `LeftDrag::Velocity`; 213 Band ring → `RightDrag::Band`;
252 `m_drag != Drag::Draw` → `m_leftDrag != LeftDrag::Draw`.

Out-of-scope hits that MUST NOT change: `WaveformView::m_drag`,
`TimeRuler::m_leftPress/m_rightPress`, automation `SweepGesture::Mode::Drag`,
keymap strings, check comments.

Acceptance: restricted grep for `\bDrag\b|m_drag|m_leftPress|m_rightPress|m_velModPress`
over the six PianoRoll files returns zero legacy hits; rollcheck green
(`deno task verify --filter rollcheck`). Manual interlock trace of the four
rules against the translated source.

---

## Commit 2 — Press path (agent: `task`)

Suggested message: `Extract PianoRoll press gestures into pianoroll_gestures`

1. Register `src/ui/songview/pianoroll_gestures.cpp` in `CMakeLists.txt` (~line 277-284, app source list).
2. Header decl block (after audition primitives, before `beginDraw`):
   interlock helpers + `beginPanGesture`, `beginKbdAudition`, `notesOnKey`,
   `beginPendingMenu`, `beginLeftPress`, `pressContent`, `beginNotePress`,
   `applyNotePressSelection`, `armNoteDrag`, `beginVelocityPress`,
   `beginPendingDraw`, `beginDraw` (existing decl, unchanged).
3. New file skeleton:
   includes `ui/songview/pianoroll.h`, `core/mid2agbtables.h`, `porydaw_scale.h`,
   `ui/keymap.h`, `ui/songview.h`, `<QMouseEvent>`, `<algorithm>`, `<utility>`, `<vector>`;
   namespace `songview`.
4. Add interlock helpers (bodies above), then press helpers in §5 order. Body
   sketches (verbatim extraction with cutover guards):

```cpp
void PianoRoll::beginPanGesture(const QMouseEvent *event)
{
    m_panning = true;
    m_panPos = event->globalPosition();
    setCursor(Qt::ClosedHandCursor);
}

void PianoRoll::beginKbdAudition(const QMouseEvent *event)
{
    m_kbdKey = yToKey(event->position().y());
    m_sv->selectionModel().setNoteSelection(notesOnKey(m_kbdKey));
    auditionKey(m_kbdKey, 100);
}

std::vector<NoteId> PianoRoll::notesOnKey(int key) const   // from :48-54
{
    std::vector<NoteId> ids;
    for (const ViewNote &note : m_sv->model().notes) {
        if (note.track == m_sv->selectionModel().primaryTrack() && note.key == key &&
            note.noteId.isAssigned())
            ids.push_back(note.noteId);
    }
    return ids;
}

void PianoRoll::beginPendingMenu(const QMouseEvent *event, const ViewNote *hit)  // payload :71-78
{
    m_pressPos = m_curPos = event->position();
    m_rightDrag = RightDrag::PendingMenu;
    m_rightShift = event->modifiers() & Qt::ShiftModifier;
    m_rightAnchorTick = m_sv->snapTick(
        m_sv->tickAtContentX(event->position().x() - m_geometry.pianoKeyboardWidth));
    m_rightHit = hit != nullptr;
    if (hit)
        m_rightHitId = hit->noteId;
}

void PianoRoll::beginLeftPress(const QMouseEvent *event)   // from :84-92; also replaces double-click :205-207
{
    m_pressPos = m_curPos = event->position();
    m_pressTick = m_sv->tickAtContentX(event->position().x() - m_geometry.pianoKeyboardWidth);
    m_pressKey = yToKey(event->position().y());
    m_dTick = 0;
    m_dKey = 0;
    m_dDur = 0;
    m_dVel = 0;
    m_modifierVelocityDrag = false;
}

void PianoRoll::pressContent(QMouseEvent *event)           // from :60-61,84-98,167-183
{
    beginLeftPress(event);
    SongDocument *doc = m_sv->document();
    const ViewNote *hit = doc ? hitNote(event->position()) : nullptr;
    if (!hit && doc && m_sv->scaleFold() &&
        (m_pressKey < 0 ||
         !porydaw_scale::isScalePitch(m_sv->scaleId(), m_sv->scaleRoot(), m_pressKey)))
        return;
    if (hit) {
        beginNotePress(*hit, event);
        if (m_leftDrag == LeftDrag::PendingVelocity)   // deferred path already invalidated
            return;
    } else if (doc) {
        beginPendingDraw(event);
    } else {
        m_sv->commitEditCursor(m_sv->snapTick(m_pressTick));
    }
    invalidateContent();
}

void PianoRoll::beginNotePress(const ViewNote &note, const QMouseEvent *event)  // from :99-121,142-160
{
    const bool rightEdge = nearRightEdge(note, event->position());
    const bool leftEdge = nearLeftEdge(note, event->position());
    const auto &keys = keymap::Registry::instance();
    const auto pressMods = event->modifiers();
    if (keys.matchesModifier(pressMods, QStringLiteral("roll.velocity_drag")) && !rightEdge &&
        !leftEdge) {
        m_leftDrag = LeftDrag::PendingVelocity;
        m_velModMods = keymap::Registry::instance().modifierBinding(
            QStringLiteral("roll.velocity_drag"));
        beginVelocityPress(note);
        return;
    }
    applyNotePressSelection(note, rightEdge || leftEdge, pressMods);
    m_sv->announceNote(note);
    m_lastVelocity = note.velocity;
    armNoteDrag(note, event->position());
    auditionKey(note.key, note.velocity);   // runs even when the velocity gesture failed
    m_auditioned = true;
}

void PianoRoll::applyNotePressSelection(const ViewNote &note, bool onEdge,   // from :122-141
                                        Qt::KeyboardModifiers modifiers)
{
    const auto &storedSelection = m_sv->selectionModel().noteSelection();
    std::vector<NoteId> ids(storedSelection.begin(), storedSelection.end());
    const NoteId id = note.noteId;
    if ((modifiers & Qt::ControlModifier) && !onEdge) {
        if (std::erase(ids, id) == 0)
            ids.push_back(id);
        m_sv->selectionModel().setNoteSelection(std::move(ids));
    } else if (modifiers & Qt::ControlModifier) {
        if (std::find(ids.begin(), ids.end(), id) == ids.end()) {
            ids.push_back(id);
            m_sv->selectionModel().setNoteSelection(std::move(ids));
        }
    } else if (note.track != m_sv->selectionModel().primaryTrack() ||
               !note.noteId.isAssigned() ||
               !m_sv->selectionModel().isNoteSelected(note.noteId)) {
        m_sv->selectionModel().setNoteSelection({id});
    }
}

void PianoRoll::armNoteDrag(const ViewNote &note, QPointF position)   // from :146-156
{
    if (nearRightEdge(note, position)) {
        activateLeftDrag(LeftDrag::Resize);
        m_gripTick = note.endTick;
        m_gripOpposite = note.startTick;
    } else if (nearLeftEdge(note, position)) {
        activateLeftDrag(LeftDrag::ResizeLeft);
        m_gripTick = note.startTick;
        m_gripOpposite = note.endTick;
    } else {
        activateLeftDrag(LeftDrag::Move);
    }
}

void PianoRoll::beginVelocityPress(const ViewNote &note)   // deferred entry ONLY; from :113-119
{
    m_velAnchor = note;
    m_velAudEff = mid2agbEffectiveVelocity(note.velocity);
    m_sv->announceNote(note);
    m_lastVelocity = note.velocity;
    auditionKey(note.key, note.velocity);
    m_auditioned = true;
    invalidateContent();
}

void PianoRoll::beginPendingDraw(const QMouseEvent *)   // from :167-177
{
    m_leftDrag = LeftDrag::PendingDraw;   // pending: direct assignment, no activation
    m_sv->selectionModel().clearNoteSelection();
    auditionKey(m_pressKey, m_lastVelocity);
    m_auditioned = true;
}
```

5. Replace `mousePressEvent` (:28-184) with the router:

```cpp
void PianoRoll::mousePressEvent(QMouseEvent *event)
{
    setFocus();
    if (!m_sv->timeline())
        return;
    m_sv->setProjectionLocked(true);
    if (event->button() == Qt::MiddleButton) {
        beginPanGesture(event);
        return;
    }
    if (event->position().x() < m_geometry.pianoKeyboardWidth) {
        if (event->button() == Qt::LeftButton)
            beginKbdAudition(event);
        return;
    }
    if (event->button() == Qt::RightButton) {
        if (m_sv->document())
            beginPendingMenu(event, hitNote(event->position()));
        return;
    }
    if (event->button() != Qt::LeftButton)
        return;
    pressContent(event);
}
```

6. Reshape `mouseDoubleClickEvent` (:186-212): keep delete-on-note branch; empty-space branch becomes `beginLeftPress(event); beginDraw(); return;` (beginDraw stays defined in commands until Commit 5); fallback stays `mousePressEvent(event)` — NOT `pressContent` (that would bypass focus/timeline/lock routing).

Acceptance: routers contain dispatch only; no press state machine inline; rollcheck green.

---

## Commit 3 — Move path (agent: `task`)

Suggested message: `Extract PianoRoll drag-update state machine`

Header decls after `beginPendingDraw`: `resolveRightPress`,
`resolveDrawPress`, `resolveVelocityPress`, `applyModifierVelocitySelection`,
`updateMoveDrag`, `updateResizeDrag`, `updateVelocityDrag`, `updateDrawDrag`,
`drawSpanAt(double, uint64_t, uint64_t&, int64_t&) const`,
`updateTimeSelDrag`, `updateBandDrag`. All event params `const QMouseEvent *`.

New includes in gestures file: `<QApplication>`, `<cmath>`, `ui/layout.h` +
aliases `namespace lyt = ::layout; using Space = lyt::Space;`.

```cpp
void PianoRoll::resolveRightPress(const QMouseEvent *event)   // from :238-243
{
    if (!dragLive() &&
        (event->pos() - m_pressPos.toPoint()).manhattanLength() >=
            QApplication::startDragDistance()) {
        m_rightDrag = m_rightShift ? RightDrag::TimeSel : RightDrag::Band;
        m_bandAud.clear();
    }
}

void PianoRoll::resolveDrawPress(const QMouseEvent *event)   // from :244-264
{
    const int key = yToKey(event->position().y());
    if (key != m_pressKey) {   // row glissando BEFORE threshold and beginDraw
        m_pressKey = key;
        auditionKey(key, m_lastVelocity);
        m_auditioned = true;
    }
    if (std::abs(event->position().x() - m_pressPos.x()) >= lyt::space(Space::One))
        beginDraw();
}

bool PianoRoll::resolveVelocityPress(const QMouseEvent *event)   // from :265-272,299-306
{
    if (std::abs(event->pos().y() - m_pressPos.toPoint().y()) <
        QApplication::startDragDistance())
        return false;   // consumes the entire event
    applyModifierVelocitySelection();
    m_modifierVelocityDrag = true;
    activateLeftDrag(LeftDrag::Velocity);
    if (!m_sv->beginVelocityGesture(resolveSelection()))
        cancelVelocityInteraction();
    if (m_leftDrag == LeftDrag::Velocity)   // re-pin AFTER activation
        setHoverKey(m_velAnchor.key);
    return true;
}

void PianoRoll::applyModifierVelocitySelection()   // from :273-298
{
    const NoteId id = m_velAnchor.noteId;
    const bool switchesNotes =
        m_suppressNextVelocitySelectionAdd && id != m_lastModifierVelocityDragNote;
    if (switchesNotes) {
        m_suppressNextVelocitySelectionAdd = false;
        m_sv->selectionModel().setNoteSelection({id});
    } else if (m_velAnchor.track != m_sv->selectionModel().primaryTrack() ||
               !m_velAnchor.noteId.isAssigned() ||
               !m_sv->selectionModel().isNoteSelected(m_velAnchor.noteId)) {
        if (m_velModMods & Qt::ControlModifier) {
            const auto &storedSelection = m_sv->selectionModel().noteSelection();
            std::vector<NoteId> ids(storedSelection.begin(), storedSelection.end());
            ids.push_back(id);
            m_sv->selectionModel().setNoteSelection(std::move(ids));
        } else {
            m_sv->selectionModel().setNoteSelection({id});
        }
    }
}

void PianoRoll::updateMoveDrag(const QMouseEvent *event)   // from :313-339
{
    const double tick =
        m_sv->tickAtContentX(event->position().x() - m_geometry.pianoKeyboardWidth);
    const int64_t grid = int64_t(m_sv->snapTicksAt(uint64_t(std::max(0.0, m_pressTick))));
    const int64_t snappedD = int64_t(std::llround((tick - m_pressTick) / double(grid))) * grid;
    const int dKey = m_sv->scaleFold() ? foldDegreeDeltaForPointer(event->position().y())
                                       : yToKey(event->position().y()) - m_pressKey;
    if (snappedD != m_dTick || dKey != m_dKey) {
        m_dTick = snappedD;
        if (dKey != m_dKey) {
            m_dKey = dKey;
            const std::vector<DocNote> notes = resolveSelection();
            if (!notes.empty()) {
                const int key =
                    m_sv->scaleFold()
                        ? porydaw_scale::nextScalePitch(m_sv->scaleId(), m_sv->scaleRoot(),
                                                        notes.front().key, m_dKey)
                        : std::clamp(int(notes.front().key) + m_dKey, 0, 127);
                if (key >= 0) {
                    auditionKey(key, notes.front().velocity);
                    m_auditioned = true;
                }
            }
        }
        invalidateContent();
    }
}

void PianoRoll::updateResizeDrag(const QMouseEvent *event)   // from :313,340-357
{
    const double tick =
        m_sv->tickAtContentX(event->position().x() - m_geometry.pianoKeyboardWidth);
    const double desired = double(m_gripTick) + (tick - m_pressTick);
    const uint64_t snapped =
        m_leftDrag == LeftDrag::Resize
            ? std::max(m_sv->snapTick(desired),
                       m_sv->snapTickUp(double(m_gripOpposite) + 1.0))
            : std::min(m_sv->snapTick(desired),
                       m_sv->snapTickDown(double(m_gripOpposite) - 1.0));
    const int64_t delta =
        std::abs(desired - double(m_gripTick)) < std::abs(desired - double(snapped))
            ? 0
            : int64_t(snapped) - int64_t(m_gripTick);
    int64_t &target = m_leftDrag == LeftDrag::Resize ? m_dDur : m_dTick;
    if (delta != target) {
        target = delta;
        invalidateContent();
    }
}

void PianoRoll::updateVelocityDrag(const QMouseEvent *event)   // from :358-376
{
    const int dv = m_pressPos.toPoint().y() - event->pos().y(); // up = louder
    if (dv != m_dVel) {
        m_dVel = dv;
        const int vel = std::clamp(int(m_velAnchor.velocity) + m_dVel, 1, 127);
        ViewNote preview = m_velAnchor;
        preview.velocity = uint8_t(vel);
        m_sv->announceNote(preview);
        const int eff = mid2agbEffectiveVelocity(vel);
        if (eff != m_velAudEff) {   // audition only on effective-velocity step
            m_velAudEff = eff;
            auditionKey(m_velAnchor.key, vel);
            m_auditioned = true;
        }
        invalidateContent();
        m_sv->updateVelocityGestureByDelta(m_dVel);
    }
}

void PianoRoll::updateDrawDrag(const QMouseEvent *event)   // from :313-315,394-407
{
    const double tick =
        m_sv->tickAtContentX(event->position().x() - m_geometry.pianoKeyboardWidth);
    const uint64_t grid = m_sv->snapTicksAt(uint64_t(std::max(0.0, m_pressTick)));
    uint64_t start;
    int64_t dur;
    drawSpanAt(tick, grid, start, dur);
    const int key = yToKey(event->position().y());
    const bool isScaleKey =
        !m_sv->scaleFold() ||
        (key >= 0 && porydaw_scale::isScalePitch(m_sv->scaleId(), m_sv->scaleRoot(), key));
    if (start != m_drawTick || dur != m_drawDur || (isScaleKey && key != m_drawKey)) {
        m_drawTick = start;
        m_drawDur = dur;
        if (isScaleKey && key != m_drawKey) {
            m_drawKey = key;
            auditionKey(m_drawKey, m_lastVelocity);
            m_auditioned = true;
        }
        invalidateContent();
    }
}

void PianoRoll::drawSpanAt(double tick, uint64_t grid, uint64_t &start,   // from :384-393
                           int64_t &dur) const
{
    const uint64_t anchor = m_drawAnchor;
    start = anchor;
    if (tick >= double(anchor)) {
        const uint64_t end = std::max(anchor + grid, m_sv->snapTickUp(tick));
        dur = int64_t(end - anchor);
    } else {
        start = m_sv->snapTickDown(tick);
        dur = int64_t(anchor + grid - start);
    }
}

void PianoRoll::updateTimeSelDrag(const QMouseEvent *event)   // from :313,408-414
{
    const double tick =
        m_sv->tickAtContentX(event->position().x() - m_geometry.pianoKeyboardWidth);
    const uint64_t t = m_sv->snapTick(tick);
    EditorSelectionModel::TimeSelection sel;
    sel.startTick = std::min(m_rightAnchorTick, t);
    sel.endTick = std::max(m_rightAnchorTick, t);
    m_sv->selectionModel().setTimeSelection(sel);
}

void PianoRoll::updateBandDrag()   // from :415-417
{
    auditionBandEntrants(QRectF(m_pressPos, m_curPos).normalized());
    invalidateContent();
}
```

Replace `mouseMoveEvent` (:214-419) — Commit 3 intermediate router (overlays
intentionally still inline; Commit 5 extracts them):

```cpp
void PianoRoll::mouseMoveEvent(QMouseEvent *event)
{
    setHoverKey(m_leftDrag == LeftDrag::Velocity ? m_velAnchor.key
                                                 : yToKey(event->position().y()));
    if (m_panning) {
        const QPointF d = event->globalPosition() - m_panPos;
        m_panPos = event->globalPosition();
        m_sv->scrollByPx(-d.x());
        m_sv->scrollRollBy(-d.y());
        return;
    }
    if (m_kbdKey >= 0) {
        const int key = yToKey(event->position().y());
        if (key != m_kbdKey) {
            m_kbdKey = key;
            auditionKey(m_kbdKey, 100);
        }
        return;
    }
    m_curPos = event->position();
    if (m_rightDrag == RightDrag::PendingMenu)
        resolveRightPress(event);
    if (m_leftDrag == LeftDrag::PendingDraw)
        resolveDrawPress(event);
    if (m_leftDrag == LeftDrag::PendingVelocity) {
        if (!resolveVelocityPress(event))
            return;
    }
    if (!dragLive()) {
        refreshHoverCursor(event->position(), event->modifiers());
        return;
    }
    if (m_rightDrag == RightDrag::Band) {
        updateBandDrag();
        return;
    }
    if (m_rightDrag == RightDrag::TimeSel) {
        updateTimeSelDrag(event);
        return;
    }
    switch (m_leftDrag) {
    case LeftDrag::Move:
        updateMoveDrag(event);
        break;
    case LeftDrag::Resize:
    case LeftDrag::ResizeLeft:
        updateResizeDrag(event);
        break;
    case LeftDrag::Velocity:
        updateVelocityDrag(event);
        break;
    case LeftDrag::Draw:
        updateDrawDrag(event);
        break;
    case LeftDrag::None:
    case LeftDrag::PendingDraw:
    case LeftDrag::PendingVelocity:
        break;   // exhaustive switch; unreachable after dragLive() gate
    }
}
```

Remove now-unused `<QApplication>`/`<cmath>` from the interaction file (it
still needs `ui/layout.h` for `lyt::space(Space::Zero)` in `auditionKey`).

Acceptance: every statement of old :214-419 exists exactly once in router or a
helper, no reordering; three threshold expressions textually distinct; rollcheck green.

---

## Commit 4 — Release path (agent: `task`)

Suggested message: `Extract PianoRoll release/commit path`

1. `pianoroll.h`: add `#include "ui/songview.h"`, drop `class SongView;`.
   Decl block after `updateBandDrag()`: `releaseRightPress`,
   `releasePendingDrawClick`, `releasePendingVelocityClick`, `commitDrag`,
   `commitDrawDrag`, `commitMoveDrag`,
   `commitVelocityDrag(SongView::VelocityCommitResult)`,
   `armVelocityOneShot(const QMouseEvent*, SongView::VelocityCommitResult)`,
   `completeProjectionGesture()`.
2. Definitions (appended after `updateBandDrag` in the gestures file):

```cpp
void PianoRoll::completeProjectionGesture()   // replaces lambda :428-431
{
    m_sv->setProjectionLocked(false);
    m_sv->flushProjectionIfDirty();
}

void PianoRoll::releaseRightPress(QMouseEvent *event)   // from :442-469
{
    SongDocument *doc = m_sv->document();
    const RightDrag drag = m_rightDrag;        // snapshot first
    m_rightDrag = RightDrag::None;
    clearLiveDragToken();                      // rule 3: aborts live left, no commit
    if (drag == RightDrag::TimeSel) {
        if (m_sv->selectionModel().timeSelection().active())
            m_sv->announceTimeSelection();
        else
            m_sv->selectionModel().clearTimeSelection();
    } else if (drag == RightDrag::Band) {
        stopBandAuditions();
        selectBand(QRectF(m_pressPos, m_curPos).normalized(),
                   event->modifiers() & Qt::ControlModifier);
    } else if (doc && m_rightHit) {
        const auto &selection = m_sv->selectionModel().noteSelection();
        if (std::find(selection.begin(), selection.end(), m_rightHitId) == selection.end())
            m_sv->selectionModel().setNoteSelection({m_rightHitId});
        showNoteMenu(event->position());
    } else if (insideTimeSelection(event->position().x())) {
        m_sv->showTimeSelectionMenu(event->globalPosition().toPoint());
    } else {
        m_sv->selectionModel().clearNoteSelection();
        m_sv->selectionModel().clearTimeSelection();
    }
    invalidateContent();
    completeProjectionGesture();   // NO stopNoteAudition on this path
}

void PianoRoll::releasePendingDrawClick(QMouseEvent *event)   // from :474-481
{
    if (insideTimeSelection(event->position().x()))
        m_sv->selectionModel().clearTimeSelection();
    m_sv->commitEditCursor(m_sv->snapTick(m_pressTick));
    invalidateContent();
    completeProjectionGesture();
    stopNoteAudition();   // unique tail order: invalidate -> complete -> stop
}

void PianoRoll::releasePendingVelocityClick(QMouseEvent *)   // from :485-505; no dragLive gate
{
    const NoteId id = m_velAnchor.noteId;
    if (m_velModMods & Qt::ControlModifier) {
        const auto &storedSelection = m_sv->selectionModel().noteSelection();
        std::vector<NoteId> ids(storedSelection.begin(), storedSelection.end());
        if (std::erase(ids, id) == 0)
            ids.push_back(id);
        m_sv->selectionModel().setNoteSelection(std::move(ids));
    } else if (m_velAnchor.track != m_sv->selectionModel().primaryTrack() ||
               !m_velAnchor.noteId.isAssigned() ||
               !m_sv->selectionModel().isNoteSelected(m_velAnchor.noteId)) {
        m_sv->selectionModel().setNoteSelection({id});
    }
    invalidateContent();
    completeProjectionGesture();
    stopNoteAudition();
}

void PianoRoll::armVelocityOneShot(const QMouseEvent *event,   // from :516-529
                                   SongView::VelocityCommitResult result)
{
    const bool modifierVelocityDrag = m_modifierVelocityDrag;
    m_modifierVelocityDrag = false;
    if (modifierVelocityDrag &&
        result == SongView::VelocityCommitResult::Committed &&
        keymap::Registry::instance().matchesModifier(
            event->modifiers(), QStringLiteral("roll.velocity_drag"))) {
        m_suppressNextVelocitySelectionAdd = true;
        m_lastModifierVelocityDragNote = m_velAnchor.noteId;
    }
}

void PianoRoll::commitDrawDrag()   // from :531-536
{
    SongDocument *doc = m_sv->document();
    if (!doc)
        return;
    const int selectedTrack = m_sv->selectionModel().primaryTrack();
    const std::vector<DocNote> before = doc->notesForTrack(selectedTrack);
    doc->addNote(selectedTrack, m_drawTick, uint8_t(m_drawKey), uint32_t(m_drawDur),
                 m_lastVelocity);
    m_sv->selectionModel().setNoteSelection(insertedNoteIds(selectedTrack, before));
}

void PianoRoll::commitMoveDrag()   // from :537-560
{
    SongDocument *doc = m_sv->document();
    if (!doc || (m_dTick == 0 && m_dKey == 0))
        return;
    std::vector<DocNote> notes = resolveSelection();
    if (notes.empty()) {
        m_sv->selectionModel().clearNoteSelection();
    } else if (m_sv->scaleFold() && m_dKey != 0) {
        std::vector<uint8_t> destinations;
        if (resolveFoldDestinations(m_sv->scaleId(), m_sv->scaleRoot(), notes, m_dKey,
                                    destinations) &&
            doc->moveNotesToPitches(notes, destinations, m_dTick)) {
            std::vector<NoteId> ids;
            ids.reserve(notes.size());
            for (const DocNote &note : notes)
                ids.push_back(note.noteId);
            m_sv->selectionModel().setNoteSelection(std::move(ids));
        }
    } else {
        doc->moveNotes(notes, m_dTick, m_dKey);
        std::vector<NoteId> ids;
        ids.reserve(notes.size());
        for (const DocNote &note : notes)
            ids.push_back(note.noteId);
        m_sv->selectionModel().setNoteSelection(std::move(ids));
    }
}

void PianoRoll::commitVelocityDrag(SongView::VelocityCommitResult result)   // from :522-523,566-568
{
    const bool velocityCommitted =
        result == SongView::VelocityCommitResult::Committed ||
        result == SongView::VelocityCommitResult::Unchanged;
    if (m_dVel != 0 && velocityCommitted)
        m_lastVelocity = uint8_t(std::clamp(int(m_velAnchor.velocity) + m_dVel, 1, 127));
}

void PianoRoll::commitDrag(QMouseEvent *event)   // from :515-576
{
    const LeftDrag drag = m_leftDrag;   // snapshot kind first
    clearLiveDragToken();               // before any commit; kills either channel
    SongView::VelocityCommitResult velocityResult = SongView::VelocityCommitResult::NoGesture;
    if (drag == LeftDrag::Velocity)
        velocityResult = m_sv->commitVelocityGesture();
    armVelocityOneShot(event, velocityResult);   // unconditional: consumes origin flag
    SongDocument *doc = m_sv->document();
    if (drag == LeftDrag::Draw) {
        commitDrawDrag();
    } else if (drag == LeftDrag::Move) {
        commitMoveDrag();
    } else if (doc && drag == LeftDrag::Resize && m_dDur != 0) {
        doc->resizeNotes(resolveSelection(), m_dDur);
    } else if (doc && drag == LeftDrag::ResizeLeft && m_dTick != 0) {
        const std::vector<DocNote> notes = resolveSelection();
        doc->resizeNotesLeft(notes, m_dTick);
    } else if (drag == LeftDrag::Velocity) {
        commitVelocityDrag(velocityResult);
    }
    stopNoteAudition();   // shared tail verbatim
    m_dTick = 0;
    m_dKey = 0;
    m_dDur = 0;
    m_dVel = 0;
    invalidateContent();
    completeProjectionGesture();
}
```

Sole sanctioned statement-order shift: `m_modifierVelocityDrag` is consumed by
`armVelocityOneShot` after `commitVelocityGesture()` instead of immediately
before; behavior-neutral (no other reader observes it between those points).

3. Replace `mouseReleaseEvent` (:426-577), delete the local completion lambda
   and release-local `doc`:

```cpp
void PianoRoll::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::MiddleButton && m_panning) {
        m_panning = false;
        setCursor(Qt::ArrowCursor);
        completeProjectionGesture();
        return;
    }
    if (m_kbdKey >= 0) {
        auditionKey(m_kbdKey, 0);   // falls through: any button ends kbd audition
        m_kbdKey = -1;
    }
    if (event->button() == Qt::RightButton && m_rightDrag != RightDrag::None) {
        releaseRightPress(event);
        return;
    }
    if (event->button() == Qt::LeftButton && m_leftDrag == LeftDrag::PendingDraw) {
        m_leftDrag = LeftDrag::None;
        if (!dragLive()) {
            releasePendingDrawClick(event);
            return;
        }
        // live right drag: fall through to commitDrag (clears the right token)
    }
    if (event->button() == Qt::LeftButton && m_leftDrag == LeftDrag::PendingVelocity) {
        m_leftDrag = LeftDrag::None;
        releasePendingVelocityClick(event);
        return;   // intentionally no dragLive gate/token clear
    }
    // catch-all stays LAST — the only projection guarantee for stray releases
    if (event->button() != Qt::LeftButton || !dragLive()) {
        if (event->button() != Qt::LeftButton && m_leftDrag == LeftDrag::Velocity)
            cancelVelocityInteraction();
        completeProjectionGesture();
        stopNoteAudition();
        return;
    }
    commitDrag(event);
}
```

`completeProjectionGesture` call-site switch list (all six current lambda
invocations): pan release (stays in router until Commit 5), :468 →
`releaseRightPress` tail, :480 → `releasePendingDrawClick`, :503 →
`releasePendingVelocityClick`, :510 → router catch-all, :576 → `commitDrag`
tail. Delete the lambda definition.

Acceptance: rollcheck green; compile confirms `SongView::VelocityCommitResult`
is nameable from `pianoroll.h`; release-order trace of the five
`stopNoteAudition` orderings.

---

## Commit 5 — Peripherals + file split (agent: `task`)

Suggested message: `Extract PianoRoll overlays, move beginDraw, split gesture files`

1. Overlay helpers in the interaction file (decls beside audition primitives):

```cpp
void PianoRoll::updateHoverKey(const QMouseEvent *event)   // from :216-219
{
    setHoverKey(m_leftDrag == LeftDrag::Velocity ? m_velAnchor.key
                                                 : yToKey(event->position().y()));
}

void PianoRoll::panMove(const QMouseEvent *event)   // from :220-226
{
    const QPointF d = event->globalPosition() - m_panPos;
    m_panPos = event->globalPosition();
    m_sv->scrollByPx(-d.x());
    m_sv->scrollRollBy(-d.y());
}

void PianoRoll::kbdGlissandoMove(const QMouseEvent *event)   // from :227-237
{
    const int key = yToKey(event->position().y());
    if (key != m_kbdKey) {
        m_kbdKey = key;
        auditionKey(m_kbdKey, 100);
    }
}

void PianoRoll::endPanGesture()   // from :432-437
{
    m_panning = false;
    setCursor(Qt::ArrowCursor);
    completeProjectionGesture();
}

void PianoRoll::endKbdAudition()   // from :438-441
{
    auditionKey(m_kbdKey, 0);
    m_kbdKey = -1;
}
```

Router substitutions: `updateHoverKey(event)` first line; `panMove(event)` /
`kbdGlissandoMove(event)` replacing inline bodies; `endPanGesture()` /
`endKbdAudition()` in the release router (pan branch still returns; kbd falls through).

2. Move `beginDraw()` from `pianoroll_commands.cpp:129-153` to the gestures
   file, changing ONLY `m_drag = Drag::Draw;` → `activateLeftDrag(LeftDrag::Draw);`.
   Body otherwise verbatim (fold guard early-return, anchor/tick/dur/key setup,
   selection clear, pending-note announce, `m_soundingKey != m_drawKey`
   no-re-attack audition, invalidate). Move the `beginDraw` declaration into
   the gesture block. Exactly two call sites remain: `mouseDoubleClickEvent`
   and `resolveDrawPress`.

3. `pianoroll.cpp` translations:

```cpp
// gestureActive() — quirk preserved (PendingVelocity omitted)
return m_panning || dragLive() || m_leftDrag == LeftDrag::PendingDraw ||
       m_rightDrag != RightDrag::None || m_kbdKey >= 0 ||
       (m_bendPopup && m_bendPopup->isVisible());

// cancelVelocityInteraction() — both resets required
if (m_leftDrag != LeftDrag::Velocity && m_leftDrag != LeftDrag::PendingVelocity)
    return;
clearLiveDragToken();      // translates old m_drag = None (incl. right demotion)
m_leftDrag = LeftDrag::None;   // translates old m_velModPress = false
// ... remaining payload resets and m_sv->cancelVelocityGesture() verbatim

// event() UngrabMouse/focus-loss guard
if ((losesFocus || type == QEvent::UngrabMouse) &&
    (m_leftDrag == LeftDrag::Velocity || m_leftDrag == LeftDrag::PendingVelocity))
    cancelVelocityInteraction();
```

4. `pianoroll_commands.cpp`: Escape arm → `cancelVelocityInteraction();
   m_leftDrag = LeftDrag::None; m_rightDrag = RightDrag::None;` + existing
   band/selection/invalidate lines (pan/kbd overlays NOT cleared — quirk);
   keyRelease audition guard → `!event->isAutoRepeat() && !dragLive()`.

5. Geometry/paint guards per Commit 1 table (already translated; verify no
   regression). Essential paint invariant: Band reticle and `m_bandAud` ring
   both require active `RightDrag::Band` — after demotion to PendingMenu the
   stale payload must not paint.

6. File split at the arm-vs-actuate seam (predicted gestures file is 540-570
   LOC without it):
   - `pianoroll_gestures.cpp`: interlock helpers, `begin*`/`pressContent`/
     `applyNotePressSelection`/`armNoteDrag`/`notesOnKey`/`resolve*`/
     `applyModifierVelocitySelection`/`beginDraw` (~285-315 LOC)
   - `pianoroll_gestures_active.cpp`: `update*`/`drawSpanAt`/`release*`/
     `commit*`/`armVelocityOneShot`/`completeProjectionGesture` (~250-280 LOC)
   - Register the new file in `CMakeLists.txt` beside `pianoroll_gestures.cpp`.

Acceptance: zero legacy-state names across `pianoroll*.{h,cpp}`; both gesture
files nameable in one sentence (arming vs. actuation) with every leaf
CCN ≤ 7 — the 200-400 band is the expected consequence of a clean seam, not
the criterion; rollcheck green.

---

## Commit 6 — Verification (agents: `task` implements, `reviewer` audits)

Suggested message: `checks: add PianoRoll multi-button interlock scenarios`

No new harness and no `eventsynth` change needed:
`checks::events::sendMouse` already takes transition button and held-button
mask separately and sends synchronous `QMouseEvent`
(`src/checks/support/eventsynth.h:12-14`).

Files:
- New `src/checks/rollcheck/interlock.cpp` — `runGestureInterlockScenarios(Harness&, const PencilVelocityFixture&)`, scenarios A-D below.
- `src/checks/rollcheck/rollcheck.h:117-123` — declaration beside `runSelectionGestureScenarios`.
- `src/checks/rollcheck.cpp:68-78` — call after `runPencilVelocityScenarios`, before selection topics.
- `CMakeLists.txt:406-422` — add `interlock.cpp` to `porydaw_checks`.

Common pattern per scenario: clear note/time selection; capture
`doc.smf().write()`, `undoStack()->index()`, `undoStack()->count()` before;
assert all three unchanged after (catches accidental edits AND empty undo
commands). Band geometry adapted from `selection.cpp:24-57`
(`bandStart = (pianoKeyboardWidth+1, 0)`, `bandEnd` beyond note cells,
`bandWarmup` = bandStart + (startDragDistance+1, 0)).

Event-mask rule: `button` = transitioned button, `buttons` = post-transition
held mask. Right release while left held = `(RightButton, LeftButton)`.

- **Scenario A (rules 1+3)** — live left Move blocks right activation; right
  release resolves as empty-space click and aborts Move uncommitted.
  Left-press note A → left-move one row (stages nonzero pitch delta) →
  right-press bandStart (both held) → both-held move to bandEnd → right
  release (left held): assert selection empty + time selection inactive →
  left release: assert SMF bytes + undo index/count unchanged.
- **Scenario B (rule 2)** — left activation demotes live right Band.
  Right-press → right-move to bandWarmup (Band live) → left-press note A
  (both held) → both-held move beyond note B → right release (left held):
  assert selection empty (Band was demoted, resolved as plain clear) → left
  release: document unchanged.
- **Scenario C (rule 1 pending exception)** — PendingDraw does not block right
  resolution. Left-press free cell (no move; PendingDraw) → right-press
  (both) → both-held move to bandEnd (right resolves to Band; draw never
  activates) → right release (left held): assert A and B both in selection
  (containment, not exact size) → left release at the free cell (park-cursor
  path): A/B still selected → document unchanged.
- **Scenario D (rule 4 observable case)** — deferred modifier-click release
  does NOT clear the live right token. Right-press → right-move to bandWarmup
  (Band live) → Ctrl-left-press note B center (PendingVelocity; both held) →
  Ctrl-left release in place (right still held): assert selection exactly
  `{noteB.noteId}` → right-move beyond note A → right release: assert A and B
  both selected (proves the token survived the modifier click).

Edge-case notes for the implementer: clear time selection before A/B (else
`insideTimeSelection` legitimately routes to a menu); do not open `QMenu`;
use `beyond(origin, target)` re-anchoring because later left presses overwrite
`m_pressPos`; release every synthetic held button; no `processEvents()` needed.
Do NOT test PendingDraw release preserving a live right token — normative
dispatch clears it via the commitDrag fall-through; PendingVelocity is the
observable survival case.

### Verification sequence

```sh
# after each of commits 1-6:
deno task verify --filter rollcheck

# after commit 6 — complexity acceptance:
lizard src/ui/songview/pianoroll_interaction.cpp \
       src/ui/songview/pianoroll_gestures.cpp \
       src/ui/songview/pianoroll_gestures_active.cpp
lizard -C 8 -w src/ui/songview/pianoroll_interaction.cpp
lizard -C 7 -w src/ui/songview/pianoroll_gestures.cpp \
             src/ui/songview/pianoroll_gestures_active.cpp
# acceptance: mouseMoveEvent CCN <= 8; all gesture leaves <= 7; warning runs empty

deno task verify   # full gate, final
```

---

## Execution notes

- Each commit is dispatched to one `task` subagent with its section above as
  the complete spec; a `reviewer` subagent audits the diff against the
  invariants list before the gate runs. Commit 1 first and alone (it defines
  the translation the later commits assume).
- Line anchors are pre-refactor; each implementer re-reads the current file
  and matches by symbol/expression, not blindly by line number.
- No behavior changes anywhere in the sequence; the two documented
  behavior-adjacent decisions (PendingDraw+live-right fall-through,
  armVelocityOneShot flag-consumption timing) are intentional and preserved.
