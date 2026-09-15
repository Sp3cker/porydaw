# T14 — Compose tabs and persistent song pages with Qt controls

## Context

Gate B needs the QML half of the workspace: `WorkspaceSongs.qml` (root scopes,
strip, persistent page delegates) and `SongTabStrip.qml` (TabBar-based strip).
Consumed by task15's WorkspaceQuickHost, which loads WorkspaceSongs as the root
and relays its signals; consumes the frozen SongTabsModel interface from task13
and the S3 scene/`isInputEligible` seam from tasks 1/8. Task19/20 prove the
behavior.

## Exact write set

- `src/ui/workspacequick/WorkspaceSongs.qml`
- `src/ui/workspacequick/SongTabStrip.qml`

## Prerequisites

Interfaces from tasks 1 (scene lifecycle), 8 (item-scope keyboard routing), and
13 (SongTabsModel).

## Interface contract

Per spec S1, `WorkspaceSongs.qml` exactly:

- Required properties `var tabs` and writable `var appearance`; signals
  `selectRequested(QtObject session)`, `closeRequested(QtObject session)`,
  `moveRequested(QtObject session, int finalRow)`; functions
  `enterEditor(reason)` and `enterTabs(reason)`.
- Root is a FocusScope with `focus: true`; contains TabBar-based SongTabStrip
  plus an editor FocusScope (`focus: true`), StackLayout and Repeater over
  `tabs`.
- Each delegate is a persistent clipped FocusScope; identity = session QObject;
  focus/enabled = `(session === tabs.selectedSession) && ready`; StackLayout
  currentIndex is `tabs.selectedIndex`; empty-state content outside the stack;
  reorder via model moves, never reset/recreate.
- Stable objectNames: `songTab:<songKey>`, `songTabClose:<songKey>`,
  `songTabStrip`, `workspaceSongs`.
- Knows no QWidget, MainWindow pointer, or per-song host.
- Forward the appearance value to SongTabStrip's required `var appearance`;
  consume only the exact keys/font metrics/theme roles frozen once in spec S1.
  No unnamed context-property map or Qt Controls default-palette substitute.

Per spec S4/S8: native tab pointer selection uses Qt.NoFocus/Qt.TabFocus
controls that do not steal editor focus; Left/Right use the exact
Keys-plus-KeyNavigation pattern in S4 with one semantic request; Enter/Return
activate/enter editor; Space is never claimed by persistent tab chrome; drag
uses Qt DragHandler (threshold/grab owned by it), release must be inside the
viewport over an actual tab with PointerDevice.UngrabExclusive AND
EventPoint.Released AND enabled strip; horizontal wheel exposes offscreen tabs;
intrinsic-width tabs with clipped native ListView scrolling.

## Implementation steps

1. Write WorkspaceSongs.qml: root FocusScope, required `tabs` and writable
   `appearance` properties, the three signals and two entry functions, editor
   FocusScope containing StackLayout + Repeater with persistent clipped
   FocusScope delegates bound as specified, empty-state content outside the
   stack.
2. In each page delegate, pass its root FocusScope itself to
   `quickView.attachToPage(viewport)` using the separate model role once when
   completed AND window-associated, regardless of readiness (loading pages still
   have scenes, disabled).
3. Write SongTabStrip.qml: TabBar/TabButton/ToolButton/ToolTip with intrinsic
   widths, clipped ListView overflow with horizontal wheel, DragHandler-driven
   reorder emitting `moveRequested(session, finalRow)` only for a valid released
   drop inside the viewport over an actual tab; target is null and visual
   feedback follows S8. Do not reject a destination tab merely because its close
   area is hit.
4. Carry the source session identity, not a press-time row index. Resolve the
   destination with the ListView hit test; use the delegate's live index only to
   skip same-row requests. WorkspaceUi resolves the source row by membership
   when handling moveRequested. Ignore cancelled, disabled, outside and
   close-button-origin drags; add no model row-lookup/get API.
5. Wire read-only model selection: user gestures emit the request signals only;
   never feed TabBar.currentIndexChanged back as a select request; no duplicate
   QML shortcuts for next/previous/F6 (those are window Registry actions,
   task18). Use S4's explicit arrow handlers plus native KeyNavigation; the
   adjacent tab delegate supplies its session without a model.get extension.

## Acceptance predicate

Real tabs switch, close and reorder safely, preserve scene objects, and support
overflow/keyboard/accessibility paths. NAMED CHECKS:
`deno task verify --filter tabcheck --filter mainwindow-routing` (controller-run
at gate B).

## Task-specific constraints

- Qt Quick Controls and native FocusScopes only; no custom focus dispatcher,
  focus cache, or per-page host.
- No prototype pixel constants; geometry/hit targets use existing
  layout/typography/font primitives and theme roles.
- Delegate attach is once per completed+window-associated page; no lazy loading
  framework or scene pooling.

## Controller verification

[Gate B](plan.md#verification-and-checkpoint-semantics).
