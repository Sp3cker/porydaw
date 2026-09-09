#include "checks/trackheaders/tst_trackheaders.h"

#include <QtTest>

#include <QCoreApplication>
#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickWindow>

#include <algorithm>
#include <memory>
#include <utility>

#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "checks/trackheaders/trackheaderoracles.h"
#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "project/voicegroupsource.h"
#include "ui/activity/trackactivity.h"
#include "ui/songtab.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"

namespace {

constexpr int kViewWidth = 1280;
constexpr int kViewHeight = 800;
constexpr int kHeaderLeft = 64;
constexpr int kHeaderTop = 96;
constexpr int kHeaderWidth = 360;
constexpr int kVisibleRows = 2;
constexpr double kSampleRate = 48000.0;

QVariant rowData(const songview::TrackHeaderModel &model, int row, int role)
{
    return model.data(model.index(row, 0), role);
}

std::vector<int> tracksIn(const MidiTimeline &timeline)
{
    std::vector<int> tracks;
    for (int track = 0; track < 16; ++track) {
        if (timeline.tracks[track].used)
            tracks.push_back(track);
    }
    return tracks;
}

} // namespace

TrackHeadersFixture::TrackHeadersFixture(QString projectRoot, QString songLabel)
    : m_projectRoot(std::move(projectRoot))
    , m_songLabel(std::move(songLabel))
{}

TrackHeadersFixture::~TrackHeadersFixture()
{
    close();
}

bool TrackHeadersFixture::create(QString &error)
{
    m_fixture = checks::ProjectFixture::copyOf(m_projectRoot, error);
    if (!m_fixture)
        return false;

    const std::unique_ptr<checks::LoadedSong> loaded =
        checks::LoadedSong::load(m_fixture->root(), m_songLabel, error);
    if (!loaded)
        return false;
    const std::optional<SongName> name = SongName::create(m_songLabel);
    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("trackheaders-test"), QString());
    if (!name || !identity) {
        error = QStringLiteral("TrackHeaders fixture identities are invalid");
        return false;
    }

    m_bank = std::make_unique<LoadedVoiceGroup>();
    m_bank->voices[0].type = VOICE_DIRECTSOUND;
    m_bank->voices[1].type = VOICE_SQUARE_1;
    m_bank->voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    m_bank->voices[3].type = VOICE_NOISE;

    auto candidate = std::make_unique<SongTab>(std::move(*name));
    candidate->resize(kViewWidth, kViewHeight);
    candidate->setSampleRate(kSampleRate);
    candidate->applyMidiStage(loaded->songInfo(), loaded->document().smf(),
                              track_limits::kHardwareCapacity);
    if (!candidate->presentationError().isEmpty()) {
        error = candidate->presentationError();
        return false;
    }
    candidate->applyBankView(
        LoadedBankView{*identity, borrowVoicegroupLease(m_bank.get()), QString()});
    candidate->applyVoicegroupBound(*identity);
    if (!candidate->isReady()) {
        error = QStringLiteral("TrackHeaders SongTab did not reach ready state");
        return false;
    }

    SongView &songView = candidate->view();
    m_headers =
        songView.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"));
    m_quick = songView.quickView();
    m_window = m_quick ? m_quick->quickWindow() : nullptr;
    m_root = m_quick ? m_quick->rootObject() : nullptr;
    if (!m_headers || !m_quick || !m_window || !m_root) {
        error = QStringLiteral("SongTab did not expose the track-header Quick host");
        return false;
    }

    m_input = m_root->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineTrackHeadersInput"));
    m_band = m_root->findChild<QQuickItem *>(QStringLiteral("timelineQuickTrackHeaders"));
    m_scrollbar = m_root->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderScrollBar"));
    m_thumb = m_root->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderScrollThumb"));
    m_rename = m_root->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderRename"));
    m_marker = m_root->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderReorderMarker"));
    m_rows = m_root->findChild<QObject *>(QStringLiteral("timelineTrackHeaderRows"));
    if (!m_input || !m_band || !m_scrollbar || !m_thumb || !m_rename || !m_marker || !m_rows) {
        error = QStringLiteral("track-header Quick surface lacks a required named object");
        return false;
    }

    candidate->show();
    if (!QTest::qWaitFor([this] {
            return m_window && m_window->isVisible() && m_window->isExposed() && m_input &&
                   m_input->window() == m_window && !m_input->bounds().isEmpty();
        })) {
        error =
            QStringLiteral("TrackHeaders Quick window did not become exposed with an input host");
        return false;
    }

    const int height = m_headers->rowHeight();
    if (height <= 0) {
        error = QStringLiteral("TrackHeaders model published a nonpositive row height");
        return false;
    }
    m_isolatedBandRect = QRect{kHeaderLeft, kHeaderTop, kHeaderWidth, height * kVisibleRows};
    songview::TimelineBandLayout layout = songView.timelineBandLayout();
    for (auto &geometry : layout.bands)
        geometry.reset();
    layout.geometry(songview::TimelineBand::TrackHeaders) =
        songview::TimelineBandGeometry{m_isolatedBandRect, QRect()};
    m_quick->setBandLayout(std::move(layout));
    checks::support::pumpQuick();
    m_quick->syncAppearance();
    checks::support::pumpQuick();
    TrackActivity activity;
    m_headers->rebuild(activity, true);
    checks::support::pumpQuick();

    const std::shared_ptr<const MidiTimeline> timeline = candidate->timeline();
    if (!timeline) {
        error = QStringLiteral("TrackHeaders SongTab lost its timeline");
        return false;
    }
    m_tracks = tracksIn(*timeline);
    if (m_tracks.size() < 2 || !candidate->document().canAddTrack()) {
        error = QStringLiteral(
            "Route 101 fixture lacks the header tracks or add capacity required by this test");
        return false;
    }
    m_sourceTrack = m_tracks.front();
    m_selectionTrack = m_tracks[1];
    m_reorderTargetTrack = m_tracks.back();
    for (const int track : m_tracks) {
        if (songView.currentProgram(track) >= 0) {
            m_voiceTrack = track;
            break;
        }
    }
    if (m_voiceTrack < 0) {
        error = QStringLiteral("Route 101 fixture lacks a track with a current program");
        return false;
    }
    m_tab = std::move(candidate);
    return true;
}

bool TrackHeadersFixture::acquireInputFocus(QString &error)
{
    if (!view().focusTimelineBand(songview::TimelineBand::TrackHeaders, Qt::OtherFocusReason)) {
        error = QStringLiteral("TrackHeaders Quick input could not request focus");
        return false;
    }
    if (!QTest::qWaitFor([this] {
            return m_window && m_input && QGuiApplication::focusWindow() == m_window &&
                   QGuiApplication::focusObject() == m_input && m_input->hasActiveFocus();
        })) {
        error = QStringLiteral("TrackHeaders Quick input did not receive native window focus");
        return false;
    }
    return true;
}

void TrackHeadersFixture::close()
{
    m_rows.clear();
    m_marker.clear();
    m_rename.clear();
    m_thumb.clear();
    m_scrollbar.clear();
    m_band.clear();
    m_root.clear();
    m_window.clear();
    m_input.clear();
    m_quick.clear();
    m_headers.clear();
    if (m_tab) {
        m_tab->close();
        QCoreApplication::sendPostedEvents();
        QCoreApplication::processEvents();
    }
    m_tab.reset();
    m_bank.reset();
    m_fixture.reset();
}

SongTab &TrackHeadersFixture::tab() noexcept
{
    return *m_tab;
}
SongView &TrackHeadersFixture::view() noexcept
{
    return m_tab->view();
}
songview::TrackHeaderModel &TrackHeadersFixture::headers() noexcept
{
    return *m_headers;
}
songview::TimelineQuickView &TrackHeadersFixture::quick() noexcept
{
    return *m_quick;
}
songview::TimelineInputItem &TrackHeadersFixture::input() noexcept
{
    return *m_input;
}
QQuickWindow &TrackHeadersFixture::window() noexcept
{
    return *m_window;
}
QQuickItem &TrackHeadersFixture::root() noexcept
{
    return *m_root;
}
QQuickItem &TrackHeadersFixture::band() noexcept
{
    return *m_band;
}
QQuickItem &TrackHeadersFixture::scrollbar() noexcept
{
    return *m_scrollbar;
}
QQuickItem &TrackHeadersFixture::thumb() noexcept
{
    return *m_thumb;
}
QQuickItem &TrackHeadersFixture::rename() noexcept
{
    return *m_rename;
}
QQuickItem &TrackHeadersFixture::marker() noexcept
{
    return *m_marker;
}
QObject &TrackHeadersFixture::rows() noexcept
{
    return *m_rows;
}
const std::vector<int> &TrackHeadersFixture::tracks() const noexcept
{
    return m_tracks;
}
int TrackHeadersFixture::sourceTrack() const noexcept
{
    return m_sourceTrack;
}
int TrackHeadersFixture::selectionTrack() const noexcept
{
    return m_selectionTrack;
}
int TrackHeadersFixture::voiceTrack() const noexcept
{
    return m_voiceTrack;
}
int TrackHeadersFixture::reorderTargetTrack() const noexcept
{
    return m_reorderTargetTrack;
}
int TrackHeadersFixture::rowHeight() const noexcept
{
    return m_headers->rowHeight();
}
QRect TrackHeadersFixture::isolatedBandRect() const noexcept
{
    return m_isolatedBandRect;
}

std::optional<int> TrackHeadersFixture::rowForTrack(int track) const
{
    return trackheaders_test::rowForTrack(*m_headers, track);
}

std::optional<int> TrackHeadersFixture::addTrackRow() const
{
    return trackheaders_test::addTrackRow(*m_headers);
}

std::optional<QPointF> TrackHeadersFixture::pointForRow(int row, const QRectF &localRect) const
{
    const QRectF target =
        localRect.translated(0.0, row * m_headers->rowHeight() - m_headers->scrollY());
    if (localRect.isEmpty() || !m_input->bounds().contains(target))
        return std::nullopt;
    return target.center();
}

std::optional<QPointF> TrackHeadersFixture::titlePoint(int row) const
{
    return pointForRow(
        row, rowData(*m_headers, row, songview::TrackHeaderModel::TitleRectRole).toRectF());
}

std::optional<QPointF> TrackHeadersFixture::voicePoint(int row) const
{
    return pointForRow(row, m_headers->voiceLineRect());
}

std::optional<QPointF> TrackHeadersFixture::mutePoint(int row) const
{
    return pointForRow(row, m_headers->muteButtonRect());
}

std::optional<QPointF> TrackHeadersFixture::soloPoint(int row) const
{
    return pointForRow(row, m_headers->soloButtonRect());
}

QImage TrackHeadersFixture::captureBand(QString &error)
{
    return checks::support::captureQuickBand(view(), m_isolatedBandRect, &error);
}

bool TrackHeadersFixture::rebuild(QString &error)
{
    checks::support::pumpQuick();
    if (QTest::qWaitFor([this] { return m_tab && m_tab->timeline() && m_headers; }))
        return true;
    error = QStringLiteral("SongTab did not rebuild its timeline after the header transaction");
    return false;
}
