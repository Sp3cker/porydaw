#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include <QByteArray>
#include <QObject>
#include <QStringList>

#include "core/songdocument.h"
#include "ui/editordrawer/nodelane/nodelane.h"

class AutomationDomainTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(AutomationDomainTest)

  public:
    AutomationDomainTest() = default;

  private slots:
    void init();
    void cleanup();

    void effectivePoints_data();
    void effectivePoints();
    void rangesAndSelection_data();
    void rangesAndSelection();
    void deletes_data();
    void deletes();
    void moves_data();
    void moves();
    void moveCollisions_data();
    void moveCollisions();
    void replaceSpans_data();
    void replaceSpans();
    void defaultNodePromotion();

    void xcmdCanonicalEdits();
    void xcmdOccurrencesAndOpaqueProtection();
    void xcmdTimeRangeCuts();
    void xcmdSweepPreservesNotes();
    void xcmdRangeRemoveOnly();
    void xcmdRangeMoves();
    void xcmdExpansionPaste();

    void sweepSteppingAndRampFinish();
    void panNeutralSnap();
    void nodeDragAndPhantomOutcomes();
    void pointRangeAndPencilReplacements();

  private:
    struct Snapshot {
        QByteArray smf;
        uint64_t revision = 0;
        int undoIndex = 0;

        bool operator==(const Snapshot &) const = default;
    };

    SongDocument &document() const;
    Snapshot snapshot() const;
    static bool isOneEdit(const Snapshot &before, const Snapshot &after);
    static bool samePoints(const std::vector<NodePoint> &actual,
                           const std::vector<NodePoint> &expected);
    static std::vector<int> rawValuesAt(const SongDocument &document, int track, uint8_t controller,
                                        uint64_t tick);
    static int tempoBpm(uint32_t microsecondsPerQuarterNote);
    static uint32_t tempoUsForBpm(int bpm);
    static void setTempo(SongDocument &document, const std::vector<TempoPoint> &points);
    static void setLane(SongDocument &document, int track, uint8_t controller,
                        const std::vector<SongDocument::LanePointValue> &points);
    static void insertCc(SongDocument &document, int track, uint8_t controller, uint64_t tick,
                         int value);
    static void setUniquePoints(SongDocument &document, int adapterKind,
                                const std::vector<NodePoint> &points);
    static bool applyMoves(SongDocument &document, int adapterKind,
                           const std::vector<NodePointMove> &moves);
    static bool applyDeletes(SongDocument &document, int adapterKind,
                             const std::vector<uint64_t> &ticks);
    bool undoRedoRestores(const Snapshot &before, const std::vector<NodePoint> &beforePoints,
                          const std::vector<NodePoint> &afterPoints, NodeLane &lane);

    std::unique_ptr<SongDocument> m_document;
};

int runAutomationDomainCheck(const QStringList &qtArguments);
