// Visual baseline check for the production Qt Quick timeline surfaces.
// Captures the real SongTab Quick window framebuffer and freezes semantic
// region bounds plus rendered pixels through checks::visual::compare. IDs and
// region names are semantic — never QWidget/QQuickItem class names — so a
// future Swift/QtBridge adapter can supply the same bounds.

#include "checks/visual/visualquick.h"

#include <QApplication>
#include <QCoreApplication>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QString>
#include <QtTest>

#include <cstring>
#include <initializer_list>
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

// One row of a surface's region table: the frozen semantic name plus the
// production object name whose scene bounds it must cover. Band regions stay
// out of the tables — they are surface geometry, not named items.
struct ItemRegionSpec {
    const char *name;
    const char *objectName;
};

// Appends a surface's item regions in table order, resolving each entry
// through the shared item-region helper. `root` is the scenario's scene root.
void appendItemRegions(QList<checks::visual::Region> &regions, QQuickItem *root,
                       std::initializer_list<ItemRegionSpec> specs)
{
    regions.reserve(regions.size() + static_cast<qsizetype>(specs.size()));
    for (const ItemRegionSpec &spec : specs) {
        regions.push_back(checks::visual::quickItemRegion(QString::fromLatin1(spec.name), root,
                                                          QString::fromLatin1(spec.objectName)));
    }
}

// Raw C voicegroup storage for the drum-keyboard fixture. A LoadedVoiceGroup
// borrows the tone tables it points into, so they all live in one local the
// caller owns; buildDrumBank() only describes them.
struct DrumBankStorage {
    ToneData tones[VOICEGROUP_SIZE]{};
    char names[VOICEGROUP_SIZE][VG_VOICE_NAME_LEN]{};
    ToneData *subGroups[1]{};
    char (*subGroupNames[1])[VG_VOICE_NAME_LEN]{};

    // One keysplit voice resolving to a subgroup that holds `noiseKey` as an
    // unlabeled noise pad, `namedKey` as "Kick" and `longNameKey` as a pad
    // whose label must elide.
    LoadedVoiceGroup buildDrumBank(int noiseKey, int namedKey, int longNameKey)
    {
        tones[noiseKey].type = VOICE_NOISE;
        std::strncpy(names[namedKey], "Kick", VG_VOICE_NAME_LEN - 1);
        std::strncpy(names[longNameKey], "Fixture Drum Pad With A Long Name",
                     VG_VOICE_NAME_LEN - 1);
        subGroups[0] = tones;
        subGroupNames[0] = names;
        LoadedVoiceGroup bank{};
        bank.voices[1].type = VOICE_KEYSPLIT_ALL;
        bank.voices[1].subGroup = tones;
        bank.subGroups = subGroups;
        bank.subGroupVoiceNames = subGroupNames;
        bank.subGroupCount = 1;
        bank.subGroupCapacity = 1;
        return bank;
    }
};

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
    QRect bandBounds(songview::TimelineBand band) const;
    checks::visual::Region bandRegion(const QString &name, songview::TimelineBand band) const;
    // Issues the pitch-bend EditCommand and returns the popup form the shared
    // session opens; null when the command is unavailable or nothing opens.
    QQuickItem *openPitchBendPopup();
    // Captures the popup form and requires a baseline match. Keyboard focus
    // parks on the steady control named here — the suite's single popup focus
    // policy — so no blinking caret or focus frame races the grab.
    void expectPopupBaseline(const QString &id, QQuickItem *form,
                             const QString &steadyFocusObjectName);
    // Clicks the row whose model text is `rowText` in an open menu panel.
    void clickMenuRow(QQuickItem *panel, const QString &rowText);

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
    // Each slot owns a fresh SongTab: slots end with a popup session still
    // open (the velocity, insert-time and time-signature prompts are never
    // accepted), swap the voicegroup, and mutate drawer, event-list and
    // selection state, so a shared fixture would leak an open session and
    // stale view state into the next scenario.
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

QRect VisualQuickTest::bandBounds(songview::TimelineBand band) const
{
    const std::optional<songview::TimelineBandGeometry> &geometry =
        m_tab->view().timelineBandLayout().geometry(band);
    return geometry ? geometry->rect : QRect{};
}

checks::visual::Region VisualQuickTest::bandRegion(const QString &name,
                                                   songview::TimelineBand band) const
{
    return {name, bandBounds(band)};
}

void VisualQuickTest::timelineRulerBaseline()
{
    QList<checks::visual::Region> regions{
        bandRegion(QStringLiteral("timeline.ruler.band"), songview::TimelineBand::Ruler)};
    appendItemRegions(regions, m_root.data(),
                      {
                          {"timeline.ruler.gutter", "timelineQuickRulerGutterChrome"},
                          {"timeline.ruler.chrome", "timelineQuickRulerChrome"},
                          {"timeline.ruler.marks", "timelineQuickRulerMarks"},
                          {"timeline.ruler.controls", "timelineRulerControls"},
                      });
    QString error;
    QVERIFY2(checks::visual::expectQuickBaseline(QStringLiteral("quick/vanilla/timeline-ruler"),
                                                 *m_window, m_root.data(), regions, &error),
             qPrintable(error));
}

void VisualQuickTest::pianoRollBaseline()
{
    QList<checks::visual::Region> regions{
        bandRegion(QStringLiteral("piano-roll.band"), songview::TimelineBand::Roll)};
    appendItemRegions(
        regions, m_root.data(),
        {
            {"piano-roll.grid.rows", "timelineQuickPianoGridRows"},
            {"piano-roll.grid.time", "timelineQuickPianoGridTime"},
            {"piano-roll.note-fills", "timelineQuickPianoNoteFills"},
            {"piano-roll.note-borders-selection", "timelineQuickPianoNoteBordersAndSelection"},
            {"piano-roll.keyboard.keys", "timelineQuickPianoKeyboardKeys"},
        });
    QString error;
    QVERIFY2(checks::visual::expectQuickBaseline(QStringLiteral("quick/vanilla/piano-roll"),
                                                 *m_window, m_root.data(), regions, &error),
             qPrintable(error));
}

void VisualQuickTest::trackHeaderBaseline()
{
    QList<checks::visual::Region> regions{
        bandRegion(QStringLiteral("track-headers.band"), songview::TimelineBand::TrackHeaders)};
    appendItemRegions(regions, m_root.data(),
                      {{"track-headers.rows", "timelineQuickTrackHeaders"}});
    QString error;
    QVERIFY2(checks::visual::expectQuickBaseline(QStringLiteral("quick/vanilla/track-headers"),
                                                 *m_window, m_root.data(), regions, &error),
             qPrintable(error));
}

void VisualQuickTest::velocityLaneBaseline()
{
    SongView &songView = m_tab->view();
    songView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    songView.setDrawerSectionHeight(EditorDrawerPage::Velocity, kVelocityLaneHeight);
    checks::support::pumpQuick();
    QList<checks::visual::Region> regions{
        bandRegion(QStringLiteral("velocity-lane.band"), songview::TimelineBand::Velocity)};
    appendItemRegions(regions, m_root.data(),
                      {
                          {"velocity-lane.axis", "timelineQuickVelocityAxis"},
                          {"velocity-lane.grid", "timelineQuickVelocityGrid"},
                          {"velocity-lane.stems", "timelineQuickVelocityStems"},
                          {"velocity-lane.nodes", "timelineQuickVelocityNodes"},
                      });
    QString error;
    QVERIFY2(checks::visual::expectQuickBaseline(QStringLiteral("quick/vanilla/velocity-lane"),
                                                 *m_window, m_root.data(), regions, &error),
             qPrintable(error));
}

void VisualQuickTest::editorDrawerBaseline()
{
    SongView &songView = m_tab->view();
    songView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    songView.setDrawerSectionHeight(EditorDrawerPage::Velocity, kVelocityLaneHeight);
    songView.setDrawerActivePage(EditorDrawerPage::Velocity);
    checks::support::pumpQuick();
    QList<checks::visual::Region> regions{bandRegion(QStringLiteral("editor-drawer.velocity-page"),
                                                     songview::TimelineBand::Velocity)};
    appendItemRegions(regions, m_root.data(),
                      {
                          {"editor-drawer.bar", "drawerBarInput"},
                          {"editor-drawer.detent", "drawerDetent"},
                          {"editor-drawer.velocity-toggle", "drawerVelocityToggle"},
                      });
    QString error;
    QVERIFY2(checks::visual::expectQuickBaseline(QStringLiteral("quick/vanilla/editor-drawer"),
                                                 *m_window, m_root.data(), regions, &error),
             qPrintable(error));
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
    DrumBankStorage storage;
    const LoadedVoiceGroup drumBank = storage.buildDrumBank(unnamedKey, namedKey, longKey);

    const LoadedVoiceGroup *const originalBank = songView.voicegroup();
    const auto restore =
        qScopeGuard([&songView, originalBank] { songView.setVoicegroup(originalBank); });
    songView.setVoicegroup(&drumBank);
    checks::support::pumpQuick();

    QList<checks::visual::Region> regions{
        bandRegion(QStringLiteral("drum-keyboard.band"), songview::TimelineBand::Roll)};
    appendItemRegions(regions, m_root.data(),
                      {{"drum-keyboard.keys", "timelineQuickPianoKeyboardKeys"}});

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
    regions.push_back({QStringLiteral("drum-keyboard.named-plate"),
                       QRect{rollRect.x() + qRound(plate.x()), rollRect.y() + qRound(plate.y()),
                             qRound(plate.width()), qRound(plate.height())}});

    QString error;
    QVERIFY2(checks::visual::expectQuickBaseline(QStringLiteral("quick/vanilla/drum-keyboard"),
                                                 *m_window, m_root.data(), regions, &error),
             qPrintable(error));
}

QQuickItem *VisualQuickTest::openPitchBendPopup()
{
    // Invoke the same semantic command the G key routes to; this is an
    // appearance check, so popup opening must not depend on desktop focus or
    // synthetic key delivery.
    m_tab->view().selectionModel().setNoteSelection({m_note.noteId});
    if (!m_tab->view().editCommandAvailable(SongView::EditCommand::PitchBend))
        return nullptr;
    m_tab->view().executeEditCommand(SongView::EditCommand::PitchBend);
    return checks::visual::awaitPopupForm(m_tab->view());
}

void VisualQuickTest::pitchBendPopupBaseline()
{
    QVERIFY(m_hasNote);
    QQuickItem *const form = openPitchBendPopup();
    QVERIFY2(form, "pitch-bend popup did not open in the Quick canvas");
    // The popup has no prompt buttons, so focus parks on its static reset
    // chrome: same policy as the prompt captures, and it keeps the graph's
    // focus frame out of the frozen pixels.
    checks::visual::steadyPopupFocus(form, QStringLiteral("pitchBendReset"));
    checks::support::pumpQuick();
    QQuickItem *const graph =
        checks::support::visualDescendant(form, QStringLiteral("pitchBendGraph"));
    QVERIFY2(graph, "pitch-bend popup lacks the pitch graph");
    QVERIFY2(!graph->hasActiveFocus(),
             "pitch-bend graph kept active focus, so its focus frame would be captured");
    const QPointF formScene = form->mapToScene(QPointF{});
    QList<checks::visual::Region> regions{
        {QStringLiteral("popup.pitch-bend.form"),
         QRect{qRound(formScene.x()), qRound(formScene.y()), qRound(form->width()),
               qRound(form->height())}},
        checks::visual::quickItemRegion(QStringLiteral("popup.pitch-bend.graph"), form,
                                        QStringLiteral("pitchBendGraph")),
    };
    QString error;
    QVERIFY2(checks::visual::expectQuickBaseline(QStringLiteral("quick/vanilla/pitch-bend-popup"),
                                                 *m_window, m_root.data(), regions, &error),
             qPrintable(error));
}

// Shared popup-form capture: the session's content item is the whole surface,
// so its scene rect is the single region. The suite's one focus policy parks
// keyboard focus on the named steady control the caller passes — an accept
// button, the confirm's resting Cancel button, the menu frame, or the
// pitch-bend reset chrome — before the grab: a blinking caret or a focused
// graph's frame would otherwise race the capture, while a parked control
// paints a fixed face.
void VisualQuickTest::expectPopupBaseline(const QString &id, QQuickItem *form,
                                          const QString &steadyFocusObjectName)
{
    QVERIFY(form);
    checks::visual::steadyPopupFocus(form, steadyFocusObjectName);
    checks::support::pumpQuick();
    const QPointF scene = form->mapToScene(QPointF{});
    QList<checks::visual::Region> regions{
        {QStringLiteral("popup.form"), QRect{qRound(scene.x()), qRound(scene.y()),
                                             qRound(form->width()), qRound(form->height())}}};
    QString error;
    QVERIFY2(checks::visual::expectQuickBaseline(id, *m_window, m_root.data(), regions, &error),
             qPrintable(error));
}

void VisualQuickTest::velocityPromptBaseline()
{
    QVERIFY(m_hasNote);
    m_tab->view().selectionModel().setNoteSelection({m_note.noteId});
    QVERIFY2(m_tab->view().editCommandAvailable(SongView::EditCommand::SetVelocity),
             "Set Velocity must be available with a note selected");
    m_tab->view().executeEditCommand(SongView::EditCommand::SetVelocity);
    expectPopupBaseline(QStringLiteral("quick/vanilla/velocity-prompt"),
                        checks::visual::awaitPopupForm(m_tab->view()),
                        QStringLiteral("noteVelocityAccept"));
}

void VisualQuickTest::insertTimePromptBaseline()
{
    QVERIFY2(m_tab->view().editCommandAvailable(SongView::EditCommand::InsertTime),
             "Insert Time must be available on a loaded timeline");
    m_tab->view().executeEditCommand(SongView::EditCommand::InsertTime);
    expectPopupBaseline(QStringLiteral("quick/vanilla/insert-time-prompt"),
                        checks::visual::awaitPopupForm(m_tab->view()),
                        QStringLiteral("insertTimeAccept"));
}

void VisualQuickTest::timeSignaturePromptBaseline()
{
    QVERIFY2(m_tab->view().editCommandAvailable(SongView::EditCommand::EditTimeSignature),
             "Edit Time Signature must be available on a loaded timeline");
    m_tab->view().executeEditCommand(SongView::EditCommand::EditTimeSignature);
    expectPopupBaseline(QStringLiteral("quick/vanilla/time-signature-prompt"),
                        checks::visual::awaitPopupForm(m_tab->view()),
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
    // Menus have no buttons; their frame is the steady chrome to park on.
    expectPopupBaseline(QStringLiteral("quick/vanilla/note-menu"),
                        checks::visual::awaitMenuPanel(songView), QStringLiteral("quickMenuFrame"));
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
    expectPopupBaseline(QStringLiteral("quick/vanilla/quick-menu-panel"),
                        checks::visual::awaitMenuPanel(m_tab->view()),
                        QStringLiteral("quickMenuFrame"));
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
    QQuickItem *const panel = checks::visual::awaitMenuPanel(songView);
    QVERIFY2(panel, "lane menu did not open");
    clickMenuRow(panel, QStringLiteral("Delete automation events"));
    // Cancel is the confirm's own resting focus (a bare Return cancels), so
    // parking there is steady and never fights the popup's queued focus.
    expectPopupBaseline(QStringLiteral("quick/vanilla/cc-delete-confirm"),
                        checks::visual::awaitPopupForm(songView), QStringLiteral("cancelButton"));
}

void VisualQuickTest::clickMenuRow(QQuickItem *panel, const QString &rowText)
{
    // Rows render inside quickMenuFrame's border as a running sum of row and
    // separator heights, so the target row's center maps through the frame.
    auto *const model =
        qobject_cast<songview::QuickMenuModel *>(panel->property("menuModel").value<QObject *>());
    QVERIFY2(model, "lane menu model is unavailable");
    const qreal rowHeight = panel->property("rowHeight").toDouble();
    const qreal separatorHeight = panel->property("separatorHeight").toDouble();
    qreal rowY = 0.0;
    bool found = false;
    for (int i = 0; i < model->count(); ++i) {
        const songview::QuickMenuItem *item = model->itemAt(i);
        if (!item)
            continue;
        if (item->separator) {
            rowY += separatorHeight;
            continue;
        }
        if (item->text == rowText) {
            found = true;
            break;
        }
        rowY += rowHeight;
    }
    QVERIFY2(found, qPrintable(QStringLiteral("lane menu lacks the '%1' row").arg(rowText)));
    QQuickItem *const frame = panel->findChild<QQuickItem *>(QStringLiteral("quickMenuFrame"));
    QVERIFY2(frame, "lane menu frame is unavailable");
    const QObject *const border = frame->property("border").value<QObject *>();
    const qreal frameBorder = border ? border->property("width").toDouble() : 1.0;
    const QPoint windowPos =
        frame->mapToScene(QPointF{frame->width() / 2.0, frameBorder + rowY + rowHeight / 2.0})
            .toPoint();
    QTest::mouseClick(m_window, Qt::LeftButton, Qt::NoModifier, windowPos);
}

void VisualQuickTest::voicePickerBaseline()
{
    // The picker is a request-driven form, not an EditCommand; open it the way
    // a track header does, over the roll band.
    SongView &songView = m_tab->view();
    songView.requestVoicePicker(
        QStringLiteral("Track 1 instrument"), 0, songView.quickView(), [](int) {},
        songview::TimelineBand::Roll);
    expectPopupBaseline(QStringLiteral("quick/vanilla/voice-picker"),
                        checks::visual::awaitPopupForm(songView),
                        QStringLiteral("voicePickerAccept"));
}

void VisualQuickTest::eventListBaseline()
{
    m_tab->view().setEventListVisible(true);
    checks::support::pumpQuick();
    QList<checks::visual::Region> regions{
        bandRegion(QStringLiteral("event-list.band"), songview::TimelineBand::OtherEvents)};
    appendItemRegions(regions, m_root.data(),
                      {
                          {"event-list.chunk", "eventListChunk"},
                          {"event-list.filter", "eventListFilter"},
                      });
    QString error;
    QVERIFY2(checks::visual::expectQuickBaseline(QStringLiteral("quick/vanilla/event-list"),
                                                 *m_window, m_root.data(), regions, &error),
             qPrintable(error));
}

void VisualQuickTest::automationTabsBaseline()
{
    SongView &songView = m_tab->view();
    songView.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    songView.setDrawerActivePage(EditorDrawerPage::Automations);
    checks::support::pumpQuick();
    QList<checks::visual::Region> regions{
        bandRegion(QStringLiteral("automation-tabs.band"), songview::TimelineBand::Automation)};
    appendItemRegions(regions, m_root.data(),
                      {{"automation-tabs.strip", "automationParameterTabs"}});
    QString error;
    QVERIFY2(checks::visual::expectQuickBaseline(QStringLiteral("quick/vanilla/automation-tabs"),
                                                 *m_window, m_root.data(), regions, &error),
             qPrintable(error));
}

int runVisualQuickCheck(QApplication &, const QStringList &qtArguments)
{
    VisualQuickTest test;
    QStringList arguments{QStringLiteral("visual-quick")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "quick.moc"
