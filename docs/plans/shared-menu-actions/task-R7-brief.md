# R7 — Rebind ownership and narrowed binding contract (E-M3 + E-m11)

## Context
Downstream consumers expect bounded boundary contracts; here the binding surface is the seam. Signed-off finding E-M3 (AMEND, QtSignoffFindings) removes the six-step `EditActions::rebind` dance (editactions.cpp:137-155, friend at songview.h:702, QPointer member songview.h:925, editactions.h:48, destructor songview.cpp:338-341, setDocument songview.cpp:807-812) **and directing it to (b) narrow the borrow to a bind/unbind pair rather than (a) direct membership.** E-m11 (AMEND): the destroyed-target callback keeps its connection but drops the redundant manual `m_target = nullptr` (editactions.cpp:181-186) since QPointer invalidation precedes `destroyed()` during `~QObject()`. The kept connection (eligibility reset, refresh) is load-bearing under the borrow protocol: it is the defensive destroyed-refresh enabling canonical QActions to be torn down on situations where a view dies without rebind(nullptr).

## Exact write set
- `src/ui/songview/editactions.h`
- `src/ui/songview/editactions.cpp`
- `src/ui/songview/songview.h` (friend declaration removal; narrowing clang warnings)

## Prerequisites
- Task R5 (same three files; serialization only, ownership not yet wired into Qt parent-tree).

## Downsides of the alternative considered and rejected
Direct `SongView::editActions` ownership (option (a)) would remove the friend and back-pointer, but would push SongView into construction-time action-set knowledge it does not otherwise owe any binding; keep the (b) as the smaller, reviewable Qt-semantics delta. The E-M3 Qt remedy's (a) direct-member shape and its (b) narrowed-bind consequence are discussed in the `Q-F1` admission (the "helper vs no helper" consequence). R7 picks (b), which by signoff verdicts means downstream [Task R9](task-R9-brief.md) proceeds with the checks::support helper parent+rebind seam (Q-F1 helper stays). This is recorded explicitly here because the Q-F1 corrective decision depends on this pick and the pick must not be duplicitously reopened by later implementers.

## Acceptance predicate
No caller can rebind a live non-null target A onto a live non-null target B; rebind(nullptr) and rebind(this) remain the only reachable transition targets; the defensive destroyed-refresh still compiles and drops only the redundant assignment. Named checks: `deno task verify --filter selectionkey --filter host-seams --verbose`.

## Task-specific constraints
[Global Constraints](plan.md#global-constraints) apply. **Spec amendments this brief lands:** spec.md#implementation-contracts under "Fixed catalogue and action ownership", substitute the `void rebind(SongView *)` interface-table row's narrow "restricted to nullptr-or-this rebind only" wording; spec.md#single-binding-operation first bullet "Callers only provide the next ready SongView, or null" gains the exact restrictive rebind contract: the friend forwarder maps rebind(x other than nullptr/this) onto a hard compile-time/Q_ASSERT rejection. E-m11's kept-but-narrowed defensive destroyed-refresh wording is amended at the "defensive destroyed-target callback" bullet. No Q_F1 or fixture/support edit belongs in this brief; Task R9 owns the helper decision's implementation follow-through.
