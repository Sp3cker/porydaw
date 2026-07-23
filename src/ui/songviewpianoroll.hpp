#pragma once

#include <QWidget>

#include <memory>

class QResizeEvent;
class SongView;

namespace songview {

class PianoRoll final : public QWidget
{
public:
    explicit PianoRoll(SongView *songView);
    ~PianoRoll() override;
    void refresh();

    bool gestureActive() const;

protected:
    void resizeEvent(QResizeEvent *event) override;

private:
    class State;

    std::unique_ptr<State> m_state;
};

} // namespace songview
