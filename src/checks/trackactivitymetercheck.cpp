#include <QAbstractItemModel>
#include <QByteArray>
#include <QColor>
#include <QElapsedTimer>
#include <QImage>
#include <QList>
#include <QPoint>
#include <QQuickItem>
#include <QRect>
#include <QString>
#include <QThread>
#include <QtGlobal>

#include "audio/trackactivitylevel.h"
#include "checks/support/quickframebuffer.h"
#include "core/miditimeline.h"
#include "ui/activity/trackactivityrender.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <initializer_list>
#include <utility>

namespace {

constexpr auto kConvergedSeconds = 60.0f;

bool isOpaque(const QImage &image)
{
    if (image.isNull())
        return false;
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            if (image.pixelColor(x, y).alpha() != 255)
                return false;
        }
    }
    return true;
}

int paintedRowsAt(const QImage &image, int x)
{
    if (image.isNull() || image.height() == 0)
        return 0;

    const QColor bottom = image.pixelColor(x, image.height() - 1);
    int rows = 0;
    for (int y = image.height() - 1; y >= 0; --y) {
        if (image.pixelColor(x, y) != bottom)
            break;
        ++rows;
    }
    return rows;
}

bool waitForQuickTrackHeaders(SongView &view, songview::TimelineQuickView &quick)
{
    QElapsedTimer timeout;
    timeout.start();
    do {
        checks::support::pumpQuick();
        QQuickItem *const root = quick.rootObject();
        auto *const input = root ? root->findChild<songview::TimelineInputItem *>(
                                       QStringLiteral("timelineTrackHeadersInput"))
                                 : nullptr;
        const auto &band = view.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
        if (band && !band->rect.isEmpty() && input && input->width() > 0.0 &&
            input->height() > 0.0) {
            return true;
        }
        QThread::msleep(10);
    } while (timeout.elapsed() < 1000);
    return false;
}

QImage captureActivityRow(SongView &view, const songview::TrackHeaderModel &model, int row,
                          QString *error)
{
    const auto &band = view.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
    const int meterHeight = std::max(0, model.rowHeight() - model.separatorWidth());
    if (!band || band->rect.isEmpty() || row < 0 || model.activityWidth() <= 0 ||
        meterHeight <= 0) {
        if (error)
            *error = QStringLiteral("track-header activity geometry is unavailable");
        return {};
    }

    const int y = band->rect.y() + qRound(row * model.rowHeight() - model.scrollY());
    return checks::support::captureQuickBand(
        view, QRect{band->rect.x(), y, model.activityWidth(), meterHeight}, error);
}

TrackActivityLevels levelsWith(std::initializer_list<std::pair<int, TrackActivityLevel>> levels)
{
    TrackActivityLevels targets{};
    for (const auto &[track, level] : levels)
        targets[static_cast<std::size_t>(track)] = level;
    return targets;
}

int channelPixelHeight(uint8_t level, int meterHeight, qreal devicePixelRatio)
{
    const track_activity_render::State state{levelToIntensity({level, level}), true};
    return track_activity_render::physicalHeight(state, state.intensity.left, meterHeight,
                                                 devicePixelRatio);
}

int devicePixelSpan(int origin, int length, qreal devicePixelRatio)
{
    return qRound((origin + length) * devicePixelRatio) - qRound(origin * devicePixelRatio);
}

uint8_t levelWithinPixel(uint8_t base, int meterHeight, qreal devicePixelRatio)
{
    for (int level = base; level < 255; ++level) {
        if (channelPixelHeight(static_cast<uint8_t>(level), meterHeight, devicePixelRatio) ==
            channelPixelHeight(static_cast<uint8_t>(level + 1), meterHeight, devicePixelRatio)) {
            return static_cast<uint8_t>(level);
        }
    }
    return 255;
}

uint8_t levelAcrossPixel(uint8_t base, int meterHeight, qreal devicePixelRatio)
{
    const int baseRows = channelPixelHeight(base, meterHeight, devicePixelRatio);
    for (int level = base + 1; level <= 255; ++level) {
        if (channelPixelHeight(static_cast<uint8_t>(level), meterHeight, devicePixelRatio) >
            baseRows) {
            return static_cast<uint8_t>(level);
        }
    }
    return 255;
}

int rowForTrack(const songview::TrackHeaderModel &model, int track)
{
    for (int row = 0; row < model.rowCount(); ++row) {
        if (model.data(model.index(row, 0), songview::TrackHeaderModel::TrackRole).toInt() == track)
            return row;
    }
    return -1;
}

struct DataChangeReport {
    int count = 0;
    int firstRow = -1;
    int lastRow = -1;
    QList<int> roles;
};

} // namespace

int runTrackActivityMeterCheck()
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "trackactivitymetercheck: FAIL: %s\n", message);
            ++failures;
        }
    };

    constexpr int track = 3;
    constexpr int secondTrack = 7;
    MidiTimeline singleTrackTimeline;
    singleTrackTimeline.tracks[track].used = true;
    singleTrackTimeline.usedTrackCount = 1;

    SongView view;
    view.resize(720, 520);
    view.setSong(&singleTrackTimeline, nullptr);
    view.show();
    checks::support::pumpQuick();

    auto *const quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *const model =
        view.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"));
    check(quick != nullptr, "SongView must expose the retained TimelineQuickView");
    check(model != nullptr, "SongView must expose TrackHeaderModel");
    if (!quick || !model)
        return 1;

    const bool headerInputReady = waitForQuickTrackHeaders(view, *quick);
    check(headerInputReady, "TimelineQuickView did not attach the track-header Quick input");
    if (!headerInputReady)
        return 1;
    const int trackRow = rowForTrack(*model, track);
    const int meterHeight = std::max(0, model->rowHeight() - model->separatorWidth());
    const bool initialRows = model->rowCount() == 1 && trackRow == 0;
    check(initialRows, "the initial TrackHeaderModel must contain the used track only");
    const bool usableGeometry = meterHeight > 0 && model->activityWidth() > 0;
    check(usableGeometry, "the track-header activity geometry must be non-empty");
    if (!initialRows || !usableGeometry)
        return 1;

    const auto captureRow = [&view, model, &check](int row) {
        QString error;
        QImage frame = captureActivityRow(view, *model, row, &error);
        check(!frame.isNull(),
              qUtf8Printable(
                  QStringLiteral("TimelineQuickView activity framebuffer is unavailable: %1")
                      .arg(error)));
        return frame;
    };

    // First capture establishes a live Quick window, so subsequent activity
    // synchronization uses the window's actual DPR rather than a provisional host value.
    const QImage warmFrame = captureRow(trackRow);
    if (warmFrame.isNull())
        return 1;
    const qreal devicePixelRatio = warmFrame.devicePixelRatio();
    check(devicePixelRatio > 0.0, "TimelineQuickView framebuffer must report a device pixel ratio");
    check(std::abs(devicePixelRatio - quick->quickDevicePixelRatio()) < 0.001,
          "activity framebuffer and TimelineQuickView must use the same device pixel ratio");
    if (const char *requestedScale = std::getenv("QT_SCALE_FACTOR")) {
        char *end = nullptr;
        const double scale = std::strtod(requestedScale, &end);
        if (requestedScale[0] != '\0' && end && *end == '\0' && scale > 0.0) {
            check(std::abs(devicePixelRatio - scale) < 0.001,
                  "the requested Qt scale must reach the TimelineQuickView activity frame");
        }
    }
    checks::support::pumpQuick();

    DataChangeReport dataChanges;
    const auto roleNames = model->roleNames();
    const int leftHeightRole = roleNames.key(QByteArrayLiteral("activityLeftHeight"), 0);
    const int rightHeightRole = roleNames.key(QByteArrayLiteral("activityRightHeight"), 0);
    check(leftHeightRole != 0 && rightHeightRole != 0,
          "TrackHeaderModel must expose activity height roles to QML by name");
    QObject::connect(model, &QAbstractItemModel::dataChanged, &view,
                     [&dataChanges](const QModelIndex &topLeft, const QModelIndex &bottomRight,
                                    const QList<int> &roles) {
                         ++dataChanges.count;
                         dataChanges.firstRow = topLeft.row();
                         dataChanges.lastRow = bottomRight.row();
                         dataChanges.roles = roles;
                     });

    const auto present = [&view](std::initializer_list<std::pair<int, TrackActivityLevel>> levels,
                                 bool playing) {
        view.advanceTrackActivity(levelsWith(levels), kConvergedSeconds, playing);
    };

    constexpr uint8_t kMidLevel = 128;
    dataChanges = {};
    present({{track, {kMidLevel, kMidLevel}}}, true);
    const QImage activeImage = captureRow(trackRow);
    check(!activeImage.isNull(), "a presented activity tick must render the Quick header frame");
    check(dataChanges.count == 1 && dataChanges.firstRow == trackRow &&
              dataChanges.lastRow == trackRow,
          "the initial activity update must notify its bounded track-header row");
    if (activeImage.isNull())
        return 1;
    if (leftHeightRole && rightHeightRole) {
        check(dataChanges.roles == QList<int>{leftHeightRole, rightHeightRole},
              "activity updates must carry exactly the two height roles");
    }

    const uint8_t sharedLevel = levelWithinPixel(kMidLevel, meterHeight, devicePixelRatio);
    check(sharedLevel != 255, "the activity raster must admit a sub-pixel level step");
    if (sharedLevel != 255) {
        dataChanges = {};
        present({{track, {sharedLevel, sharedLevel}}}, true);
        const QImage sharedPixelImage = captureRow(trackRow);
        const uint8_t withinLevel = static_cast<uint8_t>(sharedLevel + 1);

        dataChanges = {};
        present({{track, {withinLevel, withinLevel}}}, true);
        const QImage withinPixelImage = captureRow(trackRow);
        check(withinPixelImage == sharedPixelImage,
              "a level change within one physical pixel must leave the Quick frame unchanged");
        check(dataChanges.count == 0,
              "unchanged physical activity heights must emit no model notification");

        const uint8_t acrossLevel = levelAcrossPixel(withinLevel, meterHeight, devicePixelRatio);
        dataChanges = {};
        present({{track, {acrossLevel, acrossLevel}}}, true);
        const QImage acrossPixelImage = captureRow(trackRow);
        check(acrossPixelImage != sharedPixelImage,
              "a level change across a physical-pixel boundary must change the Quick frame");
        check(dataChanges.count == 1 && dataChanges.firstRow == trackRow &&
                  dataChanges.lastRow == trackRow,
              "a changed activity height must emit one bounded model span");
        if (leftHeightRole && rightHeightRole) {
            check(dataChanges.roles == QList<int>{leftHeightRole, rightHeightRole},
                  "a changed activity height span must carry exactly the height roles");
        }
    }

    dataChanges = {};
    present({}, false);
    const QImage pausedImage = captureRow(trackRow);
    check(dataChanges.count == 1 && dataChanges.firstRow == trackRow &&
              dataChanges.lastRow == trackRow,
          "a playing-to-paused activity transition must emit one bounded model span");
    if (leftHeightRole && rightHeightRole) {
        check(dataChanges.roles == QList<int>{leftHeightRole, rightHeightRole},
              "a playing-to-paused span must carry exactly the height roles");
    }
    check(!pausedImage.isNull(), "paused activity must render a TimelineQuickView framebuffer");
    if (pausedImage.isNull())
        return 1;
    const auto &headerBand =
        view.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
    const int activityY =
        headerBand ? headerBand->rect.y() + qRound(trackRow * model->rowHeight() - model->scrollY())
                   : 0;
    const QPoint cropOrigin =
        headerBand ? quick->mapFrom(&view, QPoint{headerBand->rect.x(), activityY}) : QPoint{};
    check(headerBand &&
              pausedImage.width() ==
                  devicePixelSpan(cropOrigin.x(), model->activityWidth(), devicePixelRatio) &&
              pausedImage.height() ==
                  devicePixelSpan(cropOrigin.y(), meterHeight, devicePixelRatio),
          "activity framebuffer dimensions must be physical-device-pixel dimensions");
    check(std::abs(pausedImage.devicePixelRatio() - devicePixelRatio) < 0.001,
          "activity framebuffer must preserve the Quick window device-pixel ratio");
    check(isOpaque(pausedImage), "the Quick track-header activity surface must remain opaque");
    check(paintedRowsAt(pausedImage, pausedImage.width() / 4) == pausedImage.height(),
          "paused activity fill must cover the meter to the top");
    check(activeImage.pixelColor(activeImage.width() / 4, activeImage.height() / 4) !=
              pausedImage.pixelColor(pausedImage.width() / 4, pausedImage.height() / 4),
          "a partial playing meter must leave a dimmed background above it");
    // The cap is a snapped rendering-policy contract; keep its exact oracle at
    // physicalHeight rather than weakening it to a raster color observation.

    const track_activity_render::State capped{{1.0f, 1.0f}, true, 0.15f};
    const int cappedRows = track_activity_render::physicalHeight(capped, capped.intensity.left,
                                                                 meterHeight, devicePixelRatio);
    check(cappedRows == qRound(0.15 * meterHeight * devicePixelRatio),
          "playing activity must retain its physical-pixel intensity cap");
    const track_activity_render::State uncapped{{1.0f, 1.0f}, false, 0.15f};
    check(track_activity_render::physicalHeight(uncapped, uncapped.intensity.left, meterHeight,
                                                devicePixelRatio) > cappedRows,
          "paused activity must ignore the playing intensity cap");

    constexpr TrackActivityLevel kStereoLevel{255, 64};
    present({{track, kStereoLevel}}, true);
    const QImage stereoImage = captureRow(trackRow);
    check(!stereoImage.isNull(), "stereo activity must render a TimelineQuickView framebuffer");
    if (!stereoImage.isNull()) {
        const int stereoLeftX = stereoImage.width() / 4;
        const int stereoRightX = stereoImage.width() * 3 / 4;
        const int topY = stereoImage.height() / 8;
        const int bottomY = stereoImage.height() - 1;
        check(stereoImage.pixelColor(stereoLeftX, topY) !=
                  stereoImage.pixelColor(stereoRightX, topY),
              "left and right activity levels must render independently in TrackHeaderBand");
        check(stereoImage.pixelColor(stereoLeftX, bottomY) ==
                  stereoImage.pixelColor(stereoRightX, bottomY),
              "both stereo activity levels must rise from the meter bottom");
    }

    MidiTimeline twoTrackTimeline;
    twoTrackTimeline.tracks[track].used = true;
    twoTrackTimeline.tracks[secondTrack].used = true;
    twoTrackTimeline.usedTrackCount = 2;
    view.setSong(&twoTrackTimeline, nullptr);
    checks::support::pumpQuick();

    const int rebuiltTrackRow = rowForTrack(*model, track);
    const int rebuiltSecondRow = rowForTrack(*model, secondTrack);
    check(model->rowCount() == 2 && rebuiltTrackRow >= 0 && rebuiltSecondRow >= 0,
          "TrackHeaderModel rebuild must retain every used track");
    if (rebuiltTrackRow >= 0 && rebuiltSecondRow >= 0) {
        dataChanges = {};
        present({{track, {255, 255}}, {secondTrack, {96, 96}}}, true);
        const QImage firstTrackImage = captureRow(rebuiltTrackRow);
        const QImage secondTrackImage = captureRow(rebuiltSecondRow);
        const bool rebuiltFrames = !firstTrackImage.isNull() && !secondTrackImage.isNull() &&
                                   isOpaque(firstTrackImage) && isOpaque(secondTrackImage);
        check(rebuiltFrames, "a rebuilt TrackHeaderModel must render every activity row opaquely");
        if (rebuiltFrames) {
            check(firstTrackImage.pixelColor(firstTrackImage.width() / 4,
                                             firstTrackImage.height() - 1) !=
                      secondTrackImage.pixelColor(secondTrackImage.width() / 4,
                                                  secondTrackImage.height() - 1),
                  "rebuilt activity rows must retain independent track identity colors");
        }
        check(dataChanges.count == 1 &&
                  dataChanges.firstRow == std::min(rebuiltTrackRow, rebuiltSecondRow) &&
                  dataChanges.lastRow == std::max(rebuiltTrackRow, rebuiltSecondRow),
              "one multi-track activity tick must emit one bounded model span");
        if (leftHeightRole && rightHeightRole) {
            check(dataChanges.roles == QList<int>{leftHeightRole, rightHeightRole},
                  "the rebuilt multi-track span must carry exactly the activity height roles");
        }

        dataChanges = {};
        present({{track, {255, 255}}, {secondTrack, {96, 96}}}, true);
        checks::support::pumpQuick();
        check(dataChanges.count == 0,
              "an identical repeated activity tick must not notify TrackHeaderModel");
    }

    if (failures == 0)
        std::printf("trackactivitymetercheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
