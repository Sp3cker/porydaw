#pragma once

#include "core/songdocument.h"
#include "ui/curvegraph/curvegraph.hpp"
#include "ui/songview/pitchenvelopemapping.h"

#include <QPointer>
#include <QWidget>
#include <cstdint>
#include <optional>
#include <vector>

class QHideEvent;
class QLabel;
class QResizeEvent;
class SongView;

namespace songview {

class PitchEnvelopeHost final : public QWidget
{
  public:
    explicit PitchEnvelopeHost(::SongView *songView, QWidget *parent = nullptr);

    void setEnvelopeVisible(bool visible);
    void refresh();
    void refreshGrid();
    void cancelGesture();

  protected:
    void paintEvent(QPaintEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void hideEvent(QHideEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;

  private:
    struct EnvelopeSession {
        int engineTrack = -1;
        std::vector<pitch_envelope::Projection> projections;
        uint64_t templateSourceTick = 0;
        uint64_t templateWindowEndTick = 0;
        uint64_t templateEndTick = 0;
        int templateBendRange = 0;
        uint64_t templateWindowTicks = pitch_envelope::kDefaultWindowTicks;
        uint64_t documentRevision = 0;
        bool gestureDirty = false;
    };

    std::optional<int> selectedPrimaryTrack() const;
    std::vector<pitch_envelope::Projection> eligibleProjectionsForTrack(int engineTrack) const;
    int activeBendRange(int engineTrack, uint64_t tick) const;
    struct EditingGrid {
        uint64_t cellTicks = 1;
        uint64_t anchorTick = 0;
        uint64_t endTick = 0;
    };

    EditingGrid editingGridAt(uint64_t tick, CurveGraph::Sampling sampling) const;
    uint64_t snappedGridTick(uint64_t tick, CurveGraph::Sampling sampling) const;
    uint64_t nextGridTick(uint64_t tick, CurveGraph::Sampling sampling) const;
    uint64_t lastEditableGridTick(CurveGraph::Sampling sampling) const;
    std::vector<double> gridLines() const;
    CurveGraph::CurveSpec makeGraphSpec() const;
    void applyReadOnlyState(const QString &text);
    void loadCurve();
    void commitCurve();
    void updateStatus(const QString &text);

    QPointer<::SongView> m_songView;
    CurveGraph *m_graph = nullptr;
    QLabel *m_status = nullptr;
    std::optional<EnvelopeSession> m_session;
};

} // namespace songview
