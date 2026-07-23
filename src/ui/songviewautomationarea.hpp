#pragma once

#include <QHash>
#include <QPoint>
#include <QSize>
#include <QString>
#include <QWidget>

#include <memory>

class QScrollArea;
class SongView;

namespace songview {


class AutomationArea final : public QWidget
{
public:
    AutomationArea(SongView *songView, QScrollArea *scrollArea);
    ~AutomationArea() override;

    QSize minimumSizeHint() const override;
    void showTimeSelectionContextMenu(const QPoint &globalPosition);

    int laneHeight() const;
    const QHash<QString, int> &rowHeightOverrides() const;
    bool gestureActive() const;
    void setViewHeights(int laneHeight, const QHash<QString, int> &overrides);
    void rebuildRows();
    void refresh();

protected:
    void resizeEvent(QResizeEvent *event) override;

private:
    class State;

    std::unique_ptr<State> m_state;
};

} // namespace songview
