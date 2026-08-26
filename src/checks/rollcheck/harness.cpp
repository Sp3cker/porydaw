#include "checks/rollcheck/rollcheck.h"

#include <QColor>
#include <QObject>
#include <QWidget>
#include <algorithm>
#include <cmath>
#include <cstdio>

#include "checks/support/eventsynth.h"
#include "checks/support/songfixture.h"
#include "ui/layout.h"
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
    (void)songView.grab(); // force layout so child geometry is real

    m_pianoKeyboardWidth = layout::fontPx(13.0 / 3.0);
    m_plotOrigin = layout::fontPx(17.5 + 13.0 / 3.0);
    m_pianoRollDefaultKeyHeight = layout::fontPx(1.0);
    m_roll = songView.findChild<QWidget *>(QStringLiteral("pianoRoll"));
    if (!m_roll || m_roll->width() <= m_pianoKeyboardWidth || m_roll->height() <= 0) {
        fail("piano roll not found or not laid out");
        return false;
    }

    m_track = songView.selectionModel().primaryTrack();
    if (document().engineTrackCount() <= m_track) {
        fail("no engine track to draw on");
        return false;
    }

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

QWidget &Harness::roll() noexcept
{
    return *m_roll;
}

int Harness::track() const noexcept
{
    return m_track;
}

int Harness::pianoKeyboardWidth() const noexcept
{
    return m_pianoKeyboardWidth;
}

int Harness::plotOrigin() const noexcept
{
    return m_plotOrigin;
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
    const QWidget &pianoRoll = roll();
    const SnappedRows rows{songView, pianoRoll};

    for (int key = 115; key >= 24; --key) {
        const qreal top = rows.top(key);
        const qreal bottom = rows.bottom(key);
        if (top < 0 || bottom > pianoRoll.height())
            continue;
        for (int probe = firstProbe; probe < pianoRoll.width() - m_pianoKeyboardWidth - 40;
             probe += 24) {
            const uint64_t tick = songView.snapTickDown(songView.tickAtContentX(probe));
            const uint64_t dur = songView.gridTicksAt(tick);
            const int x0 = m_pianoKeyboardWidth + songView.contentX(double(tick));
            const int x1 = m_pianoKeyboardWidth + songView.contentX(double(tick + dur));
            const int xs =
                m_pianoKeyboardWidth + songView.contentX(double(tick + songView.snapTicksAt(tick)));
            if (x0 < m_pianoKeyboardWidth || x1 - x0 < 12 || xs - x0 < 8 || x1 >= pianoRoll.width())
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
    return roll.devicePixelRatioF();
}

qreal SnappedRows::pixel() const
{
    return 1.0 / dpr();
}

qreal SnappedRows::edge(int row) const
{
    return std::round((row * view.keyHeight() - view.scrollY()) * dpr()) / dpr();
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

void click(QWidget &widget, QPoint position)
{
    events::sendMouse(widget, QEvent::MouseButtonPress, position, Qt::LeftButton, Qt::LeftButton,
                      Qt::NoModifier);
    events::sendMouse(widget, QEvent::MouseButtonRelease, position, Qt::LeftButton, Qt::NoButton,
                      Qt::NoModifier);
}

void drawNote(QWidget &widget, QPoint position)
{
    events::sendMouse(widget, QEvent::MouseButtonDblClick, position, Qt::LeftButton, Qt::LeftButton,
                      Qt::NoModifier);
    events::sendMouse(widget, QEvent::MouseButtonRelease, position, Qt::LeftButton, Qt::NoButton,
                      Qt::NoModifier);
}

void sendKeyStroke(QObject &target, int key, Qt::KeyboardModifiers modifiers, bool autoRepeat)
{
    events::sendKey(target, QEvent::KeyPress, key, modifiers, QString(), autoRepeat, 1);
    events::sendKey(target, QEvent::KeyRelease, key, modifiers, QString(), autoRepeat, 1);
}

} // namespace checks::rollcheck
