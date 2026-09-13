#include "checks/rollcheck/rollcheck.h"

#include <QColor>
#include <QCoreApplication>
#include <algorithm>
#include <cmath>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "core/timedefaults.h"
#include "ui/layout.h"
#include "ui/songtab.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"

namespace checks::rollcheck {

PianoRollFixture::PianoRollFixture(SongTab &tab, const QString &songLabel)
    : m_tab(tab)
    , m_songLabel(songLabel)
{}

bool PianoRollFixture::prepare()
{
    m_tab.resize(1280, 800);
    m_tab.show();
    m_tab.ensurePolished();
    QCoreApplication::processEvents();

    SongView &songView = view();
    songView.setGridMinDenom(4);
    m_pianoRollDefaultKeyHeight = layout::fontPx(1.0);
    auto *quick = songView.quickView();
    QQuickItem *const quickRoot = quick ? quick->rootObject() : nullptr;
    m_roll = songView.findChild<songview::PianoRoll *>();
    m_rollInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                  QStringLiteral("timelineRollInput"))
                            : nullptr;
    m_rollGutterInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                        QStringLiteral("timelineRollGutterInput"))
                                  : nullptr;
    const std::optional<songview::TimelineBandGeometry> geometry =
        songView.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    const QRect plotRect = geometry ? geometry->plotRect : QRect{};
    const QRect gutterRect = geometry
                                 ? QRect(geometry->rect.topLeft(),
                                         QSize(geometry->plotRect.left() - geometry->rect.left(),
                                               geometry->rect.height()))
                                 : QRect{};
    m_pianoKeyboardWidth = gutterRect.width();
    if (!m_roll || !geometry || plotRect.isEmpty() || gutterRect.isEmpty() || !m_rollInput ||
        !m_rollGutterInput)
        return false;

    m_track = songView.selectionModel().primaryTrack();
    if (document().engineTrackCount() <= m_track)
        return false;

    return !captureQuickFramebuffer().isNull();
}

SongDocument &PianoRollFixture::document() noexcept
{
    return m_tab.document();
}

SongView &PianoRollFixture::view() noexcept
{
    return m_tab.view();
}

const MidiTimeline &PianoRollFixture::timeline() const noexcept
{
    return *m_tab.timeline();
}

songview::PianoRoll &PianoRollFixture::roll() noexcept
{
    return *m_roll;
}

songview::TimelineInputItem &PianoRollFixture::rollInput() noexcept
{
    return *m_rollInput;
}

songview::TimelineInputItem &PianoRollFixture::rollGutterInput() noexcept
{
    return *m_rollGutterInput;
}

QRect PianoRollFixture::rollBandRect() const noexcept
{
    const std::optional<songview::TimelineBandGeometry> band =
        m_tab.view().timelineBandLayout().geometry(songview::TimelineBand::Roll);
    return band ? band->rect : QRect{};
}

QImage PianoRollFixture::captureQuickFramebuffer()
{
    return m_roll ? captureQuickBand(rollBandRect()) : QImage{};
}

QImage PianoRollFixture::captureQuickBand(const QRect &bandRect)
{
    return checks::support::captureQuickBand(view(), bandRect);
}

int PianoRollFixture::track() const noexcept
{
    return m_track;
}

int PianoRollFixture::pianoKeyboardWidth() const noexcept
{
    return m_pianoKeyboardWidth;
}

int PianoRollFixture::pianoRollDefaultKeyHeight() const noexcept
{
    return m_pianoRollDefaultKeyHeight;
}

const QString &PianoRollFixture::songLabel() const noexcept
{
    return m_songLabel;
}

bool PianoRollFixture::isOccupied(Tick tick, uint32_t dur, int key, bool checkAllTracks)
{
    const SongDocument &doc = document();
    const int startTrack = checkAllTracks ? 0 : m_track;
    const int endTrack = checkAllTracks ? doc.engineTrackCount() : m_track + 1;
    for (int track = startTrack; track < endTrack; ++track) {
        for (const DocNote &note : doc.notesForTrack(track)) {
            if (int(note.key) != key)
                continue;
            const uint64_t end = note.unterminated() ? CoreTimeDefaults::kNoTick
                                                     : uint64_t(note.tick) + note.duration + dur;
            if (note.tick < uint64_t(tick) + 2 * uint64_t(dur) && end > tick)
                return true;
        }
    }
    return false;
}

Cell PianoRollFixture::findFreeCell(int firstProbe, bool checkAllTracks)
{
    const SongView &songView = view();
    const songview::TimelineInputItem &pianoRoll = rollInput();
    const SnappedRows rows{songView, pianoRoll};

    for (int key = 115; key >= 24; --key) {
        const qreal top = rows.top(key);
        const qreal bottom = rows.bottom(key);
        if (top < 0 || bottom > pianoRoll.bounds().height())
            continue;
        for (int probe = firstProbe; probe < int(pianoRoll.bounds().width()) - 40; probe += 24) {
            const Tick tick = songView.grid().snapTickDown(songView.camera().tickAtContentX(probe));
            const Tick dur = songView.grid().gridTicksAt(tick);
            const int x0 = songView.camera().contentX(double(tick));
            const int x1 = songView.camera().contentX(double(tick + dur));
            const int xs =
                songView.camera().contentX(double(tick + songView.grid().snapTicksAt(tick)));
            if (x0 < 0 || x1 - x0 < 12 || xs - x0 < 8 || x1 >= int(pianoRoll.bounds().width()))
                continue;
            if (isOccupied(tick, dur, key, checkAllTracks))
                continue;
            const auto markerInSpan = [&](Tick markerTick) {
                return markerTick != CoreTimeDefaults::kNoTick && markerTick >= tick &&
                       markerTick <= uint64_t(tick) + 2 * uint64_t(dur);
            };
            if (markerInSpan(timeline().loopStartTick) || markerInSpan(timeline().loopEndTick))
                continue;
            return {tick, dur, key, QPoint((x0 + xs) / 2, rows.centerY(key))};
        }
    }
    return {};
}

std::optional<PencilPaintingFixture> makePaintingSeed(PianoRollFixture &fixture)
{
    const Cell cell = fixture.findFreeCell(40, true);
    if (cell.key < 0)
        return std::nullopt;
    fixture.document().addNote(fixture.track(), cell.tick, uint8_t(cell.key), uint32_t(cell.dur),
                               100);
    DocNote note;
    if (!fixture.document().findNote(fixture.track(), cell.tick, uint8_t(cell.key), &note))
        return std::nullopt;
    return PencilPaintingFixture{cell, note};
}

std::optional<PencilVelocityFixture> makeVelocitySeed(PianoRollFixture &fixture)
{
    const std::optional<PencilPaintingFixture> painting = makePaintingSeed(fixture);
    if (!painting)
        return std::nullopt;
    const Cell cell = fixture.findFreeCell(64, true);
    if (cell.key < 0)
        return std::nullopt;
    fixture.document().addNote(fixture.track(), cell.tick, uint8_t(cell.key), uint32_t(cell.dur),
                               73);
    DocNote note;
    if (!fixture.document().findNote(fixture.track(), cell.tick, uint8_t(cell.key), &note))
        return std::nullopt;
    return PencilVelocityFixture{painting->a, cell, painting->noteA, note};
}

std::optional<ResizeFixture> makeResizeSeed(PianoRollFixture &fixture)
{
    const Cell cell = fixture.findFreeCell(88, true);
    if (cell.key < 0)
        return std::nullopt;
    fixture.document().addNote(fixture.track(), cell.tick, uint8_t(cell.key), uint32_t(cell.dur),
                               100);
    DocNote note;
    if (!fixture.document().findNote(fixture.track(), cell.tick, uint8_t(cell.key), &note))
        return std::nullopt;
    return ResizeFixture{cell, fixture.view().grid().snapTicksAt(cell.tick)};
}

qreal SnappedRows::dpr() const
{
    return roll.devicePixelRatio();
}

qreal SnappedRows::pixel() const
{
    return 1.0 / dpr();
}

qreal SnappedRows::edge(int row) const
{
    return std::round((row * view.camera().keyHeight() - view.camera().scrollY()) * dpr()) / dpr();
}

qreal SnappedRows::top(int key) const
{
    return edge(127 - key);
}

qreal SnappedRows::bottom(int key) const
{
    return edge(128 - key);
}

int SnappedRows::keyAt(qreal y) const
{
    for (int row = 0; row < 128; ++row)
        if (y < edge(row + 1))
            return 127 - row;
    return 0;
}

int SnappedRows::centerY(int key) const
{
    return int(std::floor((top(key) + bottom(key)) / 2));
}

QRectF SnappedRows::noteRect(qreal x0, qreal x1, int key) const
{
    return QRectF(x0, top(key) + pixel(), std::max<qreal>(2.0, x1 - x0),
                  std::max(2.0 * pixel(), bottom(key) - top(key) - pixel()));
}

QRectF SnappedRows::noteBox(const QRectF &rect) const
{
    return rect.adjusted(0, 0, 0, -pixel());
}

bool isSelectionRingColor(QRgb pixel)
{
    const QColor selectionRingColor = themes::color(themes::Role::item_selected_background);
    const QColor actualColor(pixel);
    return std::abs(actualColor.red() - selectionRingColor.red()) <= 16 &&
           std::abs(actualColor.green() - selectionRingColor.green()) <= 16 &&
           std::abs(actualColor.blue() - selectionRingColor.blue()) <= 16;
}

void click(QQuickItem &item, QPoint position)
{
    events::sendMouse(item, QEvent::MouseButtonPress, position, Qt::LeftButton, Qt::LeftButton,
                      Qt::NoModifier);
    events::sendMouse(item, QEvent::MouseButtonRelease, position, Qt::LeftButton, Qt::NoButton,
                      Qt::NoModifier);
}

void drawNote(QQuickItem &item, QPoint position)
{
    events::sendMouse(item, QEvent::MouseButtonDblClick, position, Qt::LeftButton, Qt::LeftButton,
                      Qt::NoModifier);
    events::sendMouse(item, QEvent::MouseButtonRelease, position, Qt::LeftButton, Qt::NoButton,
                      Qt::NoModifier);
}

void sendKeyStroke(QObject &target, int key, Qt::KeyboardModifiers modifiers, bool autoRepeat)
{
    events::sendKey(target, QEvent::KeyPress, key, modifiers, QString(), autoRepeat, 1);
    events::sendKey(target, QEvent::KeyRelease, key, modifiers, QString(), autoRepeat, 1);
}

} // namespace checks::rollcheck
