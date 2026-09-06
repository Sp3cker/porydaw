#pragma once

#include "core/songdocument.h"
#include "pitchbendgraph.hpp"

#include <QMetaType>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QQuickView>
#include <QRect>
#include <QVariantMap>
#include <cstdint>
#include <functional>

class QKeyEvent;
class SongView;

namespace songview {

// Session object backing the transient Qt Quick pitch-bend popup. Owns the
// document snapshots, pending commit/cancel, controller values, cached chrome
// (geometry + appearance) and the lazily constructed QQuickView window; the
// window/filter/arbitration implementation lives in pitchbendeditor_window.cpp.
class PitchBendEditor final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int bendRange READ bendRange NOTIFY controllerValuesChanged)
    Q_PROPERTY(int lfoSpeed READ lfoSpeed NOTIFY controllerValuesChanged)
    Q_PROPERTY(QString description READ description NOTIFY appearanceChanged)
    Q_PROPERTY(QString noteDescription READ noteDescription NOTIFY appearanceChanged)
    Q_PROPERTY(QVariantMap metrics READ metrics NOTIFY appearanceChanged)
    Q_PROPERTY(QVariantMap appearance READ appearance NOTIFY appearanceChanged)

  private:
    enum class DismissAction { Commit, Cancel };
    enum class Lifecycle { Open, Closed };
    enum class CloseFocus { Restore, Discard };

  public:
    PitchBendEditor(::SongView *songView, SongDocument *document, const DocNote &note,
                    std::function<bool(QPointF)> focusNoteUnderCursor);
    ~PitchBendEditor() override;

    void openAt(const QRect &noteGlobal, double noteFraction);
    void cancelAndClose();
    void cancelAndCloseWithoutFocus();

    bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
    bool hasEditableSpan() const { return m_endTick > m_startTick; }
    uint64_t endTick() const { return m_endTick; }
    QQuickView *view() const { return m_view.data(); }

    int bendRange() const { return m_bendRange; }
    int lfoSpeed() const { return m_lfoSpeed; }
    QString description() const { return m_description; }
    QString noteDescription() const { return m_noteDescription; }
    QVariantMap metrics() const { return m_metrics; }
    QVariantMap appearance() const { return m_appearance; }

    Q_INVOKABLE void setBendRange(int range);
    Q_INVOKABLE void setLfoSpeed(int speed);
    Q_INVOKABLE void resetPitchCurve();
    Q_INVOKABLE void resetModCurve();

  signals:
    void controllerValuesChanged();
    void appearanceChanged();

  private:
    friend class PitchBendCloseController;
    friend class PitchBendPopupView;

    enum class PendingEdit { None, Curve };

    // Window-only arbitration surface.
    void undoFromKeyboard();
    void requestCancelClose();
    void dismissWithCommit(bool restoreFocus);
    bool handleUnclaimedKeyPress(QKeyEvent *event);
    void refreshChrome();

    void installCloseController(std::function<bool(QPointF)> focusNoteUnderCursor);
    bool ensureView();
    void bindGraph(PitchBendGraph *graph, PitchBendGraph::Lane lane);
    void resolveChromeGeometry();
    void rebuildCachedChrome();
    void finalize(DismissAction action, CloseFocus focus, bool deferTeardown);
    void close(DismissAction action, CloseFocus focus);

    PitchBendGraph *focusedGraph() const;
    void onGrabLost();
    void undoCurve();
    void resetCurve(PitchBendGraph *graph);
    void updateRange(int steps);
    void snapshotControllerValues();
    void snapshotCurves();
    void snapshotCurve(PitchBendGraph *graph, uint8_t cc);
    bool writeController(uint8_t cc, int value, int endValue);
    void writeCurve(PitchBendGraph *graph);
    void markCurvePending(PitchBendGraph *graph);
    void commitCurve();
    void cancelCurve();
    uint8_t ccForGraph(const PitchBendGraph *graph) const;
    void updateDescription();
    bool noteSpanStillPresent() const;

    QPointer<::SongView> m_songView;
    QPointer<SongDocument> m_document;
    DocNote m_noteSnapshot;
    int m_engineTrack = -1;
    uint64_t m_startTick = 0;
    uint64_t m_endTick = 0;
    bool m_unterminated = false;
    int m_bendRange = 2;
    int m_endRange = 2;
    int m_lfoSpeed = 22;
    int m_endLfoSpeed = 22;
    PitchBendGeometry m_geometry;
    QString m_description;
    QString m_noteDescription;
    QVariantMap m_metrics;
    QVariantMap m_appearance;
    QPointer<PitchBendGraph> m_pitchGraph;
    QPointer<PitchBendGraph> m_modGraph;
    QPointer<QQuickView> m_view;
    QPointer<PitchBendGraph> m_pendingGraph;
    PendingEdit m_pending = PendingEdit::None;
    Lifecycle m_lifecycle = Lifecycle::Open;
    CloseFocus m_closeFocus = CloseFocus::Restore;
};
} // namespace songview
