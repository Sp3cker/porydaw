[91/536] Building CXX object CMakeFiles/porydaw_app.dir/src/mainwindow.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/mainwindow.cpp:46:
In member function ‘bool SongTab::isReady() const’,
    inlined from ‘MainWindow::onSelectedTabChanged(SongTab*)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/mainwindow.cpp:794:71,
    inlined from ‘QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, MainWindow::onSelectedTabChanged(SongTab*)::<lambda()> >::call(MainWindow::onSelectedTabChanged(SongTab*)::<lambda()>&, void**)::<lambda()>’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:117:25,
    inlined from ‘static void QtPrivate::FunctorCallBase::call_internal(void**, Lambda&&) [with R = void; Lambda = QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, MainWindow::onSelectedTabChanged(SongTab*)::<lambda()> >::call(MainWindow::onSelectedTabChanged(SongTab*)::<lambda()>&, void**)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:66:41,
    inlined from ‘static void QtPrivate::FunctorCall<std::integer_sequence<long unsigned int, _Idx ...>, QtPrivate::List<Tail ...>, R, Function>::call(Function&, void**) [with long unsigned int ...II = {}; SignalArgs = {}; R = void; Function = MainWindow::onSelectedTabChanged(SongTab*)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:116:29,
    inlined from ‘static void QtPrivate::FunctorCallable<Func, Args>::call(Func&, void*, void**) [with SignalArgs = QtPrivate::List<>; R = void; Func = MainWindow::onSelectedTabChanged(SongTab*)::<lambda()>; Args = {}]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:338:85,
    inlined from ‘static void QtPrivate::QCallableObject<Func, Args, R>::impl(int, QtPrivate::QSlotObjectBase*, QObject*, void**, bool*) [with Func = MainWindow::onSelectedTabChanged(SongTab*)::<lambda()>; Args = QtPrivate::List<>; R = void]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:548:53:
/home/runner/work/porydaw/porydaw/src/ui/songtab.h:69:35: warning: potential null pointer dereference [-Wnull-dereference]
   69 |     bool isReady() const { return m_midiBound && m_voicegroupBound; }
      |                                   ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songtab.h:69:35: warning: potential null pointer dereference [-Wnull-dereference]
[92/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/theme/themedialog.cpp.o
[93/536] Building CXX object CMakeFiles/porydaw_app.dir/src/audio/resonance_suppressor.cpp.o
[94/536] Building CXX object CMakeFiles/porydaw_app.dir/src/audio/audioengine.cpp.o
[95/536] Building CXX object CMakeFiles/porydaw_app.dir/src/audio/auditionslots.cpp.o
[96/536] Building CXX object CMakeFiles/porydaw_app.dir/src/audio/wavexport.cpp.o
[97/536] Building CXX object CMakeFiles/porydaw_app.dir/src/audio/sampledsp.cpp.o
[98/536] Building CXX object CMakeFiles/porydaw_app.dir/porydaw_app_autogen/mocs_compilation.cpp.o
[99/536] Building CXX object CMakeFiles/porydaw_app.dir/src/audio/samplewav.cpp.o
[100/536] Building C object CMakeFiles/porydaw_app.dir/src/audio/miniaudio_impl.c.o
[101/536] Building CXX object CMakeFiles/porydaw_app.dir/src/audio/sampledoc.cpp.o
[102/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/activity/trackactivity.cpp.o
[103/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/activity/trackactivityrender.cpp.o
[104/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/mid2agbtables.cpp.o
[105/536] Building CXX object CMakeFiles/porydaw_app.dir/src/audio/sf2reader.cpp.o
[106/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/smf.cpp.o
[107/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/xcmd.cpp.o
In function ‘xcmd::Projection xcmd::{anonymous}::toProjection(const ParsedEvents&)’,
    inlined from ‘xcmd::Projection xcmd::projectEvents(std::span<const Event>)’ at /home/runner/work/porydaw/porydaw/src/core/xcmd.cpp:562:44:
/home/runner/work/porydaw/porydaw/src/core/xcmd.cpp:128:65: warning: potential null pointer dereference [-Wnull-dereference]
  128 |             point.lane = descriptorForSelector(block.selector)->laneController;
      |                          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/core/xcmd.cpp: In function ‘xcmd::TrafficAssessment xcmd::assessTraffic(std::span<const Event>)’:
/home/runner/work/porydaw/porydaw/src/core/xcmd.cpp:583:56: warning: potential null pointer dereference [-Wnull-dereference]
  583 |             if (descriptorForSelector(block.selector)->laneController == kEchoVolumeLane)
      |                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~
In function ‘bool xcmd::{anonymous}::writeReplacesPoint(const xcmd::PointWrite&, const ProtocolEvent&, uint8_t)’,
    inlined from ‘bool xcmd::{anonymous}::pointIsReplaced(const NormalizedPointWrites&, const ProtocolEvent&, uint8_t)’ at /home/runner/work/porydaw/porydaw/src/core/xcmd.cpp:319:31,
    inlined from ‘void xcmd::{anonymous}::emitPointRewritePoint(std::vector<xcmd::Emission>&, const ProtocolEvent&, const SelectorBlock&, const PointRewritePlan&)’ at /home/runner/work/porydaw/porydaw/src/core/xcmd.cpp:328:24,
    inlined from ‘xcmd::Patch xcmd::{anonymous}::emitPointRewrite(const ParsedEvents&, const PointRewritePlan&)’ at /home/runner/work/porydaw/porydaw/src/core/xcmd.cpp:345:34,
    inlined from ‘std::optional<xcmd::Patch> xcmd::rewritePoints(std::span<const Event>, std::span<const long unsigned int>, std::span<const PointWrite>)’ at /home/runner/work/porydaw/porydaw/src/core/xcmd.cpp:622:28:
/home/runner/work/porydaw/porydaw/src/core/xcmd.cpp:312:43: warning: potential null pointer dereference [-Wnull-dereference]
  312 |            descriptorForLane(write.lane)->selector == selector;
      |            ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^~~~~~~~
In function ‘xcmd::Patch xcmd::{anonymous}::emitPointRewrite(const ParsedEvents&, const PointRewritePlan&)’,
    inlined from ‘std::optional<xcmd::Patch> xcmd::rewritePoints(std::span<const Event>, std::span<const long unsigned int>, std::span<const PointWrite>)’ at /home/runner/work/porydaw/porydaw/src/core/xcmd.cpp:622:28:
/home/runner/work/porydaw/porydaw/src/core/xcmd.cpp:349:85: warning: potential null pointer dereference [-Wnull-dereference]
  349 |         const uint8_t value = uint8_t(std::clamp(int(write->value), int(descriptor->minimumValue),
      |                                                                         ~~~~~~~~~~~~^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/core/xcmd.cpp:350:66: warning: potential null pointer dereference [-Wnull-dereference]
  350 |                                                  int(descriptor->maximumValue)));
      |                                                      ~~~~~~~~~~~~^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/core/xcmd.cpp:351:64: warning: potential null pointer dereference [-Wnull-dereference]
  351 |         appendCanonicalPoint(inserts, write->tick, descriptor->selector, value, write->channel);
      |                                                    ~~~~~~~~~~~~^~~~~~~~
[108/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/miditimeline.cpp.o
[109/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/songdocument_timeeditor.cpp.o
[110/536] Building CXX object CMakeFiles/porydaw_app.dir/src/audio/sampleimport.cpp.o
[111/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/songdocument_range.cpp.o
[112/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/songdocument_timeeditor_insert.cpp.o
[113/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/songdocument_timeeditor_xcmd.cpp.o
[114/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/songhistory.cpp.o
[115/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/songdocument_tempo.cpp.o
[116/536] Building CXX object CMakeFiles/porydaw_app.dir/src/porydaw_scale.cpp.o
[117/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/lanemoveplan.cpp.o
[118/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/timelineplayer.cpp.o
[119/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/songdocument.cpp.o
[120/536] Building CXX object CMakeFiles/porydaw_app.dir/src/project/voicegroupprojectcontext.cpp.o
[121/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/songdocument_xcmd.cpp.o
/home/runner/work/porydaw/porydaw/src/core/songdocument_xcmd.cpp: In member function ‘void SongDocument::moveLanePoints(const std::vector<LanePointMove>&)’:
/home/runner/work/porydaw/porydaw/src/core/songdocument_xcmd.cpp:324:77: warning: potential null pointer dereference [-Wnull-dereference]
  324 |                 const int clamped = std::clamp(write.value, int(descriptor->minimumValue),
      |                                                                 ~~~~~~~~~~~~^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/core/songdocument_xcmd.cpp:325:64: warning: potential null pointer dereference [-Wnull-dereference]
  325 |                                                int(descriptor->maximumValue));
      |                                                    ~~~~~~~~~~~~^~~~~~~~~~~~
[122/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/midiimport.cpp.o
[123/536] Building CXX object CMakeFiles/porydaw_app.dir/src/project/projectidentity.cpp.o
[124/536] Building CXX object CMakeFiles/porydaw_app.dir/src/project/decompproject.cpp.o
[125/536] Building CXX object CMakeFiles/porydaw_app.dir/src/project/projectworkspace.cpp.o
[126/536] Building CXX object CMakeFiles/porydaw_app.dir/src/project/songsmk.cpp.o
[127/536] Building CXX object CMakeFiles/porydaw_app.dir/src/project/sidecar.cpp.o
[128/536] Building CXX object CMakeFiles/porydaw_app.dir/src/project/songregistry.cpp.o
[129/536] Building CXX object CMakeFiles/porydaw_app.dir/src/project/samplereg.cpp.o
[130/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/dragspinbox.cpp.o
[131/536] Building CXX object CMakeFiles/porydaw_app.dir/src/project/projectio.cpp.o
[132/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/m4asemantics.cpp.o
[133/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/applicationstartup.cpp.o
[134/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/sf2zonepicker.cpp.o
[135/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/waveformview.cpp.o
[136/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/samplepicker.cpp.o
[137/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/newsongwizard.cpp.o
/home/runner/work/porydaw/porydaw/src/ui/newsongwizard.cpp: In member function ‘QString IdentityPage::player() const’:
/home/runner/work/porydaw/porydaw/src/ui/newsongwizard.cpp:154:23: warning: declaration of ‘data’ shadows a member of ‘IdentityPage’ [-Wshadow]
  154 |         const QString data = m_player->currentData().toString();
      |                       ^~~~
In file included from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qdialog.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qwizard.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/QWizard:1,
                 from /home/runner/work/porydaw/porydaw/src/ui/newsongwizard.h:3,
                 from /home/runner/work/porydaw/porydaw/src/ui/newsongwizard.cpp:1:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qwidget.h:785:18: note: shadowed declaration is here
  785 |     QWidgetData *data;
      |                  ^~~~
[138/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/voicetypeicons.cpp.o
[139/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/sampleeditordialog.cpp.o
[140/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/keymap.cpp.o
[141/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/enginesettingsdialog.cpp.o
[142/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songsettingsdialog.cpp.o
[143/536] Building CXX object CMakeFiles/porydaw_app.dir/src/project/voicegroupsource.cpp.o
[144/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/settingsdialog.cpp.o
[145/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/polyphonypanel.cpp.o
[146/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songviewmodel.cpp.o
[147/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/voicegroupbrowser.cpp.o
[148/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/fastlabel.cpp.o
[149/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songlistpanel.cpp.o
[150/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/transportbar.cpp.o
[151/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/mousehints/mousehints.cpp.o
[152/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/mousehints/widgethints.cpp.o
In file included from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qsharedpointer.h:13,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qdebug.h:21,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qvariant.h:13,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qlocale.h:8,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtGui/qguiapplication.h:11,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qapplication.h:14,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/QApplication:1,
                 from /home/runner/work/porydaw/porydaw/src/porydaw_pch.hpp:6,
                 from /home/runner/work/porydaw/porydaw/build-asan/CMakeFiles/porydaw_app.dir/cmake_pch.hxx:5,
                 from <command-line>:
In member function ‘bool QWeakPointer<T>::isNull() const [with T = QObject]’,
    inlined from ‘bool QPointer<T>::isNull() const [with T = QObject]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qpointer.h:87:23,
    inlined from ‘QPointer<T>::operator bool() const [with T = QObject]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qpointer.h:88:61,
    inlined from ‘void ui::WidgetHintsObserver::settleCovered()’ at /home/runner/work/porydaw/porydaw/src/ui/mousehints/widgethints.cpp:370:85:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qsharedpointer_impl.h:614:43: warning: potential null pointer dereference [-Wnull-dereference]
  614 |     bool isNull() const noexcept { return d == nullptr || d->strongref.loadRelaxed() == 0 || value == nullptr; }
      |                                           ^
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qsharedpointer_impl.h:614:43: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘T* QWeakPointer<T>::internalData() const [with T = QObject]’,
    inlined from ‘T* QPointer<T>::data() const [with T = QObject]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qpointer.h:76:45,
    inlined from ‘QPointer<T>::operator T*() const [with T = QObject]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qpointer.h:84:18,
    inlined from ‘void ui::WidgetHintsObserver::settleCovered()’ at /home/runner/work/porydaw/porydaw/src/ui/mousehints/widgethints.cpp:370:65:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qsharedpointer_impl.h:799:16: warning: potential null pointer dereference [-Wnull-dereference]
  799 |         return d == nullptr || d->strongref.loadRelaxed() == 0 ? nullptr : value;
      |                ^
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qsharedpointer_impl.h:799:16: warning: potential null pointer dereference [-Wnull-dereference]
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qsharedpointer_impl.h:799:16: warning: potential null pointer dereference [-Wnull-dereference]
In file included from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobject.h:18,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qabstracteventdispatcher.h:8,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qbasictimer.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qcoreevent.h:8,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qcoreapplication.h:11,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qapplication.h:9:
In member function ‘T* QScopedPointer<T, Cleanup>::operator->() const [with T = QObjectData; Cleanup = QScopedPointerDeleter<QObjectData>]’,
    inlined from ‘QObject* QObject::parent() const’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobject.h:351:50,
    inlined from ‘QWidget* QWidget::parentWidget() const’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qwidget.h:910:48,
    inlined from ‘QWidget* ui::{anonymous}::profileOwner(QWidget*)’ at /home/runner/work/porydaw/porydaw/src/ui/mousehints/widgethints.cpp:41:78,
    inlined from ‘void ui::WidgetHintsObserver::claimHover()’ at /home/runner/work/porydaw/porydaw/src/ui/mousehints/widgethints.cpp:312:52:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qscopedpointer.h:93:16: warning: potential null pointer dereference [-Wnull-dereference]
   93 |         return d;
      |                ^
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qscopedpointer.h:93:16: warning: potential null pointer dereference [-Wnull-dereference]
[153/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/mousehints/hintprofiles.cpp.o
[154/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/workspaceui.cpp.o
[155/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/workspaceui_voicegroup.cpp.o
In file included from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qbytearray.h:12,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstringview.h:11,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qchar.h:730,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:15,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qcoreapplication.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qapplication.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/QApplication:1,
                 from /home/runner/work/porydaw/porydaw/src/porydaw_pch.hpp:6,
                 from /home/runner/work/porydaw/porydaw/build-asan/CMakeFiles/porydaw_app.dir/cmake_pch.hxx:5,
                 from <command-line>:
In copy constructor ‘QArrayDataPointer<T>::QArrayDataPointer(const QArrayDataPointer<T>&) [with T = char16_t]’,
    inlined from ‘QString::QString(const QString&)’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:1391:51,
    inlined from ‘VoicegroupId::VoicegroupId(const VoicegroupId&)’ at /home/runner/work/porydaw/porydaw/src/project/projectidentity.h:39:7,
    inlined from ‘void WorkspaceUi::rebuildVoicegroupPresentation()’ at /home/runner/work/porydaw/porydaw/src/ui/workspaceui_voicegroup.cpp:164:50:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:50: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                                            ~~~~~~^~~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:33: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                           ~~~~~~^~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:19: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |             ~~~~~~^
[156/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/workspaceui_tabs.cpp.o
In file included from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qbytearray.h:12,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstringview.h:11,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qchar.h:730,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:15,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qcoreapplication.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qapplication.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/QApplication:1,
                 from /home/runner/work/porydaw/porydaw/src/porydaw_pch.hpp:6,
                 from /home/runner/work/porydaw/porydaw/build-asan/CMakeFiles/porydaw_app.dir/cmake_pch.hxx:5,
                 from <command-line>:
In copy constructor ‘QArrayDataPointer<T>::QArrayDataPointer(const QArrayDataPointer<T>&) [with T = char16_t]’,
    inlined from ‘QString::QString(const QString&)’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:1391:51,
    inlined from ‘VoicegroupId::VoicegroupId(const VoicegroupId&)’ at /home/runner/work/porydaw/porydaw/src/project/projectidentity.h:39:7,
    inlined from ‘const LoadedBankView* WorkspaceUi::bankViewFor(const SongTab&) const’ at /home/runner/work/porydaw/porydaw/src/ui/workspaceui_tabs.cpp:191:24:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:50: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                                            ~~~~~~^~~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:33: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                           ~~~~~~^~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:19: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |             ~~~~~~^
[157/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/workspaceui_project.cpp.o
[158/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songtabquickhost.cpp.o
[159/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/pitchprojection.cpp.o
[160/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songtab.cpp.o
[161/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/playheadoverlay.cpp.o
[162/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/voicegroupviewcache.cpp.o
[163/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/workspaceui_samples.cpp.o
[164/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/voicepicker.cpp.o
[165/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/otherstrip.cpp.o
[166/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview.cpp.o
/home/runner/work/porydaw/porydaw/src/ui/songview.cpp: In lambda function:
/home/runner/work/porydaw/porydaw/src/ui/songview.cpp:446:34: warning: declaration of ‘pending’ shadows a previous local [-Wshadow]
  446 |         const PendingVoicePicker pending = std::move(*m_pendingVoicePicker);
      |                                  ^~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview.cpp:424:24: note: shadowed declaration is here
  424 |     PendingVoicePicker pending;
      |                        ^~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview.cpp:449:28: warning: declaration of ‘self’ shadows a previous local [-Wshadow]
  449 |         QPointer<SongView> self(this);
      |                            ^~~~
/home/runner/work/porydaw/porydaw/src/ui/songview.cpp:406:24: note: shadowed declaration is here
  406 |     QPointer<SongView> self(this);
      |                        ^~~~
/home/runner/work/porydaw/porydaw/src/ui/songview.cpp:451:53: warning: declaration of ‘liveQuick’ shadows a previous local [-Wshadow]
  451 |         const QPointer<songview::TimelineQuickView> liveQuick(quickView());
      |                                                     ^~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview.cpp:403:49: note: shadowed declaration is here
  403 |     const QPointer<songview::TimelineQuickView> liveQuick(quick);
      |                                                 ^~~~~~~~~
[167/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/detail.cpp.o
[168/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/editorselectionmodel.cpp.o
[169/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/trackheadermenu.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/ui/songview/trackheadermenu.cpp:4:
In member function ‘SongDocument& SongView::document() const’,
    inlined from ‘songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/ui/songview/trackheadermenu.cpp:158:43,
    inlined from ‘SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/ui/songview.h:830:29,
    inlined from ‘QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()> >::call(SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>&, void**)::<lambda()>’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:117:25,
    inlined from ‘static void QtPrivate::FunctorCallBase::call_internal(void**, Lambda&&) [with R = void; Lambda = QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()> >::call(SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>&, void**)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:66:41,
    inlined from ‘static void QtPrivate::FunctorCall<std::integer_sequence<long unsigned int, _Idx ...>, QtPrivate::List<Tail ...>, R, Function>::call(Function&, void**) [with long unsigned int ...II = {}; SignalArgs = {}; R = void; Function = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:116:29,
    inlined from ‘static void QtPrivate::FunctorCallable<Func, Args>::call(Func&, void*, void**) [with SignalArgs = QtPrivate::List<>; R = void; Func = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>; Args = {}]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:338:85,
    inlined from ‘static void QtPrivate::QCallableObject<Func, Args, R>::impl(int, QtPrivate::QSlotObjectBase*, QObject*, void**, bool*) [with Func = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>; Args = QtPrivate::List<>; R = void]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:548:53:
/home/runner/work/porydaw/porydaw/src/ui/songview.h:156:54: warning: potential null pointer dereference [-Wnull-dereference]
  156 |     SongDocument &document() const noexcept { return m_document; }
      |                                                      ^~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview.h:156:54: warning: potential null pointer dereference [-Wnull-dereference]
In file included from /home/runner/work/porydaw/porydaw/src/ui/songview/trackheadermenu.cpp:3:
In member function ‘uint64_t SongDocument::revision() const’,
    inlined from ‘songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/ui/songview/trackheadermenu.cpp:159:44,
    inlined from ‘SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/ui/songview.h:830:29,
    inlined from ‘QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()> >::call(SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>&, void**)::<lambda()>’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:117:25,
    inlined from ‘static void QtPrivate::FunctorCallBase::call_internal(void**, Lambda&&) [with R = void; Lambda = QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()> >::call(SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>&, void**)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:66:41,
    inlined from ‘static void QtPrivate::FunctorCall<std::integer_sequence<long unsigned int, _Idx ...>, QtPrivate::List<Tail ...>, R, Function>::call(Function&, void**) [with long unsigned int ...II = {}; SignalArgs = {}; R = void; Function = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:116:29,
    inlined from ‘static void QtPrivate::FunctorCallable<Func, Args>::call(Func&, void*, void**) [with SignalArgs = QtPrivate::List<>; R = void; Func = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>; Args = {}]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:338:85,
    inlined from ‘static void QtPrivate::QCallableObject<Func, Args, R>::impl(int, QtPrivate::QSlotObjectBase*, QObject*, void**, bool*) [with Func = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>; Args = QtPrivate::List<>; R = void]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:548:53:
/home/runner/work/porydaw/porydaw/src/core/songdocument.h:147:40: warning: potential null pointer dereference [-Wnull-dereference]
  147 |     uint64_t revision() const { return m_revision; }
      |                                        ^~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/core/songdocument.h:147:40: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘SongDocument& SongView::document() const’,
    inlined from ‘songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/ui/songview/trackheadermenu.cpp:134:43,
    inlined from ‘SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/ui/songview.h:830:29,
    inlined from ‘QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()> >::call(SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>&, void**)::<lambda()>’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:117:25,
    inlined from ‘static void QtPrivate::FunctorCallBase::call_internal(void**, Lambda&&) [with R = void; Lambda = QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()> >::call(SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>&, void**)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:66:41,
    inlined from ‘static void QtPrivate::FunctorCall<std::integer_sequence<long unsigned int, _Idx ...>, QtPrivate::List<Tail ...>, R, Function>::call(Function&, void**) [with long unsigned int ...II = {}; SignalArgs = {}; R = void; Function = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:116:29,
    inlined from ‘static void QtPrivate::FunctorCallable<Func, Args>::call(Func&, void*, void**) [with SignalArgs = QtPrivate::List<>; R = void; Func = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>; Args = {}]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:338:85,
    inlined from ‘static void QtPrivate::QCallableObject<Func, Args, R>::impl(int, QtPrivate::QSlotObjectBase*, QObject*, void**, bool*) [with Func = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>; Args = QtPrivate::List<>; R = void]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:548:53:
/home/runner/work/porydaw/porydaw/src/ui/songview.h:156:54: warning: potential null pointer dereference [-Wnull-dereference]
  156 |     SongDocument &document() const noexcept { return m_document; }
      |                                                      ^~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview.h:156:54: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘uint64_t SongDocument::revision() const’,
    inlined from ‘songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/ui/songview/trackheadermenu.cpp:135:44,
    inlined from ‘SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/ui/songview.h:830:29,
    inlined from ‘QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()> >::call(SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>&, void**)::<lambda()>’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:117:25,
    inlined from ‘static void QtPrivate::FunctorCallBase::call_internal(void**, Lambda&&) [with R = void; Lambda = QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()> >::call(SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>&, void**)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:66:41,
    inlined from ‘static void QtPrivate::FunctorCall<std::integer_sequence<long unsigned int, _Idx ...>, QtPrivate::List<Tail ...>, R, Function>::call(Function&, void**) [with long unsigned int ...II = {}; SignalArgs = {}; R = void; Function = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:116:29,
    inlined from ‘static void QtPrivate::FunctorCallable<Func, Args>::call(Func&, void*, void**) [with SignalArgs = QtPrivate::List<>; R = void; Func = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>; Args = {}]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:338:85,
    inlined from ‘static void QtPrivate::QCallableObject<Func, Args, R>::impl(int, QtPrivate::QSlotObjectBase*, QObject*, void**, bool*) [with Func = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>; Args = QtPrivate::List<>; R = void]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:548:53:
/home/runner/work/porydaw/porydaw/src/core/songdocument.h:147:40: warning: potential null pointer dereference [-Wnull-dereference]
  147 |     uint64_t revision() const { return m_revision; }
      |                                        ^~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/core/songdocument.h:147:40: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘SongDocument& SongView::document() const’,
    inlined from ‘songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/ui/songview/trackheadermenu.cpp:150:43,
    inlined from ‘SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/ui/songview.h:830:29,
    inlined from ‘QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()> >::call(SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>&, void**)::<lambda()>’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:117:25,
    inlined from ‘static void QtPrivate::FunctorCallBase::call_internal(void**, Lambda&&) [with R = void; Lambda = QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()> >::call(SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>&, void**)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:66:41,
    inlined from ‘static void QtPrivate::FunctorCall<std::integer_sequence<long unsigned int, _Idx ...>, QtPrivate::List<Tail ...>, R, Function>::call(Function&, void**) [with long unsigned int ...II = {}; SignalArgs = {}; R = void; Function = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:116:29,
    inlined from ‘static void QtPrivate::FunctorCallable<Func, Args>::call(Func&, void*, void**) [with SignalArgs = QtPrivate::List<>; R = void; Func = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>; Args = {}]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:338:85,
    inlined from ‘static void QtPrivate::QCallableObject<Func, Args, R>::impl(int, QtPrivate::QSlotObjectBase*, QObject*, void**, bool*) [with Func = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>; Args = QtPrivate::List<>; R = void]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:548:53:
/home/runner/work/porydaw/porydaw/src/ui/songview.h:156:54: warning: potential null pointer dereference [-Wnull-dereference]
  156 |     SongDocument &document() const noexcept { return m_document; }
      |                                                      ^~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview.h:156:54: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘uint64_t SongDocument::revision() const’,
    inlined from ‘songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/ui/songview/trackheadermenu.cpp:151:44,
    inlined from ‘SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/ui/songview.h:830:29,
    inlined from ‘QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()> >::call(SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>&, void**)::<lambda()>’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:117:25,
    inlined from ‘static void QtPrivate::FunctorCallBase::call_internal(void**, Lambda&&) [with R = void; Lambda = QtPrivate::FunctorCall<std::integer_sequence<long unsigned int>, QtPrivate::List<>, void, SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()> >::call(SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>&, void**)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:66:41,
    inlined from ‘static void QtPrivate::FunctorCall<std::integer_sequence<long unsigned int, _Idx ...>, QtPrivate::List<Tail ...>, R, Function>::call(Function&, void**) [with long unsigned int ...II = {}; SignalArgs = {}; R = void; Function = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:116:29,
    inlined from ‘static void QtPrivate::FunctorCallable<Func, Args>::call(Func&, void*, void**) [with SignalArgs = QtPrivate::List<>; R = void; Func = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>; Args = {}]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:338:85,
    inlined from ‘static void QtPrivate::QCallableObject<Func, Args, R>::impl(int, QtPrivate::QSlotObjectBase*, QObject*, void**, bool*) [with Func = SongView::queueHeaderMutation<songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()> >(songview::TrackHeaderModel::handleHeaderMenuAction(int)::<lambda()>&&)::<lambda()>; Args = QtPrivate::List<>; R = void]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qobjectdefs_impl.h:548:53:
/home/runner/work/porydaw/porydaw/src/core/songdocument.h:147:40: warning: potential null pointer dereference [-Wnull-dereference]
  147 |     uint64_t revision() const { return m_revision; }
      |                                        ^~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/core/songdocument.h:147:40: warning: potential null pointer dereference [-Wnull-dereference]
[170/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/camera.cpp.o
[171/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/timeaxis.cpp.o
[172/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/trackheadermodel.cpp.o
[173/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/timecamera.cpp.o
[174/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/grid.cpp.o
[175/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/editkeyrouting.cpp.o
[176/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/scalecontroller.cpp.o
[177/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/editactions.cpp.o
[178/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/trackvoiceops.cpp.o
[179/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/viewstate.cpp.o
[180/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/clipmime.cpp.o
[181/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/rangeedit.cpp.o
[182/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/drawercoordination.cpp.o
[183/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/pianoroll.cpp.o
[184/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/pianoroll_geometry.cpp.o
[185/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/timeruler_interaction.cpp.o
/home/runner/work/porydaw/porydaw/src/ui/songview/timeruler_interaction.cpp: In member function ‘virtual bool songview::TimeRuler::pointerMove(const songview::TimelinePointerInput&)’:
/home/runner/work/porydaw/porydaw/src/ui/songview/timeruler_interaction.cpp:129:36: warning: comparison is always true due to limited range of data type [-Wtype-limits]
  129 |                     if (note.track >= 0 && note.track < 16 &&
      |                         ~~~~~~~~~~~^~~~
[186/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/timeruler.cpp.o
[187/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/pianoroll_interaction.cpp.o
[188/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/pianoroll_gestures.cpp.o
[189/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/pianoroll_gestures_active.cpp.o
[190/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/quickmenumodel.cpp.o
[191/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/pianoroll_commands.cpp.o
[192/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/quickpopupsession.cpp.o
[193/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/quickmenulayout.cpp.o
[194/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/quickmenuhost.cpp.o
[195/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/promptappearance.cpp.o
[196/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/eventlistcontroller.cpp.o
[197/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/otherstripquick.cpp.o
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/otherstripquick.cpp: In member function ‘void songview::OtherStrip::rebuildQuickScene(songview::TimelineQuickScene&, bool)’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/otherstripquick.cpp:62:25: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::background’ [-Wmissing-field-initializers]
   62 |         labels.push_back({{TimelineQuickTextKeyKind::OtherEvents, {}, 0},
      |         ~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   63 |                           QRectF(textInset, 0, gutter.width() - 2 * textInset, gutter.height()),
      |                           ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   64 |                           SongView::tr("Other events (%1)").arg(model.strip.size()),
      |                           ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   65 |                           themes::color(themes::Role::song_view_primary_text),
      |                           ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   66 |                           m_inputHost->font(),
      |                           ~~~~~~~~~~~~~~~~~~~~
   67 |                           Qt::AlignLeft,
      |                           ~~~~~~~~~~~~~~
   68 |                           Qt::AlignVCenter,
      |                           ~~~~~~~~~~~~~~~~~
   69 |                           QRectF()});
      |                           ~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/otherstripquick.cpp:62:25: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::backgroundRect’ [-Wmissing-field-initializers]
[198/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/automationnodelanequick.cpp.o
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/automationnodelanequick.cpp: In function ‘void songview::{anonymous}::appendValueLabel(std::vector<songview::TimelineQuickTextModel::Record>*, songview::TimelineQuickTextKeyKind, const songview::NodeLaneQuickPaint::Context&, const NodeLaneHoverState::ValueLabelCache&)’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/automationnodelanequick.cpp:213:23: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::background’ [-Wmissing-field-initializers]
  213 |     records->push_back({{kind, {}, quint64(context.handle.index)},
      |     ~~~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  214 |                         rect,
      |                         ~~~~~
  215 |                         label.text,
      |                         ~~~~~~~~~~~
  216 |                         themes::color(themes::Role::song_view_primary_text),
      |                         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  217 |                         label.font,
      |                         ~~~~~~~~~~~
  218 |                         Qt::AlignHCenter,
      |                         ~~~~~~~~~~~~~~~~~
  219 |                         Qt::AlignVCenter,
      |                         ~~~~~~~~~~~~~~~~~
  220 |                         QRectF()});
      |                         ~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/automationnodelanequick.cpp:213:23: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::backgroundRect’ [-Wmissing-field-initializers]
[199/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/velocityquick.cpp.o
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/velocityquick.cpp: In function ‘void songview::{anonymous}::appendAxisText(std::vector<songview::TimelineQuickTextModel::Record>&, quint64, const QRectF&, const QString&, const QColor&, const QFont&)’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/velocityquick.cpp:39:22: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::background’ [-Wmissing-field-initializers]
   39 |     records.push_back({{TimelineQuickTextKeyKind::VelocityAxis, {}, ordinal},
      |     ~~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   40 |                        rect,
      |                        ~~~~~
   41 |                        text,
      |                        ~~~~~
   42 |                        color,
      |                        ~~~~~~
   43 |                        font,
      |                        ~~~~~
   44 |                        Qt::AlignRight,
      |                        ~~~~~~~~~~~~~~~
   45 |                        Qt::AlignVCenter,
      |                        ~~~~~~~~~~~~~~~~~
   46 |                        QRectF()});
      |                        ~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/velocityquick.cpp:39:22: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::backgroundRect’ [-Wmissing-field-initializers]
[200/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/timelineinputitem.cpp.o
[201/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/voicechangequick.cpp.o
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/voicechangequick.cpp: In function ‘void {anonymous}::appendText(std::vector<songview::TimelineQuickTextModel::Record>&, quint64, const QRectF&, const QString&, const QColor&, const QFont&, Qt::Alignment, Qt::Alignment)’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/voicechangequick.cpp:45:22: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::background’ [-Wmissing-field-initializers]
   45 |     records.push_back({{songview::TimelineQuickTextKeyKind::VoiceChanges, {}, ordinal},
      |     ~~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   46 |                        rect,
      |                        ~~~~~
   47 |                        text,
      |                        ~~~~~
   48 |                        color,
      |                        ~~~~~~
   49 |                        font,
      |                        ~~~~~
   50 |                        horizontalAlignment,
      |                        ~~~~~~~~~~~~~~~~~~~~
   51 |                        verticalAlignment,
      |                        ~~~~~~~~~~~~~~~~~~
   52 |                        QRectF()});
      |                        ~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/voicechangequick.cpp:45:22: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::backgroundRect’ [-Wmissing-field-initializers]
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/voicechangequick.cpp: In member function ‘void VoiceChangeArea::rebuildQuickHover(songview::TimelineQuickScene&)’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/voicechangequick.cpp:281:17: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::background’ [-Wmissing-field-initializers]
  281 |         QRectF()};
      |                 ^
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/voicechangequick.cpp:281:17: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::backgroundRect’ [-Wmissing-field-initializers]
[202/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/automationquick.cpp.o
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/automationquick.cpp: In function ‘void songview::{anonymous}::appendText(std::vector<songview::TimelineQuickTextModel::Record>&, songview::TimelineQuickTextKeyKind, quint64, const QRectF&, const QString&, const QColor&, const QFont&, Qt::Alignment, QRectF)’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/automationquick.cpp:40:22: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::background’ [-Wmissing-field-initializers]
   40 |     records.push_back(
      |     ~~~~~~~~~~~~~~~~~^
   41 |         {{kind, {}, ordinal}, rect, text, color, font, horizontal, Qt::AlignVCenter, clip});
      |         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/automationquick.cpp:40:22: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::backgroundRect’ [-Wmissing-field-initializers]
[203/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/timelinequickchrome.cpp.o
[204/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/playheadquick.cpp.o
[205/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/timelinequickscene.cpp.o
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickscene.cpp: In member function ‘void songview::TimelineQuickTextModel::setRecords(std::span<const Record>)’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickscene.cpp:302:15: warning: potential null pointer dereference [-Wnull-dereference]
  302 |             ++*rowFor(m_currentRows, m_records[static_cast<std::size_t>(row)].key);
      |               ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickscene.cpp:302:13: warning: potential null pointer dereference [-Wnull-dereference]
  302 |             ++*rowFor(m_currentRows, m_records[static_cast<std::size_t>(row)].key);
      |             ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[206/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/timelinequickview_pianoroll.cpp.o
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_pianoroll.cpp: In member function ‘void songview::TimelineQuickView::rebuildDrawPreviewFill()’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_pianoroll.cpp:258:15: warning: potential null pointer dereference [-Wnull-dereference]
  258 |     if (!roll.m_sv->timeline() || roll.m_leftDrag != PianoRoll::LeftDrag::Draw)
      |          ~~~~~^~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_pianoroll.cpp:258:15: warning: potential null pointer dereference [-Wnull-dereference]
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_pianoroll.cpp: In member function ‘void songview::TimelineQuickView::rebuildNoteFills()’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_pianoroll.cpp:220:15: warning: potential null pointer dereference [-Wnull-dereference]
  220 |     if (!roll.m_sv->timeline())
      |          ~~~~~^~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_pianoroll.cpp:220:15: warning: potential null pointer dereference [-Wnull-dereference]
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_pianoroll.cpp: In member function ‘void songview::TimelineQuickView::rebuildOverlay()’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_pianoroll.cpp:351:15: warning: potential null pointer dereference [-Wnull-dereference]
  351 |     if (!roll.m_sv->timeline())
      |          ~~~~~^~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_pianoroll.cpp:351:15: warning: potential null pointer dereference [-Wnull-dereference]
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_pianoroll.cpp: In member function ‘void songview::TimelineQuickView::rebuildNoteBordersAndSelection()’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_pianoroll.cpp:277:15: warning: potential null pointer dereference [-Wnull-dereference]
  277 |     if (!roll.m_sv->timeline())
      |          ~~~~~^~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_pianoroll.cpp:277:15: warning: potential null pointer dereference [-Wnull-dereference]
[207/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/timelinequickview_keyrouting.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_keyrouting.cpp:4:
In member function ‘bool EventListController::isEditing() const’,
    inlined from ‘bool songview::TimelineQuickView::dispatchSongKey(const songview::TimelineKeyInput&)’ at /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_keyrouting.cpp:32:46:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/eventlistcontroller.h:69:46: warning: potential null pointer dereference [-Wnull-dereference]
   69 |     bool isEditing() const noexcept { return m_editingRow >= 0; }
      |                                              ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/eventlistcontroller.h:69:46: warning: potential null pointer dereference [-Wnull-dereference]
[208/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/timelinequickview.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationcanvas.h:33,
                 from /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp:2:
In member function ‘int SongView::timelineSplitX() const’,
    inlined from ‘std::optional<double> songview::TimelineQuickView::guideSongViewContentXAtOrAfterStart(std::optional<double>) const’ at /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp:619:56:
/home/runner/work/porydaw/porydaw/src/ui/songview.h:249:61: warning: potential null pointer dereference [-Wnull-dereference]
  249 |     int timelineSplitX() const noexcept { return m_geometry.timelineSplitX; }
      |                                                             ^~~~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview.h:249:61: warning: potential null pointer dereference [-Wnull-dereference]
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp: In member function ‘bool songview::TimelineQuickView::focusEventListInput(Qt::FocusReason)’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp:726:35: warning: potential null pointer dereference [-Wnull-dereference]
  726 |     m_eventListInput->requestFocus(reason);
      |     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp:726:35: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘int SongView::timelineSplitX() const’,
    inlined from ‘void songview::TimelineQuickView::publishTimelineBandLayout()’ at /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp:771:70:
/home/runner/work/porydaw/porydaw/src/ui/songview.h:249:61: warning: potential null pointer dereference [-Wnull-dereference]
  249 |     int timelineSplitX() const noexcept { return m_geometry.timelineSplitX; }
      |                                                             ^~~~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview.h:249:61: warning: potential null pointer dereference [-Wnull-dereference]
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp: In member function ‘void songview::TimelineQuickView::syncVoiceChanges(songview::TimelineQuickDirtySet, bool)’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp:942:29: warning: potential null pointer dereference [-Wnull-dereference]
  942 |         if (m_voiceChanges->m_hoverActive)
      |             ~~~~~~~~~~~~~~~~^~~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp:942:29: warning: null pointer dereference [-Wnull-dereference]
In file included from /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp:3:
In member function ‘AutomationCanvas* AutomationPage::canvas()’,
    inlined from ‘void songview::TimelineQuickView::syncAutomation(songview::AutomationRefreshSet)’ at /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp:953:85:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
   38 |     AutomationCanvas *canvas() noexcept { return m_canvas; }
      |                                                  ^~~~~~~~
In member function ‘AutomationCanvas* AutomationPage::canvas()’,
    inlined from ‘void songview::TimelineQuickView::syncAutomation(songview::AutomationRefreshSet)’ at /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp:955:46:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
   38 |     AutomationCanvas *canvas() noexcept { return m_canvas; }
      |                                                  ^~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘AutomationCanvas* AutomationPage::canvas()’,
    inlined from ‘void songview::TimelineQuickView::syncAutomation(songview::AutomationRefreshSet)’ at /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp:953:85:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: null pointer dereference [-Wnull-dereference]
   38 |     AutomationCanvas *canvas() noexcept { return m_canvas; }
      |                                                  ^~~~~~~~
In member function ‘AutomationCanvas* AutomationPage::canvas()’,
    inlined from ‘songview::TimelineQuickView::TimelineQuickView(songview::TimeRuler&, songview::PianoRoll&, songview::OtherStrip&, AutomationPage&, VelocityArea&, VoiceChangeArea&, DrawerChrome&, songview::TrackHeaderModel&, EventListController&, SongView&)’ at /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp:297:94:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
   38 |     AutomationCanvas *canvas() noexcept { return m_canvas; }
      |                                                  ^~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘AutomationCanvas* AutomationPage::canvas()’,
    inlined from ‘songview::TimelineQuickView::TimelineQuickView(songview::TimeRuler&, songview::PianoRoll&, songview::OtherStrip&, AutomationPage&, VelocityArea&, VoiceChangeArea&, DrawerChrome&, songview::TrackHeaderModel&, EventListController&, SongView&)’ at /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview.cpp:300:35:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
   38 |     AutomationCanvas *canvas() noexcept { return m_canvas; }
      |                                                  ^~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
[209/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/timelinequickview_window.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_window.cpp:13:
In member function ‘AutomationCanvas* AutomationPage::canvas()’,
    inlined from ‘void songview::TimelineQuickView::detachWindow()’ at /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_window.cpp:141:45:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
   38 |     AutomationCanvas *canvas() noexcept { return m_canvas; }
      |                                                  ^~~~~~~~
In member function ‘AutomationCanvas* AutomationPage::canvas()’,
    inlined from ‘void songview::TimelineQuickView::detachWindow()’ at /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_window.cpp:142:48:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
   38 |     AutomationCanvas *canvas() noexcept { return m_canvas; }
      |                                                  ^~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘AutomationCanvas* AutomationPage::canvas()’,
    inlined from ‘void songview::TimelineQuickView::detachWindow()’ at /home/runner/work/porydaw/porydaw/src/ui/songview/quick/timelinequickview_window.cpp:141:45:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: null pointer dereference [-Wnull-dereference]
   38 |     AutomationCanvas *canvas() noexcept { return m_canvas; }
      |                                                  ^~~~~~~~
[210/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/songview/quick/timerulerquick.cpp.o
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timerulerquick.cpp: In function ‘void songview::{anonymous}::appendTextRecord(std::vector<songview::TimelineQuickTextModel::Record>&, quint64, const QRectF&, const QString&, const QFont&, const QColor&)’:
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timerulerquick.cpp:34:22: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::background’ [-Wmissing-field-initializers]
   34 |     records.push_back({{TimelineQuickTextKeyKind::Ruler, {}, ordinal},
      |     ~~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   35 |                        rect,
      |                        ~~~~~
   36 |                        text,
      |                        ~~~~~
   37 |                        color,
      |                        ~~~~~~
   38 |                        font,
      |                        ~~~~~
   39 |                        Qt::AlignLeft,
      |                        ~~~~~~~~~~~~~~
   40 |                        Qt::AlignVCenter,
      |                        ~~~~~~~~~~~~~~~~~
   41 |                        QRectF()});
      |                        ~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songview/quick/timerulerquick.cpp:34:22: warning: missing initializer for member ‘songview::TimelineQuickTextModel::Record::backgroundRect’ [-Wmissing-field-initializers]
[211/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/pitchbendgraph_render.cpp.o
[212/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/pitchbendgraph.cpp.o
[213/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/eventtablemodel.cpp.o
[214/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/pitchbendeditor.cpp.o
[215/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/eventtablemodeledit.cpp.o
[216/536] Building CXX object CMakeFiles/porydaw_app.dir/src/core/velocitymodel.cpp.o
[217/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/eventtabletypes.cpp.o
[218/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/velocitygesturemodel.cpp.o
[219/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/editordrawer.cpp.o
[220/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/drawersections.cpp.o
[221/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/drawerchrome.cpp.o
[222/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editorviewstate.cpp.o
[223/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/automationcanvas.cpp.o
[224/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/automationcanvas_input.cpp.o
[225/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/automationcanvas_tabs.cpp.o
[226/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/automationcanvas_deleteprompt.cpp.o
[227/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/automationcanvas_gesture.cpp.o
[228/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/automationcanvas_pointmenu.cpp.o
[229/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/automationcanvas_taptempo.cpp.o
[230/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/automationviewmodel.cpp.o
[231/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/automationcanvas_menu.cpp.o
[232/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/nodelane/hover.cpp.o
[233/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/cclanes.cpp.o
[234/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/nodelane/gesture.cpp.o
[235/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/automationprojection.cpp.o
[236/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/nodelane/pencilgesture.cpp.o
[237/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/voicechangearea/voicechangearea.cpp.o
[238/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/voicechangearea/voicechangemenu.cpp.o
[239/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/nodelane/nodelane.cpp.o
[240/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/nodelane/tempoadapter.cpp.o
[241/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/automationpage.cpp.o
[242/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/tempolane.cpp.o
[243/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/velocityaxis.cpp.o
[244/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/nodelane/batchcommit.cpp.o
In function ‘TempoPoint nodelane::{anonymous}::tempoDestination(const TempoPoint&, const NodePoint&)’,
    inlined from ‘std::optional<TempoEdit> nodelane::resolveTempoMoves(const SongDocument&, const std::vector<NodePointMove>&)’ at /home/runner/work/porydaw/porydaw/src/ui/editordrawer/nodelane/batchcommit.cpp:71:56:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/nodelane/batchcommit.cpp:40:69: warning: potential null pointer dereference [-Wnull-dereference]
   40 |     const int currentBpm = qRound(CoreTimeDefaults::tempoBpm(source.microsecondsPerQuarterNote));
      |                                                              ~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~
[245/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/velocityarea/velocityarea_interaction.cpp.o
[246/536] Building CXX object CMakeFiles/porydaw_app.dir/src/ui/editordrawer/velocityarea/velocityarea.cpp.o
[247/536] Building CXX object CMakeFiles/porydaw_app.dir/porydaw_app_qmltyperegistrations.cpp.o
[248/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_qmlcache_loader.cpp.o
In file included from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qglobal.h:58,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtGui/qtguiglobal.h:7,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qtwidgetsglobal.h:8,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qapplication.h:8,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/QApplication:1,
                 from /home/runner/work/porydaw/porydaw/src/porydaw_pch.hpp:6,
                 from /home/runner/work/porydaw/porydaw/build-asan/CMakeFiles/porydaw_app.dir/cmake_pch.hxx:5,
                 from <command-line>:
In member function ‘QGlobalStatic<Holder>::Type* QGlobalStatic<Holder>::operator()() [with Holder = QtGlobalStatic::Holder<{anonymous}::{anonymous}::Q_QGS_unitRegistry>]’,
    inlined from ‘static const QQmlPrivate::CachedQmlUnit* {anonymous}::Registry::lookupCachedUnit(const QUrl&)’ at /home/runner/work/porydaw/porydaw/build-asan/.rcc/qmlcache/porydaw_app_qmlcache_loader.cpp:216:24:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qglobalstatic.h:83:20: warning: potential null pointer dereference [-Wnull-dereference]
   83 |             return nullptr;
      |                    ^~~~~~~
[249/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_TimelineScrollbar_qml.cpp.o
[250/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_PianoRollCanvas_qml.cpp.o
[251/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_AutomationTabs_qml.cpp.o
[252/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_RulerToolTip_qml.cpp.o
[253/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_RulerControls_qml.cpp.o
[254/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_TimelineCanvas_qml.cpp.o
[255/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_OtherStripToolTip_qml.cpp.o
[256/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_QuickPopupLayer_qml.cpp.o
[257/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_DrawerChromeLayer_qml.cpp.o
[258/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_TrackHeaderBand_qml.cpp.o
[259/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_QuickMenuPanel_qml.cpp.o
[260/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_PromptCard_qml.cpp.o
[261/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_HoverHint_qml.cpp.o
[262/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_DragInput_qml.cpp.o
[263/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_PromptButton_qml.cpp.o
[264/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_VelocityPrompt_qml.cpp.o
[265/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_CcDeleteConfirm_qml.cpp.o
[266/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_TimeSignaturePrompt_qml.cpp.o
[267/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_InsertTimePrompt_qml.cpp.o
[268/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_PitchBendPopup_qml.cpp.o
[269/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_VoicePickerPrompt_qml.cpp.o
[270/536] Building CXX object CMakeFiles/porydaw_app.dir/build-asan/.rcc/qmlcache/porydaw_app_src_ui_songview_quick_EventListPage_qml.cpp.o
[271/536] Linking CXX static library libporydaw_app.a
[272/536] Automatic MOC and UIC for target porydaw
[273/536] Running rcc for resource cursor_images
[274/536] Running rcc for resource app_icon
[275/536] Automatic RCC for resources/fonts.qrc
[276/536] Building CXX object CMakeFiles/porydaw.dir/porydaw_autogen/mocs_compilation.cpp.o
[277/536] Building CXX object CMakeFiles/porydaw.dir/build-asan/.qt/rcc/qrc_app_icon.cpp.o
[278/536] Building CXX object CMakeFiles/porydaw.dir/build-asan/.qt/rcc/qrc_cursor_images.cpp.o
[279/536] Building CXX object CMakeFiles/porydaw.dir/porydaw_autogen/3YJK5W5UP7/qrc_fonts.cpp.o
[280/536] Building CXX object CMakeFiles/porydaw.dir/src/main.cpp.o
[281/536] Automatic MOC and UIC for target porydaw_checks
[282/536] Running rcc for resource smf_check_fixtures
[283/536] Running rcc for resource checks_cursor_images
[284/536] Running rcc for resource checks_app_icon
[285/536] Automatic RCC for ../../resources/fonts.qrc
[286/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/.qt/rcc/qrc_checks_cursor_images.cpp.o
[287/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/.qt/rcc/qrc_smf_check_fixtures.cpp.o
[288/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/.qt/rcc/qrc_checks_app_icon.cpp.o
[289/536] Linking CXX executable porydaw
[290/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/cmake_pch.hxx.gch
[291/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/checks_main.cpp.o
[292/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/checkregistry.cpp.o
[293/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/fixturecatalog.cpp.o
[294/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/support/editorrig.cpp.o
[295/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/support/eventsynth.cpp.o
[296/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/support/quickframebuffer.cpp.o
[297/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/support/support.cpp.o
[298/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/support/songfixture.cpp.o
[299/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/checkcatalog.cpp.o
[300/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/porydaw_checks_autogen/mocs_compilation.cpp.o
[301/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/support/voicegroupbrowserdriver.cpp.o
In file included from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qbytearray.h:12,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstringview.h:11,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qchar.h:730,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:15,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qcoreapplication.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qapplication.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/QApplication:1,
                 from /home/runner/work/porydaw/porydaw/src/porydaw_pch.hpp:6,
                 from /home/runner/work/porydaw/porydaw/build-asan/src/checks/CMakeFiles/porydaw_checks.dir/cmake_pch.hxx:5,
                 from <command-line>:
In copy constructor ‘QArrayDataPointer<T>::QArrayDataPointer(const QArrayDataPointer<T>&) [with T = char16_t]’,
    inlined from ‘QString::QString(const QString&)’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:1391:51,
    inlined from ‘VoicegroupId::VoicegroupId(const VoicegroupId&)’ at /home/runner/work/porydaw/porydaw/src/project/projectidentity.h:39:7,
    inlined from ‘const LoadedBankView* checks::VoicegroupBrowserDriver::selectedBankView() const’ at /home/runner/work/porydaw/porydaw/src/checks/support/voicegroupbrowserdriver.cpp:226:36:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:50: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                                            ~~~~~~^~~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:33: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                           ~~~~~~^~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:19: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |             ~~~~~~^
[302/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/clipboard/clipcheck_fixture.cpp.o
[303/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/clipboard/clipcheck_copy.cpp.o
[304/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/clipboard/clipcheck_merge.cpp.o
[305/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/clipboard/clipmime_test.cpp.o
[306/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/clipboard/selectioncheck_core.cpp.o
[307/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/clipboard/selectioncheck_tracks.cpp.o
[308/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/workspace/fixture.cpp.o
[309/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/clipboard/laneselection_test.cpp.o
[310/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/workspace/tst_workspacesessions.cpp.o
[311/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/workspace/tabs_transport.cpp.o
[312/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/workspace/tabs_scale.cpp.o
[313/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/workspace/tabs_lifecycle.cpp.o
[314/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/workspace/session.cpp.o
[315/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/workspace/selftest_timeline.cpp.o
[316/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/workspace/selftest_transport.cpp.o
[317/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/workspace/tabs_persistence.cpp.o
In file included from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qbytearray.h:12,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstringview.h:11,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qchar.h:730,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:15,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qcoreapplication.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qapplication.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/QApplication:1,
                 from /home/runner/work/porydaw/porydaw/src/porydaw_pch.hpp:6,
                 from /home/runner/work/porydaw/porydaw/build-asan/src/checks/CMakeFiles/porydaw_checks.dir/cmake_pch.hxx:5,
                 from <command-line>:
In member function ‘const T* QArrayDataPointer<T>::data() const [with T = char16_t]’,
    inlined from ‘const QChar* QString::begin() const’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:1489:47,
    inlined from ‘QStringView::QStringView(const String&) [with String = QString; typename std::enable_if<std::is_same<T, QString>::value, bool>::type <anonymous> = true]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstringview.h:165:46,
    inlined from ‘bool comparesEqual(const QString&, const QString&)’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:902:28,
    inlined from ‘bool operator==(const QString&, const QString&)’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:905:5,
    inlined from ‘bool operator==(const VoicegroupId&, const VoicegroupId&)’ at /home/runner/work/porydaw/porydaw/src/project/projectidentity.h:46:17,
    inlined from ‘bool QTest::qCompare(const T1&, const T2&, const char*, const char*, const char*, int) [with T1 = VoicegroupId; T2 = VoicegroupId]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtTest/qtestcase.h:689:38,
    inlined from ‘void WorkspaceTabsTest::voicegroupRefresh()’ at /home/runner/work/porydaw/porydaw/src/checks/workspace/tabs_persistence.cpp:164:5:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:111:45: warning: potential null pointer dereference [-Wnull-dereference]
  111 |     const T *data() const noexcept { return ptr; }
      |                                             ^~~
In member function ‘constexpr qsizetype QString::size() const’,
    inlined from ‘QStringView::QStringView(const String&) [with String = QString; typename std::enable_if<std::is_same<T, QString>::value, bool>::type <anonymous> = true]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstringview.h:165:46,
    inlined from ‘bool comparesEqual(const QString&, const QString&)’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:902:28,
    inlined from ‘bool operator==(const QString&, const QString&)’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:905:5,
    inlined from ‘bool operator==(const VoicegroupId&, const VoicegroupId&)’ at /home/runner/work/porydaw/porydaw/src/project/projectidentity.h:46:17,
    inlined from ‘bool QTest::qCompare(const T1&, const T2&, const char*, const char*, const char*, int) [with T1 = VoicegroupId; T2 = VoicegroupId]’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtTest/qtestcase.h:689:38,
    inlined from ‘void WorkspaceTabsTest::voicegroupRefresh()’ at /home/runner/work/porydaw/porydaw/src/checks/workspace/tabs_persistence.cpp:164:5:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:278:18: warning: potential null pointer dereference [-Wnull-dereference]
  278 |         return d.size;
      |                  ^~~~
[318/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/pitchbend/curve.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/checks/pitchbend/tst_pitchbendediting.h:19,
                 from /home/runner/work/porydaw/porydaw/src/checks/pitchbend/curve.cpp:1:
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::standardUndoShortcutRestoresCurve()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/curve.cpp:104:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::freehandStrokePushesSingleUndoCommand()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/curve.cpp:81:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::freehandStrokePushesSingleUndoCommand()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/curve.cpp:83:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::shiftDragDrawsLinearRamp()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/curve.cpp:60:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::duplicateNoteAtSameTickDoesNotAnchorStaleNote()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/curve.cpp:232:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::duplicateNoteAtSameTickDoesNotAnchorStaleNote()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/curve.cpp:232:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::duplicateNoteAtSameTickDoesNotAnchorStaleNote()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/curve.cpp:232:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::duplicateNoteAtSameTickDoesNotAnchorStaleNote()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/curve.cpp:232:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::duplicateNoteAtSameTickDoesNotAnchorStaleNote()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/curve.cpp:232:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::duplicateNoteAtSameTickDoesNotAnchorStaleNote()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/curve.cpp:232:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::duplicateNoteAtSameTickDoesNotAnchorStaleNote()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/curve.cpp:232:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::duplicateNoteAtSameTickDoesNotAnchorStaleNote()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/curve.cpp:232:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
[319/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/pitchbend/vertex.cpp.o
[320/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/pitchbend/fixture.cpp.o
[321/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/workspace/selftest_workspace.cpp.o
[322/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/pitchbend/raster.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/checks/pitchbend/tst_pitchbendediting.h:19,
                 from /home/runner/work/porydaw/porydaw/src/checks/pitchbend/raster.cpp:1:
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendRasterTest::shiftCurvePaintsDiagonal()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/raster.cpp:86:35:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
[323/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/pitchbend/controller.cpp.o
[324/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/harness.cpp.o
[325/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck.cpp.o
[326/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/pitchbend/lifecycle.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/checks/pitchbend/tst_pitchbendediting.h:19,
                 from /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:1:
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::idleMouseMovementPreservesPopup()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:123:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::reopeningPopupRestoresActiveGraphFocus()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:272:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::keyGAnchorsPopupToSelectedNoteWithinWindowBounds()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:86:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::keyGAnchorsPopupToSelectedNoteWithinWindowBounds()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:86:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::keyGAnchorsPopupToSelectedNoteWithinWindowBounds()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:86:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::keyGAnchorsPopupToSelectedNoteWithinWindowBounds()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:86:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::keyGAnchorsPopupToSelectedNoteWithinWindowBounds()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:86:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::keyGAnchorsPopupToSelectedNoteWithinWindowBounds()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:86:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::keyGAnchorsPopupToSelectedNoteWithinWindowBounds()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:86:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::keyGAnchorsPopupToSelectedNoteWithinWindowBounds()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:86:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::externalNoteMutationDismissesPopup()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:161:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::externalNoteMutationDismissesPopup()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:161:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::externalNoteMutationDismissesPopup()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:161:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::externalNoteMutationDismissesPopup()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:161:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::externalNoteMutationDismissesPopup()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:161:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::externalNoteMutationDismissesPopup()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:161:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::externalNoteMutationDismissesPopup()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:161:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::externalNoteMutationDismissesPopup()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:161:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:183:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:183:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:183:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:183:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:183:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:183:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:183:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:213:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:213:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:213:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:213:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:213:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:213:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:213:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:239:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:239:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:239:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:239:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:239:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:239:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:239:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:213:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::rollClickDismissesPopupAndPreservesSelection()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:183:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:318:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:318:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:318:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:318:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:318:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:318:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:318:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:333:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:333:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:333:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:333:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:333:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:333:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
In member function ‘bool songview::PitchBendEditor::isOpen() const’,
    inlined from ‘void PitchBendEditingTest::insideClickRetainedOutsideClickDismisses()’ at /home/runner/work/porydaw/porydaw/src/checks/pitchbend/lifecycle.cpp:318:5:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:57:34: warning: null pointer dereference [-Wnull-dereference]
   57 |     bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
      |                                  ^~~~~~~~~~~
[327/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/identity.cpp.o
[328/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/pencil.cpp.o
[329/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/pencil_velocity.cpp.o
[330/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/remap.cpp.o
[331/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/interlock.cpp.o
[332/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/time_signature_prompt.cpp.o
[333/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/velocity_prompt.cpp.o
[334/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/selection.cpp.o
[335/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/resize.cpp.o
[336/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/note_rendering.cpp.o
/home/runner/work/porydaw/porydaw/src/checks/rollcheck/note_rendering.cpp: In lambda function:
/home/runner/work/porydaw/porydaw/src/checks/rollcheck/note_rendering.cpp:380:55: warning: declaration of ‘before’ shadows a previous local [-Wshadow]
  380 |         const auto differingPixels = [](const QImage &before, const QImage &after,
      |                                         ~~~~~~~~~~~~~~^~~~~~
/home/runner/work/porydaw/porydaw/src/checks/rollcheck/note_rendering.cpp:360:22: note: shadowed declaration is here
  360 |     const QByteArray before = doc.smf().write();
      |                      ^~~~~~
[337/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/note_commands.cpp.o
[338/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/keyboard.cpp.o
[339/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/scale_projection.cpp.o
[340/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/timemenu.cpp.o
[341/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/presentation.cpp.o
[342/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/ruler_loop_menu.cpp.o
[343/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/scale_fold.cpp.o
[344/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/scale_editing.cpp.o
[345/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/static/geometry.cpp.o
[346/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/static/fixtures.cpp.o
[347/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/static/tst_pianorollstatic.cpp.o
[348/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/static/camera.cpp.o
[349/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/rollcheck/static/gate.cpp.o
[350/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/timelinepan/timelinepanfixture.cpp.o
[351/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/timelinepan/tst_timelinepannative.cpp.o
[352/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/eventviews/eventview_fixture.cpp.o
[353/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/timelinepan/tst_timelinepan.cpp.o
[354/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/eventviews/playhead.cpp.o
[355/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/eventviews/chrome.cpp.o
[356/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/eventviews/edits.cpp.o
[357/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/nativegraphics/nativegraphics_fixture.cpp.o
[358/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/eventviews/remap.cpp.o
[359/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/nativegraphics/renderingplayhead_runner.cpp.o
[360/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/eventviews/viewbuckets_grid.cpp.o
[361/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/nativegraphics/tst_playhead_guides.cpp.o
[362/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/nativegraphics/tst_playhead_autohover.cpp.o
[363/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/nativegraphics/tst_nativewindowing.cpp.o
[364/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/nativegraphics/tst_playhead_plots.cpp.o
[365/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/nativegraphics/tst_playhead_quick.cpp.o
[366/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/editcheck/tst_songdocument_support.cpp.o
[367/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/midi/tst_midiroundtrip.cpp.o
[368/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/midi/tst_midiexport.cpp.o
[369/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/midi/tst_midismf.cpp.o
[370/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/editcheck/tst_songdocument_runner.cpp.o
[371/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/editcheck/tst_songdocument_timerange.cpp.o
[372/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/editcheck/tst_songdocument_songraw.cpp.o
[373/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/editcheck/tst_songdocument_document.cpp.o
[374/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/editcheck/tst_songdocument_metadata.cpp.o
[375/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/editcheck/tst_songdocument_songranges.cpp.o
[376/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/editcheck/tst_songdocument_songtime.cpp.o
[377/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/editcheck/tst_songdocument_songnotes.cpp.o
[378/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/editcheck/tst_songdocument_songmoves.cpp.o
[379/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/editcheck/tst_songdocument_logic.cpp.o
[380/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/editcheck/tst_songdocument_songtracks.cpp.o
[381/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/onboardcheck/support.cpp.o
[382/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/onboardcheck/action.cpp.o
[383/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/onboardcheck/registration.cpp.o
[384/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/onboardcheck/regionedlayout.cpp.o
[385/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/onboardcheck/import.cpp.o
In file included from /usr/include/c++/13/vector:66,
                 from /home/runner/work/porydaw/porydaw/src/porydaw_pch.hpp:4,
                 from /home/runner/work/porydaw/porydaw/build-asan/src/checks/CMakeFiles/porydaw_checks.dir/cmake_pch.hxx:5,
                 from <command-line>:
In constructor ‘constexpr std::_Vector_base<_Tp, _Alloc>::_Vector_impl_data::_Vector_impl_data() [with _Tp = SmfEvent; _Alloc = std::allocator<SmfEvent>]’,
    inlined from ‘constexpr std::_Vector_base<_Tp, _Alloc>::_Vector_impl::_Vector_impl() requires  is_default_constructible_v<typename __gnu_cxx::__alloc_traits<_Allocator, typename _Allocator::value_type>::rebind::other> [with _Tp = SmfEvent; _Alloc = std::allocator<SmfEvent>]’ at /usr/include/c++/13/bits/stl_vector.h:142:19,
    inlined from ‘constexpr std::_Vector_base<_Tp, _Alloc>::_Vector_base() [with _Tp = SmfEvent; _Alloc = std::allocator<SmfEvent>]’ at /usr/include/c++/13/bits/stl_vector.h:315:7,
    inlined from ‘constexpr std::vector<_Tp, _Alloc>::vector() [with _Tp = SmfEvent; _Alloc = std::allocator<SmfEvent>]’ at /usr/include/c++/13/bits/stl_vector.h:531:7,
    inlined from ‘constexpr SmfTrack::SmfTrack()’ at /home/runner/work/porydaw/porydaw/src/core/smf.h:55:8,
    inlined from ‘constexpr void std::_Construct(_Tp*, _Args&& ...) [with _Tp = SmfTrack; _Args = {}]’ at /usr/include/c++/13/bits/stl_construct.h:119:7,
    inlined from ‘static constexpr _ForwardIterator std::__uninitialized_default_n_1<_TrivialValueType>::__uninit_default_n(_ForwardIterator, _Size) [with _ForwardIterator = SmfTrack*; _Size = long unsigned int; bool _TrivialValueType = false]’ at /usr/include/c++/13/bits/stl_uninitialized.h:643:18,
    inlined from ‘constexpr _ForwardIterator std::__uninitialized_default_n(_ForwardIterator, _Size) [with _ForwardIterator = SmfTrack*; _Size = long unsigned int]’ at /usr/include/c++/13/bits/stl_uninitialized.h:712:20,
    inlined from ‘constexpr _ForwardIterator std::__uninitialized_default_n_a(_ForwardIterator, _Size, allocator<_Tp>&) [with _ForwardIterator = SmfTrack*; _Size = long unsigned int; _Tp = SmfTrack]’ at /usr/include/c++/13/bits/stl_uninitialized.h:779:44,
    inlined from ‘constexpr void std::vector<_Tp, _Alloc>::_M_default_append(size_type) [with _Tp = SmfTrack; _Alloc = std::allocator<SmfTrack>]’ at /usr/include/c++/13/bits/vector.tcc:668:41,
    inlined from ‘constexpr void std::vector<_Tp, _Alloc>::resize(size_type) [with _Tp = SmfTrack; _Alloc = std::allocator<SmfTrack>]’ at /usr/include/c++/13/bits/stl_vector.h:1016:21,
    inlined from ‘void OnboardingTest::importRescaleOverflow()’ at /home/runner/work/porydaw/porydaw/src/checks/onboardcheck/import.cpp:155:22:
/usr/include/c++/13/bits/stl_vector.h:100:36: warning: potential null pointer dereference [-Wnull-dereference]
  100 |         : _M_start(), _M_finish(), _M_end_of_storage()
      |                                    ^~~~~~~~~~~~~~~~~~~
/usr/include/c++/13/bits/stl_vector.h:100:23: warning: potential null pointer dereference [-Wnull-dereference]
  100 |         : _M_start(), _M_finish(), _M_end_of_storage()
      |                       ^~~~~~~~~~~
/usr/include/c++/13/bits/stl_vector.h:100:11: warning: potential null pointer dereference [-Wnull-dereference]
  100 |         : _M_start(), _M_finish(), _M_end_of_storage()
      |           ^~~~~~~~~~
In file included from /usr/include/c++/13/bits/stl_iterator.h:85,
                 from /usr/include/c++/13/bits/stl_algobase.h:67,
                 from /usr/include/c++/13/algorithm:60,
                 from /home/runner/work/porydaw/porydaw/src/porydaw_pch.hpp:3:
In function ‘constexpr void std::_Construct(_Tp*, _Args&& ...) [with _Tp = SmfTrack; _Args = {}]’,
    inlined from ‘static constexpr _ForwardIterator std::__uninitialized_default_n_1<_TrivialValueType>::__uninit_default_n(_ForwardIterator, _Size) [with _ForwardIterator = SmfTrack*; _Size = long unsigned int; bool _TrivialValueType = false]’ at /usr/include/c++/13/bits/stl_uninitialized.h:643:18,
    inlined from ‘constexpr _ForwardIterator std::__uninitialized_default_n(_ForwardIterator, _Size) [with _ForwardIterator = SmfTrack*; _Size = long unsigned int]’ at /usr/include/c++/13/bits/stl_uninitialized.h:712:20,
    inlined from ‘constexpr _ForwardIterator std::__uninitialized_default_n_a(_ForwardIterator, _Size, allocator<_Tp>&) [with _ForwardIterator = SmfTrack*; _Size = long unsigned int; _Tp = SmfTrack]’ at /usr/include/c++/13/bits/stl_uninitialized.h:779:44,
    inlined from ‘constexpr void std::vector<_Tp, _Alloc>::_M_default_append(size_type) [with _Tp = SmfTrack; _Alloc = std::allocator<SmfTrack>]’ at /usr/include/c++/13/bits/vector.tcc:668:41,
    inlined from ‘constexpr void std::vector<_Tp, _Alloc>::resize(size_type) [with _Tp = SmfTrack; _Alloc = std::allocator<SmfTrack>]’ at /usr/include/c++/13/bits/stl_vector.h:1016:21,
    inlined from ‘void OnboardingTest::importRescaleOverflow()’ at /home/runner/work/porydaw/porydaw/src/checks/onboardcheck/import.cpp:155:22:
/usr/include/c++/13/bits/stl_construct.h:119:7: warning: potential null pointer dereference [-Wnull-dereference]
  119 |       ::new((void*)__p) _Tp(std::forward<_Args>(__args)...);
      |       ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
In constructor ‘constexpr std::_Vector_base<_Tp, _Alloc>::_Vector_impl_data::_Vector_impl_data() [with _Tp = SmfEvent; _Alloc = std::allocator<SmfEvent>]’,
    inlined from ‘constexpr std::_Vector_base<_Tp, _Alloc>::_Vector_impl::_Vector_impl() requires  is_default_constructible_v<typename __gnu_cxx::__alloc_traits<_Allocator, typename _Allocator::value_type>::rebind::other> [with _Tp = SmfEvent; _Alloc = std::allocator<SmfEvent>]’ at /usr/include/c++/13/bits/stl_vector.h:142:19,
    inlined from ‘constexpr std::_Vector_base<_Tp, _Alloc>::_Vector_base() [with _Tp = SmfEvent; _Alloc = std::allocator<SmfEvent>]’ at /usr/include/c++/13/bits/stl_vector.h:315:7,
    inlined from ‘constexpr std::vector<_Tp, _Alloc>::vector() [with _Tp = SmfEvent; _Alloc = std::allocator<SmfEvent>]’ at /usr/include/c++/13/bits/stl_vector.h:531:7,
    inlined from ‘constexpr SmfTrack::SmfTrack()’ at /home/runner/work/porydaw/porydaw/src/core/smf.h:55:8,
    inlined from ‘constexpr void std::_Construct(_Tp*, _Args&& ...) [with _Tp = SmfTrack; _Args = {}]’ at /usr/include/c++/13/bits/stl_construct.h:119:7,
    inlined from ‘static constexpr _ForwardIterator std::__uninitialized_default_n_1<_TrivialValueType>::__uninit_default_n(_ForwardIterator, _Size) [with _ForwardIterator = SmfTrack*; _Size = long unsigned int; bool _TrivialValueType = false]’ at /usr/include/c++/13/bits/stl_uninitialized.h:643:18,
    inlined from ‘constexpr _ForwardIterator std::__uninitialized_default_n(_ForwardIterator, _Size) [with _ForwardIterator = SmfTrack*; _Size = long unsigned int]’ at /usr/include/c++/13/bits/stl_uninitialized.h:712:20,
    inlined from ‘constexpr _ForwardIterator std::__uninitialized_default_n_a(_ForwardIterator, _Size, allocator<_Tp>&) [with _ForwardIterator = SmfTrack*; _Size = long unsigned int; _Tp = SmfTrack]’ at /usr/include/c++/13/bits/stl_uninitialized.h:779:44,
    inlined from ‘constexpr void std::vector<_Tp, _Alloc>::_M_default_append(size_type) [with _Tp = SmfTrack; _Alloc = std::allocator<SmfTrack>]’ at /usr/include/c++/13/bits/vector.tcc:668:41,
    inlined from ‘constexpr void std::vector<_Tp, _Alloc>::resize(size_type) [with _Tp = SmfTrack; _Alloc = std::allocator<SmfTrack>]’ at /usr/include/c++/13/bits/stl_vector.h:1016:21,
    inlined from ‘void OnboardingTest::importWizardOverflow()’ at /home/runner/work/porydaw/porydaw/src/checks/onboardcheck/import.cpp:187:22:
/usr/include/c++/13/bits/stl_vector.h:100:36: warning: potential null pointer dereference [-Wnull-dereference]
  100 |         : _M_start(), _M_finish(), _M_end_of_storage()
      |                                    ^~~~~~~~~~~~~~~~~~~
/usr/include/c++/13/bits/stl_vector.h:100:23: warning: potential null pointer dereference [-Wnull-dereference]
  100 |         : _M_start(), _M_finish(), _M_end_of_storage()
      |                       ^~~~~~~~~~~
/usr/include/c++/13/bits/stl_vector.h:100:11: warning: potential null pointer dereference [-Wnull-dereference]
  100 |         : _M_start(), _M_finish(), _M_end_of_storage()
      |           ^~~~~~~~~~
In function ‘constexpr void std::_Construct(_Tp*, _Args&& ...) [with _Tp = SmfTrack; _Args = {}]’,
    inlined from ‘static constexpr _ForwardIterator std::__uninitialized_default_n_1<_TrivialValueType>::__uninit_default_n(_ForwardIterator, _Size) [with _ForwardIterator = SmfTrack*; _Size = long unsigned int; bool _TrivialValueType = false]’ at /usr/include/c++/13/bits/stl_uninitialized.h:643:18,
    inlined from ‘constexpr _ForwardIterator std::__uninitialized_default_n(_ForwardIterator, _Size) [with _ForwardIterator = SmfTrack*; _Size = long unsigned int]’ at /usr/include/c++/13/bits/stl_uninitialized.h:712:20,
    inlined from ‘constexpr _ForwardIterator std::__uninitialized_default_n_a(_ForwardIterator, _Size, allocator<_Tp>&) [with _ForwardIterator = SmfTrack*; _Size = long unsigned int; _Tp = SmfTrack]’ at /usr/include/c++/13/bits/stl_uninitialized.h:779:44,
    inlined from ‘constexpr void std::vector<_Tp, _Alloc>::_M_default_append(size_type) [with _Tp = SmfTrack; _Alloc = std::allocator<SmfTrack>]’ at /usr/include/c++/13/bits/vector.tcc:668:41,
    inlined from ‘constexpr void std::vector<_Tp, _Alloc>::resize(size_type) [with _Tp = SmfTrack; _Alloc = std::allocator<SmfTrack>]’ at /usr/include/c++/13/bits/stl_vector.h:1016:21,
    inlined from ‘void OnboardingTest::importWizardOverflow()’ at /home/runner/work/porydaw/porydaw/src/checks/onboardcheck/import.cpp:187:22:
/usr/include/c++/13/bits/stl_construct.h:119:7: warning: potential null pointer dereference [-Wnull-dereference]
  119 |       ::new((void*)__p) _Tp(std::forward<_Args>(__args)...);
      |       ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[386/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/onboardcheck/debuglayout.cpp.o
/home/runner/work/porydaw/porydaw/src/checks/onboardcheck/debuglayout.cpp: In lambda function:
/home/runner/work/porydaw/porydaw/src/checks/onboardcheck/debuglayout.cpp:92:43: warning: declaration of ‘constant’ shadows a previous local [-Wshadow]
   92 |         const auto named = [](const char *constant, int comma, int paren, int slash) {
      |                               ~~~~~~~~~~~~^~~~~~~~
/home/runner/work/porydaw/porydaw/src/checks/onboardcheck/debuglayout.cpp:44:19: note: shadowed declaration is here
   44 |     const QString constant = SongRegistry::constantForLabel(label);
      |                   ^~~~~~~~
[387/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroup/voicegrouptestfixture.cpp.o
[388/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroup/voicegroupsourceediting.cpp.o
[389/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/onboardcheck/deletion.cpp.o
[390/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroup/voicegroupsourcecatalog.cpp.o
[391/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroup/voicegrouploadfixture.cpp.o
[392/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroup/tst_voicegroupbank.cpp.o
[393/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroup/tst_voicegrouploader.cpp.o
[394/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroupsave/fixture.cpp.o
[395/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroupsave/switching.cpp.o
[396/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroupsave/savecore.cpp.o
[397/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroupsave/editor.cpp.o
[398/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroup/tst_voicegroupviewcache.cpp.o
[399/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroupsave/synth.cpp.o
[400/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroupsave/picker.cpp.o
[401/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/transportfixture.cpp.o
[402/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/tst_transport.cpp.o
[403/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/cgb.cpp.o
[404/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/publish.cpp.o
[405/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/tails.cpp.o
[406/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/voicegroupsave/presentation.cpp.o
In file included from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qbytearray.h:12,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstringview.h:11,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qchar.h:730,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:15,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qcoreapplication.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qapplication.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/QApplication:1,
                 from /home/runner/work/porydaw/porydaw/src/porydaw_pch.hpp:6,
                 from /home/runner/work/porydaw/porydaw/build-asan/src/checks/CMakeFiles/porydaw_checks.dir/cmake_pch.hxx:5,
                 from <command-line>:
In copy constructor ‘QArrayDataPointer<T>::QArrayDataPointer(const QArrayDataPointer<T>&) [with T = char16_t]’,
    inlined from ‘QString::QString(const QString&)’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:1391:51,
    inlined from ‘VoicegroupId::VoicegroupId(const VoicegroupId&)’ at /home/runner/work/porydaw/porydaw/src/project/projectidentity.h:39:7,
    inlined from ‘void checks::VoicegroupSaveTest::typeColumnMapsEveryFamily()’ at /home/runner/work/porydaw/porydaw/src/checks/voicegroupsave/presentation.cpp:379:60:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:50: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                                            ~~~~~~^~~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:33: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                           ~~~~~~^~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:19: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |             ~~~~~~^
[407/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/settle.cpp.o
[408/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/tst_prime.cpp.o
[409/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/tst_xcmd.cpp.o
[410/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/tst_loop.cpp.o
[411/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/projection.cpp.o
[412/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/opaque.cpp.o
[413/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/rewrites.cpp.o
[414/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/export.cpp.o
[415/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/audio/resonancefixture.cpp.o
[416/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/audio/clickrig.cpp.o
[417/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/playback/rawreconciliation.cpp.o
[418/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/audio/tst_audiotelemetry.cpp.o
[419/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/audio/tst_audiobackend.cpp.o
[420/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/audio/tst_resonancelaw.cpp.o
[421/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/audio/tst_clicktransport.cpp.o
[422/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/audio/tst_resonancetiming.cpp.o
[423/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/audio/tst_trackactivity.cpp.o
[424/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/trackheaders/tst_trackheaders.cpp.o
[425/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/trackheaders/tst_trackheadermodel.cpp.o
[426/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/trackheaders/trackheaderinput.cpp.o
[427/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/trackheaders/trackheaderfixture.cpp.o
/home/runner/work/porydaw/porydaw/src/checks/trackheaders/trackheaderfixture.cpp: In member function ‘bool TrackHeadersFixture::focusInput(QString&)’:
/home/runner/work/porydaw/porydaw/src/checks/trackheaders/trackheaderfixture.cpp:202:26: warning: potential null pointer dereference [-Wnull-dereference]
  202 |     m_input->requestFocus(Qt::OtherFocusReason);
      |     ~~~~~~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/checks/trackheaders/trackheaderfixture.cpp:202:26: warning: potential null pointer dereference [-Wnull-dereference]
[428/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/trackheaders/trackheaderraster.cpp.o
[429/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/trackheaders/tst_trackactivitymeter.cpp.o
[430/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/trackheaders/trackheadermenu.cpp.o
[431/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/scrollbar/control.cpp.o
[432/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/trackheaders/trackheadermutations.cpp.o
[433/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/scrollbar/tst_scrollbar.cpp.o
[434/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/scrollbar/input.cpp.o
[435/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/scrollbar/geometry.cpp.o
[436/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/samplecheck/fixtures.cpp.o
[437/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/samplecheck.cpp.o
[438/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/scrollbar/drag.cpp.o
[439/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/samplecheck/project.cpp.o
[440/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/samplecheck/dsp.cpp.o
[441/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/samplecheck/decoder.cpp.o
[442/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/samplecheck/editor.cpp.o
[443/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/samplecheck/analysis.cpp.o
[444/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/samplecheck/soundfont.cpp.o
[445/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/samplecheck/integration.cpp.o
[446/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/project/identity.cpp.o
[447/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/project/iofixture.cpp.o
[448/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/project/ioflow.cpp.o
[449/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/project/save.cpp.o
[450/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/project/iomutations.cpp.o
[451/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/project/mk.cpp.o
[452/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/project/ignore.cpp.o
[453/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/project/workspace.cpp.o
[454/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/host/tst_hostseams.cpp.o
[455/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/host/tst_rulergridmenu.cpp.o
[456/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/host/tst_hostadapter.cpp.o
[457/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/host/tst_hostintegration.cpp.o
[458/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/mainwindowrouting/tst_mainwindowrouting_input.cpp.o
[459/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/keyboard/keymapregistry.cpp.o
[460/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/mainwindowrouting/tst_mainwindowrouting_native.cpp.o
[461/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp.o
In file included from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qbytearray.h:12,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstringview.h:11,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qchar.h:730,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:15,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qcoreapplication.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/qapplication.h:9,
                 from /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtWidgets/QApplication:1,
                 from /home/runner/work/porydaw/porydaw/src/porydaw_pch.hpp:6,
                 from /home/runner/work/porydaw/porydaw/build-asan/src/checks/CMakeFiles/porydaw_checks.dir/cmake_pch.hxx:5,
                 from <command-line>:
In copy constructor ‘QArrayDataPointer<T>::QArrayDataPointer(const QArrayDataPointer<T>&) [with T = char16_t]’,
    inlined from ‘QString::QString(const QString&)’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:1391:51,
    inlined from ‘VoicegroupId::VoicegroupId(const VoicegroupId&)’ at /home/runner/work/porydaw/porydaw/src/project/projectidentity.h:39:7,
    inlined from ‘void checks::mainwindowrouting::MainWindowRoutingLifecycleTest::freshBind()’ at /home/runner/work/porydaw/porydaw/src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp:170:29:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:50: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                                            ~~~~~~^~~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:33: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                           ~~~~~~^~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:19: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |             ~~~~~~^
In copy constructor ‘QArrayDataPointer<T>::QArrayDataPointer(const QArrayDataPointer<T>&) [with T = char16_t]’,
    inlined from ‘QString::QString(const QString&)’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:1391:51,
    inlined from ‘VoicegroupId::VoicegroupId(const VoicegroupId&)’ at /home/runner/work/porydaw/porydaw/src/project/projectidentity.h:39:7,
    inlined from ‘void checks::mainwindowrouting::MainWindowRoutingLifecycleTest::freshBind()’ at /home/runner/work/porydaw/porydaw/src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp:177:35:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:50: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                                            ~~~~~~^~~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:33: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                           ~~~~~~^~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:19: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |             ~~~~~~^
In copy constructor ‘QArrayDataPointer<T>::QArrayDataPointer(const QArrayDataPointer<T>&) [with T = char16_t]’,
    inlined from ‘QString::QString(const QString&)’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:1391:51,
    inlined from ‘VoicegroupId::VoicegroupId(const VoicegroupId&)’ at /home/runner/work/porydaw/porydaw/src/project/projectidentity.h:39:7,
    inlined from ‘void checks::mainwindowrouting::MainWindowRoutingLifecycleTest::stagedReload()’ at /home/runner/work/porydaw/porydaw/src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp:200:65:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:50: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                                            ~~~~~~^~~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:33: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                           ~~~~~~^~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:19: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |             ~~~~~~^
In copy constructor ‘QArrayDataPointer<T>::QArrayDataPointer(const QArrayDataPointer<T>&) [with T = char16_t]’,
    inlined from ‘QString::QString(const QString&)’ at /home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qstring.h:1391:51,
    inlined from ‘VoicegroupId::VoicegroupId(const VoicegroupId&)’ at /home/runner/work/porydaw/porydaw/src/project/projectidentity.h:39:7,
    inlined from ‘void checks::mainwindowrouting::MainWindowRoutingLifecycleTest::bankRebind()’ at /home/runner/work/porydaw/porydaw/src/checks/mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp:256:65:
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:50: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                                            ~~~~~~^~~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:33: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |                           ~~~~~~^~~
/home/runner/work/porydaw/Qt/6.11.2/gcc_64/include/QtCore/qarraydatapointer.h:39:19: warning: potential null pointer dereference [-Wnull-dereference]
   39 |         : d(other.d), ptr(other.ptr), size(other.size)
      |             ~~~~~~^
[462/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/keyboard/tst_velocitymodel.cpp.o
[463/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/mainwindowrouting/tst_mainwindowrouting_state.cpp.o
[464/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/keyboard/tst_settingsdialog.cpp.o
[465/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/polyphony/polyphonyengine.cpp.o
[466/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/polyphony/polyphonygate.cpp.o
[467/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/polyphony/polyphonypanel.cpp.o
[468/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/core.cpp.o
[469/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/automationprobe.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/checks/selectionkey/automationprobe.cpp:7:
In member function ‘AutomationCanvas* AutomationPage::canvas()’,
    inlined from ‘static std::optional<selectionkey::AutomationProbe> selectionkey::AutomationProbe::locate(SongView&, songview::TimelineInputItem*, int, uint8_t, QString*)’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/automationprobe.cpp:73:58:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
   38 |     AutomationCanvas *canvas() noexcept { return m_canvas; }
      |                                                  ^~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationpage.h:38:50: warning: potential null pointer dereference [-Wnull-dereference]
[470/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/corefixture.cpp.o
/home/runner/work/porydaw/porydaw/src/checks/selectionkey/corefixture.cpp: In lambda function:
/home/runner/work/porydaw/porydaw/src/checks/selectionkey/corefixture.cpp:265:89: warning: declaration of ‘reserved’ shadows a previous local [-Wshadow]
  265 |         const bool reserved = std::any_of(reservedX.begin(), reservedX.end(), [x](qreal reserved) {
      |                                                                                   ~~~~~~^~~~~~~~
/home/runner/work/porydaw/porydaw/src/checks/selectionkey/corefixture.cpp:265:20: note: shadowed declaration is here
  265 |         const bool reserved = std::any_of(reservedX.begin(), reservedX.end(), [x](qreal reserved) {
      |                    ^~~~~~~~
[471/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/gesture.cpp.o
[472/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/corearrows.cpp.o
[473/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/coreediting.cpp.o
[474/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/gesturevelocity.cpp.o
[475/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/gesturecommands.cpp.o
[476/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/gesturethumbs.cpp.o
[477/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/window.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/checks/selectionkey/session.h:18,
                 from /home/runner/work/porydaw/porydaw/src/checks/selectionkey/tst_windowtier.h:43,
                 from /home/runner/work/porydaw/porydaw/src/checks/selectionkey/window.cpp:9:
In member function ‘SongView& SongTab::view()’,
    inlined from ‘SongView& SelectionWindowTierTest::view() const’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/window.cpp:29:23:
/home/runner/work/porydaw/porydaw/src/ui/songtab.h:61:32: warning: potential null pointer dereference [-Wnull-dereference]
   61 |     SongView &view() { return *m_view; }
      |                                ^~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songtab.h:61:32: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool SongTab::isReady() const’,
    inlined from ‘selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/session.h:124:68,
    inlined from ‘checks::async_wait::waitUntil<selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()>, selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()> >(selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()>, selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()>, int, int)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/checks/support/asyncwait.h:26:25:
/home/runner/work/porydaw/porydaw/src/ui/songtab.h:69:35: warning: potential null pointer dereference [-Wnull-dereference]
   69 |     bool isReady() const { return m_midiBound && m_voicegroupBound; }
      |                                   ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songtab.h:69:35: warning: potential null pointer dereference [-Wnull-dereference]
[478/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/windowtier_keyboard.cpp.o
[479/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/windowtier_lifetime.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/checks/selectionkey/session.h:18,
                 from /home/runner/work/porydaw/porydaw/src/checks/selectionkey/tst_windowtier.h:43,
                 from /home/runner/work/porydaw/porydaw/src/checks/selectionkey/windowtier_lifetime.cpp:10:
In member function ‘bool SongTab::isReady() const’,
    inlined from ‘selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/session.h:124:68,
    inlined from ‘checks::async_wait::waitUntil<selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()>, selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()> >(selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()>, selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()>, int, int)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/checks/support/asyncwait.h:26:25:
/home/runner/work/porydaw/porydaw/src/ui/songtab.h:69:35: warning: potential null pointer dereference [-Wnull-dereference]
   69 |     bool isReady() const { return m_midiBound && m_voicegroupBound; }
      |                                   ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songtab.h:69:35: warning: potential null pointer dereference [-Wnull-dereference]
[480/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/windowtier_gestures.cpp.o
[481/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/localinput.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/checks/selectionkey/session.h:18,
                 from /home/runner/work/porydaw/porydaw/src/checks/selectionkey/tst_localinputtier.h:37,
                 from /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinput.cpp:9:
In member function ‘SongView& SongTab::view()’,
    inlined from ‘SongView& SelectionLocalInputTierTest::view() const’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinput.cpp:29:23:
/home/runner/work/porydaw/porydaw/src/ui/songtab.h:61:32: warning: potential null pointer dereference [-Wnull-dereference]
   61 |     SongView &view() { return *m_view; }
      |                                ^~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songtab.h:61:32: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool SongTab::isReady() const’,
    inlined from ‘selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/session.h:124:68,
    inlined from ‘checks::async_wait::waitUntil<selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()>, selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()> >(selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()>, selectionkey::waitForTabReady(const WorkspaceUi&, const SongTab*)::<lambda()>, int, int)::<lambda()>’ at /home/runner/work/porydaw/porydaw/src/checks/support/asyncwait.h:26:25:
/home/runner/work/porydaw/porydaw/src/ui/songtab.h:69:35: warning: potential null pointer dereference [-Wnull-dereference]
   69 |     bool isReady() const { return m_midiBound && m_voicegroupBound; }
      |                                   ^~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/songtab.h:69:35: warning: potential null pointer dereference [-Wnull-dereference]
[482/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/localinputtier_eventlist.cpp.o
[483/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/automation/raster/painting.cpp.o
[484/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/localinputtier_text.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/checks/support/timelinequickcheck.h:3,
                 from /home/runner/work/porydaw/porydaw/src/checks/quickpopupguard.h:13,
                 from /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinputtier_text.cpp:12:
In member function ‘bool AutomationCanvas::pencilMode() const’,
    inlined from ‘void SelectionLocalInputTierTest::renameTextInputOwnsKeys()’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinputtier_text.cpp:184:49:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationcanvas.h:149:47: warning: potential null pointer dereference [-Wnull-dereference]
  149 |     bool pencilMode() const noexcept { return m_pencilMode; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationcanvas.h:149:47: warning: potential null pointer dereference [-Wnull-dereference]
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationcanvas.h:149:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool AutomationCanvas::pencilMode() const’,
    inlined from ‘void SelectionLocalInputTierTest::renameTextInputOwnsKeys()’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinputtier_text.cpp:191:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationcanvas.h:149:47: warning: potential null pointer dereference [-Wnull-dereference]
  149 |     bool pencilMode() const noexcept { return m_pencilMode; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationcanvas.h:149:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool AutomationCanvas::pencilMode() const’,
    inlined from ‘void SelectionLocalInputTierTest::renameTextInputOwnsKeys()’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinputtier_text.cpp:199:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationcanvas.h:149:47: warning: potential null pointer dereference [-Wnull-dereference]
  149 |     bool pencilMode() const noexcept { return m_pencilMode; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/automationcanvas.h:149:47: warning: potential null pointer dereference [-Wnull-dereference]
[485/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/selectionkey/localinputtier_pitchbend.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinputtier_pitchbend.cpp:13:
In member function ‘uint64_t songview::PitchBendEditor::endTick() const’,
    inlined from ‘SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinputtier_pitchbend.cpp:304:79,
    inlined from ‘constexpr bool __gnu_cxx::__ops::_Iter_pred<_Predicate>::operator()(_Iterator) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, std::vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/predefined_ops.h:318:23,
    inlined from ‘constexpr _RandomAccessIterator std::__find_if(_RandomAccessIterator, _RandomAccessIterator, _Predicate, random_access_iterator_tag) [with _RandomAccessIterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2072:14,
    inlined from ‘constexpr _Iterator std::__find_if(_Iterator, _Iterator, _Predicate) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2117:23,
    inlined from ‘constexpr _IIter std::find_if(_IIter, _IIter, _Predicate) [with _IIter = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/stl_algo.h:3923:28:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
   59 |     uint64_t endTick() const { return m_endTick; }
      |                                       ^~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘uint64_t songview::PitchBendEditor::endTick() const’,
    inlined from ‘SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinputtier_pitchbend.cpp:304:79,
    inlined from ‘constexpr bool __gnu_cxx::__ops::_Iter_pred<_Predicate>::operator()(_Iterator) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, std::vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/predefined_ops.h:318:23,
    inlined from ‘constexpr _RandomAccessIterator std::__find_if(_RandomAccessIterator, _RandomAccessIterator, _Predicate, random_access_iterator_tag) [with _RandomAccessIterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2076:14,
    inlined from ‘constexpr _Iterator std::__find_if(_Iterator, _Iterator, _Predicate) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2117:23,
    inlined from ‘constexpr _IIter std::find_if(_IIter, _IIter, _Predicate) [with _IIter = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/stl_algo.h:3923:28:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
   59 |     uint64_t endTick() const { return m_endTick; }
      |                                       ^~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘uint64_t songview::PitchBendEditor::endTick() const’,
    inlined from ‘SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinputtier_pitchbend.cpp:304:79,
    inlined from ‘constexpr bool __gnu_cxx::__ops::_Iter_pred<_Predicate>::operator()(_Iterator) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, std::vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/predefined_ops.h:318:23,
    inlined from ‘constexpr _RandomAccessIterator std::__find_if(_RandomAccessIterator, _RandomAccessIterator, _Predicate, random_access_iterator_tag) [with _RandomAccessIterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2080:14,
    inlined from ‘constexpr _Iterator std::__find_if(_Iterator, _Iterator, _Predicate) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2117:23,
    inlined from ‘constexpr _IIter std::find_if(_IIter, _IIter, _Predicate) [with _IIter = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/stl_algo.h:3923:28:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
   59 |     uint64_t endTick() const { return m_endTick; }
      |                                       ^~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘uint64_t songview::PitchBendEditor::endTick() const’,
    inlined from ‘SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinputtier_pitchbend.cpp:304:79,
    inlined from ‘constexpr bool __gnu_cxx::__ops::_Iter_pred<_Predicate>::operator()(_Iterator) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, std::vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/predefined_ops.h:318:23,
    inlined from ‘constexpr _RandomAccessIterator std::__find_if(_RandomAccessIterator, _RandomAccessIterator, _Predicate, random_access_iterator_tag) [with _RandomAccessIterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2084:14,
    inlined from ‘constexpr _Iterator std::__find_if(_Iterator, _Iterator, _Predicate) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2117:23,
    inlined from ‘constexpr _IIter std::find_if(_IIter, _IIter, _Predicate) [with _IIter = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/stl_algo.h:3923:28:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
   59 |     uint64_t endTick() const { return m_endTick; }
      |                                       ^~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘uint64_t songview::PitchBendEditor::endTick() const’,
    inlined from ‘SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinputtier_pitchbend.cpp:304:79,
    inlined from ‘constexpr bool __gnu_cxx::__ops::_Iter_pred<_Predicate>::operator()(_Iterator) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, std::vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/predefined_ops.h:318:23,
    inlined from ‘constexpr _RandomAccessIterator std::__find_if(_RandomAccessIterator, _RandomAccessIterator, _Predicate, random_access_iterator_tag) [with _RandomAccessIterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2092:14,
    inlined from ‘constexpr _Iterator std::__find_if(_Iterator, _Iterator, _Predicate) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2117:23,
    inlined from ‘constexpr _IIter std::find_if(_IIter, _IIter, _Predicate) [with _IIter = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/stl_algo.h:3923:28:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
   59 |     uint64_t endTick() const { return m_endTick; }
      |                                       ^~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘uint64_t songview::PitchBendEditor::endTick() const’,
    inlined from ‘SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinputtier_pitchbend.cpp:304:79,
    inlined from ‘constexpr bool __gnu_cxx::__ops::_Iter_pred<_Predicate>::operator()(_Iterator) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, std::vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/predefined_ops.h:318:23,
    inlined from ‘constexpr _RandomAccessIterator std::__find_if(_RandomAccessIterator, _RandomAccessIterator, _Predicate, random_access_iterator_tag) [with _RandomAccessIterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2097:14,
    inlined from ‘constexpr _Iterator std::__find_if(_Iterator, _Iterator, _Predicate) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2117:23,
    inlined from ‘constexpr _IIter std::find_if(_IIter, _IIter, _Predicate) [with _IIter = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/stl_algo.h:3923:28:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
   59 |     uint64_t endTick() const { return m_endTick; }
      |                                       ^~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘uint64_t songview::PitchBendEditor::endTick() const’,
    inlined from ‘SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>’ at /home/runner/work/porydaw/porydaw/src/checks/selectionkey/localinputtier_pitchbend.cpp:304:79,
    inlined from ‘constexpr bool __gnu_cxx::__ops::_Iter_pred<_Predicate>::operator()(_Iterator) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, std::vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/predefined_ops.h:318:23,
    inlined from ‘constexpr _RandomAccessIterator std::__find_if(_RandomAccessIterator, _RandomAccessIterator, _Predicate, random_access_iterator_tag) [with _RandomAccessIterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2102:14,
    inlined from ‘constexpr _Iterator std::__find_if(_Iterator, _Iterator, _Predicate) [with _Iterator = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = __gnu_cxx::__ops::_Iter_pred<SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)> >]’ at /usr/include/c++/13/bits/stl_algobase.h:2117:23,
    inlined from ‘constexpr _IIter std::find_if(_IIter, _IIter, _Predicate) [with _IIter = __gnu_cxx::__normal_iterator<const DocLanePoint*, vector<DocLanePoint> >; _Predicate = SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys()::<lambda(const DocLanePoint&)>]’ at /usr/include/c++/13/bits/stl_algo.h:3923:28:
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
   59 |     uint64_t endTick() const { return m_endTick; }
      |                                       ^~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/pitchbendeditor.hpp:59:39: warning: potential null pointer dereference [-Wnull-dereference]
[486/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/automation/raster/rasterfixture.cpp.o
[487/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/automation/raster/interaction.cpp.o
[488/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/drawerpresentation/fixtures.cpp.o
[489/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/drawerpresentation/drawer.cpp.o
[490/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/drawerpresentation/valueprompt.cpp.o
/home/runner/work/porydaw/porydaw/src/checks/drawerpresentation/valueprompt.cpp: In function ‘int {anonymous}::tempoBpmAt(const SongDocument&, Tick)’:
/home/runner/work/porydaw/porydaw/src/checks/drawerpresentation/valueprompt.cpp:97:62: warning: potential null pointer dereference [-Wnull-dereference]
   97 |     return int(std::lround(CoreTimeDefaults::tempoBpm(point->microsecondsPerQuarterNote)));
      |                                                       ~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~
[491/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/drawerpresentation/voicemenus.cpp.o
[492/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/drawerpresentation/velocity.cpp.o
[493/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/velocity/velocityselection.cpp.o
[494/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/velocity/tst_velocityediting.cpp.o
/home/runner/work/porydaw/porydaw/src/checks/velocity/tst_velocityediting.cpp: In member function ‘QPointF VelocityEditingTest::nodePoint(uint8_t, uint64_t) const’:
/home/runner/work/porydaw/porydaw/src/checks/velocity/tst_velocityediting.cpp:383:56: warning: potential null pointer dereference [-Wnull-dereference]
  383 |     const qreal dpr = m_velocityInput->devicePixelRatio();
      |                       ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^~
/home/runner/work/porydaw/porydaw/src/checks/velocity/tst_velocityediting.cpp:383:56: warning: potential null pointer dereference [-Wnull-dereference]
[495/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/velocity/velocitypainting.cpp.o
[496/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/velocity/velocityhitpriority.cpp.o
[497/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/velocity/velocityclicks.cpp.o
[498/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/velocity/velocitydetentpainting.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/checks/velocity/tst_velocityediting.h:18,
                 from /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:1:
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lockedPaintUsesDetents()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:129:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lockedPaintUsesDetents()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:129:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lockedPaintUsesDetents()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:129:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lockedPaintUsesDetents()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:129:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lockedPaintUsesDetents()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:129:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lockedPaintUsesDetents()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:129:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lockedPaintUsesDetents()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:129:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lockedPaintUsesDetents()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:129:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedPaintKeepsRawVelocities()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:221:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedPaintKeepsRawVelocities()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:221:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedPaintKeepsRawVelocities()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:221:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedPaintKeepsRawVelocities()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:221:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedPaintKeepsRawVelocities()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:221:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedPaintKeepsRawVelocities()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:221:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedPaintKeepsRawVelocities()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:221:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedPaintKeepsRawVelocities()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentpainting.cpp:221:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
[499/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/velocity/velocityroll.cpp.o
[500/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/drawerpresentation/voice.cpp.o
[501/536] Building CXX object src/checks/CMakeFiles/porydaw_checks.dir/velocity/velocitydetentdragging.cpp.o
In file included from /home/runner/work/porydaw/porydaw/src/checks/velocity/tst_velocityediting.h:18,
                 from /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:1:
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lateUnlockKeepsGestureSnapped()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:43:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lateUnlockKeepsGestureSnapped()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:43:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lateUnlockKeepsGestureSnapped()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:43:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lateUnlockKeepsGestureSnapped()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:43:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lateUnlockKeepsGestureSnapped()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:43:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lateUnlockKeepsGestureSnapped()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:43:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::lateUnlockKeepsGestureSnapped()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:43:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedRelativeKeepsOffsets()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:141:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedRelativeKeepsOffsets()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:141:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedRelativeKeepsOffsets()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:141:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedRelativeKeepsOffsets()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:141:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedRelativeKeepsOffsets()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:141:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedRelativeKeepsOffsets()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:141:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
   55 |     bool useDetents() const noexcept { return m_useDetents; }
      |                                               ^~~~~~~~~~~~
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: potential null pointer dereference [-Wnull-dereference]
In member function ‘bool VelocityArea::useDetents() const’,
    inlined from ‘void VelocityEditingTest::unlockedRelativeKeepsOffsets()’ at /home/runner/work/porydaw/porydaw/src/checks/velocity/velocitydetentdragging.cpp:141:5:
/home/runner/work/porydaw/porydaw/src/ui/editordrawer/velocityarea/velocityarea.h:55:47: warning: null pointer dereference [-Wnull-dereference]
3m 14s
Run QT_QUICK_BACKEND=software deno run --allow-read --allow-write --allow-run --allow-env=ASAN_OPTIONS,DISPLAY,LLVM_PROFILE_FILE,PORYDAW_SAMPLE_CORPUS tools/run_checks.ts build-asan/porydaw_checks --no-windowing-checks --pool=1 --exclude=vgsavecheck --exclude=tabcheck --exclude=onboardcheck --exclude=sessioncheck --exclude=editor-drawer
not ok: timelinepancheck (1.39s)
exit code: 1
********* Start testing of TimelinePanTest *********
Config: Using QtTest library 6.11.2, Qt 6.11.2 (x86_64-little_endian-lp64 shared (dynamic) release build; by GCC 11.5.0 20240719 (Red Hat 11.5.0-5)), ubuntu 24.04
PASS   : TimelinePanTest::initTestCase()
PASS   : TimelinePanTest::dashPhasePreservesClip(start--1000.25-across--1)
PASS   : TimelinePanTest::dashPhasePreservesClip(start--1000.25-across-0.25)
PASS   : TimelinePanTest::dashPhasePreservesClip(start--1000.25-across-30)
PASS   : TimelinePanTest::dashPhasePreservesClip(start--1000.25-across-59.75)
PASS   : TimelinePanTest::dashPhasePreservesClip(start--1000.25-across-100.25)
PASS   : TimelinePanTest::dashPhasePreservesClip(start--7.5-across--1)
PASS   : TimelinePanTest::dashPhasePreservesClip(start--7.5-across-0.25)
PASS   : TimelinePanTest::dashPhasePreservesClip(start--7.5-across-30)
PASS   : TimelinePanTest::dashPhasePreservesClip(start--7.5-across-59.75)
PASS   : TimelinePanTest::dashPhasePreservesClip(start--7.5-across-100.25)
PASS   : TimelinePanTest::dashPhasePreservesClip(start-0-across--1)
PASS   : TimelinePanTest::dashPhasePreservesClip(start-0-across-0.25)
PASS   : TimelinePanTest::dashPhasePreservesClip(start-0-across-30)
PASS   : TimelinePanTest::dashPhasePreservesClip(start-0-across-59.75)
PASS   : TimelinePanTest::dashPhasePreservesClip(start-0-across-100.25)
PASS   : TimelinePanTest::dashPhasePreservesClip(start-17.25-across--1)
PASS   : TimelinePanTest::dashPhasePreservesClip(start-17.25-across-0.25)
PASS   : TimelinePanTest::dashPhasePreservesClip(start-17.25-across-30)
PASS   : TimelinePanTest::dashPhasePreservesClip(start-17.25-across-59.75)
PASS   : TimelinePanTest::dashPhasePreservesClip(start-17.25-across-100.25)
PASS   : TimelinePanTest::wheelPansCamera(legacy-pixel-left-8)
PASS   : TimelinePanTest::wheelPansCamera(safe-zero-delta)
PASS   : TimelinePanTest::gutterLabelsSurvivePan()
PASS   : TimelinePanTest::geometryCountsSurviveReuse()
PASS   : TimelinePanTest::fullRefreshWinsOverPan(full-then-pan)
PASS   : TimelinePanTest::fullRefreshWinsOverPan(pan-then-full)
FAIL!  : TimelinePanTest::drumGutterLabelsAndHover() Compared values are not the same
   Actual   (model->data(namedIndex, TimelineQuickTextModel::ColorRole).value<QColor>()): #ff1a1a1a
   Expected (themes::color(themes::Role::song_view_piano_keyboard_natural_key))         : #fff4f4f4
   Loc: [/home/runner/work/porydaw/porydaw/src/checks/timelinepan/tst_timelinepan.cpp(552)]
PASS   : TimelinePanTest::drumGutterTrackSwitch()
PASS   : TimelinePanTest::drumClassificationIgnoresProgramChanges()
PASS   : TimelinePanTest::hoverChipOverlayUnclipped()
PASS   : TimelinePanTest::cleanupTestCase()
Totals: 31 passed, 1 failed, 0 skipped, 0 blacklisted, 1289ms
********* Finished testing of TimelinePanTest *********

verify: 76/91 ok, 1 failed (193.85s, 14 skipped)
run_checks: FAIL (1) timelinepancheck