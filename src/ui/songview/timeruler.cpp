// ---------------------------------------------------------------- TimeRuler

#include "ui/songview/timeruler.h"

#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/grid.h"
#include "ui/songview/quick/promptappearance.h"
#include "ui/songview/quick/quickmenumodel.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/retirehostmenu.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <QFontMetrics>
#include <QGuiApplication>
#include <QUrl>
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
    appearance.insert(
        QStringLiteral("font"),
        QVariant::fromValue(m_inputHost ? m_inputHost->font() : QGuiApplication::font()));
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

// Persistent typed-menu adapters over the shared canvas popup session;
// created on first open and reused. The grid-control menus and the ruler
// loop menu may each be first, so the host, all three row models, and
// their activation/cancellation wiring are built together here.
void TimeRuler::ensureMenuAdapters()
{
    if (m_menuHost)
        return;
    m_menuHost = new QuickMenuHost(this);
    m_rulerMenuModel = new QuickMenuModel(this);
    m_divisionModel = new QuickMenuModel(this);
    m_feelModel = new QuickMenuModel(this);
    // activated() arrives after the host closed the session, so the
    // setters run against a settled view; the completion signal then
    // hands focus back to the invoking control (notifyGridMenuChoice).
    connect(m_divisionModel, &QuickMenuModel::activated, this, [this](int id) {
        m_owner.setGridMinDenom(id);
        notifyGridMenuChoice(true);
    });
    connect(m_feelModel, &QuickMenuModel::activated, this, [this](int id) {
        m_owner.setGridFeel(static_cast<GridFeel>(id));
        notifyGridMenuChoice(false);
    });
    // Every ruler-menu row is an action projection triggered through the
    // host, so activation arrives as actionActivated() — used only for
    // terminal focus completion, and only when no follow-on popup (the
    // time-signature form) already owns the session.
    connect(m_menuHost, &QuickMenuHost::actionActivated, this, [this](QAction *) {
        restoreFocusUnlessFormOpen(m_owner, [this] { restoreRulerFocus(); });
    });
    // Selection/document/cursor transitions retire only this ruler's context
    // menu: the open session must belong to this ruler's menu host AND be
    // rooted at the ruler menu model, so the division/feel grid menus sharing
    // the host and the time-signature form owning the session directly keep
    // their independent lifetimes. Normal transitions hand focus back; the
    // teardown paths keep closePopups()'s no-focus policy.
    const auto retireRulerMenu = [this](bool restoreFocus) {
        TimelineQuickView *const quick = m_owner.quickView();
        retireHostMenu(quick ? quick->popupSession() : nullptr, m_menuHost, m_rulerMenuModel,
                       restoreFocus);
    };
    connect(&m_owner, &SongView::contextMenusInvalidated, this, retireRulerMenu);
    // A committed cursor move retires the positional menu with the ordinary
    // focus policy; the drag preview (setEditCursorTick) emits nothing and
    // dismisses nothing.
    connect(&m_owner, &SongView::editCursorMoved, this,
            [retireRulerMenu](Tick) { retireRulerMenu(/*restoreFocus=*/true); });
}

void restoreFocusUnlessFormOpen(SongView &owner, const std::function<void()> &restore)
{
    if (const TimelineQuickView *const quick = owner.quickView()) {
        if (const QuickPopupSession *const session = quick->popupSession();
            session && session->isOpen())
            return;
    }
    restore();
}

void TimeRuler::openGridMenu(QPointF position, bool division)
{
    if (!m_inputHost || !m_gridControlsEnabled)
        return;
    TimelineQuickView *const quick = m_owner.quickView();
    QuickPopupSession *const session = quick ? quick->popupSession() : nullptr;
    if (!session)
        return;

    // Persistent typed-menu adapters over the shared canvas popup session,
    // created on first open — from either menu entry — and reused; the
    // session binds once per open.
    ensureMenuAdapters();
    m_menuHost->setPopupSession(session);

    // Rows rebuilt at open so the check marks mirror the live grid; ids
    // carry the raw values the owner setters consume.
    std::vector<QuickMenuItem> rows;
    const auto addRow = [&rows](int id, QString text, bool checked) {
        QuickMenuItem item;
        item.id = id;
        item.text = std::move(text);
        item.checkable = true;
        item.checked = checked;
        rows.push_back(std::move(item));
    };
    if (division) {
        rows.reserve(5);
        for (const int denom : {0, 4, 8, 16, 32})
            addRow(denom, gridDivisionText(denom), m_grid.minDenom() == denom);
        m_divisionModel->setItems(std::move(rows));
        m_menuHost->open(m_divisionModel, position);
    } else {
        rows.reserve(2);
        for (const GridFeel feel : {GridFeel::Straight, GridFeel::Triplet})
            addRow(static_cast<int>(feel),
                   feel == GridFeel::Triplet ? SongView::tr("Triplet") : SongView::tr("Straight"),
                   m_grid.feel() == feel);
        m_feelModel->setItems(std::move(rows));
        m_menuHost->open(m_feelModel, position);
    }
}

// A plain ordinary close() cannot give back the focus the in-scene menu
// displaced, so every successful choice reports which menu completed and
// the matching QML control restores itself. Dismissal keeps the session's
// own restoreFocus path; a command that opened a new popup keeps focus.
void TimeRuler::notifyGridMenuChoice(bool division)
{
    if (const TimelineQuickView *const quick = m_owner.quickView()) {
        if (const QuickPopupSession *const session = quick->popupSession();
            session && session->isOpen())
            return;
    }
    emit gridMenuActivated(division);
}

int TimeRuler::timeSigPromptInitialNumerator() const noexcept
{
    return m_pendingTimeSigPrompt ? m_pendingTimeSigPrompt->initialNumerator
                                  : timeSigPromptMinimumNumerator();
}

int TimeRuler::timeSigPromptInitialDenominatorPow2() const noexcept
{
    return m_pendingTimeSigPrompt ? m_pendingTimeSigPrompt->initialDenominatorPow2
                                  : timeSigPromptMinimumDenominatorPow2();
}

QString TimeRuler::timeSigPromptTitle() const
{
    return SongView::tr("Time Signature");
}

QString TimeRuler::timeSigPromptLabel() const
{
    return SongView::tr("Numerator (1-32):");
}

QVariantMap TimeRuler::timeSigPromptAppearance() const
{
    return promptDialogAppearance(m_inputHost ? m_inputHost->font() : QGuiApplication::font());
}

void TimeRuler::openTimeSigPrompt(Tick tick, int numerator, int denominatorPow2)
{
    SongDocument *const document = m_owner.document();
    TimelineQuickView *const quick = m_owner.quickView();
    QuickPopupSession *const session = quick ? quick->popupSession() : nullptr;
    if (!document || !session)
        return;

    // Replacement ends the active shared-popup session before this bridge
    // publishes a new guarded target.
    session->cancel(/*restoreFocus=*/false);
    if (m_pendingTimeSigPrompt)
        cancelTimeSigPromptWithoutFocus();

    PendingTimeSigPrompt pending;
    pending.document = document;
    pending.documentRevision = document->revision();
    pending.tick = tick;
    pending.initialNumerator =
        std::clamp(numerator, timeSigPromptMinimumNumerator(), timeSigPromptMaximumNumerator());
    pending.initialDenominatorPow2 =
        std::clamp(denominatorPow2, timeSigPromptMinimumDenominatorPow2(),
                   timeSigPromptMaximumDenominatorPow2());
    m_pendingTimeSigPrompt = std::move(pending);
    emit timeSigPromptChanged();

    QObject::disconnect(m_timeSigPromptCancellation);
    m_timeSigPromptCancellation =
        connect(session, &QuickPopupSession::cancelled, this,
                [this](bool restoreFocus) { clearTimeSigPrompt(restoreFocus); });
    if (!session->openForm(QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/TimeSignaturePrompt.qml")),
                           this)) {
        clearTimeSigPrompt(/*restoreFocus=*/true);
    }
}

void TimeRuler::acceptTimeSigPrompt(int numerator, int denominatorPow2)
{
    if (numerator < timeSigPromptMinimumNumerator() ||
        numerator > timeSigPromptMaximumNumerator() ||
        denominatorPow2 < timeSigPromptMinimumDenominatorPow2() ||
        denominatorPow2 > timeSigPromptMaximumDenominatorPow2() || !m_pendingTimeSigPrompt) {
        return;
    }

    const PendingTimeSigPrompt pending = std::move(*m_pendingTimeSigPrompt);
    m_pendingTimeSigPrompt.reset(); // Never expose a target while mutating its document.
    QObject::disconnect(m_timeSigPromptCancellation);
    m_timeSigPromptCancellation = {};
    emit timeSigPromptChanged();

    if (TimelineQuickView *const quick = m_owner.quickView()) {
        if (QuickPopupSession *const session = quick->popupSession();
            session && session->owns(this)) {
            session->close();
        }
    }
    SongDocument *const document = m_owner.document();
    if (document == pending.document.data() && document->revision() == pending.documentRevision &&
        (numerator != pending.initialNumerator ||
         denominatorPow2 != pending.initialDenominatorPow2)) {
        document->setTimeSig(pending.tick, numerator, denominatorPow2);
    }
    restoreRulerFocus();
}

void TimeRuler::cancelTimeSigPrompt()
{
    if (!m_pendingTimeSigPrompt)
        return;
    TimelineQuickView *const quick = m_owner.quickView();
    QuickPopupSession *const session = quick ? quick->popupSession() : nullptr;
    const bool ownsSession = session && session->owns(this);
    if (ownsSession)
        session->cancel();
    if (m_pendingTimeSigPrompt)
        clearTimeSigPrompt(ownsSession);
}

void TimeRuler::cancelTimeSigPromptWithoutFocus()
{
    TimelineQuickView *const quick = m_owner.quickView();
    QuickPopupSession *const session = quick ? quick->popupSession() : nullptr;
    const bool ownsSession = m_pendingTimeSigPrompt && session && session->owns(this);
    m_pendingTimeSigPrompt.reset();
    QObject::disconnect(m_timeSigPromptCancellation);
    m_timeSigPromptCancellation = {};
    if (ownsSession)
        session->cancel(/*restoreFocus=*/false);
}

void TimeRuler::clearTimeSigPrompt(bool restoreFocus)
{
    const bool hadPending = m_pendingTimeSigPrompt.has_value();
    m_pendingTimeSigPrompt.reset();
    QObject::disconnect(m_timeSigPromptCancellation);
    m_timeSigPromptCancellation = {};
    if (hadPending)
        emit timeSigPromptChanged();
    if (restoreFocus)
        restoreRulerFocus();
}

void TimeRuler::restoreRulerFocus()
{
    m_owner.focusTimelineBand(TimelineBand::Ruler, Qt::OtherFocusReason);
}

void TimeRuler::closePopups()
{
    // Readiness loss, document swap, and host teardown cancel the typed
    // menus (grid controls, ruler loop menu) only when this ruler's host
    // owns the session — and without handing focus back to a view that may
    // be going away.
    if (m_menuHost) {
        if (TimelineQuickView *const quick = m_owner.quickView()) {
            if (QuickPopupSession *const session = quick->popupSession();
                session && session->owns(m_menuHost))
                session->cancel(/*restoreFocus=*/false);
        }
    }
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
    cancelTimeSigPromptWithoutFocus();
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
    if (tl->loopStartTick != CoreTimeDefaults::kNoTick &&
        std::abs(m_camera.displayX(double(tl->loopStartTick), 0.0, dpr) - pos.x()) <=
            markerHitHalfWidth)
        return 0;
    if (tl->loopEndTick != CoreTimeDefaults::kNoTick &&
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
    const Tick loops[2] = {axis.loopStartTick(), axis.loopEndTick()};
    const qreal bracketWidth = fm.horizontalAdvance(QStringLiteral("["));
    for (SigChip &chip : chips) {
        for (Tick loopTick : loops) {
            if (loopTick == CoreTimeDefaults::kNoTick)
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
bool TimeRuler::hitTimeSigChip(QPointF pos, Tick *tick, int *numerator, int *denomPow2,
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
void TimeRuler::sigAtTick(Tick tick, int *numerator, int *denomPow2) const
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
