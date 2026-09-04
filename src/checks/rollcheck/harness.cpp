#include "checks/rollcheck/rollcheck.h"

#include <QColor>
#include <QCoreApplication>
#include <QObject>
#include <algorithm>
#include <cmath>
#include <cstdio>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "ui/layout.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"

namespace checks::rollcheck {

Harness::Harness(SongViewRig &rig, const QString &songLabel) : m_rig(rig), m_songLabel(songLabel) {}

Harness::~Harness()
{
    QObject::disconnect(m_documentChanged);
}

bool Harness::prepare()
{
    SongView &songView = view();
    songView.resize(1280, 800);
    songView.setGridMinDenom(4);
    songView.show();
    songView.raise();
    songView.activateWindow();
    songView.ensurePolished();
    QCoreApplication::processEvents();
    (void)songView.grab(); // force layout so child geometry is real
    QCoreApplication::processEvents();
    m_pianoRollDefaultKeyHeight = layout::fontPx(1.0);
    auto *quick =
        songView.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    QQuickItem *const quickRoot = quick ? quick->rootObject() : nullptr;
    m_roll = songView.findChild<songview::PianoRoll *>();
    m_rollInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                  QStringLiteral("timelineRollInput"))
                            : nullptr;
    m_rollGutterInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                        QStringLiteral("timelineRollGutterInput"))
                                  : nullptr;
    const std::optional<songview::TimelineBandGeometry> &geometry =
        songView.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    const QRect plotRect = geometry ? geometry->plotRect : QRect{};
    const QRect gutterRect = geometry
                                 ? QRect(geometry->rect.topLeft(),
                                         QSize(geometry->plotRect.left() - geometry->rect.left(),
                                               geometry->rect.height()))
                                 : QRect{};
    m_pianoKeyboardWidth = gutterRect.width();
    const auto inputMatches = [quickRoot, quick](const songview::TimelineInputItem *input,
                                                 const QRect &songViewRect) {
        return input && input->isVisible() &&
               input->bounds() == QRectF(QPointF{}, songViewRect.size()) &&
               QRectF(input->mapToItem(quickRoot, QPointF{}), input->size()) ==
                   QRectF(songViewRect.translated(-quick->geometry().topLeft()));
    };
    if (!m_roll || !geometry || plotRect.isEmpty() || gutterRect.isEmpty() ||
        !inputMatches(m_rollInput, plotRect) || !inputMatches(m_rollGutterInput, gutterRect)) {
        fail("piano roll not found or not laid out");
        return false;
    }

    m_track = songView.selectionModel().primaryTrack();
    if (document().engineTrackCount() <= m_track) {
        fail("no engine track to draw on");
        return false;
    }

    if (captureQuickFramebuffer().isNull())
        return false;

    m_documentChanged =
        QObject::connect(&document(), &SongDocument::documentChanged, &songView, [this] {
            QString error;
            if (!m_rig.rebuildTimeline(error))
                fail(qUtf8Printable(error));
        });
    return true;
}

SongDocument &Harness::document() noexcept
{
    return m_rig.document();
}

SongView &Harness::view() noexcept
{
    return m_rig.view();
}

const MidiTimeline &Harness::timeline() const noexcept
{
    return m_rig.timeline();
}

songview::PianoRoll &Harness::roll() noexcept
{
    return *m_roll;
}

songview::TimelineInputItem &Harness::rollInput() noexcept
{
    return *m_rollInput;
}

songview::TimelineInputItem &Harness::rollGutterInput() noexcept
{
    return *m_rollGutterInput;
}

QRect Harness::rollBandRect() const noexcept
{
    const std::optional<songview::TimelineBandGeometry> band =
        m_rig.view().timelineBandLayout().geometry(songview::TimelineBand::Roll);
    return band ? band->rect : QRect{};
}

QImage Harness::captureQuickFramebuffer()
{
    if (!m_roll) {
        fail("piano roll not found");
        return {};
    }
    return captureQuickBand(rollBandRect());
}

QImage Harness::captureQuickBand(const QRect &bandRect)
{
    QString error;
    const QImage framebuffer = checks::support::captureQuickBand(view(), bandRect, &error);
    if (framebuffer.isNull())
        fail(qUtf8Printable(error));
    return framebuffer;
}

int Harness::track() const noexcept
{
    return m_track;
}

int Harness::pianoKeyboardWidth() const noexcept
{
    return m_pianoKeyboardWidth;
}

int Harness::pianoRollDefaultKeyHeight() const noexcept
{
    return m_pianoRollDefaultKeyHeight;
}

void Harness::fail(const char *what)
{
    std::fprintf(stderr, "rollcheck: FAIL %s: %s\n", qUtf8Printable(m_songLabel), what);
    ++m_failures;
}

const QString &Harness::songLabel() const noexcept
{
    return m_songLabel;
}

void Harness::addFailures(int count) noexcept
{
    m_failures += count;
}

int Harness::failures() const noexcept
{
    return m_failures;
}

bool Harness::isOccupied(uint64_t tick, uint64_t dur, int key, bool checkAllTracks)
{
    const SongDocument &doc = document();
    const int startTrack = checkAllTracks ? 0 : m_track;
    const int endTrack = checkAllTracks ? doc.engineTrackCount() : m_track + 1;
    for (int track = startTrack; track < endTrack; ++track) {
        for (const DocNote &note : doc.notesForTrack(track)) {
            if (int(note.key) != key)
                continue;
            const uint64_t end = note.unterminated() ? UINT64_MAX : note.tick + note.duration + dur;
            if (note.tick < tick + 2 * dur && end > tick)
                return true;
        }
    }
    return false;
}

Cell Harness::findFreeCell(int firstProbe, bool checkAllTracks)
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
            const uint64_t tick =
                songView.grid().snapTickDown(songView.camera().tickAtContentX(probe));
            const uint64_t dur = songView.grid().gridTicksAt(tick);
            const int x0 = songView.camera().contentX(double(tick));
            const int x1 = songView.camera().contentX(double(tick + dur));
            const int xs =
                songView.camera().contentX(double(tick + songView.grid().snapTicksAt(tick)));
            if (x0 < 0 || x1 - x0 < 12 || xs - x0 < 8 || x1 >= int(pianoRoll.bounds().width()))
                continue;
            if (isOccupied(tick, dur, key, checkAllTracks))
                continue;
            const auto markerInSpan = [&](uint64_t markerTick) {
                return markerTick != UINT64_MAX && markerTick >= tick &&
                       markerTick <= tick + 2 * dur;
            };
            if (markerInSpan(timeline().loopStartTick) || markerInSpan(timeline().loopEndTick))
                continue;
            return {tick, dur, key, QPoint((x0 + xs) / 2, rows.centerY(key))};
        }
    }
    return {};
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
