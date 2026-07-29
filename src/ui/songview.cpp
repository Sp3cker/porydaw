#include "songview.h"
#include "layout.h"
#include "theme/color_math.h"
#include "theme/themeruntime.h"
#include "theme/trackidentitycolors.h"
#include "typography.h"
#include "ui/layout.h"

#include <QAction>
#include <QApplication>
#include <QComboBox>
#include <QContextMenuEvent>
#include <QCursor>
#include <QDialog>
#include <QDialogButtonBox>
#include <QEvent>
#include <QFontMetrics>
#include <QGridLayout>
#include <QHBoxLayout>
#include <QIcon>
#include <QInputDialog>
#include <QKeyEvent>
#include <QKeySequence>
#include <QLabel>
#include <QLineEdit>
#include <QLinearGradient>
#include <QListWidget>
#include <QMenu>
#include <QMessageBox>
#include <QMouseEvent>
#include <QObject>
#include <QPaintEvent>
#include <QPainter>
#include <QPainterPath>
#include <QPixmap>
#include <QProxyStyle>
#include <QPushButton>
#include <QResizeEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QSpinBox>
#include <QStackedWidget>
#include <QToolButton>
#include <QToolTip>
#include <QVBoxLayout>
#include <QWheelEvent>
#include <algorithm>
#include <array>
#include <climits>
#include <cmath>
#include <functional>
#include <map>
#include <numeric>
#include <set>
#include <utility>

#include <optional>

#include "core/mid2agbtables.h"
#include "core/songdocument.h"
#include "ui/editordrawer.h"
#include "ui/eventlistview.h"
#include "ui/keymap.h"
#include "ui/playheadoverlay.h"

#include "ui/velocityarea.h"
namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {

std::vector<DocNote> selectedDocumentNotes(const SongView &view) {
  std::vector<DocNote> notes;
  SongDocument *doc = view.document();
  if (!doc)
    return notes;
  for (const SongView::NoteId &id : view.selection()) {
    DocNote note;
    if (doc->findNote(view.selectedTrack(), id.tick, id.key, &note))
      notes.push_back(note);
  }
  return notes;
}

QPoint wheelDelta(const QWheelEvent *event) {
  const QPoint pixelDelta = event->pixelDelta();
  return pixelDelta.isNull() ? event->angleDelta() : pixelDelta;
}

double wheelAngleUnits(const QWheelEvent *event) {
  if (event->phase() == Qt::ScrollMomentum)
    return 0.0;
  const QPoint delta = wheelDelta(event);
  return double(delta.y()) * (event->pixelDelta().isNull() ? 1.0 : 5.0);
}

namespace {

// The ruler stacks a marker row (time-signature chips, loop brackets,
// selection handles) above the bar-number/tick row, so marker text never
// collides with the bar numbers.
constexpr int kLaneH = 48; // default row height; Ctrl+wheel rescales
constexpr int kMinLaneH = 28;
constexpr int kMaxLaneH = 128;
constexpr int kAddLaneH = 20;
constexpr double kMinPxPerBeat = 4.0;
constexpr double kMaxPxPerBeat = 640.0;
constexpr double kMinKeyHeight = 4.0;
constexpr double kMaxKeyHeight = 32.0;
constexpr int kScrollUnitsPerDip = 16;

qreal logicalPhysicalPixel(qreal dpr) { return dpr > 0.0 ? 1.0 / dpr : 1.0; }

int scrollUnits(double dip) {
  const double units =
      std::clamp(dip * kScrollUnitsPerDip, 0.0, double(INT_MAX));
  return int(std::lround(units));
}

double scrollDips(int units) { return double(units) / kScrollUnitsPerDip; }

double cursorAnchoredScroll(double anchor, double oldScale, double oldScroll,
                            double newScale) {
  const double content = (anchor + oldScroll) / oldScale;
  return content * newScale - anchor;
}
constexpr int kVoiceAuditionKey =
    60; // middle C, matching the voicegroup browser
constexpr int kVoiceAuditionVel = 112;
constexpr int kVoiceMarkerHitRadius = 9;
// Resize hit-zone reach at a note's left/right edges (rollcheck probes
// 6.8 DIPs inside the ends, so the zone must reach past that). Outside the
// note the full reach always applies; inside, both zones shrink to leave at
// least kMoveZoneMin between them so short notes keep a grabbable middle
// for move drags.
constexpr qreal kEdgeGripReach = 7.0;
constexpr qreal kMoveZoneMin = 6.0;
qreal edgeGripInnerReach(const QRectF &noteRect) {
  return std::clamp((noteRect.width() - kMoveZoneMin) / 2.0, 0.0,
                    kEdgeGripReach);
}

bool isBlackKey(int key) {
  switch (key % 12) {
  case 1:
  case 3:
  case 6:
  case 8:
  case 10:
    return true;
  default:
    return false;
  }
}

QString keyName(int key) {
  static const char *const names[] = {"C",  "C#", "D",  "D#", "E",  "F",
                                      "F#", "G",  "G#", "A",  "A#", "B"};
  return QStringLiteral("%1%2")
      .arg(QLatin1String(names[key % 12]))
      .arg(key / 12 - 1);
}

QString timeSigLabel(int numerator, int denomPow2) {
  return QStringLiteral("%1/%2").arg(numerator).arg(1
                                                    << std::min(denomPow2, 6));
}

// Modal numerator/denominator editor for a ruler time-signature marker.
bool askTimeSignature(QWidget *parent, int *numerator, int *denomPow2) {
  QDialog dlg(parent);
  dlg.setWindowTitle(SongView::tr("Time Signature"));
  auto *num = new QSpinBox(&dlg);
  num->setRange(1, 32);
  num->setValue(std::clamp(*numerator, 1, 32));
  auto *den = new QComboBox(&dlg);
  for (int p = 0; p <= 5; p++)
    den->addItem(QString::number(1 << p), p);
  den->setCurrentIndex(std::clamp(*denomPow2, 0, 5));
  auto *row = new QHBoxLayout;
  row->addWidget(num);
  row->addWidget(new QLabel(QStringLiteral("/"), &dlg));
  row->addWidget(den);
  auto *buttons = new QDialogButtonBox(
      QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dlg);
  QObject::connect(buttons, &QDialogButtonBox::accepted, &dlg,
                   &QDialog::accept);
  QObject::connect(buttons, &QDialogButtonBox::rejected, &dlg,
                   &QDialog::reject);
  auto *layout = new QVBoxLayout(&dlg);
  layout->addLayout(row);
  layout->addWidget(buttons);
  if (dlg.exec() != QDialog::Accepted)
    return false;
  *numerator = num->value();
  *denomPow2 = den->currentData().toInt();
  return true;
}

// SongView paint paths request canvas-specific roles directly, making each
// visible element traceable without knowing a shared theme alias.
QLinearGradient loopGlow(qreal edgeX, qreal transparentX) {
  auto color = themes::color(themes::Role::song_view_loop_marker);
  auto transparent = color;
  color.setAlpha(150);
  transparent.setAlpha(0);
  QLinearGradient gradient(edgeX, 0, transparentX, 0);
  gradient.setColorAt(0.0, color);
  color.setAlpha(18);
  gradient.setColorAt(0.2, color);
  gradient.setColorAt(1.0, transparent);
  return gradient;
}
QColor loopEdge() { return themes::color(themes::Role::song_view_loop_marker); }
QColor playheadColor() {
  return themes::color(themes::Role::song_view_playhead);
}
QColor pianoRollAccidentalLaneColor() {
  return themes::color(themes::Role::song_view_piano_roll_accidental_lane);
}
QColor trackHeaderAlsoSelectedColor() {
  auto color = themes::color(themes::Role::song_view_track_header_selection);
  color.setAlpha(99);
  return color;
}
} // namespace

// Perceptual blend for receding a color into its backdrop (silent-in-game
// track headers): t = 0 keeps `color`, t = 1 lands on `backdrop`.
QColor mixTowardOklab(const QColor &color, const QColor &backdrop, double t) {
  const themes::Oklab from = themes::oklabFromColor(color);
  const themes::Oklab to = themes::oklabFromColor(backdrop);
  return themes::colorFromOklab(
      {from.lightness + (to.lightness - from.lightness) * t,
       from.a + (to.a - from.a) * t, from.b + (to.b - from.b) * t});
}
namespace {

std::size_t trackIdentityIndex(int track) {
  const auto count = static_cast<int>(themes::trackIdentityColorCount);
  return static_cast<std::size_t>(((track % count) + count) % count);
}

// Saturated fills identify tracks; their paired text colors are used only where
// labels need contrast against those fills.
const QColor &trackTextColor(int track) {
  return themes::trackIdentityTextColor(trackIdentityIndex(track));
}

} // namespace

// Velocity-bar / stem shade: fixed mix of each identity toward black (once).
const QColor &trackStemColor(int track) {
  static const auto stems = [] {
    std::array<QColor, themes::trackIdentityColorCount> result{};
    for (std::size_t i = 0; i < result.size(); ++i)
      result[i] =
          mixTowardOklab(themes::trackIdentityColor(i), Qt::black, 1.0 / 3.0);
    return result;
  }();
  return stems[trackIdentityIndex(track)];
}

// Ghost notes (unselected tracks): mix ~24% of the track identity into the row
// background in OKLab, with a capped lightness offset. 16 identities × 2 row
// kinds, rebuilt only when the theme's piano-roll backgrounds change.
QColor ghostNoteColor(int track, bool accidentalRow) {
  static std::array<std::array<QColor, 2>, themes::trackIdentityColorCount>
      colors;
  static QRgb bgKey[2]{};

  const auto &whiteBg =
      themes::color(themes::Role::song_view_piano_roll_background);
  const auto &accBg =
      themes::color(themes::Role::song_view_piano_roll_accidental_lane);
  if (bgKey[0] != whiteBg.rgba() || bgKey[1] != accBg.rgba()) {
    bgKey[0] = whiteBg.rgba();
    bgKey[1] = accBg.rgba();
    const themes::Oklab bg[2] = {themes::oklabFromColor(whiteBg),
                                 themes::oklabFromColor(accBg)};
    constexpr double w = 60.0 / 255.0, maxL = 0.055;
    for (std::size_t i = 0; i < colors.size(); ++i) {
      const auto id = themes::oklabFromColor(themes::trackIdentityColor(i));
      for (int b = 0; b < 2; ++b) {
        const double dL =
            std::clamp((id.lightness - bg[b].lightness) * w, -maxL, maxL);
        colors[i][b] = themes::colorFromOklab({bg[b].lightness + dL,
                                               bg[b].a + (id.a - bg[b].a) * w,
                                               bg[b].b + (id.b - bg[b].b) * w});
      }
    }
  }
  return colors[trackIdentityIndex(track)][accidentalRow];
}

// Draw the loop-region band across rect. x positions are
// computed with origin = local x of timeline tick 0's content position.
// timeSelCovered says whether this widget (or row) is inside the active time
// selection's scope, so the selection band tints exactly the covered content.
void drawOverlays(QPainter &p, const SongView *sv, const QRect &rect,
                  qreal origin, bool timeSelCovered) {
  const MidiTimeline *tl = sv->timeline();
  if (!tl)
    return;

  const qreal dpr = p.device()->devicePixelRatioF();
  const SongView::TimeSelection &tsel = sv->timeSelection();
  if (timeSelCovered && tsel.active()) {
    const qreal x0 = sv->displayX(double(tsel.startTick), origin, dpr);
    const qreal x1 = sv->displayX(double(tsel.endTick), origin, dpr);
    if (x1 > rect.left() && x0 < rect.right()) {
      QColor fill = themes::color(themes::Role::song_view_selection_fill);
      fill.setAlpha(30);
      const QRectF selectionRect(x0, rect.top(), x1 - x0, rect.height());
      p.fillRect(selectionRect.intersected(QRectF(rect)), fill);
      p.setPen(QPen(themes::color(themes::Role::song_view_selection_edge), 1));
      p.drawLine(QLineF(x0, rect.top(), x0, rect.bottom()));
      p.drawLine(QLineF(x1, rect.top(), x1, rect.bottom()));
    }
  }
  if (tl->loopStartTick != UINT64_MAX || tl->loopEndTick != UINT64_MAX) {
    const bool hasStart = tl->loopStartTick != UINT64_MAX;
    const bool hasEnd = tl->loopEndTick != UINT64_MAX;
    const qreal x0 = hasStart
                         ? sv->displayX(double(tl->loopStartTick), origin, dpr)
                         : rect.left();
    const qreal x1 = hasEnd ? sv->displayX(double(tl->loopEndTick), origin, dpr)
                            : rect.right();
    if (x1 > rect.left() && x0 < rect.right()) {
      const qreal glowWidth =
          std::min<qreal>(lyt::space(Space::Eight), x1 - x0);
      if (hasStart && glowWidth > 0) {
        const QRectF glowRect(x0, rect.top(), glowWidth, rect.height());
        p.fillRect(glowRect.intersected(QRectF(rect)),
                   loopGlow(x0, x0 + glowWidth));
      }
      if (hasEnd && glowWidth > 0) {
        const QRectF glowRect(x1 - glowWidth, rect.top(), glowWidth,
                              rect.height());
        p.fillRect(glowRect.intersected(QRectF(rect)),
                   loopGlow(x1, x1 - glowWidth));
      }
      p.setPen(QPen(loopEdge(), 1));
      if (hasStart)
        p.drawLine(QLineF(x0, rect.top(), x0, rect.bottom()));
      if (hasEnd)
        p.drawLine(QLineF(x1, rect.top(), x1, rect.bottom()));
    }
  }
  const qreal cursorX = sv->displayX(double(sv->editCursorTick()), origin, dpr);
  if (cursorX >= rect.left() && cursorX <= rect.right()) {
    p.setPen(QPen(themes::color(themes::Role::song_view_edit_cursor), 1,
                  Qt::DashLine));
    p.drawLine(QLineF(cursorX, rect.top(), cursorX, rect.bottom()));
  }
}

namespace {

// Subdivision level of a sub-beat grid tick (relative to its segment's
// start): 1 = the beat's first split (half beat, or a third in triplet
// feel), 2 = the next, 3 = finer. Cosmetic only (drives the line fade).
int subGridLevel(uint64_t relTick, uint64_t beatTicks, bool triplet) {
  if (relTick % std::max<uint64_t>(1, beatTicks / (triplet ? 3 : 2)) == 0)
    return 1;
  if (relTick % std::max<uint64_t>(1, beatTicks / (triplet ? 6 : 4)) == 0)
    return 2;
  return 3;
}

// Calls fn(tick, level) for every visible sub-beat grid position in [t0, t1)
// that is not a beat line. At readable zoom it also includes the next finer
// snap subdivision, so every position available to a note edit has a line.
// Walks time-signature segments so the positions stay snappable and match
// the beat lines. No callbacks in segments whose grid is at (or coarser
// than) whole beats.
void forEachSubGridLine(const SongView *sv, double t0, double t1,
                        const std::function<void(uint64_t, int)> &fn) {
  const bool triplet = sv->gridFeel() == SongView::GridFeel::Triplet;
  uint64_t at = uint64_t(std::max(0.0, t0));
  const uint64_t end = t1 <= 0.0 ? 0 : uint64_t(t1);
  while (at < end) {
    const SongView::GridSeg seg = sv->gridSegAt(at);
    const uint64_t segEnd = std::min(seg.next, end);
    const uint64_t drawnGrid = sv->gridTicksAt(at);
    const uint64_t snapGrid = sv->snapTicksAt(at);
    const uint64_t g =
        snapGrid < drawnGrid && sv->pxPerTick() * double(snapGrid) >=
                                    songview::kAutoGridMinCellPx
            ? snapGrid
            : drawnGrid;
    if (g > 0 && g < seg.beatTicks &&
        sv->pxPerTick() * double(seg.beatTicks) >= 10.0) {
      const uint64_t k = at > seg.start ? (at - seg.start + g - 1) / g : 0;
      for (uint64_t tick = seg.start + k * g; tick < segEnd; tick += g) {
        if ((tick - seg.start) % seg.beatTicks == 0)
          continue; // beat/bar lines are drawn separately
        fn(tick, subGridLevel(tick - seg.start, seg.beatTicks, triplet));
      }
    }
    if (seg.next >= end)
      break;
    at = seg.next;
  }
}
// Finds a drawn-grid boundary in the direction of travel. Keyboard nudges
// use this rather than the finer editing snap so every destination is visible.
uint64_t drawnGridTick(const SongView *sv, double tick, bool upward) {
  tick = std::max(0.0, tick);
  const SongView::GridSeg seg = sv->gridSegAt(uint64_t(tick));
  const uint64_t g = std::max<uint64_t>(1, sv->gridTicksAt(uint64_t(tick)));
  const uint64_t lo =
      seg.start + uint64_t((tick - double(seg.start)) / double(g)) * g;
  if (!upward || double(lo) >= tick)
    return lo;
  return std::min(lo + g, seg.next);
}

QColor gridLineColor(int alpha = 255) {
  auto color = themes::color(themes::Role::song_view_grid);
  color.setAlpha((color.alpha() * alpha + 127) / 255);
  return color;
}

} // namespace

// Vertical bar/beat grid lines inside rect, with zoom-adaptive sub-beat
// lines at the snap grid's positions fading lighter per subdivision level.
// Lines are batched per level so each color is a single drawLines() call.
void drawGrid(QPainter &p, const SongView *sv, const QRect &rect,
              qreal origin) {
  if (!sv->timeline())
    return;
  const qreal dpr = p.device()->devicePixelRatioF();
  const qreal physicalPixel = logicalPhysicalPixel(dpr);
  const qreal roundingMargin = physicalPixel / 2.0;
  const double t0 =
      std::max(0.0, sv->tickAtContentX(rect.left() - origin - roundingMargin));
  const double t1 = sv->tickAtContentX(rect.x() + rect.width() - physicalPixel -
                                       origin + roundingMargin) +
                    1;
  const bool drawBeats = sv->pxPerBeat() >= 10.0;
  // Batches 0-2 hold sub-grid levels 1-3 (fading lighter), 3 beats, 4
  // finest-grid beats, 5 bars; painted in that order so beats and bars
  // land on top.
  const std::array<QColor, 6> colors = {gridLineColor(125), gridLineColor(100),
                                        gridLineColor(75),  gridLineColor(160),
                                        gridLineColor(200), gridLineColor()};
  std::array<QVector<QLineF>, 6> batches;
  forEachSubGridLine(sv, t0, t1, [&](uint64_t tick, int level) {
    const qreal x = sv->displayX(double(tick), origin, dpr);
    batches[level - 1].append(QLineF(x, rect.top(), x, rect.bottom()));
  });
  sv->forEachGridLine(
      uint64_t(t0), uint64_t(t1), [&](uint64_t tick, bool isBar, int, int) {
        if (!isBar && !drawBeats)
          return;
        const qreal x = sv->displayX(double(tick), origin, dpr);
        const bool atFinestGrid =
            sv->document() && sv->gridTicksAt(tick) == sv->fineGridTicks();
        batches[isBar          ? 5
                : atFinestGrid ? 4
                               : 3]
            .append(QLineF(x, rect.top(), x, rect.bottom()));
      });
  for (size_t i = 0; i < batches.size(); ++i) {
    if (batches[i].isEmpty())
      continue;
    // Grid lines are two physical pixels on every display scale.
    p.setPen(QPen(colors[i], 2.0 * physicalPixel));
    p.drawLines(batches[i]);
  }
}

namespace {

// macOS flashes a triggered menu item for 80 ms before hiding the menu;
// suppress the flash so picking an action feels instant.
class NoteMenuStyle final : public QProxyStyle {
public:
  // Base the proxy on Fusion explicitly, matching the application style set
  // in main(). QApplication::style()->name() looks like it would mirror the
  // app style, but once the theme installs a stylesheet the app style is a
  // QStyleSheetStyle whose name() is empty — and QProxyStyle(QString())
  // silently falls back to the NATIVE desktop style (QWindows11Style on
  // Windows). Polishing this menu under that style calls setWindowFlags for
  // the native rounded popup, which reentrantly crashes in Qt 6.9. Naming
  // Fusion keeps the menu on the same style as the rest of the app.
  NoteMenuStyle() : QProxyStyle(QStringLiteral("Fusion")) {}

  int styleHint(StyleHint hint, const QStyleOption *option,
                const QWidget *widget,
                QStyleHintReturn *returnData) const override {
    if (hint == SH_Menu_FlashTriggeredItem)
      return 0;
    return QProxyStyle::styleHint(hint, option, widget, returnData);
  }
};

enum class NoteMenuChoice {
  None,
  Velocity,
  Copy,
  Cut,
  Delete,
};
// Kept alive by PianoRoll so opening it does not reconstruct its actions.
class NoteContextMenu final : public QMenu {
public:
  // Called when an outside right-click may move the menu to another note;
  // returns false when the click hit nothing, so the press falls through
  // to QMenu (which dismisses the popup like any outside click).
  explicit NoteContextMenu(QWidget *parent,
                           std::function<bool(QPointF)> onOutsideRightClick)
      : QMenu(parent), m_onOutsideRightClick(std::move(onOutsideRightClick)) {
    auto *menuStyle = new NoteMenuStyle;
    menuStyle->setParent(this);
    setStyle(menuStyle);
    m_velocityAction = addAction(QString());
    addSeparator();
    // Display-only hints (the real bindings live in keyPressEvent):
    // mirror the keymap so a rebind doesn't leave the menu lying.
    const auto &keys = keymap::Registry::instance();
    m_copyAction = addAction(SongView::tr("Copy"));
    m_copyAction->setShortcut(
        keys.bindings(QStringLiteral("roll.copy")).value(0));
    m_cutAction = addAction(SongView::tr("Cut"));
    m_cutAction->setShortcut(
        keys.bindings(QStringLiteral("roll.cut")).value(0));
    m_deleteAction = addAction(SongView::tr("Delete"));
  }

  void showMenuAt(QPoint globalPos, int velocity) {
    m_velocityAction->setText(SongView::tr("Set velocity… (%1)").arg(velocity));
    popup(globalPos);
  }

  NoteMenuChoice handleAction(QAction *action) const {
    if (action == m_velocityAction)
      return NoteMenuChoice::Velocity;
    if (action == m_copyAction)
      return NoteMenuChoice::Copy;
    if (action == m_cutAction)
      return NoteMenuChoice::Cut;
    if (action == m_deleteAction)
      return NoteMenuChoice::Delete;
    return NoteMenuChoice::None;
  }

protected:
  // A right-click on another note while the popup is open retargets the
  // menu in one gesture instead of spending the click on dismissal.
  void mousePressEvent(QMouseEvent *event) override {
    if (event->button() == Qt::RightButton &&
        !QRectF(rect()).contains(event->position()) &&
        m_onOutsideRightClick(event->globalPosition())) {
      event->accept();
      return;
    }
    QMenu::mousePressEvent(event);
  }

private:
  std::function<bool(QPointF)> m_onOutsideRightClick;
  QAction *m_velocityAction = nullptr;
  QAction *m_copyAction = nullptr;
  QAction *m_cutAction = nullptr;
  QAction *m_deleteAction = nullptr;
};
QFont timeRulerFont(const QFont &source) {
  auto font = typography::bodyMono(typography::caption(source));
  font.setPixelSize(std::max(1, font.pixelSize() - lyt::singlePixel()));
  font.setLetterSpacing(QFont::AbsoluteSpacing, -0.5);
  return font;
}
// "bar.beat" labels sit one size below the bar numbers so the two label
// tiers read apart even where the deemphasized color alone wouldn't.
QFont beatRulerFont(const QFont &source) {
  auto font = timeRulerFont(source);
  font.setPixelSize(std::max(1, font.pixelSize() - lyt::singlePixel()));
  return font;
}

} // namespace

// ---------------------------------------------------------------- TimeRuler

class TimeRuler : public QWidget {
public:
  explicit TimeRuler(SongView *sv) : QWidget(sv), m_sv(sv) {
    // The ruler has a bold marker row and a regular bar-number/tick row.
    // Each row reserves its face's occupied glyph height plus semantic
    // padding, so a narrow ruler never clips text or relies on pixels.
    const auto markerRowPadding = lyt::singlePixel();
    const auto tickRowPadding = lyt::singlePixel();
    const auto rulerFont = timeRulerFont(font());
    const QFontMetrics markerMetrics(typography::bold(rulerFont));
    const QFontMetrics tickMetrics(rulerFont);
    m_markerHeight = markerMetrics.height() + markerRowPadding;
    const auto rulerHeight =
        m_markerHeight + tickMetrics.height() + tickRowPadding;
    setFixedHeight(rulerHeight);
    setMouseTracking(true);

    // Snap-grid controls in the gutter left of the timeline: minimum
    // subdivision (Auto = zoom-adaptive down to the clock grid) and
    // straight-vs-triplet feel. NoFocus for the same reason the scroll
    // areas have it: keyboard editing must stay in the roll.
    auto *gridBox = new QWidget(this);
    gridBox->setGeometry(0, 0, kGutterW - lyt::space(Space::One), rulerHeight);
    auto *row = new QHBoxLayout(gridBox);
    row->setContentsMargins(lyt::space(Space::Two), 0, 0, 0);
    row->setSpacing(lyt::space(Space::One));
    row->addWidget(new QLabel(SongView::tr("Grid"), gridBox));
    m_divCombo = new QComboBox(gridBox);
    m_divCombo->addItem(SongView::tr("Auto"), 0);
    for (int denom : {4, 8, 16, 32})
      m_divCombo->addItem(QStringLiteral("1/%1").arg(denom), denom);
    m_divCombo->setToolTip(
        SongView::tr("Finest drawn subdivision. Auto follows the zoom down to "
                     "the mid2agb clock grid; edits snap one step finer than "
                     "the drawn grid."));
    m_feelCombo = new QComboBox(gridBox);
    m_feelCombo->addItem(SongView::tr("Straight"));
    m_feelCombo->addItem(SongView::tr("Triplet"));
    m_feelCombo->setToolTip(
        SongView::tr("Straight or triplet beat subdivisions."));
    for (QComboBox *combo : {m_divCombo, m_feelCombo}) {
      combo->setFocusPolicy(Qt::NoFocus);
      row->addWidget(combo);
    }
    row->addStretch(1);
    QObject::connect(
        m_divCombo, &QComboBox::activated, m_sv, [this](int index) {
          m_sv->setGridMinDenom(m_divCombo->itemData(index).toInt());
        });
    QObject::connect(
        m_feelCombo, &QComboBox::activated, m_sv, [this](int index) {
          m_sv->setGridFeel(index == 1 ? SongView::GridFeel::Triplet
                                       : SongView::GridFeel::Straight);
        });
  }

  // Combo state from the view (setters, setSong reset, sidecar apply);
  // setCurrentIndex is safe because the handlers hang off activated(),
  // which only fires on user picks.
  void syncGridControls() {
    m_divCombo->setCurrentIndex(
        std::max(0, m_divCombo->findData(m_sv->gridMinDenom())));
    m_feelCombo->setCurrentIndex(
        m_sv->gridFeel() == SongView::GridFeel::Triplet ? 1 : 0);
  }

  // A mouse gesture is live (marker/time-sig/selection-edge drag, cursor
  // scrub, right-press sweep); the playhead follow-scroll pauses while
  // one runs so the view doesn't jump under the cursor.
  bool gestureActive() const {
    return m_dragMarker >= 0 || m_dragTimeSig || m_placingCursor ||
           m_rightPress || m_dragSelEdge >= 0;
  }

protected:
  void paintEvent(QPaintEvent *) override {
    QPainter p(this);
    const qreal dpr = p.device()->devicePixelRatioF();
    const QFont rulerFont = timeRulerFont(p.font());
    const QFont beatFont = beatRulerFont(p.font());
    p.setFont(rulerFont);
    const QColor chrome =
        themes::color(themes::Role::song_view_timeline_chrome_background);
    p.fillRect(rect(), chrome);
    p.setPen(QPen(themes::color(themes::Role::song_view_separator),
                  lyt::singlePixel()));
    p.drawLine(0, rect().bottom(), width(), rect().bottom());

    if (!m_sv->timeline()) {
      p.setPen(palette().color(QPalette::PlaceholderText));
      p.drawText(
          rect().adjusted(kGutterW + lyt::space(Space::Two), 0, 0, 0),
          Qt::AlignVCenter,
          SongView::tr("No song loaded — double-click a song in the browser."));
      return;
    }

    const QRect area(kGutterW, 0, width() - kGutterW, height());
    p.setClipRect(area);

    // Loop band across the whole ruler height.
    drawOverlays(p, m_sv, area, kGutterW, true);

    const qreal physicalPixel = logicalPhysicalPixel(dpr);
    const qreal roundingMargin = physicalPixel / 2.0;
    const double t0 = std::max(
        0.0, m_sv->tickAtContentX(area.left() - kGutterW - roundingMargin));
    const double t1 =
        m_sv->tickAtContentX(area.x() + area.width() - physicalPixel -
                             kGutterW + roundingMargin) +
        1;
    const auto indicatorColor = gridLineColor();
    // Beat labels recede a step past secondary text: blended a quarter of
    // the way into the ruler chrome so they read as texture next to the
    // bar numbers, in every theme.
    const QColor secondary =
        themes::color(themes::Role::song_view_secondary_text);
    const auto recede = [&](int fg, int bg) {
      return (191 * fg + 64 * bg + 127) / 255;
    };
    const QColor textColor(recede(secondary.red(), chrome.red()),
                           recede(secondary.green(), chrome.green()),
                           recede(secondary.blue(), chrome.blue()));

    const QRect ticks = tickRow();
    const int tickBottom = ticks.bottom();
    const QFontMetrics tickMetrics(p.font());
    const QFontMetrics beatMetrics(beatFont);
    const int tickBaseline = ticks.top() + tickMetrics.ascent();
    const auto barCapWidth = lyt::space(Space::Half);
    const auto indicatorRise = lyt::space(Space::Half);
    const auto labelGap = lyt::singlePixel();
    const auto beatDetailReserve = lyt::space(Space::Two);
    const bool drawBeatTicks = m_sv->pxPerBeat() >= 10.0;

    // Short sub-beat ticks at the snap grid, mirroring the roll's grid.
    p.setPen(indicatorColor);
    forEachSubGridLine(m_sv, t0, t1, [&](uint64_t tick, int level) {
      const qreal x = m_sv->displayX(double(tick), kGutterW, dpr);
      const int tickHeight =
          level == 1 ? lyt::space(Space::Half) : lyt::singlePixel();
      p.drawLine(QLineF(x, tickBottom - tickHeight + lyt::singlePixel(), x,
                        tickBottom));
    });

    // Bar numbers are the primary labels; the in-between beats only earn
    // "bar.beat" labels once a beat spans several label-widths, so the
    // ruler stays sparse until the zoom genuinely has room for detail.
    // One decision per paint, sized to the widest label in view, so a
    // ruler never shows some beat labels while suppressing others.
    const QColor barTextColor =
        themes::color(themes::Role::song_view_primary_text);
    const double beatLabelZoomFactor = 3.0;
    int widestDetailWidth = 0;
    m_sv->forEachGridLine(
        uint64_t(t0), uint64_t(t1),
        [&](uint64_t, bool, int barNumber, int beatNumber) {
          widestDetailWidth = std::max(
              widestDetailWidth,
              beatMetrics.horizontalAdvance(
                  QStringLiteral("%1.%2").arg(barNumber).arg(beatNumber)));
        });
    const bool showBeatLabels =
        m_sv->pxPerBeat() >=
        beatLabelZoomFactor * (barCapWidth + 2 * labelGap + beatDetailReserve +
                               widestDetailWidth);
    qreal lastLabelRight = area.left() - labelGap;
    m_sv->forEachGridLine(
        uint64_t(t0), uint64_t(t1),
        [&](uint64_t tick, bool isBar, int barNumber, int beatNumber) {
          const qreal x = m_sv->displayX(double(tick), kGutterW, dpr);
          const auto detailedLabel =
              QStringLiteral("%1.%2").arg(barNumber).arg(beatNumber);
          if (!isBar && !showBeatLabels) {
            if (drawBeatTicks) {
              p.setPen(indicatorColor);
              p.drawLine(
                  QLineF(x, ticks.center().y() - indicatorRise, x, tickBottom));
            }
            return;
          }
          const auto label = isBar ? QString::number(barNumber) : detailedLabel;
          const int labelWidth =
              (isBar ? tickMetrics : beatMetrics).horizontalAdvance(label);
          const qreal labelX = x + barCapWidth;
          if (labelX < lastLabelRight + labelGap) {
            if (!isBar && drawBeatTicks) {
              p.setPen(indicatorColor);
              p.drawLine(
                  QLineF(x, ticks.center().y() - indicatorRise, x, tickBottom));
            }
            return;
          }
          p.setPen(indicatorColor);
          if (isBar) {
            const int indicatorTop = ticks.top() - indicatorRise;
            p.drawLine(QLineF(x, indicatorTop, x, tickBottom));
            p.drawLine(QLineF(x, indicatorTop, x + barCapWidth, indicatorTop));
          } else {
            p.drawLine(
                QLineF(x, ticks.center().y() - indicatorRise, x, tickBottom));
          }
          p.setPen(isBar ? barTextColor : textColor);
          p.setFont(isBar ? rulerFont : beatFont);
          p.drawText(QPointF(labelX, tickBaseline), label);
          p.setFont(rulerFont);
          lastLabelRight = labelX + labelWidth;
        });

    const MidiTimeline *tl = m_sv->timeline();
    p.setFont(typography::bold(rulerFont));

    const QRect markers = markerRow();
    const int markerBaseline = textBaseline(markers, p.fontMetrics());

    // Time-signature chips in the marker row; a placeholder 4/4 shows
    // at tick 0 while no 0x58 meta governs the opening bars.
    for (const SigChip &chip : sigChips()) {
      if (chip.x > area.right() || chip.labelX + chip.labelW < area.left())
        continue;
      p.setPen(palette().color(chip.implicit ? QPalette::PlaceholderText
                                             : QPalette::WindowText));
      p.drawLine(QLineF(chip.x, markers.top(), chip.x, markers.bottom()));
      if (chip.labelW > 0)
        p.drawText(QPointF(chip.labelX, markerBaseline),
                   timeSigLabel(chip.numerator, chip.denomPow2));
    }

    // Loop bracket glyphs above the band edges.
    p.setPen(loopEdge());
    if (tl->loopStartTick != UINT64_MAX) {
      const qreal x = m_sv->displayX(double(tl->loopStartTick), kGutterW, dpr) +
                      lyt::space(Space::Half);
      p.drawText(QPointF(x, markerBaseline), QStringLiteral("["));
    }
    if (tl->loopEndTick != UINT64_MAX) {
      const qreal x = m_sv->displayX(double(tl->loopEndTick), kGutterW, dpr) +
                      lyt::space(Space::Half);
      p.drawText(QPointF(x, markerBaseline), QStringLiteral("]"));
    }

    // Marker / time-signature drag preview.
    const auto markerStroke = lyt::space(Space::Half);
    if (m_dragMarker >= 0 || m_dragTimeSig) {
      const qreal x = m_sv->displayX(double(m_dragTick), kGutterW, dpr);
      p.setPen(QPen(m_dragMarker >= 0 ? loopEdge()
                                      : palette().color(QPalette::WindowText),
                    markerStroke));
      p.drawLine(QLineF(x, 0, x, height()));
    }

    // Time-selection edge handles (the 1px band edges come from
    // drawOverlays); the marker row is their grab zone, while the tick
    // row stays scrub territory.
    const SongView::TimeSelection &tsel = m_sv->timeSelection();
    if (tsel.active()) {
      p.setPen(QPen(themes::color(themes::Role::song_view_selection_edge),
                    markerStroke));
      const qreal sx0 = m_sv->displayX(double(tsel.startTick), kGutterW, dpr);
      const qreal sx1 = m_sv->displayX(double(tsel.endTick), kGutterW, dpr);
      p.drawLine(QLineF(sx0, markers.top(), sx0, markers.bottom()));
      p.drawLine(QLineF(sx1, markers.top(), sx1, markers.bottom()));
    }
  }

  void wheelEvent(QWheelEvent *event) override {
    // Same bindings as the roll's notes area: plain wheel zooms the
    // timeline; Shift (or a trackpad's horizontal delta) scrolls it.
    const QPoint delta = wheelDelta(event);
    if (event->modifiers() & Qt::ShiftModifier) {
      m_sv->scrollByPx(-(delta.y() ? delta.y() : delta.x()));
    } else if (delta.x() && !delta.y()) {
      m_sv->scrollByPx(-delta.x());
    } else {
      const double zoomDelta = wheelAngleUnits(event);
      if (zoomDelta != 0.0)
        m_sv->zoomAroundContentX(std::pow(1.0015, zoomDelta),
                                 event->position().x() - kGutterW);
    }
    event->accept();
  }

  void mousePressEvent(QMouseEvent *event) override {
    SongDocument *doc = m_sv->document();
    const MidiTimeline *tl = m_sv->timeline();
    if (!tl || event->position().x() < kGutterW)
      return;
    const uint64_t clickTick =
        m_sv->snapTick(m_sv->tickAtContentX(event->position().x() - kGutterW));

    if (event->button() == Qt::RightButton) {
      // Deferred: a drag from here sweeps out a time selection;
      // releasing in place opens the loop/selection menu. Resolved in
      // mouseReleaseEvent.
      if (!doc)
        return;
      m_rightPress = true;
      m_rightPressPos = event->position();
      m_selAnchor = clickTick;
      return;
    }
    if (event->button() != Qt::LeftButton)
      return;
    m_dragMarker = doc ? hitMarker(event->position()) : -1;
    if (m_dragMarker >= 0) {
      m_dragTick = clickTick;
      update();
      return;
    }
    uint64_t sigTick;
    int sigNum, sigDen;
    bool sigImplicit;
    if (doc &&
        hitTimeSigChip(event->position(), &sigTick, &sigNum, &sigDen,
                       &sigImplicit) &&
        !sigImplicit) {
      // Drag moves the signature; starting at its own tick keeps a
      // plain click (and the first half of a double-click) a no-op.
      m_dragTimeSig = true;
      m_dragTimeSigFrom = sigTick;
      m_dragTick = sigTick;
      update();
      return;
    }
    m_dragSelEdge = doc ? hitSelEdge(event->position()) : -1;
    if (m_dragSelEdge >= 0)
      return;
    // Elsewhere on the ruler: place the edit cursor (drag scrubs it;
    // playback follows on release).
    m_placingCursor = true;
    m_sv->setEditCursorTick(clickTick);
  }

  void mouseMoveEvent(QMouseEvent *event) override {
    const auto dragTick = [this, event] {
      return m_sv->snapTick(m_sv->tickAtContentX(
          std::max(qreal(kGutterW), event->position().x()) - kGutterW));
    };
    if (m_rightPress) {
      if (!m_selSweep &&
          (event->position().toPoint() - m_rightPressPos.toPoint())
                  .manhattanLength() >= QApplication::startDragDistance())
        m_selSweep = true;
      if (m_selSweep) {
        const uint64_t tick = dragTick();
        SongView::TimeSelection sel;
        sel.startTick = std::min(m_selAnchor, tick);
        sel.endTick = std::max(m_selAnchor, tick);
        m_sv->setTimeSelection(sel); // scope: the selected tracks
      }
      return;
    }
    if (m_dragMarker >= 0 || m_dragTimeSig) {
      m_dragTick = dragTick();
      update();
      return;
    }
    if (m_dragSelEdge >= 0) {
      // Selection edges move live (view state, unlike the loop
      // markers' commit-on-release document edit).
      SongView::TimeSelection sel = m_sv->timeSelection();
      const uint64_t tick = dragTick();
      if (m_dragSelEdge == 0)
        sel.startTick = tick;
      else
        sel.endTick = tick;
      if (sel.startTick > sel.endTick) {
        std::swap(sel.startTick, sel.endTick);
        m_dragSelEdge ^= 1;
      }
      m_sv->setTimeSelection(sel);
      return;
    }
    if (m_placingCursor) {
      m_sv->setEditCursorTick(dragTick());
      return;
    }
    uint64_t sigTick;
    int sigNum, sigDen;
    bool sigImplicit;
    setCursor(m_sv->document() &&
                      (hitMarker(event->position()) >= 0 ||
                       hitSelEdge(event->position()) >= 0 ||
                       hitTimeSigChip(event->position(), &sigTick, &sigNum,
                                      &sigDen, &sigImplicit))
                  ? Qt::SplitHCursor
                  : Qt::ArrowCursor);
  }

  void mouseReleaseEvent(QMouseEvent *event) override {
    if (event->button() == Qt::RightButton && m_rightPress) {
      m_rightPress = false;
      if (m_selSweep) {
        m_selSweep = false;
        if (m_sv->timeSelection().active())
          m_sv->announceTimeSelection();
        else
          m_sv->clearTimeSelection();
      } else {
        showRulerMenu(m_selAnchor, event->globalPosition().toPoint());
      }
      return;
    }
    if (event->button() != Qt::LeftButton)
      return;
    if (m_placingCursor) {
      m_placingCursor = false;
      m_sv->commitEditCursor(m_sv->editCursorTick());
      return;
    }
    if (m_dragSelEdge >= 0) {
      m_dragSelEdge = -1;
      if (m_sv->timeSelection().active())
        m_sv->announceTimeSelection();
      else
        m_sv->clearTimeSelection(); // edges dragged together
      return;
    }
    if (m_dragTimeSig) {
      m_dragTimeSig = false;
      if (SongDocument *doc = m_sv->document())
        doc->moveTimeSig(m_dragTimeSigFrom, m_dragTick);
      update();
      return;
    }
    if (m_dragMarker < 0)
      return;
    const bool endMarker = m_dragMarker == 1;
    m_dragMarker = -1;
    if (SongDocument *doc = m_sv->document())
      doc->setLoopTick(endMarker, int64_t(m_dragTick));
    update();
  }

  void mouseDoubleClickEvent(QMouseEvent *event) override {
    SongDocument *doc = m_sv->document();
    uint64_t sigTick;
    int numerator, denomPow2;
    bool implicit;
    if (event->button() != Qt::LeftButton || !doc ||
        !hitTimeSigChip(event->position(), &sigTick, &numerator, &denomPow2,
                        &implicit))
      return;
    // The first press of the double-click armed a chip drag or cursor
    // placement; cancel it before the modal editor swallows the release.
    m_dragTimeSig = false;
    m_placingCursor = false;
    if (askTimeSignature(this, &numerator, &denomPow2))
      doc->setTimeSig(sigTick, numerator, denomPow2);
    update();
  }

private:
  QRect markerRow() const { return QRect(0, 0, width(), m_markerHeight); }

  QRect tickRow() const {
    return QRect(0, m_markerHeight, width(), height() - m_markerHeight);
  }

  int textBaseline(const QRect &row, const QFontMetrics &metrics) const {
    return row.top() + (row.height() - metrics.height()) / 2 + metrics.ascent();
  }

  // Loop-marker and selection-edge grab zones live in the marker row —
  // where the bracket glyphs and edge handles are drawn — so the tick row
  // always scrubs the edit cursor even directly on a marker line.

  // 0 = start marker, 1 = end marker, -1 = neither near pos.
  int hitMarker(QPointF pos) const {
    const MidiTimeline *tl = m_sv->timeline();
    if (!tl || !QRectF(markerRow()).contains(pos))
      return -1;
    const auto markerHitHalfWidth = lyt::space(Space::Two);
    const qreal dpr = devicePixelRatioF();
    if (tl->loopStartTick != UINT64_MAX &&
        std::abs(m_sv->displayX(double(tl->loopStartTick), kGutterW, dpr) -
                 pos.x()) <= markerHitHalfWidth)
      return 0;
    if (tl->loopEndTick != UINT64_MAX &&
        std::abs(m_sv->displayX(double(tl->loopEndTick), kGutterW, dpr) -
                 pos.x()) <= markerHitHalfWidth)
      return 1;
    return -1;
  }

  // One time-signature chip as laid out in the marker row.
  struct SigChip {
    uint64_t tick;
    int numerator;
    int denomPow2;
    bool implicit; // no 0x58 meta behind it (editing one creates the event)
    qreal x;       // stem position (widget coords)
    qreal labelX;  // label left edge, nudged right past a loop bracket
    qreal labelW;  // 0: label hidden behind the next chip (stem only)
  };

  // Chip layout shared by paint and hit-testing: shadowed same-tick
  // duplicates dropped, labels nudged past a loop bracket glyph sitting on
  // the same spot, and a label hidden (stem only) when it would run into
  // the next chip — zooming in separates them again.
  std::vector<SigChip> sigChips() const {
    std::vector<SigChip> chips;
    const MidiTimeline *tl = m_sv->timeline();
    if (!tl)
      return chips;
    const qreal dpr = devicePixelRatioF();
    const auto boldFont = typography::bold(font());
    const QFontMetrics fm(boldFont);
    const auto labelInset = lyt::space(Space::Half);
    const auto add = [&](uint64_t tick, int numerator, int denomPow2,
                         bool implicit) {
      const qreal x = m_sv->displayX(double(tick), kGutterW, dpr);
      chips.push_back(
          {tick, numerator, denomPow2, implicit, x, x + labelInset,
           qreal(fm.horizontalAdvance(timeSigLabel(numerator, denomPow2)))});
    };
    if (tl->timeSigs.empty() || tl->timeSigs.front().tick != 0)
      add(0, 4, 2, true);
    for (size_t i = 0; i < tl->timeSigs.size(); i++) {
      if (i + 1 < tl->timeSigs.size() &&
          tl->timeSigs[i + 1].tick == tl->timeSigs[i].tick)
        continue; // shadowed duplicate: the last at a tick wins
      const TimeSigPoint &ts = tl->timeSigs[i];
      add(ts.tick, ts.numerator ? ts.numerator : 4, ts.denomPow2, false);
    }
    const uint64_t loops[2] = {tl->loopStartTick, tl->loopEndTick};
    const qreal bracketWidth = fm.horizontalAdvance(QStringLiteral("["));
    for (SigChip &chip : chips) {
      for (uint64_t loopTick : loops) {
        if (loopTick == UINT64_MAX)
          continue;
        const qreal bracketStart =
            m_sv->displayX(double(loopTick), kGutterW, dpr) + labelInset;
        const qreal bracketRight = bracketStart + bracketWidth;
        if (bracketRight > chip.labelX &&
            bracketStart < chip.labelX + chip.labelW)
          chip.labelX = bracketRight + labelInset;
      }
    }
    for (size_t i = 0; i + 1 < chips.size(); i++) {
      if (chips[i].labelX + chips[i].labelW + labelInset > chips[i + 1].x)
        chips[i].labelW = 0;
    }
    return chips;
  }

  // Chip hit-test in the ruler's top half, including the placeholder 4/4
  // at tick 0. Fills the chip's tick and values.
  bool hitTimeSigChip(QPointF pos, uint64_t *tick, int *numerator,
                      int *denomPow2, bool *implicit) const {
    if (!QRectF(markerRow()).contains(pos))
      return false;
    const std::vector<SigChip> chips = sigChips();
    const auto stemHitHalfWidth = lyt::space(Space::One);
    const auto hitFuzz = lyt::singlePixel();
    // Back to front so the rightmost chip wins where chips crowd.
    for (auto it = chips.rbegin(); it != chips.rend(); ++it) {
      const bool onStem = std::abs(it->x - pos.x()) <= stemHitHalfWidth;
      const bool onLabel = it->labelW > 0 && pos.x() >= it->labelX - hitFuzz &&
                           pos.x() <= it->labelX + it->labelW + hitFuzz;
      if (onStem || onLabel) {
        *tick = it->tick;
        *numerator = it->numerator;
        *denomPow2 = it->denomPow2;
        *implicit = it->implicit;
        return true;
      }
    }
    return false;
  }

  // Values in effect at tick (4/4 before any 0x58 meta).
  void sigAtTick(uint64_t tick, int *numerator, int *denomPow2) const {
    *numerator = 4;
    *denomPow2 = 2;
    for (const TimeSigPoint &ts : m_sv->timeline()->timeSigs) {
      if (ts.tick > tick)
        break;
      *numerator = ts.numerator ? ts.numerator : 4;
      *denomPow2 = ts.denomPow2;
    }
  }

  // 0 = selection start edge, 1 = end edge, -1 = neither near pos.
  int hitSelEdge(QPointF pos) const {
    const SongView::TimeSelection &sel = m_sv->timeSelection();
    if (!sel.active() || !QRectF(markerRow()).contains(pos))
      return -1;
    const auto markerHitHalfWidth = lyt::space(Space::Two);
    const qreal dpr = devicePixelRatioF();
    if (std::abs(m_sv->displayX(double(sel.startTick), kGutterW, dpr) -
                 pos.x()) <= markerHitHalfWidth)
      return 0;
    if (std::abs(m_sv->displayX(double(sel.endTick), kGutterW, dpr) -
                 pos.x()) <= markerHitHalfWidth)
      return 1;
    return -1;
  }

  void showRulerMenu(uint64_t clickTick, const QPoint &globalPos) {
    SongDocument *doc = m_sv->document();
    const MidiTimeline *tl = m_sv->timeline();
    if (!doc || !tl)
      return;
    QMenu menu(this);
    QAction *setStart = menu.addAction(SongView::tr("Set loop start here"));
    QAction *setEnd = menu.addAction(SongView::tr("Set loop end here"));
    QAction *remove = menu.addAction(SongView::tr("Remove loop markers"));
    remove->setEnabled(tl->loopStartTick != UINT64_MAX ||
                       tl->loopEndTick != UINT64_MAX);
    QAction *loopFromSel = nullptr;
    QAction *removeContents = nullptr;
    QAction *clearSel = nullptr;
    const SongView::TimeSelection sel = m_sv->timeSelection();
    if (sel.active()) {
      menu.addSeparator();
      loopFromSel = menu.addAction(SongView::tr("Set loop to selection"));
      removeContents = menu.addAction(
          SongView::tr("Remove selection contents (shift left)"));
      clearSel = menu.addAction(SongView::tr("Clear time selection"));
    }
    menu.addSeparator();
    uint64_t sigTick = clickTick;
    int sigNum, sigDen;
    bool sigImplicit = true;
    const bool onChip = hitTimeSigChip(m_rightPressPos, &sigTick, &sigNum,
                                       &sigDen, &sigImplicit);
    if (!onChip)
      sigAtTick(clickTick, &sigNum, &sigDen);
    QAction *editSig =
        menu.addAction(onChip ? SongView::tr("Edit time signature…")
                              : SongView::tr("Set time signature here…"));
    QAction *removeSig = menu.addAction(SongView::tr("Remove time signature"));
    removeSig->setEnabled(onChip && !sigImplicit);
    QAction *chosen = menu.exec(globalPos);
    if (chosen == setStart) {
      doc->setLoopTick(false, int64_t(clickTick));
    } else if (chosen == setEnd) {
      doc->setLoopTick(true, int64_t(clickTick));
    } else if (chosen == remove) {
      // Two commands; undo restores them one at a time.
      if (tl->loopStartTick != UINT64_MAX)
        doc->setLoopTick(false, -1);
      if (m_sv->timeline()->loopEndTick != UINT64_MAX)
        doc->setLoopTick(true, -1);
    } else if (chosen && chosen == loopFromSel) {
      // Same two-command shape as "Remove loop markers".
      doc->setLoopTick(false, int64_t(sel.startTick));
      doc->setLoopTick(true, int64_t(sel.endTick));
    } else if (chosen && chosen == removeContents) {
      m_sv->removeTimeSelectionContents();
    } else if (chosen && chosen == clearSel) {
      m_sv->clearTimeSelection();
    } else if (chosen == editSig) {
      if (askTimeSignature(this, &sigNum, &sigDen))
        doc->setTimeSig(sigTick, sigNum, sigDen);
    } else if (chosen == removeSig) {
      doc->deleteTimeSig(sigTick);
    }
  }

  SongView *m_sv;
  int m_markerHeight = 0;
  int m_dragMarker = -1;
  uint64_t m_dragTick = 0;
  bool m_dragTimeSig = false;     // chip drag is live; commits moveTimeSig
  uint64_t m_dragTimeSigFrom = 0; // the dragged signature's original tick
  bool m_placingCursor = false;
  bool m_rightPress = false; // right button held; sweep vs. menu undecided
  bool m_selSweep = false;   // right-drag time-selection sweep is live
  QPointF m_rightPressPos;
  uint64_t m_selAnchor = 0;         // snapped tick of the right press
  int m_dragSelEdge = -1;           // selection edge being left-dragged (0/1)
  QComboBox *m_divCombo = nullptr;  // minimum snap subdivision (gutter)
  QComboBox *m_feelCombo = nullptr; // straight / triplet
};

namespace {

// The edge cursors are baked pixmaps, so they carry the screen DPR they were
// rendered at. Qt 6.2 has no QEvent::DevicePixelRatioChange; the hover path
// re-bakes them whenever the widget's DPR no longer matches.
struct MidiCursors {
  qreal dpr;
  QCursor leftEdge;
  QCursor rightEdge;
};

// A pixmap cursor's default hotspot is its logical center, which most
// backends scale to device pixels themselves — but Qt's xcb backend (through
// at least the current dev branch) forwards the hotspot to X unscaled beside
// the full device-pixel image, so at DPR > 1 the glyph would hang down-right
// of the pointer. Hand xcb the center in device pixels; keep the logical
// default elsewhere (e.g. Windows multiplies by the screen scale itself).
QCursor centeredCursor(const QPixmap &pm) {
  const qreal dpr = QGuiApplication::platformName() == QLatin1String("xcb")
                        ? 1.0
                        : pm.devicePixelRatio();
  return QCursor(pm, qRound(pm.width() / (2.0 * dpr)),
                 qRound(pm.height() / (2.0 * dpr)));
}

MidiCursors loadMidiCursors(qreal devicePixelRatio) {
  const QSize cursorSize(24, 24);
  const QIcon leftEdge(QStringLiteral(":/cursors/left-drag.png"));
  const QIcon rightEdge(QStringLiteral(":/cursors/right-drag.png"));
  return {devicePixelRatio,
          centeredCursor(leftEdge.pixmap(cursorSize, devicePixelRatio)),
          centeredCursor(rightEdge.pixmap(cursorSize, devicePixelRatio))};
}

QRectF noteFrame(const QPainter &painter, const QRectF &noteRect,
                 int insetPixels) {
  const qreal physicalPixel =
      logicalPhysicalPixel(painter.device()->devicePixelRatioF());
  const qreal insetDips = insetPixels * physicalPixel;
  return noteRect.adjusted(0, 0, -physicalPixel, -physicalPixel)
      .adjusted(insetDips, insetDips, -insetDips, -insetDips);
}

// Largest frame thickness (up to requestedPixels) that still leaves at
// least one physical pixel of face visible between the top and bottom
// strips; 0 when not even a one-pixel frame fits. Fitting uses the row
// height ONLY: rows are uniform at a given zoom, so every note at that
// zoom carries the same frame weight — a narrow note lets its side strips
// overlap into a solid sliver rather than shedding the frame its wider
// neighbors keep.
int fittedFrameThickness(const QPainter &painter, const QRectF &rect,
                         int requestedPixels, int insetPixels) {
  const qreal devicePixelRatio = painter.device()->devicePixelRatioF();
  const int heightPixels = qRound(rect.height() * devicePixelRatio);
  return std::clamp((heightPixels - 1) / 2 - insetPixels, 0, requestedPixels);
}

// Returns the thickness actually painted (0 = nothing fit).
int drawRectFrame(QPainter &painter, const QRectF &rect, const QColor &color,
                  int thicknessPixels, int insetPixels = 0) {
  thicknessPixels =
      fittedFrameThickness(painter, rect, thicknessPixels, insetPixels);
  if (thicknessPixels <= 0)
    return 0;

  // Paint one solid ring around the note box. Separate cosmetic outlines
  // can quantize onto non-adjacent device rows at fractional scale
  // factors, exposing the note face between them.
  const qreal devicePixelRatio = painter.device()->devicePixelRatioF();
  const qreal physicalPixel = logicalPhysicalPixel(devicePixelRatio);
  const qreal insetDips = insetPixels * physicalPixel;
  const qreal thicknessDips = thicknessPixels * physicalPixel;
  const QRectF frame =
      rect.adjusted(insetDips, insetDips, -insetDips, -insetDips);
  painter.fillRect(
      QRectF(frame.left(), frame.top(), frame.width(), thicknessDips), color);
  painter.fillRect(QRectF(frame.left(), frame.bottom() - thicknessDips,
                          frame.width(), thicknessDips),
                   color);
  const qreal sideHeight = std::max(0.0, frame.height() - 2 * thicknessDips);
  painter.fillRect(QRectF(frame.left(), frame.top() + thicknessDips,
                          thicknessDips, sideHeight),
                   color);
  painter.fillRect(QRectF(frame.right() - thicknessDips,
                          frame.top() + thicknessDips, thicknessDips,
                          sideHeight),
                   color);
  return thicknessPixels;
}

void drawNoteBoxBorder(QPainter &painter, const QRectF &noteBox,
                       bool unterminated, int insetPixels = 0) {
  const int borderPixels =
      songview::noteBorderPixels(painter.device()->devicePixelRatioF());
  if (!unterminated) {
    drawRectFrame(painter, noteBox, Qt::black, borderPixels, insetPixels);
    return;
  }
  const int thickness =
      fittedFrameThickness(painter, noteBox, borderPixels, insetPixels);
  if (thickness <= 0)
    return;

  painter.save();
  QPen borderPen(Qt::black, 0);
  borderPen.setCapStyle(Qt::FlatCap);
  borderPen.setJoinStyle(Qt::MiterJoin);
  borderPen.setDashPattern({4, 2});
  painter.setPen(borderPen);
  painter.setBrush(Qt::NoBrush);
  for (int pixel = 0; pixel < thickness; ++pixel)
    painter.drawRect(noteFrame(painter, noteBox, insetPixels + pixel));
  painter.restore();
}

int activeLaneValue(const SongViewModel &model, int track, uint8_t cc,
                    uint64_t tick, int defaultValue) {
  const AutoLane *lane = model.findLane(track, cc);
  if (!lane)
    return defaultValue;
  int value = defaultValue;
  for (const LanePoint &point : lane->points) {
    if (point.tick > tick)
      break;
    value = point.value;
  }
  return value;
}

std::optional<PsgVelocityContext>
psgVelocityContext(const SongView *sv, int track, uint64_t tick, uint8_t key) {
  const SongDocument *doc = sv ? sv->document() : nullptr;
  const LoadedVoiceGroup *voicegroup = sv ? sv->voicegroup() : nullptr;
  if (!doc || !voicegroup || track < 0 || track >= 16)
    return std::nullopt;

  const int program = sv->programAt(track, tick);
  if (program < 0 || program >= VOICEGROUP_SIZE)
    return std::nullopt;

  const ToneData &tone = voicegroup->voices[std::size_t(program)];
  const SongViewModel &model = sv->model();
  return makePsgVelocityContext(
      tone, key, activeLaneValue(model, track, 7, tick, 127),
      activeLaneValue(model, track, 10, tick, 64), doc->cfg().masterVolume);
}
} // namespace

// ---------------------------------------------------------------- PianoRoll

class PianoRoll : public QWidget {
public:
  explicit PianoRoll(SongView *sv)
      : QWidget(sv), m_sv(sv), m_cursors(loadMidiCursors(devicePixelRatioF())) {
    setObjectName(QStringLiteral("pianoRoll")); // findChild for tests
    setMinimumHeight(120);
    setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
    setMouseTracking(true);
    setFocusPolicy(Qt::ClickFocus);
    m_noteMenu = new NoteContextMenu(
        this, [this](QPointF globalPos) { return moveNoteMenu(globalPos); });
    connect(m_noteMenu, &QMenu::triggered, this, [this](QAction *action) {
      handleNoteMenuChoice(m_noteMenu->handleAction(action));
    });
  }

  // A mouse gesture is live (pan, note move/resize/velocity/draw, band or
  // time-selection sweep, a still-undecided press, keyboard gliss); the
  // playhead follow-scroll pauses while one runs so the view doesn't jump
  // under the cursor.
  bool gestureActive() const {
    return m_panning || m_drag != Drag::None || m_leftPress || m_rightPress ||
           m_kbdKey >= 0;
  }

  void cancelBandGesture() {
    if (m_drag == Drag::Band || (m_rightPress && !m_rightShift)) {
      stopBandAuditions();
      m_drag = Drag::None;
      m_rightPress = false;
      m_bandAdditive = false;
      update();
    } else {
      m_sv->clearProvisionalSelectionHighlight();
    }
  }
protected:
  void paintEvent(QPaintEvent *) override {
    QPainter p(this);
    p.fillRect(rect(),
               themes::color(themes::Role::song_view_piano_roll_background));
    if (!m_sv->timeline()) {
      drawKeyboard(p);
      return;
    }

    const QRect grid(kKeyboardW, 0, width() - kKeyboardW, height());
    p.setClipRect(grid);

    // Pitch row shading plus a hairline under every semitone row; C rows
    // keep the stronger octave delineator, on the same snapped edge as
    // the keyboard column's separators.
    const QColor accidentalRow = pianoRollAccidentalLaneColor();
    const QColor octaveLine =
        themes::color(themes::Role::song_view_piano_keyboard_separator);
    const QPen keyLinePen(gridLineColor(50), 0);
    const QPen octavePen(octaveLine, 0);
    for (int key = 0; key < 128; key++) {
      const QRectF row = keyRect(key, grid.left(), grid.width());
      if (row.bottom() <= 0 || row.top() >= height())
        continue;
      if (isBlackKey(key))
        p.fillRect(row, accidentalRow);
      p.setPen(key % 12 == 0 ? octavePen : keyLinePen);
      p.drawLine(QLineF(grid.left(), row.bottom(), grid.right(), row.bottom()));
    }

    drawGrid(p, m_sv, grid, kKeyboardW);

    // Notes: ghost pass (unselected tracks), then the selected track.
    const SongViewModel &model = m_sv->model();
    const int selected = m_sv->selectedTrack();
    drawNotes(p, model, selected, true);
    drawNotes(p, model, selected, false);
    drawDragPreview(p, model, selected);

    if (m_drag == Drag::Band) {
      const QRectF band = QRectF(m_pressPos, m_curPos).normalized();
      QColor c = themes::color(themes::Role::song_view_selection_edge);
      p.setPen(QPen(c, 1, Qt::DashLine));
      c.setAlpha(30);
      p.fillRect(band, c);
      p.drawRect(band);
    }

    drawOverlays(p, m_sv, grid, kKeyboardW,
                 m_sv->timeSelectionCoversTrack(m_sv->selectedTrack()));

    p.setClipping(false);
    drawKeyboard(p);
  }

  void wheelEvent(QWheelEvent *event) override {
    // Reaper-style bindings: plain wheel over the notes area zooms the
    // timeline, over the keyboard column it scrolls the note range.
    // Ctrl+wheel zooms the key height (the track-height analog); Shift
    // (or a trackpad's horizontal delta) scrolls horizontally.
    const QPoint delta = wheelDelta(event);
    const int d = delta.y() ? delta.y() : delta.x();
    if (event->modifiers() & Qt::ControlModifier) {
      m_sv->zoomKeyHeight(event);
    } else if (event->modifiers() & Qt::ShiftModifier) {
      m_sv->scrollByPx(-d);
    } else if (delta.x() && !delta.y()) {
      m_sv->scrollByPx(-delta.x());
    } else if (event->position().x() < kKeyboardW) {
      m_sv->scrollRollBy(-delta.y() / 2.0);
    } else {
      const double zoomDelta = wheelAngleUnits(event);
      if (zoomDelta != 0.0)
        m_sv->zoomAroundContentX(std::pow(1.0015, zoomDelta),
                                 event->position().x() - kKeyboardW);
    }
    event->accept();
  }

  void mousePressEvent(QMouseEvent *event) override {
    setFocus();
    if (!m_sv->timeline())
      return;

    if (event->button() == Qt::MiddleButton) {
      // Reaper-style pan: drag scrolls the roll on both axes.
      m_panning = true;
      m_panPos = event->globalPosition();
      setCursor(Qt::ClosedHandCursor);
      return;
    }

    // Keyboard column: audition the clicked key and select its lane on
    // the selected track.
    if (event->position().x() < kKeyboardW) {
      if (event->button() == Qt::LeftButton) {
        m_kbdKey = yToKey(event->position().y());
        auditionKey(m_kbdKey, 100);
        if (m_sv->document())
          selectKeyNotes(m_kbdKey);
      }
      return;
    }

    SongDocument *doc = m_sv->document();
    const ViewNote *hit = doc ? hitNote(event->position()) : nullptr;

    if (event->button() == Qt::RightButton) {
      // Deferred: a drag from here rubber-band-selects (with Shift, it
      // sweeps a full-height time selection instead); releasing in
      // place context-acts on the pressed note (or on the time
      // selection under the click, or clears the selections over empty
      // space). Resolved in mouseReleaseEvent.
      if (!doc)
        return;
      m_pressPos = m_curPos = event->position();
      m_rightPress = true;
      m_rightShift = event->modifiers() & Qt::ShiftModifier;
      m_bandAdditive = event->modifiers() & Qt::ControlModifier;
      m_rightAnchorTick = m_sv->snapTick(
          m_sv->tickAtContentX(event->position().x() - kKeyboardW));
      m_rightHit = hit != nullptr;
      if (hit)
        m_rightHitId = {hit->startTick, hit->key};
      return;
    }
    if (event->button() != Qt::LeftButton)
      return;

    m_pressPos = m_curPos = event->position();
    m_pressTick = m_sv->tickAtContentX(event->position().x() - kKeyboardW);
    m_pressKey = yToKey(event->position().y());
    m_dTick = 0;
    m_dKey = 0;
    m_dDur = 0;
    m_dVel = 0;

    if (hit) {
      const bool rightEdge = nearRightEdge(*hit, event->position());
      const bool leftEdge = nearLeftEdge(*hit, event->position());
      const int latchedVelocity = m_sv->canonicalNoteVelocity(
          hit->track, hit->startTick, hit->key, hit->velocity);
      // Ableton-style velocity gesture: with the bound modifier chord
      // held (Ctrl by default), a vertical drag from anywhere on the
      // note adjusts velocity. Deferred like the empty-space press:
      // the click action (Ctrl's selection toggle) resolves on
      // release, a drag past the threshold in mouseMoveEvent.
      const Qt::KeyboardModifiers gestureMods =
          keymap::Registry::instance().modifierBinding(
              QStringLiteral("roll.velocity_drag"));
      const Qt::KeyboardModifiers pressMods =
          event->modifiers() & (Qt::ControlModifier | Qt::ShiftModifier |
                                Qt::AltModifier | Qt::MetaModifier);
      if (gestureMods != Qt::NoModifier && pressMods == gestureMods &&
          !rightEdge && !leftEdge) {
        m_velModPress = true;
        m_velModMods = pressMods;
        m_velAnchor = *hit;
        m_velAudEff = mid2agbEffectiveVelocity(latchedVelocity);
        m_sv->announceNote(*hit);
        m_lastVelocity = uint8_t(latchedVelocity);
        auditionKey(hit->key, hit->velocity);
        m_auditioned = true;
        update();
        return;
      }
      std::vector<SongView::NoteId> ids = m_sv->selection();
      const SongView::NoteId id{hit->startTick, hit->key};
      if (event->modifiers() & Qt::ControlModifier) {
        if (!rightEdge && !leftEdge) {
          const auto it = std::find(ids.begin(), ids.end(), id);
          if (it != ids.end())
            ids.erase(it);
          else
            ids.push_back(id);
          m_sv->setSelection(std::move(ids));
        } else if (std::find(ids.begin(), ids.end(), id) == ids.end()) {
          // Ctrl+edge grab still resizes the whole selection. Join the
          // grabbed note to that selection instead of replacing it.
          ids.push_back(id);
          m_sv->setSelection(std::move(ids));
        }
      } else if (!m_sv->isSelected(*hit)) {
        m_sv->setSelection({id});
      }
      // Reaper-style velocity latch: touching a note makes its audible
      // velocity class the default for the next drawn note.
      m_lastVelocity = uint8_t(latchedVelocity);
      int grabbedVelocity = hit->velocity;
      if (rightEdge) {
        m_drag = Drag::Resize;
        m_gripTick = hit->endTick;
        m_gripOpposite = hit->startTick;
      } else if (leftEdge) {
        m_drag = Drag::ResizeLeft;
        m_gripTick = hit->startTick;
        m_gripOpposite = hit->endTick;
      } else if (nearVelocityHandle(*hit, event->position())) {
        m_drag = Drag::Velocity;
        m_velAnchor = *hit;
        m_velAudEff = mid2agbEffectiveVelocity(latchedVelocity);
        beginVelocityDrag();
        ViewNote preview = *hit;
        preview.velocity = uint8_t(latchedVelocity);
        m_sv->announceNote(preview);
        grabbedVelocity = latchedVelocity;
      } else {
        m_drag = Drag::Move;
      }
      if (m_drag != Drag::Velocity)
        m_sv->announceNote(*hit);
      // Sound the grabbed note so a press gives the same pitch feedback
      // a drag already does.
      auditionKey(hit->key, grabbedVelocity);
      m_auditioned = true;
    } else if (doc) {
      // Empty space: deferred, Reaper-style. A horizontal drag from
      // here draws a note (resolved in mouseMoveEvent); releasing in
      // place parks the edit cursor at the click instead. A
      // double-click draws immediately (mouseDoubleClickEvent).
      m_leftPress = true;
      m_sv->clearSelection();
      // Sound the clicked row at the latched velocity so a plain
      // press gives the same pitch feedback a draw already does.
      auditionKey(m_pressKey, m_lastVelocity);
      m_auditioned = true;
    } else {
      // Read-only (no document): park the edit cursor at the click,
      // like the ruler; playback follows when running.
      m_sv->commitEditCursor(m_sv->snapTick(m_pressTick));
    }
    update();
  }

  void mouseDoubleClickEvent(QMouseEvent *event) override {
    // Double-click on empty space drops a grid-sized note (committed on
    // release; dragging before release still sizes it); on a note it
    // deletes that note. Anywhere else a fast click-click behaves as two
    // presses — Qt replaces the second press with this event.
    SongDocument *doc = m_sv->document();
    if (event->button() == Qt::LeftButton && doc &&
        event->position().x() >= kKeyboardW) {
      setFocus();
      if (const ViewNote *hit = hitNote(event->position())) {
        DocNote note;
        if (doc->findNote(m_sv->selectedTrack(), hit->startTick, hit->key,
                          &note)) {
          doc->deleteNotes({note});
          m_sv->clearSelection();
        }
        return;
      }
      m_pressPos = m_curPos = event->position();
      m_pressTick = m_sv->tickAtContentX(event->position().x() - kKeyboardW);
      m_pressKey = yToKey(event->position().y());
      beginDraw();
      return;
    }
    mousePressEvent(event);
  }

  void mouseMoveEvent(QMouseEvent *event) override {
    // A velocity drag moves the cursor vertically while the note's
    // pitch stays put; the mark pins to the note so the readout
    // doesn't wander off its row.
    setHoverKey(m_drag == Drag::Velocity ? m_velAnchor.key
                                         : yToKey(event->position().y()));
    if (m_panning) {
      const QPointF d = event->globalPosition() - m_panPos;
      m_panPos = event->globalPosition();
      m_sv->scrollByPx(-d.x());
      m_sv->scrollRollBy(-d.y());
      return;
    }
    if (m_kbdKey >= 0) {
      // Keyboard column: dragging glisses — the sounding key follows
      // the cursor (the engine's mono preview releases the old key).
      const int key = yToKey(event->position().y());
      if (key != m_kbdKey) {
        m_kbdKey = key;
        auditionKey(m_kbdKey, 100);
      }
      return;
    }
    m_curPos = event->position();
    if (m_rightPress && m_drag == Drag::None &&
        (event->pos() - m_pressPos.toPoint()).manhattanLength() >=
            QApplication::startDragDistance()) {
      m_drag = m_rightShift ? Drag::TimeSel : Drag::Band;
      m_bandAud.clear();
      m_bandAdditive = event->modifiers() & Qt::ControlModifier;
    }
    if (m_leftPress && m_drag == Drag::None) {
      // The pressed row's preview glisses with the cursor, like the
      // keyboard column; a draw started below anchors on the new row.
      const int key = yToKey(event->position().y());
      if (key != m_pressKey) {
        m_pressKey = key;
        auditionKey(key, m_lastVelocity);
        m_auditioned = true;
      }
    }
    if (m_leftPress && m_drag == Drag::None &&
        event->position().toPoint().x() != m_pressPos.toPoint().x()) {
      // The deferred empty-space press turns out to be a draw gesture.
      // ANY horizontal travel starts it — no drag threshold — so the
      // pending note appears immediately; this same event falls
      // through to the Draw branch, which sizes it from the cursor
      // (one snap cell until the drag crosses the next snap line).
      beginDraw();
    }
    if (m_velModPress && m_drag == Drag::None) {
      // A stationary modifier-click remains a selection toggle, but the first
      // intentional vertical pixel begins velocity editing. The same event
      // falls through to the Velocity branch, which measures from the press.
      if (std::abs(event->pos().y() - m_pressPos.toPoint().y()) <
          kVelocityDragDistance)
        return;
      m_velModPress = false;
      if (!m_sv->isSelected(m_velAnchor)) {
        const SongView::NoteId id{m_velAnchor.startTick, m_velAnchor.key};
        if (m_velModMods & Qt::ControlModifier) {
          // Ctrl's velocity gesture joins the note to the existing bulk
          // selection, then applies the drag to the whole selection.
          std::vector<SongView::NoteId> ids = m_sv->selection();
          ids.push_back(id);
          m_sv->setSelection(std::move(ids));
        } else {
          m_sv->setSelection({id});
        }
      }
      m_drag = Drag::Velocity;
      // The pass at the top of this event ran before the drag
      // existed; re-pin the mark to the note's row now.
      setHoverKey(m_velAnchor.key);
      beginVelocityDrag();
    }
    if (m_drag == Drag::None) {
      // Hover cursor: resize handle at note left/right edges, velocity
      // handle along the note's velocity bar (when zoomed in enough).
      if (m_cursors.dpr != devicePixelRatioF())
        m_cursors = loadMidiCursors(devicePixelRatioF());
      const ViewNote *hit =
          m_sv->document() && event->position().x() >= kKeyboardW
              ? hitNote(event->position())
              : nullptr;
      // Resize edges win over both velocity-hover paths.
      const Qt::KeyboardModifiers hoverMods =
          event->modifiers() & (Qt::ControlModifier | Qt::ShiftModifier |
                                Qt::AltModifier | Qt::MetaModifier);
      if (hit && nearRightEdge(*hit, event->position()))
        setCursor(m_cursors.rightEdge);
      else if (hit && nearLeftEdge(*hit, event->position()))
        setCursor(m_cursors.leftEdge);
      else if (hit && hoverMods != Qt::NoModifier &&
               hoverMods == keymap::Registry::instance().modifierBinding(
                                QStringLiteral("roll.velocity_drag")))
        setCursor(Qt::SizeVerCursor);
      else if (hit && nearVelocityHandle(*hit, event->position()))
        setCursor(Qt::SizeVerCursor);
      else
        setCursor(Qt::ArrowCursor);
      return;
    }

    const double tick =
        m_sv->tickAtContentX(event->position().x() - kKeyboardW);
    const int64_t grid =
        int64_t(m_sv->snapTicksAt(uint64_t(std::max(0.0, m_pressTick))));
    const int64_t snappedD =
        int64_t(std::llround((tick - m_pressTick) / double(grid))) * grid;

    if (m_drag == Drag::Move) {
      const int dKey = yToKey(event->position().y()) - m_pressKey;
      if (snappedD != m_dTick || dKey != m_dKey) {
        m_dTick = snappedD;
        if (dKey != m_dKey) {
          m_dKey = dKey;
          // Audition the new pitch while dragging vertically.
          const std::vector<DocNote> notes = selectedDocumentNotes(*m_sv);
          if (!notes.empty()) {
            const int key = std::clamp(int(notes.front().key) + m_dKey, 0, 127);
            auditionKey(key, notes.front().velocity);
            m_auditioned = true;
          }
        }
        update();
      }
    } else if (m_drag == Drag::Resize || m_drag == Drag::ResizeLeft) {
      // Snap the dragged edge to absolute ruler grid lines, not offsets from
      // its original (possibly off-grid) position. Keep at least one tick.
      const double desired = double(m_gripTick) + (tick - m_pressTick);
      const uint64_t snapped =
          m_drag == Drag::Resize
              ? std::max(m_sv->snapTick(desired),
                         m_sv->snapTickUp(double(m_gripOpposite) + 1.0))
              : std::min(m_sv->snapTick(desired),
                         m_sv->snapTickDown(double(m_gripOpposite) - 1.0));
      const int64_t delta = std::abs(desired - double(m_gripTick)) <
                                    std::abs(desired - double(snapped))
                                ? 0
                                : int64_t(snapped) - int64_t(m_gripTick);
      int64_t &target = m_drag == Drag::Resize ? m_dDur : m_dTick;
      if (delta != target) {
        target = delta;
        update();
      }
    } else if (m_drag == Drag::Velocity) {
      const int dv = m_pressPos.toPoint().y() - event->pos().y(); // up = louder
      if (dv != m_dVel) {
        m_dVel = dv;
        const int vel = m_sv->canonicalNoteVelocity(
            m_velAnchor.track, m_velAnchor.startTick, m_velAnchor.key,
            int(m_velAnchor.velocity) + m_dVel);
        ViewNote preview = m_velAnchor;
        preview.velocity = uint8_t(vel);
        m_sv->announceNote(preview);
        // DirectSound keeps its mid2agb-step transition; CGB detents
        // change this value only when the hardware class changes.
        const int eff = mid2agbEffectiveVelocity(vel);
        if (eff != m_velAudEff) {
          m_velAudEff = eff;
          auditionKey(m_velAnchor.key, vel);
          m_auditioned = true;
        }
        m_sv->updateNoteViews();
      }
    } else if (m_drag == Drag::Draw) {
      // The edge under the cursor follows it: right of the anchor cell
      // the end grows (rounded up to the next snap line, never shorter
      // than one snap cell); left of it the start moves back (snapped
      // down) with the end pinned to the anchor cell. The key follows the
      // cursor vertically — a slight misclick on mouse-down is fixable
      // mid-gesture, with the new pitch auditioned.
      const uint64_t anchor = m_drawAnchor;
      uint64_t start = anchor;
      int64_t dur;
      if (tick >= double(anchor)) {
        const uint64_t end =
            std::max(anchor + uint64_t(grid), m_sv->snapTickUp(tick));
        dur = int64_t(end - anchor);
      } else {
        start = m_sv->snapTickDown(tick);
        dur = int64_t(anchor + uint64_t(grid) - start);
      }
      const int key = yToKey(event->position().y());
      if (start != m_drawTick || dur != m_drawDur || key != m_drawKey) {
        m_drawTick = start;
        m_drawDur = dur;
        if (key != m_drawKey) {
          m_drawKey = key;
          auditionKey(m_drawKey, m_lastVelocity);
          m_auditioned = true;
        }
        update();
      }
    } else if (m_drag == Drag::TimeSel) {
      // Full-height sweep: a time selection over the selected tracks
      // (notes and automation together), same scope as a ruler sweep.
      const uint64_t t = m_sv->snapTick(tick);
      SongView::TimeSelection sel;
      sel.startTick = std::min(m_rightAnchorTick, t);
      sel.endTick = std::max(m_rightAnchorTick, t);
      m_sv->setTimeSelection(sel);
    } else if (m_drag == Drag::Band) {
      m_bandAdditive = event->modifiers() & Qt::ControlModifier;
      auditionBandEntrants(QRectF(m_pressPos, m_curPos).normalized());
      m_sv->updateNoteViews();
    }
  }

  void leaveEvent(QEvent *) override { setHoverKey(-1); }

  void mouseReleaseEvent(QMouseEvent *event) override {
    if (event->button() == Qt::MiddleButton && m_panning) {
      m_panning = false;
      setCursor(Qt::ArrowCursor);
      return;
    }
    if (m_kbdKey >= 0) {
      auditionKey(m_kbdKey, 0);
      m_kbdKey = -1;
    }
    if (m_auditioned) {
      auditionKey(0, 0);
      m_auditioned = false;
    }
    SongDocument *doc = m_sv->document();
    if (event->button() == Qt::RightButton && m_rightPress) {
      const Drag drag = m_drag;
      m_rightPress = false;
      m_drag = Drag::None;
      if (drag == Drag::TimeSel) {
        if (m_sv->timeSelection().active())
          m_sv->announceTimeSelection();
        else
          m_sv->clearTimeSelection();
      } else if (drag == Drag::Band) {
        m_bandAdditive = event->modifiers() & Qt::ControlModifier;
        stopBandAuditions();
        selectBand(QRectF(m_pressPos, m_curPos).normalized(), m_bandAdditive);
      } else if (doc && m_rightHit) {
        const std::vector<SongView::NoteId> &sel = m_sv->selection();
        if (std::find(sel.begin(), sel.end(), m_rightHitId) == sel.end())
          m_sv->setSelection({m_rightHitId});
        showNoteMenu(event->position());
      } else if (insideTimeSelection(event->position().x())) {
        m_sv->showTimeSelectionMenu(event->globalPosition().toPoint());
      } else {
        m_sv->clearSelection();
        m_sv->clearTimeSelection();
      }
      update();
      return;
    }
    if (event->button() == Qt::LeftButton && m_leftPress) {
      m_leftPress = false;
      if (m_drag == Drag::None) {
        // Click without a drag: park the edit cursor at the click,
        // like the ruler; playback follows when running.
        m_sv->commitEditCursor(m_sv->snapTick(m_pressTick));
        update();
        return;
      }
    }
    if (event->button() == Qt::LeftButton && m_velModPress) {
      // The modifier press never grew into a velocity drag: give the
      // click its undeferred meaning — Ctrl in the chord keeps its
      // selection toggle, any other chord selects like a plain click.
      m_velModPress = false;
      const SongView::NoteId id{m_velAnchor.startTick, m_velAnchor.key};
      if (m_velModMods & Qt::ControlModifier) {
        std::vector<SongView::NoteId> ids = m_sv->selection();
        const auto it = std::find(ids.begin(), ids.end(), id);
        if (it != ids.end())
          ids.erase(it);
        else
          ids.push_back(id);
        m_sv->setSelection(std::move(ids));
      } else if (!m_sv->isSelected(m_velAnchor)) {
        m_sv->setSelection({id});
      }
      update();
      return;
    }
    if (event->button() != Qt::LeftButton || m_drag == Drag::None)
      return;

    const Drag drag = m_drag;
    m_drag = Drag::None;
    if (drag == Drag::Velocity) {
      endVelocityDrag();
      m_sv->updateNoteViews();
    }

    if (doc && drag == Drag::Draw) {
      doc->addNote(m_sv->selectedTrack(), m_drawTick, uint8_t(m_drawKey),
                   uint32_t(m_drawDur), m_lastVelocity);
      m_sv->setSelection({{uint32_t(m_drawTick), uint8_t(m_drawKey)}});
    } else if (doc && drag == Drag::Move && (m_dTick != 0 || m_dKey != 0)) {
      const std::vector<DocNote> notes = selectedDocumentNotes(*m_sv);
      doc->moveNotes(notes, m_dTick, m_dKey);
      // Follow the notes with the selection.
      std::vector<SongView::NoteId> ids;
      for (const DocNote &note : notes)
        ids.push_back(
            {uint32_t(std::max<int64_t>(0, int64_t(note.tick) + m_dTick)),
             uint8_t(std::clamp(int(note.key) + m_dKey, 0, 127))});
      m_sv->setSelection(std::move(ids));
    } else if (doc && drag == Drag::Resize && m_dDur != 0) {
      doc->resizeNotes(selectedDocumentNotes(*m_sv), m_dDur);
    } else if (doc && drag == Drag::ResizeLeft && m_dTick != 0) {
      const std::vector<DocNote> notes = selectedDocumentNotes(*m_sv);
      doc->resizeNotesLeft(notes, m_dTick);
      // Selection ids key on the start tick, which just moved; follow
      // it (same clamp as the document: the note-off pins the drag).
      std::vector<SongView::NoteId> ids;
      for (const DocNote &note : notes) {
        const int64_t maxTick = note.unterminated()
                                    ? INT64_MAX
                                    : int64_t(note.tick + note.duration) - 1;
        ids.push_back({uint32_t(std::clamp<int64_t>(
                           int64_t(note.tick) + m_dTick, 0, maxTick)),
                       note.key});
      }
      m_sv->setSelection(std::move(ids));
    } else if (doc && drag == Drag::Velocity && m_dVel != 0) {
      const std::vector<DocNote> notes = selectedDocumentNotes(*m_sv);
      std::vector<SongDocument::NoteVelocity> edits;
      edits.reserve(notes.size());
      bool needsExactVelocities = false;
      for (const DocNote &note : notes) {
        const int proposed = std::clamp(int(note.velocity) + m_dVel, 1, 127);
        const uint8_t velocity = uint8_t(m_sv->canonicalNoteVelocity(
            note.engineTrack, note.tick, note.key, proposed));
        needsExactVelocities |= velocity != proposed;
        edits.push_back({note, velocity});
      }
      if (needsExactVelocities)
        doc->setNotesVelocities(edits);
      else
        doc->nudgeNotesVelocity(notes, m_dVel);
      // Latch the dragged note's final detent for the next draw.
      m_lastVelocity = uint8_t(m_sv->canonicalNoteVelocity(
          m_velAnchor.track, m_velAnchor.startTick, m_velAnchor.key,
          int(m_velAnchor.velocity) + m_dVel));
    }
    m_dTick = 0;
    m_dKey = 0;
    m_dDur = 0;
    m_dVel = 0;
    update();
  }

  void keyPressEvent(QKeyEvent *event) override {
    if (m_sv->handleEditKey(event))
      return;
    if (event->key() == Qt::Key_Escape) {
      const Drag drag = m_drag;
      m_drag = Drag::None;
      m_leftPress = false;
      m_rightPress = false;
      stopBandAuditions();
      m_sv->clearSelection();
      m_sv->clearTimeSelection();
      if (drag == Drag::Velocity)
        endVelocityDrag();
      m_sv->updateNoteViews();
      event->accept();
      return;
    }
    QWidget::keyPressEvent(event);
  }

  void keyReleaseEvent(QKeyEvent *event) override {
    // End a transpose audition when the shortcut's keys come up. Autorepeat
    // releases are skipped so a held Ctrl+Up keeps sounding the moving pitch.
    // A stray release still must not cut a live mouse-gesture preview short.
    if (!event->isAutoRepeat()) {
      m_sv->releaseEditKeyAudition();
      if (m_auditioned && m_drag == Drag::None) {
        auditionKey(0, 0);
        m_auditioned = false;
      }
    }
    QWidget::keyReleaseEvent(event);
  }

private:
  enum class Drag {
    None,
    Band,
    TimeSel,
    Move,
    Resize,
    ResizeLeft,
    Velocity,
    Draw
  };

  // Whether pos falls inside the active time selection's band as this
  // widget draws it (the selection must cover the shown track).
  bool insideTimeSelection(qreal x) const {
    const SongView::TimeSelection &sel = m_sv->timeSelection();
    if (!sel.active() || !m_sv->timeSelectionCoversTrack(m_sv->selectedTrack()))
      return false;
    const qreal dpr = devicePixelRatioF();
    const qreal startX = m_sv->displayX(double(sel.startTick), kKeyboardW, dpr);
    const qreal endX = m_sv->displayX(double(sel.endTick), kKeyboardW, dpr);
    return x >= startX && x < endX;
  }

  // The roll has one vertical projection. Every row edge is independently
  // snapped from the continuous camera, so adjacent rows meet exactly at
  // fractional display scales without accumulated rounding error.
  const std::array<qreal, 129> &rowEdges() const {
    const qreal dpr = devicePixelRatioF();
    const qreal keyHeight = m_sv->keyHeight();
    const qreal scrollY = m_sv->scrollY();
    if (!m_rowEdgesValid || m_rowEdgesDpr != dpr ||
        m_rowEdgesKeyHeight != keyHeight || m_rowEdgesScrollY != scrollY) {
      for (int row = 0; row <= 128; ++row) {
        const qreal ideal = row * keyHeight - scrollY;
        m_rowEdges[row] = std::round(ideal * dpr) / dpr;
      }
      m_rowEdgesDpr = dpr;
      m_rowEdgesKeyHeight = keyHeight;
      m_rowEdgesScrollY = scrollY;
      m_rowEdgesValid = true;
    }
    return m_rowEdges;
  }

  qreal keyTop(int key) const { return rowEdges()[127 - key]; }
  qreal keyBottom(int key) const { return rowEdges()[128 - key]; }

  QRectF keyRect(int key, qreal x, qreal width) const {
    const qreal top = keyTop(key);
    return QRectF(x, top, width, keyBottom(key) - top);
  }

  int yToKey(qreal y) const {
    const std::array<qreal, 129> &edges = rowEdges();
    const auto edge = std::upper_bound(edges.begin(), edges.end(), y);
    const int row = std::clamp(int(edge - edges.begin()) - 1, 0, 127);
    return 127 - row;
  }

  qreal physicalPixel() const {
    return logicalPhysicalPixel(devicePixelRatioF());
  }

  // Key row under the cursor: the keyboard column mirrors it with a tint
  // and a note-name chip so the row reads at any zoom (-1 = cursor left
  // the roll). Exposed as a dynamic property for the check harness.
  void setHoverKey(int key) {
    if (key == m_hoverKey)
      return;
    m_hoverKey = key;
    setProperty("hoverKey", m_hoverKey);
    update(0, 0, kKeyboardW, height());
  }

  // All roll auditions go through here so the keyboard column can mark the
  // sounding key (velocity 0 releases and clears the mark).
  void auditionKey(int key, int velocity) {
    m_sv->audition(m_sv->selectedTrack(), key, velocity);
    const int sounding = velocity > 0 ? key : -1;
    if (sounding != m_soundingKey) {
      m_soundingKey = sounding;
      update(0, 0, kKeyboardW, height());
    }
  }

  // Begin the pencil gesture: a pending grid-cell note at the press
  // position that sounds while the button is held; the document note is
  // committed on release (one undo entry).
  void beginDraw() {
    m_drawAnchor = m_sv->snapTickDown(m_pressTick);
    m_drawTick = m_drawAnchor;
    m_drawDur = int64_t(m_sv->gridTicksAt(m_drawAnchor));
    m_drawKey = m_pressKey;
    m_drag = Drag::Draw;
    m_sv->clearSelection();
    ViewNote pending{};
    pending.startTick = uint32_t(m_drawTick);
    pending.endTick = uint32_t(m_drawTick + uint64_t(m_drawDur));
    pending.key = uint8_t(m_drawKey);
    pending.velocity = m_lastVelocity;
    pending.track = uint8_t(m_sv->selectedTrack());
    m_sv->announceNote(pending);
    // The empty-space press already sounds this row; don't re-attack it.
    if (m_soundingKey != m_drawKey)
      auditionKey(m_drawKey, m_lastVelocity);
    m_auditioned = true;
    update();
  }

  QRectF noteRect(qreal x0, qreal x1, int key) const {
    const qreal pixel = physicalPixel();
    return QRectF(x0, keyTop(key) + pixel, std::max<qreal>(2.0, x1 - x0),
                  std::max(2.0 * pixel, keyBottom(key) - keyTop(key) - pixel));
  }

  QRectF noteRect(const ViewNote &note) const {
    const qreal dpr = devicePixelRatioF();
    return noteRect(m_sv->displayX(double(note.startTick), kKeyboardW, dpr),
                    m_sv->displayX(double(note.endTick), kKeyboardW, dpr),
                    note.key);
  }

  // The painted box: flush with the note's end on the right so
  // consecutive notes abut (their black borders separate them), one
  // pixel short on the bottom so the row hairline stays visible.
  QRectF noteBox(const QRectF &rect) const {
    return rect.adjusted(0, 0, 0, -physicalPixel());
  }

  // Topmost (last-drawn) note of the selected track under pos. The rect is
  // widened a little on both sides so the edge resize handles can be
  // grabbed from just outside the note.
  const ViewNote *hitNote(QPointF pos) const {
    const int selected = m_sv->selectedTrack();
    const ViewNote *hit = nullptr;
    const qreal reach = kEdgeGripReach;
    for (const ViewNote &note : m_sv->model().notes) {
      if (note.track != selected)
        continue;
      const QRectF r = noteRect(note).adjusted(-reach, 0, reach, 0);
      if (pos.x() >= r.left() && pos.x() < r.right() && pos.y() >= r.top() &&
          pos.y() < r.bottom())
        hit = &note;
    }
    return hit;
  }

  bool nearRightEdge(const ViewNote &note, QPointF pos) const {
    const QRectF r = noteRect(note);
    return pos.x() >= r.right() - edgeGripInnerReach(r) &&
           pos.x() <= r.right() + kEdgeGripReach;
  }

  bool nearLeftEdge(const ViewNote &note, QPointF pos) const {
    const QRectF r = noteRect(note);
    return pos.x() >= r.left() - kEdgeGripReach &&
           pos.x() <= r.left() + edgeGripInnerReach(r);
  }

  bool nearVelocityHandle(const ViewNote &note, QPointF pos) const {
    if (m_sv->keyHeight() < kVelHandleMinKeyH)
      return false;
    const QRectF r = noteRect(note);
    // The bar itself is 1-2px; grab within a few pixels of it, more
    // generously on taller notes.
    const QRectF bar = velBarRect(r, note.velocity, devicePixelRatioF());
    const qreal pad =
        std::clamp(qRound(r.height() / physicalPixel()) / 6, 2, 4) *
        physicalPixel();
    const qreal inner = edgeGripInnerReach(r);
    return pos.x() > r.left() + inner && pos.x() < r.right() - inner &&
           pos.y() >= bar.top() - pad && pos.y() < bar.bottom() + pad;
  }

  void selectKeyNotes(int key) {
    std::vector<SongView::NoteId> ids;
    for (const ViewNote &note : m_sv->model().notes) {
      if (note.track == m_sv->selectedTrack() && note.key == key)
        ids.push_back({note.startTick, note.key});
    }
    m_sv->setSelection(std::move(ids));
  }

  void drawNotes(QPainter &painter, const SongViewModel &model,
                 int selectedTrack, bool drawingGhostNotes) {
    const double keyHeight = m_sv->keyHeight();
    const bool showVelocityHandles = keyHeight >= kVelHandleMinKeyH;
    // Velocity labels are optional at tight zoom levels; never force a
    // minimum face that can clip vertically.
    const auto velocityFont =
        !drawingGhostNotes && m_drag == Drag::Velocity
            ? typography::fitted(painter.font(), int(std::lround(keyHeight)))
            : std::optional<QFont>{};
    if (velocityFont)
      painter.setFont(*velocityFont);

    for (const ViewNote &note : model.notes) {
      const bool isGhostNote = note.track != selectedTrack;
      if (isGhostNote != drawingGhostNotes)
        continue;
      const QRectF noteRect = displayedNoteRect(note);
      if (noteRect.right() < kKeyboardW || noteRect.left() > width())
        continue;
      if (noteRect.bottom() < 0 || noteRect.top() > height())
        continue;

      const QRectF noteBox = this->noteBox(noteRect);
      if (isGhostNote) {
        painter.fillRect(noteBox,
                         ghostNoteColor(note.track, isBlackKey(note.key)));
        continue;
      }

      int renderedVelocity = note.velocity;
      if (const auto p = m_sv->noteVelocityPreview(note)) {
        renderedVelocity = *p;
      }
      const QColor fill =
          m_sv->noteFillColor(note.track, renderedVelocity);
      painter.fillRect(noteBox, fill);

      // Mixing one-third toward black in OKLab keeps the bar distinct
      // without rotating the identity hue. In velocity-color mode the
      // full-strength fill already is the identity.
      if (showVelocityHandles) {
        const QColor identity = m_sv->velocityColorMode()
                                    ? fill
                                    : SongView::trackColor(note.track);
        painter.fillRect(
            velBarRect(noteRect, renderedVelocity, devicePixelRatioF()),
            mixTowardOklab(identity, Qt::black, 1.0 / 3.0));
      }

      // While a velocity drag is live, every current-track note shows
      // its previewed value.
      if (m_drag == Drag::Velocity && velocityFont) {
        const QString velocityText = QString::number(renderedVelocity);
        if (noteRect.width() >=
            painter.fontMetrics().horizontalAdvance(velocityText) + 4) {
          painter.setPen(
              m_sv->velocityColorMode()
                  ? (themes::contrastRatio(fill, Qt::white) >=
                             themes::contrastRatio(fill, Qt::black)
                         ? QColor(Qt::white)
                         : QColor(Qt::black))
                  : trackTextColor(note.track));
          painter.drawText(noteRect, Qt::AlignCenter, velocityText);
        }
      }

      const bool selected = m_sv->isSelectionHighlighted(note);
      if (selected) {
        const QColor selectionColor =
            themes::color(themes::Role::item_selected_background);
        // The ring thins before it disappears; the black border
        // insets by whatever ring actually fit. Insets are physical
        // pixels too, so fractional display scale cannot change the
        // ring or inner border thickness.
        const int ringThickness =
            drawRectFrame(painter, noteBox, selectionColor,
                          songview::selectionRingPixels(devicePixelRatioF()));
        if (ringThickness > 0) {
          drawNoteBoxBorder(painter, noteBox, note.unterminated, ringThickness);
        } else {
          // At extreme zoom there is no room for a frame plus a
          // face. Keep the note visible as a solid selection mark.
          painter.fillRect(noteBox, selectionColor);
        }
      } else {
        drawNoteBoxBorder(painter, noteBox, note.unterminated);
      }
    }
  }

  // The pending note of a draw gesture, solid like the real note. (Move and
  // resize gestures need no extra pass: drawNotes paints the selected notes
  // at their dragged geometry via displayedNoteRect.)
  void drawDragPreview(QPainter &p, const SongViewModel &model, int selected) {
    Q_UNUSED(model);
    if (m_drag != Drag::Draw)
      return;
    const qreal dpr = p.device()->devicePixelRatioF();
    const qreal x0 = m_sv->displayX(double(m_drawTick), kKeyboardW, dpr);
    const qreal x1 = m_sv->displayX(double(m_drawTick + uint64_t(m_drawDur)),
                                    kKeyboardW, dpr);
    const QRectF r = noteRect(x0, x1, m_drawKey);
    const QRectF box = noteBox(r);
    p.fillRect(box, m_sv->noteFillColor(selected, m_lastVelocity));
    drawNoteBoxBorder(p, box, false);
  }

  // Where the note sits on screen right now: its stored geometry, displaced
  // by the live move/resize deltas when it's part of the gesture. Mirrors
  // the clamping applied on release in mouseReleaseEvent.
  QRectF displayedNoteRect(const ViewNote &note) const {
    const bool dragging = m_drag == Drag::Move || m_drag == Drag::Resize ||
                          m_drag == Drag::ResizeLeft;
    if (!dragging || !m_sv->isSelected(note))
      return noteRect(note);
    int64_t tick, endTick;
    if (m_drag == Drag::ResizeLeft) {
      // The note-off pins the gesture; only the start moves.
      endTick = int64_t(note.endTick);
      tick = std::clamp<int64_t>(int64_t(note.startTick) + m_dTick, 0,
                                 endTick - 1);
    } else {
      tick = std::max<int64_t>(0, int64_t(note.startTick) + m_dTick);
      endTick =
          std::max<int64_t>(tick + 1, int64_t(note.endTick) + m_dTick + m_dDur);
    }
    const int key = std::clamp(int(note.key) + m_dKey, 0, 127);
    const qreal dpr = devicePixelRatioF();
    const qreal x0 = m_sv->displayX(double(tick), kKeyboardW, dpr);
    const qreal x1 = m_sv->displayX(double(endTick), kKeyboardW, dpr);
    return noteRect(x0, x1, key);
  }

  void showNoteMenu(QPointF localPos) {
    SongDocument *doc = m_sv->document();
    if (!doc)
      return;
    const std::vector<DocNote> notes = selectedDocumentNotes(*m_sv);
    if (notes.empty())
      return;
    m_noteMenu->showMenuAt(mapToGlobal(localPos.toPoint()),
                           notes.front().velocity);
  }

  // Retargets the open note menu to the note under an outside right-click.
  // Returns false when nothing was hit (empty space, the keyboard strip,
  // another widget) so the caller can dismiss the popup instead.
  bool moveNoteMenu(QPointF globalPos) {
    const QPointF pos = globalPos - QPointF(mapToGlobal(QPoint(0, 0)));
    const ViewNote *hit =
        m_sv->document() && pos.x() >= kKeyboardW ? hitNote(pos) : nullptr;
    if (!hit)
      return false;
    if (!m_sv->isSelected(*hit))
      m_sv->setSelection({{hit->startTick, hit->key}});
    showNoteMenu(pos);
    update();
    return true;
  }

  void handleNoteMenuChoice(NoteMenuChoice choice) {
    SongDocument *doc = m_sv->document();
    if (!doc)
      return;
    switch (choice) {
    case NoteMenuChoice::Copy:
      m_sv->copyNoteSelection();
      break;
    case NoteMenuChoice::Cut:
      m_sv->cutNoteSelection();
      break;
    case NoteMenuChoice::Velocity: {
      const std::vector<DocNote> notes = selectedDocumentNotes(*m_sv);
      if (notes.empty())
        return;
      bool ok = false;
      const int velocity =
          QInputDialog::getInt(this, SongView::tr("Note velocity"),
                               SongView::tr("Velocity (1-127):"),
                               notes.front().velocity, 1, 127, 1, &ok);
      if (ok) {
        doc->setNotesVelocity(notes, uint8_t(velocity));
        m_lastVelocity = uint8_t(velocity);
      }
      break;
    }
    case NoteMenuChoice::Delete:
      m_sv->deleteNoteSelection();
      break;
    case NoteMenuChoice::None:
      break;
    }
  }

  void drawKeyboard(QPainter &p) {
    const int keyH = int(std::lround(m_sv->keyHeight()));
    p.fillRect(
        QRect(0, 0, kKeyboardW, height()),
        themes::color(themes::Role::song_view_piano_keyboard_natural_key));
    // Natural-key labels disappear when no real font face fits the lane.
    const auto labelFont = typography::fitted(p.font(), keyH);
    if (labelFont)
      p.setFont(*labelFont);
    const int hovered = m_hoverKey;
    const QPen separatorPen(
        themes::color(themes::Role::song_view_piano_keyboard_separator), 0);
    for (int key = 0; key < 128; key++) {
      const QRectF keyRect = this->keyRect(key, 0, kKeyboardW);
      if (keyRect.bottom() <= 0 || keyRect.top() >= height())
        continue;
      const bool sounding =
          key == m_soundingKey || key == m_sv->editKeyAuditionKey();
      if (isBlackKey(key)) {
        p.fillRect(keyRect,
                   sounding
                       ? themes::color(
                             themes::Role::song_view_piano_keyboard_active_key)
                       : themes::color(
                             themes::Role::song_view_piano_keyboard_black_key));
      } else {
        if (sounding) {
          p.fillRect(
              keyRect,
              themes::color(themes::Role::song_view_piano_keyboard_active_key));
        }
        // B/C and E/F are the only spots where two natural
        // keys touch, so those bottom edges get a separator.
        if (key % 12 == 0 || key % 12 == 5) {
          p.setPen(separatorPen);
          p.drawLine(QLineF(0, keyRect.bottom(), kKeyboardW, keyRect.bottom()));
        }
        if (key % 12 == 0) {
          p.setPen(themes::color(themes::Role::song_view_piano_keyboard_label));
          if (labelFont) {
            p.drawText(
                QRectF(0, keyRect.top(), kKeyboardW - 3, keyRect.height()),
                Qt::AlignRight | Qt::AlignVCenter, keyName(key));
          }
        }
      }
      if (key == hovered && !sounding) {
        QColor h = m_sv->palette().color(QPalette::Highlight);
        h.setAlpha(80);
        p.fillRect(keyRect, h);
      }
    }
    // Note-name chip on the hovered row: keys can be as short as 4px,
    // so the name gets its own fixed-size readout instead of in-row
    // text, vertically clamped so edge rows stay readable.
    if (hovered >= 0) {
      const QString name = midiKeyName(hovered);
      QFont cf = p.font();
      cf.setPixelSize(10);
      p.setFont(cf);
      const QFontMetrics fm(cf);
      const int cw = fm.horizontalAdvance(name) + 8;
      const int ch = fm.height() + 2;
      const QRectF hoveredRect = keyRect(hovered, 0, kKeyboardW);
      const qreal cy = std::clamp(hoveredRect.center().y() - ch / 2.0, 0.0,
                                  qreal(std::max(0, height() - ch)));
      const QRectF chip(kKeyboardW - 2 - cw, cy, cw, ch);
      p.save();
      p.setRenderHint(QPainter::Antialiasing);
      p.setPen(Qt::NoPen);
      p.setBrush(QColor(0x30, 0x30, 0x30, 230));
      p.drawRoundedRect(chip, 3, 3);
      p.setPen(Qt::white);
      p.drawText(chip, Qt::AlignCenter, name);
      p.restore();
    }
    p.setPen(themes::color(themes::Role::song_view_separator));
    p.drawLine(0, 0, 0, height());
  }

  // Selects the selected track's notes intersecting the band rect.
  // Ableton-style sweep audition: each note sounds the moment the rubber
  // band first covers it and stops when the band leaves it (its own
  // length is the ceiling), so sweeping across a chord hears its notes
  // together without long notes ringing on. A note swept out and back in
  // re-auditions.
  void auditionBandEntrants(const QRectF &band) {
    std::vector<SongView::NoteId> inBand;
    for (const ViewNote &note : m_sv->model().notes) {
      if (note.track != m_sv->selectedTrack() ||
          !noteRect(note).intersects(band))
        continue;
      const SongView::NoteId id{note.startTick, note.key};
      if (std::find(m_bandAud.begin(), m_bandAud.end(), id) == m_bandAud.end())
        m_sv->auditionTimed(note.track, note.key, note.velocity, note.startTick,
                            note.endTick);
      inBand.push_back(id);
    }
    for (const SongView::NoteId &old : m_bandAud) {
      if (std::find(inBand.begin(), inBand.end(), old) != inBand.end())
        continue;
      // Previews are one-per-key: keep the key sounding while the band
      // still covers another note of the same pitch.
      const bool keyCovered = std::any_of(
          inBand.begin(), inBand.end(),
          [&](const SongView::NoteId &id) { return id.key == old.key; });
      if (!keyCovered)
        m_sv->auditionTimedOff(m_sv->selectedTrack(), old.key);
    }
    m_bandAud = std::move(inBand);
    std::vector<SongView::NoteId> highlighted =
        m_bandAdditive ? m_sv->selection() : std::vector<SongView::NoteId>();
    for (const SongView::NoteId &id : m_bandAud) {
      if (std::find(highlighted.begin(), highlighted.end(), id) ==
          highlighted.end())
        highlighted.push_back(id);
    }
    m_sv->setProvisionalSelectionHighlight(std::move(highlighted));
  }

  // Release every preview the band still covers (drag ended or cancelled).
  void stopBandAuditions() {
    for (const SongView::NoteId &id : m_bandAud)
      m_sv->auditionTimedOff(m_sv->selectedTrack(), id.key);
    m_bandAud.clear();
    m_sv->clearProvisionalSelectionHighlight();
  }

  void selectBand(const QRectF &band, bool additive) {
    std::vector<SongView::NoteId> ids =
        additive ? m_sv->selection() : std::vector<SongView::NoteId>();
    for (const ViewNote &note : m_sv->model().notes) {
      if (note.track != m_sv->selectedTrack())
        continue;
      if (!noteRect(note).intersects(band))
        continue;
      const SongView::NoteId id{note.startTick, note.key};
      if (std::find(ids.begin(), ids.end(), id) == ids.end())
        ids.push_back(id);
    }
    m_sv->setSelection(std::move(ids));
  }

  SongView *m_sv;
  MidiCursors m_cursors;
  mutable std::array<qreal, 129> m_rowEdges{};
  mutable qreal m_rowEdgesDpr = 0.0;
  mutable qreal m_rowEdgesKeyHeight = 0.0;
  mutable qreal m_rowEdgesScrollY = 0.0;
  mutable bool m_rowEdgesValid = false;
  Drag m_drag = Drag::None;
  QPointF m_pressPos;
  QPointF m_curPos;
  double m_pressTick = 0.0;
  int m_pressKey = 0;
  uint64_t m_gripTick = 0;     // edge tick grabbed by a resize drag
  uint64_t m_gripOpposite = 0; // the note's other edge (the pivot)
  int64_t m_dTick = 0;
  int m_dKey = 0;
  int64_t m_dDur = 0;
  int m_dVel = 0;
  struct VelocityDragTarget {
    SongView::NoteId id;
    uint8_t originalVelocity;
  };
  int m_velocityDragTrack = -1;
  std::vector<VelocityDragTarget> m_velocityDragTargets;

public:

  void beginVelocityDrag() {
    m_velocityDragTrack = m_sv->selectedTrack();
    m_velocityDragTargets.clear();
    for (const ViewNote &note : m_sv->model().notes) {
      if (note.track == m_velocityDragTrack && m_sv->isSelected(note)) {
        m_velocityDragTargets.push_back(
            {{note.startTick, note.key}, note.velocity});
      }
    }
  }

  void endVelocityDrag() {
    m_velocityDragTrack = -1;
    m_velocityDragTargets.clear();
  }

  std::optional<uint8_t> velocityPreview(const ViewNote &note) const {
    if (m_drag != Drag::Velocity || note.track != m_velocityDragTrack)
      return std::nullopt;
    for (const auto &target : m_velocityDragTargets) {
      if (target.id.tick == note.startTick && target.id.key == note.key) {
        const int proposed =
            std::clamp(int(target.originalVelocity) + m_dVel, 1, 127);
        return uint8_t(m_sv->canonicalNoteVelocity(note.track, note.startTick,
                                                   note.key, proposed));
      }
    }
    return std::nullopt;
  }
  uint64_t m_drawTick = 0; // pending note of a draw gesture
  int64_t m_drawDur = 0;
  int m_drawKey = 0;               // follows the cursor vertically mid-draw
  uint64_t m_drawAnchor = 0;       // grid cell pressed; drags pivot around it
  bool m_leftPress = false;        // left button held on empty space; cursor
                                   // move vs. draw undecided
  bool m_rightPress = false;       // right button held; band vs. menu undecided
  bool m_rightShift = false;       // …with Shift: drag sweeps a time selection
  uint64_t m_rightAnchorTick = 0;  // snapped tick of the right press
  bool m_rightHit = false;         // that press landed on a note…
  SongView::NoteId m_rightHitId{}; // …this one
  std::vector<SongView::NoteId> m_bandAud; // notes the band currently
                                           // covers; entrants audition
  bool m_bandAdditive = false; // band preview unions the committed selection
  ViewNote m_velAnchor{};     // pressed note of a velocity drag (a copy)
  int m_velAudEff = -1;       // last effective velocity auditioned mid-drag
  bool m_velModPress = false; // velocity-modifier press on a note; click
                              // vs. vertical velocity drag undecided
  Qt::KeyboardModifiers m_velModMods = Qt::NoModifier; // that press's chord
  int m_kbdKey = -1;            // key sounding from a keyboard-column press
  int m_soundingKey = -1;       // auditioned key highlighted on the keyboard
  int m_hoverKey = -1;          // key row under the cursor; -1 = no mark
  bool m_auditioned = false;    // a drag/draw preview note is sounding
  uint8_t m_lastVelocity = 100; // latches to touched/velocity-edited notes
  bool m_panning = false;       // middle-drag pan
  QPointF m_panPos;             // last pan sample, global coords
  NoteContextMenu *m_noteMenu = nullptr;
};

// ----------------------------------------------------------- AutomationArea

class AutomationArea : public QWidget {
public:
  explicit AutomationArea(SongView *sv) : QWidget(nullptr), m_sv(sv) {
    setObjectName(QStringLiteral("automationArea")); // findChild for tests
    setMinimumHeight(kLaneH);
    setMouseTracking(true); // divider hover cursor
    // Range shortcuts (copy/cut/delete/paste on the time selection) work
    // from the lanes area too; a click focuses it, like the roll.
    setFocusPolicy(Qt::ClickFocus);
  }

  // View-state plumbing for the .porydaw sidecar: the shared row height
  // plus the individually-resized rows (keyed by AutomationRowId). laneH <= 0
  // resets to the default.
  int laneHeight() const { return m_laneH; }
  const QHash<AutomationRowId, AutomationRowDisplayState> &
  rowDisplayStates() const {
    return m_rowStates;
  }
  void setRowDisplayStates(
      const QHash<AutomationRowId, AutomationRowDisplayState> &states) {
    m_rowStates.clear();
    for (auto it = states.constBegin(); it != states.constEnd(); ++it) {
      AutomationRowDisplayState state = it.value();
      if (state.height.has_value())
        state.height = std::clamp(*state.height, kMinLaneH, kMaxLaneH);
      if (state.range.has_value())
        state.range = std::clamp(*state.range, 0, 127);
      if (state.height.has_value() || state.range.has_value())
        m_rowStates.insert(it.key(), state);
    }
    applyHeight();
    update();
  }
  void setLaneRange(int track, uint8_t cc, int value) {
    m_rowStates[AutomationRowId::controller(track, cc)].range =
        std::clamp(value, 0, 127);
    update();
  }

  // Apply the document's post-mutation old-slot-to-new-slot map to the
  // track-owned height and value-range overrides. Keys for owners mapped
  // to -1 (or outside the 16 engine slots) are discarded.
  void remapTrackRowState(const QVector<int> &newEngineSlotByOldSlot) {
    const auto newEngineSlotForOldSlot = [&newEngineSlotByOldSlot](
                                             int oldEngineSlot) {
      if (oldEngineSlot < 0 || oldEngineSlot >= newEngineSlotByOldSlot.size())
        return -1;
      const int newEngineSlot = newEngineSlotByOldSlot[oldEngineSlot];
      return newEngineSlot >= 0 && newEngineSlot < 16 ? newEngineSlot : -1;
    };
    QHash<AutomationRowId, AutomationRowDisplayState> remapped;
    for (auto it = m_rowStates.constBegin(); it != m_rowStates.constEnd();
         ++it) {
      AutomationRowId id = it.key();
      if (id.kind == AutomationRowId::Kind::Voice ||
          id.kind == AutomationRowId::Kind::Controller) {
        const int newTrack = newEngineSlotForOldSlot(id.track);
        if (newTrack < 0)
          continue;
        id.track = newTrack;
      }
      remapped.insert(id, it.value());
    }
    m_rowStates = std::move(remapped);
  }

  // A mouse gesture is live (pan, point/sweep/line edit, row resize,
  // right-press sweep); the playhead follow-scroll pauses while one runs
  // so the view doesn't jump under the cursor.
  bool gestureActive() const {
    return m_panning || m_gesture != Gesture::None || m_dragRow >= 0 ||
           m_resizeRow >= 0 || m_rightPress;
  }

  void clearHoverFeedback() {
    if (m_hoverRow < 0)
      return;
    const int previousHoverRow = m_hoverRow;
    m_hoverRow = -1;
    m_voiceInsertionPreviewVisible = false;
    if (previousHoverRow < int(m_rows.size()))
      update(QRect(0, rowTop(previousHoverRow), width(),
                   rowHeight(m_rows[previousHoverRow])));
    else
      update();
  }
  void setViewHeights(int laneH) {
    m_laneH = laneH > 0 ? std::clamp(laneH, kMinLaneH, kMaxLaneH) : kLaneH;
    applyHeight();
    update();
  }

  void rebuildRows() {
    m_rows.clear();
    m_selectedTrackVoiceChanges.clear();
    m_dragRow = -1;
    m_resizeRow = -1;
    m_gesture = Gesture::None;
    m_sweep.clear();
    m_rightPress = false;
    m_selSweep = false;
    m_hoverRow = -1;
    if (m_sv->timeline()) {
      m_rows.push_back(AutomationRowId::tempo());
      const SongViewModel &model = m_sv->model();
      const int selectedTrack = m_sv->selectedTrack();
      // The voice row shows whenever the track has changes; with a
      // document attached it is always present as the place to add one.
      bool showVoiceRow = m_sv->document() != nullptr;
      for (const VoiceChange &change : model.voices) {
        if (change.track != selectedTrack)
          continue;
        showVoiceRow = true;
        m_selectedTrackVoiceChanges.push_back(change);
      }
      if (showVoiceRow)
        m_rows.push_back(AutomationRowId::voice(selectedTrack));
      for (const AutoLane &lane : model.lanes)
        if (lane.track == selectedTrack &&
            !m_sv->laneHidden(lane.track, lane.cc))
          m_rows.push_back(AutomationRowId::controller(lane.track, lane.cc));
    }
    applyHeight();
    update();
  }

protected:
  void paintEvent(QPaintEvent *event) override {
    const QRegion &paintRegion = event->region();
    QPainter p(this);
    const qreal dpr = p.device()->devicePixelRatioF();
    p.fillRect(paintRegion.boundingRect(),
               themes::color(themes::Role::song_view_piano_roll_background));
    if (!m_sv->timeline())
      return;

    int rowY = 0;
    for (size_t i = 0; i < m_rows.size(); i++) {
      const int h = rowHeight(m_rows[i]);
      const QRect rowRect(0, rowY, width(), h);
      if (paintRegion.intersects(rowRect))
        paintRow(p, m_rows[i], rowRect);
      rowY += h;
    }

    if (m_sv->document()) {
      const QRect strip = addLaneRect();
      if (paintRegion.intersects(strip)) {
        p.setPen(
            themes::color(themes::Role::song_view_add_automation_lane_action));
        p.drawText(strip.adjusted(8, 0, -8, 0),
                   Qt::AlignLeft | Qt::AlignVCenter,
                   SongView::tr("+ Add lane"));
      }
    }

    // Drag preview: the pending stream (sweep) or ramp (line), plus a
    // marker with the value the gesture will commit at the cursor.
    if (m_dragRow >= 0 && m_dragRow < int(m_rows.size())) {
      int minV, maxV;
      rowRange(m_rows[m_dragRow], &minV, &maxV);
      const int top = rowTop(m_dragRow) + 5;
      const int bottom = rowBottom(m_dragRow) - 1 - 4;
      auto valueY = [&](int v) {
        return bottom - (v - minV) * (bottom - top) / std::max(1, maxV - minV);
      };
      auto tickX = [&](uint64_t t) {
        return m_sv->displayX(double(t), kGutterW, dpr);
      };
      p.setClipRect(QRect(kGutterW, rowTop(m_dragRow), width() - kGutterW,
                          rowHeight(m_rows[m_dragRow])));
      p.setPen(
          QPen(themes::color(themes::Role::song_view_edit_preview_outline), 1));
      p.setBrush(Qt::NoBrush);
      if (m_gesture == Gesture::Sweep && m_sweep.size() > 1) {
        // Hold-value steps, like paintCurve draws committed points.
        for (size_t i = 0; i + 1 < m_sweep.size(); i++) {
          const int y = valueY(m_sweep[i].second);
          p.drawLine(QLineF(tickX(m_sweep[i].first), y,
                            tickX(m_sweep[i + 1].first), y));
          p.drawLine(QLineF(tickX(m_sweep[i + 1].first), y,
                            tickX(m_sweep[i + 1].first),
                            valueY(m_sweep[i + 1].second)));
        }
      } else if (m_gesture == Gesture::Line) {
        p.drawLine(QLineF(tickX(m_lineStartTick), valueY(m_lineStartValue),
                          tickX(m_dragTick), valueY(m_dragValue)));
      }
      const qreal x = tickX(m_dragTick);
      const int y = valueY(m_dragValue);
      p.drawEllipse(QPointF(x, y), 3, 3);
      p.drawText(QPointF(x + 6, y - 4),
                 formatRowValue(m_rows[m_dragRow], m_dragValue));
      p.setClipping(false);
    }

    if (m_hoverRow >= 0 && m_hoverRow < int(m_rows.size()) &&
        paintRegion.intersects(QRect(0, rowTop(m_hoverRow), width(),
                                     rowHeight(m_rows[m_hoverRow]))))
      paintHoverReadout(p);
  }

  // Idle-hover readout: voice rows preview the snapped insertion tick;
  // value lanes mark the value in effect at the cursor's tick (the last
  // point at or before it, since lanes hold until the next point).
  void paintHoverReadout(QPainter &p) {
    if (m_dragRow >= 0 || m_selSweep || m_hoverRow < 0 ||
        m_hoverRow >= int(m_rows.size()))
      return;
    const AutomationRowId &row = m_rows[m_hoverRow];
    if (row.kind == AutomationRowId::Kind::Voice) {
      if (!m_sv->document() || !m_voiceInsertionPreviewVisible)
        return;

      const uint64_t insertionTick = m_voiceInsertionPreviewTick;
      const int voice = selectedTrackVoiceAtTick(insertionTick);

      const int insertionX = kGutterW + m_sv->contentX(double(insertionTick));
      const QRect plot(kGutterW, rowTop(m_hoverRow), width() - kGutterW,
                       rowHeight(row));
      const QColor previewColor =
          themes::color(themes::Role::song_view_edit_preview_outline);
      const QColor backgroundColor =
          themes::color(themes::Role::song_view_piano_roll_background);
      p.setClipRect(plot);
      const int lineTop = plot.top() + 4;
      const int lineBottom = plot.bottom() - 4;
      p.setPen(backgroundColor);
      p.drawLine(insertionX, lineTop, insertionX, lineBottom);
      p.setPen(QPen(previewColor, 1, Qt::DashLine));
      p.drawLine(insertionX, lineTop, insertionX, lineBottom);

      const QString fullLabel = QStringLiteral("→ %1 %2")
                                    .arg(voice, 3, 10, QLatin1Char('0'))
                                    .arg(m_sv->voiceShortName(uint8_t(voice)));
      constexpr int labelGap = 6;
      const int fullLabelWidth = fontMetrics().horizontalAdvance(fullLabel);
      const int rightSpace =
          std::max(0, plot.right() - insertionX - labelGap + 1);
      const int leftSpace = std::max(0, insertionX - labelGap - plot.left());
      const bool labelOnRight =
          rightSpace >= fullLabelWidth ||
          (leftSpace < fullLabelWidth && rightSpace >= leftSpace);
      const int labelSpace = labelOnRight ? rightSpace : leftSpace;
      const QString label =
          fontMetrics().elidedText(fullLabel, Qt::ElideRight, labelSpace);
      if (!label.isEmpty()) {
        const int labelWidth = fontMetrics().horizontalAdvance(label);
        const int labelX = labelOnRight ? insertionX + labelGap
                                        : insertionX - labelGap - labelWidth;
        const QRect labelRect(labelX, plot.top() + 4, labelWidth,
                              plot.height() - 8);
        p.fillRect(labelRect, backgroundColor);
        p.setPen(previewColor);
        p.drawText(labelRect, Qt::AlignLeft | Qt::AlignVCenter, label);
        p.setPen(QPen(SongView::trackColor(m_sv->selectedTrack()), 2));
        for (const VoiceChange &change : m_selectedTrackVoiceChanges) {
          const qreal markerX = m_sv->displayX(double(change.tick), kGutterW,
                                               p.device()->devicePixelRatioF());
          if (markerX >= labelRect.left() && markerX <= labelRect.right()) {
            p.drawLine(QLineF(markerX, lineTop, markerX, lineBottom));
          }
        }
      }
      p.setClipping(false);
      return;
    }
    const std::vector<LanePoint> *points = rowPoints(row);
    if (!points || points->empty())
      return;
    const auto it = std::upper_bound(
        points->begin(), points->end(), m_hoverTick,
        [](double t, const LanePoint &pt) { return t < double(pt.tick); });
    if (it == points->begin())
      return; // before the first point: no value in effect yet
    const int value = (it - 1)->value;
    int minV, maxV;
    rowRange(row, &minV, &maxV);
    const int top = rowTop(m_hoverRow) + 5;
    const int bottom = rowBottom(m_hoverRow) - 1 - 4;
    const qreal x =
        m_sv->displayX(m_hoverTick, kGutterW, p.device()->devicePixelRatioF());
    const int y =
        bottom - (value - minV) * (bottom - top) / std::max(1, maxV - minV);
    p.setClipRect(QRect(kGutterW, rowTop(m_hoverRow), width() - kGutterW,
                        rowHeight(row)));
    p.setPen(
        QPen(themes::color(themes::Role::song_view_edit_preview_outline), 1));
    p.setBrush(Qt::NoBrush);
    p.drawEllipse(QPointF(x, y), 3, 3);
    const QString text = formatRowValue(row, value);
    // Keep the label inside the row: flip left of the cursor at the right
    // edge, and keep the baseline below the row top when the curve is high.
    const int tw = fontMetrics().horizontalAdvance(text);
    const qreal tx = x + 6 + tw > width() ? x - 6 - tw : x + 6;
    const int ty =
        std::max(y - 4, rowTop(m_hoverRow) + fontMetrics().ascent() + 2);
    p.drawText(QPointF(tx, ty), text);
    p.setClipping(false);
  }

  void wheelEvent(QWheelEvent *event) override {
    // Same bindings as the roll's notes area: plain wheel over the plot
    // zooms the timeline; Ctrl+wheel resizes the lane rows (the roll's
    // key-height analog); Shift (or a trackpad's horizontal delta)
    // scrolls horizontally. Over the gutter the wheel pages the lane
    // list vertically via the scroll area.
    const QPoint delta = wheelDelta(event);
    const int d = delta.y() ? delta.y() : delta.x();
    if (event->modifiers() & Qt::ControlModifier) {
      zoomLaneHeight(d, int(event->position().y()));
    } else if (event->modifiers() & Qt::ShiftModifier) {
      m_sv->scrollByPx(-d);
    } else if (delta.x() && !delta.y()) {
      m_sv->scrollByPx(-delta.x());
    } else if (event->position().x() < kGutterW) {
      event->ignore();
      return;
    } else {
      const double zoomDelta = wheelAngleUnits(event);
      if (zoomDelta != 0.0)
        m_sv->zoomAroundContentX(std::pow(1.0015, zoomDelta),
                                 event->position().x() - kGutterW);
    }
    event->accept();
  }

  void mousePressEvent(QMouseEvent *event) override {
    // Any press starts a gesture (or a menu); the idle readout would
    // paint stale under it. The next idle move restores it.
    clearHoverFeedback();
    if (event->button() == Qt::MiddleButton) {
      // Reaper-style pan: drag scrolls the timeline and the lane list.
      // Tracked in global coords — the vertical scroll moves this
      // widget under the cursor, so local deltas would double-count.
      m_panning = true;
      m_panPos = event->globalPosition();
      setCursor(Qt::ClosedHandCursor);
      return;
    }
    const int boundary = rowBoundaryAt(event->pos().y());
    if (boundary >= 0) {
      if (event->button() == Qt::LeftButton) {
        // Dragging the divider under a row gives it an
        // individual height, overriding the shared Ctrl+wheel height.
        m_resizeRow = boundary;
        m_resizeOrigH = rowHeight(m_rows[boundary]);
        m_resizePressY = event->pos().y();
      }
      // A separator is neither row. Consume every other press so it
      // cannot fall through to a neighboring lane's context action.
      event->accept();
      return;
    }
    const int ri = rowIndexAt(event->pos().y());
    SongDocument *doc = m_sv->document();
    if (!doc)
      return;
    if ((event->button() == Qt::LeftButton ||
         event->button() == Qt::RightButton) &&
        addLaneRect().contains(event->pos())) {
      showAddLaneMenu(event->globalPosition().toPoint());
      return;
    }
    if (ri < 0)
      return;
    setFocus();
    const AutomationRowId &row = m_rows[ri];
    if (event->position().x() < kGutterW) {
      if (const AutoLane *lane = rowLane(row);
          lane && (event->button() == Qt::LeftButton ||
                   event->button() == Qt::RightButton))
        showLaneMenu(*lane, event->globalPosition().toPoint());
      return;
    }
    if (event->button() == Qt::RightButton) {
      // Deferred: a drag from here sweeps a time selection across the
      // crossed rows; releasing in place context-acts (menu inside the
      // selection, point/voice-marker delete elsewhere). Resolved in
      // mouseReleaseEvent.
      m_rightPress = true;
      m_rightPressPos = event->pos();
      m_rightRow = ri;
      m_selAnchorTick = m_sv->snapTick(rawTickAt(event->position().x()),
                                       event->modifiers() & Qt::AltModifier);
      return;
    }
    if (row.kind == AutomationRowId::Kind::Voice) {
      voiceRowPress(event);
      return;
    }
    uint8_t cc;
    int track;
    if (!rowTarget(row, &cc, &track))
      return;

    if (event->button() != Qt::LeftButton)
      return;
    m_dragRow = ri;
    const bool fine = event->modifiers() & Qt::AltModifier;
    updateDrag(event->position().x(), event->pos().y(), fine,
               event->modifiers() & Qt::ControlModifier);
    const LanePoint *grab =
        grabPoint(row, ri, event->position().x(), event->pos().y());
    if (event->modifiers() & Qt::ShiftModifier) {
      // Line ramp: the press anchors one end, release commits the
      // interpolated segment (checked before the point grab so a
      // ramp can start exactly on an existing point).
      m_gesture = Gesture::Line;
      m_lineStartTick = m_dragTick;
      m_lineStartValue = m_dragValue;
    } else if (grab) {
      // Grabbing requires hitting the point's dot (x and y), so a
      // freehand redraw over a dense curve isn't captured by every
      // cell's point — sweeping overwrites them instead.
      m_gesture = Gesture::Point;
      m_dragOrigTick = int64_t(grab->tick);
      // Start from the point's exact position, not the pixel-derived
      // one: a no-motion click (or the first half of a double-click)
      // must not quantize the value to the pixel grid.
      m_dragTick = grab->tick;
      m_dragValue = grab->value;
    } else {
      // Freehand sweep; a no-motion click degenerates to a single
      // point (overwriting any point already on that tick).
      m_gesture = Gesture::Sweep;
      m_dragOrigTick = -1;
      m_sweep.assign(1, {m_dragTick, m_dragValue});
      m_prevTick = rawTickAt(event->position().x());
      m_prevValue = m_dragValue;
    }
    update();
  }

  void mouseMoveEvent(QMouseEvent *event) override {
    if (m_panning) {
      const QPointF d = event->globalPosition() - m_panPos;
      m_panPos = event->globalPosition();
      m_sv->scrollByPx(-d.x());
      if (auto *scroll = scrollArea()) {
        auto *vbar = scroll->verticalScrollBar();
        vbar->setValue(vbar->value() - int(d.y()));
      }
      return;
    }
    if (m_resizeRow >= 0 && m_resizeRow < int(m_rows.size())) {
      const int newH =
          std::clamp(m_resizeOrigH + event->pos().y() - m_resizePressY,
                     kMinLaneH, kMaxLaneH);
      if (newH != rowHeight(m_rows[m_resizeRow])) {
        m_rowStates[m_rows[m_resizeRow]].height = newH;
        applyHeight();
        update();
      }
      return;
    }
    if (m_rightPress) {
      if (!m_selSweep && (event->pos() - m_rightPressPos).manhattanLength() >=
                             QApplication::startDragDistance())
        m_selSweep = true;
      if (m_selSweep)
        updateSelSweep(event);
      return;
    }
    if (m_dragRow < 0) {
      const int boundary = rowBoundaryAt(event->pos().y());
      const bool overRowBoundary = boundary >= 0;
      setCursor(overRowBoundary ? Qt::SplitVCursor : Qt::ArrowCursor);
      updateHover(event->position(), overRowBoundary);
      return;
    }
    const bool fine = event->modifiers() & Qt::AltModifier;
    updateDrag(event->position().x(), event->pos().y(), fine,
               event->modifiers() & Qt::ControlModifier);
    if (m_gesture == Gesture::Sweep)
      extendSweep(event->position().x(), fine);
    update();
  }

  void mouseReleaseEvent(QMouseEvent *event) override {
    if (event->button() == Qt::MiddleButton && m_panning) {
      m_panning = false;
      setCursor(Qt::ArrowCursor);
      return;
    }
    if (event->button() == Qt::RightButton && m_rightPress) {
      m_rightPress = false;
      if (m_selSweep) {
        m_selSweep = false;
        if (m_sv->timeSelection().active())
          m_sv->announceTimeSelection();
        else
          m_sv->clearTimeSelection();
      } else {
        rightClickInPlace(event);
      }
      return;
    }
    if (event->button() == Qt::LeftButton && m_resizeRow >= 0) {
      m_resizeRow = -1;
      return;
    }
    if (event->button() != Qt::LeftButton || m_dragRow < 0 ||
        m_dragRow >= int(m_rows.size()))
      return;
    const AutomationRowId &row = m_rows[m_dragRow];
    const Gesture gesture = m_gesture;
    m_gesture = Gesture::None;
    m_dragRow = -1;
    update();

    SongDocument *doc = m_sv->document();
    uint8_t cc;
    int track;
    if (!doc || !rowTarget(row, &cc, &track))
      return;
    if (gesture == Gesture::Point) {
      if (m_dragOrigTick < 0)
        return;
      DocLanePoint pt;
      // Skip the no-op commit: a plain click on a point (including the
      // first half of a double-click) must not touch the document.
      if (doc->findLanePoint(track, cc, uint64_t(m_dragOrigTick), &pt) &&
          (pt.tick != m_dragTick || pt.value != m_dragValue))
        doc->moveLanePoint(track, cc, pt, m_dragTick, m_dragValue);
    } else if (gesture == Gesture::Sweep) {
      // writeLanePoints even for a plain click: it overwrites any
      // point already sitting on the tick instead of duplicating it.
      if (!m_sweep.empty())
        doc->writeLanePoints(track, cc, m_sweep.front().first,
                             m_sweep.back().first, sweepPoints());
      m_sweep.clear();
    } else if (gesture == Gesture::Line) {
      const bool fine = event->modifiers() & Qt::AltModifier;
      uint64_t a = m_lineStartTick, b = m_dragTick;
      int va = m_lineStartValue, vb = m_dragValue;
      if (a > b) {
        std::swap(a, b);
        std::swap(va, vb);
      }
      if (a == b) {
        doc->writeLanePoints(track, cc, a, a, {{a, vb}});
        return;
      }
      const uint64_t g = std::max<uint64_t>(1, fine ? m_sv->fineGridTicks()
                                                    : m_sv->gridTicksAt(a));
      std::vector<SongDocument::LanePointValue> pts;
      for (uint64_t t = a; t < b; t += g)
        pts.push_back(
            {t, va + int(std::llround(double(vb - va) * double(t - a) /
                                      double(b - a)))});
      pts.push_back({b, vb});
      doc->writeLanePoints(track, cc, a, b, pts);
    }
  }

  // Double-click: type-in for the exact value the pixel grid can't hit
  // (e.g. pan dead-center). The first click of the pair already ran as a
  // normal click, so on empty space a point exists at the snapped tick by
  // now — either way this edits the point on that tick via an overwriting
  // single-point write.
  void mouseDoubleClickEvent(QMouseEvent *event) override {
    SongDocument *doc = m_sv->document();
    if (!doc || event->button() != Qt::LeftButton ||
        event->position().x() < kGutterW)
      return;
    const int ri = rowIndexAt(event->pos().y());
    if (ri < 0)
      return;
    const AutomationRowId &row = m_rows[ri];
    uint8_t cc;
    int track;
    if (!rowTarget(row, &cc, &track))
      return;
    // The double-click replaced this pair's second press; drop any
    // half-open gesture so its release is a no-op.
    m_gesture = Gesture::None;
    m_dragRow = -1;
    m_sweep.clear();
    update();

    uint64_t tick;
    int value;
    if (const LanePoint *nearPt = nearestPoint(row, event->position().x())) {
      tick = nearPt->tick;
      value = nearPt->value;
    } else {
      // The click's point can sit farther than nearestPoint's radius
      // when the snap grid is coarse; re-derive its tick the same way.
      tick = m_sv->snapTick(rawTickAt(event->position().x()),
                            event->modifiers() & Qt::AltModifier);
      DocLanePoint pt;
      value = doc->findLanePoint(track, cc, tick, &pt)
                  ? pt.value
                  : valueAtY(row, ri, event->pos().y());
    }
    if (!editValue(row, &value))
      return;
    doc->writeLanePoints(track, cc, tick, tick, {{tick, value}});
  }

  void keyPressEvent(QKeyEvent *event) override {
    if (m_sv->handleEditKey(event))
      return;
    if (event->key() == Qt::Key_Escape) {
      m_rightPress = false;
      m_selSweep = false;
      m_sv->clearTimeSelection();
      event->accept();
      return;
    }
    QWidget::keyPressEvent(event);
  }

  void keyReleaseEvent(QKeyEvent *event) override {
    if (!event->isAutoRepeat())
      m_sv->releaseEditKeyAudition();
    QWidget::keyReleaseEvent(event);
  }

  void leaveEvent(QEvent *) override { clearHoverFeedback(); }

private:
  // Lane rows carry their identity BY VALUE, never a pointer into
  // model.lanes: rows outlive a model rebuild (setSong resets view
  // heights before rebuildRows repopulates them), so a cached pointer
  // dangles the moment the model is reassigned. Anything needing the
  // live lane (points, name) resolves it through rowLane().
  const AutoLane *rowLane(const AutomationRowId &row) const {
    if (row.kind != AutomationRowId::Kind::Controller)
      return nullptr;
    for (const AutoLane &lane : m_sv->model().lanes) {
      if (lane.track == row.track && lane.cc == row.cc)
        return &lane;
    }
    return nullptr; // stale row: its lane left the model
  }

  // The lane identity a row contributes to a lane-scoped time selection:
  // (engine track, cc), with the global tempo row as track -1 so it
  // survives track switches.
  std::pair<int, uint8_t> rowIdentity(const AutomationRowId &row) const {
    switch (row.kind) {
    case AutomationRowId::Kind::Tempo:
      return {-1, DOC_CC_TEMPO};
    case AutomationRowId::Kind::Voice:
      return {row.track, DOC_CC_VOICE};
    case AutomationRowId::Kind::Controller:
      return {row.track, row.cc};
    }
    return {-1, 0};
  }

  // Live update of a right-drag selection sweep: the tick span between the
  // press anchor and the cursor, across every row the drag crosses.
  void updateSelSweep(QMouseEvent *event) {
    if (m_rightRow < 0 || m_rightRow >= int(m_rows.size()))
      return;
    const bool fine = event->modifiers() & Qt::AltModifier;
    const uint64_t tick =
        m_sv->snapTick(rawTickAt(event->position().x()), fine);
    SongView::TimeSelection sel;
    sel.startTick = std::min(m_selAnchorTick, tick);
    sel.endTick = std::max(m_selAnchorTick, tick);
    sel.scope = SongView::TimeSelection::Lanes;
    int r0 = m_rightRow;
    int r1 = rowIndexAt(
        std::clamp(event->pos().y(), 0, rowTop(int(m_rows.size())) - 1));
    if (r1 < 0)
      r1 = r0;
    if (r0 > r1)
      std::swap(r0, r1);
    for (int ri = r0; ri <= r1 && ri < int(m_rows.size()); ri++)
      sel.lanes.push_back(rowIdentity(m_rows[ri]));
    m_sv->setTimeSelection(sel);
  }

  // Right release without a drag: menu inside the time selection, voice-
  // marker or point delete elsewhere, and clearing the selection over
  // empty space (mirroring the roll).
  void rightClickInPlace(QMouseEvent *event) {
    SongDocument *doc = m_sv->document();
    if (!doc || m_rightRow < 0 || m_rightRow >= int(m_rows.size()))
      return;
    const AutomationRowId &row = m_rows[m_rightRow];
    const std::pair<int, uint8_t> id = rowIdentity(row);
    const SongView::TimeSelection &sel = m_sv->timeSelection();
    const qreal x = event->position().x();
    const qreal dpr = devicePixelRatioF();
    const qreal startX = m_sv->displayX(double(sel.startTick), kGutterW, dpr);
    const qreal endX = m_sv->displayX(double(sel.endTick), kGutterW, dpr);
    if (sel.active() && m_sv->timeSelectionCoversRow(id.first, id.second) &&
        x >= startX && x < endX) {
      m_sv->showTimeSelectionMenu(event->globalPosition().toPoint());
      return;
    }
    if (row.kind == AutomationRowId::Kind::Voice) {
      if (const VoiceChange *change = voiceChangeNear(event->position().x())) {
        DocLanePoint point;
        if (doc->findLanePoint(m_sv->selectedTrack(), DOC_CC_VOICE,
                               change->tick, &point))
          doc->deleteLanePoints(m_sv->selectedTrack(), DOC_CC_VOICE, {point});
      }
      return;
    }
    uint8_t cc;
    int track;
    if (!rowTarget(row, &cc, &track))
      return;
    if (const LanePoint *nearPt = nearestPoint(row, event->position().x())) {
      DocLanePoint pt;
      if (doc->findLanePoint(track, cc, nearPt->tick, &pt))
        doc->deleteLanePoints(track, cc, {pt});
      return;
    }
    m_sv->clearTimeSelection();
  }

  // Voice change within the marker hit radius of x, if any.
  const VoiceChange *voiceChangeNear(qreal x) const {
    const double cursorTick = rawTickAt(x);
    const double hitRadiusTicks =
        double(kVoiceMarkerHitRadius) / m_sv->pxPerTick();
    const double firstTick = std::max(0.0, cursorTick - hitRadiusTicks);
    auto change = std::lower_bound(
        m_selectedTrackVoiceChanges.begin(), m_selectedTrackVoiceChanges.end(),
        firstTick, [](const VoiceChange &candidate, double tick) {
          return double(candidate.tick) < tick;
        });

    const VoiceChange *nearestChange = nullptr;
    qreal nearestDistance = kVoiceMarkerHitRadius;
    const double lastTick = cursorTick + hitRadiusTicks;
    const qreal dpr = devicePixelRatioF();
    for (; change != m_selectedTrackVoiceChanges.end() &&
           double(change->tick) <= lastTick;
         ++change) {
      const qreal distance =
          std::abs(m_sv->displayX(double(change->tick), kGutterW, dpr) - x);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestChange = &*change;
      }
    }
    return nearestChange;
  }

  int selectedTrackVoiceAtTick(uint64_t tick) const {
    return std::max(0, m_sv->programAt(m_sv->selectedTrack(), tick));
  }

  // Per-row geometry: individually-resized rows (divider drag) override
  // the shared m_laneH. Identities survive track switches, so each lane keeps
  // its height when the user comes back to the track.
  int rowHeight(const AutomationRowId &row) const {
    const auto it = m_rowStates.constFind(row);
    if (it == m_rowStates.constEnd() || !it.value().height.has_value())
      return m_laneH;
    return *it.value().height;
  }

  // Top of row `index`; index == m_rows.size() gives the total height.
  int rowTop(int index) const {
    int y = 0;
    for (int i = 0; i < index && i < int(m_rows.size()); i++)
      y += rowHeight(m_rows[i]);
    return y;
  }

  int rowBottom(int index) const {
    return rowTop(index) + rowHeight(m_rows[index]);
  }

  int rowIndexAt(int y) const {
    if (y < 0)
      return -1;
    int bottom = 0;
    for (size_t i = 0; i < m_rows.size(); i++) {
      bottom += rowHeight(m_rows[i]);
      if (y < bottom)
        return int(i);
    }
    return -1;
  }

  // Divider hit test: every bottom edge is an inert separator for context
  // actions and a resize handle for left-button drags.
  int rowBoundaryAt(int y) const {
    int bottom = 0;
    for (size_t i = 0; i < m_rows.size(); i++) {
      bottom += rowHeight(m_rows[i]);
      if (std::abs(y - bottom) <= 3)
        return int(i);
    }
    return -1;
  }

  QRect addLaneRect() const {
    return QRect(0, rowTop(int(m_rows.size())), width(), kAddLaneH);
  }

  void applyHeight() {
    // Minimum, not fixed: the scroll area stretches the widget to fill
    // its viewport when the user drags the lanes area taller.
    const int addH = m_sv->timeline() && m_sv->document() ? kAddLaneH : 0;
    setMinimumHeight(std::max(m_laneH, rowTop(int(m_rows.size())) + addH));
  }

  // Ctrl+wheel: rescale the lane rows (the roll's key-height analog),
  // keeping the row under the cursor pinned. anchorY is widget-local, so
  // it already includes the scroll offset. Individually-resized rows
  // scale by the same factor, keeping their proportions.
  void zoomLaneHeight(int wheelDelta, int anchorY) {
    m_laneZoomAccum += wheelDelta;
    const int steps = m_laneZoomAccum / 120;
    if (steps == 0)
      return;
    m_laneZoomAccum -= steps * 120;
    const int newH = std::clamp(m_laneH + steps * 4, kMinLaneH, kMaxLaneH);
    if (newH == m_laneH)
      return;
    const double factor = double(newH) / double(m_laneH);
    for (auto it = m_rowStates.begin(); it != m_rowStates.end(); ++it) {
      auto &height = it.value().height;
      if (height.has_value())
        height = std::clamp(int(std::lround(*height * factor)), kMinLaneH,
                            kMaxLaneH);
    }
    m_laneH = newH;
    applyHeight();
    if (auto *scroll = scrollArea()) {
      auto *vbar = scroll->verticalScrollBar();
      const int viewportY = anchorY - vbar->value();
      vbar->setValue(int(std::lround(anchorY * factor)) - viewportY);
    }
    update();
  }

  // Menu of §4.2 audible parameters without a lane on the selected track.
  void showAddLaneMenu(const QPoint &globalPos) {
    struct LaneMenuChoice {
      QAction *action;
      uint8_t cc;
      bool showsHiddenLane;
      QString laneName;
    };

    const int track = m_sv->selectedTrack();
    const SongViewModel &model = m_sv->model();
    QMenu menu;
    std::vector<LaneMenuChoice> laneMenuChoices;
    bool addLaneAvailable = false;
    static constexpr uint8_t kAudibleCcs[] = {0x01, 0x07, 0x0A,
                                              0x14, 0x15, LANE_CC_BEND};
    for (uint8_t cc : kAudibleCcs) {
      if (model.findLane(track, cc) || m_sv->laneHidden(track, cc))
        continue;
      QString label;
      if (cc == LANE_CC_BEND) {
        label = SongView::tr("Pitch bend (BEND)");
      } else {
        const M4aCcInfo info = m4aClassifyCc(cc);
        label = QStringLiteral("%1 (%2)").arg(QLatin1String(info.display),
                                              QLatin1String(info.name));
      }
      QAction *action = menu.addAction(label);
      laneMenuChoices.push_back({action, cc, false, {}});
      addLaneAvailable = true;
    }
    if (!addLaneAvailable)
      menu.addAction(SongView::tr("All parameters already have lanes"))
          ->setEnabled(false);

    bool hiddenLaneAvailable = false;
    for (const std::pair<int, uint8_t> &hiddenLane : m_sv->hiddenLanes()) {
      if (hiddenLane.first != track)
        continue;
      const uint8_t cc = hiddenLane.second;
      const AutoLane *lane = model.findLane(track, cc);
      QString laneName;
      if (lane)
        laneName = lane->name;
      else if (cc == LANE_CC_BEND)
        laneName = SongView::tr("Pitch bend");
      else {
        const M4aCcInfo info = m4aClassifyCc(cc);
        laneName = info.eventClass == M4aEventClass::AudibleLane
                       ? QLatin1String(info.display)
                       : SongView::tr("CC %1").arg(cc);
      }
      if (!hiddenLaneAvailable) {
        menu.addSeparator();
        hiddenLaneAvailable = true;
      }
      QAction *action =
          menu.addAction(SongView::tr("Show: %1 (hidden)").arg(laneName));
      laneMenuChoices.push_back({action, cc, true, laneName});
    }

    QAction *selectedAction = menu.exec(globalPos);
    if (!selectedAction)
      return;
    for (const LaneMenuChoice &choice : laneMenuChoices) {
      if (selectedAction != choice.action)
        continue;
      if (choice.showsHiddenLane) {
        m_sv->showLane(track, choice.cc);
        m_sv->announce(SongView::tr("Showed the %1 lane").arg(choice.laneName));
      } else {
        m_sv->addEmptyLane(track, choice.cc);
      }
      return;
    }
  }

  // Gutter menu on a CC/bend lane: clear its events (the lane stays,
  // empty), or delete the lane outright — confirmed first while it still
  // has events, since that throws the whole curve away in one step.
  void showLaneMenu(const AutoLane &lane, const QPoint &globalPos) {
    // Copies: the menu's actions mutate the model, and lane points into it.
    const int track = lane.track;
    const uint8_t cc = lane.cc;
    const QString name = lane.name;
    const bool empty = lane.points.empty();

    QMenu menu;
    QAction *copyLane = menu.addAction(SongView::tr("Copy lane"));
    copyLane->setEnabled(!empty);
    QAction *pasteLane = menu.addAction(SongView::tr("Paste lane (replace)"));
    // Only whole-lane clips (their ticks are absolute) paste here; range
    // clips are anchored at the edit cursor instead.
    {
      const SongView::Clip &clip = m_sv->clipboard();
      pasteLane->setEnabled(clip.wholeLane && clip.lanes.size() == 1 &&
                            !clip.lanes.front().points.empty());
    }
    menu.addSeparator();
    QAction *hideLaneAction = menu.addAction(SongView::tr("Hide lane"));
    QAction *clear = menu.addAction(SongView::tr("Clear events"));
    clear->setEnabled(!empty);
    QAction *del = menu.addAction(empty ? SongView::tr("Remove empty lane")
                                        : SongView::tr("Delete lane"));
    // Value-axis zoom: display range only, the events keep their values.
    std::vector<std::pair<QAction *, int>> rangeActions;
    if (laneRangeZoomable(cc)) {
      QMenu *range = menu.addMenu(SongView::tr("Value range"));
      const AutomationRowDisplayState rowState =
          m_rowStates.value(AutomationRowId::controller(track, cc));
      const int current = rowState.range.value_or(laneRangeDefault(cc));
      const std::pair<int, QString> options[] = {
          {0, SongView::tr("Auto (fit to data)")},
          {16, QStringLiteral("0–16")},
          {32, QStringLiteral("0–32")},
          {64, QStringLiteral("0–64")},
          {127, SongView::tr("0–127 (full)")},
      };
      for (const auto &opt : options) {
        QAction *action = range->addAction(opt.second);
        action->setCheckable(true);
        action->setChecked(opt.first == current);
        rangeActions.emplace_back(action, opt.first);
      }
    }
    QAction *chosen = menu.exec(globalPos);
    if (!chosen)
      return;
    for (const std::pair<QAction *, int> &opt : rangeActions) {
      if (chosen == opt.first) {
        setLaneRange(track, cc, opt.second);
        return;
      }
    }
    if (chosen == hideLaneAction) {
      m_sv->hideLane(track, cc);
      m_sv->announce(SongView::tr("Hid the %1 lane").arg(name));
      return;
    }

    SongDocument *doc = m_sv->document();
    const std::vector<DocLanePoint> points = doc->lanePoints(track, cc);
    if (chosen == copyLane) {
      if (points.empty())
        return;
      SongView::Clip clip;
      clip.wholeLane = true;
      clip.span = points.back().tick + 1;
      SongView::ClipLane cl{track, cc, {}};
      for (const DocLanePoint &pt : points)
        cl.points.push_back({uint32_t(pt.tick), pt.value});
      clip.lanes.push_back(std::move(cl));
      m_sv->clipboard() = std::move(clip);
      m_sv->announce(SongView::tr("Copied the %1 lane (%n point(s))", nullptr,
                                  int(points.size()))
                         .arg(name));
      return;
    }
    if (chosen == pasteLane) {
      // Replace this lane's whole contents with the clipboard lane at
      // its original ticks (values clamp to this lane's range), as one
      // undoable command.
      SongDocument::RangeEdit edit;
      edit.removePoints = points;
      SongDocument::RangeEdit::LaneWrite lw{track, cc, {}};
      for (const std::pair<uint32_t, int> &pv :
           m_sv->clipboard().lanes.front().points)
        lw.points.push_back({uint64_t(pv.first), pv.second});
      edit.addPoints.push_back(std::move(lw));
      doc->applyRangeEdit(SongView::tr("paste lane"), edit);
      m_sv->announce(SongView::tr("Replaced the %1 lane").arg(name));
      return;
    }
    if (chosen == clear) {
      if (points.empty())
        return;
      // Keep the row alive as an empty lane once its events go.
      m_sv->addEmptyLane(track, cc);
      doc->deleteLanePoints(track, cc, points);
    } else if (chosen == del) {
      if (!points.empty() &&
          QMessageBox::question(
              this, SongView::tr("Delete lane"),
              SongView::tr("Delete the %1 lane and its %2 events?")
                  .arg(name)
                  .arg(points.size())) != QMessageBox::Yes)
        return;
      m_sv->removeEmptyLane(track, cc); // forget the view state first
      if (!points.empty())
        doc->deleteLanePoints(track, cc, points);
    }
  }

  // Voice row, left button only (right-button gestures are handled by the
  // shared deferral): click a marker to re-pick its voice, click empty
  // space to insert a change at the snapped tick; release-in-place
  // right-clicks delete a marker via rightClickInPlace. The value axis is
  // meaningless here (a voice is an identity, not a level), so the picker
  // dialog replaces the lanes' drag editing.
  void voiceRowPress(QMouseEvent *event) {
    SongDocument *doc = m_sv->document();
    const int track = m_sv->selectedTrack();
    if (!doc || event->button() != Qt::LeftButton)
      return;
    const uint64_t tick = m_sv->snapTick(m_sv->tickAtContentX(
        std::max(qreal(kGutterW), event->position().x()) - kGutterW));
    const qreal insertionX =
        m_sv->displayX(double(tick), kGutterW, devicePixelRatioF());
    const VoiceChange *change = voiceChangeNear(event->position().x());
    if (!change)
      change = voiceChangeNear(insertionX);
    if (change) {
      DocLanePoint hit;
      if (!doc->findLanePoint(track, DOC_CC_VOICE, change->tick, &hit))
        return;
      int voice = hit.value;
      if (m_sv->pickVoice(SongView::tr("Change voice"), hit.value, &voice) &&
          voice != hit.value)
        doc->moveLanePoint(track, DOC_CC_VOICE, hit, hit.tick, voice);
    } else {
      int voice = selectedTrackVoiceAtTick(tick);
      if (m_sv->pickVoice(SongView::tr("Insert voice change"), voice, &voice))
        doc->addLanePoint(track, DOC_CC_VOICE, tick, voice);
    }
  }

  // Document target of an editable row; false for the voice row.
  bool rowTarget(const AutomationRowId &row, uint8_t *cc, int *track) const {
    if (row.kind == AutomationRowId::Kind::Tempo) {
      *cc = DOC_CC_TEMPO;
      *track = m_sv->selectedTrack();
      return true;
    }
    if (row.kind == AutomationRowId::Kind::Controller) {
      *cc = row.cc; // LANE_CC_BEND == DOC_CC_BEND
      *track = row.track;
      return true;
    }
    return false;
  }

  const std::vector<LanePoint> *rowPoints(const AutomationRowId &row) const {
    if (row.kind == AutomationRowId::Kind::Tempo)
      return &m_sv->model().tempoLane;
    if (const AutoLane *lane = rowLane(row))
      return &lane->points;
    return nullptr;
  }

  // Lanes whose value axis can zoom: 0-based CC lanes. Centered lanes
  // (PAN/TUNE swing around 64) and bend keep their fixed scales.
  static bool laneRangeZoomable(uint8_t cc) {
    return cc != LANE_CC_BEND && cc != 0x0A && cc != 0x18;
  }

  // Default axis mode per CC (0 = auto-fit): MOD is only musical in the
  // bottom stretch of 0..127 (vibrato past ~20 is cartoony), so it fits
  // to the data by default; everything else keeps the full axis.
  static int laneRangeDefault(uint8_t cc) { return cc == 0x01 ? 0 : 127; }

  // Auto-fit rung: the smallest of 16/32/64/127 that holds the lane's
  // data. Coarse rungs keep the scale from twitching while points are
  // edited. 16 is the floor because typical MOD curves live in 0..15.
  static int laneAutoMax(int dataMax) {
    if (dataMax <= 16)
      return 16;
    if (dataMax <= 32)
      return 32;
    if (dataMax <= 64)
      return 64;
    return 127;
  }

  void rowRange(const AutomationRowId &row, int *minV, int *maxV) const {
    *minV = 0;
    *maxV = 127;
    if (row.kind == AutomationRowId::Kind::Tempo) {
      *maxV = 200;
      for (const LanePoint &pt : m_sv->model().tempoLane)
        *maxV = std::max(*maxV, pt.value + 20);
    } else if (row.kind == AutomationRowId::Kind::Controller &&
               row.cc == LANE_CC_BEND) {
      *minV = -8192;
      *maxV = 8191;
    } else if (row.kind == AutomationRowId::Kind::Controller &&
               laneRangeZoomable(row.cc)) {
      // Zoomed value axis: the display max shrinks so a small useful
      // range (MOD's 0..20, say) gets the row's pixels. Data outside
      // the chosen range always grows the axis back — points never
      // draw off-scale, and the gutter label shows the live range.
      int dataMax = 0;
      if (const AutoLane *lane = rowLane(row)) {
        for (const LanePoint &pt : lane->points)
          dataMax = std::max(dataMax, pt.value);
      }
      const auto rowState = m_rowStates.value(row);
      const int mode = rowState.range.value_or(laneRangeDefault(row.cc));
      *maxV = mode > 0 ? std::max(mode, dataMax) : laneAutoMax(dataMax);
    }
  }

  QString rowTitle(const AutomationRowId &row) const {
    switch (row.kind) {
    case AutomationRowId::Kind::Tempo:
      return SongView::tr("Tempo (BPM)");
    case AutomationRowId::Kind::Voice:
      return SongView::tr("Voice");
    case AutomationRowId::Kind::Controller: {
      if (row.cc == LANE_CC_BEND)
        return SongView::tr("Pitch bend (BEND)");
      const M4aCcInfo info = m4aClassifyCc(row.cc);
      const AutoLane *lane = rowLane(row);
      return QStringLiteral("%1 (%2)").arg(lane ? lane->name
                                                : QLatin1String(info.name),
                                           QLatin1String(info.name));
    }
    }
    return QString();
  }

  // The m4a display convention used elsewhere in the app (PAN/TUNE as
  // c_v±, bend signed): a raw "64" for pan hides that it IS center.
  QString formatRowValue(const AutomationRowId &row, int v) const {
    if (row.kind == AutomationRowId::Kind::Controller) {
      if (row.cc == LANE_CC_BEND)
        return m4aFormatBend(v);
      return m4aFormatCcValue(row.cc, uint8_t(v));
    }
    return QString::number(v);
  }

  // Neutral value a Ctrl-drag magnetizes to; only lanes where "centered"
  // is meaningful and hard to hit by eye.
  bool rowDetent(const AutomationRowId &row, int *value) const {
    if (row.kind != AutomationRowId::Kind::Controller)
      return false;
    if (row.cc == 0x0A || row.cc == 0x18) { // PAN/TUNE: c_v 0
      *value = 64;
      return true;
    }
    if (row.cc == LANE_CC_BEND) {
      *value = 0;
      return true;
    }
    return false;
  }

  // Type-in editor: the only way to hit an arbitrary exact value, since a
  // pixel spans several value units at normal lane heights. Input uses the
  // display convention; PAN/TUNE entry is c_v (stored value minus 64).
  bool editValue(const AutomationRowId &row, int *value) {
    int minShown = 0, maxShown = 127, offset = 0; // stored = shown + offset
    QString label = SongView::tr("Value:");
    if (row.kind == AutomationRowId::Kind::Tempo) {
      minShown = 1;
      maxShown = 999;
      label = SongView::tr("BPM:");
    } else if (row.cc == LANE_CC_BEND) {
      minShown = -8192;
      maxShown = 8191;
      label = SongView::tr("Bend (0 = none):");
    } else if (row.cc == 0x0A || row.cc == 0x18) {
      minShown = -64;
      maxShown = 63;
      offset = 64;
      label = SongView::tr("c_v value (0 = center):");
    }
    bool ok = false;
    const int shown =
        QInputDialog::getInt(this, rowTitle(row), label, *value - offset,
                             minShown, maxShown, 1, &ok);
    if (ok)
      *value = shown + offset;
    return ok;
  }

  const LanePoint *nearestPoint(const AutomationRowId &row, qreal x) const {
    const std::vector<LanePoint> *points = rowPoints(row);
    if (!points)
      return nullptr;
    const LanePoint *best = nullptr;
    qreal bestDist = 9.0;
    const qreal dpr = devicePixelRatioF();
    for (const LanePoint &pt : *points) {
      const qreal dist =
          std::abs(m_sv->displayX(double(pt.tick), kGutterW, dpr) - x);
      if (dist < bestDist) {
        bestDist = dist;
        best = &pt;
      }
    }
    return best;
  }

  // Left-press grab test: near the point's dot in BOTH x and y. A dense
  // freehand curve has a point on every grid cell, so an x-only radius
  // (nearestPoint, kept for right-click delete) would capture every press
  // and make redrawing impossible; grab the dot itself to move a point.
  const LanePoint *grabPoint(const AutomationRowId &row, int ri, qreal x,
                             int y) const {
    const std::vector<LanePoint> *points = rowPoints(row);
    if (!points)
      return nullptr;
    int minV, maxV;
    rowRange(row, &minV, &maxV);
    // paintCurve's valueY mapping for this row.
    const int top = rowTop(ri) + 5;
    const int bottom = rowBottom(ri) - 1 - 4;
    const LanePoint *best = nullptr;
    qreal bestDist = qreal(INT_MAX);
    const qreal dpr = devicePixelRatioF();
    for (const LanePoint &pt : *points) {
      const qreal dx = m_sv->displayX(double(pt.tick), kGutterW, dpr) - x;
      const int dy =
          bottom -
          (pt.value - minV) * (bottom - top) / std::max(1, maxV - minV) - y;
      if (std::abs(dx) > 7 || std::abs(dy) > 7)
        continue;
      const qreal dist = dx * dx + qreal(dy * dy);
      if (dist < bestDist) {
        bestDist = dist;
        best = &pt;
      }
    }
    return best;
  }

  double rawTickAt(qreal x) const {
    return std::max(
        0.0, m_sv->tickAtContentX(std::max(qreal(kGutterW), x) - kGutterW));
  }

  // Idle cursor position for hover feedback: raw (unsnapped) tick for
  // value readouts and as the input to the voice row's snapped preview.
  // The gutter, row resize handles, and rows without either affordance
  // clear it.
  void updateHover(QPointF pos, bool overRowBoundary) {
    if (overRowBoundary) {
      clearHoverFeedback();
      return;
    }
    const int rowIndex = pos.x() >= kGutterW ? rowIndexAt(pos.y()) : -1;
    const bool voiceInsertionPreviewAvailable =
        rowIndex >= 0 &&
        m_rows[rowIndex].kind == AutomationRowId::Kind::Voice &&
        m_sv->document();
    if (rowIndex < 0 ||
        (!rowPoints(m_rows[rowIndex]) && !voiceInsertionPreviewAvailable)) {
      clearHoverFeedback();
      return;
    }

    const double tick = rawTickAt(pos.x());
    if (voiceInsertionPreviewAvailable) {
      const uint64_t insertionTick = m_sv->snapTick(tick);
      const int insertionX = kGutterW + m_sv->contentX(double(insertionTick));
      const bool previewVisible =
          !voiceChangeNear(pos.x()) && !voiceChangeNear(insertionX);
      const bool sameRow = rowIndex == m_hoverRow;
      const bool previewChanged =
          !sameRow || previewVisible != m_voiceInsertionPreviewVisible ||
          (previewVisible && insertionTick != m_voiceInsertionPreviewTick);
      m_hoverRow = rowIndex;
      m_hoverTick = tick;
      m_voiceInsertionPreviewTick = insertionTick;
      m_voiceInsertionPreviewVisible = previewVisible;
      if (previewChanged) {
        if (sameRow)
          update(
              QRect(0, rowTop(rowIndex), width(), rowHeight(m_rows[rowIndex])));
        else
          update();
      }
      return;
    }

    if (rowIndex == m_hoverRow && tick == m_hoverTick)
      return;
    m_hoverRow = rowIndex;
    m_hoverTick = tick;
    update();
  }

  // Invert paintCurve's valueY mapping; ri indexes the row for geometry.
  int valueAtY(const AutomationRowId &row, int ri, int yPos) const {
    int minV, maxV;
    rowRange(row, &minV, &maxV);
    const int top = rowTop(ri) + 5;
    const int bottom = rowBottom(ri) - 1 - 4;
    const int y = std::clamp(yPos, top, bottom);
    return minV + (bottom - y) * (maxV - minV) / std::max(1, bottom - top);
  }

  void updateDrag(qreal x, int y, bool fine, bool detent) {
    if (m_dragRow < 0 || m_dragRow >= int(m_rows.size()))
      return;
    const AutomationRowId &row = m_rows[m_dragRow];
    m_dragValue = valueAtY(row, m_dragRow, y);
    if (row.kind == AutomationRowId::Kind::Tempo)
      m_dragValue = std::max(1, m_dragValue);
    // Ctrl detent: magnetize to the lane's neutral value within ~8 px,
    // so dead-center doesn't require pixel-perfect aim.
    int neutral;
    if (detent && rowDetent(row, &neutral)) {
      int minV, maxV;
      rowRange(row, &minV, &maxV);
      const int plotH = std::max(1, rowHeight(row) - 10); // bottom - top
      if (std::abs(m_dragValue - neutral) <= (maxV - minV) * 8 / plotH)
        m_dragValue = neutral;
    }
    m_dragTick = m_sv->snapTick(rawTickAt(x), fine);
  }

  // Freehand sweep bookkeeping: fills every grid cell crossed since the
  // last mouse sample (linear interpolation, so a fast drag leaves no
  // gaps), overwriting cells swept more than once.
  void extendSweep(qreal x, bool fine) {
    const double rawTick = rawTickAt(x);
    const double from = m_prevTick;
    const double to = rawTick;
    const uint64_t t0 = m_sv->snapTick(std::min(from, to), fine);
    const uint64_t t1 = m_sv->snapTick(std::max(from, to), fine);
    const uint64_t g = std::max<uint64_t>(1, fine ? m_sv->fineGridTicks()
                                                  : m_sv->gridTicksAt(t0));
    for (uint64_t t = t0; t <= t1; t += g) {
      int v = m_dragValue;
      if (to != from) {
        const double f = std::clamp((double(t) - from) / (to - from), 0.0, 1.0);
        v = m_prevValue + int(std::llround(f * (m_dragValue - m_prevValue)));
      }
      sweepUpsert(t, v);
    }
    m_prevTick = rawTick;
    m_prevValue = m_dragValue;
  }

  void sweepUpsert(uint64_t tick, int value) {
    auto it = std::lower_bound(m_sweep.begin(), m_sweep.end(), tick,
                               [](const std::pair<uint64_t, int> &a,
                                  uint64_t t) { return a.first < t; });
    if (it != m_sweep.end() && it->first == tick)
      it->second = value;
    else
      m_sweep.insert(it, {tick, value});
  }

  std::vector<SongDocument::LanePointValue> sweepPoints() const {
    std::vector<SongDocument::LanePointValue> pts;
    pts.reserve(m_sweep.size());
    for (const std::pair<uint64_t, int> &s : m_sweep)
      pts.push_back({s.first, s.second});
    return pts;
  }

  void paintRow(QPainter &p, const AutomationRowId &row, const QRect &r) {
    p.setClipRect(r);
    p.setPen(themes::color(themes::Role::song_view_separator));
    p.drawLine(r.left(), r.bottom(), r.right(), r.bottom());

    // Gutter label.
    const QString name = rowTitle(row);
    const QColor primaryText =
        themes::color(themes::Role::song_view_primary_text);
    p.setPen(primaryText);
    const auto titleFont = typography::bold(font());
    const auto captionFont = typography::caption(font());
    QRect textBounds(8, r.top(), kGutterW - 16, r.height());

    p.setFont(titleFont);
    int minV = 0, maxV = 127;
    const std::vector<LanePoint> *points = nullptr;
    QColor curve =
        themes::color(themes::Role::song_view_automation_default_curve);
    rowRange(row, &minV, &maxV);
    switch (row.kind) {
    case AutomationRowId::Kind::Tempo:
      points = &m_sv->model().tempoLane;
      curve = themes::color(themes::Role::song_view_automation_tempo_curve);
      break;
    case AutomationRowId::Kind::Voice:
      break;
    case AutomationRowId::Kind::Controller:
      if (const AutoLane *lane = rowLane(row))
        points = &lane->points;
      curve = SongView::trackColor(row.track);
      break;
    }

    const auto textLayout = ::layout::twoLineText(
        titleFont, titleFont, captionFont, ::layout::Space::Zero);
    const auto textBoxes =
        textLayout.align(textBounds, ::layout::VerticalAlignment::Center);
    p.drawText(textBoxes.primary, Qt::AlignLeft | Qt::AlignVCenter, name);
    p.setFont(captionFont);
    if (points && !points->empty()) {
      p.setPen(themes::color(themes::Role::song_view_secondary_text));
      p.drawText(textBoxes.secondary, Qt::AlignLeft | Qt::AlignVCenter,
                 SongView::tr("%1 points · %2..%3")
                     .arg(points->size())
                     .arg(minV)
                     .arg(maxV));
    } else if (points && row.kind == AutomationRowId::Kind::Controller) {
      p.setPen(themes::color(themes::Role::song_view_secondary_text));
      p.drawText(textBoxes.secondary, Qt::AlignLeft | Qt::AlignVCenter,
                 SongView::tr("empty · click to add points"));
    } else if (row.kind == AutomationRowId::Kind::Voice && m_sv->document()) {
      const int voiceChangeCount = int(m_selectedTrackVoiceChanges.size());
      p.setPen(themes::color(themes::Role::song_view_secondary_text));
      p.drawText(textBoxes.secondary, Qt::AlignLeft | Qt::AlignVCenter,
                 voiceChangeCount
                     ? SongView::tr("%n change(s) · click to edit", nullptr,
                                    voiceChangeCount)
                     : SongView::tr("no voice set · click to add"));
    }

    const QRect plot(kGutterW, r.top(), width() - kGutterW, r.height());
    p.setClipRect(plot);
    drawGrid(p, m_sv, plot, kGutterW);

    if (row.kind == AutomationRowId::Kind::Voice)
      paintVoiceRow(p, plot);
    else if (points)
      paintCurve(p, plot, *points, minV, maxV, curve,
                 row.kind == AutomationRowId::Kind::Controller &&
                     row.cc == LANE_CC_BEND);

    const std::pair<int, uint8_t> id = rowIdentity(row);
    drawOverlays(p, m_sv, plot, kGutterW,
                 m_sv->timeSelectionCoversRow(id.first, id.second));
    p.setClipping(false);
  }

  void paintCurve(QPainter &p, const QRect &plot,
                  const std::vector<LanePoint> &points, int minV, int maxV,
                  const QColor &color, bool centerLine) {
    const int top = plot.top() + 5;
    const int bottom = plot.bottom() - 4;
    auto valueY = [&](int v) {
      return bottom - (v - minV) * (bottom - top) / std::max(1, maxV - minV);
    };
    const qreal dpr = p.device()->devicePixelRatioF();
    if (centerLine) {
      p.setPen(QPen(themes::color(themes::Role::song_view_separator), 1,
                    Qt::DashLine));
      p.drawLine(plot.left(), valueY(0), plot.right(), valueY(0));
    }
    p.setPen(QPen(color, 2));
    for (size_t i = 0; i < points.size(); i++) {
      const qreal x0 = m_sv->displayX(double(points[i].tick), kGutterW, dpr);
      const qreal x1 =
          i + 1 < points.size()
              ? m_sv->displayX(double(points[i + 1].tick), kGutterW, dpr)
              : plot.right();
      if (x1 < plot.left() || x0 > plot.right())
        continue;
      const int y = valueY(points[i].value);
      p.drawLine(QLineF(x0, y, x1, y)); // hold value until the next point
      if (i + 1 < points.size())
        p.drawLine(QLineF(x1, y, x1, valueY(points[i + 1].value)));
      if (m_sv->pxPerBeat() >= 24.0)
        p.fillRect(QRectF(x0 - 1, y - 1, 3, 3), color);
    }
  }

  void paintVoiceRow(QPainter &p, const QRect &plot) {
    const int selectedTrack = m_sv->selectedTrack();
    const QColor color = SongView::trackColor(selectedTrack);
    const qreal dpr = p.device()->devicePixelRatioF();
    auto paintChange = [&](const VoiceChange &change, qreal regionEndX) {
      const qreal x = m_sv->displayX(double(change.tick), kGutterW, dpr);
      if (regionEndX < plot.left() || x > plot.right())
        return;
      p.setPen(QPen(color, 2));
      p.drawLine(QLineF(x, plot.top() + 4, x, plot.bottom() - 4));
      p.setPen(themes::color(themes::Role::song_view_primary_text));
      const QString text =
          QStringLiteral("%1 %2")
              .arg(int(change.program), 3, 10, QLatin1Char('0'))
              .arg(m_sv->voiceShortName(change.program));
      // Keep the label readable while its voice region is scrolled
      // partially off the left edge.
      const qreal textX = std::max<qreal>(x + 4, plot.left() + 4);
      const qreal textWidth = std::max<qreal>(10.0, regionEndX - textX - 4);
      p.drawText(
          QRectF(textX, plot.top() + 4, textWidth, plot.height() - 8),
          Qt::AlignLeft | Qt::AlignVCenter,
          fontMetrics().elidedText(text, Qt::ElideRight, qFloor(textWidth)));
    };

    const VoiceChange *previousChange = nullptr;
    for (const VoiceChange &change : m_selectedTrackVoiceChanges) {
      if (previousChange)
        paintChange(*previousChange,
                    m_sv->displayX(double(change.tick), kGutterW, dpr));
      previousChange = &change;
    }
    if (previousChange)
      paintChange(*previousChange, plot.right());
  }

  // Left-drag gestures: Point moves an existing point (press landed near
  // one), Sweep freehand-draws a stream of points, Line (Shift) commits an
  // interpolated ramp between press and release. Alt snaps to the clock
  // grid instead of the visible grid throughout; Ctrl magnetizes the value
  // to the lane's neutral (pan/tune center, zero bend); double-click opens
  // a type-in for the exact value.
  QScrollArea *scrollArea() const {
    auto *viewport = parentWidget();
    return viewport ? qobject_cast<QScrollArea *>(viewport->parentWidget())
                    : nullptr;
  }

  enum class Gesture { None, Point, Sweep, Line };

  SongView *m_sv;
  std::vector<AutomationRowId> m_rows;
  std::vector<VoiceChange> m_selectedTrackVoiceChanges;
  int m_laneH = kLaneH;    // shared row height; Ctrl+wheel rescales
  int m_laneZoomAccum = 0; // sub-notch wheel remainder, like zoomKeyHeight
  QHash<AutomationRowId, AutomationRowDisplayState> m_rowStates;
  int m_resizeRow = -1; // row whose bottom divider is being dragged
  int m_resizeOrigH = 0;
  int m_resizePressY = 0;
  bool m_panning = false;    // middle-drag pan
  QPointF m_panPos;          // last pan sample, global coords
  bool m_rightPress = false; // right button held; sweep vs. click undecided
  bool m_selSweep = false;   // right-drag time-selection sweep is live
  QPoint m_rightPressPos;
  int m_rightRow = -1; // row of the right press
  uint64_t m_selAnchorTick = 0;
  Gesture m_gesture = Gesture::None;
  int m_dragRow = -1;
  int64_t m_dragOrigTick = -1; // existing point being moved, -1 = new point
  uint64_t m_dragTick = 0;
  int m_dragValue = 0;
  std::vector<std::pair<uint64_t, int>> m_sweep; // tick-sorted freehand samples
  uint64_t m_lineStartTick = 0;                  // Shift-drag anchor
  int m_lineStartValue = 0;
  double m_prevTick = 0.0; // last raw (unsnapped) sweep sample
  int m_prevValue = 0;
  int m_hoverRow = -1;      // row under an idle cursor; -1 = no readout
  double m_hoverTick = 0.0; // raw tick under the idle cursor
  uint64_t m_voiceInsertionPreviewTick = 0;
  bool m_voiceInsertionPreviewVisible = false;
};

// ---------------------------------------------------------------- OtherStrip

class OtherStrip : public QWidget {
public:
  explicit OtherStrip(SongView *sv) : QWidget(sv), m_sv(sv) {
    setFixedHeight(QFontMetrics(font()).height() + lyt::space(Space::Two));
    setMouseTracking(true);
  }

protected:
  void paintEvent(QPaintEvent *) override {
    QPainter p(this);
    const qreal dpr = p.device()->devicePixelRatioF();
    p.fillRect(rect(), themes::color(
                           themes::Role::song_view_timeline_chrome_background));
    p.setPen(themes::color(themes::Role::song_view_separator));
    p.drawLine(0, 0, width(), 0);

    const SongViewModel &model = m_sv->model();
    p.setPen(themes::color(themes::Role::song_view_primary_text));
    const auto textInset = lyt::space(Space::Two);
    p.drawText(QRect(textInset, 0, kGutterW - 2 * textInset, height()),
               Qt::AlignVCenter,
               SongView::tr("Other events (%1)").arg(model.strip.size()));
    if (!m_sv->timeline())
      return;

    const QRect area(kGutterW, 0, width() - kGutterW, height());
    p.setClipRect(area);
    drawOverlays(p, m_sv, area, kGutterW, false);

    const int cy = height() / 2;
    for (const StripItem &item : model.strip) {
      const qreal x = m_sv->displayX(double(item.tick), kGutterW, dpr);
      if (x < area.left() - 4 || x > area.right() + 4)
        continue;
      QColor c = item.track >= 0
                     ? SongView::trackColor(item.track)
                     : themes::color(themes::Role::song_view_file_event_marker);
      QPainterPath diamond;
      diamond.moveTo(x, cy - 5);
      diamond.lineTo(x + 4, cy);
      diamond.lineTo(x, cy + 5);
      diamond.lineTo(x - 4, cy);
      diamond.closeSubpath();
      p.fillPath(diamond, c);
    }
  }

  void mouseMoveEvent(QMouseEvent *event) override {
    const MidiTimeline *tl = m_sv->timeline();
    if (!tl || event->position().x() < kGutterW) {
      QToolTip::hideText();
      return;
    }
    QStringList lines;
    for (const StripItem &item : m_sv->model().strip) {
      const qreal x =
          m_sv->displayX(double(item.tick), kGutterW, devicePixelRatioF());
      if (std::abs(x - event->position().x()) > 4)
        continue;
      const double seconds =
          double(tl->sampleForTick(item.tick)) / tl->sampleRate;
      QString where = item.track >= 0
                          ? SongView::tr("Track %1").arg(item.track + 1)
                          : SongView::tr("File");
      lines << QStringLiteral("%1:%2 · %3 · %4")
                   .arg(int(seconds) / 60)
                   .arg(int(seconds) % 60, 2, 10, QLatin1Char('0'))
                   .arg(where, item.label);
      if (lines.size() >= 12) {
        lines << SongView::tr("…");
        break;
      }
    }
    if (lines.isEmpty())
      QToolTip::hideText();
    else
      QToolTip::showText(event->globalPosition().toPoint(),
                         lines.join(QStringLiteral("\n")), this);
  }

private:
  SongView *m_sv;
};

// ---------------------------------------------------------- VoicePickerDialog

// Modal instrument picker (SPEC §4.2): the voicegroup's 128 entries, the same
// list the import wizard's mapping combo renders. Press-and-hold auditions
// through the preview engine; double-click chooses.
class VoicePickerDialog : public QDialog {
public:
  VoicePickerDialog(SongView *sv, const QString &title, int initialVoice,
                    std::function<void(int, int)> audition)
      : QDialog(sv), m_audition(std::move(audition)) {
    setWindowTitle(title);
    resize(lyt::fontPx(30), lyt::fontPx(110.0 / 3.0));
    auto *dialogLayout = new QVBoxLayout(this);
    auto *searchField = new QLineEdit(this);
    searchField->setPlaceholderText(tr("Search voices..."));
    searchField->setClearButtonEnabled(true);
    dialogLayout->addWidget(searchField);
    m_list = new QListWidget(this);
    m_list->setUniformItemSizes(true);
    m_list->setToolTip(SongView::tr("Click and hold to audition (middle C)."));
    for (int v = 0; v < VOICEGROUP_SIZE; v++)
      m_list->addItem(QStringLiteral("%1  %2")
                          .arg(v, 3, 10, QLatin1Char('0'))
                          .arg(sv->voiceShortName(uint8_t(v))));
    m_list->setCurrentRow(std::clamp(initialVoice, 0, VOICEGROUP_SIZE - 1));
    m_list->scrollToItem(m_list->currentItem(),
                         QAbstractItemView::PositionAtCenter);
    dialogLayout->addWidget(m_list, 1);

    auto *dialogButtons = new QDialogButtonBox(
        QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    connect(dialogButtons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(dialogButtons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    dialogLayout->addWidget(dialogButtons);
    connect(searchField, &QLineEdit::textChanged, this,
            [this, dialogButtons](const QString &query) {
              QListWidgetItem *firstMatchingVoice = nullptr;
              for (int voiceIndex = 0; voiceIndex < m_list->count();
                   ++voiceIndex) {
                QListWidgetItem *voiceItem = m_list->item(voiceIndex);
                const bool matchesQuery =
                    voiceItem->text().contains(query, Qt::CaseInsensitive);
                voiceItem->setHidden(!matchesQuery);
                if (matchesQuery && !firstMatchingVoice)
                  firstMatchingVoice = voiceItem;
              }
              m_list->setCurrentItem(firstMatchingVoice);
              dialogButtons->button(QDialogButtonBox::Ok)
                  ->setEnabled(firstMatchingVoice);
            });
    searchField->setFocus();

    connect(m_list, &QListWidget::itemPressed, this,
            [this](QListWidgetItem *item) {
              releaseVoice();
              if (item) {
                m_sounding = m_list->row(item);
                m_audition(m_sounding, kVoiceAuditionVel);
              }
            });
    connect(m_list, &QListWidget::itemDoubleClicked, this,
            [this] { accept(); });
    m_list->viewport()->installEventFilter(this);
  }

  ~VoicePickerDialog() override { releaseVoice(); }

  int selectedVoice() const { return std::max(0, m_list->currentRow()); }

  bool eventFilter(QObject *watched, QEvent *event) override {
    if (watched == m_list->viewport() &&
        event->type() == QEvent::MouseButtonRelease)
      releaseVoice();
    return QDialog::eventFilter(watched, event);
  }

private:
  void releaseVoice() {
    if (m_sounding < 0)
      return;
    m_audition(m_sounding, 0);
    m_sounding = -1;
  }

  QListWidget *m_list;
  std::function<void(int, int)> m_audition;
  int m_sounding = -1;
};

// ---------------------------------------------------------- TrackHeaderPanel

class TrackHeaderRow : public QWidget {
public:
  TrackHeaderRow(SongView *sv, int track, QWidget *parent)
      : QWidget(parent), m_sv(sv), m_track(track) {
    const auto buttonExtent = ::layout::fontPx(1.5);
    setFixedHeight(::layout::fontPx(4.0));
    auto *layout = new QHBoxLayout(this);
    layout->setContentsMargins(::layout::space(::layout::Space::Zero),
                               ::layout::space(::layout::Space::Zero),
                               ::layout::space(::layout::Space::One),
                               ::layout::singlePixel());
    layout->addStretch();

    auto *buttons = new QVBoxLayout;
    buttons->setSpacing(::layout::space(::layout::Space::Zero));
    m_mute = new QToolButton(this);
    m_mute->setAutoRaise(false);
    m_mute->setText(QStringLiteral("M"));
    m_mute->setCheckable(true);
    m_mute->setFixedSize(buttonExtent, buttonExtent);
    m_mute->setObjectName(QStringLiteral("trackMuteButton"));
    m_mute->setToolTip(SongView::tr("Mute"));
    // Headers are rebuilt on every document edit; keep the persistent
    // mute/solo state (checked before connect, so nothing re-emits).
    m_mute->setChecked(sv->trackMuted(track));
    connect(m_mute, &QToolButton::toggled, this,
            [this](bool on) { m_sv->setTrackMute(m_track, on); });
    m_solo = new QToolButton(this);
    m_solo->setAutoRaise(false);
    m_solo->setText(QStringLiteral("S"));
    m_solo->setCheckable(true);
    m_solo->setFixedSize(buttonExtent, buttonExtent);
    m_solo->setObjectName(QStringLiteral("trackSoloButton"));
    m_solo->setToolTip(SongView::tr("Solo"));
    m_solo->setChecked(sv->trackSoloed(track));
    connect(m_solo, &QToolButton::toggled, this,
            [this](bool on) { m_sv->setTrackSolo(m_track, on); });
    buttons->addStretch();
    buttons->addWidget(m_mute);
    buttons->addStretch();
    buttons->addWidget(m_solo);
    buttons->addStretch();
    layout->addLayout(buttons);
    layout->setAlignment(buttons, Qt::AlignVCenter);
  }

  int track() const { return m_track; }

  // True when the song's music player never starts this track in-game
  // (track index at or beyond SongDocument::trackBudget).
  bool isSilentInGame() const {
    const SongDocument *doc = m_sv->document();
    return doc && m_track >= doc->trackBudget();
  }

protected:
  void paintEvent(QPaintEvent *) override {
    QPainter p(this);
    const bool selected = m_sv->selectedTrack() == m_track;
    if (selected) {
      // The derived selection fill has the required lightness gap. Keep
      // it opaque so the visible header reaches that target.
      p.fillRect(rect(),
                 themes::color(themes::Role::song_view_track_header_selection));
    } else if (m_sv->trackSelectionMask() & (1u << m_track)) {
      // Part of the multi-track scope (Ctrl/Shift+click), lighter than
      // the primary selection.
      p.fillRect(rect(), trackHeaderAlsoSelectedColor());
    }
    p.fillRect(QRect(0, 0, lyt::space(Space::One), height()),
               SongView::trackColor(m_track));
    p.setPen(QPen(themes::color(themes::Role::song_view_separator),
                  lyt::singlePixel()));
    p.drawLine(0, height() - lyt::singlePixel(), width(),
               height() - lyt::singlePixel());

    const MidiTimeline *tl = m_sv->timeline();
    QString name = tl ? tl->tracks[m_track].name : QString();
    if (name.isEmpty())
      name = SongView::tr("Track %1").arg(m_track + 1);
    const auto textInset = lyt::space(Space::Two);
    const auto textW = width() - lyt::fontPx(2) - textInset;
    const auto title = QStringLiteral("%1 · %2").arg(m_track + 1).arg(name);
    const auto normalTitleFont = p.font();
    const auto titleFont =
        selected ? typography::bold(normalTitleFont) : normalTitleFont;
    const auto titleMetrics = QFontMetrics(titleFont);
    const auto visibleTitle =
        titleMetrics.elidedText(title, Qt::ElideRight, textW);
    // The song's music player never starts this track in-game
    // (MPlayStart), so playback mutes it; the header must read as inert
    // at a glance: text recedes most of the way into the backdrop and a
    // faint cross spans the row, under the text so labels stay legible.
    const bool silentInGame = isSilentInGame();
    const QColor backdrop =
        selected ? themes::color(themes::Role::song_view_track_header_selection)
        : (m_sv->trackSelectionMask() & (1u << m_track))
            ? trackHeaderAlsoSelectedColor()
            : palette().color(QPalette::Window);
    QColor titleColor =
        selected
            ? themes::color(themes::Role::song_view_track_header_selection_text)
            : themes::color(themes::Role::song_view_primary_text);
    QColor subtitleColor =
        selected
            ? themes::color(themes::Role::song_view_track_header_selection_text)
            : themes::color(themes::Role::song_view_secondary_text);
    if (silentInGame) {
      titleColor = mixTowardOklab(titleColor, backdrop, selected ? 0.35 : 0.6);
      subtitleColor =
          mixTowardOklab(subtitleColor, backdrop, selected ? 0.35 : 0.6);
      QColor cross = mixTowardOklab(titleColor, backdrop, 0.3);
      p.save();
      p.setRenderHint(QPainter::Antialiasing);
      p.setPen(QPen(cross, lyt::singlePixel()));
      const QRectF box = QRectF(rect()).adjusted(
          lyt::space(Space::One), lyt::space(Space::One),
          -lyt::space(Space::One),
          -lyt::space(Space::One) - lyt::singlePixel());
      p.drawLine(box.topLeft(), box.bottomRight());
      p.drawLine(box.bottomLeft(), box.topRight());
      p.restore();
    }
    p.setFont(titleFont);
    p.setPen(titleColor);
    const auto subtitleFont = typography::caption(normalTitleFont);
    const auto subtitleMetrics = QFontMetrics(subtitleFont);
    const auto textLayout = ::layout::twoLineText(
        normalTitleFont, typography::bold(normalTitleFont), subtitleFont,
        ::layout::Space::Half);
    // The bottom pixel belongs to the separator, not the row's content.
    const auto textBounds = QRect(10, 0, textW, height() - lyt::singlePixel());
    const auto textBoxes =
        textLayout.align(textBounds, ::layout::VerticalAlignment::Center);
    // Bold and regular glyph bounds differ. Translate the selected title
    // so changing weight does not make the visible text jump.
    const auto titleBox = QRectF(textBoxes.primary)
                              .translated(typography::glyphCenteringOffset(
                                  normalTitleFont, titleFont, visibleTitle));
    p.drawText(titleBox, Qt::AlignLeft | Qt::AlignVCenter, visibleTitle);

    p.setFont(subtitleFont);
    p.setPen(subtitleColor);
    m_shownProgram = m_sv->currentProgram(m_track);
    const QString subtitle = silentInGame
                                 ? SongView::tr("silent in-game · %1")
                                       .arg(m_sv->instrumentLabel(m_track))
                                 : m_sv->instrumentLabel(m_track);
    p.drawText(textBoxes.secondary, Qt::AlignLeft | Qt::AlignVCenter,
               subtitleMetrics.elidedText(subtitle, Qt::ElideRight, textW));
  }

  // The painted voice line (paintEvent's instrument-label rect): a plain
  // click here also reveals the voice in the voicegroup dock.
  QRect voiceLineRect() const { return QRect(10, 22, width() - 36, 16); }

  void mousePressEvent(QMouseEvent *event) override {
    m_sv->trackHeaderClicked(m_track, event->modifiers());
    // A plain left press may become a reorder drag (the track's chunk
    // moves — AGB track order is chunk order).
    m_dragArmed =
        event->button() == Qt::LeftButton &&
        !(event->modifiers() & (Qt::ControlModifier | Qt::ShiftModifier)) &&
        m_sv->document();
    m_voiceClickArmed =
        event->button() == Qt::LeftButton &&
        !(event->modifiers() & (Qt::ControlModifier | Qt::ShiftModifier)) &&
        voiceLineRect().contains(event->pos());
    m_pressPos = event->pos();
  }

  // Defined below TrackHeaderPanel (they drive its drag state).
  void mouseMoveEvent(QMouseEvent *event) override;
  void mouseReleaseEvent(QMouseEvent *event) override;

public:
  // Inline rename: a line edit overlaid on the row's name line. Return
  // commits, Escape cancels (both restore the roll's focus), focus-out
  // commits Reaper-style. The document edit itself is queued by
  // commitTrackRename — it rebuilds the header panel, which would delete
  // this row and the editor mid-signal.
  // The voice line follows the song's program changes as the playhead (or
  // edit cursor) moves; repaint only when the shown program flips.
  void syncVoice() {
    if (m_shownProgram == m_sv->currentProgram(m_track))
      return;
    update();
    updateToolTip();
  }

  void updateToolTip() {
    const MidiTimeline *tl = m_sv->timeline();
    if (!tl)
      return;
    QString tip = SongView::tr("%1 notes · %2")
                      .arg(tl->tracks[m_track].noteCount)
                      .arg(m_sv->instrumentLabel(m_track));
    if (isSilentInGame()) {
      tip += SongView::tr(
                 "\nSilent in-game: this song's music player only allocates "
                 "%1 track(s) (sound/music_player_table.inc), and the game "
                 "never starts the tracks beyond them. porydaw plays it the "
                 "same way. Raise the player's track count in the project to "
                 "use this track.")
                 .arg(m_sv->document()->trackBudget());
    }
    if (m_sv->document()) {
      tip += SongView::tr("\nDouble-click to rename · right-click "
                          "to change voice, duplicate, or delete"
                          " · drag to reorder"
                          "\nClick the voice name to show it in the "
                          "voicegroup dock · double-click it to "
                          "change the voice");
    }
    setToolTip(tip);
  }

  void beginRename() {
    SongDocument *doc = m_sv->document();
    if (!doc)
      return;
    if (!m_editor) {
      m_editor = new QLineEdit(this);
      m_editor->setObjectName(QStringLiteral("trackRenameEditor"));
      m_editor->installEventFilter(this);
      connect(m_editor, &QLineEdit::editingFinished, this,
              [this] { finishRename(true, false); });
    }
    m_editor->setText(doc->trackName(m_track));
    // What an empty name falls back to (mirrors the painted default).
    m_editor->setPlaceholderText(SongView::tr("Track %1").arg(m_track + 1));
    m_editor->setGeometry(editorRect());
    m_editor->show();
    m_editor->setFocus();
    m_editor->selectAll();
  }

  // Reaper-style commit for gestures that will rebuild the panel: header
  // rows take no focus, so pressing one never gives the editor a
  // focus-out — without this, the rebuild would destroy the editor and
  // silently drop the typed name.
  void commitOpenRename() { finishRename(true, false); }

protected:
  void mouseDoubleClickEvent(QMouseEvent *event) override {
    m_sv->selectTrack(m_track);
    // The voice line opens the voice picker (its single click already
    // revealed the voice in the dock); anywhere else renames. Queued:
    // the picked voice's edit rebuilds the header panel, deleting this
    // row out from under its own event handler.
    if (voiceLineRect().contains(event->pos())) {
      QMetaObject::invokeMethod(
          m_sv, [sv = m_sv, t = m_track] { sv->editTrackVoice(t); },
          Qt::QueuedConnection);
      return;
    }
    beginRename();
  }

  void contextMenuEvent(QContextMenuEvent *event) override {
    if (!m_sv->document())
      return;
    // A right-click with the left button still down is a mid-drag
    // cancel (mouseReleaseEvent), not a menu request.
    if (QApplication::mouseButtons() & Qt::LeftButton)
      return;
    m_sv->selectTrack(m_track);
    QMenu menu(this);
    QAction *voiceAction = menu.addAction(SongView::tr("Change voice..."));
    QAction *showVoiceAction =
        menu.addAction(SongView::tr("Show voice in voicegroup"));
    QAction *renameAction = menu.addAction(SongView::tr("Rename track..."));
    QAction *duplicateAction = menu.addAction(SongView::tr("Duplicate track"));
    duplicateAction->setEnabled(m_sv->document()->canAddTrack());
    QAction *deleteAction = menu.addAction(SongView::tr("Delete track"));
    QAction *chosen = menu.exec(event->globalPos());
    // Queued: these edits rebuild the header panel, which deletes this
    // row out from under its own event handler. (Rename just opens the
    // inline editor — no edit until it commits — so it's direct.)
    if (chosen == renameAction) {
      beginRename();
    } else if (chosen == showVoiceAction) {
      // No document edit — nothing rebuilds, so no queue needed.
      m_sv->revealTrackVoice(m_track);
    } else if (chosen == voiceAction) {
      QMetaObject::invokeMethod(
          m_sv, [sv = m_sv, t = m_track] { sv->editTrackVoice(t); },
          Qt::QueuedConnection);
    } else if (chosen == duplicateAction) {
      QMetaObject::invokeMethod(
          m_sv, [sv = m_sv, t = m_track] { sv->duplicateTrack(t); },
          Qt::QueuedConnection);
    } else if (chosen == deleteAction) {
      QMetaObject::invokeMethod(
          m_sv, [sv = m_sv, t = m_track] { sv->deleteTrack(t); },
          Qt::QueuedConnection);
    }
  }

  bool eventFilter(QObject *watched, QEvent *event) override {
    if (watched == m_editor && event->type() == QEvent::KeyPress) {
      auto *keyEvent = static_cast<QKeyEvent *>(event);
      if (keyEvent->key() == Qt::Key_Escape) {
        finishRename(false, true);
        return true;
      }
      if (keyEvent->key() == Qt::Key_Return ||
          keyEvent->key() == Qt::Key_Enter) {
        finishRename(true, true);
        return true;
      }
    }
    return QWidget::eventFilter(watched, event);
  }

  void resizeEvent(QResizeEvent *) override {
    // Rows are born 100px wide and only get their real width on the
    // deferred layout pass; an open editor must follow.
    if (m_editor)
      m_editor->setGeometry(editorRect());
  }

private:
  // The row's name line, clear of the color strip and the M/S column.
  QRect editorRect() const { return QRect(6, 2, width() - 32, 20); }

  void finishRename(bool commit, bool restoreFocus) {
    // isHidden, not isVisible: the guard must also hold when the view
    // itself isn't shown (offscreen harnesses). m_finishing blocks the
    // editingFinished that hide()'s focus-out re-emits.
    if (!m_editor || m_editor->isHidden() || m_finishing)
      return;
    m_finishing = true;
    const QString text = m_editor->text();
    m_editor->hide();
    m_finishing = false;
    if (restoreFocus)
      m_sv->focusContent();
    if (commit)
      m_sv->commitTrackRename(m_track, text);
  }

  SongView *m_sv;
  int m_track;
  QToolButton *m_mute;
  QToolButton *m_solo;
  QLineEdit *m_editor = nullptr;
  bool m_finishing = false;
  // Program painted on the voice line, for syncVoice's changed check
  // (-2 = never painted; distinct from -1, "no voice set").
  int m_shownProgram = -2;
  QPoint m_pressPos;
  bool m_dragArmed = false;
  bool m_dragging = false;
  bool m_voiceClickArmed = false;
};

class TrackHeaderPanel : public QWidget {
public:
  explicit TrackHeaderPanel(SongView *sv) : QWidget(nullptr), m_sv(sv) {
    setObjectName(QStringLiteral("trackHeaderPanel"));
    setAttribute(Qt::WA_StyledBackground);
    m_layout = new QVBoxLayout(this);
    m_layout->setContentsMargins(0, 0, 0, 0);
    m_layout->setSpacing(0);
    m_layout->addStretch();
    // Reorder-drag drop indicator: a thin line floating over the rows at
    // the insertion point.
    m_indicator = new QWidget(this);
    m_indicator->setFixedHeight(3);
    m_indicator->setStyleSheet(
        QStringLiteral("background: palette(highlight);"));
    m_indicator->hide();
  }

  void rebuild() {
    // A document edit mid-drag rebuilds the rows, deleting the dragged
    // one out from under its own gesture; abandon the drag first.
    endRowDrag(false);
    // Deferred deletion: a rebuild can arrive from inside a row's own
    // mouse press (clicking a header focuses the roll, which fires an
    // editor field's editingFinished; a structural voice commit then
    // swaps the voicegroup into every view). Freeing the rows here
    // would leave that row's event handler running on freed memory.
    // Keep them parented (their mouse handlers cast parentWidget())
    // but hidden and anonymous until the event loop collects them.
    for (QWidget *row : m_rows) {
      row->hide();
      // Anonymous, children included: name lookups (the rename
      // editor, harness hooks) must only ever see the live rows.
      row->setObjectName(QString());
      for (QWidget *child : row->findChildren<QWidget *>())
        child->setObjectName(QString());
      m_layout->removeWidget(row);
      row->deleteLater();
    }
    m_rows.clear();
    m_rowByTrack.clear();
    m_trackRows.clear();
    const MidiTimeline *tl = m_sv->timeline();
    if (tl) {
      for (int t = 0; t < 16; t++) {
        if (!tl->tracks[t].used)
          continue;
        auto *row = new TrackHeaderRow(m_sv, t, this);
        row->setObjectName(QStringLiteral("trackHeaderRow%1").arg(t));
        m_rowByTrack[t] = row;
        row->updateToolTip();
        m_layout->insertWidget(m_layout->count() - 1, row);
        m_rows.push_back(row);
        m_trackRows.push_back(row);
      }
      SongDocument *doc = m_sv->document();
      if (doc && doc->canAddTrack()) {
        auto *add = new QPushButton(SongView::tr("+ Add track"), this);
        add->setFocusPolicy(Qt::NoFocus);
        add->setToolTip(SongView::tr("Add a track (picks its voice first)"));
        // Queued: the edit rebuilds this panel, deleting the button
        // out from under its own clicked handler.
        connect(
            add, &QPushButton::clicked, m_sv, [sv = m_sv] { sv->addTrack(); },
            Qt::QueuedConnection);
        m_layout->insertWidget(m_layout->count() - 1, add);
        m_rows.push_back(add);
      }
    }
  }

  void syncSelection() {
    for (QWidget *row : m_rows)
      row->update();
  }

  void beginRename(int track) {
    const auto it = m_rowByTrack.find(track);
    if (it != m_rowByTrack.end())
      it->second->beginRename();
  }

  // Called on every playhead/cursor move; each row repaints only when its
  // shown program actually changes.
  void syncVoices() {
    for (const auto &entry : m_rowByTrack)
      entry.second->syncVoice();
  }

  // --- header-row reorder drag (driven by TrackHeaderRow's mouse events;
  // the panel owns the state so a mid-drag rebuild can abandon it) ---

  bool beginRowDrag(int track) {
    if (m_dragFrom >= 0 || m_trackRows.size() < 2)
      return false;
    m_dragFrom = track;
    m_dropSlot = -1;
    QApplication::setOverrideCursor(Qt::ClosedHandCursor);
    return true;
  }

  void dragRowTo(QPoint pos) {
    if (m_dragFrom < 0)
      return;
    // Insertion slot: before the first row whose center is below the
    // cursor; past the last row otherwise.
    int slot = 0;
    for (const TrackHeaderRow *row : m_trackRows) {
      if (pos.y() > row->y() + row->height() / 2)
        slot++;
    }
    m_dropSlot = slot;
    const int y = slot < int(m_trackRows.size())
                      ? m_trackRows[size_t(slot)]->y()
                      : m_trackRows.back()->y() + m_trackRows.back()->height();
    m_indicator->setGeometry(0, y - 1, width(), 3);
    m_indicator->raise();
    m_indicator->show();
  }

  void endRowDrag(bool commit) {
    if (m_dragFrom < 0)
      return;
    const int from = m_dragFrom;
    const int slot = m_dropSlot;
    m_dragFrom = -1;
    m_dropSlot = -1;
    m_indicator->hide();
    QApplication::restoreOverrideCursor();
    if (!commit || slot < 0)
      return;
    int fromIdx = -1;
    for (size_t i = 0; i < m_trackRows.size(); i++) {
      if (m_trackRows[i]->track() == from)
        fromIdx = int(i);
    }
    // The slots adjacent to the dragged row leave it where it was.
    if (fromIdx < 0 || slot == fromIdx || slot == fromIdx + 1)
      return;
    const int target =
        m_trackRows[size_t(slot > fromIdx ? slot - 1 : slot)]->track();
    // The move's rebuild would destroy an open rename editor without a
    // focus-out (rows take no focus): commit it Reaper-style first. Its
    // queued commit runs before the queued move below, and renameTrack
    // renumbers nothing, so both captured track numbers stay valid.
    for (const auto &entry : m_rowByTrack)
      entry.second->commitOpenRename();
    // Queued: the edit rebuilds this panel, deleting the dragged row out
    // from under its own mouse-release handler.
    QMetaObject::invokeMethod(
        m_sv, [sv = m_sv, from, target] { sv->moveTrack(from, target); },
        Qt::QueuedConnection);
  }

private:
  SongView *m_sv;
  QVBoxLayout *m_layout;
  std::vector<QWidget *> m_rows;
  std::map<int, TrackHeaderRow *> m_rowByTrack;
  std::vector<TrackHeaderRow *> m_trackRows;
  QWidget *m_indicator = nullptr;
  int m_dragFrom = -1; // dragged engine track; -1 = no drag live
  int m_dropSlot = -1; // insertion slot the indicator marks
};

// The drag handlers live below TrackHeaderPanel because they drive it.

void TrackHeaderRow::mouseMoveEvent(QMouseEvent *event) {
  auto *panel = static_cast<TrackHeaderPanel *>(parentWidget());
  if (!m_dragging) {
    if (!m_dragArmed || !(event->buttons() & Qt::LeftButton) ||
        (event->pos() - m_pressPos).manhattanLength() <
            QApplication::startDragDistance())
      return;
    m_dragging = panel->beginRowDrag(m_track);
    if (!m_dragging)
      return;
  }
  panel->dragRowTo(mapTo(panel, event->pos()));
}

void TrackHeaderRow::mouseReleaseEvent(QMouseEvent *event) {
  // Only a left release drops the row; any other button mid-drag is a
  // cancel gesture (matching the ruler's and roll's release handling).
  if (event->button() != Qt::LeftButton) {
    if (m_dragging) {
      m_dragging = false;
      m_dragArmed = false;
      static_cast<TrackHeaderPanel *>(parentWidget())->endRowDrag(false);
    }
    return;
  }
  m_dragArmed = false;
  const bool voiceClick = m_voiceClickArmed;
  m_voiceClickArmed = false;
  if (!m_dragging) {
    // A completed plain click on the voice line (not a drag, released
    // where it pressed) surfaces the track's voice in the dock.
    if (voiceClick && voiceLineRect().contains(event->pos()))
      m_sv->revealTrackVoice(m_track);
    return;
  }
  m_dragging = false;
  static_cast<TrackHeaderPanel *>(parentWidget())->endRowDrag(true);
}

} // namespace songview

// ------------------------------------------------------------------ SongView

using namespace songview;
int SongView::canonicalNoteVelocity(int track, uint64_t tick, uint8_t key,
                                    int proposedVelocity) const {
  const auto context = songview::psgVelocityContext(this, track, tick, key);
  if (!context)
    return std::clamp(proposedVelocity, 1, 127);
  return psgCanonicalVelocity(*context, proposedVelocity);
}

std::optional<uint8_t> SongView::noteVelocityLevel(int track, uint64_t tick,
                                                   uint8_t key,
                                                   int velocity) const {
  const auto context = songview::psgVelocityContext(this, track, tick, key);
  if (!context)
    return std::nullopt;
  return psgVelocityLevel(*context, uint8_t(std::clamp(velocity, 1, 127)));
}

std::optional<uint8_t>
SongView::velocityForLevel(int track, uint64_t tick, uint8_t key,
                           uint8_t requestedLevel) const {
  const auto context = songview::psgVelocityContext(this, track, tick, key);
  if (!context)
    return std::nullopt;
  return psgVelocityForLevel(psgVelocityDetents(*context), requestedLevel);
}

std::optional<PsgVelocityContext>
SongView::velocityAxisContext(int track) const {
  if (!m_document || !m_voicegroup || !m_timeline || track < 0 || track >= 16)
    return std::nullopt;
  const uint64_t tick =
      m_playing ? uint64_t(m_playheadTick) : m_editCursorTick;
  const int program = programAt(track, tick);
  if (program < 0 || program >= VOICEGROUP_SIZE)
    return std::nullopt;
  const ToneData &tone = m_voicegroup->voices[std::size_t(program)];
  if (tone.type & (VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL))
    return std::nullopt;
  // The idle ruler describes the active program's detent model. Track
  // VOL/PAN automation affects note loudness, not the ruler's geometry.
  return makePsgVelocityContext(tone, 0, 127, 64,
                                m_document->cfg().masterVolume);
}

void SongView::refreshVelocityAxisContext() {
  const auto context = velocityAxisContext(m_selectedTrack);
  if (context == m_velocityAxisContext)
    return;
  m_velocityAxisContext = context;
  if (m_velocityArea)
    m_velocityArea->update();
}

std::optional<VelocityDetentInfo>
SongView::velocityAxisDetents(int track,
                              const std::vector<NoteId> &notes) const {
  if (track < 0 || track >= 16)
    return std::nullopt;
  if (notes.empty()) {
    const auto context = velocityAxisContext(track);
    return context
               ? std::optional<VelocityDetentInfo>{psgVelocityDetents(*context)}
               : std::nullopt;
  }
  auto commonDetents = std::optional<VelocityDetentInfo>{};
  for (const auto &note : notes) {
    const auto context =
        songview::psgVelocityContext(this, track, note.tick, note.key);
    if (!context)
      return std::nullopt;
    const auto detents = psgVelocityDetents(*context);
    if (!commonDetents) {
      commonDetents = detents;
    } else if (!velocityDetentsCompatible(*commonDetents, detents)) {
      return std::nullopt;
    }
  }
  return commonDetents;
}

SongView::SongView(QWidget *parent) : QWidget(parent) {
  auto *vbox = new QVBoxLayout(this);
  vbox->setContentsMargins(0, 0, 0, 0);
  vbox->setSpacing(0);

  m_ruler = new TimeRuler(this);
  vbox->addWidget(m_ruler);

  // EditorDrawer owns the positioned overlay. The roll still fills its host,
  // so opening the drawer never changes track-header or piano-roll layout.
  auto *rollPane = new QWidget;
  auto *mid = new QHBoxLayout(rollPane);
  mid->setContentsMargins(0, 0, 0, 0);
  mid->setSpacing(0);
  auto *headerColumn = new QWidget(rollPane);
  headerColumn->setFixedWidth(kHeaderW);
  auto *headerColumnLayout = new QGridLayout(headerColumn);
  headerColumnLayout->setContentsMargins(0, 0, 0, 0);
  headerColumnLayout->setSpacing(0);
  auto *headerScroll = new QScrollArea(headerColumn);
  headerScroll->setObjectName(QStringLiteral("trackHeaderScroll"));
  headerScroll->setFrameShape(QFrame::NoFrame);
  headerScroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
  headerScroll->setWidgetResizable(true);
  // The roll owns keyboard editing (delete, copy/paste); the scroll areas
  // must not steal its focus on click (QAbstractScrollArea defaults to
  // StrongFocus, which broke shortcuts right after a track switch).
  headerScroll->setFocusPolicy(Qt::NoFocus);
  m_headers = new TrackHeaderPanel(this);
  headerScroll->setWidget(m_headers);
  headerColumnLayout->addWidget(headerScroll, 0, 0);

  mid->addWidget(headerColumn);
  // The note grid and raw event list share the roll's slot. Headers, ruler,
  // and automation lanes remain visible on either page.
  m_rollStack = new QStackedWidget(this);
  auto *rollPage = new QWidget(m_rollStack);
  auto *rollBox = new QHBoxLayout(rollPage);
  rollBox->setContentsMargins(0, 0, 0, 0);
  rollBox->setSpacing(0);
  m_roll = new PianoRoll(this);
  rollBox->addWidget(m_roll, 1);
  m_vbar = new QScrollBar(Qt::Vertical, this);
  ::layout::configureListPositionIndicator(*m_vbar);
  m_vbar->setSingleStep(kScrollUnitsPerDip);
  rollBox->addWidget(m_vbar);
  m_rollStack->addWidget(rollPage);
  m_events = new EventListView(this);
  m_rollStack->addWidget(m_events);
  mid->addWidget(m_rollStack, 1);

  m_lanes = new AutomationArea(this);

  m_velocityArea = new songview::VelocityArea(this);
  m_editorDrawer =
      new songview::EditorDrawer(rollPane, m_lanes, m_velocityArea, this);
  vbox->addWidget(m_editorDrawer, 1);
  themes::registerGridLineRepaintTarget(*m_ruler);
  themes::registerGridLineRepaintTarget(*m_roll);
  themes::registerGridLineRepaintTarget(*m_lanes);
  themes::registerGridLineRepaintTarget(*m_velocityArea);

  connect(m_editorDrawer, &songview::EditorDrawer::drawerStateChanged, this,
          [this] {
            m_velocityArea->cancelGesture();
            m_lanes->clearHoverFeedback();
            updateScrollbars();
            syncPlayheadOverlay();
          });
  connect(m_editorDrawer, &songview::EditorDrawer::announceRequested, this,
          [this](const QString &text) { announce(text); });

  connect(m_editorDrawer, &songview::EditorDrawer::contentFocusRequested, this,
          &SongView::focusContent);

  m_strip = new OtherStrip(this);
  vbox->addWidget(m_strip);
  PlayheadOverlay::Surfaces playheadSurfaces;
  playheadSurfaces.ruler = m_ruler;
  playheadSurfaces.rulerOrigin = kGutterW;
  playheadSurfaces.roll = m_roll;
  playheadSurfaces.rollOrigin = kKeyboardW;
  playheadSurfaces.lanes = m_editorDrawer->timelineSurface();
  playheadSurfaces.lanesOrigin = kGutterW;
  playheadSurfaces.strip = m_strip;
  playheadSurfaces.stripOrigin = kGutterW;
  m_playheadOverlay =
      new PlayheadOverlay(this, playheadSurfaces, playheadColor());

  m_hbar = new QScrollBar(Qt::Horizontal, this);
  m_hbar->setSingleStep(kScrollUnitsPerDip);
  auto *hbarRow = new QHBoxLayout;
  hbarRow->addSpacing(kGutterW);
  hbarRow->addWidget(m_hbar);
  vbox->addLayout(hbarRow);

  connect(m_hbar, &QScrollBar::valueChanged, this,
          [this](int v) { setHScroll(scrollDips(v)); });
  connect(m_vbar, &QScrollBar::valueChanged, this,
          [this](int v) { setVScroll(scrollDips(v)); });
}

void SongView::setSong(const MidiTimeline *timeline,
                       const LoadedVoiceGroup *voicegroup) {
  if (m_roll)
    m_roll->cancelBandGesture();
  clearProvisionalSelectionHighlight();
  m_timeline = timeline;
  m_voicegroup = voicegroup;
  m_model = timeline ? buildSongViewModel(*timeline) : SongViewModel();
  m_emptyLanes.clear();
  m_hiddenLanes.clear();
  m_selection.clear();
  m_timeSel = TimeSelection();
  m_clip = Clip();
  m_muteMask = 0;
  m_soloMask = 0;
  emit muteMaskChanged(0);
  emit soloMaskChanged(0);
  m_playheadTick = 0.0;
  m_editCursorTick = 0;
  m_playing = false;
  m_scrollX = 0.0;
  m_events->setPlayheadTick(-1.0, false); // another song's ticks are stale
  // Lane heights/value ranges and the snap grid are per-song view state;
  // back to defaults until a sidecar (applyViewState) says otherwise.
  m_lanes->setViewHeights(0);
  m_lanes->setRowDisplayStates({});
  m_gridFeel = GridFeel::Straight;
  m_gridMinDenom = 0;
  m_ruler->syncGridControls();
  if (m_velocityArea)
    m_velocityArea->cancelGesture();
  setDrawerPage(DrawerPage::Automations);
  setDrawerVisible(true);

  m_selectedTrack = 0;
  if (timeline) {
    for (int t = 0; t < 16; t++) {
      if (timeline->tracks[t].used) {
        m_selectedTrack = t;
        break;
      }
    }
  }
  m_trackSelMask = 1u << m_selectedTrack;
  refreshVelocityAxisContext();

  rebuildAfterSongChange();
}

void SongView::rebuildAfterSongChange() {
  double initialScrollY = 0.0;
  if (m_timeline) {
    // Default zoom: 32 px per beat, scrolled so the notes' pitch range
    // is centered in the roll.
    m_pxPerTick = 32.0 / double(m_timeline->ticksPerBeat);
    const int midKey = m_model.minNoteKey <= m_model.maxNoteKey
                           ? (m_model.minNoteKey + m_model.maxNoteKey) / 2
                           : 60;
    initialScrollY = std::max(0.0, (127 - midKey) * m_keyHeight -
                                       std::max(200, m_roll->height()) / 2.0);
  } else {
    m_pxPerTick = 1.0;
  }
  m_headers->rebuild();
  m_lanes->rebuildRows();
  updateScrollbars();
  setVScroll(initialScrollY);
  refreshTimelineViews();
}

void SongView::updateSong(const MidiTimeline *timeline) {
  if (m_velocityArea)
    m_velocityArea->cancelGesture();
  if (m_roll)
    m_roll->cancelBandGesture();
  m_timeline = timeline;
  m_model = timeline ? buildSongViewModel(*timeline) : SongViewModel();
  mergeEmptyLanes();

  if (timeline && !timeline->tracks[m_selectedTrack].used) {
    // The edited track disappeared (e.g. undo of its only events).
    m_selectedTrack = 0;
    for (int t = 0; t < 16; t++) {
      if (timeline->tracks[t].used) {
        m_selectedTrack = t;
        break;
      }
    }
  }

  // Keep only selection ids that still resolve to a note.
  std::vector<NoteId> keep;
  for (const NoteId &id : m_selection) {
    for (const ViewNote &note : m_model.notes) {
      if (note.track == m_selectedTrack && note.startTick == id.tick &&
          note.key == id.key) {
        keep.push_back(id);
        break;
      }
    }
  }
  m_selection = std::move(keep);

  refreshVelocityAxisContext();

  m_headers->rebuild();
  m_lanes->rebuildRows();
  updateScrollbars();
  refreshTimelineViews();
}

void SongView::setDocument(SongDocument *document) {
  if (m_document != document) {
    if (m_velocityArea)
      m_velocityArea->cancelGesture();
    if (m_document) {
      disconnect(m_document, &SongDocument::tracksRemapped, this, nullptr);
    }
    m_document = document;
    refreshVelocityAxisContext();
    if (document) {
      connect(document, &SongDocument::tracksRemapped, this,
              &SongView::onTracksRemapped);
    }
    m_selection.clear();
    m_headers->rebuild();   // the "+ Add track" button follows editability
    m_lanes->rebuildRows(); // the "+ Add lane" strip follows editability
    m_events->setDocument(document);
  }
}

bool SongView::eventListVisible() const {
  return m_rollStack->currentIndex() == 1;
}

void SongView::setEventListVisible(bool visible) {
  if (eventListVisible() == visible)
    return;
  if (visible && m_roll)
    m_roll->cancelBandGesture();
  m_rollStack->setCurrentIndex(visible ? 1 : 0);
  m_editorDrawer->setShortcutsEnabled(!visible);
  if (visible) {
    // The list skips refreshes while hidden; catch up when shown.
    m_events->refresh();
    m_events->syncTrackSelection();
  }
  focusContent();
  emit eventListVisibilityChanged(visible);
}

void SongView::focusContent() {
  if (eventListVisible())
    m_events->setFocus();
  else
    m_roll->setFocus();
}

void SongView::setDrawerPage(DrawerPage page) {
  m_editorDrawer->setDrawerPage(page);
}

SongView::DrawerPage SongView::drawerPage() const {
  return m_editorDrawer->drawerPage();
}

bool SongView::drawerVisible() const { return m_editorDrawer->drawerVisible(); }

void SongView::setDrawerVisible(bool visible) {
  m_editorDrawer->setDrawerVisible(visible);
}

bool SongView::isValidLaneIdentity(int track, int cc) {
  return track >= 0 && track < 16 &&
         ((cc >= 0 && cc <= 0x7F) || cc == LANE_CC_BEND);
}

void SongView::addEmptyLane(int track, uint8_t cc) {
  if (track < 0 || track > 15 || !m_timeline)
    return;
  const std::pair<int, uint8_t> key(track, cc);
  if (std::find(m_emptyLanes.begin(), m_emptyLanes.end(), key) ==
      m_emptyLanes.end())
    m_emptyLanes.push_back(key);
  mergeEmptyLanes();
  m_lanes->rebuildRows();
}

void SongView::removeEmptyLane(int track, uint8_t cc) {
  m_emptyLanes.erase(std::remove(m_emptyLanes.begin(), m_emptyLanes.end(),
                                 std::pair<int, uint8_t>(track, cc)),
                     m_emptyLanes.end());
  for (auto it = m_model.lanes.begin(); it != m_model.lanes.end(); ++it) {
    if (it->track == track && it->cc == cc && it->points.empty()) {
      m_model.lanes.erase(it);
      break;
    }
  }
  m_lanes->rebuildRows();
}
void SongView::hideLane(int track, uint8_t cc) {
  if (track < 0 || track > 15 || !m_timeline)
    return;
  const std::pair<int, uint8_t> laneIdentity(track, cc);
  if (laneHidden(track, cc) || !m_model.findLane(track, cc))
    return;
  m_hiddenLanes.push_back(laneIdentity);
  m_lanes->rebuildRows();
}

void SongView::showLane(int track, uint8_t cc) {
  const std::pair<int, uint8_t> laneIdentity(track, cc);
  const auto remainingEnd =
      std::remove(m_hiddenLanes.begin(), m_hiddenLanes.end(), laneIdentity);
  if (remainingEnd == m_hiddenLanes.end())
    return;
  m_hiddenLanes.erase(remainingEnd, m_hiddenLanes.end());
  if (!m_model.findLane(track, cc)) {
    addEmptyLane(track, cc);
    return;
  }
  m_lanes->rebuildRows();
}

bool SongView::laneHidden(int track, uint8_t cc) const {
  const std::pair<int, uint8_t> laneIdentity(track, cc);
  return std::find(m_hiddenLanes.begin(), m_hiddenLanes.end(), laneIdentity) !=
         m_hiddenLanes.end();
}

void SongView::setLaneDisplayRange(int track, uint8_t cc, int maxValue) {
  m_lanes->setLaneRange(track, cc, maxValue);
}

void SongView::mergeEmptyLanes() {
  bool added = false;
  for (const std::pair<int, uint8_t> &key : m_emptyLanes) {
    if (m_model.findLane(key.first, key.second))
      continue;
    AutoLane lane;
    lane.track = uint8_t(key.first);
    lane.cc = key.second;
    if (key.second == LANE_CC_BEND) {
      lane.lane = M4aLane::PitchBend;
      lane.name = m4aLaneName(M4aLane::PitchBend);
    } else {
      const M4aCcInfo info = m4aClassifyCc(key.second);
      lane.lane = info.lane;
      lane.name = QString::fromLatin1(info.display);
    }
    m_model.lanes.push_back(std::move(lane));
    added = true;
  }
  if (added) {
    // Same order buildSongViewModel establishes.
    std::stable_sort(m_model.lanes.begin(), m_model.lanes.end(),
                     [](const AutoLane &a, const AutoLane &b) {
                       if (a.track != b.track)
                         return a.track < b.track;
                       return a.cc < b.cc;
                     });
  }
}

SongView::ViewState SongView::viewState() const {
  ViewState state;
  if (!m_timeline)
    return state;
  state.valid = true;
  state.pxPerBeat = m_pxPerTick * double(m_timeline->ticksPerBeat);
  state.keyHeight = m_keyHeight;
  state.scrollPx = m_scrollX;
  state.scrollY = m_scrollY;
  state.selectedTrack = m_selectedTrack;
  state.editCursorTick = m_editCursorTick;
  state.laneHeight = m_lanes->laneHeight();
  state.rowStates = m_lanes->rowDisplayStates();
  state.drawerVisible = drawerVisible();
  state.drawerPage = drawerPage();
  const int drawerHeight = m_editorDrawer->drawerHeight();
  state.splitterSizes = {std::max(1, m_editorDrawer->height() - drawerHeight),
                         std::max(1, drawerHeight)};
  state.emptyLanes = m_emptyLanes;
  state.hiddenLanes = m_hiddenLanes;
  state.gridMinDenom = m_gridMinDenom;
  state.gridTriplet = m_gridFeel == GridFeel::Triplet;
  state.eventList = eventListVisible();
  return state;
}

void SongView::applyViewState(const ViewState &state) {
  if (!state.valid || !m_timeline)
    return;
  const double tpb = double(m_timeline->ticksPerBeat);
  m_pxPerTick = std::clamp(state.pxPerBeat, kMinPxPerBeat, kMaxPxPerBeat) / tpb;
  m_keyHeight = std::clamp(state.keyHeight, kMinKeyHeight, kMaxKeyHeight);
  setGridMinDenom(state.gridMinDenom); // setter validates the denominator
  setGridFeel(state.gridTriplet ? GridFeel::Triplet : GridFeel::Straight);
  m_editCursorTick =
      std::min<uint64_t>(state.editCursorTick, m_timeline->lengthTicks);
  for (const std::pair<int, uint8_t> &lane : state.emptyLanes)
    if (isValidLaneIdentity(lane.first, lane.second) &&
        std::find(m_emptyLanes.begin(), m_emptyLanes.end(), lane) ==
            m_emptyLanes.end())
      m_emptyLanes.push_back(lane);
  mergeEmptyLanes();
  m_hiddenLanes.clear();
  for (const std::pair<int, uint8_t> &hiddenLane : state.hiddenLanes)
    if (isValidLaneIdentity(hiddenLane.first, hiddenLane.second) &&
        !laneHidden(hiddenLane.first, hiddenLane.second))
      m_hiddenLanes.push_back(hiddenLane);
  m_lanes->setViewHeights(state.laneHeight);
  m_lanes->setRowDisplayStates(state.rowStates);
  if (state.selectedTrack >= 0 && state.selectedTrack < 16 &&
      m_timeline->tracks[state.selectedTrack].used)
    selectTrack(state.selectedTrack);
  setDrawerPage(state.drawerPage);
  if (state.splitterSizes.size() == 2 && state.splitterSizes[0] > 0 &&
      state.splitterSizes[1] > 0)
    m_editorDrawer->setDrawerHeight(state.splitterSizes[1]);
  setDrawerVisible(state.drawerVisible);
  m_lanes->rebuildRows();
  updateScrollbars();
  setHScroll(std::max(0.0, state.scrollPx));
  setVScroll(state.scrollY);
  setEventListVisible(state.eventList);
  refreshTimelineViews();
}

void SongView::setVoicegroup(const LoadedVoiceGroup *voicegroup) {
  m_voicegroup = voicegroup;
  refreshVelocityAxisContext();
  m_headers->rebuild();
  refreshTimelineViews();
}

void SongView::setGridFeel(GridFeel feel) {
  if (m_gridFeel == feel)
    return;
  m_gridFeel = feel;
  m_ruler->syncGridControls();
  m_lanes->clearHoverFeedback();
  refreshTimelineViews();
}

void SongView::setGridMinDenom(int denom) {
  if (denom != 4 && denom != 8 && denom != 16 && denom != 32)
    denom = 0;
  if (m_gridMinDenom == denom)
    return;
  m_gridMinDenom = denom;
  m_ruler->syncGridControls();
  m_lanes->clearHoverFeedback();
  refreshTimelineViews();
}

SongView::GridSeg SongView::gridSegAt(uint64_t tick) const {
  GridSeg seg;
  if (!m_timeline)
    return seg;
  const uint64_t tpb = std::max<uint32_t>(1, m_timeline->ticksPerBeat);
  seg.beatTicks = tpb;
  for (const TimeSigPoint &ts : m_timeline->timeSigs) { // tick-sorted
    if (ts.tick > tick) {
      seg.next = ts.tick;
      break;
    }
    // Same-tick duplicates overwrite: the last at a tick wins, matching
    // forEachGridLine.
    seg.start = ts.tick;
    seg.beatTicks = std::max<uint64_t>(1, (uint64_t(tpb) * 4) >>
                                              std::min<int>(ts.denomPow2, 63));
  }
  return seg;
}

uint64_t SongView::gridTicksAt(uint64_t tick) const {
  if (!m_timeline)
    return 24;
  return gridTicksIn(gridSegAt(tick));
}

uint64_t SongView::snapTicksAt(uint64_t tick) const {
  if (!m_timeline)
    return 24;
  return gridTicksIn(gridSegAt(tick), /*snap=*/true);
}

uint64_t SongView::gridTicksIn(const GridSeg &seg, bool snap) const {
  const uint64_t clock = m_document ? m_document->ticksPerClock() : 1;
  // Finest visible subdivision at least kAutoGridMinCellPx wide from the
  // feel's ladder
  // (divisions per beat), floored at the mid2agb clock grid and at the
  // user's minimum note value. The floor is one division per beat of the
  // governing signature (1/4 = the beat); triplet feel fits three notes
  // where straight fits two, so the same denominator allows 3/2 the
  // divisions.
  static constexpr uint64_t kStraight[] = {32, 16, 8, 4, 2, 1};
  static constexpr uint64_t kTriplet[] = {48, 24, 12, 6, 3, 1};
  const bool triplet = m_gridFeel == GridFeel::Triplet;
  const uint64_t maxDiv =
      m_gridMinDenom == 0 ? UINT64_MAX
                          : std::max<uint64_t>(1, uint64_t(m_gridMinDenom) *
                                                      (triplet ? 3 : 2) / 8);
  const double pxPerSegBeat = m_pxPerTick * double(seg.beatTicks);
  const uint64_t *ladder = triplet ? kTriplet : kStraight;
  constexpr int kSteps = 6;
  int step = kSteps - 1; // whole beats when even one-per-beat cells are
                         // too narrow (ladder[kSteps - 1] == 1)
  for (int i = 0; i < kSteps; i++) {
    if (ladder[i] > maxDiv)
      continue;
    if (pxPerSegBeat / double(ladder[i]) >= songview::kAutoGridMinCellPx) {
      step = i;
      break;
    }
  }
  // Snapping runs one ladder step finer than the drawn grid, so edits
  // aren't limited to visible lines. The minimum subdivision is a display
  // floor only — snapping steps past it too. gcd keeps the snap grid a
  // divisor of the drawn grid when a beat's ticks don't split evenly, so
  // every drawn line stays snappable.
  const uint64_t vis =
      std::max(std::max<uint64_t>(1, seg.beatTicks / ladder[step]), clock);
  if (!snap || step == 0)
    return vis;
  const uint64_t fine = std::max<uint64_t>(1, seg.beatTicks / ladder[step - 1]);
  return std::max(std::gcd(vis, fine), clock);
}

uint64_t SongView::fineGridTicks() const {
  return m_document ? std::max<uint32_t>(1, m_document->ticksPerClock())
                    : gridTicksAt(0);
}

uint64_t SongView::snapTick(double tick, bool fine) const {
  tick = std::max(0.0, tick);
  if (fine) {
    // The clock grid is the document's absolute resolution; it does not
    // restart at time-signature changes.
    const double g = double(fineGridTicks());
    return uint64_t(std::round(tick / g) * g);
  }
  const GridSeg seg = gridSegAt(uint64_t(tick));
  const uint64_t g = std::max<uint64_t>(1, gridTicksIn(seg, /*snap=*/true));
  const uint64_t k = uint64_t((tick - double(seg.start)) / double(g));
  const uint64_t lo = seg.start + k * g;
  // The next signature's tick is itself a grid position (the grid
  // restarts there), so the upper candidate never crosses it.
  const uint64_t hi = std::min(lo + g, seg.next);
  return tick - double(lo) <= double(hi) - tick ? lo : hi;
}

uint64_t SongView::snapTickDown(double tick) const {
  tick = std::max(0.0, tick);
  const GridSeg seg = gridSegAt(uint64_t(tick));
  const uint64_t g = std::max<uint64_t>(1, gridTicksIn(seg, /*snap=*/true));
  return seg.start + uint64_t((tick - double(seg.start)) / double(g)) * g;
}

uint64_t SongView::snapTickUp(double tick) const {
  tick = std::max(0.0, tick);
  const GridSeg seg = gridSegAt(uint64_t(tick));
  const uint64_t g = std::max<uint64_t>(1, gridTicksIn(seg, /*snap=*/true));
  const uint64_t lo =
      seg.start + uint64_t((tick - double(seg.start)) / double(g)) * g;
  if (double(lo) >= tick)
    return lo;
  // The next signature's tick is itself a grid position, so the upper
  // candidate never crosses it.
  return std::min(lo + g, seg.next);
}

bool SongView::isSelected(const ViewNote &note) const {
  if (note.track != m_selectedTrack)
    return false;
  const NoteId id{note.startTick, note.key};
  return std::find(m_selection.begin(), m_selection.end(), id) !=
         m_selection.end();
}
bool SongView::isSelectionHighlighted(const ViewNote &note) const {
  if (note.track != m_selectedTrack)
    return false;
  if (!m_provisionalSelectionHighlight)
    return isSelected(note);
  const NoteId id{note.startTick, note.key};
  return std::find(m_provisionalSelectionHighlight->begin(),
                   m_provisionalSelectionHighlight->end(),
                   id) != m_provisionalSelectionHighlight->end();
}

void SongView::setProvisionalSelectionHighlight(std::vector<NoteId> ids) {
  m_provisionalSelectionHighlight = std::move(ids);
  updateNoteViews();
}

void SongView::clearProvisionalSelectionHighlight() {
  if (!m_provisionalSelectionHighlight)
    return;
  m_provisionalSelectionHighlight.reset();
  updateNoteViews();
}


void SongView::setSelection(std::vector<NoteId> ids) {
  m_selection = std::move(ids);
  // The two selection kinds are mutually exclusive, so Ctrl+C is never
  // ambiguous.
  if (!m_selection.empty() && m_timeSel.active())
    clearTimeSelection();
  m_roll->update();
  if (m_velocityArea)
    m_velocityArea->update();
}

void SongView::clearSelection() {
  if (!m_selection.empty()) {
    m_selection.clear();
    m_roll->update();
    if (m_velocityArea)
      m_velocityArea->update();
  }
}

void SongView::setTimeSelection(const TimeSelection &sel) {
  m_timeSel = sel;
  if (m_timeSel.active() && !m_selection.empty())
    m_selection.clear();
  refreshTimelineViews();
}

void SongView::clearTimeSelection() {
  m_timeSel = TimeSelection();
  refreshTimelineViews();
}

bool SongView::timeSelectionCoversTrack(int track) const {
  if (!m_timeSel.active() || track < 0 || track > 15)
    return false;
  if (m_timeSel.scope == TimeSelection::Lanes)
    return false;
  // Track scope is live: it always mirrors the header selection.
  return trackSelectionMask() & (1u << track);
}

bool SongView::timeSelectionCoversRow(int track, uint8_t cc) const {
  if (!m_timeSel.active())
    return false;
  if (m_timeSel.scope == TimeSelection::Lanes)
    return std::find(m_timeSel.lanes.begin(), m_timeSel.lanes.end(),
                     std::pair<int, uint8_t>(track, cc)) !=
           m_timeSel.lanes.end();
  // Track scopes cover the track's CC/voice rows, never the global tempo.
  if (cc == DOC_CC_TEMPO)
    return false;
  return timeSelectionCoversTrack(track);
}

void SongView::announceTimeSelection() {
  if (!m_timeSel.active() || !m_timeline)
    return;
  const double beats = double(m_timeSel.endTick - m_timeSel.startTick) /
                       double(std::max<uint32_t>(1, m_timeline->ticksPerBeat));
  QString scope;
  if (m_timeSel.scope == TimeSelection::Lanes) {
    scope = tr("%n lane(s)", nullptr, int(m_timeSel.lanes.size()));
  } else {
    const uint32_t mask = trackSelectionMask();
    int n = 0;
    for (int t = 0; t < 16; t++)
      n += (mask >> t) & 1;
    scope = tr("%n track(s)", nullptr, n);
  }
  emit statusMessage(tr("Time selection: %1 beats · %2 · Ctrl+C/X copies, "
                        "Del clears, Ctrl+V pastes at the edit cursor")
                         .arg(beats, 0, 'g', 4)
                         .arg(scope));
}

std::vector<int> SongView::timeSelectionTracks() const {
  std::vector<int> tracks;
  if (!m_timeline || !m_document)
    return tracks;
  const uint32_t mask = trackSelectionMask();
  for (int t = 0; t < 16; t++) {
    if (!m_timeline->tracks[t].used || !(mask & (1u << t)))
      continue;
    if (m_document->smfTrackFor(t) < 0)
      continue;
    tracks.push_back(t);
  }
  return tracks;
}

std::vector<uint8_t> SongView::trackCcs(int track) const {
  std::vector<uint8_t> ccs;
  for (const AutoLane &lane : m_model.lanes)
    if (lane.track == track)
      ccs.push_back(lane.cc); // LANE_CC_BEND == DOC_CC_BEND
  ccs.push_back(DOC_CC_VOICE);
  return ccs;
}

void SongView::copyTimeSelection() {
  if (!m_document || !m_timeSel.active())
    return;
  const uint64_t s = m_timeSel.startTick;
  const uint64_t e = m_timeSel.endTick;
  Clip clip;
  clip.span = e - s;
  int noteCount = 0;
  int pointCount = 0;
  const auto copyLanePoints = [&](int track, uint8_t cc) {
    ClipLane lane{track, cc, {}};
    const int query = track < 0 ? m_selectedTrack : track;
    for (const DocLanePoint &pt : m_document->lanePoints(query, cc)) {
      if (pt.tick >= s && pt.tick < e)
        lane.points.push_back({uint32_t(pt.tick - s), pt.value});
    }
    pointCount += int(lane.points.size());
    // Empty segments are kept: they carry "this span is silent" so paste
    // clears the destination range.
    clip.lanes.push_back(std::move(lane));
  };
  if (m_timeSel.scope == TimeSelection::Lanes) {
    for (const std::pair<int, uint8_t> &id : m_timeSel.lanes)
      copyLanePoints(id.first, id.second);
  } else {
    for (int t : timeSelectionTracks()) {
      ClipTrack ct{t, {}};
      for (const DocNote &note : m_document->notesForTrack(t)) {
        if (note.tick < s || note.tick >= e)
          continue;
        ct.notes.push_back(
            {uint32_t(note.tick - s), note.key,
             note.duration ? note.duration : uint32_t(gridTicksAt(note.tick)),
             note.velocity});
      }
      noteCount += int(ct.notes.size());
      clip.tracks.push_back(std::move(ct));
      for (uint8_t cc : trackCcs(t))
        copyLanePoints(t, cc);
    }
  }
  m_clip = std::move(clip);
  announce(tr("Copied range: %1 note(s), %2 automation point(s)")
               .arg(noteCount)
               .arg(pointCount));
}

void SongView::deleteTimeSelection() {
  if (!m_document || !m_timeSel.active())
    return;
  const uint64_t s = m_timeSel.startTick;
  const uint64_t e = m_timeSel.endTick;
  SongDocument::RangeEdit edit;
  const auto removeLanePoints = [&](int track, uint8_t cc) {
    const int query = track < 0 ? m_selectedTrack : track;
    for (const DocLanePoint &pt : m_document->lanePoints(query, cc)) {
      if (pt.tick >= s && pt.tick < e)
        edit.removePoints.push_back(pt);
    }
  };
  if (m_timeSel.scope == TimeSelection::Lanes) {
    for (const std::pair<int, uint8_t> &id : m_timeSel.lanes)
      removeLanePoints(id.first, id.second);
  } else {
    for (int t : timeSelectionTracks()) {
      for (const DocNote &note : m_document->notesForTrack(t)) {
        if (note.tick >= s && note.tick < e)
          edit.removeNotes.push_back(note);
      }
      for (uint8_t cc : trackCcs(t))
        removeLanePoints(t, cc);
    }
  }
  if (edit.empty()) {
    announce(tr("Nothing to delete in the time selection"));
    return;
  }
  const int notes = int(edit.removeNotes.size());
  const int points = int(edit.removePoints.size());
  m_document->applyRangeEdit(tr("delete range"), edit);
  announce(tr("Deleted range: %1 note(s), %2 automation point(s)")
               .arg(notes)
               .arg(points));
}

void SongView::transposeTimeSelection(int dKey) {
  if (!m_document || !m_timeSel.active() || dKey == 0 ||
      m_timeSel.scope == TimeSelection::Lanes)
    return;
  const uint64_t s = m_timeSel.startTick;
  const uint64_t e = m_timeSel.endTick;
  std::vector<DocNote> notes;
  for (int t : timeSelectionTracks()) {
    for (const DocNote &note : m_document->notesForTrack(t)) {
      if (note.tick >= s && note.tick < e)
        notes.push_back(note);
    }
  }
  if (notes.empty()) {
    announce(tr("No notes in the time selection"));
    return;
  }
  for (const DocNote &note : notes) {
    const int key = int(note.key) + dKey;
    if (key < 0 || key > 127) {
      announce(tr("Transpose out of range"));
      return;
    }
  }
  m_document->moveNotes(notes, 0, dKey, /*mergeable=*/true);
  // Keep the moved notes in sight: the row the move headed toward
  // scrolls into view just enough (no re-centering).
  int edge = int(notes.front().key) + dKey;
  for (const DocNote &note : notes) {
    const int key = int(note.key) + dKey;
    edge = dKey > 0 ? std::max(edge, key) : std::min(edge, key);
  }
  ensureKeyVisible(edge);
  announce(tr("Transposed %n note(s) by %1", nullptr, int(notes.size()))
               .arg(dKey > 0 ? QStringLiteral("+%1").arg(dKey)
                             : QString::number(dKey)));
}

void SongView::nudgeTimeSelection(bool right) {
  if (!m_document || !m_timeSel.active())
    return;
  const uint64_t s = m_timeSel.startTick;
  const uint64_t e = m_timeSel.endTick;
  const uint64_t snapped =
      drawnGridTick(this, double(s) + (right ? 1.0 : -1.0), right);
  const int64_t dTick = int64_t(snapped) - int64_t(s);
  if (dTick == 0)
    return;
  std::vector<DocNote> notes;
  std::vector<DocLanePoint> points;
  const auto gatherLanePoints = [&](int track, uint8_t cc) {
    const int query = track < 0 ? m_selectedTrack : track;
    for (const DocLanePoint &pt : m_document->lanePoints(query, cc)) {
      if (pt.tick >= s && pt.tick < e)
        points.push_back(pt);
    }
  };
  if (m_timeSel.scope == TimeSelection::Lanes) {
    for (const std::pair<int, uint8_t> &id : m_timeSel.lanes)
      gatherLanePoints(id.first, id.second);
  } else {
    for (int t : timeSelectionTracks()) {
      for (const DocNote &note : m_document->notesForTrack(t)) {
        if (note.tick >= s && note.tick < e)
          notes.push_back(note);
      }
      for (uint8_t cc : trackCcs(t))
        gatherLanePoints(t, cc);
    }
  }
  m_document->moveRange(notes, points, dTick);
  // The band follows even over empty content, so repeated nudges keep
  // aiming at the same region.
  TimeSelection moved = m_timeSel;
  moved.startTick = uint64_t(int64_t(s) + dTick);
  moved.endTick = uint64_t(int64_t(e) + dTick);
  setTimeSelection(moved);
  ensureRangeVisible(moved.startTick, moved.endTick, right);
}

void SongView::removeTimeSelectionContents() {
  if (!m_document || !m_timeline || !m_timeSel.active())
    return;
  const uint64_t s = m_timeSel.startTick;
  const uint64_t e = m_timeSel.endTick;
  SongDocument::RippleScope scope;
  QString scopeText;
  if (m_timeSel.scope == TimeSelection::Lanes) {
    scope.lanes = m_timeSel.lanes;
    scopeText = tr("%n lane(s)", nullptr, int(scope.lanes.size()));
  } else {
    scope.tracks = timeSelectionTracks();
    if (scope.tracks.empty())
      return;
    int used = 0;
    for (int t = 0; t < 16; t++)
      used += m_timeline->tracks[t].used ? 1 : 0;
    scope.wholeSong = int(scope.tracks.size()) == used;
    scopeText = scope.wholeSong
                    ? tr("all tracks")
                    : tr("%n track(s)", nullptr, int(scope.tracks.size()));
  }
  if (!m_document->removeTimeRange(s, e, scope)) {
    announce(tr("Nothing to remove in the time selection"));
    return;
  }
  // The span is gone and later content now sits under where the selection
  // was; clear it and park the edit cursor at the seam.
  clearTimeSelection();
  commitEditCursor(s);
  const double beats =
      double(e - s) / double(std::max<uint32_t>(1, m_timeline->ticksPerBeat));
  announce(tr("Removed %1 beats on %2 — later events shifted left")
               .arg(beats, 0, 'g', 4)
               .arg(scopeText));
}

void SongView::pasteRangeAtEditCursor() {
  if (!m_document || m_clip.span == 0 || m_clip.empty())
    return;
  const uint64_t s = snapTick(double(m_editCursorTick));
  const uint64_t e = s + m_clip.span;

  // A clip whose content came from one track retargets to the selected
  // track (cross-track copy); multi-track clips paste back in place.
  int sole = -2;
  bool multi = false;
  const auto consider = [&](int track) {
    if (track < 0)
      return; // tempo is global
    if (sole == -2)
      sole = track;
    else if (sole != track)
      multi = true;
  };
  for (const ClipTrack &ct : m_clip.tracks)
    consider(ct.track);
  for (const ClipLane &cl : m_clip.lanes)
    consider(cl.track);
  const auto mapTrack = [&](int track) {
    return track < 0 ? -1 : (multi ? track : m_selectedTrack);
  };

  SongDocument::RangeEdit edit;
  for (const ClipTrack &ct : m_clip.tracks) {
    const int t = mapTrack(ct.track);
    if (t < 0 || m_document->smfTrackFor(t) < 0)
      continue;
    // Replace: whatever notes start inside the destination span go away.
    for (const DocNote &note : m_document->notesForTrack(t)) {
      if (note.tick >= s && note.tick < e)
        edit.removeNotes.push_back(note);
    }
    if (!ct.notes.empty()) {
      SongDocument::RangeEdit::TrackNotes tn{t, {}};
      for (const ClipNote &cn : ct.notes)
        tn.notes.push_back({s + cn.relTick, cn.key, cn.duration, cn.velocity});
      edit.addNotes.push_back(std::move(tn));
    }
  }
  for (const ClipLane &cl : m_clip.lanes) {
    const int t = mapTrack(cl.track);
    if (t >= 0 && m_document->smfTrackFor(t) < 0)
      continue;
    const int query = t < 0 ? m_selectedTrack : t;
    for (const DocLanePoint &pt : m_document->lanePoints(query, cl.cc)) {
      if (pt.tick >= s && pt.tick < e)
        edit.removePoints.push_back(pt);
    }
    if (!cl.points.empty()) {
      SongDocument::RangeEdit::LaneWrite lw{t, cl.cc, {}};
      for (const std::pair<uint32_t, int> &pv : cl.points)
        lw.points.push_back({s + pv.first, pv.second});
      edit.addPoints.push_back(std::move(lw));
    }
  }
  m_document->applyRangeEdit(tr("paste range"), edit);

  // Set up for tiling: the edit cursor advances to the end of the pasted
  // span so repeated Ctrl+V lays copies back-to-back, and the selection is
  // cleared so its band doesn't sit in the way of the next ruler click.
  clearTimeSelection();
  commitEditCursor(e);
  // Anchor on the start of the pasted span, not the advanced cursor:
  // seeing the content that just landed is what confirms the paste.
  ensureTickVisible(s);
  announce(tr(
      "Pasted range · edit cursor moved to its end — paste again to repeat"));
}

// Plain note clips are additive and tick-relative to the first selected note.
// The selection-facing entry points share this writer so cut never resolves
// the same document notes twice.
void SongView::writeNoteClipboard(const std::vector<DocNote> &notes) {
  uint64_t base = UINT64_MAX;
  for (const DocNote &note : notes)
    base = std::min(base, note.tick);
  Clip clip;
  ClipTrack track{m_selectedTrack, {}};
  for (const DocNote &note : notes)
    track.notes.push_back(
        {uint32_t(note.tick - base), note.key,
         note.duration ? note.duration : uint32_t(gridTicksAt(note.tick)),
         note.velocity});
  clip.tracks.push_back(std::move(track));
  m_clip = std::move(clip);
  announce(tr("Copied %n note(s)", nullptr, int(notes.size())));
}

void SongView::copyNoteSelection() {
  const std::vector<DocNote> notes = selectedDocumentNotes(*this);
  if (!notes.empty())
    writeNoteClipboard(notes);
}

void SongView::cutNoteSelection() {
  const std::vector<DocNote> notes = selectedDocumentNotes(*this);
  if (notes.empty())
    return;
  writeNoteClipboard(notes);
  m_document->deleteNotes(notes);
  clearSelection();
}

void SongView::deleteNoteSelection() {
  const std::vector<DocNote> notes = selectedDocumentNotes(*this);
  if (notes.empty())
    return;
  m_document->deleteNotes(notes);
  clearSelection();
}

// Paste a plain note clip onto the selected track at the snapped edit cursor.
// Range clips retain their replace semantics in pasteRangeAtEditCursor.
void SongView::pasteNotesAtEditCursor() {
  if (!m_document || m_clip.span != 0 || m_clip.tracks.empty() ||
      m_clip.tracks.front().notes.empty())
    return;
  const uint64_t base = snapTick(double(m_editCursorTick));
  std::vector<SongDocument::NewNote> notes;
  std::vector<NoteId> ids;
  uint64_t end = base;
  for (const ClipNote &note : m_clip.tracks.front().notes) {
    const uint64_t tick = base + note.relTick;
    notes.push_back({tick, note.key, note.duration, note.velocity});
    ids.push_back({uint32_t(tick), note.key});
    end = std::max(end, tick + note.duration);
  }
  m_document->addNotes(m_selectedTrack, notes);
  setSelection(std::move(ids));
  commitEditCursor(end);
  ensureTickVisible(base);
  announce(tr("Pasted %n note(s)", nullptr, int(notes.size())));
}

void SongView::selectAllNotes() {
  std::vector<NoteId> ids;
  for (const ViewNote &note : m_model.notes) {
    if (note.track == m_selectedTrack)
      ids.push_back({note.startTick, note.key});
  }
  setSelection(std::move(ids));
}

// Transposes keep intervals: if any selected note would leave the MIDI key
// range, the whole move is a no-op. The first moved note auditions until the
// focused editor surface receives a real key release.
void SongView::transposeNoteSelection(int dKey) {
  const std::vector<DocNote> notes = selectedDocumentNotes(*this);
  if (notes.empty())
    return;
  for (const DocNote &note : notes) {
    const int key = int(note.key) + dKey;
    if (key < 0 || key > 127)
      return;
  }
  m_document->moveNotes(notes, 0, dKey, /*mergeable=*/true);
  std::vector<NoteId> ids;
  for (const DocNote &note : notes)
    ids.push_back({uint32_t(note.tick), uint8_t(int(note.key) + dKey)});
  setSelection(std::move(ids));
  int edge = int(notes.front().key) + dKey;
  for (const DocNote &note : notes) {
    const int key = int(note.key) + dKey;
    edge = dKey > 0 ? std::max(edge, key) : std::min(edge, key);
  }
  ensureKeyVisible(edge);
  const int key = int(notes.front().key) + dKey;
  m_editKeyAudition = EditKeyAudition{m_selectedTrack, key};
  emit auditionNote(m_selectedTrack, key, notes.front().velocity);
  if (m_roll)
    m_roll->update();
}

// Move the earliest selected note to the adjacent drawn-grid line and keep
// every selected note's offset from it.
void SongView::nudgeNoteSelection(bool right) {
  const std::vector<DocNote> notes = selectedDocumentNotes(*this);
  if (notes.empty())
    return;
  uint64_t anchor = UINT64_MAX;
  for (const DocNote &note : notes)
    anchor = std::min(anchor, note.tick);
  const uint64_t snapped =
      drawnGridTick(this, double(anchor) + (right ? 1.0 : -1.0), right);
  const int64_t dTick = int64_t(snapped) - int64_t(anchor);
  if (dTick == 0)
    return;
  m_document->moveNotes(notes, dTick, 0, /*mergeable=*/true);
  std::vector<NoteId> ids;
  for (const DocNote &note : notes)
    ids.push_back({uint32_t(int64_t(note.tick) + dTick), note.key});
  setSelection(std::move(ids));
  uint64_t lo = UINT64_MAX;
  uint64_t hi = 0;
  for (const DocNote &note : notes) {
    const uint64_t tick = uint64_t(int64_t(note.tick) + dTick);
    lo = std::min(lo, tick);
    hi = std::max(hi, tick + note.duration);
  }
  ensureRangeVisible(lo, hi, right);
}

void SongView::audition(int track, int key, int velocity) {
  const bool replacedEditAudition = m_editKeyAudition.has_value();
  m_editKeyAudition.reset();
  emit auditionNote(track, key, velocity);
  if (replacedEditAudition && m_roll)
    m_roll->update();
}

int SongView::editKeyAuditionKey() const {
  return m_editKeyAudition ? m_editKeyAudition->key : -1;
}

void SongView::releaseEditKeyAudition() {
  if (!m_editKeyAudition)
    return;
  const EditKeyAudition active = *m_editKeyAudition;
  m_editKeyAudition.reset();
  emit auditionNote(active.track, active.key, 0);
  if (m_roll)
    m_roll->update();
}

// Maps the four transpose commands to their semitone step, 0 when the event
// matches none. Shared by the note-selection and time-selection key paths so
// a rebinding changes both at once.
int SongView::transposeStepFor(const QKeyEvent *event) const {
  const auto &keys = keymap::Registry::instance();
  if (keys.matches(event, QStringLiteral("roll.transpose_up")))
    return 1;
  if (keys.matches(event, QStringLiteral("roll.transpose_down")))
    return -1;
  if (keys.matches(event, QStringLiteral("roll.transpose_up_octave")))
    return 12;
  if (keys.matches(event, QStringLiteral("roll.transpose_down_octave")))
    return -12;
  return 0;
}

bool SongView::handleEditKey(QKeyEvent *event) {
  // Window shortcuts normally consume plain A/V. This fallback keeps the
  // same behavior in embedded or inactive editor surfaces.
  if ((event->key() == Qt::Key_A || event->key() == Qt::Key_V) &&
      event->modifiers() == Qt::NoModifier) {
    if (!event->isAutoRepeat()) {
      m_editorDrawer->toggleDrawerPage(event->key() == Qt::Key_A
                                           ? DrawerPage::Automations
                                           : DrawerPage::Velocity);
    }
    event->accept();
    return true;
  }
  if (!m_document)
    return false;
  const auto &keys = keymap::Registry::instance();
  const bool timeSelection = m_timeSel.active();
  if (timeSelection && keys.matches(event, QStringLiteral("roll.copy"))) {
    copyTimeSelection();
    event->accept();
    return true;
  }
  if (timeSelection && keys.matches(event, QStringLiteral("roll.cut"))) {
    copyTimeSelection();
    deleteTimeSelection();
    event->accept();
    return true;
  }
  if (timeSelection && keys.matches(event, QStringLiteral("roll.delete"))) {
    deleteTimeSelection();
    event->accept();
    return true;
  }
  if (timeSelection) {
    const int transpose = transposeStepFor(event);
    if (transpose != 0) {
      transposeTimeSelection(transpose);
      event->accept();
      return true;
    }
  }
  if (timeSelection &&
      (keys.matches(event, QStringLiteral("roll.nudge_left")) ||
       keys.matches(event, QStringLiteral("roll.nudge_right")))) {
    nudgeTimeSelection(keys.matches(event, QStringLiteral("roll.nudge_right")));
    event->accept();
    return true;
  }
  if (keys.matches(event, QStringLiteral("roll.paste"))) {
    if (m_clip.span > 0 && !m_clip.empty())
      pasteRangeAtEditCursor();
    else
      pasteNotesAtEditCursor();
    event->accept();
    return true;
  }
  const bool cut = keys.matches(event, QStringLiteral("roll.cut"));
  if (cut || keys.matches(event, QStringLiteral("roll.copy"))) {
    if (cut)
      cutNoteSelection();
    else
      copyNoteSelection();
    event->accept();
    return true;
  }
  if (keys.matches(event, QStringLiteral("roll.select_all"))) {
    selectAllNotes();
    event->accept();
    return true;
  }
  if (keys.matches(event, QStringLiteral("roll.delete"))) {
    deleteNoteSelection();
    event->accept();
    return true;
  }
  const int transpose = transposeStepFor(event);
  if (transpose != 0) {
    transposeNoteSelection(transpose);
    event->accept();
    return true;
  }
  if (keys.matches(event, QStringLiteral("roll.nudge_left")) ||
      keys.matches(event, QStringLiteral("roll.nudge_right"))) {
    nudgeNoteSelection(keys.matches(event, QStringLiteral("roll.nudge_right")));
    event->accept();
    return true;
  }
  return false;
}

void SongView::showTimeSelectionMenu(const QPoint &globalPos) {
  if (!m_document || !m_timeSel.active())
    return;
  QMenu menu(this);
  // Display-only hints mirroring the keymap, like the note context menu.
  const auto &keys = keymap::Registry::instance();
  QAction *copy = menu.addAction(tr("Copy range"));
  copy->setShortcut(keys.bindings(QStringLiteral("roll.copy")).value(0));
  QAction *cut = menu.addAction(tr("Cut range"));
  cut->setShortcut(keys.bindings(QStringLiteral("roll.cut")).value(0));
  QAction *del = menu.addAction(tr("Delete range"));
  QAction *removeContents = menu.addAction(tr("Remove contents (shift left)"));
  QAction *paste = menu.addAction(tr("Paste at edit cursor"));
  paste->setShortcut(keys.bindings(QStringLiteral("roll.paste")).value(0));
  paste->setEnabled(m_clip.span > 0 && !m_clip.empty());
  menu.addSeparator();
  QAction *clear = menu.addAction(tr("Clear selection"));
  QAction *chosen = menu.exec(globalPos);
  if (chosen == copy) {
    copyTimeSelection();
  } else if (chosen == cut) {
    copyTimeSelection();
    deleteTimeSelection();
  } else if (chosen == del) {
    deleteTimeSelection();
  } else if (chosen == removeContents) {
    removeTimeSelectionContents();
  } else if (chosen == paste) {
    pasteRangeAtEditCursor();
  } else if (chosen == clear) {
    clearTimeSelection();
  }
}

void SongView::announceNote(const ViewNote &note) {
  if (!m_timeline)
    return;
  const bool ext = m_document && m_document->cfg().extendedClocks;
  const bool exact = m_document && m_document->cfg().exactGate;
  const int64_t ticks = int64_t(note.endTick) - int64_t(note.startTick);
  const int vel = note.velocity;
  const int effVel = mid2agbEffectiveVelocity(note.velocity);
  const int64_t effClocks =
      mid2agbEffectiveDuration(ticks, m_timeline->ticksPerBeat, ext, exact);
  const QString kName = keyName(note.key);

  emit noteAnnounced(kName, vel, effVel, ticks, effClocks);
}

void SongView::auditionTimed(int track, int key, int velocity,
                             uint64_t startTick, uint64_t endTick) {
  if (!m_timeline || endTick <= startTick)
    return;
  uint64_t dur =
      m_timeline->sampleForTick(endTick) - m_timeline->sampleForTick(startTick);
  // Safety cap: an unterminated note's span runs to the end of the song,
  // which is not a useful audition length.
  const uint64_t cap = uint64_t(m_timeline->sampleRate * 10.0);
  if (cap > 0)
    dur = std::min(dur, cap);
  if (dur > 0)
    emit auditionNoteTimed(track, key, velocity,
                           quint32(std::min<uint64_t>(dur, UINT32_MAX)));
}

void SongView::setPlayheadSample(uint64_t samplePos, bool playing) {
  if (!m_timeline)
    return;
  m_playheadTick = m_timeline->tickForSample(samplePos);
  m_playing = playing;
  refreshVelocityAxisContext();
  // Follow the playhead — but not while the user is mid-gesture (panning,
  // dragging notes or selections, sweeping automation): yanking the view
  // out from under a held mouse button is disorienting.
  if (playing && !userGestureActive()) {
    const qreal px = contentX(m_playheadTick);
    const qreal vw = viewportWidth();
    if (px < 0.0 || px > vw * 85.0 / 100.0)
      setHScroll(m_playheadTick * m_pxPerTick - vw / 10.0);
  }
  m_events->setPlayheadTick(m_playheadTick, playing);
  m_headers->syncVoices();
  syncPlayheadOverlay();
}

bool SongView::userGestureActive() const {
  return (m_ruler && m_ruler->gestureActive()) ||
         (m_roll && m_roll->gestureActive()) ||
         (m_lanes && m_lanes->gestureActive()) ||
         (m_velocityArea && m_velocityArea->gestureActive());
}

void SongView::syncPlayheadOverlay() {
  if (m_playheadOverlay) {
    m_playheadOverlay->setPlayhead(contentX(m_playheadTick),
                                   m_timeline != nullptr, m_playing);
  }
}

void SongView::setEditCursorTick(uint64_t tick) {
  if (m_editCursorTick == tick)
    return;
  m_editCursorTick = tick;
  refreshVelocityAxisContext();
  m_headers->syncVoices();
  refreshTimelineViews();
}

void SongView::commitEditCursor(uint64_t tick) {
  setEditCursorTick(tick);
  emit editCursorMoved(tick);
}

void SongView::goToStart() {
  setHScroll(0);
  commitEditCursor(0);
}

qreal SongView::displayX(double tick, qreal origin, qreal dpr) const {
  const qreal widgetX = origin + contentX(tick);
  return dpr > 0.0 ? std::round(widgetX * dpr) / dpr : widgetX;
}

double SongView::pxPerBeat() const {
  return m_timeline ? m_pxPerTick * m_timeline->ticksPerBeat
                    : m_pxPerTick * 24.0;
}

void SongView::selectTrack(int track) {
  if (track == m_selectedTrack || track < 0 || track > 15)
    return;
  if (m_roll)
    m_roll->cancelBandGesture();
  if (m_velocityArea)
    m_velocityArea->cancelGesture();
  m_selectedTrack = track;
  refreshVelocityAxisContext();
  // Programmatic selection collapses the multi-track scope;
  // trackHeaderClicked restores it for modifier clicks.
  m_trackSelMask = 1u << track;
  m_selection.clear();
  // A track-scoped time selection would keep rendering only in the ruler
  // once the shown track leaves its scope; drop it on any track switch.
  clearTimeSelection();
  m_headers->syncSelection();
  m_lanes->rebuildRows();
  // Switching tracks readies the roll for keyboard editing (e.g. copy on
  // one track, click another's header, paste), wherever focus was.
  m_roll->setFocus();
  updateNoteViews();
  emit selectedTrackChanged(track);
}

bool SongView::revealNote(int track, uint8_t key, uint64_t tick) {
  if (track < 0 || track > 15)
    return false;
  selectTrack(track);
  // Notes are sorted by startTick, so the last match is the note that was
  // sounding (or had just finished fading) at the event's position.
  const ViewNote *found = nullptr;
  for (const ViewNote &note : m_model.notes) {
    if (note.startTick > tick)
      break;
    if (note.track == track && note.key == key)
      found = &note;
  }
  if (!found)
    return false;
  setSelection({NoteId{found->startTick, found->key}});
  ensureKeyVisible(key);
  return true;
}

uint32_t SongView::trackSelectionMask() const {
  uint32_t used = 0;
  if (m_timeline) {
    for (int t = 0; t < 16; t++)
      if (m_timeline->tracks[t].used)
        used |= 1u << t;
  }
  const uint32_t mask = (m_trackSelMask | (1u << m_selectedTrack)) & used;
  return mask ? mask : (1u << m_selectedTrack);
}

void SongView::trackHeaderClicked(int track, Qt::KeyboardModifiers modifiers) {
  if (track < 0 || track > 15)
    return;
  if (modifiers & Qt::ControlModifier) {
    uint32_t mask = trackSelectionMask() ^ (1u << track);
    if (mask == 0)
      return; // the scope can't go empty
    if (!(mask & (1u << m_selectedTrack))) {
      // The primary track was toggled out; hand primary to the lowest
      // remaining scoped track. This is a scope adjustment, not a
      // track switch, so the time selection survives (selectTrack
      // clears it and collapses the mask — restore both after).
      int next = 0;
      while (!(mask & (1u << next)))
        next++;
      const TimeSelection keep = m_timeSel;
      selectTrack(next);
      m_timeSel = keep;
    }
    m_trackSelMask = mask;
  } else if (modifiers & Qt::ShiftModifier) {
    const int lo = std::min(track, m_selectedTrack);
    const int hi = std::max(track, m_selectedTrack);
    uint32_t mask = 0;
    for (int t = lo; t <= hi; t++) {
      if (m_timeline && m_timeline->tracks[t].used)
        mask |= 1u << t;
    }
    m_trackSelMask = mask | (1u << m_selectedTrack);
  } else {
    selectTrack(track);
    clearSelection();
    m_trackSelMask = 1u << track; // collapse even when already primary
  }
  m_headers->syncSelection();
  // The time selection's track scope is live; repaint its bands.
  refreshTimelineViews();
}

void SongView::setTrackMute(int track, bool on) {
  const uint32_t bit = 1u << track;
  const uint32_t mask = on ? (m_muteMask | bit) : (m_muteMask & ~bit);
  if (mask != m_muteMask) {
    m_muteMask = mask;
    emit muteMaskChanged(mask);
  }
}

void SongView::setTrackSolo(int track, bool on) {
  const uint32_t bit = 1u << track;
  const uint32_t mask = on ? (m_soloMask | bit) : (m_soloMask & ~bit);
  if (mask != m_soloMask) {
    m_soloMask = mask;
    emit soloMaskChanged(mask);
  }
}

QColor SongView::trackColor(int track) {
  return themes::trackIdentityColor(trackIdentityIndex(track));
}

QColor SongView::noteColor(int track, int velocity) {
  // 16 identities × 128 velocities; rebuilt when the theme zero-velocity
  // color changes. Steady-state paint is a table load (mixTowardOklab is
  // only paid on rebuild).
  static std::array<std::array<QColor, 128>, themes::trackIdentityColorCount>
      table;
  static QRgb zeroKey{};

  const auto &zero = themes::color(themes::Role::song_view_note_velocity_zero);
  if (zeroKey != zero.rgba()) {
    zeroKey = zero.rgba();
    for (std::size_t i = 0; i < table.size(); ++i) {
      const auto &fill = themes::trackIdentityColor(i);
      table[i][0] = zero;
      table[i][127] = fill;
      for (int v = 1; v < 127; ++v)
        table[i][static_cast<std::size_t>(v)] =
            mixTowardOklab(fill, zero, 1.0 - double(v) / 127.0);
    }
  }
  const int v = std::clamp(velocity, 0, 127);
  return table[trackIdentityIndex(track)][static_cast<std::size_t>(v)];
}

int SongView::programAt(int track, uint64_t tick) const {
  if (!m_timeline)
    return -1;
  int program = m_timeline->tracks[track].firstProgram;
  for (const VoiceChange &change : m_model.voices) {
    if (change.tick > tick)
      break;
    if (change.track == track)
      program = change.program;
  }
  return program;
}

int SongView::currentProgram(int track) const {
  const uint64_t tick = m_playing ? uint64_t(m_playheadTick) : m_editCursorTick;
  return programAt(track, tick);
}

QColor SongView::velocityNoteColor(int velocity) {
  if (velocity <= 0)
    return themes::color(themes::Role::song_view_note_velocity_zero);
  // Purple's hue (~250°) interpolates linearly down to red's (~1°), which
  // is the long way around the wheel — through blue, green, and yellow —
  // so the full spectrum spreads across the velocity range.
  static const QColor kMinVelocity(0x5f, 0x44, 0xe9);
  static const QColor kMaxVelocity(0xe9, 0x09, 0x04);
  if (velocity <= 1)
    return kMinVelocity;
  if (velocity >= 127)
    return kMaxVelocity;
  const float t = float(velocity - 1) / 126.0f;
  float h0, s0, v0, h1, s1, v1;
  kMinVelocity.getHsvF(&h0, &s0, &v0);
  kMaxVelocity.getHsvF(&h1, &s1, &v1);
  // Quantize to 8-bit RGB: QColor equality is spec- and depth-sensitive,
  // and callers compare against rendered pixels.
  return QColor(QColor::fromHsvF(h0 + (h1 - h0) * t, s0 + (s1 - s0) * t,
                                 v0 + (v1 - v0) * t)
                    .rgb());
}

void SongView::setVelocityColorMode(bool on) {
  if (m_velocityColorMode == on)
    return;
  m_velocityColorMode = on;
  m_roll->update();
}

QColor SongView::noteFillColor(int track, int velocity) const {
  return m_velocityColorMode ? velocityNoteColor(velocity)
                             : noteColor(track, velocity);
}

void SongView::revealVoice(int program) {
  if (program >= 0 && program < 128)
    emit revealVoiceRequested(program);
}

void SongView::revealTrackVoice(int track) {
  if (!m_timeline || track < 0 || track > 15)
    return;
  const int prog = currentProgram(track);
  if (prog < 0) {
    emit statusMessage(tr("Track %1 has no voice set.").arg(track + 1));
    return;
  }
  revealVoice(prog);
}

QSet<int> SongView::usedVoices() const {
  QSet<int> used;
  if (!m_timeline)
    return used;
  for (int t = 0; t < 16; t++) {
    if (m_timeline->tracks[t].used && m_timeline->tracks[t].firstProgram >= 0)
      used.insert(m_timeline->tracks[t].firstProgram);
  }
  for (const VoiceChange &vc : m_model.voices)
    used.insert(vc.program);
  return used;
}

QString SongView::instrumentLabel(int track) const {
  if (!m_timeline)
    return QString();
  const int prog = currentProgram(track);
  if (prog < 0)
    return tr("(no voice set)");
  QString name = voiceShortName(uint8_t(prog));
  return QStringLiteral("%1 %2").arg(prog, 3, 10, QLatin1Char('0')).arg(name);
}

QString SongView::voiceShortName(uint8_t program) const {
  QString name;
  QString type;
  if (m_voicegroup && program < VOICEGROUP_SIZE) {
    name = QString::fromUtf8(m_voicegroup->voiceNames[program]).trimmed();
    type = m4aVoiceTypeName(m_voicegroup->voices[program].type);
  }
  if (name.isEmpty())
    return type.isEmpty() ? tr("Voice") : type;
  return QStringLiteral("%1 (%2)").arg(name, type);
}

bool SongView::pickVoice(const QString &title, int initialVoice,
                         int *outVoice) {
  VoicePickerDialog dialog(
      this, title, initialVoice, [this](int voice, int velocity) {
        emit auditionVoice(voice, kVoiceAuditionKey, velocity);
      });
  if (dialog.exec() != QDialog::Accepted)
    return false;
  *outVoice = dialog.selectedVoice();
  return true;
}

void SongView::editTrackVoice(int track) {
  if (!m_document || track < 0 || track > 15)
    return;
  const std::vector<DocLanePoint> changes =
      m_document->lanePoints(track, DOC_CC_VOICE);
  const int initial = changes.empty() ? 0 : changes.front().value;
  int voice = initial;
  if (!pickVoice(tr("Track %1 voice").arg(track + 1), initial, &voice))
    return;
  if (changes.empty())
    m_document->addLanePoint(track, DOC_CC_VOICE, 0, voice);
  else if (voice != initial)
    m_document->moveLanePoint(track, DOC_CC_VOICE, changes.front(),
                              changes.front().tick, voice);
}

void SongView::renameTrack(int track) {
  if (!m_document || track < 0 || track > 15 ||
      m_document->smfTrackFor(track) < 0)
    return;
  m_headers->beginRename(track);
}

void SongView::commitTrackRename(int track, const QString &name) {
  if (!m_document || track < 0 || track > 15 ||
      m_document->smfTrackFor(track) < 0)
    return;
  const QString trimmed = name.trimmed();
  if (nameIsLoopMarker(trimmed)) {
    announce(tr("\"%1\" is read by the song build as a loop or label "
                "marker, so it can't be a track name.")
                 .arg(trimmed));
    return;
  }
  // Queued: the commit arrives from the header row's editor signal, and
  // the edit rebuilds the header panel — deleting that editor mid-signal.
  QMetaObject::invokeMethod(
      this,
      [this, track, trimmed] {
        if (m_document)
          m_document->renameTrack(track, trimmed);
      },
      Qt::QueuedConnection);
}

void SongView::addTrack() {
  if (!m_document || !m_document->canAddTrack())
    return;
  int voice = 0;
  if (!pickVoice(tr("New track voice"), 0, &voice))
    return;
  const int track = m_document->addTrack(voice); // rebuilds via documentChanged
  if (track >= 0) {
    selectTrack(track);
    announce(tr("Added track %1").arg(track + 1));
  }
}

void SongView::duplicateTrack(int track) {
  if (!m_document || track < 0 || track > 15 ||
      m_document->smfTrackFor(track) < 0)
    return;
  const int copy =
      m_document->duplicateTrack(track); // rebuilds via documentChanged
  if (copy >= 0) {
    selectTrack(copy);
    announce(
        tr("Duplicated track %1 as track %2").arg(track + 1).arg(copy + 1));
  }
}

void SongView::deleteTrack(int track) {
  if (!m_document || track < 0 || track > 15 ||
      m_document->smfTrackFor(track) < 0)
    return;
  // The post-mutation remap runs before documentChanged rebuilds the views.
  m_document->deleteTrack(track);
  announce(tr("Deleted track %1").arg(track + 1));
}

void SongView::moveTrack(int from, int to) {
  if (!m_document)
    return;
  // The document decides validity. Its post-mutation engine-slot map
  // carries all surviving per-track view state on apply, undo, and redo.
  if (m_document->moveTrack(from, to)) // rebuilds via documentChanged
    announce(tr("Moved track %1 to slot %2").arg(from + 1).arg(to + 1));
}

void SongView::onTracksRemapped(const SongDocument::TrackRemap &remap) {
  const QVector<int> &newEngineSlotByOldSlot = remap.newEngineSlotByOldSlot;
  // This signal arrives after SongDocument has rebuilt its engine-track
  // mapping but before documentChanged rebuilds the views. Remap state
  // only: newly introduced slots have no old owner and therefore keep
  // defaults.
  const int newEngineSlotCount =
      m_document ? std::clamp(m_document->engineTrackCount(), 0, 16) : 0;
  const auto newEngineSlotForOldSlot = [&newEngineSlotByOldSlot,
                                        newEngineSlotCount](int oldEngineSlot) {
    if (oldEngineSlot < 0 || oldEngineSlot >= newEngineSlotByOldSlot.size())
      return -1;
    const int newEngineSlot = newEngineSlotByOldSlot[oldEngineSlot];
    return newEngineSlot >= 0 && newEngineSlot < newEngineSlotCount
               ? newEngineSlot
               : -1;
  };

  const auto remapTrackMask = [&newEngineSlotForOldSlot](uint32_t trackMask) {
    uint32_t remappedTrackMask = 0;
    for (int oldEngineSlot = 0; oldEngineSlot < 16; ++oldEngineSlot) {
      if (!(trackMask & (uint32_t{1} << oldEngineSlot)))
        continue;
      const int newEngineSlot = newEngineSlotForOldSlot(oldEngineSlot);
      if (newEngineSlot >= 0)
        remappedTrackMask |= uint32_t{1} << newEngineSlot;
    }
    return remappedTrackMask;
  };
  const uint32_t newMuteMask = remapTrackMask(m_muteMask);
  const uint32_t newSoloMask = remapTrackMask(m_soloMask);
  if (newMuteMask != m_muteMask) {
    m_muteMask = newMuteMask;
    emit muteMaskChanged(newMuteMask);
  }
  if (newSoloMask != m_soloMask) {
    m_soloMask = newSoloMask;
    emit soloMaskChanged(newSoloMask);
  }

  const auto remapLaneOwners = [&newEngineSlotForOldSlot](
                                   auto &laneIdentities) {
    for (auto laneIdentity = laneIdentities.begin();
         laneIdentity != laneIdentities.end();) {
      const int newEngineSlot = newEngineSlotForOldSlot(laneIdentity->first);
      if (newEngineSlot < 0) {
        laneIdentity = laneIdentities.erase(laneIdentity);
      } else {
        laneIdentity->first = newEngineSlot;
        ++laneIdentity;
      }
    }
  };
  remapLaneOwners(m_emptyLanes);
  remapLaneOwners(m_hiddenLanes);
  m_lanes->remapTrackRowState(newEngineSlotByOldSlot);

  const int oldSelectedEngineSlot = m_selectedTrack;
  const int newSelectedEngineSlot =
      newEngineSlotForOldSlot(oldSelectedEngineSlot);
  if (newSelectedEngineSlot >= 0) {
    m_selectedTrack = newSelectedEngineSlot;
  } else {
    // Keep the same numbered slot when another owner now occupies it;
    // when deletion removed the tail, fall back to the new last slot.
    m_selection.clear();
    m_selectedTrack = newEngineSlotCount > 0
                          ? std::min(std::max(oldSelectedEngineSlot, 0),
                                     newEngineSlotCount - 1)
                          : 0;
  }

  // Multi-track/time selection is address-based rather than owner-based.
  // Collapse it without repainting; documentChanged refreshes the views.
  m_trackSelMask = newEngineSlotCount > 0 ? uint32_t{1} << m_selectedTrack : 0;
  m_timeSel = TimeSelection();
}

void SongView::forEachGridLine(
    uint64_t tickBegin, uint64_t tickEnd,
    const std::function<void(uint64_t, bool, int, int)> &fn) const {
  if (!m_timeline || tickEnd <= tickBegin)
    return;
  const uint32_t tpb = m_timeline->ticksPerBeat;

  struct Seg {
    uint64_t tick;
    uint64_t beatTicks;
    int beatsPerBar;
  };
  std::vector<Seg> segs;
  segs.push_back({0, tpb, 4});
  for (const TimeSigPoint &ts : m_timeline->timeSigs) {
    uint64_t beatTicks = (uint64_t(tpb) * 4) >> std::min<int>(ts.denomPow2, 63);
    if (beatTicks < 1)
      beatTicks = 1;
    const Seg seg{ts.tick, beatTicks, ts.numerator ? ts.numerator : 4};
    if (ts.tick == segs.back().tick)
      segs.back() = seg;
    else
      segs.push_back(seg);
  }

  int bar = 1;
  for (size_t i = 0; i < segs.size(); i++) {
    const Seg &seg = segs[i];
    const uint64_t segEnd = i + 1 < segs.size()
                                ? segs[i + 1].tick
                                : std::max<uint64_t>(tickEnd, seg.tick);
    const uint64_t clampedEnd = std::min(segEnd, tickEnd);
    if (seg.tick < clampedEnd) {
      uint64_t k =
          tickBegin > seg.tick ? (tickBegin - seg.tick) / seg.beatTicks : 0;
      for (uint64_t tick = seg.tick + k * seg.beatTicks; tick < clampedEnd;
           tick += seg.beatTicks, k++) {
        if (tick < tickBegin)
          continue;
        fn(tick, k % seg.beatsPerBar == 0, bar + int(k / seg.beatsPerBar),
           int(k % seg.beatsPerBar) + 1);
      }
    }
    if (i + 1 < segs.size()) {
      const uint64_t segTicks = segs[i + 1].tick - seg.tick;
      const uint64_t barTicks = seg.beatTicks * seg.beatsPerBar;
      bar += int((segTicks + barTicks - 1) / barTicks);
    }
  }
}

void SongView::updateNoteViews() {
  if (m_roll)
    m_roll->update();
  if (m_velocityArea)
    m_velocityArea->update();
}

std::optional<uint8_t>
SongView::noteVelocityPreview(const ViewNote &note) const {
  if (m_velocityArea) {
    if (const auto preview = m_velocityArea->velocityPreview(note))
      return preview;
  }
  if (m_roll)
    return m_roll->velocityPreview(note);
  return std::nullopt;
}

void SongView::zoomAroundContentX(double factor, qreal anchorContentX) {
  if (!m_timeline)
    return;
  const double tpb = double(m_timeline->ticksPerBeat);
  const double oldPxPerTick = m_pxPerTick;
  m_pxPerTick = std::clamp(oldPxPerTick * factor, kMinPxPerBeat / tpb,
                           kMaxPxPerBeat / tpb);
  m_scrollX =
      std::clamp(cursorAnchoredScroll(double(anchorContentX), oldPxPerTick,
                                      m_scrollX, m_pxPerTick),
                 0.0, maxHScroll());
  updateScrollbars();
  m_lanes->clearHoverFeedback();
  refreshTimelineViews();
}

void SongView::zoomKeyHeight(const QWheelEvent *event) {
  if (!m_timeline)
    return;
  const double zoomDelta = wheelAngleUnits(event);
  if (zoomDelta == 0.0)
    return;
  const double oldH = m_keyHeight;
  const double newH = std::clamp(oldH * std::exp2(zoomDelta / 1200.0),
                                 kMinKeyHeight, kMaxKeyHeight);
  if (newH == m_keyHeight)
    return;
  // Pin the content row under the cursor before projecting to the scrollbar.
  const double anchorY = event->position().y();
  const double anchoredScroll =
      cursorAnchoredScroll(anchorY, oldH, m_scrollY, newH);
  m_keyHeight = newH;
  updateScrollbars();
  setVScroll(std::clamp(anchoredScroll, 0.0, maxRollScroll()));
  // The camera scale changed even when the cursor anchor keeps its scroll
  // offset numerically unchanged.
  m_roll->update();
}

void SongView::scrollByPx(double dx) { setHScroll(m_scrollX + dx); }

void SongView::scrollRollBy(double dy) { setVScroll(m_scrollY + dy); }

void SongView::setHScroll(double px) {
  const double newX = std::clamp(px, 0.0, maxHScroll());
  const bool cameraChanged = newX != m_scrollX;
  m_scrollX = newX;
  const int scrollbarValue = scrollUnits(m_scrollX);
  if (m_hbar->value() != scrollbarValue) {
    m_hbar->blockSignals(true);
    m_hbar->setValue(scrollbarValue);
    m_hbar->blockSignals(false);
  }
  if (cameraChanged) {
    m_lanes->clearHoverFeedback();
    refreshTimelineViews();
  }
}

void SongView::ensureTickVisible(uint64_t tick) {
  const qreal vw = viewportWidth();
  const qreal dpr = m_roll->devicePixelRatioF();
  const qreal physicalPixel = logicalPhysicalPixel(dpr);
  const qreal displayedX = displayX(double(tick), 0.0, dpr);
  if (displayedX >= 0.0 && displayedX <= vw - physicalPixel)
    return;
  setHScroll(double(tick) * m_pxPerTick - vw / 3.0);
}

void SongView::ensureRangeVisible(uint64_t startTick, uint64_t endTick,
                                  bool preferEnd) {
  const qreal x0 = contentX(double(startTick));
  const qreal x1 = contentX(double(endTick));
  const qreal vw = viewportWidth();
  const qreal dpr = m_roll->devicePixelRatioF();
  const qreal physicalPixel = logicalPhysicalPixel(dpr);
  const qreal displayedX0 = displayX(double(startTick), 0.0, dpr);
  const qreal displayedX1 = displayX(double(endTick), 0.0, dpr);
  const qreal rightEdge = vw - physicalPixel;
  qreal dx = 0.0;
  if (displayedX1 - displayedX0 > rightEdge)
    // Wider than the viewport: the leading edge wins.
    dx = preferEnd ? x1 - rightEdge : x0;
  else if (displayedX1 > rightEdge)
    dx = x1 - rightEdge;
  else if (displayedX0 < 0.0)
    dx = x0;
  if (dx != 0.0)
    setHScroll(m_scrollX + dx);
}

void SongView::ensureKeyVisible(int key) {
  const double y0 = (127 - key) * m_keyHeight - m_scrollY;
  const double y1 = y0 + m_keyHeight;
  const int vh = m_roll->height();
  if (y0 < 0)
    setVScroll(m_scrollY + y0);
  else if (y1 > vh)
    setVScroll(m_scrollY + y1 - vh);
}

int SongView::viewportWidth() const {
  return std::max(50, m_roll->width() - kKeyboardW);
}

double SongView::maxHScroll() const {
  const double contentWidth =
      m_timeline ? double(m_timeline->lengthTicks) * m_pxPerTick + 100.0 : 0.0;
  return std::max(0.0, contentWidth - double(viewportWidth()));
}

double SongView::maxRollScroll() const {
  return std::max(0.0, 128.0 * m_keyHeight - m_roll->height());
}

void SongView::setVScroll(double y) {
  const double newY = std::clamp(y, 0.0, maxRollScroll());
  const bool cameraChanged = m_scrollY != newY;
  m_scrollY = newY;
  const int scrollbarValue = scrollUnits(m_scrollY);
  if (m_vbar->value() != scrollbarValue) {
    m_vbar->blockSignals(true);
    m_vbar->setValue(scrollbarValue);
    m_vbar->blockSignals(false);
  }
  if (cameraChanged)
    m_roll->update();
}

void SongView::updateScrollbars() {

  m_hbar->blockSignals(true);
  m_hbar->setRange(0, scrollUnits(maxHScroll()));
  m_hbar->setPageStep(scrollUnits(double(viewportWidth())));
  m_hbar->blockSignals(false);
  setHScroll(m_scrollX);

  m_vbar->blockSignals(true);
  m_vbar->setRange(0, scrollUnits(maxRollScroll()));
  m_vbar->setPageStep(scrollUnits(double(m_roll->height())));
  m_vbar->blockSignals(false);
  setVScroll(m_scrollY);
}

void SongView::refreshTimelineViews() {
  m_ruler->update();
  m_roll->update();
  if (m_events)
    m_events->update();
  if (m_lanes)
    m_lanes->update();
  if (m_velocityArea)
    m_velocityArea->update();
  if (m_strip)
    m_strip->update();
  syncPlayheadOverlay();
}

void SongView::resizeEvent(QResizeEvent *event) {
  QWidget::resizeEvent(event);
  updateScrollbars();
  syncPlayheadOverlay();
}
