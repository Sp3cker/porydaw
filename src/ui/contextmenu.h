#pragma once

#include <QMenu>
#include <QPointF>
#include <functional>

class QMouseEvent;

namespace ui {

// Popup menu with the retarget gesture the roll's note menu established: a
// right-click outside the popup while it is open re-aims the menu in one
// gesture instead of spending the click on dismissal. Extracted from
// SongView's NoteContextMenu (ported alongside the automation point menu
// from specker/cleanup/psg-velocity-history-pr) so both menus share the
// interaction and the popup-style fix.
class ContextMenu : public QMenu
{
  public:
    // Called when an outside right-click may move the menu to another
    // target; returns false when the click hit nothing, so the press falls
    // through to QMenu (which dismisses the popup like any outside click).
    explicit ContextMenu(QWidget *parent, std::function<bool(QPointF)> onOutsideRightClick);

  protected:
    void mousePressEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;

  private:
    std::function<bool(QPointF)> m_onOutsideRightClick;
    bool m_handledRetargetPress = false;
};

} // namespace ui
