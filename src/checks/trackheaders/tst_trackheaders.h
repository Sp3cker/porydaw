#pragma once

#include <QImage>
#include <QPointer>
#include <QRect>
#include <QString>
#include <QStringList>

extern "C" {
#include "voicegroup_loader.h"
}

#include <memory>
#include <optional>
#include <vector>

class QObject;
class QQuickItem;
class QQuickWindow;
class SongTab;
class SongView;

namespace checks {
class ProjectFixture;
}

namespace songview {
class TimelineInputItem;
class TimelineQuickView;
class TrackHeaderModel;
} // namespace songview

class TrackHeadersFixture final
{
  public:
    TrackHeadersFixture(QString projectRoot, QString songLabel);
    ~TrackHeadersFixture();

    TrackHeadersFixture(const TrackHeadersFixture &) = delete;
    TrackHeadersFixture &operator=(const TrackHeadersFixture &) = delete;

    bool create(QString &error);
    bool acquireInputFocus(QString &error);
    void close();

    SongTab &tab() noexcept;
    SongView &view() noexcept;
    songview::TrackHeaderModel &headers() noexcept;
    songview::TimelineQuickView &quick() noexcept;
    songview::TimelineInputItem &input() noexcept;
    QQuickWindow &window() noexcept;
    QQuickItem &root() noexcept;
    QQuickItem &band() noexcept;
    QQuickItem &scrollbar() noexcept;
    QQuickItem &thumb() noexcept;
    QQuickItem &rename() noexcept;
    QQuickItem &marker() noexcept;
    QQuickItem &toolTip() noexcept;
    QObject &rows() noexcept;
    const std::vector<int> &tracks() const noexcept;
    int sourceTrack() const noexcept;
    int selectionTrack() const noexcept;
    int voiceTrack() const noexcept;
    int reorderTargetTrack() const noexcept;
    int rowHeight() const noexcept;
    QRect isolatedBandRect() const noexcept;
    std::optional<int> rowForTrack(int track) const;
    std::optional<int> addTrackRow() const;
    std::optional<QPointF> pointForRow(int row, const QRectF &localRect) const;
    std::optional<QPointF> titlePoint(int row) const;
    std::optional<QPointF> voicePoint(int row) const;
    std::optional<QPointF> mutePoint(int row) const;
    std::optional<QPointF> soloPoint(int row) const;
    QImage captureBand(QString &error);
    bool rebuild(QString &error);

  private:
    QString m_projectRoot;
    QString m_songLabel;
    std::unique_ptr<checks::ProjectFixture> m_fixture;
    std::unique_ptr<LoadedVoiceGroup> m_bank;
    std::unique_ptr<SongTab> m_tab;
    QPointer<songview::TrackHeaderModel> m_headers;
    QPointer<songview::TimelineQuickView> m_quick;
    QPointer<songview::TimelineInputItem> m_input;
    QPointer<QQuickWindow> m_window;
    QPointer<QQuickItem> m_root;
    QPointer<QQuickItem> m_band;
    QPointer<QQuickItem> m_scrollbar;
    QPointer<QQuickItem> m_thumb;
    QPointer<QQuickItem> m_rename;
    QPointer<QQuickItem> m_marker;
    QPointer<QQuickItem> m_toolTip;
    QPointer<QObject> m_rows;
    std::vector<int> m_tracks;
    int m_sourceTrack = -1;
    int m_selectionTrack = -1;
    int m_voiceTrack = -1;
    int m_reorderTargetTrack = -1;
    QRect m_isolatedBandRect;
};

class TrackHeadersTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TrackHeadersTest)

  public:
    TrackHeadersTest(QString projectRoot, QString songLabel);
    ~TrackHeadersTest() override;

  private slots:
    void init();
    void cleanup();
    void quickSurfacePublishesAndRendersHeaders();
    void selectionAndVoiceRouteThroughHeaders();
    void muteAndSoloHonorCancellationAndButtons();
    void scrollClampsAndRoutesKeyboardAndWheelInput();
    void tooltipClearsOnScroll();
    void renameCommitsAndRebuildsHeader();
    void reorderCommitsAndRebuildsHeader();
    void addTrackOpensPickerAndRebuildsHeader();
    void headerMenuOpensWithTypedRowsAndDismissesWithoutWrite();
    void headerMenuChangeVoiceOpensPickerAfterMenuCloses();
    void headerMenuRenameBeginsAfterCloseAndFocusesEditor();
    void headerMenuRowsDispatchRevealDuplicateDelete();
    void headerMenuStaleStructuralChangeCancelsWithoutWrite();
    void headerMenuQueuedDestructiveMutationsDropAfterRemap();
    void headerMenuOutsidePressDismissesWithoutClickThrough();
    void emptyTrackHeadersRejectInputWithoutMutation();
    void activityRasterMatchesRolesAndIsSilentWhenUnchanged();
    void voiceSubtitleFollowsProgramPosition();

  private:
    TrackHeadersFixture &fixture() noexcept;

    QString m_projectRoot;
    QString m_songLabel;
    std::unique_ptr<TrackHeadersFixture> m_fixture;
};

int runTrackHeaderQuickCheck(const QString &projectRoot, const QString &songLabel,
                             const QStringList &qtArguments);
