#include "checks/clipboard/clipcheck_test.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QtTest>

#include <memory>
#include <optional>
#include <utility>

extern "C" {
#include "voicegroup_loader.h"
}

#include "checks/support/quickframebuffer.h"
#include "core/smf.h"
#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "project/voicegroupsource.h"
#include "ui/songtab.h"
#include "ui/songview/editactions.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

namespace checks::clipboard {

namespace {

constexpr int kViewWidth = 1280;
constexpr int kViewHeight = 800;
constexpr double kSampleRate = 48000.0;

} // namespace

ClipTabRig::ClipTabRig()
    : m_temporary(std::make_unique<QTemporaryDir>())
    , m_bank(std::make_unique<LoadedVoiceGroup>())
{}

ClipTabRig::~ClipTabRig()
{
    m_tab.reset();
    m_bank.reset();
    m_temporary.reset();
}

std::unique_ptr<ClipTabRig> ClipTabRig::create(uint16_t ticksPerBeat, QString &error)
{
    error.clear();
    auto rig = std::unique_ptr<ClipTabRig>(new ClipTabRig);
    if (!rig->m_temporary->isValid()) {
        error = QStringLiteral("could not create temporary clip transaction directory");
        return nullptr;
    }

    std::optional<SongName> name = SongName::create(QStringLiteral("clipboard-check"));
    if (!name) {
        error = QStringLiteral("could not create synthetic song name");
        return nullptr;
    }

    auto smf = SmfFile{};
    smf.format = 1;
    smf.division = ticksPerBeat;
    smf.tracks.push_back({{}, 0});

    auto info = SongInfo{};
    info.label = QStringLiteral("clipboard-check");
    info.midPath = rig->m_temporary->filePath(QStringLiteral("clipboard-check.mid"));
    info.hasMid = true;

    rig->m_tab = std::make_unique<SongTab>(std::move(*name));
    rig->m_tab->resize(kViewWidth, kViewHeight);
    rig->m_tab->setSampleRate(kSampleRate);
    rig->m_tab->applyMidiStage(std::move(info), std::move(smf), track_limits::kHardwareCapacity);
    if (!rig->m_tab->presentationError().isEmpty()) {
        error = rig->m_tab->presentationError();
        return nullptr;
    }

    rig->m_bank->voices[0].type = VOICE_DIRECTSOUND;
    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("clipboard-check"), QString());
    if (!identity) {
        error = QStringLiteral("could not create synthetic voicegroup identity");
        return nullptr;
    }
    rig->m_tab->applyBankView(
        LoadedBankView{*identity, borrowVoicegroupLease(rig->m_bank.get()), QString()});
    rig->m_tab->applyVoicegroupBound(*identity);
    if (!rig->m_tab->isReady()) {
        error = QStringLiteral("synthetic song tab did not become ready");
        return nullptr;
    }
    auto *const editActions = new songview::EditActions(&rig->m_tab->view());
    editActions->rebind(&rig->m_tab->view());

    rig->m_tab->show();
    QCoreApplication::processEvents();
    checks::support::pumpQuick();
    SongView &view = rig->view();

    songview::TimelineQuickView *const quick = view.quickView();
    if (!quick || !quick->rootObject()) {
        error = QStringLiteral("song tab did not expose the timeline Quick root");
        return nullptr;
    }
    rig->m_roll = quick->rootObject()->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineRollInput"));
    if (!rig->m_roll) {
        error = QStringLiteral("song tab did not expose the timeline roll input");
        return nullptr;
    }
    // Application-focus staging: view-level keys travel the Quick window, so the
    // rig stages real roll-band focus (requestFocus plus focusWindow/focusObject
    // convergence) instead of relying on window-local scope alone.
    QQuickWindow *const quickWindow = quick->quickWindow();
    if (!quickWindow) {
        error = QStringLiteral("song tab did not expose the timeline Quick window");
        return nullptr;
    }
    rig->m_roll->requestFocus(Qt::OtherFocusReason);
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    if (!QTest::qWaitFor([quickWindow, roll = rig->m_roll] {
            return QGuiApplication::focusWindow() == quickWindow &&
                   QGuiApplication::focusObject() == roll && roll->hasActiveFocus();
        })) {
        error = QStringLiteral("song tab roll input did not take application focus");
        return nullptr;
    }

    return rig;
}

SongDocument &ClipTabRig::document() noexcept
{
    return m_tab->document();
}

SongView &ClipTabRig::view() noexcept
{
    return m_tab->view();
}

bool ClipTabRig::sendRollKey(int key, Qt::KeyboardModifiers modifiers)
{
    if (!m_roll)
        return false;
    QKeyEvent press(QEvent::KeyPress, key, modifiers);
    QCoreApplication::sendEvent(m_roll, &press);
    QKeyEvent release(QEvent::KeyRelease, key, modifiers);
    QCoreApplication::sendEvent(m_roll, &release);
    return true;
}

bool ClipTabRig::sendViewKey(int key, Qt::KeyboardModifiers modifiers)
{
    if (!m_tab)
        return false;
    // SongView is a QObject now, so view-level keys travel the normal Quick/host
    // path: real QTest delivery into the active Quick window, where the focused
    // band policy or the focus-less window route claims them.
    songview::TimelineQuickView *const quick = view().quickView();
    QQuickWindow *const window = quick ? quick->quickWindow() : nullptr;
    if (!window)
        return false;
    QTest::keyClick(window, static_cast<Qt::Key>(key), modifiers);
    return true;
}

std::vector<NoteSpec> notesOf(const SongDocument &document, int engineTrack)
{
    std::vector<NoteSpec> result;
    for (const DocNote &note : document.notesForTrack(engineTrack))
        result.push_back({note.tick, note.key, note.duration, note.velocity});
    return result;
}

std::vector<LaneSpec> lanesOf(const SongDocument &document, int engineTrack, uint8_t cc)
{
    std::vector<LaneSpec> result;
    for (const DocLanePoint &point : document.lanePoints(engineTrack, cc))
        result.push_back({point.tick, point.value});
    return result;
}

std::vector<TempoSpec> tempoOf(const SongDocument &document)
{
    std::vector<TempoSpec> result;
    for (const TempoPoint &point : document.tempoPoints())
        result.push_back({point.tick, point.microsecondsPerQuarterNote});
    return result;
}

std::vector<NoteId> noteIds(const SongDocument &document, int engineTrack)
{
    std::vector<NoteId> ids;
    for (const DocNote &note : document.notesForTrack(engineTrack))
        ids.push_back(note.noteId);
    return ids;
}

void ClipCheckTest::init()
{
    m_clipboard = std::make_unique<clipcheck_support::ClipboardStateGuard>();
    m_clipboard->clear();
}

void ClipCheckTest::cleanup()
{
    m_clipboard.reset();
}

} // namespace checks::clipboard

int runClipCheck(const QStringList &qtArguments)
{
    checks::clipboard::ClipCheckTest test;
    QStringList arguments{QStringLiteral("clipcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
