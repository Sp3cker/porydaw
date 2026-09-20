#pragma once

#include <QImage>
#include <QList>
#include <QRect>
#include <QString>

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
// A record run writes the fixture and reports failure, so an unreviewed
// baseline can never pass as verification; re-run without the variable once
// the fixture has been reviewed. Without it a missing baseline fails; normal
// verification is
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
/// the first problem and artifacts are written. A missing baseline fails;
/// with PORYDAW_RECORD_VISUAL_BASELINES=1 it records the fixture and still
/// fails, so a fresh baseline must be reviewed and verified separately.
/// `regions` must be non-empty, uniquely named, non-degenerate, and inside
/// the image; violations fail rather than record.
/// Requires a prior checks::visual::prepare().
bool compare(const QString &id, const QImage &image, const QList<Region> &regions, QString *error);

/// Grabs the shown `widget` (QWidget::grab, DPR retained) and compares it
/// like compare(). Fails when the grab is null.
bool compareWidget(const QString &id, QWidget &widget, const QList<Region> &regions,
                   QString *error);

/// Deterministic renderer-neutral regions for `root`'s visible named QWidget
/// descendants, mapped into root coordinates and sorted by name. Each child's
/// bounds are its rendered extent (QWidget::visibleRegion) clipped through
/// ancestor viewports and root.rect(), so scroll-clipped children report only
/// their actually painted area and no bound ever leaves the root. Children
/// sharing an object name collapse to the first sorted (smallest) rectangle,
/// so the result always satisfies compare()'s uniqueness rule. visibleRegion()
/// ignores sibling occlusion: a partially occluded child freezes the bounding
/// rect of its unclipped area, and a fully clipped or out-of-root child
/// contributes nothing. Qt implementation internals (qt_* object names) are
/// skipped. Scenarios add explicit semantically named subregions for rows and
/// custom painting; those must likewise clip to the painted extent rather than
/// nominal geometry.
QList<Region> widgetRegions(QWidget &root);

/// Behavior coverage for the comparator itself: proves a 1px bound change,
/// a modest flat-fill color change, and a missing baseline each fail, using
/// synthetic baselines in a private directory. Runs in verify-only mode, so
/// PORYDAW_RECORD_VISUAL_BASELINES can never record a mutant. Returns true
/// when every mutation is rejected; `error` reports the first acceptance that
/// should have failed.
bool selfTest(QString *error);

} // namespace checks::visual
