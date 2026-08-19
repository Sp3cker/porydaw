// ---------------------------------------------------------------- PianoRoll lifecycle

#include "ui/songview/pianoroll.h"

#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/pitchbendeditor.hpp"
#include "ui/songview.h"
#include "ui/songview/detail.h"

#include <QAction>
#include <QEvent>
#include <QMenu>
#include <QWheelEvent>

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
    // Display-only hints (the real bindings live in keyPressEvent):
    // mirror the keymap so a rebind doesn't leave the menu lying.
    const auto &keys = keymap::Registry::instance();
    m_copyAction = addAction(SongView::tr("Copy"));
    m_copyAction->setShortcut(keys.bindings(QStringLiteral("roll.copy")).value(0));
    m_cutAction = addAction(SongView::tr("Cut"));
    m_cutAction->setShortcut(keys.bindings(QStringLiteral("roll.cut")).value(0));
    m_deleteAction = addAction(SongView::tr("Delete"));
}

void NoteContextMenu::showMenuAt(QPoint globalPos, int velocity)
{
    m_velocityAction->setText(SongView::tr("Set velocity… (%1)").arg(velocity));
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
    : TimelineSurface(sv)
    , m_sv(sv)
    , m_geometry(PianoRollGeometry::resolve())
    , m_cursors(loadMidiCursors(devicePixelRatioF(), m_geometry.midiCursorExtent))
{
    setObjectName(QStringLiteral("pianoRoll")); // findChild for tests
    setMinimumHeight(m_geometry.minimumVisiblePianoRollHeight);
    setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
    setMouseTracking(true);
    setFocusPolicy(Qt::ClickFocus);
    m_noteMenu =
        new NoteContextMenu(this, [this](QPointF globalPos) { return moveNoteMenu(globalPos); });
    connect(m_noteMenu, &QMenu::triggered, this,
            [this](QAction *action) { handleNoteMenuChoice(m_noteMenu->handleAction(action)); });
}

bool PianoRoll::gestureActive() const
{
    return m_panning || m_drag != Drag::None || m_leftPress || m_rightPress || m_kbdKey >= 0 ||
           (m_bendPopup && m_bendPopup->isVisible());
}

void PianoRoll::cancelPitchBendPopup()
{
    if (m_bendPopup && m_bendPopup->isVisible())
        m_bendPopup->cancelAndClose();
}

void PianoRoll::cancelVelocityInteraction()
{
    if (m_drag != Drag::Velocity && !m_velModPress)
        return;
    m_drag = Drag::None;
    m_dVel = 0;
    m_velModPress = false;
    m_modifierVelocityDrag = false;
    m_velModMods = Qt::NoModifier;
    m_velAnchor = {};
    m_velAudEff = -1;
    if (m_auditioned) {
        auditionKey(0, 0);
        m_auditioned = false;
    }
    m_sv->cancelVelocityGesture();
    invalidateContent();
}

bool PianoRoll::event(QEvent *event)
{
    const auto type = event->type();
    const bool losesFocus =
        type == QEvent::Hide || type == QEvent::WindowDeactivate || type == QEvent::FocusOut;
    if (losesFocus) {
        m_suppressNextVelocitySelectionAdd = false;
        m_lastModifierVelocityDragNote = {};
    }
    if ((losesFocus || type == QEvent::UngrabMouse) && (m_drag == Drag::Velocity || m_velModPress))
        cancelVelocityInteraction();
    const bool handled = TimelineSurface::event(event);
    if (event->type() == QEvent::FontChange) {
        m_geometry = PianoRollGeometry::resolve();
        setMinimumHeight(m_geometry.minimumVisiblePianoRollHeight);
        m_cursors = loadMidiCursors(devicePixelRatioF(), m_geometry.midiCursorExtent);
        m_rowEdgesValid = false;
        invalidateContent();
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
