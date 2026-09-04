// ---------------------------------------------------------------- TimeRuler

#include "ui/songview/timeruler.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/grid.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <QAction>
#include <QFontMetrics>
#include <QMenu>
#include <QVariant>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <utility>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
using namespace songview::detail;

TimeRuler::Geometry TimeRuler::Geometry::resolve()
{
    return {lyt::fontPx(5.0 / 6.0), lyt::fontPx(1.0 / 12.0), lyt::fontPxF(-1.0 / 24.0), 3.0};
}

QFont TimeRuler::resolveRulerFont(const Geometry &geometry)
{
    QFont rulerFont = typography::bodyMono(typography::caption(*typography::bodyFont()));
    rulerFont.setPixelSize(std::max(geometry.timeRulerMinimumFontPixelSize,
                                    rulerFont.pixelSize() - lyt::singlePixel()));
    rulerFont.setLetterSpacing(QFont::AbsoluteSpacing, geometry.timeRulerLetterSpacing);
    return rulerFont;
}

int TimeRuler::markerRowHeight(const QFontMetrics &metrics)
{
    return metrics.height() + lyt::singlePixel();
}

int TimeRuler::rowHeight()
{
    const Geometry geometry = Geometry::resolve();
    const QFont rulerFont = resolveRulerFont(geometry);
    const QFontMetrics markerMetrics(typography::bold(rulerFont));
    const QFontMetrics tickMetrics(rulerFont);
    return markerRowHeight(markerMetrics) + tickMetrics.height() + lyt::singlePixel();
}

namespace {

QString gridDivisionText(int minDenom)
{
    return minDenom == 0 ? SongView::tr("Auto") : QStringLiteral("1/%1").arg(minDenom);
}

} // namespace

QString TimeRuler::divisionText() const
{
    return m_divisionText;
}

QString TimeRuler::feelText() const
{
    return m_feelText;
}

QString TimeRuler::divisionToolTip() const
{
    return SongView::tr("Finest drawn subdivision. Auto follows the zoom down to "
                        "the mid2agb clock grid; edits snap one step finer than "
                        "the drawn grid.");
}

QString TimeRuler::feelToolTip() const
{
    return SongView::tr("Straight or triplet beat subdivisions.");
}

bool TimeRuler::gridControlsEnabled() const noexcept
{
    return m_gridControlsEnabled;
}

QVariantMap TimeRuler::gridControlAppearance() const
{
    return m_gridControlAppearance;
}

void TimeRuler::syncGridControls()
{
    const QString division = gridDivisionText(m_grid.minDenom());
    const QString feel =
        m_grid.feel() == GridFeel::Triplet ? SongView::tr("Triplet") : SongView::tr("Straight");
    const bool enabled = m_inputHost != nullptr;
    if (m_divisionText == division && m_feelText == feel && m_gridControlsEnabled == enabled)
        return;

    m_divisionText = division;
    m_feelText = feel;
    m_gridControlsEnabled = enabled;
    emit gridControlsChanged();
}

void TimeRuler::syncGridControlAppearance()
{
    QVariantMap appearance;
    appearance.insert(QStringLiteral("primaryText"),
                      QVariant::fromValue(themes::color(themes::Role::song_view_primary_text)));
    appearance.insert(QStringLiteral("buttonBackground"),
                      QVariant::fromValue(themes::color(themes::Role::combo_background)));
    appearance.insert(QStringLiteral("buttonText"),
                      QVariant::fromValue(themes::color(themes::Role::combo_text)));
    appearance.insert(QStringLiteral("buttonOutline"),
                      QVariant::fromValue(themes::color(themes::Role::combo_outline)));
    appearance.insert(
        QStringLiteral("buttonHoverBackground"),
        QVariant::fromValue(themes::color(themes::Role::combo_drop_down_hover_background)));
    appearance.insert(
        QStringLiteral("buttonPressedBackground"),
        QVariant::fromValue(themes::color(themes::Role::combo_drop_down_pressed_background)));
    appearance.insert(QStringLiteral("font"),
                      QVariant::fromValue(m_inputHost ? m_inputHost->font() : m_owner.font()));
    if (m_gridControlAppearance == appearance)
        return;

    m_gridControlAppearance = std::move(appearance);
    emit gridControlAppearanceChanged();
}

void TimeRuler::openDivisionMenu(QPointF position)
{
    openGridMenu(position, true);
}

void TimeRuler::openFeelMenu(QPointF position)
{
    openGridMenu(position, false);
}

void TimeRuler::openGridMenu(QPointF position, bool division)
{
    if (!m_inputHost || !m_gridControlsEnabled)
        return;

    QMenu menu(&m_owner);
    if (division) {
        for (const int denom : {0, 4, 8, 16, 32}) {
            QAction *const action = menu.addAction(gridDivisionText(denom));
            action->setData(denom);
            action->setCheckable(true);
            action->setChecked(m_grid.minDenom() == denom);
        }
    } else {
        for (const GridFeel feel : {GridFeel::Straight, GridFeel::Triplet}) {
            QAction *const action = menu.addAction(
                feel == GridFeel::Triplet ? SongView::tr("Triplet") : SongView::tr("Straight"));
            action->setData(static_cast<int>(feel));
            action->setCheckable(true);
            action->setChecked(m_grid.feel() == feel);
        }
    }

    m_openMenu = &menu;
    QAction *const action = menu.exec(m_inputHost->mapToGlobal(position).toPoint());
    if (m_openMenu.data() == &menu)
        m_openMenu.clear();
    if (!action)
        return;

    if (division)
        m_owner.setGridMinDenom(action->data().toInt());
    else
        m_owner.setGridFeel(static_cast<GridFeel>(action->data().toInt()));
}

void TimeRuler::closePopups()
{
    if (m_openMenu)
        m_openMenu->close();
}

TimeRuler::TimeRuler(SongView &owner)
    : QObject()
    , m_owner(owner)
    , m_camera(owner.camera())
    , m_grid(owner.grid())
    , m_geometry(Geometry::resolve())
{
    m_rulerFont = resolveRulerFont(m_geometry);
    m_beatFont = m_rulerFont;
    m_beatFont.setPixelSize(std::max(m_geometry.timeRulerMinimumFontPixelSize,
                                     m_beatFont.pixelSize() - lyt::singlePixel()));
    m_signatureFont = typography::bold(*typography::bodyFont());
    m_boldRulerFont = typography::bold(m_rulerFont);
    m_rulerMetrics = QFontMetrics(m_rulerFont);
    m_beatMetrics = QFontMetrics(m_beatFont);
    m_boldRulerMetrics = QFontMetrics(m_boldRulerFont);
    m_signatureMetrics = QFontMetrics(m_signatureFont);
    m_markerHeight = markerRowHeight(m_boldRulerMetrics);
    syncGridControls();
    syncGridControlAppearance();
}

void TimeRuler::attachInputHost(TimelineInputHost &host)
{
    Q_ASSERT(!m_inputHost);
    m_inputHost = &host;
    syncGridControls();
    syncGridControlAppearance();
    requestQuickUpdate();
}

void TimeRuler::detachInputHost(TimelineInputHost &host)
{
    Q_ASSERT(m_inputHost == &host);
    if (m_inputHost != &host)
        return;
    closePopups();
    cancelInteraction();
    m_inputHost = nullptr;
    syncGridControls();
    syncGridControlAppearance();
}

void TimeRuler::requestQuickUpdate()
{
    m_owner.requestTimelineQuickUpdate(TimelineQuickDirty::Ruler);
}

// A mouse gesture is live (marker/time-sig/selection-edge drag or a
// pending ruler press); the playhead follow-scroll pauses while one runs
// so the view doesn't jump under the cursor.
bool TimeRuler::gestureActive() const noexcept
{
    return m_dragMarker >= 0 || m_dragTimeSig || m_leftPress || m_rightPress || m_dragSelEdge >= 0;
}

void TimeRuler::cancelInteraction()
{
    m_dragMarker = -1;
    m_dragTimeSig = false;
    m_leftPress = false;
    m_rightPress = false;
    m_selSweep = false;
    m_multiTrackSweep = false;
    m_dragSelEdge = -1;
    if (m_inputHost)
        m_inputHost->clearCursor();
    requestQuickUpdate();
}

void TimeRuler::hostAppearanceChanged()
{
    syncGridControlAppearance();
    requestQuickUpdate();
}

QRect TimeRuler::markerRow() const
{
    Q_ASSERT(m_inputHost);
    return QRect(lyt::space(Space::Zero), lyt::space(Space::Zero),
                 qRound(m_inputHost->bounds().width()), m_markerHeight);
}

QRect TimeRuler::tickRow() const
{
    Q_ASSERT(m_inputHost);
    return QRect(lyt::space(Space::Zero), m_markerHeight, qRound(m_inputHost->bounds().width()),
                 qRound(m_inputHost->bounds().height()) - m_markerHeight);
}

int TimeRuler::textBaseline(const QRect &row, const QFontMetrics &metrics) const
{
    return row.top() + (row.height() - metrics.height()) / 2 + metrics.ascent();
}

// 0 = start marker, 1 = end marker, -1 = neither near pos.
int TimeRuler::hitMarker(QPointF pos) const
{
    const MidiTimeline *tl = m_owner.timeline();
    if (!tl || !QRectF(markerRow()).contains(pos))
        return -1;
    const auto markerHitHalfWidth = lyt::space(Space::Two);
    const qreal dpr = m_inputHost->devicePixelRatio();
    if (tl->loopStartTick != UINT64_MAX &&
        std::abs(m_camera.displayX(double(tl->loopStartTick), 0.0, dpr) - pos.x()) <=
            markerHitHalfWidth)
        return 0;
    if (tl->loopEndTick != UINT64_MAX &&
        std::abs(m_camera.displayX(double(tl->loopEndTick), 0.0, dpr) - pos.x()) <=
            markerHitHalfWidth)
        return 1;
    return -1;
}

// Chip layout shared by paint and hit-testing: shadowed same-tick
// duplicates dropped, labels nudged past a loop bracket glyph sitting on
// the same spot, and a label hidden (stem only) when it would run into
// the next chip — zooming in separates them again.
std::vector<TimeRuler::SigChip> TimeRuler::sigChips() const
{
    std::vector<SigChip> chips;
    const TimeAxis &axis = m_owner.timeAxis();
    const qreal dpr = m_inputHost->devicePixelRatio();
    const QFontMetrics &fm = m_signatureMetrics;
    const auto labelInset = lyt::space(Space::Half);
    const auto add = [&](const TimeAxis::ResolvedTimeSignature &sig) {
        const qreal x = m_camera.displayX(double(sig.tick), 0.0, dpr);
        chips.push_back({sig.tick, sig.numerator, sig.denomPow2, sig.implicit, x, x + labelInset,
                         qreal(fm.horizontalAdvance(timeSigLabel(sig.numerator, sig.denomPow2)))});
    };
    // The axis synthesizes the opening 4/4 whenever no actual signature
    // governs tick 0 — always so on the fallback axis.
    if (axis.hasImplicitOpeningSignature())
        add(axis.signatureAt(0));
    const std::span<const TimeSigPoint> sigs = axis.explicitTimeSignatures();
    for (size_t i = 0; i < sigs.size(); i++) {
        if (i + 1 < sigs.size() && sigs[i + 1].tick == sigs[i].tick)
            continue; // shadowed duplicate: the last at a tick wins
        add(axis.signatureAt(sigs[i].tick));
    }
    const uint64_t loops[2] = {axis.loopStartTick(), axis.loopEndTick()};
    const qreal bracketWidth = fm.horizontalAdvance(QStringLiteral("["));
    for (SigChip &chip : chips) {
        for (uint64_t loopTick : loops) {
            if (loopTick == UINT64_MAX)
                continue;
            const qreal bracketStart = m_camera.displayX(double(loopTick), 0.0, dpr) + labelInset;
            const qreal bracketRight = bracketStart + bracketWidth;
            if (bracketRight > chip.labelX && bracketStart < chip.labelX + chip.labelW)
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
bool TimeRuler::hitTimeSigChip(QPointF pos, uint64_t *tick, int *numerator, int *denomPow2,
                               bool *implicit) const
{
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

// Values in effect at tick; the axis resolves the implicit opening 4/4.
void TimeRuler::sigAtTick(uint64_t tick, int *numerator, int *denomPow2) const
{
    const TimeAxis::ResolvedTimeSignature sig = m_owner.timeAxis().signatureAt(tick);
    *numerator = sig.numerator;
    *denomPow2 = sig.denomPow2;
}

// 0 = selection start edge, 1 = end edge, -1 = neither near pos.
int TimeRuler::hitSelEdge(QPointF pos) const
{
    const auto &sel = m_owner.selectionModel().timeSelection();
    if (!sel.active() || !QRectF(markerRow()).contains(pos))
        return -1;
    const auto markerHitHalfWidth = lyt::space(Space::Two);
    const qreal dpr = m_inputHost->devicePixelRatio();
    if (std::abs(m_camera.displayX(double(sel.startTick), 0.0, dpr) - pos.x()) <=
        markerHitHalfWidth)
        return 0;
    if (std::abs(m_camera.displayX(double(sel.endTick), 0.0, dpr) - pos.x()) <= markerHitHalfWidth)
        return 1;
    return -1;
}

} // namespace songview
