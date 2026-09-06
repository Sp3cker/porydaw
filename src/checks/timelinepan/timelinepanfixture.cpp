#include "checks/timelinepan/timelinepanfixture.h"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QImage>
#include <QPoint>
#include <QPointF>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtTest>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

#include <cmath>
#include <cstdint>
#include <memory>
#include <optional>
#include <utility>

namespace {

constexpr qreal kCameraTolerance = 0.01;
constexpr uint8_t kVolumeController = 7;
constexpr QPoint kLegacyPanPixelDelta{-8, 0};

bool closeEnough(qreal actual, qreal expected)
{
    return std::abs(actual - expected) <= kCameraTolerance;
}

} // namespace

namespace checks::timelinepan {

TimelinePanFixture::TimelinePanFixture(const QString &projectRoot, const QString &songLabel)
    : m_projectRoot(projectRoot)
    , m_songLabel(songLabel)
{}

TimelinePanFixture::~TimelinePanFixture()
{
    cleanup();
}

bool TimelinePanFixture::load(QString &error)
{
    std::unique_ptr<checks::LoadedSong> loaded =
        checks::LoadedSong::load(m_projectRoot, m_songLabel, error);
    if (!loaded)
        return false;

    const std::optional<SongName> name = SongName::create(m_songLabel);
    if (!name) {
        error = QStringLiteral("could not create timeline-pan song name");
        return false;
    }

    m_bank = {};
    m_bank.voices[0].type = VOICE_DIRECTSOUND;
    m_bank.voices[1].type = VOICE_SQUARE_1;
    m_bank.voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    m_bank.voices[3].type = VOICE_NOISE;

    m_tab = std::make_unique<SongTab>(*name);
    m_tab->resize(1280, 800);
    m_tab->setSampleRate(48000.0);

    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("timeline-pan-check"), QString());
    if (!identity) {
        error = QStringLiteral("could not create timeline-pan voicegroup identity");
        return false;
    }

    m_tab->applyMidiStage(loaded->songInfo(), loaded->document().smf(),
                          track_limits::kHardwareCapacity);
    if (!m_tab->presentationError().isEmpty()) {
        error = m_tab->presentationError();
        return false;
    }
    m_tab->applyBankView(LoadedBankView{*identity, borrowVoicegroupLease(&m_bank), QString()});
    m_tab->applyVoicegroupBound(*identity);

    SongView &songView = view();
    songView.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    songView.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    songView.setEditorTimeZoom(640.0);
    return true;
}

void TimelinePanFixture::show()
{
    m_tab->show();
    checks::support::pumpQuick();
}

bool TimelinePanFixture::isReady(bool requiresExposedWindow)
{
    if (!m_tab || !m_tab->isReady())
        return false;

    songview::TimelineQuickView *const quick = view().quickView();
    if (!quick)
        return false;
    m_window = quick->quickWindow();
    if (!m_window || !m_window->isVisible())
        return false;
    if (requiresExposedWindow && !m_window->isExposed())
        return false;

    m_root = quick->rootObject();
    if (!m_root)
        return false;
    m_input = m_root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRollInput"));
    m_scene = quick->findChild<songview::TimelineQuickScene *>();
    return m_input && m_scene && m_scene->automationTextModel()->rowCount() > 0 &&
           m_scene->voiceChangesGutterTextModel()->rowCount() > 0;
}

SongView &TimelinePanFixture::view() const
{
    return m_tab->view();
}

songview::TimelineQuickScene *TimelinePanFixture::scene() const
{
    return m_scene;
}

qreal TimelinePanFixture::pan(const QPoint &pixelDelta)
{
    const qreal before = view().camera().scrollX();
    checks::events::sendWheel(*m_input, QPointF(100.0, 100.0), pixelDelta, {}, Qt::NoButton,
                              Qt::NoModifier, Qt::NoScrollPhase, false);
    return view().camera().scrollX() - before;
}

QImage TimelinePanFixture::render() const
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    return m_window ? m_window->grabWindow() : QImage();
}

QImage TimelinePanFixture::capture(QString *error) const
{
    songview::TimelineQuickView *const quick = view().quickView();
    if (!quick) {
        if (error)
            *error = QStringLiteral("timeline Quick view is unavailable");
        return {};
    }
    return checks::support::captureQuickBand(view(), quick->geometry(), error);
}

bool TimelinePanFixture::setSelection(uint64_t endTick)
{
    const int primaryTrack = view().selectionModel().primaryTrack();
    if (primaryTrack < 0 || primaryTrack >= m_tab->document().engineTrackCount() ||
        primaryTrack >= track_limits::kHardwareCapacity) {
        return false;
    }

    songview::EditorSelectionModel::TimeSelection selection;
    selection.endTick = endTick;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes = {{primaryTrack, kVolumeController}};
    selection.tempo = true;
    view().selectionModel().setTimeSelection(std::move(selection));
    return true;
}

bool TimelinePanFixture::measureSelectedPan(uint64_t beats, qint64 *elapsedMilliseconds,
                                            QString *error)
{
    if (!m_tab->timeline()) {
        if (error)
            *error = QStringLiteral("timeline is unavailable");
        return false;
    }
    if (!setSelection(beats * m_tab->timeline()->ticksPerBeat)) {
        if (error)
            *error = QStringLiteral("primary track cannot host the volume-controller lane");
        return false;
    }
    if (render().isNull()) {
        if (error)
            *error = QStringLiteral("selection render produced no image");
        return false;
    }

    QElapsedTimer timer;
    timer.start();
    const qreal delta = pan(kLegacyPanPixelDelta);
    const QImage rendered = render();
    *elapsedMilliseconds = timer.elapsed();

    if (!closeEnough(delta, 8.0)) {
        if (error)
            *error = QStringLiteral("wheel did not pan the real camera");
        return false;
    }
    if (rendered.isNull()) {
        if (error)
            *error = QStringLiteral("pan render produced no image");
        return false;
    }
    return true;
}

void TimelinePanFixture::cleanup()
{
    if (m_window) {
        QTest::keyClick(m_window, Qt::Key_Escape);
        if (QQuickItem *const grabber = m_window->mouseGrabberItem())
            grabber->ungrabMouse();
    }

    if (m_tab)
        m_tab->close();
    m_input = nullptr;
    m_scene = nullptr;
    m_root.clear();
    m_window.clear();
    m_tab.reset();
    m_bank = {};
}

} // namespace checks::timelinepan
