#include "checks/drawerpresentation/tst_drawerpresentation.h"

#include <QtTest>

#include <algorithm>
#include <array>
#include <cmath>
#include <utility>

#include "checks/drawerpresentation/fixtures.h"
#include "checks/support/editorrig.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "checks/support/timelinequickcheck.h"
#include "core/velocitymodel.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/velocityaxis.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"

using namespace checks::drawerpresentation;

namespace {

void createVelocityFixture(VelocityFixture &fixture)
{
    QString error;
    if (!fixture.create(error))
        qFatal("%s", qPrintable(error));
}

void createVelocityFixture(VelocityTransactionFixture &fixture)
{
    QString error;
    if (!fixture.create(error))
        qFatal("%s", qPrintable(error));
}

ToneData tone(int type)
{
    ToneData result{};
    result.type = type;
    return result;
}

void setVoice(VelocityFixture &fixture, const ToneData &voice)
{
    fixture.voicegroup.voices[0] = voice;
    fixture.rig->view().setVoicegroup(&fixture.voicegroup);
    fixture.area->songChanged();
    fixture.refresh();
}

QPointF nodePoint(const VelocityFixture &fixture, const DocNote &note, int velocity = -1)
{
    const int value = velocity < 0 ? note.velocity : velocity;
    return {fixture.xForTick(double(note.tick)), fixture.area->axis().velocityToY(value)};
}

bool samePixels(const QImage &left, const QImage &right)
{
    if (left.size() != right.size())
        return false;
    for (int y = 0; y < left.height(); ++y)
        for (int x = 0; x < left.width(); ++x)
            if (left.pixel(x, y) != right.pixel(x, y))
                return false;
    return true;
}

} // namespace

VelocityPageTest::VelocityPageTest(QString scratchProject, QString songLabel)
    : m_scratchProject(std::move(scratchProject))
    , m_songLabel(std::move(songLabel))
{}

void VelocityPageTest::fixtureRoute101AndInputGeometry()
{
    QString error;
    auto project = checks::ProjectFixture::copyOf(m_scratchProject, error);
    QVERIFY2(project, qPrintable(error));
    auto song = checks::LoadedSong::load(project->root(), m_songLabel, error);
    QVERIFY2(song, qPrintable(error));
    auto timeline = song->document().buildTimeline(48000.0);
    QVERIFY(timeline);
    LoadedVoiceGroup voices{};
    for (ToneData &voice : voices.voices)
        voice.type = VOICE_DIRECTSOUND;
    SongView view;
    view.resize(960, 480);
    view.setDocument(&song->document());
    view.setSong(timeline.get(), &voices);
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.show();
    pump();
    auto *drawer = view.editorDrawer();
    auto *quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *root = quick ? quick->rootObject() : nullptr;
    auto *input = root ? root->findChild<songview::TimelineInputItem *>(
                             QStringLiteral("timelineVelocityInput"))
                       : nullptr;
    auto *gutter = root ? root->findChild<songview::TimelineInputItem *>(
                              QStringLiteral("timelineVelocityGutterInput"))
                        : nullptr;
    QVERIFY(drawer);
    QVERIFY(input);
    QVERIFY(gutter);
    const auto &geometry = view.timelineBandLayout().geometry(songview::TimelineBand::Velocity);
    QVERIFY(geometry);
    QCOMPARE(input->bounds(), QRectF(QPointF{}, geometry->plotRect.size()));
    QCOMPARE(gutter->bounds(), QRectF(QPointF{}, QSizeF(geometry->plotRect.x() - geometry->rect.x(),
                                                        geometry->rect.height())));
    const auto notes = song->document().notesForTrack(0);
    QVERIFY(!notes.empty());
    view.selectionModel().setNoteSelection({notes.front().noteId});
    drawer->velocityArea()->songChanged();
    const QPointF anchor = input->bounds().center();
    const double tick = view.camera().tickAtContentX(anchor.x());
    const double zoom = view.camera().pxPerBeat();
    checks::events::sendWheel(*input, anchor, {}, QPoint(0, 120), Qt::NoButton, Qt::NoModifier,
                              Qt::NoScrollPhase, false);
    pump();
    QVERIFY(view.camera().pxPerBeat() > zoom);
    QVERIFY(std::abs(view.camera().displayX(tick, 0.0, input->devicePixelRatio()) - anchor.x()) <=
            1.0 / input->devicePixelRatio());
    QCOMPARE(drawer->velocityArea()->axis().mode(), VelocityAxis::Mode::Continuous);
    QCOMPARE(drawer->velocityArea()->axis().markerCount(), size_t(1));
    QCOMPARE(drawer->velocityArea()->axis().markers()[0].velocity, notes.front().velocity);
    QVERIFY(std::abs(drawer->velocityArea()->axis().markers()[0].y -
                     drawer->velocityArea()->axis().velocityToY(notes.front().velocity)) <=
            1.0 / input->devicePixelRatio());
    view.hide();
}

void VelocityPageTest::chromeAndContinuousAxis()
{
    VelocityFixture fixture;
    createVelocityFixture(fixture);
    SongView &view = fixture.rig->view();
    DrawerChrome &chrome = *fixture.drawerChrome;
    QVERIFY(fixture.barItem->isVisible());
    QCOMPARE(fixture.barItem->interaction(), &chrome.interaction(DrawerChromeTarget::Bar));
    QVERIFY(chrome.barRect().contains(chrome.velocityToggleRect()));
    QCOMPARE(chrome.velocityToggleRect().x(), chrome.automationToggleRect().x() +
                                                  chrome.automationToggleRect().width() +
                                                  layout::space(layout::Space::One));
    QVERIFY(fixture.barItem->bounds().contains(chrome.velocityToggleRect().center() -
                                               chrome.barRect().topLeft()));
    QVERIFY(!fixture.detentItem->isVisible());
    QVERIFY(!chrome.detentVisible());
    QCOMPARE(fixture.area->axis().mode(), VelocityAxis::Mode::Continuous);
    QVERIFY(!VelocityAxis::nodesFocusable());
    QVERIFY(!VelocityAxis::graduationLabelsFocusable());

    const int height = view.drawerSectionHeight(EditorDrawerPage::Velocity);
    const QPointF toggle = chrome.velocityToggleRect().center() - chrome.barRect().topLeft();
    sendMouse(*fixture.barItem, QEvent::MouseButtonPress, toggle, Qt::LeftButton, Qt::LeftButton);
    sendMouse(*fixture.barItem, QEvent::MouseButtonRelease, toggle, Qt::LeftButton);
    QVERIFY(!view.drawerSectionVisible(EditorDrawerPage::Velocity));
    QCOMPARE(view.drawerSectionHeight(EditorDrawerPage::Velocity), height);
    sendMouse(*fixture.barItem, QEvent::MouseButtonPress, toggle, Qt::LeftButton, Qt::LeftButton);
    sendMouse(*fixture.barItem, QEvent::MouseButtonRelease, toggle, Qt::LeftButton);
    QVERIFY(view.drawerSectionVisible(EditorDrawerPage::Velocity));
}

void VelocityPageTest::continuousGraduationDensity()
{
    VelocityFixture fixture;
    createVelocityFixture(fixture);
    SongView &view = fixture.rig->view();
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity,
                                layout::fontPx(25.0 / 3.0) + layout::space(layout::Space::One));
    fixture.refresh();
    QCOMPARE(fixture.area->axis().tickCount(), 9);
    QCOMPARE(fixture.area->axis().labelCount(), 5);
    const auto &labels = fixture.area->axis().labels();
    QCOMPARE(labels[0].velocity, 127);
    QCOMPARE(labels[1].velocity, 96);
    QCOMPARE(labels[2].velocity, 64);
    QCOMPARE(labels[3].velocity, 32);
    QCOMPARE(labels[4].velocity, 1);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity,
                                layout::fontPx(24.0) + layout::space(layout::Space::Six));
    fixture.refresh();
}

void VelocityPageTest::gridAndPanClamp()
{
    VelocityFixture fixture;
    createVelocityFixture(fixture);
    SongView &view = fixture.rig->view();
    const auto &timeline = fixture.rig->timeline();
    const uint64_t firstPastEnd =
        (timeline.lengthTicks / (timeline.ticksPerBeat * 4) + 1) * timeline.ticksPerBeat * 4;
    const QPointF gridPoint(fixture.xForTick(double(firstPastEnd)),
                            fixture.plotRect().center().y());
    const std::array colors = {
        songview::detail::gridLineColor(125), songview::detail::gridLineColor(100),
        songview::detail::gridLineColor(75),  songview::detail::gridLineColor(160),
        songview::detail::gridLineColor(200), songview::detail::gridLineColor()};
    QVERIFY(std::any_of(colors.cbegin(), colors.cend(), [&](const QColor &color) {
        return layerTouches(
            *fixture.rig->quickScene(), songview::TimelineQuickLayer::VelocityGrid,
            QRectF(gridPoint - QPointF(2, 0), QSizeF(4, fixture.plotRect().height())), color);
    }));
    view.goToStart();
    fixture.refresh();
    const QImage before = checks::support::captureQuickBand(view, fixture.bandRect());
    const double scroll = view.camera().scrollX();
    const QPointF start(layout::space(layout::Space::Two), fixture.plotRect().center().y());
    sendMouse(*fixture.inputItem, QEvent::MouseButtonPress, start, Qt::MiddleButton,
              Qt::MiddleButton);
    sendMouse(*fixture.inputItem, QEvent::MouseMove,
              start + QPointF(layout::space(layout::Space::Eight), 0), Qt::NoButton,
              Qt::MiddleButton);
    sendMouse(*fixture.inputItem, QEvent::MouseButtonRelease,
              start + QPointF(layout::space(layout::Space::Eight), 0), Qt::MiddleButton);
    QCOMPARE(view.camera().scrollX(), scroll);
    QVERIFY(samePixels(before, checks::support::captureQuickBand(view, fixture.bandRect())));
}

void VelocityPageTest::psgAxisContexts_data()
{
    QTest::addColumn<int>("voiceType");
    QTest::addColumn<int>("graduations");
    QTest::newRow("square") << int(VOICE_SQUARE_1) << 16;
    QTest::newRow("wave") << int(VOICE_PROGRAMMABLE_WAVE) << 5;
    QTest::newRow("noise") << int(VOICE_NOISE) << 16;
}

void VelocityPageTest::psgAxisContexts()
{
    QFETCH(int, voiceType);
    QFETCH(int, graduations);
    VelocityFixture fixture;
    createVelocityFixture(fixture);
    fixture.rig->view().selectionModel().setNoteSelection({fixture.notes[0].noteId});
    setVoice(fixture, tone(voiceType));
    QCOMPARE(fixture.area->axis().mode(), VelocityAxis::Mode::Intrinsic);
    QCOMPARE(fixture.area->axis().graduationCount(), graduations);
}

void VelocityPageTest::hoveredPsgContext()
{
    VelocityFixture fixture;
    createVelocityFixture(fixture);
    const ToneData noise = tone(VOICE_NOISE);
    setVoice(fixture, noise);
    SongView &view = fixture.rig->view();
    view.selectionModel().setNoteSelection({fixture.notes[0].noteId});
    fixture.refresh();
    QVERIFY(view.beginVelocityGesture({fixture.notes[1]}));
    QVERIFY(view.updateVelocityGesture({{fixture.notes[1].noteId, 74}}));
    ToneData children[128]{};
    children[60] = noise;
    children[64] = tone(VOICE_PROGRAMMABLE_WAVE);
    ToneData split{};
    split.type = VOICE_KEYSPLIT_ALL;
    split.subGroup = children;
    setVoice(fixture, split);
    view.selectionModel().setNoteSelection({fixture.notes[2].noteId});
    fixture.refresh();
    const VelocityMap noiseMap = VelocityMap::resolve(&noise, fixture.notes[1].key);
    const QPointF hovered(fixture.xForTick(double(fixture.notes[1].tick)),
                          VelocityAxis(noiseMap, fixture.area->axis().geometry()).levelToY(9));
    sendMouse(*fixture.inputItem, QEvent::MouseMove, hovered);
    QCOMPARE(fixture.area->axis().map(), noiseMap);
    QVERIFY(fixture.area->axis().graduations()[9].active);
    sendMouse(*fixture.inputItem, QEvent::Leave, {});
    view.cancelVelocityGesture();
}

void VelocityPageTest::psgRenderingAndDetentToggle()
{
    VelocityFixture fixture;
    createVelocityFixture(fixture);
    SongView &view = fixture.rig->view();
    const ToneData noise = tone(VOICE_NOISE);
    setVoice(fixture, noise);
    view.selectionModel().setNoteSelection({fixture.notes[0].noteId});
    QVERIFY(view.beginVelocityGesture({fixture.notes[1]}));
    QVERIFY(view.updateVelocityGesture({{fixture.notes[1].noteId, 74}}));
    fixture.refresh();
    const VelocityMap map = VelocityMap::resolve(&noise, fixture.notes[1].key);
    const QPointF hover(fixture.xForTick(double(fixture.notes[1].tick)),
                        fixture.area->axis().levelToY(9));
    const QImage snapped = checks::support::captureQuickBand(view, fixture.bandRect());
    sendMouse(*fixture.inputItem, QEvent::MouseMove, hover);
    pump();
    QCOMPARE(map.representative(9), 76);
    QVERIFY(fixture.area->useDetents());
    QCOMPARE(
        std::count_if(fixture.area->axis().graduations().cbegin(),
                      fixture.area->axis().graduations().cbegin() +
                          fixture.area->axis().graduationCount(),
                      [](const VelocityAxisGraduation &graduation) { return graduation.active; }),
        1);
    QVERIFY(fixture.area->axis().graduations()[9].active);
    const qreal separatorX = fixture.gutterItem->bounds().right() - layout::singlePixel();
    const QRectF accentProbe(separatorX - 3.0 * layout::space(layout::Space::Half) - 1.0,
                             fixture.area->axis().graduations()[9].y - 2.0,
                             3.0 * layout::space(layout::Space::Half) + 2.0, 4.0);
    QVERIFY(layerTouches(*fixture.rig->quickScene(), songview::TimelineQuickLayer::VelocityAxis,
                         accentProbe, fixture.gutterItem->palette().highlight().color()));
    fixture.area->setUseDetents(false);
    pump();
    QCOMPARE(fixture.area->axis().markers()[0].velocity, 74);
    QVERIFY(checks::support::captureQuickBand(view, fixture.bandRect()) != snapped);
    fixture.area->setUseDetents(true);
    sendMouse(*fixture.inputItem, QEvent::Leave, {});
    QVERIFY(samePixels(snapped, checks::support::captureQuickBand(view, fixture.bandRect())));

    const auto selectedLevel = map.levelOf(fixture.notes[0].velocity);
    const auto outsiderLevel = map.levelOf(fixture.notes[1].velocity);
    QVERIFY(selectedLevel);
    QVERIFY(outsiderLevel);
    const qreal nodeX = fixture.xForTick(double(fixture.notes[0].tick));
    const qreal selectedY = fixture.area->axis().levelToY(int(*selectedLevel));
    const qreal outsiderY = fixture.area->axis().levelToY(9);
    const QRectF selectedProbe(QPointF(nodeX, selectedY) - QPointF(4, 4), QSizeF(8, 8));
    const QRectF outsiderProbe(QPointF(nodeX, outsiderY) - QPointF(4, 4), QSizeF(8, 8));
    const QColor stemColor = songview::mixTowardOklab(Qt::cyan, Qt::black, 1.0 / 3.0);
    const auto &nodes =
        fixture.rig->quickScene()->layer(songview::TimelineQuickLayer::VelocityNodes);
    const auto &stems =
        fixture.rig->quickScene()->layer(songview::TimelineQuickLayer::VelocityStems);
    QVERIFY(checks::support::layerHasColorIn(
        stems,
        QRectF(nodeX, outsiderY - layout::singlePixel(),
               fixture.xForTick(double(fixture.notes[1].tick + fixture.notes[1].duration)) - nodeX,
               2 * layout::singlePixel()),
        stemColor));
    QVERIFY(checks::support::layerHasColorIn(nodes, selectedProbe,
                                             fixture.inputItem->palette().highlight().color()));
    QVERIFY(checks::support::layerHasColorIn(nodes, outsiderProbe, Qt::black));
    QVERIFY(checks::support::layerHasColorIn(nodes, outsiderProbe, Qt::cyan));
    view.selectionModel().setNoteSelection({fixture.notes[0].noteId, fixture.notes[2].noteId});
    fixture.refresh();
    const auto &dimmedNodes =
        fixture.rig->quickScene()->layer(songview::TimelineQuickLayer::VelocityNodes);
    QVERIFY(checks::support::layerHasColorIn(dimmedNodes, outsiderProbe,
                                             fixture.inputItem->palette().mid().color()));
    QVERIFY(!checks::support::layerHasColorIn(dimmedNodes, outsiderProbe, Qt::black));
    view.cancelVelocityGesture();

    setVoice(fixture, tone(VOICE_PROGRAMMABLE_WAVE));
    view.selectionModel().setNoteSelection({fixture.notes[0].noteId});
    fixture.refresh();
    QVERIFY(fixture.detentItem->isVisible());
    QVERIFY(fixture.drawerChrome->detentVisible());
    QCOMPARE(fixture.detentItem->interaction(),
             &fixture.drawerChrome->interaction(DrawerChromeTarget::Detent));
    QCOMPARE(fixture.detentItem->bounds(),
             QRectF(QPointF{}, fixture.drawerChrome->detentRect().size()));
    const QRect band = fixture.bandRect();
    const QRectF detentRect = fixture.drawerChrome->detentRect();
    QVERIFY(std::abs(detentRect.left() - band.left()) <= layout::singlePixel());
    QVERIFY(std::abs(detentRect.bottom() - band.bottom()) <= layout::singlePixel());
    QVERIFY(detentRect.right() < fixture.plotRect().left());
    QVERIFY(!detentRect.contains(
        QPointF(detentRect.center().x(), fixture.area->axis().graduations()[0].y)));
    setVoice(fixture, tone(VOICE_DIRECTSOUND));
    view.selectionModel().setNoteSelection({fixture.notes[0].noteId, fixture.notes[2].noteId});
    fixture.refresh();
    const QImage directSoundBand = checks::support::captureQuickBand(view, fixture.bandRect());
    setVoice(fixture, tone(VOICE_PROGRAMMABLE_WAVE));
    const int checkedIconRevision = fixture.drawerChrome->iconRevision();
    const QPointF detent = fixture.detentItem->bounds().center();
    sendMouse(*fixture.detentItem, QEvent::MouseButtonPress, detent, Qt::LeftButton,
              Qt::LeftButton);
    sendMouse(*fixture.detentItem, QEvent::MouseButtonRelease, detent, Qt::LeftButton);
    QVERIFY(!fixture.drawerChrome->detentChecked());
    QVERIFY(!fixture.area->useDetents());
    const QImage continuousBand = checks::support::captureQuickBand(view, fixture.bandRect());
    const qreal imageScale = continuousBand.devicePixelRatio();
    const QRect rulerBounds(0, 0, qCeil(double(fixture.fixedSpan()) * imageScale),
                            qFloor(double(detentRect.top() - band.top()) * imageScale));
    QVERIFY(samePixels(continuousBand.copy(rulerBounds), directSoundBand.copy(rulerBounds)));
    QVERIFY(fixture.drawerChrome->iconRevision() > checkedIconRevision);
    const int uncheckedIconRevision = fixture.drawerChrome->iconRevision();
    sendMouse(*fixture.detentItem, QEvent::MouseButtonPress, detent, Qt::LeftButton,
              Qt::LeftButton);
    sendMouse(*fixture.detentItem, QEvent::MouseButtonRelease, detent, Qt::LeftButton);
    QVERIFY(fixture.drawerChrome->detentChecked());
    QVERIFY(fixture.area->useDetents());
    QVERIFY(fixture.drawerChrome->iconRevision() > uncheckedIconRevision);
    setVoice(fixture, tone(VOICE_DIRECTSOUND));
    QTRY_VERIFY(!fixture.detentItem->isVisible());
}

void VelocityPageTest::editCursorAndContextRounding()
{
    VelocityFixture fixture;
    createVelocityFixture(fixture);
    SongView &view = fixture.rig->view();
    auto *quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    QVERIFY(quick);
    view.setEditCursorTick(12);
    fixture.refresh();
    const qreal first = quick->editRootContentX();
    view.setEditCursorTick(18);
    fixture.refresh();
    QVERIFY(quick->editVisible());
    QVERIFY(first != quick->editRootContentX());
    fixture.area->clearTrackHeaderSelection();
    QVERIFY(view.selectionModel().noteSelection().empty());
    const std::array<double, 4> inputs = {-1.0, 0.49, 0.5, 0.51};
    const std::array<uint64_t, 4> expected = {0, 0, 1, 1};
    const std::array voices = {tone(VOICE_DIRECTSOUND), tone(VOICE_SQUARE_1),
                               tone(VOICE_PROGRAMMABLE_WAVE), tone(VOICE_NOISE)};
    for (const ToneData &voice : voices) {
        setVoice(fixture, voice);
        for (int index = 0; index < 4; ++index) {
            DrawerPageLiveState live;
            live.documentRevision = fixture.document.revision();
            live.playback.playing = true;
            live.playback.playheadTick = inputs[index];
            fixture.area->refreshLiveState(live);
            QCOMPARE(view.voiceContext(expected[index]).voice, &fixture.voicegroup.voices[0]);
        }
    }
}

void VelocityPageTest::transientBandAndStackedNodes()
{
    VelocityFixture fixture;
    createVelocityFixture(fixture);
    SongView &view = fixture.rig->view();
    setVoice(fixture, tone(VOICE_NOISE));
    view.selectionModel().setNoteSelection({fixture.notes[0].noteId});
    fixture.refresh();
    const QRectF selector(layout::space(layout::Space::One), fixture.plotRect().height() / 3.0,
                          2 * layout::space(layout::Space::Eight),
                          layout::space(layout::Space::Eight));
    QColor fill = themes::color(themes::Role::song_view_selection_fill);
    fill.setAlpha(30);
    const QColor edge = themes::color(themes::Role::song_view_selection_edge);
    sendMouse(*fixture.inputItem, QEvent::MouseButtonPress, selector.topLeft(), Qt::RightButton,
              Qt::RightButton);
    sendMouse(*fixture.inputItem, QEvent::MouseMove, selector.bottomRight(), Qt::NoButton,
              Qt::RightButton);
    pump();
    QVERIFY(layerTouches(*fixture.rig->quickScene(),
                         songview::TimelineQuickLayer::VelocityTransient, selector, fill));
    QVERIFY(layerTouches(*fixture.rig->quickScene(),
                         songview::TimelineQuickLayer::VelocityTransient, selector, edge));
    sendMouse(*fixture.inputItem, QEvent::MouseButtonRelease, selector.bottomRight(),
              Qt::RightButton);
    pump();
    QVERIFY(
        layerEmpty(*fixture.rig->quickScene(), songview::TimelineQuickLayer::VelocityTransient));
    view.selectionModel().setNoteSelection({});
    fixture.refresh();
    DocNote first;
    QVERIFY(fixture.document.findNote(fixture.notes[0].noteId, &first));
    fixture.document.addNote(0, first.tick + 8, first.key, first.duration, first.velocity);
    fixture.refresh();
    const auto notes = fixture.document.notesForTrack(0);
    const auto overlap = std::find_if(notes.cbegin(), notes.cend(), [&first](const DocNote &note) {
        return note.tick == first.tick + 8 && note.noteId != first.noteId;
    });
    QVERIFY(overlap != notes.cend());
    const VelocityMap map = VelocityMap::resolve(&fixture.voicegroup.voices[0], overlap->key);
    const auto overlapLevel = map.levelOf(overlap->velocity);
    QVERIFY(overlapLevel);
    const QPointF stacked(fixture.xForTick(double(overlap->tick)),
                          fixture.area->axis().levelToY(int(*overlapLevel)));
    sendMouse(*fixture.inputItem, QEvent::MouseButtonPress, stacked, Qt::LeftButton,
              Qt::LeftButton);
    pump();
    QVERIFY(layerTouches(*fixture.rig->quickScene(), songview::TimelineQuickLayer::VelocityNodes,
                         QRectF(stacked - QPointF(3, 3), QSizeF(6, 6)),
                         fixture.inputItem->palette().highlight().color()));
    sendMouse(*fixture.inputItem, QEvent::MouseButtonRelease, stacked, Qt::LeftButton);
    view.selectionModel().setNoteSelection({fixture.notes[0].noteId, fixture.notes[2].noteId});
    fixture.refresh();
    const auto selectedLevel = map.levelOf(first.velocity);
    QVERIFY(selectedLevel);
    const QPointF selected(fixture.xForTick(double(first.tick)),
                           fixture.area->axis().levelToY(int(*selectedLevel)));
    sendMouse(*fixture.inputItem, QEvent::MouseButtonPress, selected, Qt::RightButton,
              Qt::RightButton);
    pump();
    QVERIFY(layerTouches(*fixture.rig->quickScene(), songview::TimelineQuickLayer::VelocityNodes,
                         QRectF(selected - QPointF(3, 3), QSizeF(6, 6)),
                         fixture.inputItem->palette().highlight().color()));
    sendMouse(*fixture.inputItem, QEvent::MouseButtonRelease, selected, Qt::RightButton);
}

void VelocityPageTest::rampAndRollPreview()
{
    VelocityFixture fixture;
    createVelocityFixture(fixture);
    SongView &view = fixture.rig->view();
    const ToneData noise = tone(VOICE_NOISE);
    setVoice(fixture, noise);
    const VelocityMap map = VelocityMap::resolve(&noise, fixture.notes[0].key);
    DocNote first;
    DocNote third;
    QVERIFY(fixture.document.findNote(fixture.notes[0].noteId, &first));
    QVERIFY(fixture.document.findNote(fixture.notes[2].noteId, &third));
    fixture.document.setNotesVelocity({first}, map.representative(0));
    fixture.document.setNotesVelocity({third}, map.representative(4));
    fixture.document.addNote(0, 36, first.key, 12, map.representative(3));
    const std::vector<DocNote> notes = fixture.document.notesForTrack(0);
    const auto middle = std::find_if(notes.cbegin(), notes.cend(),
                                     [](const DocNote &note) { return note.tick == 36; });
    QVERIFY(middle != notes.cend());
    view.selectionModel().setNoteSelection(
        {fixture.notes[0].noteId, middle->noteId, fixture.notes[2].noteId});
    fixture.refresh();
    const QPointF start(fixture.xForTick(double(first.tick)), fixture.area->axis().levelToY(0));
    const QPointF end(fixture.xForTick(double(third.tick)), fixture.area->axis().levelToY(4));
    sendMouse(*fixture.inputItem, QEvent::MouseButtonPress, start, Qt::LeftButton, Qt::LeftButton,
              Qt::ShiftModifier);
    sendMouse(*fixture.inputItem, QEvent::MouseMove, end, Qt::NoButton, Qt::LeftButton,
              Qt::ShiftModifier);
    pump();
    const QPointF quarter = start + (end - start) / 4.0;
    QVERIFY(layerTouches(*fixture.rig->quickScene(),
                         songview::TimelineQuickLayer::VelocityTransient,
                         QRectF(quarter - QPointF(2.0, 2.0), QSizeF(5.0, 5.0)),
                         themes::color(themes::Role::song_view_edit_preview_outline)));
    sendMouse(*fixture.inputItem, QEvent::MouseButtonRelease, end, Qt::LeftButton, Qt::NoButton,
              Qt::ShiftModifier);
    fixture.document.deleteNotes({*middle});
    view.selectionModel().setNoteSelection({fixture.notes[0].noteId, fixture.notes[1].noteId});
    fixture.refresh();
    auto *roll = fixture.rig->quickRoot()->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineRollInput"));
    QVERIFY(roll);
    const Qt::KeyboardModifiers modifiers =
        keymap::Registry::instance().modifierBinding(QStringLiteral("roll.velocity_drag"));
    QVERIFY(modifiers != Qt::NoModifier);
    const QPointF center(
        view.camera().displayX(first.tick + first.duration / 2.0, 0.0, roll->devicePixelRatio()),
        (127.5 - first.key) * view.camera().keyHeight() - view.camera().scrollY());
    const QPointF dragged = center - QPointF(0, QApplication::startDragDistance() + 16);
    sendMouse(*roll, QEvent::MouseButtonPress, center, Qt::LeftButton, Qt::LeftButton, modifiers);
    sendMouse(*roll, QEvent::MouseMove, dragged, Qt::NoButton, Qt::LeftButton, modifiers);
    QVERIFY(view.previewVelocity(first.noteId).has_value());
    sendMouse(*roll, QEvent::MouseButtonRelease, dragged, Qt::LeftButton, Qt::NoButton, modifiers);
}

void VelocityPageTest::velocityGestureTransactions()
{
    VelocityTransactionFixture fixture;
    createVelocityFixture(fixture);
    SongView &view = fixture.view();
    view.selectionModel().setNoteSelection({fixture.notes[0].noteId, fixture.notes[2].noteId});
    const Snapshot baseline = fixture.snapshot();
    const QPointF start(fixture.xForTick(double(fixture.notes[0].tick)),
                        fixture.area().axis().velocityToY(fixture.notes[0].velocity));
    const QPointF raised = start - QPointF(0, QApplication::startDragDistance() + 16);

    sendMouse(fixture.input(), QEvent::MouseButtonPress, start, Qt::LeftButton, Qt::LeftButton);
    sendMouse(fixture.input(), QEvent::MouseMove, raised, Qt::NoButton, Qt::LeftButton);
    QVERIFY(view.previewVelocity(fixture.notes[0].noteId).has_value());
    QVERIFY(fixture.snapshot() == baseline);
    sendKey(fixture.input(), Qt::Key_Escape);
    QVERIFY(fixture.snapshot() == baseline);
    QVERIFY(!view.previewVelocity(fixture.notes[0].noteId).has_value());

    sendMouse(fixture.input(), QEvent::MouseButtonPress, start, Qt::LeftButton, Qt::LeftButton);
    sendMouse(fixture.input(), QEvent::MouseMove, raised, Qt::NoButton, Qt::LeftButton);
    sendMouse(fixture.input(), QEvent::MouseButtonRelease, raised, Qt::LeftButton);
    const Snapshot committed = fixture.snapshot();
    QCOMPARE(committed.revision, baseline.revision + 1);
    QCOMPARE(committed.undoIndex, baseline.undoIndex + 1);
    QVERIFY(committed.smf != baseline.smf);
    fixture.document().undoStack()->undo();
    const Snapshot undone = fixture.snapshot();
    QCOMPARE(undone.smf, baseline.smf);
    QCOMPARE(undone.undoIndex, baseline.undoIndex);
    QCOMPARE(undone.revision, committed.revision + 1);
    fixture.document().undoStack()->redo();
    const Snapshot redone = fixture.snapshot();
    QCOMPARE(redone.smf, committed.smf);
    QCOMPARE(redone.undoIndex, committed.undoIndex);
    QCOMPARE(redone.revision, undone.revision + 1);
}

void VelocityPageTest::textRetentionAndPlayheadPerformance()
{
    VelocityFixture fixture;
    createVelocityFixture(fixture);
    auto *scene = fixture.rig->quickScene();
    QAbstractItemModel *const text = scene->velocityTextModel();
    QVERIFY(text);
    const int rows = text->rowCount();
    QVERIFY(rows > 0);
    int churn = 0;
    QObject observer;
    QObject::connect(
        text, &QAbstractItemModel::rowsInserted, &observer,
        [&churn](const QModelIndex &, int first, int last) { churn += last - first + 1; });
    QObject::connect(
        text, &QAbstractItemModel::rowsRemoved, &observer,
        [&churn](const QModelIndex &, int first, int last) { churn += last - first + 1; });
    fixture.area->songChanged();
    fixture.refresh();
    QCOMPARE(churn, 0);
    fixture.rig->view().setEditorHorizontalScroll(layout::space(layout::Space::Eight));
    fixture.refresh();
    QCOMPARE(churn, 0);
    fixture.rig->view().setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
    fixture.rig->view().setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    fixture.refresh();
    QCOMPARE(text->rowCount(), rows);
    fixture.refresh(true, -1.0);
    const VelocityAreaDiagnostics warm = fixture.area->diagnostics();
    for (int tick = 0; tick < 120; ++tick)
        fixture.refresh(true, double(tick));
    QCOMPARE(fixture.area->diagnostics().contentBuildCount, warm.contentBuildCount);
    QCOMPARE(fixture.area->diagnostics().presentedPlayheadTick, 119.0);
    QCOMPARE(fixture.area->diagnostics().playheadPresentationCount,
             warm.playheadPresentationCount + 120);
}

int runVelocityPageCheck(const QString &scratchProject, const QString &songLabel,
                         const QStringList &qtArguments)
{
    VelocityPageTest test(scratchProject, songLabel);
    QStringList arguments{QStringLiteral("velocity-page")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
