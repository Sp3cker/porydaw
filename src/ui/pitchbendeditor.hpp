#pragma once

#include "core/songdocument.h"
#include "pitchbendgraph.hpp"

#include <QMetaObject>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QRectF>
#include <QVariantMap>
#include <cstdint>
#include <functional>

class QEvent;
class QKeyEvent;
class QQuickItem;
class QQuickWindow;
class SongView;

namespace songview {

class QuickPopupSession;

// Session bridge backing the shared Quick popup pitch-bend editor. Owns the
// document snapshots, pending commit/cancel, controller values, cached chrome,
// and the note-anchored surface placement. The TimelineQuickView popup session
// hosts the QML surface on the shared canvas window; this object arbitrates
// keys and dismissal. No private window: the former
// PitchBendPopupView/PitchBendCloseController machinery is gone.
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

    // noteScene is the anchor note rect in the shared canvas window's scene
    // coordinates; the surface hangs from it, clamped to the viewport.
    void openAt(const QRectF &noteScene, double noteFraction);
    Q_INVOKABLE void cancelAndClose();
    Q_INVOKABLE void cancelAndCloseWithoutFocus();

    bool isOpen() const { return m_lifecycle == Lifecycle::Open; }
    bool hasEditableSpan() const { return m_endTick > m_startTick; }
    uint64_t endTick() const { return m_endTick; }

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
    // Terminal key sink for keys unclaimed by the graphs or the numeric
    // fields: vertex-delete retry, then the single routed Solo command.
    Q_INVOKABLE bool routeUnclaimedKey(int key, int modifiers, bool autoRepeat);

  signals:
    void controllerValuesChanged();
    void appearanceChanged();

  private:
    enum class PendingEdit { None, Curve };

    // Shared-window arbitration surface: document undo is claimed before
    // Quick child-first delivery can turn the chord into a focused
    // TextInput's local text undo.
    bool handleUnclaimedKeyPress(QKeyEvent *event);
    void refreshChrome();

    void bindGraph(PitchBendGraph *graph, PitchBendGraph::Lane lane);
    void resolveChromeGeometry();
    void rebuildCachedChrome();
    void placeContent();
    // Single dismissal primitive. The lifecycle guard settles every close,
    // tab, document, and replacement path exactly once; the session's
    // cancelled() re-enters through the guard without effect.
    void dispose(DismissAction action, CloseFocus focus, bool deferTeardown = true);

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

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    QPointer<::SongView> m_songView;
    QPointer<SongDocument> m_document;
    DocNote m_noteSnapshot;
    int m_engineTrack = -1;
    uint64_t m_startTick = 0;
    uint64_t m_endTick = 0;
    bool m_unterminated = false;
    // Outside-press classifier in shared-window scene coordinates: true when
    // the press lands on a note (any note), restoring the old close
    // controller's consume-and-retarget rule.
    std::function<bool(QPointF)> m_focusNoteUnderCursor;
    int m_bendRange = 2;
    int m_endRange = 2;
    int m_lfoSpeed = 22;
    int m_endLfoSpeed = 22;
    PitchBendGeometry m_geometry;
    QString m_description;
    QString m_noteDescription;
    QVariantMap m_metrics;
    QVariantMap m_appearance;
    QPointer<QuickPopupSession> m_session;
    QRectF m_noteAnchor;
    QPointer<QQuickWindow> m_sessionWindow;
    QMetaObject::Connection m_sessionCancelledConnection;
    QMetaObject::Connection m_sessionClosedConnection;
    QPointer<PitchBendGraph> m_pitchGraph;
    QPointer<PitchBendGraph> m_modGraph;
    QPointer<PitchBendGraph> m_pendingGraph;
    PendingEdit m_pending = PendingEdit::None;
    Lifecycle m_lifecycle = Lifecycle::Open;
};
} // namespace songview
