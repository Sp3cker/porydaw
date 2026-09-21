# Task 7 — Accept the complete production drawer

## Context

Follow all [Global Constraints](plan.md#global-constraints), [Focus, commands, and lifetime](spec.md#focus-commands-and-lifetime), and [Verification ownership and parity ledger](spec.md#verification-ownership-and-parity-ledger).

This is an acceptance/integration task, not permission for a cleanup rewrite. Tasks 3–6b must already be reviewed/checkpointed, except explicitly approval-gated capability blockers carried forward in their results. Verify the normal production app with real project content, all three pages mounted, one shared playhead, production input/lifetime, exact visual profiles, complete translated coverage, and honest residual accounting.

## Exact write set

Expected production source write set: none.

Permitted only when evidence exposes a defect:

- the owning task's existing Swift/QML/check files, changed by one bounded fix dispatch and reviewed against the owning contract;
- `src/checks/fixtures/visual/macos-dpr1-font12/quick/vanilla/`, `macos-dpr1-font16/quick/vanilla/`, `macos-dpr2-font12/quick/vanilla/`, and `macos-dpr2-font16/quick/vanilla/`: update/add only grounded pane PNG/JSON baselines named below;
- existing coverage/exclusion ledger file(s), but only to replace each reopened row with exact Swift/QML evidence or leave it explicitly open. Do not create a second ledger.

Capture artifacts for handoff belong in the harness artifact/scratch output, not an untracked repository report. Do not modify unrelated planning files or sibling worktree assets.

## Prerequisites

- Tasks 3, 4 independent surface, 5 independent surface, 6a, and 6b have clean task reviews and pushed checkpoints.
- Any unresolved Velocity keysplit/drumkit context or Voice Changes arbitrary audition blocker is explicitly carried with exact missing native contract and affected scenarios.
- Existing normal app launch, Swift/QML checks, native window checks, and macOS window capture capability are available.

## Interface contract

### Production scenario

Launch the normal production app, not a fixture-only component. Open a staged real project/song through `ApplicationSession`. Confirm all three attached pages are available and can be shown together through production drawer chrome. Use representative content that visibly exercises:

- Velocity: selected/unselected notes, multiple values, labels/readout, prompt;
- Voice Changes: multiple markers/slots, current context, picker, menu;
- Automation: at least volume/pan/tempo plus another CC/XCMD where the fixture supports it, selected points, curve types, tabs, prompt/menu/tap-tempo; and
- shared playhead: roll plus every visible drawer body at one aligned x.

Exercise pointer edit, keyboard/accessibility activation where the harness exposes it, selection, prompt accept/cancel, menu dismiss/commit, Undo/Redo, play/pause/stop/seek, loop wrap, track change, section resize/hide/show, follow-scroll suspension/resume, and project/song replacement. Confirm no stale prompt, audition, pointer grab, preview, follow suspension, or page callback survives replacement/close.

### Visual/reference evidence

Ground every baseline against the sibling production/reference authority before updating it. Required checked/reference profiles:

- `velocity-lane` and `editor-drawer`: DPR 1/2 at font 12/16;
- `velocity-prompt`, `voice-picker`, and `automation-tabs`: DPR 2 at font 12/16; and
- any additional page baseline introduced by earlier task review.

For each JSON metadata file record exact logical size, DPR, font, palette/theme, fixture/content identity, and production component path. PNG and JSON must describe the same capture. Use offscreen deterministic captures only for the profile matrix; label them as such. Separately capture the actual normal production macOS window at its physical DPR. Never claim an offscreen DPR value proves OS/physical-DPR behavior.

Reject clipped text, gutter/playhead misalignment, mismatched font metrics, hard-coded-pixel drift, stale hover/selection, incorrect prompt/menu modality, blank pages, or fixture-only rendering.

### Performance/lifetime evidence

Record observable counters before/after at least 128 authoritative playhead positions while all pages are visible. Static grid/Velocity/Voice/Automation content-build counters must not change unless an effective semantic context boundary requires the documented page update. Presentation counters must advance. Confirm one polling task and no update after acknowledged retirement.

Exercise document replacement while each page has an active provisional interaction/modal state. Cancellation must precede detach, owners remain alive through host acknowledgment, and the replacement receives no old callback.

### Coverage/exclusion accounting

Produce an exact mapping in the task result (not a new repository report) from legacy behavior categories/previous exclusions to:

- direct Swift check ID;
- editor-QML production case;
- native-window case where required; and
- reference image/profile where visual.

Reassess all ten prior absent-UI exclusions individually. The five Automation rows named in task 6a close only with semantic and mounted-input evidence. Voicegroup-save rows remain separate scope. Four native MIME clipboard gaps remain separate unless independently implemented and verified. Capability blockers remain open with exact costs; a passing smaller manifest never closes them.

## Implementation steps

1. Read the `verify` and `capture-macos-app-window` skills and use their production-safe procedures.
2. Run focused suites first and resolve any introduced failure through the owning task's bounded fix/review path.
3. Generate/compare the deterministic reference profile matrix from production components.
4. Launch and exercise the normal production app, capture the actual window with every pane, and record exact observed state.
5. Run the complete verification suite once after focused evidence is clean.
6. Package final evidence and exclusion/blocker mapping for the independent whole-branch review. Do not add a documentation/report file.

## Acceptance predicate

- normal production app mounts and operates all three Swift/QML pages with one shared camera, playhead, document, history, and audio sample authority;
- real input, selection, editing, prompts, commands, audition where capability exists, preferences, cancellation, Undo/Redo, mounting/routing, replacement, and close paths are exercised end to end;
- shared playhead aligns across roll/all visible bodies and avoids content rebuilds over the performance sequence;
- deterministic references match the exact required font/DPR profiles and an actual production-window capture proves the physical surface available on this workstation;
- translated coverage has no C++ scenario body hidden behind a Swift launcher;
- ten absent-UI exclusions and four native MIME gaps are individually accounted;
- every introduced check passes, then the full suite passes; and
- independent final whole-branch review reports both spec compliance and quality with no open Critical/Important finding.

Exact verification:

```bash
deno task build:app
deno task verify --filter swiftcore --verbose --qt projectSession
deno task verify:qml --filter editorqml-drawer --verbose
deno task verify --filter swiftrollgated --verbose
deno task verify
```

Normal-app launch/capture uses the repository's supported launch path from the `verify` skill and the window-capture skill; record the exact commands/tool outcomes in the result.

If approval-gated Velocity keysplit context or Voice Changes arbitrary audition remains unavailable, this task cannot claim the corresponding full-page acceptance. Complete every independent verification/capture, mark the milestone `BLOCKED` only on those exact capabilities, and report the smallest missing native contracts. Do not hide, fake, or narrow them.

## Task-specific constraints

- No broad refactor or opportunistic cleanup.
- No baseline update to make a wrong rendering pass; fix source first.
- No offscreen-as-physical-DPR claim.
- No new report/check lane/C++/QtBridge infrastructure.
- No closure of unrelated voicegroup-save or native MIME gaps.
- Do not touch unrelated dirty planning documents or `.scratch/`.
- Return exact commands/outcomes, production capture artifact paths, reference-profile matrix, performance counters, lifecycle observations, coverage/exclusion mapping, blockers, and review disposition.