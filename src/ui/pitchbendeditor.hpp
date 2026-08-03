#pragma once

#include "core/songdocument.h"
#include "pitchbendgraph.hpp"
#include "songview.h"

#include <QEvent>
#include <QFocusEvent>
#include <QFrame>
#include <QHideEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPaintEvent>
#include <QPoint>
#include <QPointF>
#include <QPushButton>
#include <QRect>
#include <QSpinBox>
#include <QString>
#include <cstdint>
#include <functional>

namespace songview {

class PitchBendEditor final : public QFrame
{
  public:
    PitchBendEditor(::SongView *songView, SongDocument *document, const DocNote &note,
                    QWidget *parent, std::function<bool(QPointF)> focusNoteUnderCursor);

    void openAt(const QRect &noteGlobal, double noteFraction);

    bool hasEditableSpan() const;
    uint64_t endTick() const;
    QRect graphRect() const;
    QRect modGraphRect() const;

  protected:
    bool event(QEvent *event) override;
    bool eventFilter(QObject *watched, QEvent *event) override;
    void paintEvent(QPaintEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void hideEvent(QHideEvent *event) override;

  private:
    enum class PendingEdit { None, Curve };
    enum class CloseState { Open, Cancel, Closed };

    static constexpr int kPopupWidth = 340;
    static constexpr int kPopupHeight = 432;
    static constexpr int kOuterInset = 8;
    static constexpr int kNoteGap = 8;
    static constexpr int kScreenInset = 8;
    static constexpr int kResetWidth = 60;
    static constexpr int kResetHeight = 26;
    static constexpr int kHeaderHeight = 64;
    static constexpr int kGraphHeight = 184;

    PitchBendGraph *focusedGraph() const;
    uint8_t ccForGraph(const PitchBendGraph *graph) const;
    void undoCurve();
    void resetCurve(PitchBendGraph *graph);
    void snapshotCurves();
    void snapshotCurve(PitchBendGraph *graph, uint8_t cc);
    bool writeController(uint8_t cc, int value, int endValue);
    void writeCurve(PitchBendGraph *graph);
    void markCurvePending(PitchBendGraph *graph);
    void commitCurve();
    void cancelCurve();
    void updateRange(int steps);
    void setBendRange(int range);
    void setLfoSpeed(int speed);
    void close(CloseState state);
    void updateDescription();

    bool noteSpanStillPresent() const;

    ::SongView *m_songView = nullptr;
    SongDocument *m_document = nullptr;
    DocNote m_noteSnapshot;
    int m_engineTrack = -1;
    uint64_t m_startTick = 0;
    uint64_t m_endTick = 0;
    bool m_unterminated = false;
    int m_bendRange = 2;
    int m_endRange = 2;
    int m_lfoSpeed = 22;
    int m_endLfoSpeed = 22;
    PitchBendGraph *m_pitchGraph = nullptr;
    PitchBendGraph *m_modGraph = nullptr;
    QPushButton *m_pitchResetButton = nullptr;
    QPushButton *m_modResetButton = nullptr;
    QSpinBox *m_bendRangeSpin = nullptr;
    QSpinBox *m_lfoSpeedSpin = nullptr;
    PitchBendGraph *m_pendingGraph = nullptr;
    PendingEdit m_pending = PendingEdit::None;
    CloseState m_closeState = CloseState::Open;
    std::function<bool(QPointF)> m_focusNoteUnderCursor;
};
} // namespace songview
