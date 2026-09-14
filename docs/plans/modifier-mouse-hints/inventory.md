# Modifier-mouse inventory

This is the coverage contract for [spec.md](spec.md), not a new runtime command catalog. Descriptions live beside their existing input owners. `ControlModifier` means Command on macOS and Ctrl on Windows/Linux; `AltModifier` means Option on macOS. The two registered hold chords are immutable shipped bindings, read through `keymap::Registry::modifierBinding`, not user-rebindable settings.

## Timeline

| Target | Modifier-dependent mouse alternative | Authority / preserved distinction |
| --- | --- | --- |
| Roll note body | Registered `roll.velocity_drag` + left-drag adjusts velocity; Control + click toggles note selection | `src/ui/songview/pianoroll_gestures.cpp`, `beginNotePress`, `applyNotePressSelection`; velocity requires exact hold chord and wins before normal body drag. Sub-threshold velocity press becomes selection click on release in `pianoroll_gestures_active.cpp::releasePendingVelocityClick`. |
| Roll note resize edge | Control + left-drag adds the note to selection and resizes; not velocity dragging | Same press/selection functions and `armNoteDrag`. Reuse `nearLeftEdge`/`nearRightEdge`; do not advertise velocity over an edge. |
| Roll plot, including note/background | Shift + right-drag selects time instead of note marquee; Control held at right-drag release adds marquee notes to selection | `pianoroll_gestures.cpp::beginPendingMenu`/`resolveRightPress`; `pianoroll_gestures_active.cpp::releaseRightPress`. Right-button alternatives are not left-drag hints. |
| Roll plot and piano-key gutter | Control + wheel changes pitch/key-height zoom; Shift + wheel scrolls horizontally | `src/ui/songview/pianoroll.cpp::wheel`. Control branch precedes Shift and surface distinction. Plain plot wheel time-zooms; plain gutter wheel vertically scrolls pitches. |
| Ruler sweep/background | Control + left-drag includes tracks with notes intersecting swept time selection | `src/ui/songview/timeruler_interaction.cpp::pointerPress`/`pointerMove`. Captured at press; includes primary track plus intersecting note tracks, not indiscriminately every track. |
| Ruler marker/signature/selection edge | Shift + wheel horizontal scroll; no special modifier variant for dragging those handles | Ruler press handles take precedence over sweep. Reuse `hitMarker`, `hitTimeSigChip`, `hitSelEdge`. Do not advertise multi-track sweep on a handle consumed by another drag. |
| Entire ruler plot | Shift + wheel horizontal scroll | `TimeRuler::wheel`. No separate Control-wheel action here. |
| Track-header body and voice line | Control + click toggles track scope; Shift + click selects track range | `src/ui/songview/trackvoiceops.cpp::SongView::trackHeaderClicked`; Control wins over Shift. `trackheadermodel.cpp::pointerPress` does not arm ordinary reorder/reveal for those chords. |
| Track-header mute, solo, add-track controls | No modifier-specific mouse action | `TrackHeaderModel::pointerPress` handles these before scope adjustment. Clear body hints over these targets. Rename field is a separate text target. |

Roll hover authority is `PianoRoll::refreshHoverCursor`/`pointerMove`; ruler authority is `TimeRuler::pointerMove`; header authority is `TrackHeaderModel::rowAt`/`hitTarget`/`pointerMove`. Never build a second geometry classifier in the status presenter.

`TimelineInputItem` currently overrides hover move/leave but not hover enter. Qt delivers HoverEnter instead of HoverMove on first entry, so immediate stationary-entry hints require an explicit idle hover-enter forwarding path. Preserve `TimelineBandInteraction::gestureActive()` and existing action delivery; add the presentation-only `TimelineInputHost::setMouseHint` seam so the physical input item, not a shared band model, owns publication. Do not forward a synthetic move into an active gesture.

## Drawer

| Target | Modifier-dependent mouse alternative | Authority / preserved distinction |
| --- | --- | --- |
| Automation node | Shift + left-drag constrains to an axis; Alt + left-drag uses fine time grid; Control + left-drag snaps value toward the lane's neutral value | `src/ui/editordrawer/automationcanvas_gesture.cpp::updateActiveGesture`; `nodelane/gesture.cpp::PointDragGesture::update`; `mappedForLane`. Existing sticky axis/slop behavior remains. |
| Automation origin phantom | Shift + left-drag constrains the existing value gesture; Control + left-drag snaps neutral value | Phantom branch of `updateActiveGesture`. It edits the source event's value, not time; do not label Alt as phantom time movement. |
| Automation ordinary background/sweep mode | Shift + left-drag makes a ramp; Alt + mouse placement/drag uses fine time grid; Control + drag snaps neutral value | `automationcanvas_input.cpp::beginDragOrSweep`; mode is fixed at press, not reselected by Shift mid-sweep. `updateActiveGesture` keeps Alt/Control live. |
| Automation pencil background | Control + left-drag draws freehand; Shift + left-drag holds value constant | `automationcanvas_gesture.cpp` PencilGesture branch. Node hits can still resolve to node drag; reuse actual pencil cell/node classification. Do not claim Alt changes pencil stroke sampling. |
| Automation plot right-drag / insertion double-click | Alt uses fine time-grid placement | `automationcanvas_input.cpp::pointerPress`, `pointerMove`, `pointerDoubleClick`. This is distinct from pencil-stroke sampling. |
| Automation plot | Shift + wheel horizontal scroll | `AutomationCanvas::wheel`; gutter declines this path. |
| Automation parameter tab | Control + click toggles the ghost parameter instead of normal activation | `automationcanvas_tabs.cpp::parameterPressed`; `src/ui/songview/quick/AutomationTabs.qml`. Show description without mirroring `canGhostParameter` or disabling/dimming the hint. |
| Velocity note/head and background | Registered `velocity.detent_unlock` + left-drag/paint unlocks velocity detents; Shift + left-drag draws a ramp | `src/ui/editordrawer/velocityarea/velocityarea_interaction.cpp::pointerPress`; `velocityarea.cpp::detentsUnlocked`. Detent mode captured at press; plot permits the registered chord plus Shift for an unlocked ramp. |
| Velocity note/head | Control + click toggles selection; Control + left-drag preserves/adds note selection while adjusting velocity | `VelocityArea::pointerPress` and `pointerRelease`; no second selection model for hinting. |
| Velocity plot | Control + right-click toggles note selection; Control + right-drag adds marquee notes | `VelocityArea::pointerRelease`; Control decision captured at press, unlike roll marquee's release-time decision. |
| Velocity gutter ruler | Registered detent-unlock chord + click sets exact velocity instead of ruler detent | `VelocityArea::pointerPress` Gutter branch; exact chord, no Shift carve-out. |
| Velocity plot | Shift + wheel horizontal scroll | `VelocityArea::wheel`; not the gutter. |
| Voice-change marker | Alt + left-drag uses fine time grid | `src/ui/editordrawer/voicechangearea/voicechangearea.cpp::pointerMove`; same live marker hit/drag owner. |
| Voice-change plot | Shift + wheel horizontal scroll | `VoiceChangeArea::wheel`. No modifier variant for the ordinary picker double-click. |

`AutomationCanvas::refreshHoverAt`, existing node/phantom hit helpers and `NodeLaneHoverState` remain the automation hover authority. Hint strings do not join the numeric value-label cache or add held-modifier dimensions. Use tool/target identity only. Velocity reuses `notesAt`/hovered-note computation; voice changes reuse their marker classification. The hint path must not re-run transaction, selection, lane eligibility, or document mutation code.

## Quick controls and graph popup

| Target | Modifier-dependent mouse alternative | Authority / preserved distinction |
| --- | --- | --- |
| `DragInput` numeric editor (all prompts) | Shift + vertical drag adjusts more finely; Control + wheel steps by ten | `src/ui/songview/quick/DragInput.qml`, `state.scrubTo`, `WheelHandler`. macOS Shift-wheel uses horizontal delta to retain stepping after OS axis conversion; do not describe that as panning or a second faster step. |
| Event-list row/cell/row-header outside active text editing | Control + click toggles row; Shift + click selects range; Control+Shift + click adds range | `EventListPage.qml` forwards to `eventlistcontroller.cpp::selectRow`; combined chord is additive range, unlike track-header Control precedence. |
| Event-list inline text editor | Shift + click extends text selection | `EventListPage.qml` TextInput has `selectByMouse: true`; editor takes precedence over underlying row selection. |
| Track-header rename field | Shift + click extends text selection | `TrackHeaderBand.qml` TextInput has `selectByMouse: true`; header scope hints do not leak through it. |
| Voice-picker search field | Shift + click extends text selection | `VoicePickerPrompt.qml::search`; Qt 6.9 TextInput defaults `selectByMouse` to true and its mousePressEvent gates Shift marking on that property. Preserve its existing I-beam handler and filter binding. |
| Drawer inline value-prompt field | Shift + click extends text selection | `DrawerChromeLayer.qml::valuePromptInput`; same modern TextInput default. Its surrounding card/shield is a separate empty profile within one publisher group. |
| Pitch-bend and modulation graph background | Shift **or** Alt + left-drag draws a straight/angled segment rather than freehand | `src/ui/pitchbendgraph.cpp::mousePressEvent`. These are two equivalent alternative chords, not a required Shift+Alt combination. |
| Pitch-bend/modulation graph interior vertex | Alt + left-drag moves time with fine sampling | `PitchBendGraph::hitTest`, `updateVertexDrag`. Endpoints are pinned in time; their target description must not promise horizontal movement. |

`PitchBendGraph` is a QQuickItem hosted by the shared popup overlay, not a QWidget or independent floating Quick window. It currently accepts mouse input but has no hover override; passive hover support must be added here, reusing `hitTest`/`canvasRect`. Existing `hasGesture`/cancel paths own gestures.

Quick scrollbars, prompt buttons, shields, menu panels and drawer resize handles have no custom modifier mouse alternatives. They must prevent covered editor hints from leaking through; do not invent actions for them. Existing popups remain authoritative about ownership. Shared generic numeric/text controls are annotated once, not independently in every prompt.

## App-owned QWidget controls, including dialogs and floating docks

| Family / actual consumers | Description | Authority |
| --- | --- | --- |
| `DragSpinBox` embedded editor; voicegroup ADSR fields | Shift + drag adjusts more finely | `src/ui/dragspinbox.cpp::eventFilter` (0.2 vs 0.5 steps per DIP, **not** half speed). Its click-select-all override supersedes ordinary Shift-click text selection. Retain inherited wheel/arrow-button alternatives. |
| `OutputVolumeDial` | Shift + drag fine adjustment; Control **or** Shift + wheel page-sized adjustment | `src/ui/transportbar.cpp::OutputVolumeDial::mouseMoveEvent`; inherited `QAbstractSliderPrivate::scrollByDelta`. |
| `QSpinBox` / `QDoubleSpinBox`, including transport, settings, sample editor, song/new-song controls | Platform/style step modifier + wheel or arrow-button click steps by ten; ordinary embedded editor also supports Shift-click text selection | `QAbstractSpinBox`; modifier is `QStyle::SH_SpinBox_StepModifier`, not assumed from custom drag behavior. Describe mouse operations, not Ctrl+keyboard arrows. |
| Ordinary `QLineEdit`, editable combo/spin text, filters/search/rename fields | Shift + click extends text selection | `QLineEdit::mousePressEvent`. Custom DragSpinBox editor overrides this; do not add generic text hint underneath it. |
| Actual single-selection song list, voicegroup tree, sample-picker tree, SoundFont zone tree and polyphony log | Control + click deselects the selected item | `QAbstractItemView::selectionCommand` SingleSelection. Neither QListWidget nor QTreeWidget defaults to ExtendedSelection. Do not advertise Shift ranges or multi-item selection on these lists. |
| Polyphony NoSelection table | No selection modifier hint | `src/ui/polyphonypanel.cpp` explicitly sets NoSelection. |
| QWidget sliders, dials, scrollbars reached directly or through standard scroll-area wheel forwarding | Control **or** Shift + wheel page-sized adjustment | `QAbstractSliderPrivate::scrollByDelta`. `layout::configureListPositionIndicator` only applies style; include both scrollbar and forwarding viewport hover targets. |

The common widget adapter recognizes these actual class/configuration families; no copy of every dialog's business enablement. Configured control kind is target identity, not action availability. Preserve subclass overrides and mouse-event propagation. QWidget-only app dialogs and floated docks belong to the same main-window hint destination even when the main window is inactive. A modal popup must not leak underlying hints.

No custom modifier-dependent pointer handler was found in `waveformview.cpp`, app workspace tab management, theme controls, or activity painting. Their standard child controls still receive family coverage. OS-owned native file dialogs and window-manager decorations are not Porydaw mouse targets and are not replaced or globally hooked by this feature.

## Audited Qt evidence and planning experiment

Primary references:

- [QStatusTipEvent](https://doc.qt.io/qt-6/qstatustipevent.html), [QStatusBar](https://doc.qt.io/qt-6/qstatusbar.html), [HoverHandler](https://doc.qt.io/qt-6/qml-qtquick-hoverhandler.html).
- [Qt 6.9 QWidget source](https://raw.githubusercontent.com/qt/qtbase/6.9/src/widgets/kernel/qwidget.cpp): Enter/Leave generate status tips only for annotated widgets; setter merely stores text.
- [Qt 6.9 QApplication source](https://raw.githubusercontent.com/qt/qtbase/6.9/src/widgets/kernel/qapplication.cpp): native status-tip propagation stops at the top-level QWidget.
- [Qt 6.9 QStatusBar source](https://raw.githubusercontent.com/qt/qtbase/6.9/src/widgets/widgets/qstatusbar.cpp): `reformat`, `messageRect`, `hideOrShow` explain permanent-vs-normal layout.
- [Qt 6.9 QKeySequence source](https://raw.githubusercontent.com/qt/qtbase/6.9/src/gui/kernel/qkeysequence.cpp): native modifier mapping/order and unknown-key behavior.
- [Qt 6.9 Quick delivery agent](https://raw.githubusercontent.com/qt/qtdeclarative/6.9/src/quick/util/qquickdeliveryagent.cpp): `deliverHoverEventToItem` sends HoverEnter on first entry and HoverMove only for an already-hovered item.
- [Qt 6.9 item-view selection](https://raw.githubusercontent.com/qt/qtbase/6.9/src/widgets/itemviews/qabstractitemview.cpp), [line edit](https://raw.githubusercontent.com/qt/qtbase/6.9/src/widgets/widgets/qlineedit.cpp), [abstract slider](https://raw.githubusercontent.com/qt/qtbase/6.9/src/widgets/widgets/qabstractslider.cpp), [abstract spinbox](https://raw.githubusercontent.com/qt/qtbase/6.9/src/widgets/widgets/qabstractspinbox.cpp).

A standalone macOS Qt offscreen probe compiled and exited 0 during planning. It observed native modifier labels `⌘`, `⇧`, `⌥`, `⇧⌘`; QListWidget/QTreeWidget SingleSelection; Control-click deselection; Shift-click selecting one list row, not a range; both integer and double spinboxes stepping 1 versus 10 with Control-wheel; QDial ordinary wheel +3 versus Control/Shift page-step +10; QLineEdit Shift-click selection extension.

A second probe used unmodified QStatusBar: normal empty reservation (stretch 1, `retainSizeWhenHidden`), permanent hint label (stretch 2, horizontal `Ignored` policy), permanent meter (stretch 0). At width 1000, left reservation x=2/w=280, hint x=288/w=560, meter x=854/w=122, bar height=22. Geometry and visible hint remained unchanged through `showMessage`, a 300-character hint and `clearMessage`; operational message remained intact. This proves Qt layout feasibility, not Porydaw integration or native visual quality. No production code or application tests were changed/run for the plan.

`typography::installBundledFonts` installs body text at 1.125 times the captured platform base size; `typography::caption` uses that base size. The caption role therefore supplies the requested smaller text in the real app without an arbitrary per-widget font decrement.

The first audit's standalone Quick probe reproduced two ownership failures: a popup can leave underlying `HoverHandler.hovered` values true, and closing it does not necessarily emit `hoveredChanged`; independent parent/child publishers also lack deterministic precedence. A revised isolated probe passed stationary popup-close restoration and child-to-parent transitions using one logical group publisher, explicit scope refresh, and scope rejection of covered background publications. This proves those Qt primitives, not the planned application integration.

A further standalone Qt Widgets offscreen probe compiled and exited 0 during plan repair. Original child mouse-move/press/release events had `spontaneous=1`; propagated parent copies had `spontaneous=0`. An implicit press retained delivery to the child after movement outside while `QWidget::mouseGrabber()` remained null. The native observer must distinguish original delivery from ancestor propagation and track its actual pressed source rather than treating `mouseGrabber()` as the complete implicit-grab authority. The Qt QApplication source also sends application event filters mouse-tracking-only moves even for widgets without mouse tracking; adding global mouse tracking is unnecessary.

The repaired native-scope primitive also passed an isolated Qt Widgets/Quick offscreen probe: opening a window-modal dialog delivered `WindowBlocked` to its parent QWindow and embedded QQuickWindow, but not an unrelated top-level widget; closing delivered `WindowUnblocked` to both. Output was `windowModalScope=correct` and `windowModalRestored=correct`, exit 0. [Qt's implementation](https://raw.githubusercontent.com/qt/qtbase/6.9/src/gui/kernel/qguiapplication.cpp), `updateBlockedStatusRecursion`, is the authority; mirror its delivered blocked bit rather than duplicating modality/ancestry policy.

The Quick repair specialist's isolated probe confirmed that an accepting QQuickItem above a page blocks lower-sibling hover even when its handler ignores the event. `timelineEventListInput` currently occupies that position above EventListPage while owning only local keys. The revision therefore explicitly restacks it below the page and requires press/wheel/reorder/focus parity checks; this is a delivery correction, not a claim of unchanged hover reachability.

[Qt 6.9 TextInput source](https://raw.githubusercontent.com/qt/qtdeclarative/6.9/src/quick/items/qquicktextinput.cpp) documents `selectByMouse` default true since Qt 6.4 and uses it with Shift in mousePressEvent. This adds the voice-picker search and drawer value field to coverage. DragInput's deferred tap-select-all overrides ordinary selection-click behavior, so it retains its custom fine-drag/wheel profile rather than generic Shift-click help.

An additional isolated Qt/QML probe compiled the meta-object and called `Q_INVOKABLE bool owns(const QObject *) const` from a real QML object. It printed `constQObjectInvokable=supported`, exit 0, without QML warnings. The existing QuickPopupSession ownership signature can therefore be exposed without changing its C++ parameter type or adding a forwarding wrapper.

A stationary native-modal reentry probe exposed a second failure: `before hovered=1 enters=1`, `blocked hovered=0 enters=1`, `closed hovered=0 enters=1` after 100 ms without motion. WindowUnblocked alone does not restore Quick membership. A corrected isolated probe queued a callback, checked current cursor/native window containment, button/grab/domain-idle guards, then sent one stack-local idle MouseMove through the Quick window. Output: `recovered hovered=1 enters=2 deliveries=1`; with a newly higher leaf, `lowerHovered=0 upperHovered=1 deliveries=2`; changing domain-active state after scheduling kept `deliveries=2`. Compilation and execution exited 0 without warnings. This proves Qt reentry, leaf exclusion, coalescing and dispatch-time guard evaluation—not the unimplemented application's full gesture/scope integration.

The first recovery-probe variant warped QCursor before establishing initial delivery, which changed the offscreen current-window setup and no longer reproduced Leave; its expected second-enter assertion failed. Removing that setup change preserved the original counterexample and produced the successful recovery output above. No project check failed or was run.

## Real workflow anchors

- `MainWindow::exportWav` in `src/mainwindow.cpp` creates a QProgressDialog with `Qt::WindowModal`. Native scope suppression/recovery has a real application workflow; exercise it in the WAV-export walkthrough rather than inventing an unrelated second window.
- `SongView::handleEditKey` dispatches `EditStandaloneOperation::PencilToggle` in `src/ui/songview/editkeyrouting.cpp`, calling `AutomationCanvas::setPencilMode`. This supports a tool change while the pointer stays stationary, with no popup open.
- `QuickPopupSession::eventFilter` in `src/ui/songview/quick/quickpopupsession.cpp` owns popup shortcut arbitration, with its existing transport exception. Do not simulate background tool changes by bypassing that scope. For recovery over a changed target, move the real pointer while the popup is open and dismiss normally.

The preceding isolated Qt probes establish implementation mechanics. Revision 3 does not promote every probed state or event ordering into a permanent application check; plan.md's realism rule governs that choice.
