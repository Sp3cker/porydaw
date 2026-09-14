# Centralized hover-hint profiles

Revision: **3 — admission naming and task ownership revised after independent quizzes; focused retest adjudicated in [audit.md](audit.md)**. This is the current implementation contract, not evidence of a completed runtime cutover.

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

The cache and source have different lifetimes: cached descriptions survive tab closure, but the hovered/grabbed **source does not**. Hiding/detaching/destroying its tab follows the existing source-checked clear and membership rules; the caption cannot be restored from a cached description alone. The application-owned QPointer field may outlive a tab, but the item it guarded and its claim do not. A new tab must make a new admitted claim through ordinary hover/recovery.

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

1. The existing physical host applies its own membership/grab/visibility gates. Quick popup coverage is rejected by the existing host mute or HoverHint session-ownership gate **before** calling claim.
2. MouseHints::claim applies **`allowsNativeInput(source)`** before rendering or transferring ownership. This is the existing allowsSource implementation renamed to describe its limited responsibility: native/application input scope and effective visibility/windowing, **not Quick session coverage**. Bypassing a Quick host's gate with a direct call is unsupported and is not guaranteed to be rejected by this native check. Do not move or duplicate Quick session logic into MouseHints. Empty exempts a source from neither gate.
3. An admitted claim transfers the source observations even when the ID or rendered text matches the previous source.
4. Resolve the cached description and emit hintChanged only when its final text changes. An admitted Empty claim owns blank text; a covered underlying source's Empty request owns nothing new.

The popup's own admitted Empty claim and a covered control's rejected Empty request are different **sources**, not different kinds of empty value. Keep the existing division between Quick host gates and native/application gates; this naming refactor does not move, duplicate, or generalize them.

Rename `allowsSource(QObject*) const` to **`allowsNativeInput(QObject*) const`** and migrate its existing callers without changing its body. `clear(QObject*)`, `currentSource`, `currentText`, `hintChanged(const QString&)`, and `scopeRefresh` retain their contracts. The caption continues to receive text. Do not add currentProfile/currentClaim, history, or source-indexed state to expose catalogue internals to tests; existing displayed text/source observations suffice.

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
