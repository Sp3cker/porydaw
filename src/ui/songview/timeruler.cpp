// ---------------------------------------------------------------- TimeRuler

#include "ui/songview/timeruler.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/typography.h"

#include <QComboBox>
#include <QEvent>
#include <QFontMetrics>
#include <QHBoxLayout>
#include <QLabel>
#include <QObject>
#include <QWheelEvent>

#include <algorithm>
#include <cmath>
#include <cstddef>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
using namespace songview::detail;

TimeRuler::Geometry TimeRuler::Geometry::resolve()
{
    return {lyt::fontPx(17.5 + 13.0 / 3.0), lyt::fontPx(5.0 / 6.0), lyt::fontPx(1.0 / 12.0),
            lyt::fontPxF(-1.0 / 24.0), 3.0};
}

void TimeRuler::refreshGeometry()
{
    m_geometry = Geometry::resolve();
    const auto markerRowPadding = lyt::singlePixel();
    const auto tickRowPadding = lyt::singlePixel();
    m_rulerFont = typography::bodyMono(typography::caption(font()));
    m_rulerFont.setPixelSize(std::max(m_geometry.timeRulerMinimumFontPixelSize,
                                      m_rulerFont.pixelSize() - lyt::singlePixel()));
    m_rulerFont.setLetterSpacing(QFont::AbsoluteSpacing, m_geometry.timeRulerLetterSpacing);
    m_beatFont = m_rulerFont;
    m_beatFont.setPixelSize(std::max(m_geometry.timeRulerMinimumFontPixelSize,
                                     m_beatFont.pixelSize() - lyt::singlePixel()));
    m_signatureFont = typography::bold(font());
    m_boldRulerFont = typography::bold(m_rulerFont);
    const QFontMetrics markerMetrics(m_boldRulerFont);
    const QFontMetrics tickMetrics(m_rulerFont);
    m_markerHeight = markerMetrics.height() + markerRowPadding;
    const auto rulerHeight = m_markerHeight + tickMetrics.height() + tickRowPadding;
    setFixedHeight(rulerHeight);
    if (m_gridBox)
        m_gridBox->setGeometry(lyt::space(Space::Zero), lyt::space(Space::Zero),
                               m_geometry.plotOrigin - lyt::space(Space::One), rulerHeight);
    requestQuickUpdate();
}

TimeRuler::TimeRuler(SongView *sv) : QWidget(sv), m_sv(sv), m_geometry(Geometry::resolve())
{
    setAutoFillBackground(false);
    refreshGeometry();
    const auto rulerHeight = height();
    setMouseTracking(true);

    // Snap-grid controls in the gutter left of the timeline: minimum
    // subdivision (Auto = zoom-adaptive down to the clock grid) and
    // straight-vs-triplet feel. NoFocus for the same reason the scroll
    // areas have it: keyboard editing must stay in the roll.
    m_gridBox = new QWidget(this);
    m_gridBox->setGeometry(lyt::space(Space::Zero), lyt::space(Space::Zero),
                           m_geometry.plotOrigin - lyt::space(Space::One), rulerHeight);
    auto *row = new QHBoxLayout(m_gridBox);
    row->setContentsMargins(lyt::space(Space::Two), lyt::space(Space::Zero),
                            lyt::space(Space::Zero), lyt::space(Space::Zero));
    row->setSpacing(lyt::space(Space::One));
    row->addWidget(new QLabel(SongView::tr("Grid"), m_gridBox));
    m_divCombo = new QComboBox(m_gridBox);
    m_divCombo->addItem(SongView::tr("Auto"), 0);
    for (int denom : {4, 8, 16, 32})
        m_divCombo->addItem(QStringLiteral("1/%1").arg(denom), denom);
    m_divCombo->setToolTip(SongView::tr("Finest drawn subdivision. Auto follows the zoom down to "
                                        "the mid2agb clock grid; edits snap one step finer than "
                                        "the drawn grid."));
    m_feelCombo = new QComboBox(m_gridBox);
    m_feelCombo->addItem(SongView::tr("Straight"));
    m_feelCombo->addItem(SongView::tr("Triplet"));
    m_feelCombo->setToolTip(SongView::tr("Straight or triplet beat subdivisions."));
    for (QComboBox *combo : {m_divCombo, m_feelCombo}) {
        combo->setFocusPolicy(Qt::NoFocus);
        row->addWidget(combo);
    }
    row->addStretch(1);
    QObject::connect(m_divCombo, &QComboBox::activated, m_sv, [this](int index) {
        m_sv->setGridMinDenom(m_divCombo->itemData(index).toInt());
    });
    QObject::connect(m_feelCombo, &QComboBox::activated, m_sv, [this](int index) {
        m_sv->setGridFeel(index == 1 ? SongView::GridFeel::Triplet : SongView::GridFeel::Straight);
    });
}

// Combo state from the view (setters, setSong reset, sidecar apply);
// setCurrentIndex is safe because the handlers hang off activated(),
// which only fires on user picks.
void TimeRuler::syncGridControls()
{
    m_divCombo->setCurrentIndex(std::max(0, m_divCombo->findData(m_sv->gridMinDenom())));
    m_feelCombo->setCurrentIndex(m_sv->gridFeel() == SongView::GridFeel::Triplet ? 1 : 0);
}

void TimeRuler::requestQuickUpdate()
{
    m_sv->requestTimelineQuickUpdate(TimelineQuickDirty::Ruler);
}

// A mouse gesture is live (marker/time-sig/selection-edge drag or a
// pending ruler press); the playhead follow-scroll pauses while one runs
// so the view doesn't jump under the cursor.
bool TimeRuler::gestureActive() const
{
    return m_dragMarker >= 0 || m_dragTimeSig || m_leftPress || m_rightPress || m_dragSelEdge >= 0;
}

void TimeRuler::cancelTransientInput()
{
    m_divCombo->hidePopup();
    m_feelCombo->hidePopup();
    m_dragMarker = -1;
    m_dragTimeSig = false;
    m_leftPress = false;
    m_rightPress = false;
    m_selSweep = false;
    m_multiTrackSweep = false;
    m_dragSelEdge = -1;
    unsetCursor();
    requestQuickUpdate();
}

bool TimeRuler::event(QEvent *event)
{
    const bool handled = QWidget::event(event);
    if (event->type() == QEvent::FontChange)
        refreshGeometry();
    return handled;
}

void TimeRuler::wheelEvent(QWheelEvent *event)
{
    // Same bindings as the roll's notes area: plain wheel zooms the
    // timeline; Shift (or a trackpad's horizontal delta) scrolls it.
    const QPoint delta = wheelDelta(event);
    if (event->modifiers() & Qt::ShiftModifier) {
        m_sv->scrollByPx(-(delta.y() ? delta.y() : delta.x()));
    } else if (delta.x() && !delta.y()) {
        m_sv->scrollByPx(-delta.x());
    } else {
        m_sv->zoomTimelineAtWheel(event, event->position().x() - m_geometry.plotOrigin);
    }
    event->accept();
}

QRect TimeRuler::markerRow() const
{
    return QRect(lyt::space(Space::Zero), lyt::space(Space::Zero), width(), m_markerHeight);
}

QRect TimeRuler::tickRow() const
{
    return QRect(lyt::space(Space::Zero), m_markerHeight, width(), height() - m_markerHeight);
}

int TimeRuler::textBaseline(const QRect &row, const QFontMetrics &metrics) const
{
    return row.top() + (row.height() - metrics.height()) / 2 + metrics.ascent();
}

// 0 = start marker, 1 = end marker, -1 = neither near pos.
int TimeRuler::hitMarker(QPointF pos) const
{
    const MidiTimeline *tl = m_sv->timeline();
    if (!tl || !QRectF(markerRow()).contains(pos))
        return -1;
    const auto markerHitHalfWidth = lyt::space(Space::Two);
    const qreal dpr = devicePixelRatioF();
    if (tl->loopStartTick != UINT64_MAX &&
        std::abs(m_sv->displayX(double(tl->loopStartTick), m_geometry.plotOrigin, dpr) - pos.x()) <=
            markerHitHalfWidth)
        return 0;
    if (tl->loopEndTick != UINT64_MAX &&
        std::abs(m_sv->displayX(double(tl->loopEndTick), m_geometry.plotOrigin, dpr) - pos.x()) <=
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
    const TimeAxis &axis = m_sv->timeAxis();
    const qreal dpr = devicePixelRatioF();
    const QFontMetrics fm(m_signatureFont);
    const auto labelInset = lyt::space(Space::Half);
    const auto add = [&](const TimeAxis::ResolvedTimeSignature &sig) {
        const qreal x = m_sv->displayX(double(sig.tick), m_geometry.plotOrigin, dpr);
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
            const qreal bracketStart =
                m_sv->displayX(double(loopTick), m_geometry.plotOrigin, dpr) + labelInset;
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
    const TimeAxis::ResolvedTimeSignature sig = m_sv->timeAxis().signatureAt(tick);
    *numerator = sig.numerator;
    *denomPow2 = sig.denomPow2;
}

// 0 = selection start edge, 1 = end edge, -1 = neither near pos.
int TimeRuler::hitSelEdge(QPointF pos) const
{
    const auto &sel = m_sv->selectionModel().timeSelection();
    if (!sel.active() || !QRectF(markerRow()).contains(pos))
        return -1;
    const auto markerHitHalfWidth = lyt::space(Space::Two);
    const qreal dpr = devicePixelRatioF();
    if (std::abs(m_sv->displayX(double(sel.startTick), m_geometry.plotOrigin, dpr) - pos.x()) <=
        markerHitHalfWidth)
        return 0;
    if (std::abs(m_sv->displayX(double(sel.endTick), m_geometry.plotOrigin, dpr) - pos.x()) <=
        markerHitHalfWidth)
        return 1;
    return -1;
}

} // namespace songview
