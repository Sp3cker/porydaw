# T13 — Project authoritative sessions through a Qt item model

## Context

Gate B replaces the QTabWidget as display/selection authority with a Qt item
model over WorkspaceUi's session vector. This task produces `SongTabsModel`, the
frozen [spec.md](spec.md) S2 interface that task14 (QML strip/pages), task15
(host), and task16 (WorkspaceUi cutover) consume. The model borrows the owner's
vector and selected pointer; it owns neither and is not a second session list.

## Exact write set

- `src/ui/workspacequick/songtabsmodel.h`
- `src/ui/workspacequick/songtabsmodel.cpp`

## Prerequisites

Frozen spec S1/S2.

## Interface contract

Per spec S2, exactly:

- `SongTabsModel final : QAbstractListModel` with
  `SongTabsModel(WorkspaceUi &owner, QObject *parent = nullptr)`.
- `QObject *selectedSession() const`, `int selectedIndex() const`; Q_PROPERTYs
  of those names with `selectionChanged()` / `selectedIndexChanged()`; normal
  `rowCount`/`data`/`roleNames` overrides.
- Roles: `songKey` (SongName.value), `session` (QObject*), `quickView` (QObject*
  coordinator), `title`, `tooltip`, `ready`. Title is the existing
  document-dirty label exactly as spec S2 freezes from refreshTabTitle; tooltip
  remains document().midPath(). Bank dirtiness never adds a title marker.
- Private notification methods called only by friend WorkspaceUi:
  `void beginInsert(int row)`, `void endInsert()`, `void beginRemove(int row)`,
  `void endRemove()`, `bool beginMove(int from, int finalRow)`,
  `void endMove()`, `void notifySelectionChanged()`, `void refresh(SongTab *)`.
- `beginMove` uses destinationChild = finalRow + 1 for a forward move, finalRow
  for a backward move; API finalRow is always the final index after
  removal/reinsertion. No-op/invalid requests issue no begin/end pair. Return
  the underlying `beginMoveRows` result; false means the owner neither mutates
  the vector nor calls `endMove`.
- Publish derived index after every structural operation that changes it even
  when selected identity is unchanged; emit selected-session notification only
  when identity changes.
- Exported C++-owned QObject borrows are marked `QQmlEngine::CppOwnership`
  before QML sees them.

## Implementation steps

1. Declare the final class, constructor taking `WorkspaceUi &`, Q_PROPERTYs,
   role enum, and the private friend-only notification methods; declare
   `friend class WorkspaceUi` (owner grants friendship per spec).
2. Implement rowCount/data/roleNames over the owner's `m_tabPages` vector and
   `m_selectedTab` pointer; `title` reads via the owner's new private
   `tabTitle(const SongTab &)`, `tooltip` the existing song path, `ready` the
   existing readiness definition.
3. Implement the begin/end notification wrappers mapping to the corresponding
   QAbstractListModel protected calls, with the specified move destinationChild
   arithmetic and no-pair behavior for no-op/invalid requests.
4. Implement `notifySelectionChanged()` (identity vs derived-index emission
   rules above) and `refresh(SongTab *)` (dataChanged over that session's row,
   all roles).
5. Mark exported session/coordinator QObject borrows `QQmlEngine::CppOwnership`
   at the point they are exposed to QML.

## Acceptance predicate

Model moves/removals/insertions remain valid and UI identity/persistence stays
consistent when driven through real WorkspaceUi operations. NAMED CHECKS:
`deno task verify --filter tabcheck` (controller-run at gate B; model behavior
coverage lands in task19).

## Task-specific constraints

- No duplicate session list, selected pointer, or selection policy inside the
  model.
- Do not feed TabBar.currentIndexChanged back as a select request (spec S2).
- Write set is closed; the owner-side friendship/tabTitle/vector changes belong
  to task16.

## Controller verification

[Gate B](plan.md#verification-and-checkpoint-semantics).
