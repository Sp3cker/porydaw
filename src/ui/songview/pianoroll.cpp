// ---------------------------------------------------------------- PianoRoll lifecycle

#include "ui/songview/pianoroll.h"

#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/pitchbendeditor.hpp"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/typography.h"

#include <QAction>
#include <QEvent>
#include <QMenu>
#include <QWheelEvent>

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
    : QWidget(sv)
    , m_sv(sv)
    , m_geometry(PianoRollGeometry::resolve())
    , m_cursors(loadMidiCursors(devicePixelRatioF(), m_geometry.midiCursorExtent))
{
    setObjectName(QStringLiteral("pianoRoll")); // findChild for tests
    setMinimumHeight(m_geometry.minimumVisiblePianoRollHeight);
    setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
    setMouseTracking(true);
    setFocusPolicy(Qt::ClickFocus);
    rebuildFontCache();
    m_noteMenu =
        new NoteContextMenu(this, [this](QPointF globalPos) { return moveNoteMenu(globalPos); });
    connect(m_noteMenu, &QMenu::triggered, this,
            [this](QAction *action) { handleNoteMenuChoice(m_noteMenu->handleAction(action)); });
}

void PianoRoll::requestQuickUpdate(PianoRollQuickDirtySet dirty)
{
    if (dirty == PianoRollQuickDirty::None)
        return;
    m_sv->requestPianoRollQuickUpdate(dirty);
}

void PianoRoll::rebuildFontCache()
{
    m_fixedNoteNameFont = typography::noteName(font());
    m_fixedNoteNameFont.setPixelSize(
        std::max(lyt::singlePixel(), m_fixedNoteNameFont.pixelSize() - 2 * lyt::singlePixel()));
    const QFontMetrics noteMetrics(m_fixedNoteNameFont);
    m_fixedNoteNameOccupiedHeight = noteMetrics.ascent() + noteMetrics.descent();

    m_keyboardHoverChipFont = typography::caption(font());
    const QFontMetrics hoverMetrics(m_keyboardHoverChipFont);
    m_keyboardHoverChipHeight = hoverMetrics.height() + m_geometry.keyboardHoverChipVerticalPadding;
    for (int key = 0; key < int(m_keyboardHoverNameWidths.size()); ++key)
        m_keyboardHoverNameWidths[std::size_t(key)] =
            hoverMetrics.horizontalAdvance(midiKeyName(key));

    refreshTextLayout();
}

void PianoRoll::refreshTextLayout()
{
    m_velocityLabelFont = typography::fitted(font(), velocityLabelHeight());
    if (m_velocityLabelFont) {
        m_velocityLabelFont->setPixelSize(
            std::max(lyt::singlePixel(), m_velocityLabelFont->pixelSize() - lyt::singlePixel()));
    }

    const int noteTextHeight =
        int(std::floor(m_sv->keyHeight() - physicalPixel() - 2.0 * lyt::space(Space::Half)));
    if (m_sv->keyHeight() >= kNoteNameMinKeyH && m_fixedNoteNameOccupiedHeight <= noteTextHeight) {
        m_noteNameFont = m_fixedNoteNameFont;
    } else {
        m_noteNameFont.reset();
    }

    m_keyboardLabelFont = typography::fitted(font(), int(std::lround(m_sv->keyHeight())));
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
    setCursor(Qt::ArrowCursor);
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

bool PianoRoll::event(QEvent *event)
{
    const auto type = event->type();
    const bool losesFocus =
        type == QEvent::Hide || type == QEvent::WindowDeactivate || type == QEvent::FocusOut;
    if ((losesFocus || type == QEvent::UngrabMouse) &&
        (m_leftDrag == LeftDrag::Velocity || m_leftDrag == LeftDrag::PendingVelocity))
        cancelVelocityInteraction();
    const bool handled = QWidget::event(event);
    switch (type) {
    case QEvent::PaletteChange:
    case QEvent::ApplicationPaletteChange:
    case QEvent::StyleChange:
    case QEvent::ThemeChange:
    case QEvent::DevicePixelRatioChange:
        m_geometry = PianoRollGeometry::resolve();
        setMinimumHeight(m_geometry.minimumVisiblePianoRollHeight);
        m_cursors = loadMidiCursors(devicePixelRatioF(), m_geometry.midiCursorExtent);
        m_rowEdgesValid = false;
        refreshTextLayout();
        m_sv->syncTimelineQuickAppearance();
        break;
    default:
        break;
    }
    return handled;
}

void PianoRoll::wheelEvent(QWheelEvent *event)
{
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
    } else if (event->position().x() < m_geometry.pianoKeyboardWidth) {
        m_sv->scrollRollBy(-delta.y() / 2.0);
    } else {
        m_sv->zoomTimelineAtWheel(event, event->position().x() - m_geometry.pianoKeyboardWidth);
    }
    event->accept();
}

} // namespace songview
