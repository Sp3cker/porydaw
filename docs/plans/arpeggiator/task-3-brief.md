# Context
Build the real arpeggiator QML surface with the control arrangement specified in plan.md, not a generic form. Controller owns presenter/registration/contextual menu wiring. Read plan.md Global Constraints and presenter/QML interface first. Selector controls must use separate left-hand toggles and right-hand labels. No visual MIDI-note preview.

# Exact write set
- src/ui/songview/quick/ArpeggiatorPanel.qml (new)
- src/ui/songview/quick/ArpeggiatorKnob.qml (new, if needed)
- src/ui/songview/quick/ArpeggiatorStepPad.qml (new, if needed)

# Prerequisites
Presenter interface frozen in plan.md; implementation may proceed before presenter exists. Controller supplies loader, focusOrigin and registered App.ArpeggiatorPresenter.

# Interface contract
ArpeggiatorPanel is a production PromptOverlay with `required property App.ArpeggiatorPresenter model`, inherited required focusOrigin, optional App.MouseHints hintService. Bind overlayOpen to model.isOpen; dismiss calls model.close(). All controls call fixed presenter methods in plan.md. The two helper controls take theme/style/font-derived geometry and emit edits, no business generation logic.

# Implementation steps
1. Read skill://qt-qml, skill://qt-ui-design, rule://text-contrast, existing VelocityPrompt.qml/PromptOverlay/PromptCard/PromptButton and Dial or numeric controls. Reuse appearance patterns. No alternate palette/token system.
2. Lay out like reference: left Master/Transpose/Accent knobs; central Rate+Trigger, Mode six vertically stacked toggle/label rows, Octave four rows, Insert three rows and Custom text display beneath; right Shuffle/Gate/Steps knobs and audition toggle. Every selector has a small rectangular active toggle on the left and a separate plain label on the right, never full-width label-button chrome. Bottom 32 numbered pads in 2x16 grid. Maintain these spatial relationships at font-derived size; don't substitute dropdowns for mode/octave/insert columns. Rate quick selectors 1/8,1/16,1/32 plus More rate choice including all rateLabels. Keyboard trigger maps to restartOnNoteOn with explanatory accessible text.
3. Add compact source/loop heading, status and footer Copy Notes / Reshuffle / Close. Do not add a MIDI-note preview strip or model. Visually distinct active, disabled, accented and playing pads (accent marker not color alone). Left click toggle; right click or Shift+left toggle accent. Keyboard Return toggles, Shift+Return accent; full keyboard navigation; drag/wheel/typed values for knobs where existing controls permit. Escape closes, no accidental normal song Space command while editing modal.
4. Use exact palette pairs for text including selected/pressed text, numeric readouts, visible focus and accessible names/descriptions. No raw color literals, source-frame per-tick formatting, Canvas animation, proprietary logos/art assets, or hardcoded pixel geometry. Keep all named features functional. QML primitives okay for static decorative knob face; use Qt control mechanics for interaction.
5. Read-only local syntax/diagnostic inspection; report visual assumptions. Controller handles all registration and runtime proof.

# Acceptance predicate
Production surface preserves reference arrangement and separate toggle/label selectors, every named control is reachable by pointer and keyboard, pads distinguish on/off/accent/play, Copy Notes reflects the generated snapshot, and all text uses theme-correct pairs. No visual MIDI-note preview. NAMED CHECKS: controller `uv run --no-sync dev checks:shell --release --filter shell-arpeggiator`, `uv run --no-sync dev checks:shell --release --filter shell-text-contrast`, `uv run --no-sync dev checks:qml-aot --release`, and visible production screenshot.

# Task-specific constraints
SHARED_TREE: do not run build/test/format/lint; report DEFERRED_TO_CONTROLLER. No edits outside exact write set, no JS musical logic or mock presenter. Do not register files; controller owns CMake. Geometry derives from model.baseFontPx, existing style dimensions and measured text. Follow existing style if control wrapper differs from stock Qt. No commits or report files.
