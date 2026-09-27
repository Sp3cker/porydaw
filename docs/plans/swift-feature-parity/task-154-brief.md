# Task 154 brief — the header voice picker filters, reveals and cancels on the mounted roll

# Context

Complete the mounted header voice-picker consumer rather than stopping at the existing request signal. `tst_SwiftRollWindowing.qml::test_headerSelectionAndVoiceRequest` currently double-clicks the header but cancels by directly calling `completeTrackHeaderVoiceRequest(-1)`. The production loader in `EditorSurfacePrompts.qml` actually mounts `VoicePickerPrompt` with `HeaderVoicePicker`. Prove the fork's visible prompt/list, initial search focus, program-127 filtering, no-match refusal, cleared-filter row and Escape path on that exact surface. The drawer's separate `VoicePicker.qml` is not this owner.

Selected **7 GAP rows** in `src/checks/nativegraphics/proof.tst_nativewindowing.txt`, at `fceecd88:src/checks/nativegraphics/tst_nativewindowing.cpp`:

| Target A-ids | Fork assertion-start lines / clause |
|---|---|
| A030–A032 | 246,247,248 — visible picker/list and active search focus |
| A033–A036 | 251,255,258,261 — program 127, unmatched filter disables acceptance, clear reveals 0, Escape closes |

No selected row is setup-only. The surrounding fresh-rig and geometry guards remain setup, outside this selection. QQuick/QWidget pointer identity and popup-session internals do not port, but every selected visible/input outcome does; do not retire them wholesale as native-only.

# Exact write set

- `src/swift/app/headers/HeaderVoicePicker.swift` — filter, selection, open/close publication only, conditional repair.
- `src/ui/songview/quick/VoicePickerPrompt.qml` — search/list reveal, acceptance gating and Escape only, conditional repair.
- `src/checks/rollqml/tst_SwiftRollWindowing.qml`
- `src/checks/nativegraphics/proof.tst_nativewindowing.txt` — A030–A036 only.

# Prerequisites

Existing track-header voice-request and prompt-loader contracts are consumed unchanged. No dependency on Task146's shell keyboard/voicegroup/clipboard files, and no host-ledger edits. Read sprint-3 §17 for common constraints and native desktop requirements.

# Interface contract

Preserve `HeaderVoicePicker.open(track:)`, `setPickerFilter(text:)`, `acceptPicker() -> Bool`, `cancelPicker()`, and the QtBridge-visible `pickerOpen`, `pickerRows`, `pickerIndex`, `pickerHasMatch` state. `VoicePickerPrompt` remains the existing mounted presentation; do not mount a duplicate in the check.

After selecting an alternate track and double-clicking its actual header voice line, the prompt and list are effectively visible and the real `voicePickerSearch` owns focus. Type `127` through that control and require program-127's delegate visible in the list viewport (not merely present in the model). Replace it with `zz-no-such-voice` and require the mounted acceptance control disabled; pressing Return must neither mutate the document nor close the prompt. Clear the filter through actual text input and require program 0 visible, matching the fork's reset behavior. Press Escape in the prompt: the loader closes, the document revision/history remain unchanged and the rename editor stays hidden. Preserve the already-proved request identity and one-request behavior.

# Implementation steps

1. Extend the current windowing journey after its real header double-click; wait on the mounted loader/prompt rather than direct-completing the request.
2. Drive the real search field with select-all/type/clear input. Assert visible delegate intersection with the list's viewport for programs 127 and 0, and actual disabled acceptance for the unmatched string.
3. Finish with Escape and the unchanged-document observations already supported by the session/grid model. Repair only the named picker or prompt boundary if the production journey diverges.
4. Map each selected clause to its fresh input/surface predicate. Keep window clear-color, grid contrast, wheel zoom and other windowing cases unchanged.

# Acceptance predicate

The header picker is usable end-to-end on the production roll: focused search, visible filtered result, no-match refusal, reset and Escape without an edit. `RollQmlTests.swift` registers the `swiftroll-window` lane; its QML input directory includes `tst_SwiftRollWindowing.qml`. `verify:qml-roll` runs that existing converted-window suite. Swift presenter tests or the drawer-picker lane are not substitutes.

Named check under §17 ownership (macOS native Qt desktop required):

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml-roll --verbose
deno task proof check --executed
```

# Task-specific constraints

No changes to `EditorSurface.qml`, prompt mounting, shell key dispatcher, Task146 keyboard files or the drawer picker. Do not restore native QWidget APIs. Remaining A001/A002/A008/A047/A055–A078 stay open: Win32 erase, contrast persistence and rendered geometry lifecycle are not proved by picker input. The four-file exception is one mounted prompt surface; this ledger is not deletable after these seven rows alone.
