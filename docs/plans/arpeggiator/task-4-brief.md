# Context
Integrate fixed generator, audition and QML interfaces from tasks 1–3 as one user-visible track tool. Read plan.md Global Constraints and shared specification.

# Exact write set
- src/swift/app/arpeggiator/ArpeggiatorPresenter.swift (new)
- src/swift/app/DocumentWorkspace.swift
- src/swift/app/SongTabsController.swift
- src/swift/app/headers/TrackHeaders.swift
- src/swift/app/shell/PorydawQmlTypes.swift
- src/swift/app/CMakeLists.txt
- src/ui/songview/quick/swiftroll/EditorSurface.qml
- src/ui/songview/quick/swiftroll/EditorSurfacePrompts.qml
- CMakeLists.txt (register production QML sources only)

# Prerequisites
Task interfaces 1–3 in plan.md, exact contracts only.

# Interface contract
Implement plan presenter, register it through SongTabSession and PorydawQmlTypes, own it in DocumentWorkspace. Track-header context menu opens bound track without selecting notes. Closing/deactivation/document or bank changes stop audition; selection-only changes do not reroute. Open/configure surfaces through actual EditorSurface loader and include in modal/hint arbitration. One cached generated result supplies the isolated audition timeline and loop-span clipboard notes; no visual-note-preview row model or registration. Build timeline from original file/controller/voice/tempo information with all original note messages replaced by generated notes on source track; preserve correct program at loop start and absolute loop bounds. No source document writes.

# Implementation steps
1. Inspect affected declarations and references, then implement the presenter without a visual-note-preview model. Clear errors/stale audition appropriately; copy success must reflect clipboard write result. Invalid settings/loop disables audition/copy with explanatory status. CurrentStep follows generated stepTicks/stepIndices using actual audition sample position and timeline tick conversion.
2. Wire workspace lifecycle, contextual header action, SongTabSession root, type registrations, QML loader/hints and explicit source build lists. Reuse existing menu/PromptStyle patterns, no EditCommand-wide extension needed for contextual tool.
3. Provide controller with exact contextual menu action, presenter/UI object names, clipboard/audition observation seams and any intended baseline changes for focused new behavior checks. Controller owns all checks, check registration, baselines and documentation.
4. Perform file-local structural/diagnostic inspection. Controller runs settled-tree commands, native surface smoke and review; report DEFERRED_TO_CONTROLLER for shared verification.

# Acceptance predicate
User opens on track, hears and sees only generated loop, changes plugin-arranged controls, copies that exact loop and pastes through normal clipboard with leading/trailing rests and PPQ preserved; source/history unchanged until ordinary Paste. NAMED CHECKS: all plan.md verification commands plus visible production smoke.

# Task-specific constraints
SHARED_TREE: worker owns only the exact integration write set above, no builds/checks/formatters/linters or commits. Controller owns checks, check registration, baseline changes, documentation and verification. Do not edit user untracked prototypes/profiler/docs. No generic preview engine, saved effect, routing selector, native business logic, stubs or unimplemented controls.
