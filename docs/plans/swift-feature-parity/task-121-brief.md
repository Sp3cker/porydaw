# Task 121 brief — mounted typography preserves fitted faces and italic caption semantics

# Context

Complete the existing typography consumer contract across font sizes, italic transformation and appearance restoration. The fork defines italic(source), not an independent font family; preserve that transformation rather than inventing an unused caption subsystem. This deliberately excludes theme-settings and sample-editor gaps.

Verified planning selection: **14 open rows (10 GAP + 4 PARTIAL)**. This is the in-flight §13 census, not a completion claim.

- `src/checks/themelayout/proof.tst_themelayout_font.txt` — A005, A008, A022, A032, A033, A034, A041, A047, A052, A054, A055.
- `src/checks/themelayout/proof.tst_themelayout_scale.txt` — A002, A003, A005.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea`, `97dc7fea819cb7c4a97a0dac819244ee570e993f`. Read selected expressions with `deno task proof sites` / `show`; deleted C++ check paths are references, never write targets.

# Exact write set

- `src/swift/app/typography/Typography.swift`
- `src/swift/app/timeline/GridTypography.swift`
- `src/ui/songview/quick/docks/SamplePicker.qml`
- `src/checks/themelayout/TypographyLayoutChecks.swift`
- `src/checks/editorqml/tst_Typography.qml`
- `src/checks/themelayout/proof.tst_themelayout_font.txt`
- `src/checks/themelayout/proof.tst_themelayout_scale.txt`

Closed list: production writes are limited to the interface below. The implementer owns code/check files; the separate ledger writer alone owns the listed proof files after evidence settles, in the same surface change.

# Prerequisites

The accepted Group A checkpoint precedes this task. Read 118’s settled application font-map consumer but do not write ApplicationSession; it belongs to 122 in Group B. No new font role or interface is required by 122.

# Interface contract

- Keep Typography.fitted and GridTypography/NativeFontMetrics as the font-sizing owners. Font A041 checks every original height in the fork loop, including a face that cannot fit, with independently measured ascent+descent bounded by that height. A047 checks note-name ascent+descent against captionHeight in the original context; do not infer fit from the producer’s selected pixelSize.
- Font A032/A033/A034 observes an italic transform of the production caption font on a mounted text consumer: same Atkinson Hyperlegible Next family and caption pixel size, with italic style. Reuse Qt.font’s source-font transformation already used by SamplePicker’s typed row. Keep the typed-row consumer on its original body-size role; do not change its visual size merely to make a caption test pass or add an otherwise-unused Swift role. Extend the existing mounted typography probe, not a new user-facing control.
- A022 retains absolute pixel letter spacing via the real resolved QML font at more than one size; retire only the QFont enum representation if the pixel-spacing predicate fully proves the observable contract. A054/A055: after appearance restoration, both the mounted shell and existing text probe resolve the canonical family. An imperative mutation of QApplication’s global font is a deleted architecture; use the existing production capture/restore path and explicitly distinguish that retirement from the still-required resolved text behavior.
- Font A005/A008/A052 and scale A002/A003/A005 pin QWidget initialization boolean, application stylesheet preservation, native probe visibility and rejected zero initialization. Retire those native forms with the replacement production Typography(baseFontPx:) positive normalization and live bound-font consumers; do not change Swift’s existing max(1, baseFontPx) policy merely to emulate an absent global initializer. Preserve actual font-update/fit behavior and all existing layout tokens.
- No settings dialog or sample editor is included. Color A038 is an unexecuted preset branch and A039 includes five nonexistent sample-editor pairs; leave both untouched rather than fabricate a preset or claim partial 3:1 coverage closes the row. Text still obeys WCAG AA on the real surface.

# Implementation steps

1. Extend the registered typography fit checks across the exact fork height domain using independent metrics and preserve already-passing maximality predicates.
2. Extend mounted typography font/italic/restoration observations through the existing production font maps and Qt.font transformation.
3. Repair only selected fit/map/restoration defects; the separate ledger writer maps the fourteen rows and conditionally deletes font/scale inventories after bounded representation classification.

# Acceptance predicate

The registered typography layout suite exercises the complete fit domain and shell-typography observes actual resolved faces and restoration. Neither CSS bytes nor a font map compared with itself supplies a user-visible font predicate.

The implementer runs these exact covering lanes under §13’s build-lock policy; the controller runs the settled-group full gates:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-typography --verbose
```

# Task-specific constraints

No ApplicationSession, NativeFontMetrics C ABI, theme-settings, palette policy, ShellWindow, registration or fixture changes. Preserve the existing caption/body role distinction; no DPR2 claim is inferred from a Swift dpr parameter.

Read sprint-3 §13 “Evidence and execution contract” as part of this brief: real input; independent expectations; no setup-only assertions; exact raster colors/positions and executed DPR2 where claimed; no shell dispatcher in editorqml; verbatim existing and unique complete new messages; all exact-content fixture consumers updated; copied-fixture isolation for shared bank leases; implementer-owned locked lanes; separate ledger writer.
