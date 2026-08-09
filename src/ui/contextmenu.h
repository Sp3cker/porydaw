#pragma once

#include <functional>

#include <QMenu>
#include <QPointF>

class QMouseEvent;

namespace ui {

// Kept in its own file so SongView and the EditorDrawer can share the same
// context-menu interaction and popup-style behavior.
class ContextMenu : public QMenu
{
  public:
    explicit ContextMenu(QWidget *parent = nullptr,
                         std::function<bool(QPointF)> onOutsideRightClick = {});

    void setOutsideRightClickHandler(std::function<bool(QPointF)> onOutsideRightClick);

  protected:
    void mousePressEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;

  private:
    std::function<bool(QPointF)> m_onOutsideRightClick;
    bool m_handledOutsideRightPress = false;
};

} // namespace ui
