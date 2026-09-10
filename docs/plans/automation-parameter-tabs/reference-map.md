# Planned API cutover reference map

Controller reference, not an implementer brief. Generated from successful parent-session clangd `references` queries. Refresh references before deletion; line numbers are navigation hints, not patch anchors. Every consumer of a removed UI declaration must migrate first. QML consumers additionally require scoped text search.

Audit scope: EditorViewState fields, QSettings serialization and remap APIs in this inventory are retained unchanged, not deletion targets. Their workspace/main-window/rollcheck callers need no rewrite. minimumContentHeight is retained as the Qt-measured selector minimum. The inventory is evidence for caller closure, not an instruction to change every listed file. The previously unassigned automationstroke.cpp UI caller is owned by task 26 (after task 28).

## laneHeight

- `src/ui/editorviewstate.h:62:9`
- `src/checks/automation/automationcanvaslayout.cpp:332:27`
- `src/checks/automation/automationcanvaslayout.cpp:332:54`
- `src/checks/automation/automationcanvaslayout.cpp:368:58`
- `src/checks/automation/automationcanvaslayout.cpp:372:43`
- `src/checks/host/tst_hostseams.cpp:92:15`
- `src/checks/mainwindowrouting/mainwindowroutingfixture.h:248:15`
- `src/checks/rollcheck/identity.cpp:148:15`
- `src/checks/rollcheck/remap.cpp:100:15`
- `src/checks/rollcheck/remap.cpp:115:18`
- `src/checks/rollcheck/remap.cpp:129:18`
- `src/checks/rollcheck/remap.cpp:506:15`
- `src/checks/workspace/selftest_workspace.cpp:66:18`
- `src/checks/workspace/selftest_workspace.cpp:66:41`
- `src/checks/workspace/selftest_workspace.cpp:84:11`
- `src/checks/workspace/selftest_workspace.cpp:213:26`
- `src/checks/workspace/selftest_workspace.cpp:230:30`
- `src/checks/workspace/session.cpp:89:11`
- `src/checks/workspace/tabs_persistence.cpp:37:11`
- `src/ui/editordrawer/automationpage.cpp:124:21`
- `src/ui/editordrawer/automationpage.cpp:124:50`
- `src/ui/editordrawer/automationpage.cpp:424:21`
- `src/ui/editordrawer/automationpage.cpp:424:50`
- `src/ui/editordrawer/automationpage.cpp:434:17`
- `src/ui/editorviewstate.cpp:326:16`
- `src/ui/editorviewstate.cpp:422:58`

## laneHeights

- `src/ui/editorviewstate.h:63:42`
- `src/checks/automation/automationcanvaslayout.cpp:333:27`
- `src/checks/automation/automationcanvaslayout.cpp:333:55`
- `src/checks/automation/automationfixture.cpp:393:21`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:355:11`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:447:11`
- `src/checks/automation/raster/rasterfixture.cpp:132:11`
- `src/checks/mainwindowrouting/mainwindowroutingfixture.h:249:15`
- `src/checks/rollcheck/identity.cpp:149:15`
- `src/checks/rollcheck/remap.cpp:90:31`
- `src/checks/rollcheck/remap.cpp:90:59`
- `src/checks/rollcheck/remap.cpp:101:15`
- `src/checks/rollcheck/remap.cpp:102:15`
- `src/checks/rollcheck/remap.cpp:103:15`
- `src/checks/rollcheck/remap.cpp:115:44`
- `src/checks/rollcheck/remap.cpp:117:30`
- `src/checks/rollcheck/remap.cpp:118:30`
- `src/checks/rollcheck/remap.cpp:119:30`
- `src/checks/rollcheck/remap.cpp:129:44`
- `src/checks/rollcheck/remap.cpp:131:30`
- `src/checks/rollcheck/remap.cpp:132:30`
- `src/checks/rollcheck/remap.cpp:358:22`
- `src/checks/rollcheck/remap.cpp:507:15`
- `src/checks/rollcheck/remap.cpp:508:15`
- `src/checks/workspace/selftest_workspace.cpp:66:61`
- `src/checks/workspace/selftest_workspace.cpp:85:11`
- `src/checks/workspace/selftest_workspace.cpp:217:25`
- `src/checks/workspace/selftest_workspace.cpp:228:29`
- `src/checks/workspace/session.cpp:90:11`
- `src/checks/workspace/tabs_persistence.cpp:38:11`
- `src/ui/editordrawer/automationcanvas_input.cpp:282:36`
- `src/ui/editordrawer/automationpage.cpp:125:33`
- `src/ui/editordrawer/automationpage.cpp:126:30`
- `src/ui/editordrawer/automationpage.cpp:430:47`
- `src/ui/editorviewstate.cpp:77:14`
- `src/ui/editorviewstate.cpp:83:38`
- `src/ui/editorviewstate.cpp:86:22`
- `src/ui/editorviewstate.cpp:275:16`
- `src/ui/editorviewstate.cpp:343:48`

## emptyLanes

- `src/ui/editorviewstate.h:65:37`
- `src/checks/automation/automationcanvaslayout.cpp:213:11`
- `src/checks/automation/automationcanvaslayout.cpp:335:27`
- `src/checks/automation/automationcanvaslayout.cpp:335:54`
- `src/checks/automation/automationcanvaslayout.cpp:341:36`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:175:11`
- `src/checks/automation/raster/rasterfixture.cpp:131:11`
- `src/checks/automation/raster/rasterfixture.cpp:410:11`
- `src/checks/host/tst_hostadapter.cpp:616:15`
- `src/checks/host/tst_hostadapter.cpp:619:40`
- `src/checks/host/tst_hostadapter.cpp:620:41`
- `src/checks/host/tst_hostintegration.cpp:643:15`
- `src/checks/host/tst_hostseams.cpp:94:15`
- `src/checks/mainwindowrouting/mainwindowroutingfixture.h:251:15`
- `src/checks/nativegraphics/tst_playhead_autohover.cpp:77:17`
- `src/checks/rollcheck/identity.cpp:151:15`
- `src/checks/rollcheck/remap.cpp:76:18`
- `src/checks/rollcheck/remap.cpp:76:69`
- `src/checks/rollcheck/remap.cpp:107:15`
- `src/checks/rollcheck/remap.cpp:108:15`
- `src/checks/rollcheck/remap.cpp:116:50`
- `src/checks/rollcheck/remap.cpp:130:50`
- `src/checks/rollcheck/remap.cpp:511:15`
- `src/checks/workspace/selftest_workspace.cpp:67:46`
- `src/checks/workspace/selftest_workspace.cpp:87:11`
- `src/checks/workspace/selftest_workspace.cpp:219:25`
- `src/checks/workspace/selftest_workspace.cpp:229:29`
- `src/checks/workspace/session.cpp:92:11`
- `src/checks/workspace/tabs_persistence.cpp:40:11`
- `src/ui/editordrawer/automationcanvas_menu.cpp:294:32`
- `src/ui/editordrawer/automationcanvas_menu.cpp:294:75`
- `src/ui/editordrawer/automationpage.cpp:397:21`
- `src/ui/editordrawer/automationpage.cpp:408:21`
- `src/ui/editordrawer/cclanes.cpp:93:48`
- `src/ui/editorviewstate.cpp:79:14`
- `src/ui/editorviewstate.cpp:93:28`
- `src/ui/editorviewstate.cpp:96:22`
- `src/ui/editorviewstate.cpp:300:20`
- `src/ui/editorviewstate.cpp:425:70`
- `src/ui/songview/viewstate.cpp:216:15`
- `src/ui/songview/viewstate.cpp:226:14`

## hideLane

- `src/ui/editorviewstate.h:72:10`
- `src/checks/automation/automationcanvaslayout.cpp:212:11`
- `src/checks/automation/automationmenus.cpp:87:11`
- `src/checks/automation/raster/rasterfixture.cpp:130:11`
- `src/checks/mainwindowrouting/mainwindowroutingfixture.h:252:15`
- `src/checks/mainwindowrouting/mainwindowroutingfixture.h:253:15`
- `src/checks/workspace/selftest_workspace.cpp:88:11`
- `src/checks/workspace/selftest_workspace.cpp:89:11`
- `src/checks/workspace/selftest_workspace.cpp:90:11`
- `src/checks/workspace/session.cpp:93:11`
- `src/checks/workspace/session.cpp:94:11`
- `src/checks/workspace/tabs_persistence.cpp:41:11`
- `src/ui/editordrawer/automationcanvas_menu.cpp:435:32`
- `src/ui/editordrawer/automationcanvas_menu.cpp:441:32`
- `src/ui/editorviewstate.cpp:33:23`
- `src/ui/editorviewstate.cpp:101:22`
- `src/ui/editorviewstate.cpp:311:20`

## hiddenLanes

- `src/ui/editorviewstate.h:79:47`
- `src/checks/automation/automationcanvaslayout.cpp:336:27`
- `src/checks/automation/automationcanvaslayout.cpp:336:57`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_state.cpp:206:38`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_state.cpp:207:38`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_state.cpp:208:38`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_state.cpp:266:27`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_state.cpp:267:27`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_state.cpp:268:26`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_state.cpp:269:27`
- `src/checks/workspace/selftest_workspace.cpp:67:74`
- `src/checks/workspace/selftest_workspace.cpp:220:25`
- `src/checks/workspace/selftest_workspace.cpp:229:59`
- `src/checks/workspace/session.cpp:231:51`
- `src/checks/workspace/session.cpp:231:77`
- `src/ui/editordrawer/automationcanvas_menu.cpp:299:47`
- `src/ui/editorviewstate.cpp:365:52`

## automationContentHeight

- `src/ui/editordrawer/automationpage.h:49:9`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:278:57`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:478:42`
- `src/checks/host/tst_hostseams.cpp:46:27`
- `src/checks/nativegraphics/tst_playhead_autohover.cpp:95:48`
- `src/checks/selectionkey/automationprobe.cpp:160:54`
- `src/checks/selectionkey/windowtier_gestures.cpp:300:40`
- `src/ui/editordrawer/automationcanvas.cpp:125:72`
- `src/ui/editordrawer/automationcanvas.cpp:311:28`
- `src/ui/editordrawer/automationpage.cpp:48:21`
- `src/ui/editordrawer/drawerchrome.cpp:358:19`

## verticalScroll

- `src/ui/editordrawer/automationpage.h:50:9`
- `src/checks/automation/automationactions.cpp:139:47`
- `src/checks/automation/automationcanvaslayout.cpp:362:61`
- `src/checks/automation/automationfixture.cpp:96:62`
- `src/checks/automation/automationfixture.cpp:103:73`
- `src/checks/automation/automationfixture.cpp:113:41`
- `src/checks/automation/automationfixture.cpp:144:78`
- `src/checks/automation/automationfixture.cpp:382:60`
- `src/checks/automation/automationpainting.cpp:123:17`
- `src/checks/automation/automationpainting.cpp:127:37`
- `src/checks/automation/automationpainting.cpp:159:37`
- `src/checks/automation/automationpainting.cpp:198:37`
- `src/checks/automation/automationpainting.cpp:257:37`
- `src/checks/automation/automationpainting.cpp:326:36`
- `src/checks/automation/automationpainting.cpp:328:37`
- `src/checks/automation/automationpainting.cpp:365:38`
- `src/checks/automation/automationpreviews.cpp:163:80`
- `src/checks/automation/automationpreviews.cpp:164:80`
- `src/checks/automation/automationpreviews.cpp:180:66`
- `src/checks/automation/automationpreviews.cpp:246:39`
- `src/checks/automation/automationpreviews.cpp:304:49`
- `src/checks/automation/automationpreviews.cpp:346:68`
- `src/checks/automation/automationpreviews.cpp:378:39`
- `src/checks/automation/automationpreviews.cpp:390:81`
- `src/checks/automation/hover/hoverfixture.cpp:250:74`
- `src/checks/automation/hover/hoverfixture.cpp:315:69`
- `src/checks/automation/hover/hoverfixture.cpp:441:50`
- `src/checks/automation/hover/hoverfixture.cpp:445:75`
- `src/checks/automation/presentation/painting.cpp:210:52`
- `src/checks/automation/presentation/painting.cpp:245:52`
- `src/checks/automation/presentation/painting.cpp:275:52`
- `src/checks/automation/presentation/painting.cpp:296:52`
- `src/checks/automation/presentation/painting.cpp:346:70`
- `src/checks/automation/presentation/painting.cpp:354:29`
- `src/checks/automation/presentation/painting.cpp:364:25`
- `src/checks/automation/presentation/painting.cpp:408:82`
- `src/checks/automation/presentation/painting.cpp:418:51`
- `src/checks/automation/presentation/painting.cpp:438:69`
- `src/checks/automation/presentation/painting.cpp:441:67`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:264:42`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:289:69`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:380:64`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:392:33`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:397:48`
- `src/checks/automation/raster/painting.cpp:339:46`
- `src/checks/automation/raster/painting.cpp:355:55`
- `src/checks/automation/raster/painting.cpp:454:72`
- `src/checks/automation/raster/painting.cpp:456:73`
- `src/checks/automation/raster/painting.cpp:459:73`
- `src/checks/automation/raster/painting.cpp:479:58`
- `src/checks/automation/raster/painting.cpp:482:59`
- `src/checks/automation/raster/painting.cpp:486:59`
- `src/checks/automation/raster/rasterfixture.cpp:270:55`
- `src/checks/automation/tst_automationediting.cpp:142:79`
- `src/checks/automation/tst_automationediting.cpp:185:45`
- `src/checks/host/tst_hostadapter.cpp:506:81`
- `src/checks/host/tst_hostadapter.cpp:515:52`
- `src/checks/host/tst_hostseams.cpp:48:24`
- `src/checks/host/tst_hostseams.cpp:50:24`
- `src/checks/nativegraphics/tst_playhead_autohover.cpp:46:38`
- `src/checks/nativegraphics/tst_playhead_autohover.cpp:59:19`
- `src/checks/nativegraphics/tst_playhead_autohover.cpp:98:30`
- `src/checks/scrollbar/tst_scrollbar.cpp:261:24`
- `src/checks/scrollbar/tst_scrollbar.cpp:269:24`
- `src/checks/scrollbar/tst_scrollbar.cpp:304:24`
- `src/checks/scrollbar/tst_scrollbar.cpp:308:23`
- `src/checks/scrollbar/tst_scrollbar.cpp:310:24`
- `src/checks/scrollbar/tst_scrollbar.cpp:314:23`
- `src/checks/scrollbar/tst_scrollbar.cpp:314:53`
- `src/checks/scrollbar/tst_scrollbar.cpp:319:24`
- `src/checks/scrollbar/tst_scrollbar.cpp:323:23`
- `src/checks/scrollbar/tst_scrollbar.cpp:325:24`
- `src/checks/scrollbar/tst_scrollbar.cpp:328:23`
- `src/checks/scrollbar/tst_scrollbar.cpp:328:53`
- `src/checks/scrollbar/tst_scrollbar.cpp:361:24`
- `src/checks/scrollbar/tst_scrollbar.cpp:365:20`
- `src/checks/selectionkey/automationprobe.cpp:104:39`
- `src/checks/selectionkey/automationprobe.cpp:181:78`
- `src/checks/selectionkey/gesturecommands.cpp:129:41`
- `src/checks/selectionkey/gesturethumbs.cpp:61:80`
- `src/checks/selectionkey/windowtier_gestures.cpp:316:50`
- `src/checks/selectionkey/windowtier_gestures.cpp:329:60`
- `src/ui/editordrawer/automationcanvas.cpp:102:51`
- `src/ui/editordrawer/automationcanvas.cpp:107:50`
- `src/ui/editordrawer/automationcanvas.cpp:119:46`
- `src/ui/editordrawer/automationcanvas.cpp:310:28`
- `src/ui/editordrawer/automationcanvas_input.cpp:232:37`
- `src/ui/editordrawer/automationpage.cpp:53:21`
- `src/ui/editordrawer/drawerchrome.cpp:353:19`
- `src/ui/songview/quick/automationquick.cpp:137:39`

## pinnedTempoRect

- `src/ui/editordrawer/automationcanvas.h:148:11`
- `src/checks/automation/automationclipboard.cpp:44:56`
- `src/checks/automation/automationfixture.cpp:378:44`
- `src/checks/automation/automationmenus.cpp:263:56`
- `src/checks/automation/automationmenus.cpp:411:39`
- `src/checks/automation/automationrouting.cpp:104:48`
- `src/checks/automation/automationrouting.cpp:114:31`
- `src/checks/automation/hover/hoverfixture.cpp:311:44`
- `src/checks/automation/presentation/painting.cpp:139:72`
- `src/checks/automation/presentation/painting.cpp:193:58`
- `src/checks/automation/presentation/painting.cpp:195:63`
- `src/checks/automation/presentation/painting.cpp:205:51`
- `src/checks/automation/presentation/painting.cpp:228:58`
- `src/checks/automation/presentation/painting.cpp:230:63`
- `src/checks/automation/presentation/painting.cpp:262:58`
- `src/checks/automation/presentation/painting.cpp:274:52`
- `src/checks/automation/presentation/painting.cpp:297:55`
- `src/checks/automation/presentation/painting.cpp:306:54`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:271:68`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:288:51`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:344:40`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:364:50`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:398:51`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:422:47`
- `src/checks/automation/presentation/tst_automationpresentation.cpp:456:52`
- `src/checks/automation/raster/rasterfixture.cpp:289:34`
- `src/checks/host/tst_hostadapter.cpp:506:42`
- `src/checks/nativegraphics/tst_playhead_autohover.cpp:106:33`
- `src/ui/editordrawer/automationcanvas.cpp:434:25`

## updateTempoLayout

- `src/ui/editordrawer/automationcanvas.h:88:10`
- `src/ui/editordrawer/automationcanvas.cpp:303:24`
- `src/ui/editordrawer/automationcanvas_input.cpp:185:17`
- `src/ui/editordrawer/automationcanvas_input.cpp:486:9`

## minimumHeight

- `src/ui/editordrawer/cclanes.h:62:9`
- `src/ui/editordrawer/automationcanvas.cpp:130:22`
- `src/ui/editordrawer/cclanes.cpp:104:14`

## Additional source-owned consumers

- `src/ui/songview/viewstate.cpp`, `src/ui/songview.h`: addEmptyLane/removeEmptyLane wrappers.
- `src/ui/songview/quick/timelinequickview.cpp`: drawer-scroll refresh connection and new canvas context injection.
- `src/ui/songview/quick/TimelineCanvas.qml`: gutter input layering and Tempo header plates.
- `src/ui/songview/quick/timelinequickscene.h`, `timelinequickscene.cpp`: Tempo header plate properties.
- `src/ui/editordrawer/drawerchrome.h`, `drawerchrome.cpp`, `src/ui/songview/quick/DrawerChromeLayer.qml`: automation scrollbar properties/control; do not remove piano-roll/timeline scrollbars.
- `src/ui/editordrawer/editordrawer.cpp`, `drawersections.cpp`: scrollbar width subtraction and snapshot producers; automation-only minimum-height contract.
- `src/ui/editordrawer/automationcanvas_deleteprompt.cpp`: retain guarded event deletion, remove only empty-row presentation mutation.
