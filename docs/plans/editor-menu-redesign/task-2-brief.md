# Context
Task2 owns the voice-select redesign in the paired editor-menu redesign. Read plan.md Global Constraints first; the Goal is the user spec.

# Exact write set
/Users/spencer/dev/cProjects/porydaw/.worktrees/vst3-midi-effects/src/ui/songview/quick/VoicePickerPrompt.qml; /Users/spencer/dev/cProjects/porydaw/.worktrees/vst3-midi-effects/src/checks/editorqml/tst_EditorDrawerVoicePicker.qml only for deleting obsolete original-width/list-height/padding default pins and their now-unused local. Keep all modal stacking, pointer isolation, audition, transaction and keyboard behavior assertions unchanged. Never repin cosmetic defaults.

# Preserve
One production component is shared by header voice selection/add-track and drawer voice-change insertion/replacement. Preserve every root property/signal/model dispatch and consumer objectName, search/focus initialization, selection/navigation, no-match acceptance disabling, Tab cycle, Enter/double-click acceptance, Escape/outside cancellation, pointer hold audition and unconditional release on close/cancel/destruction. No voice document changes until existing accept path. Do not edit drawer/VoicePicker.qml (legacy) or Swift owners/shared controls.

# Change
1. Inspect complete production picker and shared prompt controls plus relevant header/drawer checks. Existing design is a minimally laid-out title, search box, flat list and equally plain OK/Cancel row.
2. Opus designs and implements a focused voice chooser: clear contextual title, obvious name/number search, readable framed list with deliberate current selection/focus, and aligned confirmation footer. The user's refinement removes the voice-count and preview-hint labels entirely; no replacement or extraneous labels. Keep labels sourced from existing typed roles; no parsing formatted labels or invented name/category roles.
3. Constrain the card/list to the actual available window using existing font/style metrics, including smaller windows and larger text. Match the paired MIDI Effects design family. No new keyboard/focus manager, animations, behavior features or model changes.
4. Perform required local inspection/self-review and freeze the file. No runtime/build/format actions under SHARED_TREE.

# Acceptance
Header and drawer use the improved same production voice chooser, with all prior keyboard, search, pointer audition, acceptance/cancellation and text contrast behavior intact; controller's voice/header/contrast and AOT/bridge checks and actual-app screenshot/keyboard inspection pass.
