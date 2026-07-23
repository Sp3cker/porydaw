#pragma once

#include <QWidget>

#include <cstdint>
#include <functional>
#include <memory>

class QPainter;
class QRect;
class QResizeEvent;
class SongView;

namespace songview {

class TimeRuler final : public QWidget
{
public:
    explicit TimeRuler(SongView *songView);
    ~TimeRuler() override;

    void syncGridControls();
    bool gestureActive() const;
    void refresh();

protected:
    void resizeEvent(QResizeEvent *event) override;

private:
    class State;

    std::unique_ptr<State> m_state;
};

namespace time_ruler_detail {

void drawOverlays(QPainter &painter, const SongView *songView, const QRect &rect,
                  int origin, bool timeSelectionCovered);
void forEachSubGridLine(const SongView *songView, double startTick, double endTick,
                        const std::function<void(uint64_t, int)> &callback);

} // namespace time_ruler_detail

} // namespace songview
