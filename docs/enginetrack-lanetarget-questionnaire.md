# EngineTrack / LaneTarget questionnaire

Review in place. Reply `Q1=A Q2=A …` or mark exceptions. No implementation until sign-off.

## Locked

| # | Decision |
|---|---|
| Scope | Piles 1+2 only. Type engine-track APIs so they cannot take `-1`, and stop encoding tempo/global as `track = -1`. Lookup returns (`smfTrackFor`, remap tables, `previewTrack`, `firstProgram`, `freeChannel`) stay `-1` this pass. |
| Tempo | One core tagged `LaneTarget`. Do not discriminate tempo with `track < 0`. |

## Pile map

**Pile 1 — defensive `if (track < 0 \|\| track > 15)`.** The callee never wants `-1`. Garbage `int` from Qt/engine/restore.

**Pile 2 — `-1` is the payload.** Tempo/global. Paste and remap branch on it.

**Pile 3 — out of scope.** `-1` as a *return* (no chunk, deleted in remap table, nothing sounding).

---

### Q1 — `EngineTrack` representation

There is no such type today. These `int track` APIs would take it.

**Defensive guards (never want `-1`):**

| Guard | Location |
|---|---|
| `revealNote` | `src/ui/songview/trackvoiceops.cpp:49` |
| `trackHeaderClicked` | `src/ui/songview/trackvoiceops.cpp:69` |
| `revealTrackVoice` | `src/ui/songview/trackvoiceops.cpp:251` |
| `editTrackVoice` | `src/ui/songview/trackvoiceops.cpp:285` |
| `renameTrack` | `src/ui/songview/trackvoiceops.cpp:308` |
| `commitTrackRename` | `src/ui/songview/trackvoiceops.cpp:314` |
| `duplicateTrack` | `src/ui/songview/trackvoiceops.cpp:348` |
| `deleteTrack` | `src/ui/songview/trackvoiceops.cpp:358` |
| `applyPrimaryTrackTransition` | `src/ui/songview/editorselectionmodel.cpp:138` |
| `timeSelectionCoversTrack` | `src/ui/songview/editorselectionmodel.cpp:32-33` |
| `addEmptyLane` | `src/ui/songview/viewstate.cpp:208` |
| `setLaneDisplayRange` | `src/ui/songview/viewstate.cpp:222` |
| `TrackActivity::intensity` | `src/ui/activity/trackactivity.cpp:86` |
| `AuditionSlots::apply` | `src/audio/auditionslots.cpp:100` |
| `voiceContext` on `primaryTrack()` | `src/ui/songview/trackvoiceops.cpp:227` |

**No guard — UB if out of range:**

```234:235:src/ui/songview.h
    bool trackMuted(int track) const { return m_muteMask & (1u << track); }
    bool trackSoloed(int track) const { return m_soloMask & (1u << track); }
```

`removeEmptyLane` (`src/ui/songview/viewstate.cpp:214-218`) also has no range check; `addEmptyLane` does.

| | Option | Notes |
|---|---|---|
| **A** | `struct EngineTrack { uint8_t index; }` | No implicit `int`. `from(int) → optional` at edges. **Recommended.** |
| B | `uint8_t` | Kills `< 0`, not `16…255`. `1u << track` / `array[track]` still need a check. |
| C | `unsigned` + `assert` | No new type. The `if`s return at every array index. |
| D | `enum class` `T0…T15` | Illegal states unrepresentable; cannot increment/loop without pain. |

**Recommended: A.**

---

### Q2 — Where `EngineTrack` lives

Constants already disagree:

- `kMaxTracks` — `src/audio/trackactivitylevel.h:8`
- `kMaxEngineTracks` — `src/core/midiimport.cpp:12`
- `MAX_TRACKS` — poryaaaa; `static_assert(kMaxTracks == MAX_TRACKS)` at `src/audio/audioengine.h:23`

| | Option | Notes |
|---|---|---|
| **A** | New `src/core/enginetrack.h` | Core owns the 0–15 slot. Audio `static_assert`s against it. **Recommended.** |
| B | Put it in `trackactivitylevel.h` | Wrong module: meters. |
| C | Header-only next to `DOC_CC_*` in `songdocument.h` | That file is already huge. |

**Recommended: A.** One concept, one small file. Do not relocate `kMaxTracks` this pass; `static_assert(EngineTrack::kCount == kMaxTracks)`.

---

### Q3 — `LaneTarget` shape

Tempo is identified by flattening a kind to `-1`.

Drawer already has a kind, then throws it away:

```17:28:src/ui/editorviewstate.h
enum class EditorAutomationRowKind : uint8_t { Tempo, Voice, ControlChange };
struct EditorAutomationRowId {
    EditorAutomationRowKind kind = ...;
    uint8_t track = 0;
    uint8_t controller = 0;
};
```

```225:228:src/ui/editordrawer/automationrows.cpp
    if (row.id.kind == EditorAutomationRowKind::Tempo)
        return {-1, DOC_CC_TEMPO};
```

That pair is stored as:

```24:24:src/ui/songview/editorselectionmodel.h
        std::vector<std::pair<int, uint8_t>> lanes;
```

Clipboard:

```454:456:src/ui/songview.h
    struct ClipLane {
        int track; // source engine track; -1 = tempo
        uint8_t cc;
```

Document contract:

```205:216:src/core/songdocument.h
    // an engineTrack of -1 targets the tempo lane (DOC_CC_TEMPO only).
        struct LaneWrite {
            int engineTrack; // -1 = tempo (seq chunk)
```

Same encoding in:

- `TimeScope::lanes` — `src/core/songdocument.h:263`
- `LanePointMove::engineTrack` — `src/core/songdocument.h:192`
- `AutomationLaneEdit::Target` — `src/ui/editordrawer/automationlaneedit.h:13-15`
- `TimeEditor::LaneIdentity` — `src/core/songdocument_time.cpp:55-57`

Document already keys tempo by `cc == DOC_CC_TEMPO` and writes SMF chunk 0 (`src/core/songdocument.cpp:1318`, `:1343`, `:1559`). The `-1` exists so paste/remap will not treat tempo as “retarget to selected track”:

```354:366:src/ui/songview/rangeedit.cpp
        if (track < 0)
            return; // tempo is global
        return track < 0 ? -1 : (multi ? track : m_selectionModel.primaryTrack());
```

```427:429:src/ui/songview/trackvoiceops.cpp
        const int destination = lane.track < 0 ? lane.track : remapTrack(lane.track);
        if (destination >= 0 || lane.track < 0)
```

| | Option | Notes |
|---|---|---|
| **A** | Factories, no dummy track on tempo | See sketch below. **Recommended.** |
| B | `{ kind, EngineTrack track, uint8_t cc }` | `track` unused when `kind == Tempo`. Today’s `EditorAutomationRowId` bug, in core. |
| C | `std::variant<Tempo, TrackLane>` | Correct, heavier at every call site. |
| D | Reuse `EditorAutomationRowId` inside `SongDocument` | UI type in core. |

Sketch for A:

```cpp
struct LaneTarget {
    static LaneTarget tempo();
    static LaneTarget voice(EngineTrack);
    static LaneTarget controlChange(EngineTrack, uint8_t cc);
    bool isTempo() const;
    std::optional<EngineTrack> track() const; // nullopt iff tempo
    uint8_t cc() const;                       // DOC_CC_TEMPO / VOICE / n
};
```

**Recommended: A.** Kind is explicit; tempo cannot accidentally carry track 3.

---

### Q4 — Where `LaneTarget` lives

| | Option | Notes |
|---|---|---|
| **A** | Same `src/core/enginetrack.h`, or `src/core/lanetarget.h` if the file grows | **Recommended.** |
| B | Nested in `SongDocument` | Hides a type other modules need. |
| C | UI-only; keep `RangeEdit.engineTrack = -1` | UI `LaneTarget` gets flattened again at `applyRangeEdit`. |

**Recommended: A.** `RangeEdit` is the core twin of `ClipLane`.

---

### Q5 — How far into `SongDocument` this pass

`addNote` / `notesForTrack` / `lanePoints` / `duplicateTrack` take `int engineTrack` and do **not** use `-1` as tempo. They use `smfTrackFor` → `-1` as “no chunk” (`src/core/songdocument.cpp:504-508`, comment at `src/core/songdocument.h:424`). That return is pile 3.

| | Option | Notes |
|---|---|---|
| **A** | `EngineTrack` on every parameter that means “0–15 slot”; `LaneTarget` on every field that means “slot OR tempo” | `RangeEdit::LaneWrite`, `LanePointMove`, `TimeScope::lanes`, `TimeEditor::LaneIdentity`. Lookup *returns* stay `int` / `-1`. **Recommended.** |
| B | UI + clipboard + `RangeEdit` only | `addNote(int)` stays. Second `int` dialect. |
| C | Also replace `smfTrackFor` / remap maps / `DocNote::engineTrack = -1` | Different project (`previewTrack`, `firstProgram`, `freeChannel`, `OtherEvent.track` at `src/core/miditimeline.h:56`). |

**Recommended: A.**

---

### Q6 — Time-selection lane pairs

```24:24:src/ui/songview/editorselectionmodel.h
        std::vector<std::pair<int, uint8_t>> lanes;
```

```263:263:src/core/songdocument.h
        std::vector<std::pair<int, uint8_t>> lanes; // (engineTrack, cc); -1 = tempo
```

`AutomationRows::rowIdentity` is the only producer of the `-1` pair (`src/ui/editordrawer/automationrows.cpp:225-228`). `rowTarget` then throws tempo’s kind away and substitutes `primaryTrack()` so `lanePoints` can be called (`:218-221`).

| | Option | Notes |
|---|---|---|
| **A** | `vector<LaneTarget>` in both selection and `TimeScope` | **Recommended.** |
| B | Keep the pair; only change `ClipLane` | `-1` pair remains a producer. |
| C | Selection uses `EditorAutomationRowId`; convert to `LaneTarget` at the document edge | Two tagged ids. |

**Recommended: A.** One type.

---

### Q7 — Qt / engine edges stay `int`?

Untrusted `int` sources that must parse once:

```64:64:src/ui/polyphonypanel.h
    void jumpToEvent(uint64_t tick, int track, int midiKey);
```

```602:602:src/mainwindow.cpp
                m_active->view->revealNote(track, uint8_t(midiKey), tick);
```

From `QVariant::toInt()` of `ev.trackIndex` at `src/ui/polyphonypanel.cpp:451,506`.

Also: `selectedTrackChanged(int)` (`src/ui/songview.h:531`), `auditionNote(int track, …)` (`:537`), restore `selectTrack(state.selectedTrack)` (`src/ui/songview.cpp:417`).

| | Option | Notes |
|---|---|---|
| **A** | Signals stay `int` (MOC). `EngineTrack::from` at the slot / `connect`. Invalid → no-op | **Recommended.** |
| B | Change signals to `EngineTrack` | Awkward with Qt meta-types. |
| C | Change signals to `uint8_t` and hope | `16…255` still compile. |

**Recommended: A.**

---

### Q8 — Remap tables this pass

```42:43:src/core/songdocument.h
    std::vector<int> smfTrackMap;
    std::vector<int> engineTrackMap;
```

Filled with `-1`, then some slots get a destination (`src/core/songdocument.cpp:370-371`, `:457-471`). `mappedTrack` in selection (`src/ui/songview/editorselectionmodel.cpp:286-290`) and clip remap (`src/ui/songview/trackvoiceops.cpp:428`) treat `-1` as deleted.

| | Option | Notes |
|---|---|---|
| **A** | Tables stay `vector<int>` with `-1` = gone | Callers that already have `EngineTrack` do `optional<EngineTrack> remap(EngineTrack)`. Tempo is `LaneTarget::isTempo()`, not `track < 0`. **Recommended.** |
| B | `vector<optional<EngineTrack>>` now | Pile 3. |
| C | Leave clip remap as `if (lane.track < 0)` | Does not delete the paste/remap `if`s. |

**Recommended: A.** Table encoding is pile 3. The `if (track < 0)` on clips goes away because tempo is no longer in `track`.

---

### Q9 — `primaryTrack()` return type

```49:49:src/ui/songview/editorselectionmodel.h
    int primaryTrack() const noexcept { return m_primaryTrack; }
```

Defaults to `0` (`src/ui/songview/editorselectionmodel.h:81`). Setter rejects `< 0` (`src/ui/songview/editorselectionmodel.cpp:138`). These checks are dead against that invariant:

- `src/ui/editordrawer/automationarea.cpp:1004,1153`
- `src/ui/editordrawer/automationhover.cpp:84`
- `src/ui/editordrawer/automationrows.cpp:63`
- `src/ui/songview/trackvoiceops.cpp:227`

| | Option | Notes |
|---|---|---|
| **A** | Return `EngineTrack`. Dead `< 0` checks deleted | **Recommended.** |
| B | Keep `int`, only change setters | Every drawer call reintroduces `int`. |

**Recommended: A.**

---

### Q10 — `ClipTrack.track`

```450:452:src/ui/songview.h
    struct ClipTrack {
        int track; // source engine track
        std::vector<ClipNote> notes;
```

Notes are never tempo. `-1` here would be a bug.

| | Option | Notes |
|---|---|---|
| **A** | `EngineTrack track` | **Recommended.** |
| B | Leave `int` | |

**Recommended: A.**

---

### Q11 — Implementation order

| | Option | Notes |
|---|---|---|
| **A** | Types → `RangeEdit` / `TimeScope` / `ClipLane` / `ClipTrack` → selection lanes → SongView / selection / activity / audition signatures → parse at Qt edges → delete the Q1 `if (track < 0 \|\| …)` list | **Recommended.** |
| B | Types + SongView only; leave `RangeEdit.engineTrack = -1` | Does not delete the paste/remap `if (track < 0)`s. |
| C | One giant change including pile 3 | Different project. |

**Recommended: A.**

---

## Answer sheet

```
Q1  EngineTrack representation     [ ] A  [ ] B  [ ] C  [ ] D     rec A
Q2  EngineTrack file               [ ] A  [ ] B  [ ] C            rec A
Q3  LaneTarget shape               [ ] A  [ ] B  [ ] C  [ ] D     rec A
Q4  LaneTarget file                [ ] A  [ ] B  [ ] C            rec A
Q5  SongDocument depth             [ ] A  [ ] B  [ ] C            rec A
Q6  Time-selection lane pairs      [ ] A  [ ] B  [ ] C            rec A
Q7  Qt / engine edges              [ ] A  [ ] B  [ ] C            rec A
Q8  Remap tables                   [ ] A  [ ] B  [ ] C            rec A
Q9  primaryTrack() return          [ ] A  [ ] B                   rec A
Q10 ClipTrack.track                [ ] A  [ ] B                   rec A
Q11 Implementation order           [ ] A  [ ] B  [ ] C            rec A
```
