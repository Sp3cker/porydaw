# Drawer interaction restoration

## Authority

Restore observable pre-Swift editor-drawer interaction behavior. Reuse the original QML controls and component structure, adapting bindings to Swift rather than inventing replacement controls. Swift retains document, transaction, selection, and presenter authority under [the charter](../swift-backend-charter.md). Historical C++ is evidence, not a runtime dependency.

User ruling: no new C++ code, including native bridge extensions. New implementation is Swift/QML. Only external-library adaptation may remain native; an existing first-party C API is not an exemption. Move the responsible first-party policy to Swift instead of adding another delegation. No opaque-layout guesses, diagnostic-token pointer casts, or new handwritten C++ accessors.

The detailed [inventory](inventory.md) records source locations and hypotheses. Source before `becfeb40` (container), `4b0d0738` (velocity), `414d2544` (voice), and `d2eb173e` (automation) is the oracle. The migration commits themselves are not the pre-migration baseline. The current dirty working tree is the implementation starting point; unrelated TrackHeaders and ownership work must survive.

## Accepted behavior contracts

### Automation

- Preserve every historical plot input in the inventory: middle-pan, wheel zoom/scroll, click-delete written node, Shift stationary no-op and dynamic axis lock, Alt fine snap, neutral snap, phantom promotion, empty stationary cursor placement, staircase sweep, Shift ramp, pencil extrema/revisit semantics, node-detail hit precedence, cancellation, menus and prompts.
- Selected-node moves commit every covered parameter atomically from press-time snapshots, each through its own lane/tempo resolver. Clamp shared movement at tick zero; shift selection only after a successful commit. Previews retain parameter identity; only the active displayed lane is drawn using its own projection. A stationary node click deletes only the grabbed node, never the entire selection.
- Right-band activation uses the historical Manhattan drag threshold. Left and right presses outside the current time selection clear it immediately; middle press does not. A stationary right-click inside the selection preserves it and opens its appropriate menu or is a no-op. An activated band with zero snapped width clears time selection on release. The single-active-plot layout does not invent stacked-row vertical selection.
- Pencil hover deletion follows the existing semantic delete command. It consumes blank hover with no note/time selection, deletes an actual hovered point, and defers to shared selection deletion when selection exists. Do not create a second keymap or steal window-priority commands.
- Outside right-click retargets an open point menu to the newly hit point. Lane menus and confirmation prompts dismiss without retargeting or click-through.
- Restore the hierarchical Value range menu for zoomable CC domains: Auto (0), 16, 32, 64, 127; exactly one checked entry. Modulation defaults to Auto; other zoomable lanes default to 127. Auto fits maxima to 16/32/64/127. This is per-lane view state: no document revision or history entry. Respect the existing `zoomable` domain metadata; Tempo, Pan, Pitch Bend, Modulation Type and Fine Tune do not acquire this menu.
- Restore original `AutomationTabs.qml` interaction and appearance: parameter activation, Ctrl ghost rules, event/inclusion/ghost indicators, minimal reveal, inline tempo tapping, color-only focus treatment. No extra floating tap-tempo dialog. Preserve staged tempo cadence, idle commit at tick zero, no-op identical tempo, cancellation on document change, undo, and preservation of later points.
- Restore original value prompt and `CcDeleteConfirm.qml` structure. Delete confirmation initially focuses Cancel; initial Return must not delete. All captured actions reject stale document/track targets.

### Velocity

- Preserve all existing pointer, selection, fine/unlock, relative-drag, sweep, ramp, wheel, axis, cancellation and history semantics in the inventory.
- Restore original `VelocityPrompt.qml` and `DragInput.qml` behavior: vertical scrub threshold, normal/Shift rates, integer correction and selection, wheel remainder and modifier stepping, arrows and PageUp/PageDown, explicit Tab/Backtab cycle, acceptance/cancellation and immunity to unrelated commands. Use the original implementation, not another TextInput imitation.
- Restore per-note keysplit/drumkit velocity mapping in Swift using already available typed bank facts. Preserve borrowed lifetime and one Swift-owned copy. Resolve each note using its key; preserve native keyless/invalid behavior and mixed-selection continuous display. Do not guess a top-level or first-child map.
- Restore the detent toggle's historical velocity-body bottom-left placement from `drawersections.cpp:430-436`, icon and interactions. The initial scout claim that it lived in the drawer bar was wrong. Existing velocity presenter detent state and mutation remain the sole authority. Preserve graduation and gutter work already present.

### Voice changes

- Preserve marker/held-span hit geometry, fine snap, drag collisions, context targets, empty/marker double-click, selection, prompts, undo and stale-target cancellation.
- Recover original `VoicePickerPrompt.qml` structure and focus policy: search → list → OK → Cancel → search, reverse cycle, Down from search transfers focus to list, selected match is revealed, accept enabled only for a match.
- Restore real arbitrary-program audition on row press/hold, at native historical key 60 and velocity 112. Release the sounding program with velocity 0 on release, cancellation, filter invalidation, replacement, document/workspace teardown and acceptance. The user approved full Swift audio-controller conversion, preserving the complete existing controller feature set and using existing miniaudio/poryaaaa APIs without new C++ or ABI extensions. Never audition the track's current voice as a substitute.
- Restore original shared menu row rendering and pointer/keyboard behavior; preserve row availability and captured command policy in Swift.

### Container and shared controls

- Blank drawer-bar clicks take drawer focus without executing commands. Preserve section toggle and resize behavior, keyboard handles, host clamps, focus transfers, preferences and bare-Space transport priority.
- Reuse original PromptCard, PromptButton, DragInput, QuickMenuPanel and hover/cursor behavior wherever applicable. Native C++ application presenters and popup hosts must not be resurrected. QML binding adaptation is allowed; a parallel compatibility presenter is not.
- Modal containment remains the existing drawer-wide layer. Persistent controls use Enter/Return, pointer and accessibility activation; modal exceptions retain their historical local keys.

## Evidence and corrections

Historical source supersedes both scout rounds: left/right presses outside selection clear it, while a stationary right-click inside preserves it; a stationary selected-node click deletes only the grabbed point; vertical band extent is not applicable to one displayed lane. The scout suggestion to call native file-private `resolveVoice` directly is not an available API: recover equivalent read-only subvoice facts from the bank's ToneData without linking the old application policy into Swift.

Scouts' direct binary/ctest commands are discovery notes, not approved verification commands. Controller runs `deno task verify --filter swiftcore --verbose`, `deno task verify --filter swiftqtml --verbose`, and `deno task verify:qml --filter editorqml-drawer --verbose`. Existing tap-tempo tests exist; the follow-up claim that the entire family is absent must be reconciled against `AutomationPageChecks.swift` before adding checks. Source-based preserved claims are not runtime proof.

## Verified acceptance checkpoints

- Automation restoration and selection commands: independent historical SPEC/QUALITY review passed. Regressions reproduced empty-clipboard Paste availability and lost command notifications after detach/reattach; both pass after the fixes. `deno task verify --filter swiftcore --filter swiftqtml --verbose` passed. The cohesive projection owner remains an accepted size exception; no line-count-only extraction.
