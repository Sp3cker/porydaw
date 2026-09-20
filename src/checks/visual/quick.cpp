// Visual baseline check for the production Qt Quick timeline surfaces.
// Captures the real SongTab Quick window framebuffer and freezes semantic
// region bounds plus rendered pixels through checks::visual::compare. IDs and
// region names are semantic — never QWidget/QQuickItem class names — so a
// future Swift/QtBridge adapter can supply the same bounds.

#include "checks/visual/visualbaseline.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QImage>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QString>
#include <QStyleHints>
#include <QtTest>

#include <cstring>
#include <functional>
#include <optional>
#include <utility>
#include <vector>

#include "checks/quickpopupguard.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/support.h"
#include "checks/support/timelinequickcheck.h"
#include "core/smf.h"
#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "project/voicegroupsource.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editorviewstate.h"
#include "ui/pitchprojection.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"

extern "C" {
#include "voicegroup_loader.h"
}

namespace {

constexpr int kViewWidth = 1280;
constexpr int kViewHeight = 800;
constexpr double kSampleRate = 48000.0;
constexpr double kTimeZoom = 64.0;
constexpr int kVelocityLaneHeight = 160;

SmfEvent noteEvent(uint8_t status, Tick tick, uint8_t key, uint8_t velocity)
{
    return {.tick = Tick(tick),
            .status = status,
            .data0 = key,
            .data1 = velocity,
            .blob = {},
            .noteId = {}};
}

// Deterministic three-track song: tempo map plus program changes and notes
// with deliberately varied pitches and velocities so the ruler, roll, track
// headers, and velocity lane all render real content.
SmfFile visualSmf()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.resize(4);
    smf.tracks[0].events.push_back({.tick = 0,
                                    .status = 0xFF,
                                    .metaType = 0x51,
                                    .blob = QByteArray("\x07\xA1\x20", 3),
                                    .noteId = {}});
    smf.tracks[0].endTick = 384;
    smf.tracks[1].events = {noteEvent(0xC0, 0, 1, 0),   noteEvent(0x90, 0, 60, 40),
                            noteEvent(0x80, 24, 60, 0), noteEvent(0x90, 48, 64, 80),
                            noteEvent(0x80, 72, 64, 0), noteEvent(0x90, 96, 67, 120),
                            noteEvent(0x80, 144, 67, 0)};
    smf.tracks[1].endTick = 384;
    smf.tracks[2].events = {noteEvent(0xC1, 0, 5, 0), noteEvent(0x91, 0, 48, 90),
                            noteEvent(0x81, 96, 48, 0)};
    smf.tracks[2].endTick = 384;
    smf.tracks[3].events = {noteEvent(0xC2, 0, 10, 0), noteEvent(0x92, 24, 55, 70),
                            noteEvent(0x82, 72, 55, 0)};
    smf.tracks[3].endTick = 384;
    return smf;
}

} // namespace

class VisualQuickTest : public QObject
{
    Q_OBJECT

  private slots:
    void initTestCase();
    void init();
    void cleanup();

    void timelineRulerBaseline();
    void pianoRollBaseline();
    void trackHeaderBaseline();
    void velocityLaneBaseline();
    void editorDrawerBaseline();
    void drumKeyboardBaseline();
    void pitchBendPopupBaseline();
    void velocityPromptBaseline();
    void insertTimePromptBaseline();
    void timeSignaturePromptBaseline();
    void noteMenuBaseline();
    void quickMenuPanelBaseline();
    void ccDeleteConfirmBaseline();
    void voicePickerBaseline();
    void eventListBaseline();
    void automationTabsBaseline();

  private:
    bool createFixture(QString &error);
    void destroyFixture();
    QImage grab(QString &error);
    QRect itemBounds(const QString &objectName) const;
    QRect bandBounds(songview::TimelineBand band) const;
    checks::visual::Region region(const QString &name, const QRect &bounds) const;
    checks::visual::Region itemRegion(const QString &name, const QString &objectName) const;
    checks::visual::Region bandRegion(const QString &name, songview::TimelineBand band) const;
    void expectBaseline(const QString &id, const QList<checks::visual::Region> &regions);
    bool openPitchBendPopup();
    // Waits for the shared QuickPopupSession to open a form and returns its
    // content item; null when the command never produced a popup.
    QQuickItem *awaitPopupForm();
    // Menus push QuickMenuPanel levels onto the session overlay rather than a
    // single content item; returns the root panel once the session is open.
    QQuickItem *awaitMenuPanel();
    void expectPopupBaseline(const QString &id, QQuickItem *form,
                             const QString &steadyFocusObjectName = QString());

    LoadedVoiceGroup m_bank{};
    std::unique_ptr<SongTab> m_tab;
    QPointer<QQuickWindow> m_window;
    QPointer<QQuickItem> m_root;
    QPointer<songview::TimelineInputItem> m_rollInput;
    DocNote m_note{};
    bool m_hasNote = false;
};

void VisualQuickTest::initTestCase()
{
    checks::visual::prepare(*static_cast<QApplication *>(QCoreApplication::instance()));
}

void VisualQuickTest::init()
{
    QString error;
    QVERIFY2(createFixture(error), qPrintable(error));
}

void VisualQuickTest::cleanup()
{
    destroyFixture();
}

bool VisualQuickTest::createFixture(QString &error)
{
    m_bank = {};
    m_bank.voices[0].type = VOICE_DIRECTSOUND;
    m_bank.voices[1].type = VOICE_SQUARE_1;
    m_bank.voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    m_bank.voices[3].type = VOICE_NOISE;

    const std::optional<SongName> name = SongName::create(QStringLiteral("visual-quick"));
    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("visual-quick-check"), QString());
    if (!name || !identity) {
        error = QStringLiteral("visual quick fixture has invalid identities");
        return false;
    }
    auto candidate = std::make_unique<SongTab>(std::move(*name));
    candidate->resize(kViewWidth, kViewHeight);
    candidate->setSampleRate(kSampleRate);
    SongInfo info;
    info.label = QStringLiteral("visual-quick");
    info.hasMid = true;
    candidate->applyMidiStage(std::move(info), visualSmf(), track_limits::kHardwareCapacity);
    if (!candidate->presentationError().isEmpty()) {
        error = candidate->presentationError();
        return false;
    }
    candidate->applyBankView(LoadedBankView{
        .id = *identity,
        .bank = borrowVoicegroupLease(&m_bank),
        .loadName = QString(),
        .slotViews = {},
    });
    candidate->applyVoicegroupBound(*identity);
    if (!candidate->isReady()) {
        error = QStringLiteral("visual quick SongTab did not reach ready state");
        return false;
    }
    checks::support::bindEditActionsForTest(candidate->view());

    // One voice change gives the voice-changes lane and track headers real
    // program content without depending on a project fixture.
    candidate->document().addLanePoint(0, DOC_CC_VOICE, 48, 3);

    const std::vector<DocNote> notes = candidate->document().notesForTrack(0);
    if (notes.empty()) {
        error = QStringLiteral("visual quick fixture has no notes on track 0");
        return false;
    }
    m_note = notes.front();
    m_hasNote = true;

    SongView &songView = candidate->view();
    songView.setEditorTimeZoom(kTimeZoom);
    songView.setScaleFold(false);
    songView.setEventListVisible(false);
    songView.selectTrack(0);
    songView.selectionModel().setNoteSelection({m_note.noteId});

    songview::TimelineQuickView *quick = songView.quickView();
    m_window = quick ? quick->quickWindow() : nullptr;
    m_root = quick ? quick->rootObject() : nullptr;
    if (!quick || !m_window || !m_root) {
        error = QStringLiteral("SongTab did not expose the Quick canvas");
        return false;
    }
    m_rollInput =
        m_root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRollInput"));
    if (!m_rollInput) {
        error = QStringLiteral("Quick canvas lacks the roll input item");
        return false;
    }

    candidate->show();
    if (!QTest::qWaitFor(
            [this] { return m_window && m_window->isVisible() && m_window->isExposed(); })) {
        error = QStringLiteral("Quick window did not become exposed");
        return false;
    }
    if (!checks::support::waitForQuickFrame(*m_window, &error))
        return false;
    m_tab = std::move(candidate);
    return true;
}

void VisualQuickTest::destroyFixture()
{
    if (m_tab) {
        if (songview::QuickPopupSession *session = quick_popup::popupSession(m_tab->view());
            session && session->isOpen())
            session->cancel();
        m_tab->hide();
    }
    m_rollInput.clear();
    m_root.clear();
    m_window.clear();
    m_tab.reset();
    m_hasNote = false;
}

QImage VisualQuickTest::grab(QString &error)
{
    if (!m_window || !checks::support::waitForQuickFrame(*m_window, &error))
        return {};
    const QImage image = m_window->grabWindow();
    if (image.isNull())
        error = QStringLiteral("Quick framebuffer grab is empty");
    return image;
}

QRect VisualQuickTest::itemBounds(const QString &objectName) const
{
    // Input items are transparent hit targets: bounds matter, opacity does
    // not, so visibility is not required — only a real mapped rectangle.
    QQuickItem *const item = checks::support::visualDescendant(m_root.data(), objectName);
    if (!item || item->width() <= 0 || item->height() <= 0)
        return {};
    const QPointF topLeft = item->mapToScene(QPointF{});
    return {qRound(topLeft.x()), qRound(topLeft.y()), qRound(item->width()),
            qRound(item->height())};
}

QRect VisualQuickTest::bandBounds(songview::TimelineBand band) const
{
    const std::optional<songview::TimelineBandGeometry> &geometry =
        m_tab->view().timelineBandLayout().geometry(band);
    return geometry ? geometry->rect : QRect{};
}

checks::visual::Region VisualQuickTest::region(const QString &name, const QRect &bounds) const
{
    return {name, bounds};
}

checks::visual::Region VisualQuickTest::itemRegion(const QString &name,
                                                   const QString &objectName) const
{
    return region(name, itemBounds(objectName));
}

checks::visual::Region VisualQuickTest::bandRegion(const QString &name,
                                                   songview::TimelineBand band) const
{
    return region(name, bandBounds(band));
}

void VisualQuickTest::expectBaseline(const QString &id,
                                     const QList<checks::visual::Region> &regions)
{
    QString error;
    const QImage image = grab(error);
    QVERIFY2(!image.isNull(), qPrintable(error));
    for (const checks::visual::Region &entry : regions)
        QVERIFY2(!entry.bounds.isEmpty(), qPrintable(entry.name + " has no visible bounds"));
    QVERIFY2(checks::visual::compare(id, image, regions, &error), qPrintable(error));
}

void VisualQuickTest::timelineRulerBaseline()
{
    expectBaseline(
        QStringLiteral("quick/vanilla/timeline-ruler"),
        {bandRegion(QStringLiteral("timeline.ruler.band"), songview::TimelineBand::Ruler),
         itemRegion(QStringLiteral("timeline.ruler.gutter"),
                    QStringLiteral("timelineQuickRulerGutterChrome")),
         itemRegion(QStringLiteral("timeline.ruler.chrome"),
                    QStringLiteral("timelineQuickRulerChrome")),
         itemRegion(QStringLiteral("timeline.ruler.marks"),
                    QStringLiteral("timelineQuickRulerMarks")),
         itemRegion(QStringLiteral("timeline.ruler.controls"),
                    QStringLiteral("timelineRulerControls"))});
}

void VisualQuickTest::pianoRollBaseline()
{
    expectBaseline(QStringLiteral("quick/vanilla/piano-roll"),
                   {bandRegion(QStringLiteral("piano-roll.band"), songview::TimelineBand::Roll),
                    itemRegion(QStringLiteral("piano-roll.grid.rows"),
                               QStringLiteral("timelineQuickPianoGridRows")),
                    itemRegion(QStringLiteral("piano-roll.grid.time"),
                               QStringLiteral("timelineQuickPianoGridTime")),
                    itemRegion(QStringLiteral("piano-roll.note-fills"),
                               QStringLiteral("timelineQuickPianoNoteFills")),
                    itemRegion(QStringLiteral("piano-roll.note-borders-selection"),
                               QStringLiteral("timelineQuickPianoNoteBordersAndSelection")),
                    itemRegion(QStringLiteral("piano-roll.keyboard.keys"),
                               QStringLiteral("timelineQuickPianoKeyboardKeys"))});
}

void VisualQuickTest::trackHeaderBaseline()
{
    expectBaseline(
        QStringLiteral("quick/vanilla/track-headers"),
        {bandRegion(QStringLiteral("track-headers.band"), songview::TimelineBand::TrackHeaders),
         itemRegion(QStringLiteral("track-headers.rows"),
                    QStringLiteral("timelineQuickTrackHeaders"))});
}

void VisualQuickTest::velocityLaneBaseline()
{
    SongView &songView = m_tab->view();
    songView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    songView.setDrawerSectionHeight(EditorDrawerPage::Velocity, kVelocityLaneHeight);
    checks::support::pumpQuick();
    expectBaseline(
        QStringLiteral("quick/vanilla/velocity-lane"),
        {bandRegion(QStringLiteral("velocity-lane.band"), songview::TimelineBand::Velocity),
         itemRegion(QStringLiteral("velocity-lane.axis"),
                    QStringLiteral("timelineQuickVelocityAxis")),
         itemRegion(QStringLiteral("velocity-lane.grid"),
                    QStringLiteral("timelineQuickVelocityGrid")),
         itemRegion(QStringLiteral("velocity-lane.stems"),
                    QStringLiteral("timelineQuickVelocityStems")),
         itemRegion(QStringLiteral("velocity-lane.nodes"),
                    QStringLiteral("timelineQuickVelocityNodes"))});
}

void VisualQuickTest::editorDrawerBaseline()
{
    SongView &songView = m_tab->view();
    songView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    songView.setDrawerSectionHeight(EditorDrawerPage::Velocity, kVelocityLaneHeight);
    songView.setDrawerActivePage(EditorDrawerPage::Velocity);
    checks::support::pumpQuick();
    expectBaseline(
        QStringLiteral("quick/vanilla/editor-drawer"),
        {itemRegion(QStringLiteral("editor-drawer.bar"), QStringLiteral("drawerBarInput")),
         itemRegion(QStringLiteral("editor-drawer.detent"), QStringLiteral("drawerDetent")),
         itemRegion(QStringLiteral("editor-drawer.velocity-toggle"),
                    QStringLiteral("drawerVelocityToggle")),
         bandRegion(QStringLiteral("editor-drawer.velocity-page"),
                    songview::TimelineBand::Velocity)});
}

void VisualQuickTest::drumKeyboardBaseline()
{
    SongView &songView = m_tab->view();
    const songview::PitchProjection &projection = songView.pitchProjection();

    // Pick a visible accidental pad plus two naturals, mirroring the
    // timelinepan drum fixture so dark-lane plates render.
    int namedKey = -1;
    int unnamedKey = -1;
    int longKey = -1;
    const QRect rollRect = bandBounds(songview::TimelineBand::Roll);
    for (int row = 0; row < projection.visibleRowCount(); ++row) {
        const int key = projection.visiblePitchAt(row);
        const QRectF rect =
            projection.rowRect(row, 0, songView.pianoKeyboardWidth(), songView.camera().keyHeight(),
                               songView.camera().scrollY(), m_rollInput->devicePixelRatio());
        if (rect.top() < 0 || rect.bottom() > rollRect.height())
            continue;
        if (songview::detail::isBlackKey(key)) {
            if (namedKey < 0)
                namedKey = key;
        } else if (unnamedKey < 0) {
            unnamedKey = key;
        } else {
            longKey = key;
        }
    }
    QVERIFY2(namedKey >= 0 && unnamedKey >= 0 && longKey >= 0,
             "fixture must expose an accidental and two natural pad rows");

    // Keysplit bank: the selected track's program resolves to a drum subgroup
    // whose named keys render label plates on the keyboard gutter.
    static ToneData tones[VOICEGROUP_SIZE]{};
    static char names[VOICEGROUP_SIZE][VG_VOICE_NAME_LEN]{};
    static ToneData *subGroups[1]{};
    static char (*subGroupNames[1])[VG_VOICE_NAME_LEN]{};
    std::memset(tones, 0, sizeof(tones));
    std::memset(names, 0, sizeof(names));
    tones[unnamedKey].type = VOICE_NOISE;
    std::strncpy(names[namedKey], "Kick", VG_VOICE_NAME_LEN - 1);
    std::strncpy(names[longKey], "Fixture Drum Pad With A Long Name", VG_VOICE_NAME_LEN - 1);
    subGroups[0] = tones;
    subGroupNames[0] = names;
    LoadedVoiceGroup drumBank{};
    drumBank.voices[1].type = VOICE_KEYSPLIT_ALL;
    drumBank.voices[1].subGroup = tones;
    drumBank.subGroups = subGroups;
    drumBank.subGroupVoiceNames = subGroupNames;
    drumBank.subGroupCount = 1;
    drumBank.subGroupCapacity = 1;

    const LoadedVoiceGroup *const originalBank = songView.voicegroup();
    const auto restore =
        qScopeGuard([&songView, originalBank] { songView.setVoicegroup(originalBank); });
    songView.setVoicegroup(&drumBank);
    checks::support::pumpQuick();

    QList<checks::visual::Region> regions{
        bandRegion(QStringLiteral("drum-keyboard.band"), songview::TimelineBand::Roll),
        itemRegion(QStringLiteral("drum-keyboard.keys"),
                   QStringLiteral("timelineQuickPianoKeyboardKeys")),
    };

    // Semantic bounds for the named-pad label plate: the text model publishes
    // the plate rect in band-local coordinates.
    songview::TimelineQuickScene *const scene =
        songView.findChild<songview::TimelineQuickScene *>();
    QVERIFY(scene);
    QAbstractItemModel *const model = scene->pianoKeyboardTextModel();
    QVERIFY(model);
    const int namedRow = projection.rowForPitch(namedKey);
    QVERIFY(namedRow >= 0);
    const QRectF padRect = projection.rowRect(
        namedRow, 0, songView.pianoKeyboardWidth(), songView.camera().keyHeight(),
        songView.camera().scrollY(), m_rollInput->devicePixelRatio());
    QModelIndex namedIndex;
    for (int i = 0; i < model->rowCount(); ++i) {
        const QModelIndex index = model->index(i, 0);
        const QRectF rect =
            model->data(index, songview::TimelineQuickTextModel::RectRole).toRectF();
        if (rect.top() <= padRect.center().y() && rect.bottom() >= padRect.center().y()) {
            namedIndex = index;
            break;
        }
    }
    QVERIFY(namedIndex.isValid());
    QCOMPARE(model->data(namedIndex, songview::TimelineQuickTextModel::TextRole).toString(),
             QStringLiteral("Kick"));
    const QRectF plate =
        model->data(namedIndex, songview::TimelineQuickTextModel::BackgroundRectRole).toRectF();
    QVERIFY2(!plate.isEmpty(), "named drum pad must publish a label plate");
    regions.push_back(
        region(QStringLiteral("drum-keyboard.named-plate"),
               QRect{rollRect.x() + qRound(plate.x()), rollRect.y() + qRound(plate.y()),
                     qRound(plate.width()), qRound(plate.height())}));

    expectBaseline(QStringLiteral("quick/vanilla/drum-keyboard"), regions);
}

bool VisualQuickTest::openPitchBendPopup()
{
    // Invoke the same semantic command the G key routes to; this is an
    // appearance check, so popup opening must not depend on desktop focus or
    // synthetic key delivery.
    m_tab->view().selectionModel().setNoteSelection({m_note.noteId});
    if (!m_tab->view().editCommandAvailable(SongView::EditCommand::PitchBend))
        return false;
    m_tab->view().executeEditCommand(SongView::EditCommand::PitchBend);
    return QTest::qWaitFor([this] {
        songview::QuickPopupSession *session = quick_popup::popupSession(m_tab->view());
        return session && session->isOpen() && session->contentItem() != nullptr;
    });
}

void VisualQuickTest::pitchBendPopupBaseline()
{
    QVERIFY(m_hasNote);
    QVERIFY2(openPitchBendPopup(), "pitch-bend popup did not open in the Quick canvas");
    songview::QuickPopupSession *session = quick_popup::popupSession(m_tab->view());
    QVERIFY(session);
    QQuickItem *const form = session->contentItem();
    QVERIFY(form);
    const QPointF formScene = form->mapToScene(QPointF{});
    QList<checks::visual::Region> regions{
        region(QStringLiteral("popup.pitch-bend.form"),
               QRect{qRound(formScene.x()), qRound(formScene.y()), qRound(form->width()),
                     qRound(form->height())}),
    };
    QQuickItem *const graph =
        checks::support::visualDescendant(form, QStringLiteral("pitchBendGraph"));
    QVERIFY(graph);
    // Canonical fixture state is explicitly unfocused, like the other
    // non-input captures: the focus frame is input-routing appearance, not
    // size/color baseline. Assert the real precondition the renderer checks.
    graph->setFocus(false);
    checks::support::pumpQuick();
    QVERIFY2(!graph->hasActiveFocus(),
             "pitch-bend graph kept active focus for the unfocused baseline capture");
    {
        const QPointF graphScene = graph->mapToScene(QPointF{});
        regions.push_back(region(QStringLiteral("popup.pitch-bend.graph"),
                                 QRect{qRound(graphScene.x()), qRound(graphScene.y()),
                                       qRound(graph->width()), qRound(graph->height())}));
    }
    expectBaseline(QStringLiteral("quick/vanilla/pitch-bend-popup"), regions);
}

QQuickItem *VisualQuickTest::awaitPopupForm()
{
    if (!QTest::qWaitFor([this] {
            songview::QuickPopupSession *session = quick_popup::popupSession(m_tab->view());
            return session && session->isOpen() && session->contentItem() != nullptr;
        }))
        return nullptr;
    return quick_popup::popupSession(m_tab->view())->contentItem();
}

// Shared popup-form capture: the session's content item is the whole dialog,
// so its scene rect is the single semantic region. A focused text field
// blinks its caret, which would race the capture; callers pass the accept
// button's objectName so focus lands on a steady (non-blinking) control.
void VisualQuickTest::expectPopupBaseline(const QString &id, QQuickItem *form,
                                          const QString &steadyFocusObjectName)
{
    QVERIFY(form);
    if (!steadyFocusObjectName.isEmpty()) {
        if (QQuickItem *const steady = form->findChild<QQuickItem *>(steadyFocusObjectName))
            steady->setFocus(true);
    }
    checks::support::pumpQuick();
    const QPointF scene = form->mapToScene(QPointF{});
    expectBaseline(id, {region(QStringLiteral("popup.form"),
                               QRect{qRound(scene.x()), qRound(scene.y()), qRound(form->width()),
                                     qRound(form->height())})});
}

void VisualQuickTest::velocityPromptBaseline()
{
    QVERIFY(m_hasNote);
    m_tab->view().selectionModel().setNoteSelection({m_note.noteId});
    QVERIFY2(m_tab->view().editCommandAvailable(SongView::EditCommand::SetVelocity),
             "Set Velocity must be available with a note selected");
    m_tab->view().executeEditCommand(SongView::EditCommand::SetVelocity);
    expectPopupBaseline(QStringLiteral("quick/vanilla/velocity-prompt"), awaitPopupForm(),
                        QStringLiteral("noteVelocityAccept"));
}

void VisualQuickTest::insertTimePromptBaseline()
{
    QVERIFY2(m_tab->view().editCommandAvailable(SongView::EditCommand::InsertTime),
             "Insert Time must be available on a loaded timeline");
    m_tab->view().executeEditCommand(SongView::EditCommand::InsertTime);
    expectPopupBaseline(QStringLiteral("quick/vanilla/insert-time-prompt"), awaitPopupForm(),
                        QStringLiteral("insertTimeAccept"));
}

void VisualQuickTest::timeSignaturePromptBaseline()
{
    QVERIFY2(m_tab->view().editCommandAvailable(SongView::EditCommand::EditTimeSignature),
             "Edit Time Signature must be available on a loaded timeline");
    m_tab->view().executeEditCommand(SongView::EditCommand::EditTimeSignature);
    expectPopupBaseline(QStringLiteral("quick/vanilla/time-signature-prompt"), awaitPopupForm(),
                        QStringLiteral("timeSignatureAccept"));
}

void VisualQuickTest::noteMenuBaseline()
{
    QVERIFY(m_hasNote);
    SongView &songView = m_tab->view();
    // Project the fixture note's center into the roll plot's local space:
    // contentX is tick * pxPerTick - scrollX, and rowRect gives the pitch row.
    const double noteX = songView.camera().contentX(m_note.tick + m_note.duration / 2.0);
    const int row = songView.pitchProjection().rowForPitch(m_note.key);
    QVERIFY2(row >= 0, "fixture note must be on a visible pitch row");
    const QRectF rowRect = songView.pitchProjection().rowRect(
        row, 0, 0, songView.camera().keyHeight(), songView.camera().scrollY(),
        m_rollInput->devicePixelRatio());
    const QPointF local{noteX, (rowRect.top() + rowRect.bottom()) / 2.0};
    const QPoint windowPos = m_rollInput->mapToScene(local).toPoint();
    QTest::mouseClick(m_window, Qt::RightButton, Qt::NoModifier, windowPos);
    expectPopupBaseline(QStringLiteral("quick/vanilla/note-menu"), awaitMenuPanel());
}

void VisualQuickTest::quickMenuPanelBaseline()
{
    // The event-list filter button opens a QuickMenuPanel through the shared
    // session; clicking it exercises the same menu surface as the note menu.
    m_tab->view().setEventListVisible(true);
    checks::support::pumpQuick();
    QQuickItem *const filter = m_root->findChild<QQuickItem *>(QStringLiteral("eventListFilter"));
    QVERIFY2(filter, "event list filter button is unavailable");
    QVERIFY2(QTest::qWaitFor([filter] { return filter->isEnabled() && filter->isVisible(); }),
             "event list filter button did not become enabled");
    const QPoint windowPos =
        filter->mapToScene(QPointF{filter->width() / 2.0, filter->height() / 2.0}).toPoint();
    QTest::mouseClick(m_window, Qt::LeftButton, Qt::NoModifier, windowPos);
    expectPopupBaseline(QStringLiteral("quick/vanilla/quick-menu-panel"), awaitMenuPanel());
}

void VisualQuickTest::ccDeleteConfirmBaseline()
{
    SongView &songView = m_tab->view();
    // The confirm only opens for a lane carrying document-written events, so
    // write one Volume point before arming the lane menu.
    songView.document().addLanePoint(0, CoreTimeDefaults::kCcVolume, 24, 96);
    songView.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    songView.setDrawerActivePage(EditorDrawerPage::Automations);
    checks::support::pumpQuick();

    AutomationCanvas *const canvas =
        songView.editorDrawer() ? songView.editorDrawer()->automationPage()->canvas() : nullptr;
    QVERIFY2(canvas, "automation canvas is unavailable");
    // Parameter 0 is Volume in the supported-controller order; open its lane
    // menu at a fixed scene point.
    canvas->openParameterMenu(0, 200.0, 200.0);
    QQuickItem *const panel = awaitMenuPanel();
    QVERIFY2(panel, "lane menu did not open");

    // Locate the destructive row by its model text, then click it. Row y is
    // the running sum of row/separator heights above it.
    auto *const model =
        qobject_cast<songview::QuickMenuModel *>(panel->property("menuModel").value<QObject *>());
    QVERIFY2(model, "lane menu model is unavailable");
    const qreal rowHeight = panel->property("rowHeight").toDouble();
    const qreal separatorHeight = panel->property("separatorHeight").toDouble();
    qreal rowY = 0.0;
    int targetRow = -1;
    for (int i = 0; i < model->count(); ++i) {
        const songview::QuickMenuItem *item = model->itemAt(i);
        if (!item)
            continue;
        if (item->separator) {
            rowY += separatorHeight;
            continue;
        }
        if (item->text == QStringLiteral("Delete automation events")) {
            targetRow = i;
            break;
        }
        rowY += rowHeight;
    }
    QVERIFY2(targetRow >= 0, "lane menu lacks a Delete automation events row");
    // Rows live in the ListView inside quickMenuFrame (offset by menuOrigin
    // plus the frame border), so map the row center through the frame.
    QQuickItem *const frame = panel->findChild<QQuickItem *>(QStringLiteral("quickMenuFrame"));
    QVERIFY2(frame, "lane menu frame is unavailable");
    const qreal frameBorder =
        frame->property("border").value<QObject *>()
            ? frame->property("border").value<QObject *>()->property("width").toDouble()
            : 1.0;
    const QPoint windowPos =
        frame->mapToScene(QPointF{frame->width() / 2.0, frameBorder + rowY + rowHeight / 2.0})
            .toPoint();
    QTest::mouseClick(m_window, Qt::LeftButton, Qt::NoModifier, windowPos);
    expectPopupBaseline(QStringLiteral("quick/vanilla/cc-delete-confirm"), awaitPopupForm());
}

QQuickItem *VisualQuickTest::awaitMenuPanel()
{
    if (!QTest::qWaitFor([this] {
            songview::QuickPopupSession *session = quick_popup::popupSession(m_tab->view());
            return session && session->isOpen();
        }))
        return nullptr;
    songview::QuickPopupSession *session = quick_popup::popupSession(m_tab->view());
    QQuickItem *const overlay = session ? session->overlayRoot() : nullptr;
    if (!overlay)
        return nullptr;
    // Panels are item-children of the overlay but QObject-children of the menu
    // host, so findChild cannot reach them; scan the visual children.
    for (QQuickItem *child : overlay->childItems()) {
        if (child->objectName() == QStringLiteral("quickMenuPanelRoot"))
            return child;
    }
    return nullptr;
}

void VisualQuickTest::voicePickerBaseline()
{
    // The picker is a request-driven form, not an EditCommand; open it the way
    // a track header does, over the roll band.
    m_tab->view().requestVoicePicker(
        QStringLiteral("Track 1 instrument"), 0, m_tab->view().quickView(), [](int) {},
        songview::TimelineBand::Roll);
    expectPopupBaseline(QStringLiteral("quick/vanilla/voice-picker"), awaitPopupForm(),
                        QStringLiteral("voicePickerAccept"));
}

void VisualQuickTest::eventListBaseline()
{
    m_tab->view().setEventListVisible(true);
    checks::support::pumpQuick();
    expectBaseline(
        QStringLiteral("quick/vanilla/event-list"),
        {bandRegion(QStringLiteral("event-list.band"), songview::TimelineBand::OtherEvents),
         itemRegion(QStringLiteral("event-list.chunk"), QStringLiteral("eventListChunk")),
         itemRegion(QStringLiteral("event-list.filter"), QStringLiteral("eventListFilter"))});
}

void VisualQuickTest::automationTabsBaseline()
{
    SongView &songView = m_tab->view();
    songView.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    songView.setDrawerActivePage(EditorDrawerPage::Automations);
    checks::support::pumpQuick();
    expectBaseline(
        QStringLiteral("quick/vanilla/automation-tabs"),
        {bandRegion(QStringLiteral("automation-tabs.band"), songview::TimelineBand::Automation),
         itemRegion(QStringLiteral("automation-tabs.strip"),
                    QStringLiteral("automationParameterTabs"))});
}

int runVisualQuickCheck(QApplication &, const QStringList &qtArguments)
{
    VisualQuickTest test;
    QStringList arguments{QStringLiteral("visual-quick")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "quick.moc"
