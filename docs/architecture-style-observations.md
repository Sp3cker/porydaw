> Scope note (2026-09): this is a cross-repository provenance study feeding STYLE_GUIDE.md, not a description of the Porydaw app. Porydaw itself is now a Swift 6 + QML application (Swift owns behavior, exposed to QML through QtBridge; no QWidgets). The `cProjects/porydaw` row above describes its earlier C++20/Qt6 era.

Nothing here is a universal prescription. Each observation in §3 is
labeled as **observed fact**, **inference**, **evolution**, or
**counterexample**, and carries a confidence level. Sections 2, 4, 5,
and 6 are analysis layered on those observations; where a claim there
goes beyond what the packet records, it is marked *(inference)* inline.

## 1. Corpus and provenance boundaries

The corpus is finite and uneven. Conclusions below are bounded by it.

### Repositories examined

| Lineage | Repositories | Era / stack |
| :--- | :--- | :--- |
| Legacy services | `nodeProjects/whs-socket-server` (2021), `nodeProjects/mktplace` (2019–2021), `nodeProjects/mGrezza` (2019–2020) | JavaScript, Express, Socket.IO, PM2, DB2 |
| stapl suite | `nodeProjects/stapl-api` (`alpha`), `nodeProjects/stapl-server` (`odbc`), `nodeProjects/stapldb2` (`odbc`) | TypeScript, Express, undici, ODBC, Keycloak/Okta |
| Typed backend (adjacent) | `nodeProjects/weaboats-api` (`master`) | TypeScript, MongoDB |
| Tools / parsers | `nodeProjects/mktcli`, `nodeProjects/lexerr`, `nodeProjects/spory-sparser` | JS then TypeScript, Joi then Zod |
| Frontend / full-stack | `reactProjects/eidex` (`faster` branch), `reactProjects/staplcotn-members` | React/Zustand, React Native, Express API |
| Current project | `cProjects/porydaw` | C++20, Qt6 |

### Lineages, not votes

Two groups in the corpus are single evolutionary lineages and must not be
counted as independent evidence:

- **stapl suite.** `stapl-api`, `stapl-server`, and `stapldb2` are one
  system evolving from IBM iSeries `idb-connector` callbacks through an
  HTTP gateway to ODBC pools, `undici`, and Keycloak M2M auth. A pattern
  appearing in all three is one data point, not three.
- **lexerr → spory-sparser.** Git reflog shows `spory-sparser` was cloned
  directly from `lexerr` (`.git/logs/HEAD`: `clone: from
  https://github.com/Sp3cker/lexerr.git`). Differences between them are
  *evolution within one codebase*, which is actually the more useful
  signal: it shows which habits Spencer kept and which he revised.

### Authoritative provenance correction: lexerr

Per authoritative testimony, in `lexerr` Spencer authored the **INC-file
parsing** code only: `src/parseMaps/incParser.ts`,
`src/parseMaps/trainerInc.ts`, `src/parseMaps/extractTrainers.ts`,
`src/parseMaps/extractTrainerParties.ts`. He did **not** author the
picture/sprite/image parsing code. The excluded paths differ per
repository and are listed separately below.

Excluded in `lexerr` (non-Spencer picture/sprite/image tooling, per the
same testimony):

- `src/sprites/*`, `src/newSpriteGenerator/*`
- `itemSpriteGenerator.ts`, `tmSpriteGeneratorImageMagick.ts`,
  `convert_png.c`, and related image tooling

Excluded in `spory-sparser` — despite `Sp3cker` commit authorship on
some of them, the packet marks these paths unsuitable for inference
because they are direct continuations of the non-Spencer image tooling
or were produced by third-party refactoring assistants (documented in
`src/newSpriteGenerator/README.md`):

- `src/newSpriteGenerator/*` (including `SpriteDatasetPipeline.ts`,
  `SpriteProcessor.ts`, `PeopleSpriteProcessorBase.ts`,
  `TrainerSpriteProcessor.ts`, `OverworldTrainerSpriteProcessor.ts`,
  `ItemSpriteProcessor.ts`, `PaletteApplier/*`,
  `_applyGraphicPalettes.ts`, `resizePeopleSprite.ts`, `justSpecies.ts`,
  `runCharacterSpriteProcessor.ts`, `runSpriteDatasetPipeline.ts`,
  `TMsApplier.ts`)
- `src/trainerproc.c` and its compiled binary `src/trainerproc`
- `src/scripts/drawMapSections.ts`,
  `src/parseMaps/overworld/collectSprites.ts`,
  `src/parseMaps/Trainers/mugshots.ts`, `mugshotOverrides.ts`,
  `joinTrainerGraphics.ts`, `utils/renameTMs.ts`

This matters because the excluded paths contain the corpus's only complex
class hierarchies (`SpriteProcessor` / `PeopleSpriteProcessorBase` /
`TrainerSpriteProcessor`). Any claim that "Spencer builds deep class
hierarchies for processing pipelines" would be an attribution error.

### Other corpus limits

- `stapl-api/src/queryFiles.ts` / `stapldb2/src/queryFiles.ts` contain
  recursive regex template substitution (`replaceParams`,
  `flattenObject`) that the packet reports — from git history, though
  without citing a specific commit — was inherited legacy code carried
  forward, not newly authored logic.
- `eidex` was assessed on the `faster` branch over high-confidence
  Spencer-authored modules only (`src/stores`, `src/components/Map`,
  `src/lib`, `src/workers`, `src/services`, `src/hooks`, `worker`,
  `scripts`).
- `staplcotn-members` excludes untouched third-party scaffolding.
- `STYLE_GUIDE.md` was an untracked draft at the time the evidence
  packet was compiled (September 2026); it is evidence of intent, not
  of practice.

## 2. Historical evolution

The corpus spans roughly 2019–present and shows a real trajectory, not a
static style.

**2019–2021 (mGrezza, mktplace, whs-socket-server).** Core instincts are
already present — derived aggregates, pre-mutation invariant checks,
top-down orchestration — alongside early-career defects: ad-hoc in-memory
mutation (`mktplace/services/markit/markitplace.js` `this.markits`,
`_resetMarkit`), missing input validation
(`whs-socket-server/app.js` `socket.on("updateStatus")` assigning
untrusted payloads), and universal error flattening into HTTP 500 strings
(`mGrezza/op/*_routes.js`, `markitEngine.js`'s
`unhandledRejection` joke log). Physical schema names
(`PRODDATA.PINBWRK`, `DEFAULT_LIB = "SATEST"`) leak into business logic.

**TypeScript services (stapl suite, weaboats-api).** The instincts
harden: validation moves to compiled boundary schemas
(`stapl-server/src/middleware/checkBody.ts` with `Joi.assert`), errors
fail fast at edges, resource lifecycles get explicit `bail`/`close`
guards (`stapldb2/src/util/preparing.ts`), and shared transient state is
isolated behind one owner with singleflight deduplication
(`stapl-api/src/client/TokenClient/TokenClient.class.ts`). The error
swallowing of the mGrezza era is gone.

**Tools (mktcli → lexerr → spory-sparser).** Configuration evolves from
implicit up-tree lookup (`findUp.sync('./server.config.json')` in mktcli)
to an explicit typed singleton (`spory-sparser/src/config/configReader.ts`
`Config` with `ConfigSchema` + `validateDirectoriesExist`). Schema
validation is promoted from leaf nodes (`PartyMonSchema` in lexerr) to
stage-boundary contracts (`IncDataSchema`, `LevelIncDataSchema` in
spory-sparser). Silent error suppression (`catch (err) {}` in
`lexerr/src/parseMaps/incParser.ts` label prettification) is replaced by
explicit unrecoverable throws on failed ID lookups.

**Frontend (eidex, staplcotn-members).** The same instincts reappear in
UI form: coarse domain stores publishing atomic multi-field transitions
(`eidex/src/stores/useMapStore/useMapStore.ts` `setSelectedMap` updating
12 interrelated keys in one setter), boundary schema parsing
(`staplcotn-members/api/src/repositories/Fixations.ts`
`fixationsSchema.parse` over raw DB2 rows), and explicit async
coordination (`randomizerStore.ts` `waitForEncountersReady`).

**Porydaw (current).** The accumulated habits land in C++20/Qt6 as a
functional-core/imperative-shell split: `src/core/` holds pure domain
logic with zero Qt-GUI/disk dependencies, `src/project/` owns async I/O
behind immutable snapshots (`ProjectSnapshot`, `ProjectState`), and
`src/ui/` consumes passively (`src/ui/workspaceui.h` "never performs
project file I/O").

## 3. Recurring tendencies (evidence-backed)

### 3.1 Store facts; derive classifications and views — Strong

The single most consistent pattern across every era and stack.

- `mGrezza/op/buisnessLogic.js` `generateTotalRow` computes every invoice
  subtotal and deduction from raw line items at inspection time; nothing
  is cached on warehouse records. `inbndParser.js` `calcLen` maps
  continuous lengths to staple grades on the fly.
- `weaboats-api/src/connections/availability.ts` `determineIfAvailable`
  derives the `Availability` classification from raw ship facts at query
  time; no status flag is persisted.
- `eidex/src/stores/useCaughtStore` stores only the set of caught IDs;
  counts and status are derived.
- `cProjects/porydaw/src/core/songdocument.h`: `SmfFile` + `SongCfg` are
  the sole persistent facts; `MidiTimeline`, `SongViewModel`, and
  `AutomationViewModel` are rebuilt projections
  (`src/ui/songtab.cpp:108-114`, `src/ui/songviewmodel.h`,
  `src/ui/editordrawer/automationviewmodel.h`).

*Counterexample / qualification:* this is a default, not a dogma. When
latency is at stake Spencer eagerly precomputes:
`eidex/src/workers/descriptionWorker.ts` `preprocessAllMaps()` fills
`descriptionCache` at worker init; `levelIdtoLocationMap.ts`
`initializeLevelIdLookup()` builds a reverse index at module load;
`engine.ts` memoizes `speciesTablePromiseByMode`. The accurate rule is
"derive by default; cache when an observable consumer needs the latency,"
not "never cache."

### 3.2 Validate at the boundary; assume invariants downstream — Strong

- `stapl-server/src/middleware/checkBody.ts`: `Joi.assert` upfront, then
  immediate normalization (`req.body.profile.toUpperCase()`), HTTP 400 on
  failure.
- `stapl-api/src/client/index.ts` `ensureProfile` throws synchronously on
  a missing profile; `sequence.ts` `sqlSequence` throws on non-array
  input.
- `mktcli/src/configValidator.js` `flightCheck` verifies schema *and*
  filesystem existence (`markits` path, SSL keyfile/certfile) before any
  process spawns; `cliTools.js` `ensureOwner` aborts on OS-user mismatch.
- `spory-sparser/src/config/configReader.ts` aggregates all missing
  directories into one fail-fast error.
- `staplcotn-members/api/src/repositories/Fixations.ts` runs
  `fixationsSchema.parse()` on raw DB2 output before it becomes a domain
  type; `types/src/summary.types.ts` separates raw `AccountSummaryQ`
  (uppercase legacy columns) from clean `AccountSummary`.
- `eidex/src/lib/randomiser/trainerIdExtractor.ts` asserts buffer length
  and magic sector signature `0x08012025` before parsing a save file.

*Evolution:* the boundary-validation mechanism moved from manual type
guards (`stapldb2/src/util/setConn.ts`) to declarative schemas (Joi →
Zod) to, in Porydaw, typed seams enforced by the C++ type system. A
related but distinct mechanism is failure *representation*: Porydaw
models fallible cross-seam outcomes as `std::variant` payloads
(`src/project/projectworkspace.h` `ProjectMutationFailure`) rather than
flattened error strings — that is error modeling, not shape validation.

### 3.3 Linear top-down orchestration — Strong

Main paths read as sequential checklists in execution order.

- `mGrezza/op/inbound/inbound.js` `postInbound`: detect format → generate
  batch ID → parse → stage → update header → return fresh state.
- `stapl-server/src/index.ts`: middleware pipeline ordered sentry → json
  → pino → timeouts → helmet → swagger → healthcheck → audit → auth →
  schema → dispatch.
- `stapl-api/src/client/index.ts` `runRequest`: token → profile → debug →
  request → status assert → decompress → parse.
- `spory-sparser/src/parseMaps/index.ts`: single procedural orchestrator
  iterating directories, delegating to adjacent helpers.

### 3.4 High abstraction threshold; classes only for stateful accumulation — Strong

- `mktcli/src/functions.js` exports standalone async functions
  (`start`, `serve`, `stop`, `restart`) rather than a ProcessManager
  hierarchy.
- `stapl-server/src/handleQuery.ts` dispatches straight to
  `stapldb2.dbCall` — zero service/repository/unit-of-work layers.
  `weaboats-api/src/app.ts` routes via a plain function map
  (`responser[intent]`).
- In the parser lineage, classes appear almost exclusively as stateful
  accumulators (`IncScriptEvent` in `incParser.ts`) or configuration
  singletons (`Config`). The corpus's only deep class hierarchies are in
  the excluded, non-Spencer sprite paths (§1).
- *Counterexample:* `stapl-api/src/client/TokenClient/` uses a class with
  injected `HttpClient` — but only at an external protocol boundary
  (OAuth), where test seams and retry wrapping justify it. Abstraction is
  accepted at physical boundaries, refused inside the domain.

### 3.5 One owner per coherent state; atomic invariant publishing — Strong

- `TokenClient.class.ts` owns the cached token, the refresh timer, and
  the in-flight `ongoing` map — callers never see synchronization.
- `useMapStore.ts` `setSelectedMap` computes all derived data first, then
  publishes 12 interrelated keys in one setter; no torn intermediate
  state.
- `porydaw/src/ui/songtab.h` pairs `SongDocument`/`SongView`/
  `MidiTimeline` per tab; `src/project/projectworkspace.h` is the single
  public seam for project state.
- *Counterexample (historical):* `mktplace/services/markit/markitplace.js`
  duplicated PM2 state into `this.markits`, producing drift that required
  `getRunningMarkits()` to repair. The current rule exists because the
  violation hurt.

### 3.6 Explicit concurrency coordination — Strong (typed era onward)

- Singleflight: `TokenClient` caches the in-flight promise in `ongoing`
  and deletes it in `finally`.
- Readiness gates: `randomizerStore.ts` `waitForEncountersReady()`
  deferred promise instead of polling flags.
- Write coalescing: `useCaughtStore/actions.ts` `queueMicrotask` flush
  with `writeGeneration`/`storageGeneration` counters dropping stale
  in-flight writes.
- Buffered side effects: `urlManager.ts` holds `history.pushState` during
  animations via `isAnimating`/`pendingUpdate`.
- Porydaw equivalent: borrow-safe swaps (`songtab.cpp` `applyMidiStage`,
  `applyBankView` parked `VoicegroupLease`), `InputGate` filtering input
  while presentation stays live, `ProjectOpenState` enum instead of busy
  flags.

### 3.7 Explicit resource lifecycle — Strong (typed era onward)

- `stapldb2/src/util/preparing.ts` `bail()` closes statement and
  connection unconditionally; `runQueries.ts` gives each parallel query
  its own connection so one crash strands nothing.
- `stapl-server/src/index.ts` sets request/response timeouts to prevent
  hung iSeries sockets leaking.
- `weaboats-api/src/index.ts` registers `SIGINT` teardown.
- Porydaw: destructor ordering in `SongTab::~SongTab()` deletes `m_host`
  before `m_view` deliberately.

### 3.8 Lightweight procedural parsing over grammar tooling — Strong (parser lineage)

- `lexerr/src/parseMaps/incParser.ts`: line loop + regex command matches,
  `line.endsWith("::")` block detection.
- `spory-sparser/src/parseMaps/pory/extractPoryScripts.ts`: regex trigger
  + integer brace-depth counter, throwing on `depth !== 0`.
- `extractTrainerParties.ts`: comment strip + manual brace matching for C
  structs — no C parser.
- *Evolution:* `spory-sparser/src/parseMaps/Trainers/trainerInc.ts`
  extended the same model to multi-line constructs via `parenDepth`
  tracking rather than adopting a token engine.

### 3.9 Comments carry rationale, not narration — Moderate

- `stapl-api/src/runQuery.ts` JSDoc argues *against* using
  `runQueriesSequence` unless `QTEMP` is needed and suggests the better
  shape.
- `stapl-api/src/client/handleError.ts`: `/** You best not send this to
  the client. */`
- `stapldb2/CONVERSION_NOTES.md` records design debates and deferred
  decisions.
- Porydaw headers state seam contracts directly
  (`projectworkspace.h:26-30`, `workspaceui.h:46-52`).

## 4. Tensions and counterexamples — do not flatten these

The honest picture includes real internal tensions. Forcing consistency
here would misrepresent the practice.

**Fail-fast vs. self-healing.** The corpus shows a *dual* error
philosophy, not a single one. Algorithmic kernels throw immediately
(`sfc32.ts`, `trainerIdExtractor.ts` "Save must be at least 128KB";
`spory-sparser/src/main.ts` hard throw on missing trainer ID). But
application/UI layers heal defensively: `useCaughtStore/actions.ts`
catches IndexedDB failure and runs `db.recreate()`; `setSelectedMap.ts`
logs and calls `deselectMap()` on unresolvable data; `Map.tsx` wraps each
panel in its own `ErrorBoundary`; `descriptionWorkerService.ts` has two
distinct fallbacks — the async `getMapDescription` returns a
`Promise<string>` with a 2000ms `setTimeout` fallback, while the
separate synchronous `getMapDescriptionSync` returns an immediate
static fallback and queues background metadata updates. Batch loops get
a third mode: `spory-sparser/src/parseMaps/index.ts` catches
per-directory failures so the batch completes. The current guide
already encodes this split: "never add recovery for a state the design
says cannot occur" applies inside `core/`, while "bounded resilience
belongs at user-facing and external-system seams" — matching the
observed evidence that the real rule is *where* the code sits.

**Derive vs. cache.** §3.1's counterexamples show eager precomputation
is standard when interaction latency demands it. The tension is
resolved by cost, not principle: derivation is the default; caching is
justified by an observable consumer (frame rate, lookup latency). The
current guide's materialization clause names four acceptable reasons —
throughput, atomic publication, lifecycle, and non-repeatable cost —
and the eidex evidence shows that bar is met often, not rarely.

**Domain decisions vs. option bags.** The guide says "build around a
domain decision," yet `stapldb2`/`stapl-server` internals run on
polymorphic option bags (`options: { returnNumbers, debug, rowsAffected,
pool }`) and string-typed query kinds. Public facades are domain-named;
internal plumbing is generic. Both are real.

**No abstraction vs. boundary wrappers.** `HttpClient.ts` wraps a single
Undici call in a `RetryAgent` subclass; `TokenClient` uses DI around one
token flow. Small abstractions are accepted when they isolate flaky
external protocol mechanics — retries are bounded (max 3, linear
backoff) and applied only to idempotent handshakes, never to general
mutations
(SQL has no retry; *(inference)* the packet records the absence of SQL
retry but no stated rationale — avoiding double execution is the
analyst's reading, not a documented motive).

**Testing.** The style guide's "checks and proof" section is aspirational
for the TS corpus: `mktcli` has one smoke test; `lexerr` and
`spory-sparser` have zero test suites — correctness was defended by
runtime Zod schemas and script execution. `eidex` does have real store
tests (`caughtEncounterStore.test.ts`, `setSelectedMap.test.ts`), and
Porydaw has an extensive `src/checks/` harness culture mandated by
`AGENTS.md`. So "writes checks" is a *Porydaw-local* and late-era
practice, not a career-long habit.

## 5. What cannot be concluded from this corpus

- **C++ style beyond Porydaw.** Porydaw is the only C++ codebase in the
  corpus. Whether the functional-core/imperative-shell split is a
  durable preference or a project-specific answer to Qt threading cannot
  be determined from one data point.
- **Formatting and naming micro-style.** The historical sources are
  inconsistent (ES5/CommonJS vs. TS ESM; Joi vs. Zod; varying quotes and
  semicolons). No cross-repo formatting rule is derivable — which is why
  the guide defers to `clang-format` and nearby code.
- **How Spencer behaves on teams.** The Spencer-attributed subsets of
  the corpus are effectively solo-authored — but attribution is
  partial: the packet documents non-Spencer sprite/image code,
  third-party refactoring-assistant output, generated code, and
  untouched scaffolding (§1). Conventions for code review, API
  negotiation, or shared-ownership compromise are unobservable here.
- **Performance engineering depth.** The corpus shows latency-conscious
  caching and worker offloading in eidex, but contains no profiling
  artifacts, benchmarks, or hot-path optimization history. Claims about
  systems-level performance discipline would be speculation.
- **Anything from the excluded lexerr/spory-sparser image paths.** Per
  §1, sprite/picture parsing is not Spencer's work and informs nothing.

## 6. Implications for Porydaw

Porydaw is where these tendencies are most fully realized — and where
some of them are *project-local rules* rather than personal defaults:

- **Porydaw-local, mandated by AGENTS.md:** the `src/checks/` harness
  culture and `deno task verify` gate; `layout::` primitives for all
  widget geometry; file-size discipline (200–400L target); keyboard
  shortcut arbitration.
- **Porydaw-observed idioms, not AGENTS.md mandates** *(inference —
  the packet classifies these as inferred personal defaults realized in
  this codebase, not written repo rules)*: `QUndoStack`-owned document
  mutation; `std::variant` exhaustive failure types; borrow-safe swap
  discipline.
- **Personal defaults that happen to hold here:** facts-vs-projections
  (`SmfFile`/`SongCfg` vs. `MidiTimeline`/`SongViewModel`); boundary
  validation with clean interior; top-down main paths; high abstraction
  threshold; single ownership with atomic transitions
  (`ProjectWorkspace`, `SongTab`); explicit lifecycle coordination
  (`InputGate`, `ProjectOpenState`, parked leases).
- **Where a flat reading of the guide overshoots:** unqualified "no
  recovery behavior" and "no caching" readings conflict with observed
  practice; the accurate forms are "fail fast in kernels, heal at
  UI/orchestration seams" and "derive by default, cache for observable
  latency." The
  operational condensation in [../STYLE_GUIDE.md](../STYLE_GUIDE.md)
  carries these qualifications; this file carries the evidence behind
  them.
