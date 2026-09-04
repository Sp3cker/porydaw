// ---------------------------------------------------------------- PianoRoll lifecycle

#include "ui/songview/pianoroll.h"

#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/pitchbendeditor.hpp"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/typography.h"

#include <QAction>
#include <QMenu>
#include <QPointer>

#include <QFontMetrics>
#include <algorithm>
#include <cmath>
#include <utility>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview::pianoroll_detail {
using namespace songview::detail;

NoteContextMenu::NoteContextMenu(QWidget *parent, std::function<bool(QPointF)> onOutsideRightClick)
    : ui::ContextMenu(parent, std::move(onOutsideRightClick))
{
    m_velocityAction = addAction(QString());
    addSeparator();
    // The shortcut is text only: MainWindow's native Edit menu owns Copy.
    m_copyAction = addAction(SongView::tr("Copy"));
    m_cutAction = addAction(SongView::tr("Cut"));
    m_deleteAction = addAction(SongView::tr("Delete"));
}

void NoteContextMenu::showMenuAt(QPoint globalPos, int velocity)
{
    m_velocityAction->setText(SongView::tr("Set velocity… (%1)").arg(velocity));
    m_copyAction->setText(contextActionText(SongView::tr("Copy"), QStringLiteral("roll.copy")));
    m_cutAction->setText(contextActionText(SongView::tr("Cut"), QStringLiteral("roll.cut")));
    popup(globalPos);
}

NoteMenuChoice NoteContextMenu::handleAction(QAction *action) const
{
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

} // namespace songview::pianoroll_detail

namespace songview {
using namespace songview::detail;
using namespace songview::pianoroll_detail;

PianoRoll::PianoRoll(SongView *sv)
    : m_sv(sv)
    , m_camera(sv->camera())
    , m_grid(sv->grid())
    , m_geometry(PianoRollGeometry::resolve(sv->pianoKeyboardWidth()))
{
    setObjectName(QStringLiteral("pianoRoll")); // findChild for tests
    m_fixedNoteNameFont = typography::noteName(sv->font());
    m_fixedNoteNameFont.setPixelSize(
        std::max(lyt::singlePixel(), m_fixedNoteNameFont.pixelSize() - 2 * lyt::singlePixel()));
    m_fixedNoteNameMetrics = QFontMetricsF(m_fixedNoteNameFont);
    const QFontMetrics noteMetrics(m_fixedNoteNameFont);
    m_fixedNoteNameOccupiedHeight = noteMetrics.ascent() + noteMetrics.descent();

    m_keyboardHoverChipFont = typography::caption(sv->font());
    const QFontMetrics hoverMetrics(m_keyboardHoverChipFont);
    m_keyboardHoverChipHeight = hoverMetrics.height() + m_geometry.keyboardHoverChipVerticalPadding;
    for (int key = 0; key < int(m_keyboardHoverNameWidths.size()); ++key)
        m_keyboardHoverNameWidths[std::size_t(key)] =
            hoverMetrics.horizontalAdvance(midiKeyName(key));

    const QPointer<PianoRoll> guardedThis(this);
    m_noteMenu = new NoteContextMenu(sv, [guardedThis](QPointF globalPos) {
        return guardedThis && guardedThis->moveNoteMenu(globalPos);
    });
    connect(m_noteMenu, &QMenu::triggered, this,
            [this](QAction *action) { handleNoteMenuChoice(m_noteMenu->handleAction(action)); });
}

void PianoRoll::requestQuickUpdate(PianoRollQuickDirtySet dirty)
{
    if (dirty == PianoRollQuickDirty::None)
        return;
    m_sv->requestPianoRollQuickUpdate(dirty);
}

QRectF PianoRoll::bounds() const
{
    Q_ASSERT(m_inputHost);
    return m_inputHost ? m_inputHost->bounds() : QRectF{};
}

qreal PianoRoll::devicePixelRatio() const
{
    Q_ASSERT(m_inputHost);
    return m_inputHost ? m_inputHost->devicePixelRatio() : 1.0;
}

QFont PianoRoll::font() const
{
    Q_ASSERT(m_inputHost);
    return m_inputHost ? m_inputHost->font() : QFont{};
}

QPalette PianoRoll::palette() const
{
    Q_ASSERT(m_inputHost);
    return m_inputHost ? m_inputHost->palette() : QPalette{};
}

void PianoRoll::attachInputHost(TimelineInputHost &host)
{
    Q_ASSERT(!m_inputHost);
    m_inputHost = &host;
    m_cursors = loadMidiCursors(host.devicePixelRatio(), m_geometry.midiCursorExtent);
    refreshTextLayout();
    m_rowEdgesValid = false;
    requestQuickUpdate(PianoRollQuickDirty::All);
}

void PianoRoll::detachInputHost(TimelineInputHost &host)
{
    Q_ASSERT(m_inputHost == &host);
    if (m_inputHost != &host)
        return;
    cancelTransientInput();
    m_curPosValid = false;
    host.clearCursor();
    m_inputHost = nullptr;
}

void PianoRoll::hostAppearanceChanged()
{
    if (!m_inputHost)
        return;
    m_cursors = loadMidiCursors(m_inputHost->devicePixelRatio(), m_geometry.midiCursorExtent);
    m_rowEdgesValid = false;
    refreshTextLayout();
    requestQuickUpdate(PianoRollQuickDirty::All);
}

void PianoRoll::refreshTextLayout()
{
    m_velocityLabelFont = typography::fitted(font(), velocityLabelHeight());
    if (m_velocityLabelFont) {
        m_velocityLabelFont->setPixelSize(
            std::max(lyt::singlePixel(), m_velocityLabelFont->pixelSize() - lyt::singlePixel()));
    }

    const int noteTextHeight =
        int(std::floor(m_camera.keyHeight() - physicalPixel() - 2.0 * lyt::space(Space::Half)));
    if (m_camera.keyHeight() >= kNoteNameMinKeyH &&
        m_fixedNoteNameOccupiedHeight <= noteTextHeight) {
        m_noteNameFont = m_fixedNoteNameFont;
    } else {
        m_noteNameFont.reset();
    }

    m_keyboardLabelFont = typography::fitted(font(), int(std::lround(m_camera.keyHeight())));
}

bool PianoRoll::gestureActive() const
{
    return m_panning || dragLive() || m_leftDrag == LeftDrag::PendingDraw ||
           m_rightDrag != RightDrag::None || m_kbdKey >= 0 ||
           (m_bendPopup && m_bendPopup->isVisible());
}

void PianoRoll::cancelPitchBendPopup()
{
    if (m_bendPopup && m_bendPopup->isVisible())
        m_bendPopup->cancelAndClose();
}

void PianoRoll::cancelTransientInput()
{
    if (m_bendPopup && m_bendPopup->isVisible())
        m_bendPopup->cancelAndCloseWithoutFocus();
    if (m_leftDrag == LeftDrag::Velocity || m_leftDrag == LeftDrag::PendingVelocity)
        cancelVelocityInteraction();
    if (m_kbdKey >= 0)
        endKbdAudition();
    stopNoteAudition();
    if (m_soundingKey >= 0)
        auditionKey(m_soundingKey, 0);
    stopBandAuditions();
    if (m_panHost)
        m_panHost->clearCursor();
    m_panHost = nullptr;
    m_panning = false;
    m_panPos = {};
    m_leftDrag = LeftDrag::None;
    m_rightDrag = RightDrag::None;
    m_pressPos = {};
    m_curPos = {};
    m_pressTick = 0.0;
    m_pressKey = 0;
    m_gripTick = 0;
    m_gripOpposite = 0;
    m_dTick = 0;
    m_dKey = 0;
    m_dDur = 0;
    m_dVel = 0;
    m_drawTick = 0;
    m_drawDur = 0;
    m_drawKey = 0;
    m_drawAnchor = 0;
    m_rightShift = false;
    m_rightAnchorTick = 0;
    m_rightHit = false;
    m_rightHitId = {};
    m_velAnchor = {};
    m_velAudEff = -1;
    m_velModMods = Qt::NoModifier;
    m_kbdKey = -1;
    m_soundingKey = -1;
    setHoverKey(-1);
    if (m_inputHost)
        m_inputHost->clearCursor();
    completeProjectionGesture();
    requestQuickUpdate(cDrawCommitDirty);
}

void PianoRoll::cancelVelocityInteraction()
{
    if (m_leftDrag != LeftDrag::Velocity && m_leftDrag != LeftDrag::PendingVelocity)
        return;
    clearLiveDragToken();
    m_leftDrag = LeftDrag::None;
    m_dVel = 0;
    m_velModMods = Qt::NoModifier;
    m_velAnchor = {};
    m_velAudEff = -1;
    if (m_auditioned) {
        auditionKey(0, 0);
        m_auditioned = false;
    }
    m_sv->cancelVelocityGesture();
    requestQuickUpdate(PianoRollQuickDirty::NoteFills | PianoRollQuickDirty::NoteText);
}

bool PianoRoll::wheel(const TimelineWheelInput &input)
{
    // Reaper-style bindings: plain wheel over the notes area zooms the
    // timeline, while the gutter scrolls the note range. Ctrl+wheel zooms
    // the key height (the track-height analog); Shift (or a trackpad's
    // horizontal delta) scrolls horizontally.
    const QPoint delta = input.pixelDelta.isNull() ? input.angleDelta : input.pixelDelta;
    const int d = delta.y() ? delta.y() : delta.x();
    if (input.modifiers & Qt::ControlModifier) {
        m_sv->zoomKeyHeight(input);
    } else if (input.modifiers & Qt::ShiftModifier) {
        m_sv->scrollByPx(-d);
    } else if (delta.x() && !delta.y()) {
        m_sv->scrollByPx(-delta.x());
    } else if (input.surface == TimelineInputSurface::Gutter) {
        m_sv->scrollRollBy(-delta.y() / 2.0);
    } else {
        m_sv->zoomTimelineAtWheel(input, input.position.x());
    }
    return true;
}

} // namespace songview
