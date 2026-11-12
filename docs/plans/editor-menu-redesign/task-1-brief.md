# Context
Task1 owns the MIDI Effects redesign in the paired editor-menu redesign. Read plan.md Global Constraints first; the Goal is the user spec.

# Exact write set
/Users/spencer/dev/cProjects/porydaw/.worktrees/vst3-midi-effects/src/ui/songview/quick/MidiEffectsPanel.qml only.

# Preserve
Root PromptOverlay/interface and all model calls/guards; dialog dismissal/focus restoration/Space priority; selection and blocked retry; folder add/remove/rescan/cancel; plugin list; editor, input/pacing/preroll, status/diagnostics, reload/remove and close. All current objectNames used by checks remain. Shared controls and Swift presenter are read-only.

# Change
1. Inspect existing production composition, shared prompt components, presenter readonly surface and relevant checks. Before screenshot /var/folders/tm/rx2sb_ks5dx5x81c3vgsrvtm0000gn/T/omp-computer-15c966424b4790e1.png shows cramped edge-to-edge controls, duplicate Close actions, unstructured options, huge saturated selected row and an oversized raw diagnostic row.
2. Design and implement a visibly polished, coherent rack/browser dialog with a useful hierarchy: track context/title, discovery/library controls and plugin choices, installed-effect settings, bounded status/diagnostics, clear footer. Remove duplicated Close presentation. Avoid walls of equally-weighted buttons and giant saturated selection blocks; keep every existing action available and errors fully discoverable without hover-only access. Exact design is Opus's responsibility, no approval pause.
3. Keep font-relative responsive sizing/scrolling, visible focus, actual disabled guards and all-theme contrast. Read-only state and display binding only; no new backend modes or hidden dispatcher.
4. Perform required local inspection/self-review and freeze the file. No runtime/build/format actions under SHARED_TREE.

# Acceptance
The actual production MIDI Effects dialog has substantially improved hierarchy, spacing, list selection and settings organization without losing any existing workflow; controller's shell MIDI/output/contrast and AOT/bridge checks and screenshot/keyboard inspection pass.
