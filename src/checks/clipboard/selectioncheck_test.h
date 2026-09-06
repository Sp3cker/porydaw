#pragma once

#include <cstddef>
#include <cstdint>

#include <QObject>

#include "ui/songview/editorselectionmodel.h"

namespace checks::clipboard {

class NotificationLog final
{
  public:
    void attach(songview::EditorSelectionModel &model)
    {
        model.setObserver(
            [this](const songview::EditorSelectionModel::SelectionTransition &transition) {
                transitions.push_back(transition);
            });
    }

    void clear() { transitions.clear(); }

    std::vector<songview::EditorSelectionModel::SelectionTransition> transitions;
};

constexpr uint32_t trackBit(int track) noexcept
{
    return track >= 0 && track < 16 ? (uint32_t{1} << track) : 0;
}

inline bool hasTransition(const NotificationLog &log, size_t before, uint32_t changes)
{
    return log.transitions.size() == before + 1 &&
           static_cast<uint32_t>(log.transitions.back().changes) == changes;
}

class SelectionCheckTest final : public QObject
{
    Q_OBJECT

  public:
    SelectionCheckTest() = default;
    Q_DISABLE_COPY_MOVE(SelectionCheckTest)

  private slots:
    void noteSelectionSanitizesAndExcludesTime();
    void timeSelectionAndScopeCommitAtomically();
    void clearOperationsPreserveTheOtherSelection();
    void reconciliationPreservesSelectionOrder();

    void trackScopeGesturesPreserveOrClearAtTheRightBoundary();
    void coverageQueriesAndLaneScopeSanitization();
    void outOfRangeTrackMasksAreIgnored();
    void resetForSongSwapNotifiesExactState();
    void remapPreservesMeaningfulSelection();
};

} // namespace checks::clipboard
