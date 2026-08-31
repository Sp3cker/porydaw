#pragma once

#include <QColor>
#include <QImage>
#include <QMetaObject>
#include <QPoint>
#include <QRectF>
#include <QString>
#include <QtGlobal>
#include <optional>

#include "core/songdocument.h"
#include "ui/songview.h"

class MidiTimeline;
class QWidget;
class QObject;

namespace checks {
class SongViewRig;
}

namespace checks::rollcheck {

struct Cell;

// Stable ownership and geometry shared by the sequential SongView scenarios.
// Individual topics keep their transient cells, notes, and event sequences local.
class Harness final
{
  public:
    Harness(SongViewRig &rig, const QString &songLabel);
    ~Harness();

    Harness(const Harness &) = delete;
    Harness &operator=(const Harness &) = delete;

    bool prepare();

    SongDocument &document() noexcept;
    SongView &view() noexcept;
    const MidiTimeline &timeline() const noexcept;
    QWidget &roll() noexcept;
    QImage captureQuickFramebuffer();
    QImage captureQuickBand(QWidget &band);
    int track() const noexcept;
    int pianoKeyboardWidth() const noexcept;
    int plotOrigin() const noexcept;
    int pianoRollDefaultKeyHeight() const noexcept;

    void fail(const char *what);
    const QString &songLabel() const noexcept;
    void addFailures(int count) noexcept;
    int failures() const noexcept;
    bool isOccupied(uint64_t tick, uint64_t dur, int key, bool checkAllTracks = false);
    Cell findFreeCell(int firstProbe = 8, bool checkAllTracks = false);

  private:
    SongViewRig &m_rig;
    QString m_songLabel;
    QWidget *m_roll = nullptr;
    int m_track = -1;
    int m_pianoKeyboardWidth = 0;
    int m_plotOrigin = 0;
    int m_pianoRollDefaultKeyHeight = 0;
    int m_failures = 0;
    QMetaObject::Connection m_documentChanged;
};

// Test-side mirror of the roll's vertical projection. It intentionally samples
// the independently-snapped row bounds without exposing SongView paint geometry.
struct SnappedRows {
    const SongView &view;
    const QWidget &roll;

    qreal dpr() const;
    qreal pixel() const;
    qreal edge(int row) const;
    qreal top(int key) const;
    qreal bottom(int key) const;
    int keyAt(qreal y) const;
    int centerY(int key) const;
    QRectF noteRect(qreal x0, qreal x1, int key) const;
    QRectF noteBox(const QRectF &rect) const;
};

bool isSelectionRingColor(QRgb pixel);

struct Cell {
    uint64_t tick = 0;
    uint64_t dur = 0;
    int key = -1;
    QPoint center;
};

enum class ScenarioContinuation {
    Continue,
    Stop,
};

struct PencilPaintingFixture {
    Cell a;
    DocNote noteA;
};

struct PencilVelocityFixture {
    Cell a;
    Cell b;
    DocNote noteA;
    DocNote noteB;
};

struct ResizeFixture {
    Cell cell;
    uint64_t snapCell = 0;
};

ScenarioContinuation runLoadingRulerScenarios(Harness &check);
ScenarioContinuation runIdentityScenarios(Harness &check, const SongInfo &song);
ScenarioContinuation runRemapScenarios(Harness &check, const SongInfo &song);
ScenarioContinuation runHeaderReconciliationScenarios(Harness &check, const SongInfo &song);
ScenarioContinuation runCameraScenarios(Harness &check);
std::optional<PencilPaintingFixture> runPencilPaintingScenarios(Harness &check);
ScenarioContinuation runPencilNoteRenderingScenarios(Harness &check,
                                                     const PencilPaintingFixture &fixture);
std::optional<PencilVelocityFixture> runPencilVelocityScenarios(Harness &check,
                                                                PencilPaintingFixture fixture);
ScenarioContinuation runGestureInterlockScenarios(Harness &check,
                                                  const PencilVelocityFixture &fixture);
ScenarioContinuation runSelectionGestureScenarios(Harness &check,
                                                  const PencilVelocityFixture &fixture);
ScenarioContinuation runSelectionRasterScenarios(Harness &check,
                                                 const PencilVelocityFixture &fixture);
std::optional<ResizeFixture> runResizeScenarios(Harness &check,
                                                const PencilVelocityFixture &fixture);
ScenarioContinuation runKeyboardAndTimelineScenarios(Harness &check, const ResizeFixture &fixture);
ScenarioContinuation runHeaderAndPresentationScenarios(Harness &check,
                                                       const PencilVelocityFixture &fixture,
                                                       const QString &screenshotPath);
ScenarioContinuation runScaleProjectionScenarios(Harness &check);
ScenarioContinuation runScaleFoldScenarios(Harness &check);
ScenarioContinuation runScaleEditingScenarios(Harness &check);

void click(QWidget &widget, QPoint position);
void drawNote(QWidget &widget, QPoint position);
void sendKeyStroke(QObject &target, int key, Qt::KeyboardModifiers modifiers, bool autoRepeat);

} // namespace checks::rollcheck
