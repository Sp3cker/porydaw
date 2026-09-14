# Architecture quiz — revision 2 evidence

Historical, non-normative. Fresh readers had only the normative book, not earlier reports or author keys. The initial transport rejected overlength fields; complete original answer payloads were recovered from the agents' recorded yield calls. No answer coaching or new quiz was used for recovery. These reports include any remaining mistakes; the author's rulings are in audit.md.

## HintRetestInterfaces

```json
{
  "answers": [
    {
      "answer": "Edit only the catalogue: src/ui/mousehints/hintprofiles.cpp, where all hover-hint literal phrases/templates live. The velocity element keeps only its classification role: selecting inventoried profile IDs (VelocityNote / VelocityBackground / VelocityGutter) from its existing hit result. It no longer owns any wording, modifier formatting, joining, or rendered-text cache.",
      "confidence": "high",
      "evidence": "spec.md ownership table + 'All hover-hint literal phrases and templates reside in hintprofiles.cpp'; task-1 brief step 2.",
      "id": 1,
      "naturalExpectation": "Naturally I'd edit velocityarea_interaction.cpp::ensureMouseHintProfiles. The book's rule that listed producer paths are 'authorities to extract, not permanent dependencies, and ensureMouseHintProfiles is deleted' is the corrective."
    },
    {
      "answer": "Ruler handle and voice plot background share the public HorizontalScroll profile — the spec explicitly replaced draft RulerHandle/VoicePlot IDs because action set and modifiers are identical regardless of element class. TrackScope and EventRows must NOT merge: TrackScope lacks the additive Control+Shift range EventRows includes. Text equality proves nothing; divergence later justifies a split then.",
      "confidence": "high",
      "evidence": "spec.md ID table HorizontalScroll row; 'Share a complete profile when the current action set and modifiers are the same'; 'Do not merge TrackScope with EventRows'.",
      "id": 2,
      "naturalExpectation": "Consistent rule: identical actions+modifiers → merged; differing list → separate even if sentences look similar. I wouldn't have merged on name similarity; no disagreement once the wheel/Control+Shift rows are read."
    },
    {
      "answer": "The no-hint host publishes/claims Id::Empty — an ownership claim with blank text, not an admission exemption. Different operation from clear(): claim moves ownership (an admitted claim transfers source observations even when ID/text match or text is blank); clear(source) ends that source's ownership. Afterward the new Empty source IS current source owning blank text; the old target's leave has nothing to clear.",
      "confidence": "high",
      "evidence": "spec.md Profile identity + admission rules 2–3; task-4 'the dispatch fallback claims Empty'.",
      "id": 3,
      "naturalExpectation": "Blank reads like 'nothing published' or a clear(). Renaming None→Empty ('a valid empty description, not the absence of a source') is the deliberate surprise, though observable mechanics end up similar."
    },
    {
      "answer": "No. Admission rule 3: an admitted claim transfers the source observations even when ID or rendered text match. Only the signal is conditional: hintChanged is emitted only when resolved final caption text changes. After A's leave: clear(A) is source-checked and changes nothing because B owns the display; B stays current source and wording stays visible unchanged.",
      "confidence": "high",
      "evidence": "spec.md Claim admission rules 3–4; 'A rejected source changes neither source nor caption'; task-2's source-checked clear.",
      "id": 4,
      "naturalExpectation": "I'd expect a same-profile move to short-circuit on text equality. Rejected: the currentSource observation must transfer to B; only the caption signal may be suppressed."
    },
    {
      "answer": "No. Empty is never an exemption at either gate. The covered source is rejected by the existing Quick host mute / HoverHint session-ownership gate BEFORE claim (or native allowsSource); a rejected source changes neither current source nor caption. The popup's own admitted Empty claim is a different source and legitimately moves ownership with blank text. Same verb, different sources.",
      "confidence": "high",
      "evidence": "spec.md admission items 1–2, 'Empty is never an exemption'; 'the popup's own admitted Empty claim and a covered control's rejected Empty request are different sources'.",
      "id": 5,
      "naturalExpectation": "I might expect blank text to bypass suppression or need a world-visible flag for Empty. The book keeps existing physical gates and gives Empty no exemption — the simpler design, and I agree."
    },
    {
      "answer": "Automation's own local classifier selects it: AutomationCanvas keeps a local ui::hint_profiles::Id mouseHintProfile() const reading existing hover/tool state (invalid lane → Empty). Applied via the existing primary host's non-claiming refreshMouseHint (current source only). If another source owns the display, refresh declines; the code must NOT fall back to resyncMouseHint or claim to steal the foreign source. Task 7 keeps the classifier; task 4 hosts it.",
      "confidence": "high",
      "evidence": "spec.md 'Physical C++ hosts and domain selectors' ('stationary pencil change uses the existing primary host's non-claiming refresh… never falls back to resync'); task-7 item 3.",
      "id": 6,
      "naturalExpectation": "Given a window-level MouseHints, I'd expect a stationary change to re-claim or use resync to reassert. The refresh-is-non-claiming / resync-is-recovery-only distinction is the subtle rule; keep it near the call site."
    },
    {
      "answer": "setWidgetProfile assigns a COMPLETE profile, not pointer-only metadata. The NativeFineSpinEditor catalogue entry already contains fine drag PLUS style-modified wheel step-by-ten, so the inherited wheel alternative comes from the catalogue; the observer never formats text and must not append inherited wheel text after an explicit complete profile. Metadata is the porydaw.mouseHintProfile property ID; missing means infer native family; explicit Empty means a complete blank override, not missing metadata.",
      "confidence": "high",
      "evidence": "spec.md 'Native adapter: complete profiles'; native mapping list; 'Missing property means infer the native family; explicit Empty means a complete blank override'.",
      "id": 7,
      "naturalExpectation": "The name, following setPointerDescription(QWidget&, QString), suggests a pointer-fragment override composed with a separately rendered wheel string. Replacing that contract is deliberately called out as removing the 'half-profile' surprise."
    },
    {
      "answer": "A zero spin style modifier removes only the accelerated-step alternative; never render bare 'wheel: step by ten'. (a) Spin body (NativeSpinBox): renders empty. (b) Ordinary editor (NativeSpinEditor): keeps text selection without the wheel clause. (c) Fine editor (NativeFineSpinEditor): keeps fine drag without the wheel clause. No QML change: DragScrub has its own fixed Control wheel handler. Style change selects a new (profile, stepModifier) cache key, not a cache flush.",
      "confidence": "high",
      "evidence": "spec.md zero-style paragraph (all three outcomes verbatim, verbatim); DragScrub unaffected note; task-3 acceptance 'all three zero-style spin results'.",
      "id": 8,
      "naturalExpectation": "I might expect the whole widget to fall back to a generic wheel description, or QML numerics to change too. Making each residual alternative explicit is more informative than my guess."
    },
    {
      "answer": "The native spin style step modifier. Public invokable signature is claim(QObject*, Id); a private non-invokable three-argument overload takes Qt::KeyboardModifiers, reachable only through the existing WidgetHintsObserver friendship. The observer obtains it from already-read spin style facts (spinBoxFor / configuration-owner reads) and calls the private overload even when it is NoModifier. Ordinary C++ elements and QML cannot pass it: no style parameter, no second public verb, no ordinary producer selecting native spin IDs.",
      "confidence": "high",
      "evidence": "spec.md Claim admission section (two overloads, friendship, forbidden style exposure); task-3 (observer supplies style modifier to private overload); task-2 contract.",
      "id": 9,
      "naturalExpectation": "I'd have expected one public claim with a defaulted modifier argument. Hiding it behind a friend-only overload prevents QML producers spoofing native-spin styling — reasonable, though it leans on C++ friendship discipline."
    },
    {
      "answer": "Two mechanics: (1) the enum namespace is registered once per process — qmlRegisterUncreatableMetaObject(ui::hint_profiles::staticMetaObject, \"Porydaw.Ui\", 1, 0, \"HintProfiles\", \"Enum values only\") inside TimelineQuickView's existing function-local static std::once_flag before any tab's QML loads; (2) each view installs its existing mouseHints context property into its own engine, all borrowing the same application-owned MouseHints and catalogue. Do NOT replace the context property with qmlRegisterSingletonInstance or create per-tab MouseHints objects.",
      "confidence": "high",
      "evidence": "spec.md 'QML: enum constants, no text transport' (registration once per process, per-engine context install, forbid qmlRegisterSingletonInstance); task-6 step 1 and constraints.",
      "id": 10,
      "naturalExpectation": "I'd assume per-engine registration of the QML type and might 'upgrade' the context property to a singleton. The book's split — process-wide enum, per-engine context property — is the opposite instinct and what the two-tab smoke verifies."
    },
    {
      "answer": "HoverHint stores an enum-valued integer: 'property int profile: HintProfiles.Empty' (and _gestureProfile as originating-gesture integer ID). Not a sentence, string key, or object. The public C++ publication parameter is the enum ui::hint_profiles::Id (QML constants are integer-valued, but the claim parameter stays enum-typed). If enum delivery fails at runtime, do NOT silently substitute a QString/int fallback: diagnose registration/AUTOMOC/module wiring and revise the contract through review if needed.",
      "confidence": "high",
      "evidence": "spec.md QML section (property int profile; 'C++ claim parameter remains enum-typed'); task-6 constraint against int/QString fallback; spec Evidence section on diagnosing registration.",
      "id": 11,
      "naturalExpectation": "Since the field is int, I'd expect the C++ seam to accept int too. The typed-enum boundary is deliberate; storage type and C++ payload differ but agree in intent — no conflict once stated."
    },
    {
      "answer": "The graph is both classifier and physical source, so it retains its single originating profile itself: m_gestureProfile (renamed from m_hintText), initialized Empty, captured at gesture start. During the gesture every update claims the captured ID without re-applying the idle classifier — even crossing blank plot space. Reclassification happens only via the existing idle path or terminal inside-settlement; outside settlement clears. TimelineInputItem must NOT gain a retained field: it retains ownership through its existing domain/dispatch flow; only payload types change.",
      "confidence": "high",
      "evidence": "spec.md PitchBendGraph paragraph and 'Do not add a retained-profile member to TimelineInputItem'; task-5 steps, task-4 constraints.",
      "id": 12,
      "naturalExpectation": "I'd expect the same retention shape (or none) on both drag surfaces. The book preserves a pre-existing asymmetry — the graph historically needed a gesture member, the timeline host never did. Documented but the least uniform part."
    },
    {
      "answer": "Only in the catalogue (owned by MouseHints, application lifetime, keyed by profile + spin style modifier for the three native spin profiles only) and in final presentation state: MouseHints' private m_text and the caption's displayed QString. Producers may not cache QStrings; their old caches are deleted. Tab close/reopen changes nothing: cache and current source are not tab/widget lifetime. An empty rendered string is a valid cached result, not a cache-miss sentinel; do not let a null QString re-render empty profiles.",
      "confidence": "high",
      "evidence": "spec.md catalogue-cache section ('lifetime… not widget or tab lifetime'; 'Empty rendered text is a valid cached result'); admission section allowing MouseHints/catalogue/caption text; task-8 audit item 5.",
      "id": 13,
      "naturalExpectation": "Empty-as-cache-hit is surprising — empty usually signals miss — and QString caches are naturally suspected in producers today (velocity's cached strings, AutomationCanvas caches); the plan deletes all of those."
    },
    {
      "answer": "Read the canonical configured binding inside catalogue rendering via keymap::Registry::modifierBinding for roll.velocity_drag and velocity.detent_unlock. Do not hard-code Control, accept from elements, or watch held keys — the catalogue reads config bindings, not input state or eligibility. The existing equal/unequal-chord branch moves intact: equal detent/add-selection chords get one combined drag explanation; different chords get separate explanations. Not the 'Shift or Alt' equivalent-action template.",
      "confidence": "high",
      "evidence": "spec.md catalogue-interface final paragraphs (modifierBinding; 'does not inspect held keys or decide action eligibility'; chord branch); task-1 step 2.",
      "id": 14,
      "naturalExpectation": "I expected interaction code to know the chord and pass a rendered phrase. Routing reads into catalogue rendering via the Registry is centralization's point; hard-coding Control would diverge from configurable bindings."
    },
    {
      "answer": "Add: a new ID in the hint_profiles inventory plus its catalogue rendering (task-1 write set); the target's already-computed hit result selects the ID at its existing call site; existing admission handles ownership. Must NOT be added: new lifetime/registration machinery, availability filtering, held-key listeners, caches, aliases, or a new claim verb. A public fragment builder would NOT help: fragments stay private rendering ingredients; composition lives entirely in the catalogue.",
      "confidence": "high",
      "evidence": "spec.md 'Do not expose… public fragment arrays'; 'Partial fragments used inside larger profiles remain private rendering ingredients'; task-1 constraints.",
      "id": 15,
      "naturalExpectation": "I'd expect a build-a-sentence-from-parts API to scale. The book says a new action is usually a new complete profile; my fragment-builder instinct is blocked deliberately in favor of consistency."
    },
    {
      "answer": "Keep the existing target's profile. Classification (what the target does) and action eligibility (whether useful now) are separate: interaction modules select the ID from the existing hit/layout classification and do not re-classify per document context or selection; nothing inspects the document to decide display validity. Switching to Empty for temporary futility would be new availability filtering, which the plan forbids.",
      "confidence": "high",
      "evidence": "spec.md 'not… an action registry', 'no new availability filtering'; task-3 'do not infer action eligibility'; catalogue 'does not inspect held keys or decide action eligibility'.",
      "id": 16,
      "naturalExpectation": "I might expect the hover system to switch to Empty when an action can't apply — helpful UX. That's exactly the forbidden 'second behavior'; display always tracks target classification. Aesthetic disagreement, consistent scope."
    },
    {
      "answer": "No. Tasks 1–7 form one atomic production cutover: no intermediate build, behavioral acceptance, or Git checkpoint of a half-migrated interface. No QString compatibility overload exists — the gate demands clean cutover with no parallel old path and no remaining publish caller. Task 7 (direct migration contract) owns every outstanding producer/recorder migration: TimelineInputHost virtuals, both test adapters, all remaining C++ producers, and every QML text binding; it executes atomically against the settled catalogue interface alongside tasks 2–6.",
      "confidence": "high",
      "evidence": "plan.md task table ('one atomic production cutover… no intermediate build… or Git checkpoint'), constraint 2; task-2 'no QString or old-name escape hatch'; Task 7 write set.",
      "id": 17,
      "naturalExpectation": "I'd expect incremental tasks with per-task green builds and checkpoints. The ~30-file atomicity is the least intuitive choice, deliberately protecting one instance of interface-change breakage; per-task commits are prohibited."
    },
    {
      "answer": "Not established: AUTOMOC processing the new Q_NAMESPACE header; actual QML enum delivery; two-tab enum delivery with shared MouseHints; native style variants including the Qt::NoModifier path (blank spin body, residual editor/fine descriptions); composed hover on roll, QML numeric, event row/inline editor, native fine/ordinary controls; blank claims and source transfer across equal-profile fields; stationary pencil change; popup dismiss; real window capture rather than press/move/release substitution. Also required: named filters confirmed against checkcatalog.cpp, native edge smoke, structural cutover audit (no publish/fragments/caches/format-only helpers; no new hit tests/state machine), format check, and the cumulative thermo-nuclear review. Authority: the original spec/plan rule behavior except the payload contracts the supplement supersedes.",
      "confidence": "high",
      "evidence": "plan.md Verification steps 1–6 ('planned verification, not checks already run'), capture/edge/audit/finish steps; supplement header superseding only payload contracts.",
      "id": 18,
      "naturalExpectation": "I'd have expected build + tests to suffice for 'done'. The plan demands composed window-level evidence at origin paths and honest limitation records — a higher bar than assumed."
    }
  ],
  "changes": [
    {
      "answer": "The porydaw.mouseHintProfile property conflates 'absent/inherit family' with 'explicit Empty' as a prose rule. A separate bool annotation or a distinct inherit sentinel would make the missing-vs-explicit-Empty distinction (Q7) evident from the annotation itself instead of documentation."
    },
    {
      "answer": "The claim(QObject*, Id) / private claim(QObject*, Id, Modifiers) split relies on WidgetHintsObserver friendship. A small typed native-claim entry point visible only to widgethints would remove the friendship tier and the 'why two overloads' surprise while keeping the same gate."
    },
    {
      "answer": "Collapse the selection rules to one uniform shape — producers keep no QString and one local Id classifier where they already classify (automation's mouseHintProfile()), everything else a direct ID at the call site — instead of enumerating per-producer removals across task 7."
    }
  ],
  "contradictions": [
    {
      "answer": "Minor wording tension only: admission rule 3 says matching ID/text still transfers observations, while task-2 phrasing warns to 'suppress an unchanged-text signal' — coexistable (transfer vs signal differ) but the single ordered rule should enumerate rejection/transfer/signal in one place. No unimplementable requirement found in plan, spec, or briefs; write sets are disjoint with fixed pre-dispatch interfaces."
    }
  ]
}
```

## HintRetestMaintenance

```json
{
  "answers": [
    {
      "confidence": "high",
      "evidence": "spec.md Ownership table element row; ID table VelocityNote row; Task 7 §3 removes VelocityArea::ensureMouseHintProfiles and its cached strings",
      "id": 1,
      "answer": "Edit only src/ui/mousehints/hintprofiles.cpp (task 1's catalogue), which owns all literal wording and rendering. The velocity element (velocityarea_interaction.cpp) is emptied of text by task 7 and continues only to classify its existing hit result, select VelocityNote, and publish the typed claim through its physical host — no sentence, modifier label, or fragment material.",
      "naturalExpectation": "Exactly as expected for a centralized catalogue: wording in one file, the element keeps pure classification. The detent modifier itself is read from the keymap by the catalogue, so it is not the designer's editing concern."
    },
    {
      "confidence": "high",
      "evidence": "spec.md ID table HorizontalScroll row and merge/don't-merge paragraph",
      "id": 2,
      "answer": "Ruler handle and voice plot background share one public ID, HorizontalScroll — it explicitly replaces the draft's separate RulerHandle/VoicePlot IDs because their complete current action set and modifiers are identical regardless of element class. TrackScope must NOT merge with EventRows: EventRows includes the additive Control+Shift range that TrackScope explicitly lacks. Partial duplication removed: fragment strings, modifier-label rendering, and separator joins become private ingredients inside hintprofiles.cpp; producers lose all text, not public profile identity.",
      "naturalExpectation": "Same complete behavior, same profile — agreed. The caveat that text equality alone does not prove behavioral equality (TrackScope/EventRows are near-identical yet diverge) is a nuance requiring reading actual modifier sets, not just names."
    },
    {
      "confidence": "high",
      "evidence": "spec.md 'Empty deliberately replaces None…'; Claim admission rules 1–4; original spec 'clear…Unhover uses this, not empty publication'",
      "id": 3,
      "answer": "The new no-hint target publishes claim(source, Id::Empty) through its existing host — a real ownership claim with blank text. Not the same operation as the old target ending hover: unhover is clear(source), which only ends that source's ownership and installs nothing. An admitted Empty claim still transfers the source observations after the host mute and native/allowsSource gates, and emits nothing only when final text is unchanged. Afterward the new target owns blank text; the old target owns nothing.",
      "naturalExpectation": "Naive reading treats blank as absence of a source (clear); the book deliberately defines Empty as an owned blank claim — accepted once read, and the identical-text transfer rule explains why."
    },
    {
      "confidence": "high",
      "evidence": "spec.md Claim admission rule 3 'transfers the source observations even when the ID or rendered text matches'; rule 4",
      "id": 4,
      "answer": "Yes — admission still happens: B's claim transfers ownership/source observations even though profile and rendered text match A's, because text identity is not owner identity. What may be skipped is only resolution/emission churn when final text is unchanged. After A's late, source-checked leave (clear) is handled, A no longer owns anything, so B's ownership and the unchanged visible text stand — no regression to A or blank.",
      "naturalExpectation": "Natural shortcut would be 'same text, skip everything'; the book separates ownership transfer from text change precisely so a stale leave cannot erase the current owner. I agree with the book."
    },
    {
      "confidence": "high",
      "evidence": "spec.md Claim admission rule 2 'Empty is never an exemption at either gate'; original spec three-gates table",
      "id": 5,
      "answer": "No. The covered control's Empty request is rejected at the Quick host gate (HoverHint skips when quickPopupSession.isOpen && !quickPopupSession.owns(source); TimelineInputItem skips while view-muted) before claim is even called; a direct call would then still be rejected by MouseHints' native/application allowsSource check — Empty is never an exemption at either gate. A rejected source changes neither source nor caption, so the popup's blank stays. The popup's own admitted Empty claim uses its physical overlay root via claim(source, Id::Empty) — a different SOURCE, not a different kind of empty value.",
      "naturalExpectation": "One might assume blank text is harmless and bypasses suppression; the book forbids that at both gates while keeping the two gates distinct. I agree — the separate overlay-root ownership is the clean part of the design."
    },
    {
      "confidence": "high",
      "evidence": "spec.md Physical C++ hosts; 'A stationary pencil change uses the existing primary host's non-claiming refresh'; task-4-brief",
      "id": 6,
      "answer": "AutomationCanvas's own local classifier decides: its kept local mouseHintProfile() reads existing hover/tool state and returns AutomationPencil instead of AutomationSweep. The update goes through the existing primary plot host's non-claiming refreshMouseHint(Id), which publishes only when this item still owns the display. If another source already owns the display, refresh does nothing (never steals), and the design explicitly forbids falling back to resyncMouseHint to steal after refresh declines — resync is only the existing guarded recovery path.",
      "naturalExpectation": "I would naturally have called the claiming setMouseHint for a new profile; the non-claiming refresh is the ownership-respecting op and the no-steal rule protects a foreign owner."
    },
    {
      "confidence": "high",
      "evidence": "spec.md Native adapter 'complete profiles, not partial overrides'; task-3-brief 'complete, not a pointer-only override'",
      "id": 7,
      "answer": "setWidgetProfile assigns a COMPLETE description, not pointer-only metadata: the catalogue entry NativeFineSpinEditor already includes the inherited style-modifier wheel step-by-ten, and no wheel text is appended after the explicit profile. The inherited wheel alternative lives in the catalogue profile, with the actual modifier value passed from the owning spin's style read via the private three-argument claim overload. Missing property means infer the native family (a real complete profile); explicit Empty means a complete blank override, not missing metadata.",
      "naturalExpectation": "The old setPointerDescription contract was literally a pointer fragment overriding half a profile; a maintainer would expect partial concatenation until reading this — removing that surprise is a stated goal."
    },
    {
      "confidence": "high",
      "evidence": "spec.md zero-style result paragraph and Native inference mapping; DragScrub note",
      "id": 8,
      "answer": "NoModifier removes only the accelerated-step alternative. (a) spin body: NativeSpinBox renders empty. (b) ordinary embedded editor: NativeSpinEditor retains its text selection description (wheel alternative removed). (c) fine-drag editor: NativeFineSpinEditor retains fine drag with no ordinary text-selection description. Never render bare 'wheel: step by ten' without a modifier. A QML numeric input does NOT necessarily change: DragScrub has its own fixed Control wheel handler and is unaffected by native spin style changes (configuration selection, not availability filtering).",
      "naturalExpectation": "(b) initially surprised me: 'retains text selection' means half of the ordinary editor's complete profile survives; with complete-profile plus cache-key semantics the outcome is coherent."
    },
    {
      "confidence": "high",
      "evidence": "spec.md Claim admission code block; task-2/task-3 briefs",
      "id": 9,
      "answer": "The three native spin profiles (NativeSpinBox, NativeSpinEditor, NativeFineSpinEditor) need the extra parameter: the private, non-invokable three-argument claim(QObject*, Id, Qt::KeyboardModifiers stepModifier). The parameter is obtained by WidgetHintsObserver — using the existing WidgetHintsObserver friendship — from the owning spin's style read. Ordinary elements and QML cannot pass it: the public Q_INVOKABLE claim takes only source+profile and delegates with Qt::NoModifier; no style parameter is exposed to ordinary elements or QML and no parallel public verb exists.",
      "naturalExpectation": "Reasonable: friendship is the pre-existing native channel. In a fresh design I might prefer a narrower internal boundary than whole-service friendship, but that is taste, not disagreement."
    },
    {
      "confidence": "high",
      "evidence": "spec.md QML registration block; task-6-brief step 1 and constraints",
      "id": 10,
      "answer": "HintProfiles constants reach the second engine by process-wide registration: qmlRegisterUncreatableMetaObject(ui::hint_profiles::staticMetaObject, \"Porydaw.Ui\", 1, 0, \"HintProfiles\", …) once per process inside TimelineQuickView's existing function-local static std::once_flag block, before any tab's QML loads. The mouseHints context property remains per-engine/per-view-installed, and every engine's instance borrows the same application-owned MouseHints and catalogue. Do NOT replace the context property with qmlRegisterSingletonInstance and do not create per-tab MouseHints objects.",
      "naturalExpectation": "I would naturally have wanted qmlRegisterSingletonInstance; the book's split (process-wide enum registration, per-engine context-property borrowing of one shared object) avoids per-tab duplicate MouseHints and needs no new singleton machinery — I agree after reading."
    },
    {
      "confidence": "high",
      "evidence": "spec.md QML section property lines; task-6-brief no-fallback constraint",
      "id": 11,
      "answer": "HoverHint stores an integer-valued enum ID: property int profile defaulting to HintProfiles.Empty; the gesture-state counterpart is _gestureProfile, also an integer ID. No sentence, no string name, no object. The public C++ publication parameter remains enum-typed ui::hint_profiles::Id in Q_INVOKABLE claim. If enum delivery fails at runtime, no silent fallback is defined: diagnose the registration (AUTOMOC of Q_NAMESPACE, qmlRegisterUncreatableMetaObject) or update the contract through review rather than replacing the typed interface with a QString/int fallback.",
      "naturalExpectation": "I might expect automatic QML-int↔C++-enum coercion to be relied on; the book pins the C++ parameter as enum-typed and treats any int/QString fallback as a failure to diagnose, not a design."
    },
    {
      "confidence": "high",
      "evidence": "spec.md Graph profile retention; task-5-brief; task-4-brief no-retained-member constraint",
      "id": 12,
      "answer": "PitchBendGraph retains the captured originating profile in its own m_gestureProfile (renamed from m_hintText, initialized Empty), captured at gesture start. During the active gesture every update reuses that captured ID — even across blank plot space — without invoking the idle classifier; reclassification happens only through the existing idle or terminal inside-settlement path, and outside settlement clears. TimelineInputItem gains NO retained-profile field: it already retains ownership through its existing dispatch flow without such storage; task 4 changes payload types only.",
      "naturalExpectation": "Symmetric retention in the timeline host would be my first guess; the book justifies the asymmetry because the graph is both classifier and physical source while the timeline host's dispatch flow preserves ownership without new state."
    },
    {
      "confidence": "high",
      "evidence": "spec.md Catalogue interface and cache; 'catalogue and caption may store rendered text; producers do not'",
      "id": 13,
      "answer": "Rendered strings are cached only in the application-owned MouseHints' by-value Catalog (keyed by profile, plus style-modifier for the three native spin profiles only), plus MouseHints' private final m_text presentation state and the caption widget's displayed QString. Cache lifetime is the owning MouseHints/QApplication lifetime, NOT widget or tab lifetime — closing and reopening a tab does not invalidate it. An empty rendered string is a valid cached result, not a cache-miss sentinel; a null QString must not cause re-rendering. Producers store no rendered text and no per-widget text/key caches.",
      "naturalExpectation": "Per-tab or per-widget caches dying with the widget/tab would be natural; the central app-lifetime cache is simpler and gives one place to revise if runtime language switching ever arrives."
    },
    {
      "confidence": "high",
      "evidence": "spec.md keymap paragraph 'Catalogue interface and cache'; original spec Presentation bullets",
      "id": 14,
      "answer": "The catalogue reads the canonical configured binding (roll.velocity_drag / velocity.detent_unlock) through keymap::Registry::modifierBinding inside rendering — not hard-coded Control, not accepted from elements, not held-key watching, and it does not decide eligibility. The existing equal-chord/unequal-chord composition branch moves intact: equal detent/add-selection chords get one drag explanation combining 'without detents' and 'preserving selection'; different chords get separate drag explanations — distinct from the generic 'Shift or Alt' equivalent-action template.",
      "naturalExpectation": "Matches: the modifier authority stays in one place (the registry binding), and the wording branch just moves home with the literal phrases."
    },
    {
      "confidence": "high",
      "evidence": "centralization spec.md 'A profile is not a sentence fragment…'; task-1-brief constraints",
      "id": 15,
      "answer": "Add a new inventoried Id to the catalogue (task-1's write set via a documented contract correction) with its complete description, plus the classifier change in the owning interaction. Do NOT add to the catalogue or source-lifetime machinery: new hit resolvers, action-registry entries, availability filtering, source/claim machinery, new cache rules, or held-key logic. A public fragment builder is explicitly not part of the intended design: profiles are complete entries, fragments stay private, and the maintainer writes one whole sentence in the catalogue instead of composing fragments at the caller.",
      "naturalExpectation": "I would instinctively want a public fragment builder to compose 'common piece plus new action'; the book deliberately makes descriptions whole catalogue profiles — simpler for callers, slightly more duplication inside the catalogue. I accept the trade."
    },
    {
      "confidence": "high",
      "evidence": "spec.md flow sentence + catalogue-not-document rules; original spec 'No availability checks, dimming…'",
      "id": 16,
      "answer": "The existing target's profile remains published. No availability checks exist: no dimming, selection/value/document eligibility, canGhostParameter, or enabled-command queries. Each profile describes the complete set of alternatives for the selected behavior/configuration, and the catalogue never inspects the document, selection, or held keys. Target classification (which already-classified hit result is under the pointer — body vs edge vs gutter) is the element's existing duty; action eligibility (would this action affect the current selection) belongs to actual execution, never to the hint path.",
      "naturalExpectation": "Matches the original spec: list all alternatives immediately with no availability filtering; this refactor only re-homes where the classification text is produced."
    },
    {
      "confidence": "high",
      "evidence": "plan.md Global constraint 5; Task 7 contract; spec.md Global constraints 2",
      "id": 17,
      "answer": "No partial acceptance or checkpoint: tasks 1–7 are one atomic cutover, no intermediate build/Git checkpoint of a half-migrated interface. No compatibility overload exists; virtuals, QML, native annotations, and test recorders migrate simultaneously. Task 7 owns the outstanding producer/recorder migration.",
      "naturalExpectation": "Naively I would checkpoint the compiling C++ half separately; atomicity exists because a virtual/QML interface cannot be half-migrated. I agree, at the cost of a large combined change window."
    },
    {
      "confidence": "high",
      "evidence": "spec.md Authority section; plan.md Verification and Milestones",
      "id": 18,
      "answer": "Build success plus a correct quiz prove neither runtime correctness nor composed behavior: unproven are actual hover wording in every face, QML enum delivery at runtime, native style-modifier/NoModifier spin paths, popup/scope behavior, real composed smoke, and the structural cutover audit. Authority: the original behavior spec remains authoritative for behavior; the supplement supersedes only description ownership, string-payload interfaces, rendered-text caching, and the original four-new-files limit (adding the two catalogue files). Required before 'complete': the task-8 verification trail — build/registration, six named filter checks, real composed smoke with window capture, the uncertain native edge, structural audit, format check, and the cumulative read-only thermo-nuclear quality verdict.",
      "naturalExpectation": "Aligned: build success and a quiz pass are far short of the acceptance bar; runtime proof requires launching the real app and exercising every listed face."
    }
  ],
  "changes": [
    "Restate-once: the atomicity/no-shim rule appears in plan.md global constraint 5, the Task-7 contract, task-brief contexts, and task 2/6 constraints. One canonical statement plus cross-references would prevent drift and shrink every brief.",
    "Have task 4 own the two test adapter files (they change only their overridden virtuals' payload type) so task 7 is purely producers; this removes the cross-task implicit ordering edge on timelineinput.h and aligns adapter migration with the host-contract task.",
    "State in one place which selectors may survive as C++ classifier functions (automation's local mouseHintProfile, graph's hintProfileAt, ruler's profile function) versus which must become inline call-site constants; today the rule is implied by examples only."
  ],
  "contradictions": [
    "timelineinput.h (the virtual-interface header) is written by task 7, while task 4 owns timelineinputitem.h overrides of those same virtuals and depends on task 7's signatures. Files are disjoint, but the shared signature decision sits inside task 7's write-set rather than the task-1 interface contract, so 'no file has multiple planned writers' is technically true yet contractually split.",
    "The original spec.md still mandates Q_INVOKABLE QString fragment and setPointerDescription(QWidget&, const QString&) and is declared 'authoritative for behavior'; only the supplement's opening paragraph marks those presentation-payload contracts superseded. A maintainer implementing from the original spec alone would re-add the removed public interfaces.",
    "Task 7 says simple two-way selectors become direct ID selection at call sites, not forwarding methods, yet preserves AutomationCanvas's local mouseHintProfile() classifier; the distinguishing criterion (reads hover/tool state vs pure pass-through) is implicit and could be read either way."
  ]
}
```

## Frozen revision 2 answer key

# Frozen author key — revision 2

Frozen before fresh-reader dispatch. Retain revision-1 scores separately. Score direct scenario outcomes and owning seam, not exact prose. Relevant incorrect extra assertions make an answer partial even when its opening answer is correct.

Q1: wording only hintprofiles.cpp; element selects VelocityNote; old ensureMouseHintProfiles deleted, not retained classifier.
Q2: ruler handle and voice background share HorizontalScroll because actual full action/modifier sets match; TrackScope/EventRows distinct (additive range differs); private sharing for partial fragments. No future-proof duplicate IDs.
Q3: admitted claim(new,Empty) owns blank; clear(old) only ends old ownership; not equivalent. Empty requires same gates as other IDs.
Q4: admission first then source transfer even same ID/text, only text-change signal suppressed; late A clear cannot clear B.
Q5: never exempt Empty; existing Quick host mute/HoverHint session-owns gates before claim; native/application allowsSource inside claim; popup's own admissible empty claim is different source not privileged empty value; catalogue no scope.
Q6: automation local classifier reads existing target/tool; primary host refresh current owner only, foreign ownership -> no-op, no resync fallback on tool change.
Q7: complete NativeFineSpinEditor includes wheel centrally; missing annotation infers family, explicit Empty complete blank override. No additional wheel concatenation.
Q8: NativeSpinBox(NoModifier) blank; NativeSpinEditor retains text selection; NativeFineSpinEditor retains fine drag. DragScrub fixed Control QML wheel unaffected.
Q9: only native observer private non-invokable claim(source,Id,styleModifier); read owning spin QStyle SH_SpinBox_StepModifier. Public C++/QML claim takes source,Id. Ordinary producers don't use native IDs pretending style zero.
Q10: enum namespace registered once process-wide with function-local static once_flag; context property installed per engine borrowing same application object/catalogue; no per-tab registration or MouseHints construction or singleton change.
Q11: QML enum-valued int, C++ Id argument; name claim; no strings/lookup/objects; diagnose registration/moc on failure, no silent int/QString fallback.
Q12: graph m_gestureProfile retains vertex ID across active drag, idle/release inside reclassifies, outside clears; QML _gestureProfile separate existing retention site, no new TimelineInputItem field.
Q13: by-value Catalog owned by application MouseHints, persists tabs and dies with owner; valid empty cached; final MouseHints m_text/caption/cache QStrings legitimate, no producer rendered caches.
Q14: canonical binding at lazy catalogue render, no held keys or local parameter/hardcoding. Equal detent/additive chords combine without-detents/preserve-selection drag wording; unequal separate. Not an or-template or combined chord.
Q15: new Id+complete catalogue description+existing resolver chooses Id; no centralized hit test/source machinery, public fragments, registration framework; existing behavior-sharing rule from Q2 applies.
Q16: existing target profile remains despite useless action; classification uses actual hit/tool/config, not static widget class alone; no availability filtering/document inspection by catalogue.
Q17: no mixed acceptance/checkpoint/shim; task7 owns remaining producers/virtuals/test recorders; atomic cutover accepted after all writers settled.
Q18: quiz learning, build compile only; original behavior spec vs new supplement payload/cache/interfaces; actual composed hover, enum invocation two engines, native style cases, existing suites and structural/cumulative quality gates still required.


## Revision 2 specification snapshot

# Centralized hover-hint profiles

Revision: **2 — revised after the first independent architecture quiz; fresh-reader retest pending**.

## Authority and scope

This supplements [the original behavior specification](../spec.md). It supersedes only description ownership, string-payload interfaces, rendered-text caching, and the original four-new-production-files limit. The two additional production files are `src/ui/mousehints/hintprofiles.h` and `hintprofiles.cpp`.

The original behavior specification still owns target coverage, action semantics, physical hover/grab lifetime, popup/native scope, accessibility, and layout. Preserve the verified implementation's wording, ordering, modifiers, and current status-bar appearance. Do not restore older appearance details while extracting descriptions. Existing fixes must be settled and verified before this refactor starts; this document does not certify them.

This is a refactor, not a new action registry, generic help framework, localization feature, or second input dispatcher. No new availability filtering, held-modifier listener, hit testing, recovery mechanism, or hover state machine.

## Ownership: classify, describe, claim, paint

| Module | Owns | Does not own |
| --- | --- | --- |
| Existing element/interaction | Existing target resolution; select a profile ID from that result | Hint sentences, modifier formatting, joining, rendered-text caches |
| `hintprofiles.h/.cpp` catalogue | Complete profiles, translated wording, fragment order, native modifier labels, cached rendering | QWidget/QQuickItem inspection, hit tests, cursor position, hover or grab ownership |
| Existing physical host and `MouseHints` | Source identity, permitted claims, retained gesture profile where already needed, refresh/clear | Action eligibility, new target resolution, wording assembly |
| Existing status caption | Paint/elide the final QString; expose full accessible description | Profiles, target selection, input handling |

The flow is **existing hit result → profile ID → existing admitted claim → catalogue rendering → existing caption**. Each profile describes the complete set of alternatives for the selected behavior/configuration; that set may be empty. A profile is not a sentence fragment, widget identity, or action command.

## Profile identity

Declare `ui::hint_profiles` with `Q_NAMESPACE` in `hintprofiles.h`, and `enum class Id` with `Q_ENUM_NS(Id)`. `Empty = 0` is the default. Do not expose string keys, widget class names, callable actions, or public fragment arrays.

`Empty` deliberately replaces the earlier proposal's name `None`: it is a valid empty description, not the absence of a source. `claim(source, Empty)` requests ownership with blank text; it does not bypass admission. `clear(source)` ends that source's ownership. The single admission/transfer rule is in [Claim admission and observation](#claim-admission-and-observation).

The following table is the complete initial ID inventory. The source paths are relative to `src/ui/` in the implementation checkout. They identify current wording/selection authorities to extract, not permanent dependencies or names to retain. In particular, the listed `ensureMouseHintProfiles` methods are deleted by task 7; they do not survive as aliases for the new selectors.

| ID | Existing authority and selection |
| --- | --- |
| `Empty` | Existing empty publications, inert targets, pinned graph endpoints, non-ruler velocity gutter |
| `TextSelection` | QLineEdit and QML text editors: Shift-click extension only |
| `NativePageStep` | `mousehints/widgethints.cpp::wheelDescription`: Control **or** Shift wheel page-step; includes item views with no pointer alternatives, headers, popup views and generic scroll areas/sliders |
| `NativeSingleSelection` | `widgethints.cpp::pointerDescription`: single-selection deselect **plus** native wheel page-step |
| `NativeExtendedSelection` | Same: toggle/range **plus** native wheel page-step |
| `NativeContiguousSelection` | Same: range **plus** native wheel page-step |
| `NativeSpinBox` | Spin body: style-modifier wheel or arrow-click step-by-ten |
| `NativeSpinEditor` | Embedded ordinary spin editor: text selection **plus** style-modifier wheel step-by-ten |
| `NativeFineSpinEditor` | `dragspinbox.cpp` editor: fine drag **plus** style-modifier wheel step-by-ten; no ordinary text-selection description |
| `NativeFinePageStep` | `transportbar.cpp::OutputVolumeDial`: fine drag **plus** native wheel page-step |
| `RollNoteBody` | `songview/pianoroll_geometry.cpp::rollMouseHints`: note-body alternatives plus plot alternatives |
| `RollNoteEdge` | Same: resize alternatives plus plot alternatives |
| `RollPlot` | Same: right-drag/time/marquee and wheel alternatives |
| `RollGutter` | Same: key-height/horizontal wheel alternatives only |
| `HorizontalScroll` | Shared complete Shift-wheel horizontal-scroll behavior: ruler handles (`songview/timeruler_interaction.cpp::mouseHintProfile(false)`) and voice plot background (`editordrawer/voicechangearea/voicechangearea.cpp::mouseHintText(false)`) |
| `RulerSweep` | `songview/timeruler_interaction.cpp::mouseHintProfile(true)`: multi-track sweep plus horizontal wheel |
| `TrackScope` | `songview/trackheadermodel.cpp::scopeHint`: track toggle/range, **not** additive Control+Shift range |
| `AutomationNode` | `editordrawer/automationcanvas.cpp::ensureMouseHintProfiles`: node profile |
| `AutomationOriginPhantom` | Same: phantom profile; value-only movement, no fine-time claim |
| `AutomationSweep` | Same: ordinary sweep background |
| `AutomationPencil` | Same: pencil background |
| `VelocityNote` | `editordrawer/velocityarea/velocityarea_interaction.cpp::ensureMouseHintProfiles`: note profile |
| `VelocityBackground` | Same: background profile |
| `VelocityGutter` | Same: exact velocity click, no wheel alternative |
| `VoiceMarker` | `editordrawer/voicechangearea/voicechangearea.cpp::mouseHintText(true)` |
| `PitchBendVertex` | `pitchbendgraph.cpp::hintTextAt`: movable interior vertex, not pinned endpoints |
| `PitchBendBackground` | Same: Shift **or** Alt line drawing, not combined Shift+Alt |
| `EventRows` | `songview/quick/EventListPage.qml::rowHintText`: row toggle, range, **and** additive Control+Shift range |
| `GhostParameter` | `songview/quick/AutomationTabs.qml`: ghost-parameter toggle |
| `DragScrub` | `songview/quick/DragInput.qml`: fine drag plus fixed Control wheel step-by-ten |

Share a complete profile when the current action set and modifiers are the same, regardless of element class. `HorizontalScroll` replaces the draft's separate RulerHandle/VoicePlot IDs; `TextSelection` is shared across native and Quick text fields. Do not merge `TrackScope` with `EventRows`, or `DragScrub` with native spin profiles: their actual actions differ. Text equality alone does not prove behavioral equality, but hypothetical future divergence is not a reason to duplicate equivalent current profiles. If a future action set diverges, split it then. Partial fragments used inside larger profiles remain private rendering ingredients.

## Catalogue interface and cache

`hintprofiles.h` declares a non-QObject value module:

```cpp
namespace ui::hint_profiles {
class Catalog {
  public:
    QString text(Id profile, Qt::KeyboardModifiers stepModifier = Qt::NoModifier);
};
}
```

`MouseHints` owns one `Catalog m_profiles` by value. The catalogue needs no source QObject, application observer, signals, or QML registration of its own instance. Its enum namespace alone is exported. Construction is inert; formatting happens lazily on the GUI thread after the existing application/keymap startup.

The cache key is the profile and, for the three native spin profiles only, the style-read step modifier. Other profiles use `Qt::NoModifier`. A cache hit returns an implicitly shared QString; it must not translate, join fragments, format key sequences, read the keymap again, or deep-copy text. Empty rendered text is a valid cached result, not a cache-miss sentinel. Do not let a null QString cause repeated rendering of empty profiles.

Cache lifetime is the owning `MouseHints`/QApplication lifetime, not widget or tab lifetime. Preserve the current lazy-once language policy; there is no new runtime language switching or invalidation observer in this refactor. If runtime translation switching is introduced later, it must revise this central cache contract rather than adding local element caches.

All hover-hint literal phrases and templates reside in `hintprofiles.cpp`, using literal `QCoreApplication::translate("MouseHints", ...)` calls so extraction can see them. All modifier label rendering and separators are private there. Keep whole grammatical templates for equivalent-chord alternatives ("%1 or %2 ..."); do not substitute a combined modifier chord. Preserve existing phrase order and distinguish ordinary operations from right-button and release-time operations.

`roll.velocity_drag` and `velocity.detent_unlock` remain read through `keymap::Registry::modifierBinding` inside catalogue rendering, not copied Control constants. Move the existing velocity equal-chord/unequal-chord composition branch intact: equal detent/add-selection chords get one drag explanation combining “without detents” and “preserving selection”; different chords get their separate drag explanations. This is not the “Shift or Alt” equivalent-action template above. The catalogue reads canonical configured bindings; it does not inspect held keys or decide action eligibility.

## Claim admission and observation

Rename the existing public `publish` operation to **`claim`** while replacing its text payload. The name makes its ownership effect explicit: it is not merely a status-text setter. No old-name alias remains.

```cpp
Q_INVOKABLE void claim(QObject *source, ui::hint_profiles::Id profile);
```

A **private**, non-invokable three-argument overload accepts the style parameter:

```cpp
void claim(QObject *source, ui::hint_profiles::Id profile,
           Qt::KeyboardModifiers stepModifier);
```

The existing `WidgetHintsObserver` friendship grants native access. The public overload delegates with `Qt::NoModifier`; both use one existing claim implementation. For native spin profiles the observer calls the private overload, including when the style supplies `Qt::NoModifier`. Ordinary/QML producers select their own inventoried profiles; they do not select native spin IDs and silently assume an absent style. Do not expose a style parameter to ordinary elements or QML, introduce a parallel public verb, or retain any public publish/QString overload.

One admission-and-transfer order applies regardless of whether the profile renders text:

1. The existing physical host applies its own membership/grab/visibility gates. Quick popup coverage is rejected by the existing host mute or HoverHint session-ownership gate **before** calling claim; it is not a new check delegated to the catalogue or to native `allowsSource`.
2. MouseHints::claim applies the existing native/application `allowsSource` check before rendering or transferring ownership. A rejected source changes neither source nor caption. Empty is never an exemption at either gate.
3. An admitted claim transfers the source observations even when the ID or rendered text matches the previous source.
4. Resolve the cached description and emit hintChanged only when its final text changes. An admitted Empty claim owns blank text; a covered underlying source's Empty request owns nothing new.

The popup's own admitted Empty claim and a covered control's rejected Empty request are different **sources**, not different kinds of empty value. Keep the existing division between Quick host gates and native/application gates; this naming refactor does not move, duplicate, or generalize them.

`clear(QObject*)`, `allowsSource`, `currentSource`, `currentText`, `hintChanged(const QString&)`, and `scopeRefresh` retain their contracts. The caption continues to receive text. Do not add currentProfile/currentClaim, history, or source-indexed state to expose catalogue internals to tests; existing displayed text/source observations suffice.

`MouseHints::fragment` is removed. The private final `m_text` remains legitimate presentation state. The catalogue and caption may store rendered text; producers do not.

## Native adapter: complete profiles, not partial overrides

Replace `setPointerDescription(QWidget&, QString)` with:

```cpp
static void setWidgetProfile(QWidget &widget, ui::hint_profiles::Id profile);
```

This annotation supplies a **complete profile**, not a pointer fragment. It does not concatenate with a separately rendered wheel string. The two migrated call sites explicitly choose `NativeFineSpinEditor` and `NativeFinePageStep`, whose catalogue entries already include the inherited wheel behavior. This deliberate naming/semantic change removes the surprising "whole profile that only overrides half a profile" contract.

Store the enum metadata under `porydaw.mouseHintProfile`. Missing property means infer the native family; explicit `Empty` means a complete blank override, not missing metadata. Only the two current supported annotations are required; no new public reset operation or generic widget-family override framework.

`WidgetHintsObserver` continues to resolve the physical widget and its configuration owner using `profileOwner`, `spinBoxFor`, native view selection mode, popup/header exclusions, and existing style reads. It selects one complete ID and supplies the spin style modifier where applicable. It never formats text or reads/constructs the status description. Native inference must preserve:

- Ordinary standalone line edit → `TextSelection`.
- Ordinary embedded spin editor → `NativeSpinEditor`; modified editor → `NativeFineSpinEditor`.
- Spin body → `NativeSpinBox`, not the editor profile.
- Header/popup/no-selection view → `NativePageStep`, not an item selection profile.
- Custom fine dial → `NativeFinePageStep`, not just the fine-drag fragment.
- Unsupported no-hint widget → `Empty`.

A zero spin style modifier removes only the accelerated-step alternative. Spin body renders empty; ordinary editor retains text selection; fine editor retains fine drag. Never render bare "wheel: step by ten" with no modifier. This is configuration selection, not action availability filtering. The QML DragScrub action has its own fixed Control wheel handler and is unaffected by native spin style changes.

Delete `profileKeyProperty`, `profileTextProperty`, `configKey`, `invalidateProfile`, and per-widget rendered-text caching. Preserve existing event timing, style/metadata refresh triggers, ownership/grab tracking, popup/modality logic, and the native/status module split. A style change selects a new `(profile, stepModifier)` cache key; it does not flush every rendered description. Rename metadata event matching to the new property key.

## Physical C++ hosts and domain selectors

`TimelineInputHost` takes `Id` in both `setMouseHint(Id)` and `refreshMouseHint(Id)`. All three concrete hosts migrate together: `TimelineInputItem`, `CursorDprHost`, and `RasterAutomationInputHost`.

`setMouseHint` participates in the current idle dispatch and requests a claim through its existing guards. `refreshMouseHint` remains non-claiming: update only the current source. `resyncMouseHint` remains the existing guarded explicit reacquisition path for existing recovery events. A stationary tool change never falls back to resync to steal a foreign source after refresh declines. `Empty` replaces QString() fallbacks. Preserve these existing operations; the payload refactor does not collapse them.

Do not add a retained-profile member to TimelineInputItem: it currently retains ownership through its existing domain/dispatch flow without such storage. Change only payload types there. The two test adapters keep honest typed records and their ownership flag, not a renderer, no-op, or fabricated source.

Domain modules select IDs using their already-computed hit result. Remove text-only helpers, caches, and formatting-only singleton borrows. Preserve `TimeRuler::pressTargetAt` and its shared action/hover precedence. Automation's selector remains local (`mouseHintProfile() const` returning Id) because it reads existing hover/tool state; invalid lane returns Empty. A stationary pencil change uses the existing primary host's non-claiming refresh. Never centralize hit testing in the catalogue.

PitchBendGraph remains its own physical source. Rename `hintTextAt` to `hintProfileAt` returning Id and `m_hintText` to **`m_gestureProfile`**, initialized Empty. Keep that existing originating-gesture value; remove m_vertexHint, m_backgroundHint, and its duplicate modifier renderer. During an active gesture every update uses the captured ID, even when the cursor crosses another target: do not call the idle classifier then. Reclassification occurs only through the existing idle or terminal inside-settlement path; outside settlement clears. This preserves the existing hit tests, gesture, visibility, and cancellation paths.

## QML: enum constants, no text transport

In `TimelineQuickView`'s existing registration block, keep its **function-local static `std::once_flag`**. The following registers the enum namespace once **per process**, before any tab's QML loads:

```cpp
qmlRegisterUncreatableMetaObject(ui::hint_profiles::staticMetaObject,
    "Porydaw.Ui", 1, 0, "HintProfiles", QStringLiteral("Enum values only"));
```

Enum type registration is process-wide; it is not repeated per engine or per view instance. Separately, each view installs its existing `mouseHints` context property into its own engine. All those properties borrow the same application-owned MouseHints and catalogue. Do not replace that borrowing with qmlRegisterSingletonInstance or create per-tab MouseHints objects. Both new catalogue files must be explicit CMake sources so AUTOMOC processes Q_NAMESPACE.

`HoverHint.qml` imports Porydaw.Ui. Replace `property string text` with `property int profile: HintProfiles.Empty`; replace `_retained` with **`_gestureProfile`**, also an integer ID defaulting to Empty. This is the QML counterpart of the graph's existing gesture-value storage, not a new retention layer. Both retain their origin until the existing terminal settlement; TimelineInputItem gains no field. Enum constants are integer-valued in QML, not string keys; the C++ claim parameter remains enum-typed. Keep every existing sync/scope/grab condition and physical source/parent relationship.

All callers bind `profile`, including nested row/editor and value-prompt selection. An editor hover chooses TextSelection, an ordinary event row EventRows, and an inert editor margin Empty. Child hover handlers still only choose the enclosing group's profile; they do not become independent publishers. Empty-profile shields/scrollbars may use the default. Delete `rowHintText` and all producer `mouseHints.fragment`, hover-only `qsTr`, separator joins, and their text-construction guards. Do not delete unrelated labels, tooltips, accessible names, or service-availability guards inside HoverHint.

The existing popup direct publication becomes `claim(source, Id::Empty)`. All C++/QML direct publishers migrate to claim, including the host's current-owner refresh path. Popup and timeline recovery behavior otherwise remains untouched.

## Evidence and limitations

Architecture grounded in the current `.worktrees/modifier-mouse-hints` source snapshot on 2026-09-13: native resolution in `widgethints.cpp`; public source ordering in `MouseHints::publish`; physical host dispatch/refresh in `timelineinputitem.cpp`; the producer authorities in the ID table; imperative registration in `timelinequickview.cpp`; and AUTOMOC/module ownership in `CMakeLists.txt`.

Qt documents [namespace-enum registration](https://doc.qt.io/qt-6/qqml-h.html#qmlRegisterUncreatableMetaObject). This is design evidence, not proof that the proposed code builds or that QML calls it successfully. The [implementation verification gate](plan.md#verification) must exercise AUTOMOC, QML enum delivery, native style variants, and real composed hover. Do not silently replace the typed interface with QString/int fallbacks if a check fails; diagnose the registration or update this contract through review.
