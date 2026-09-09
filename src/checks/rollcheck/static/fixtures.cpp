#include "checks/rollcheck/static/fixtures.h"

#include <QCoreApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSize>
#include <QtTest>

#include "checks/support/editorrig.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songtab.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/eventlistcontroller.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeruler.h"
#include "ui/songview/trackheadermodel.h"

namespace checks::rollcheck::staticcheck {

bool Raster::valid() const
{
    return !image.isNull() && image.width() > 8 && image.height() > 8;
}

QRgb Raster::at(qreal logicalX, qreal logicalY) const
{
    return image.pixel(std::clamp(qRound(logicalX * dpr), 0, image.width() - 1),
                       std::clamp(qRound(logicalY * dpr), 0, image.height() - 1));
}

int Raster::deviceX(qreal logicalX) const
{
    return qRound(logicalX * dpr);
}

Raster captureRuler(SongView &view)
{
    const auto band = view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    if (!band)
        return {};
    QImage image = checks::support::captureQuickBand(view, band->rect);
    const qreal dpr = image.devicePixelRatio();
    return {std::move(image), dpr > 0.0 ? dpr : 1.0};
}

int rulerBandHeight(const SongView &view)
{
    const auto band = view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    return band ? band->rect.height() : 0;
}

qreal rulerPlotOffset(const SongView &view)
{
    const auto band = view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    return band ? band->plotRect.x() - band->rect.x() : 0.0;
}

CameraFixture::CameraFixture(QString projectRoot, QString songLabel)
    : m_projectRoot(std::move(projectRoot))
    , m_songLabel(std::move(songLabel))
{}

CameraFixture::~CameraFixture()
{
    m_host.reset();
    m_tab.reset();
    m_bank.reset();
    m_project.reset();
}

bool CameraFixture::create(QString &error)
{
    m_project = checks::ProjectFixture::copyOf(m_projectRoot, error);
    if (!m_project)
        return false;
    const std::unique_ptr<checks::LoadedSong> loaded =
        checks::LoadedSong::load(m_project->root(), m_songLabel, error);
    if (!loaded)
        return false;
    const auto name = SongName::create(m_songLabel);
    if (!name) {
        error = QStringLiteral("static camera probe song name was rejected");
        return false;
    }
    m_bank = std::make_unique<LoadedVoiceGroup>();
    m_bank->voices[0].type = VOICE_DIRECTSOUND;
    m_bank->voices[1].type = VOICE_SQUARE_1;
    m_bank->voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    m_bank->voices[3].type = VOICE_NOISE;
    m_tab = std::make_unique<SongTab>(*name);
    m_tab->setSampleRate(48000.0);
    m_tab->applyMidiStage(loaded->songInfo(), loaded->document().smf(),
                          track_limits::kHardwareCapacity);
    if (!m_tab->presentationError().isEmpty()) {
        error = m_tab->presentationError();
        return false;
    }
    const auto bankId =
        VoicegroupId::create(QStringLiteral("sound/voicegroups/rollcheck.inc"), QString());
    if (!bankId) {
        error = QStringLiteral("static camera probe voicegroup identity was rejected");
        return false;
    }
    m_tab->applyBankView(LoadedBankView{*bankId, borrowVoicegroupLease(m_bank.get()), QString()});
    m_tab->applyVoicegroupBound(*bankId);
    m_host = std::make_unique<checks::QuickSceneHost>(m_tab->view(), QSize(1280, 800));
    if (!checks::support::showQuickViewport(m_tab->view(), QSize(1280, 800))) {
        error = QStringLiteral("static camera probe could not expose the Quick viewport");
        return false;
    }
    if (!m_tab->isReady()) {
        error = QStringLiteral("static camera probe tab did not become ready");
        return false;
    }
    SongView &songView = m_tab->view();
    auto *quick =
        songView.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    m_roll = songView.findChild<songview::PianoRoll *>();
    m_rollInput =
        root ? root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRollInput"))
             : nullptr;
    m_gutterInput = root ? root->findChild<songview::TimelineInputItem *>(
                               QStringLiteral("timelineRollGutterInput"))
                         : nullptr;
    m_track = songView.selectionModel().primaryTrack();
    if (!m_roll || !m_rollInput || !m_gutterInput || !m_tab->timeline() ||
        m_tab->document().engineTrackCount() <= m_track) {
        error = QStringLiteral("static camera probe has no live piano-roll surfaces");
        return false;
    }
    // Quick-window geometry reaches the canvas items asynchronously.
    if (!QTest::qWaitFor([this] { return !m_rollInput->bounds().isEmpty(); })) {
        error = QStringLiteral("static camera probe Quick roll geometry did not settle");
        return false;
    }
    return true;
}

SongTab *CameraFixture::tab() const noexcept
{
    return m_tab.get();
}
SongView *CameraFixture::view() const noexcept
{
    return m_tab ? &m_tab->view() : nullptr;
}
songview::PianoRoll *CameraFixture::roll() const noexcept
{
    return m_roll;
}
songview::TimelineInputItem *CameraFixture::rollInput() const noexcept
{
    return m_rollInput;
}
songview::TimelineInputItem *CameraFixture::gutterInput() const noexcept
{
    return m_gutterInput;
}
int CameraFixture::track() const noexcept
{
    return m_track;
}

GateFixture::GateFixture() = default;

GateFixture::~GateFixture()
{
    if (m_host) {
        m_host.reset();
        QCoreApplication::processEvents();
    }
}

bool GateFixture::create(QString &error)
{
    const auto name = SongName::create(QStringLiteral("mus_loading_ruler_probe"));
    if (!name) {
        error = QStringLiteral("loading probe song name was rejected");
        return false;
    }
    m_tab = std::make_unique<SongTab>(*name);
    m_tab->setSampleRate(48000.0);
    m_host = std::make_unique<checks::QuickSceneHost>(m_tab->view(), QSize(1280, 800));
    if (!checks::support::showQuickViewport(m_tab->view(), QSize(1280, 800))) {
        error = QStringLiteral("loading probe could not expose the Quick viewport");
        return false;
    }
    SongView &view = m_tab->view();
    auto *quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    QQuickItem *const root = quick ? quick->rootObject() : nullptr;
    m_rollInput =
        root ? root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRollInput"))
             : nullptr;
    m_rulerInput =
        root ? root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRulerInput"))
             : nullptr;
    m_horizontalScrollbar =
        root ? root->findChild<QQuickItem *>(QStringLiteral("timelineHorizontalScrollBar"))
             : nullptr;
    m_controls =
        root ? root->findChild<QQuickItem *>(QStringLiteral("timelineRulerControls")) : nullptr;
    m_divisionControl =
        root ? root->findChild<QQuickItem *>(QStringLiteral("timelineRulerDivisionControl"))
             : nullptr;
    m_feelControl =
        root ? root->findChild<QQuickItem *>(QStringLiteral("timelineRulerFeelControl")) : nullptr;
    m_toolTip =
        root ? root->findChild<QQuickItem *>(QStringLiteral("timelineRulerToolTip")) : nullptr;
    m_ruler =
        m_rulerInput ? dynamic_cast<songview::TimeRuler *>(m_rulerInput->interaction()) : nullptr;
    m_headers = view.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"),
                                                             Qt::FindDirectChildrenOnly);
    m_headersInput = root ? root->findChild<songview::TimelineInputItem *>(
                                QStringLiteral("timelineTrackHeadersInput"))
                          : nullptr;
    m_eventListController = view.eventListController();
    m_drawer = view.editorDrawer();
    if (!m_rollInput || !m_rulerInput || !m_horizontalScrollbar || !m_controls ||
        !m_divisionControl || !m_feelControl || !m_toolTip || !m_ruler || !m_headers ||
        !m_headersInput || !m_eventListController || !m_drawer) {
        error = QStringLiteral("loading probe has incomplete live coverage surfaces");
        return false;
    }
    const auto *vertical = root->findChild<QQuickItem *>(QStringLiteral("timelineRollScrollBar"));
    if (!vertical || !QTest::qWaitFor([this, vertical] {
            return m_horizontalScrollbar->isVisible() && vertical->isVisible();
        })) {
        error = QStringLiteral("loading probe Quick scrollbar geometry did not settle");
        return false;
    }
    return true;
}

SongTab *GateFixture::tab() const noexcept
{
    return m_tab.get();
}
SongView *GateFixture::view() const noexcept
{
    return m_tab ? &m_tab->view() : nullptr;
}

QQuickWindow *GateFixture::window() const noexcept
{
    return m_host ? &m_host->window() : nullptr;
}
songview::TimelineInputItem *GateFixture::rollInput() const noexcept
{
    return m_rollInput;
}
songview::TimelineInputItem *GateFixture::rulerInput() const noexcept
{
    return m_rulerInput;
}
QQuickItem *GateFixture::horizontalScrollbar() const noexcept
{
    return m_horizontalScrollbar;
}
QQuickItem *GateFixture::controls() const noexcept
{
    return m_controls;
}
QQuickItem *GateFixture::divisionControl() const noexcept
{
    return m_divisionControl;
}
QQuickItem *GateFixture::feelControl() const noexcept
{
    return m_feelControl;
}
QQuickItem *GateFixture::toolTip() const noexcept
{
    return m_toolTip;
}
songview::TimeRuler *GateFixture::ruler() const noexcept
{
    return m_ruler;
}
songview::TrackHeaderModel *GateFixture::headers() const noexcept
{
    return m_headers;
}
songview::TimelineInputItem *GateFixture::headersInput() const noexcept
{
    return m_headersInput;
}
EventListController *GateFixture::eventListController() const noexcept
{
    return m_eventListController;
}
EditorDrawer *GateFixture::drawer() const noexcept
{
    return m_drawer;
}

} // namespace checks::rollcheck::staticcheck
