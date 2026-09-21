# Restore the complete editor drawer in Swift/QML

Status: active implementation plan. Camera integration and the drawer container
are accepted and pushed. This plan extends that accepted base through one shared
playhead, all three production pages, translated Swift/QML coverage, and final
production acceptance.

## Scope and accepted base

The accepted base is:

- task 1, camera integration, commit `5f0924e8`;
- task 2, drawer container, commit `becfeb40`;
- one `DocumentSession`-owned `EditorCamera`;
- one `ApplicationSession`-owned `PianoGrid`, `NativeAudio`, and
  `EditorDrawerPresenter`;
- acknowledged whole-scene detachment before document presentation owners are
  released; and
- the standalone `swiftcore`, `editorqml-drawer`, and `swiftrollgated`
  verification lanes.

Restore the remaining editor surface in this order:

1. one shared playhead sourced from the authoritative audio sample position;
2. Velocity;
3. Voice Changes;
4. Automation domain/projection and transactions;
5. Automation QML/input/prompts/menus; and
6. final production-app acceptance with every page mounted.

The sibling `swift-qml-songtab` worktree is read-only parity authority for
production behavior, legacy scenario intent, and reference images. Its C++
checks are inventories to translate, not suites to re-enable.

## Global Constraints

- Read [the shared spec](spec.md) and the current task brief before dispatch.
  Briefs are implementation contracts, not discovery prompts.
- Swift owns application state, projection, transactions, history integration,
  and semantic checks. QML owns visual composition and input delivery. Reuse the
  existing QtBridge, native audio/project services, and application shell.
- No new handwritten C++ application code, test scenario, bootstrap, bridge API,
  or QtBridge expansion is authorized. A capability gap is a blocker; it is not
  permission for a fallback or workaround.
- One document/history, one playback sample authority, one
  `PlaybackTimeline`, one camera, and one shared playhead owner. No page-local
  clock, interpolation loop, viewport, history, or reciprocal scroll binding.
- Playback presentation uses `NativeAudio.playheadSamples` and
  `PlaybackTimeline.tick(for:)`. Playback never derives from wall-clock time.
  Edit cursor and history remain separate.
- Playhead-only updates must not rebuild page/grid content, mutate the document,
  consume Redo, publish audio, or dirty the song.
- Page gestures and drawer resizing participate in one aggregate follow-scroll
  suspension. Cancellation is synchronous and ends every affected provisional
  edit, prompt, audition, pointer grab, and preview transaction.
- QML production composition is the tested composition. Fixtures may inject
  production presenters and production page components; copied handlers,
  lookalike pages, and test-only production branches are prohibited.
- Persistent chrome yields bare Space to the window transport command.
  Enter/Return, pointer input, and accessibility press actions activate local
  controls. Preserve modal text-entry and explicit audition exceptions.
- Use existing font-relative geometry and the exact DPR/font reference profiles.
  No hard-coded widget pixel geometry.
- Keep the acknowledged scene-detachment lifecycle. Attach document-bound pages
  before the scene mounts; cancel while the scene exists; detach/release them
  only after host acknowledgment.
- Translate every relevant handwritten C++ scenario into direct Swift policy or
  Swift-hosted production QML coverage. Do not leave C++ scenario bodies behind
  a Swift launcher and do not restore retired suite aliases.
- Tests must exercise observable behavior. Static source assertions, mock echoes,
  copied implementation logic, and case-count claims are not acceptance.
- Reassess the ten stale absent-UI exclusions as their owning pages return.
  Keep the voicegroup-save rows separate from this drawer milestone. Track the
  four native MIME clipboard gaps separately; do not close them by implication.
- Do not invent a public follow toggle. Follow is enabled by default; a
  Swift-only setter may exist for deterministic policy checks.
- Every accepted task receives controller-run exact verification, an independent
  production-and-coverage review, a cohesive commit, and a push before the next
  task reuses its files.
- Do not modify the unrelated dirty `swift-core-rewrite` documents.

## Shared ownership contract

`ApplicationSession` is the integration owner. It retains the audio service,
document session, grid, drawer, shared-playhead owner, and the three
document-bound page owners. `DocumentSession` remains the sole owner of the
document, timeline, camera, selection, edit cursor, and history.

The playhead owner reads the audio service's sample/transport state, maps samples
through the current timeline, and projects the resulting tick through the current
camera. `EditorSurface.qml` draws that one published position as clipped segments
over the roll plot and each visible drawer body. Gutters never receive a
playhead segment.

Every page implements the existing `EditorDrawerPage` seam, consumes the shared
camera/playhead/document state, and owns only its page-specific vertical/value
projection and interaction state. A page commits one document transaction per
completed gesture; preview state is frozen at gesture start and discarded on
cancellation.

## Tasks

| Task | Deliverable | Prerequisites | Route |
| --- | --- | --- | --- |
| 1 | [Integrate the camera into the real grid](task-1-brief.md) | Accepted camera prep and bounded T8 | Accepted at `5f0924e8`. |
| 2 | [Implement the Swift/QML editor drawer container](task-2-brief.md) | Task 1 | Accepted at `becfeb40`. |
| 3 | [Integrate the shared Swift playhead](task-3-brief.md) | Task 2 | SDD-track: one owner, authoritative sample mapping, follow policy, segmented production rendering, translated checks. |
| 4 | [Restore the Velocity page](task-4-brief.md) | Task 3 | SDD-track: page model, frozen gesture transactions, production QML, translated semantics and visual references. |
| 5 | [Restore the Voice Changes page](task-5-brief.md) | Task 4 | SDD-track: voice context, markers, picker/menu/audition, transactions, production QML and translated checks. |
| 6a | [Restore Automation domain and projection](task-6a-brief.md) | Task 5 | SDD-track: deep Swift model for parameters, curves, selection, clipboard policy and transaction semantics. |
| 6b | [Restore mounted Automation editing](task-6b-brief.md) | Task 6a | SDD-track: production QML, input, prompts, menus, tap tempo, audition/context, cancellation and translated rendered coverage. |
| 7 | [Accept the complete production drawer](task-7-brief.md) | Task 6b | SDD-track: normal app verification, exact profile captures, lifecycle/performance evidence, exclusion accounting and final review. |

Tasks are sequential because they reuse `ApplicationSession`, `EditorSurface.qml`,
drawer attachment state, QML resources, and the same verification lanes. Planning
evidence may be gathered ahead of execution, but no later task edits an unaccepted
predecessor surface.

## Acceptance and review

Each task's acceptance predicate is in its brief. The independent task reviewer
must judge both:

1. production behavior against the current Swift architecture and sibling
   production parity authority; and
2. coverage translation against the legacy C++ scenario inventory and reference
   images named by the brief.

Critical or Important findings return to the original writer for a bounded fix
loop. Accepted tasks are committed and pushed immediately.

The milestone is complete only when the normal production app mounts all three
pages, one shared playhead crosses every visible timeline body, every required
interaction and cancellation path is implemented, the exact verification set
passes, and production captures exist for every named pane/profile. Remaining
gaps must be explicit blockers; no scope is silently narrowed.
