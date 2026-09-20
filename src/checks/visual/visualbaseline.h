#pragma once

#include <QImage>
#include <QList>
#include <QRect>
#include <QString>
#include <QStringList>

class QApplication;
class QWidget;

// Shared frozen-appearance baselines for the visual-* check suites. A
// baseline is a reviewed source fixture pair stored at
// src/checks/fixtures/visual/<profile>/<id>.json + .png:
//   - <id> is a caller-chosen semantic relative path (e.g.
//     "transportbar/darkneutralhigh"); it never derives from QWidget class
//     names so a future QML adapter can supply identical bounds.
//   - <profile> is derived automatically as "<os>-dpr<D>-font<PX>" from the
//     running platform, the captured image's actual devicePixelRatio
//     (integers "dpr1"/"dpr2", fractions like "dpr1_25"), and the
//     PORYDAW_VISUAL_FONT_PX selection, so baselines recorded on one
//     platform/DPR/font never silently bless another.
//
// All region bounds are logical pixels relative to the image origin; images
// keep their devicePixelRatio so a native QQuickWindow::grabWindow() result
// compares in the same logical space as a QWidget::grab().
// Recording is explicit opt-in only: PORYDAW_RECORD_VISUAL_BASELINES=1 writes
// new source fixtures for human review, e.g.
//   PORYDAW_RECORD_VISUAL_BASELINES=1 deno task verify --filter visual
// Without it a missing baseline fails; normal verification is
//   deno task verify --filter visual
// Failure artifacts (actual/expected/diff PNGs plus a summary) go to
// PORYDAW_VISUAL_ARTIFACT_DIR, defaulting to <temp>/porydaw-visual-artifacts;
// normal runs never overwrite expected fixtures.
// PORYDAW_VISUAL_SCREEN_DPR (e.g. "1" or "2") optionally pins every top-level
// window to a connected screen whose native devicePixelRatio matches —
// captures then exercise a real 1x/2x framebuffer rather than QT_SCALE_FACTOR
// simulation. prepare() fails when no connected screen matches, and compare()
// fails when the captured DPR differs from the request, so a run can never
// silently record or verify the wrong profile.
namespace checks::visual {

/// A named logical-pixel rectangle inside a captured image. Names are stable
/// semantic identifiers assigned by the scenario, not Qt internals.
struct Region {
    QString name;
    QRect bounds;
};

/// Installs Fusion style, bundled fonts, font-relative layout geometry and the
/// vanilla theme. PORYDAW_VISUAL_FONT_PX="application" uses production's base
/// font; legacy profiles accept "12" (default) or "16". The profile records the
/// actual base size. Scenarios may change theme but must not reset font/style.
void prepare(QApplication &app);

/// Compares `image` against the frozen baseline <profile>/<id>: exact image
/// logical size and DPR, exact region name set and bounds, then per-region
/// raster comparison. Returns true on match; on failure `error` describes
/// the first problem and artifacts are written. A missing baseline fails
/// unless PORYDAW_RECORD_VISUAL_BASELINES=1, which records instead.
/// `regions` must be non-empty, uniquely named, non-degenerate, and inside
/// the image; violations fail rather than record.
bool compare(const QString &id, const QImage &image, const QList<Region> &regions, QString *error);

/// Grabs the shown `widget` (QWidget::grab, DPR retained) and compares it
/// like compare(). Fails when the grab is null.
bool compareWidget(const QString &id, QWidget &widget, const QList<Region> &regions,
                   QString *error);

/// Deterministic renderer-neutral regions for `root`'s visible named QWidget
/// descendants, mapped into root coordinates and sorted by name. Each child's
/// bounds are its rendered extent (QWidget::visibleRegion) clipped through
/// ancestor viewports and the root, so scroll-clipped children report only
/// their actually painted area. Qt implementation internals (qt_* object
/// names) are skipped. Scenarios add explicit semantically named subregions
/// for rows and custom painting; those must likewise clip to the painted
/// extent rather than nominal geometry.
QList<Region> widgetRegions(QWidget &root);

/// Behavior coverage for the comparator itself: proves a 1px bound change,
/// a modest flat-fill color change, and a missing baseline each fail, using
/// synthetic baselines in a private directory. Immune to
/// PORYDAW_RECORD_VISUAL_BASELINES so recording can never bless the mutants.
/// Returns true when every mutation is rejected; `error` reports the first
/// acceptance that should have failed.
bool selfTest(QString *error);

} // namespace checks::visual

// Suite runners (src/checks/visual/{chrome,transport,browsers,dialogs,
// sampleeditor,quick}.cpp).
// Each owns application startup via checks::visual::prepare and runs one
// qExec; registered in the catalog as HandlerOwned.
int runVisualChromeCheck(QApplication &application, const QStringList &qtArguments);
int runVisualTransportCheck(QApplication &application, const QStringList &qtArguments);
int runVisualBrowsersCheck(QApplication &application, const QStringList &qtArguments);
int runVisualDialogsCheck(QApplication &application, const QStringList &qtArguments);
int runVisualSampleEditorCheck(QApplication &application, const QStringList &qtArguments);
int runVisualQuickCheck(QApplication &application, const QStringList &qtArguments);
