#include "checks/pitchbend/tst_pitchbendediting.h"

#include <QCoreApplication>
#include <QEvent>
#include <QKeySequence>
#include <QWheelEvent>
#include <QtTest>

#include <algorithm>
#include <optional>
#include <utility>

#include "checks/support/eventsynth.h"
#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "project/voicegroupsource.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {
constexpr uint64_t kNoteTick = 48;
constexpr uint64_t kNoteEndTick = 144;
constexpr uint8_t kNoteKey = 60;
constexpr uint8_t kNoteVelocity = 100;

SmfEvent noteEvent(uint8_t status, uint64_t tick, uint8_t key, uint8_t velocity)
{
    SmfEvent event;
    event.status = status;
    event.tick = tick;
    event.data0 = key;
    event.data1 = velocity;
    return event;
}

SmfFile pitchBendSmf(bool unterminated, bool duplicateNote)
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    track.events = {noteEvent(0xC0, 0, 0, 0), noteEvent(0x90, kNoteTick, kNoteKey, kNoteVelocity)};
    if (duplicateNote)
        track.events.push_back(noteEvent(0x90, kNoteTick, kNoteKey, kNoteVelocity));
    if (!unterminated)
        track.events.push_back(noteEvent(0x80, kNoteEndTick, kNoteKey, 0));
    track.endTick = unterminated ? kNoteTick : kNoteEndTick + 48;
    smf.tracks.push_back(std::move(track));
    return smf;
}

QPoint graphPoint(const songview::PitchBendGraph &graph, qreal xFraction, qreal yFraction)
{
    const QRect canvas = graph.canvasRect();
    return QPoint(qRound(canvas.left() + canvas.width() * xFraction),
                  qRound(canvas.top() + canvas.height() * yFraction));
}
} // namespace

bool PitchBendFixture::setUp(bool unterminated, bool duplicateNote)
{
    m_bank = {};
    m_bank.voices[0].type = VOICE_DIRECTSOUND;
    m_bank.voices[1].type = VOICE_SQUARE_1;
    m_bank.voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    m_bank.voices[3].type = VOICE_NOISE;

    std::optional<SongName> name = SongName::create(QStringLiteral("pitch-bend-editing"));
    if (!name)
        return false;
    m_tab = std::make_unique<SongTab>(std::move(*name));
    m_tab->resize(1280, 800);
    m_tab->setSampleRate(48000.0);

    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("pitch-bend-editing-check"), QString());
    if (!identity)
        return false;
    SongInfo song;
    song.label = QStringLiteral("pitch-bend-editing");
    song.hasMid = true;
    m_tab->applyMidiStage(std::move(song), pitchBendSmf(unterminated, duplicateNote),
                          track_limits::kHardwareCapacity);
    if (!m_tab->presentationError().isEmpty())
        return false;
    m_tab->applyBankView(LoadedBankView{*identity, borrowVoicegroupLease(&m_bank), QString()});
    m_tab->applyVoicegroupBound(*identity);
    if (!QTest::qWaitFor([this] { return m_tab->isReady(); }) ||
        m_tab->voicegroupLease().get() != &m_bank) {
        return false;
    }

    const std::vector<DocNote> notes = m_tab->document().notesForTrack(0);
    if (notes.size() != (duplicateNote ? 2 : 1))
        return false;
    m_note = notes.front();
    m_endTick = m_tab->document().noteEndTick(m_note);

    SongView &songView = m_tab->view();
    songView.setEditorTimeZoom(64.0);
    songView.setScaleFold(false);
    songView.setEventListVisible(false);
    songView.selectTrack(0);
    songView.selectionModel().setNoteSelection({m_note.noteId});

    songview::TimelineQuickView *quick = songView.quickView();
    if (!quick)
        return false;
    m_timelineWindow = quick->quickWindow();
    QObject *root = quick->rootObject();
    if (!m_timelineWindow || !root)
        return false;
    m_rollInput =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRollInput"));
    if (!m_rollInput)
        return false;

    m_tab->show();
    if (!QTest::qWaitFor(
            [this] { return m_timelineWindow->isVisible() && m_timelineWindow->isExposed(); })) {
        return false;
    }
    m_rollInput->forceActiveFocus(Qt::OtherFocusReason);
    return QTest::qWaitFor([this] { return m_rollInput->hasActiveFocus(); });
}

void PitchBendFixture::tearDown()
{
    if (!m_tab) {
        m_rollInput.clear();
        m_timelineWindow.clear();
        return;
    }
    if (songview::PitchBendEditor *editor = popup(); editor && editor->isOpen())
        editor->cancelAndCloseWithoutFocus();
    drainDeferredDeletes();
    if (m_timelineWindow) {
        QTest::keyClick(m_timelineWindow, Qt::Key_Escape);
        if (QQuickItem *grabber = m_timelineWindow->mouseGrabberItem())
            grabber->ungrabMouse();
    }
    m_rollInput.clear();
    m_timelineWindow.clear();
    m_tab.reset();
}

SongTab &PitchBendFixture::tab() const
{
    Q_ASSERT(m_tab);
    return *m_tab;
}

SongView &PitchBendFixture::view() const
{
    return tab().view();
}

SongDocument &PitchBendFixture::document() const
{
    return tab().document();
}

QQuickWindow &PitchBendFixture::timelineWindow() const
{
    Q_ASSERT(m_timelineWindow);
    return *m_timelineWindow;
}

songview::TimelineInputItem &PitchBendFixture::rollInput() const
{
    Q_ASSERT(m_rollInput);
    return *m_rollInput;
}

const DocNote &PitchBendFixture::note() const
{
    return m_note;
}

uint64_t PitchBendFixture::endTick() const
{
    return m_endTick;
}

QPoint PitchBendFixture::notePoint() const
{
    const SongView &songView = view();
    const qreal dpr = rollInput().devicePixelRatio();
    const int row = songView.pitchProjection().rowForPitch(m_note.key);
    const qreal x0 = songView.camera().displayX(double(m_note.tick), 0.0, dpr);
    const qreal x1 = songView.camera().displayX(double(m_endTick), 0.0, dpr);
    const qreal y0 = songView.pitchProjection().rowTop(row, songView.camera().keyHeight(),
                                                       songView.camera().scrollY(), dpr);
    const qreal y1 = songView.pitchProjection().rowBottom(row, songView.camera().keyHeight(),
                                                          songView.camera().scrollY(), dpr);
    return QPoint(qRound((x0 + x1) / 2.0), qRound((y0 + y1) / 2.0));
}

songview::PitchBendEditor *PitchBendFixture::openPopup()
{
    view().selectionModel().setNoteSelection({m_note.noteId});
    rollInput().forceActiveFocus(Qt::OtherFocusReason);
    if (!QTest::qWaitFor([this] { return rollInput().hasActiveFocus(); }))
        return nullptr;
    // Direct item delivery does not establish native activation. Settle the
    // host before opening a transient window that must receive input.
    if (!QTest::qWaitForWindowExposed(&timelineWindow()) ||
        !QTest::qWaitForWindowActive(&timelineWindow()))
        return nullptr;
    // Deliberately hover away from the note: G must anchor the popup to the
    // selected note, never to the pointer.
    checks::events::sendMouse(rollInput(), QEvent::MouseMove, notePoint() + QPoint(300, 0),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QTest::keyClick(&timelineWindow(), Qt::Key_G);
    if (!QTest::qWaitFor([this] {
            songview::PitchBendEditor *editor = popup();
            return editor && editor->isOpen() && editor->view() && editor->view()->isVisible() &&
                   editor->view()->isExposed();
        })) {
        return nullptr;
    }
    QPointer<songview::PitchBendEditor> editor = popup();
    if (!editor || !editor->view())
        return nullptr;
    QPointer<QQuickWindow> surface = editor->view();
    if (!QTest::qWaitForWindowActive(surface.data()))
        return nullptr;
    QCoreApplication::processEvents();
    if (!editor || !editor->isOpen() || !surface || !surface->isExposed() || !surface->isActive())
        return nullptr;
    return editor;
}

songview::PitchBendEditor *PitchBendFixture::popup() const
{
    return view().findChild<songview::PitchBendEditor *>(QStringLiteral("pitchBendPopup"));
}

songview::PitchBendGraph *PitchBendFixture::graph(const QString &objectName) const
{
    songview::PitchBendEditor *editor = popup();
    if (!editor || !editor->view() || !editor->view()->rootObject())
        return nullptr;
    return qobject_cast<songview::PitchBendGraph *>(
        editor->view()->rootObject()->findChild<QQuickItem *>(objectName));
}

QQuickItem *PitchBendFixture::item(const QString &objectName) const
{
    songview::PitchBendEditor *editor = popup();
    return editor && editor->view() && editor->view()->rootObject()
               ? editor->view()->rootObject()->findChild<QQuickItem *>(objectName)
               : nullptr;
}

void PitchBendFixture::closePopupViaEscape()
{
    if (songview::PitchBendEditor *editor = popup(); editor && editor->view())
        QTest::keyClick(editor->view(), Qt::Key_Escape);
    drainDeferredDeletes();
}

void PitchBendFixture::drainDeferredDeletes()
{
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
    QCoreApplication::sendPostedEvents(nullptr, QEvent::MetaCall);
    QCoreApplication::processEvents();
}

QPoint PitchBendFixture::windowPoint(const QQuickItem &item, QPointF local) const
{
    return item.mapToScene(local).toPoint();
}

bool PitchBendFixture::stroke(songview::PitchBendGraph &target, QPoint start, QPoint finish,
                              Qt::KeyboardModifiers modifiers)
{
    QPointer<songview::PitchBendEditor> editor = popup();
    if (!editor || !editor->view())
        return false;
    QPointer<QQuickWindow> window = editor->view();
    QTest::mousePress(window.data(), Qt::LeftButton, modifiers, windowPoint(target, start));
    if (!editor || !window)
        return false;
    QTest::mouseEvent(QTest::MouseMove, window.data(), Qt::NoButton, modifiers,
                      windowPoint(target, finish));
    if (!editor || !window)
        return false;
    QTest::mouseRelease(window.data(), Qt::LeftButton, modifiers, windowPoint(target, finish));
    return editor && window;
}

bool PitchBendFixture::wheel(songview::PitchBendGraph &target, QPoint point, QPoint angleDelta)
{
    songview::PitchBendEditor *editor = popup();
    if (!editor || !editor->view())
        return false;
    QQuickWindow *window = editor->view();
    const QPointF position = target.mapToScene(point);
    QWheelEvent event(position, window->mapToGlobal(position.toPoint()), QPoint{}, angleDelta,
                      Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(window, &event);
    return true;
}

bool PitchBendFixture::scrub(QQuickItem &field, int steps, Qt::KeyboardModifiers modifiers)
{
    QPointer<songview::PitchBendEditor> editor = popup();
    if (!editor || !editor->view())
        return false;
    const qreal threshold = editor->metrics().value(QStringLiteral("scrubThreshold")).toReal();
    const int extra = modifiers & Qt::ShiftModifier ? 5 : 2;
    const QPointF start = field.boundingRect().center();
    const int pixels = qRound(threshold) + extra;
    const QPointF finish = start + QPointF(0, steps > 0 ? -pixels : pixels);
    QPointer<QQuickWindow> window = editor->view();
    QTest::mousePress(window.data(), Qt::LeftButton, modifiers, windowPoint(field, start));
    if (!editor || !window)
        return false;
    QTest::mouseEvent(QTest::MouseMove, window.data(), Qt::NoButton, modifiers,
                      windowPoint(field, finish));
    if (!editor || !window)
        return false;
    QTest::mouseRelease(window.data(), Qt::LeftButton, modifiers, windowPoint(field, finish));
    return editor && window;
}

bool PitchBendFixture::click(QQuickItem &target)
{
    songview::PitchBendEditor *editor = popup();
    if (!editor || !editor->view())
        return false;
    QTest::mouseClick(editor->view(), Qt::LeftButton, Qt::NoModifier,
                      windowPoint(target, target.boundingRect().center()));
    return true;
}

bool PitchBendFixture::sendUndo()
{
    songview::PitchBendEditor *editor = popup();
    if (!editor || !editor->view())
        return false;
    const auto bindings = QKeySequence::keyBindings(QKeySequence::Undo);
    if (bindings.empty())
        return false;
    const QKeyCombination combination = bindings.front()[0];
    QTest::keyClick(editor->view(), combination.key(), combination.keyboardModifiers());
    return true;
}

void PitchBendFixture::assertNoteSelection() const
{
    QVERIFY(view().selectionModel().noteSelection() == std::vector<NoteId>{m_note.noteId});
}

bool PitchBendFixture::hasLanePoint(uint8_t cc, uint64_t tick, int value) const
{
    const std::vector<DocLanePoint> points = document().lanePoints(0, cc);
    return std::any_of(points.cbegin(), points.cend(), [tick, value](const DocLanePoint &point) {
        return point.tick == tick && point.value == value;
    });
}

int PitchBendFixture::effectiveLaneValue(uint8_t cc, uint64_t tick, int fallback) const
{
    int value = fallback;
    for (const DocLanePoint &point : document().lanePoints(0, cc)) {
        if (point.tick > tick)
            break;
        value = point.value;
    }
    return value;
}

std::vector<DocLanePoint> PitchBendFixture::interiorPoints(uint8_t cc) const
{
    std::vector<DocLanePoint> points;
    for (const DocLanePoint &point : document().lanePoints(0, cc)) {
        if (point.tick > m_note.tick && point.tick < m_endTick)
            points.push_back(point);
    }
    return points;
}

QByteArray PitchBendFixture::smf() const
{
    return document().smf().write();
}

void PitchBendEditingTest::init()
{
    QVERIFY(m_fixture.setUp());
}

void PitchBendEditingTest::cleanup()
{
    m_fixture.tearDown();
}

songview::PitchBendEditor *PitchBendEditingTest::popup()
{
    return m_fixture.openPopup();
}

songview::PitchBendGraph *PitchBendEditingTest::pitchGraph()
{
    songview::PitchBendGraph *graph = m_fixture.graph(QStringLiteral("pitchBendGraph"));
    return graph && !graph->canvasRect().isEmpty() ? graph : nullptr;
}

songview::PitchBendGraph *PitchBendEditingTest::modGraph()
{
    songview::PitchBendGraph *graph = m_fixture.graph(QStringLiteral("modWheelGraph"));
    return graph && !graph->canvasRect().isEmpty() ? graph : nullptr;
}

bool PitchBendEditingTest::drawPitchCurve(songview::PitchBendGraph &graph)
{
    return m_fixture.stroke(graph, graphPoint(graph, 0.25, 0.70), graphPoint(graph, 0.75, 0.25));
}

bool PitchBendEditingTest::drawModCurve(songview::PitchBendGraph &graph)
{
    return m_fixture.stroke(graph, graphPoint(graph, 0.25, 0.80), graphPoint(graph, 0.75, 0.20));
}
