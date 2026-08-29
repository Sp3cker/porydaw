#include <QAbstractItemModel>
#include <QByteArray>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QEvent>
#include <QImage>
#include <QList>
#include <QQmlContext>
#include <QThread>
#include <QVariant>
#include <QWidget>
#include <QtGlobal>

#include "audio/trackactivitylevel.h"
#include "ui/activity/trackactivitypresentation.h"
#include "ui/activity/trackactivityrender.h"
#include "ui/activity/trackactivityview.h"
#include "ui/layout.h"

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <utility>

#ifdef Q_OS_MACOS
int runMacTrackActivityPresentationCheck();
#endif
namespace {

constexpr int kMeterHeight = 32;
constexpr auto kConvergedSeconds = 60.0f;

class PaintCounter final : public QObject
{
  public:
    int paints = 0;

  protected:
    bool eventFilter(QObject *, QEvent *event) override
    {
        if (event->type() == QEvent::Paint)
            ++paints;
        return false;
    }
};

void drainPaintEvents()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

void reset(PaintCounter &counter)
{
    drainPaintEvents();
    counter.paints = 0;
}

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

QImage captureFramebuffer(TrackActivityView &view)
{
    const QSize expected(qRound(view.width() * view.devicePixelRatioF()),
                         qRound(view.height() * view.devicePixelRatioF()));
    QElapsedTimer timeout;
    timeout.start();
    do {
        drainPaintEvents();
        QImage frame = view.grabFramebuffer();
        if (!frame.isNull() && frame.size() == expected) {
            view.update();
            drainPaintEvents();
            frame = view.grabFramebuffer();
            frame.setDevicePixelRatio(view.devicePixelRatioF());
            return frame;
        }
        QThread::msleep(10);
    } while (timeout.elapsed() < 1000);
    return {};
}

// A converged advance copies each target level into the activity intensity
// bit-exactly, so exact levels reach the view through the real smoothing
// state machine.
TrackActivity activityWithLevels(std::initializer_list<std::pair<int, TrackActivityLevel>> levels)
{
    TrackActivity activity;
    activity.reset();
    TrackActivityLevels targets{};
    for (const auto &[track, level] : levels)
        targets[static_cast<std::size_t>(track)] = level;
    activity.advance(targets, kConvergedSeconds, true);
    return activity;
}

// Physical pixel height one channel level renders at, per the render policy
// the view applies.
int channelPixelHeight(uint8_t level, qreal devicePixelRatio)
{
    const track_activity_render::State state{levelToIntensity({level, level}), true};
    return track_activity_render::physicalHeight(state, state.intensity.left, kMeterHeight,
                                                 devicePixelRatio);
}

// The lowest level whose one-level step stays inside the same physical pixel;
// 255 when the raster density admits no such step.
uint8_t levelWithinPixel(uint8_t base, qreal devicePixelRatio)
{
    for (int level = base; level < 255; ++level) {
        if (channelPixelHeight(static_cast<uint8_t>(level), devicePixelRatio) ==
            channelPixelHeight(static_cast<uint8_t>(level + 1), devicePixelRatio))
            return static_cast<uint8_t>(level);
    }
    return 255;
}

// The lowest level rendering strictly taller than base.
uint8_t levelAcrossPixel(uint8_t base, qreal devicePixelRatio)
{
    const int baseRows = channelPixelHeight(base, devicePixelRatio);
    for (int level = base + 1; level <= 255; ++level) {
        if (channelPixelHeight(static_cast<uint8_t>(level), devicePixelRatio) > baseRows)
            return static_cast<uint8_t>(level);
    }
    return 255;
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

#ifdef Q_OS_MACOS
    failures += runMacTrackActivityPresentationCheck();
#endif

    QWidget parent;
    parent.resize(80, 48);
    TrackActivityView view(&parent);
    constexpr int track = 3;
    const std::array definitions{TrackActivityView::TrackDefinition{track, QColor(Qt::red)}};
    view.setTracks(definitions, {kMeterHeight, kMeterHeight});
    view.move(12, 6);
    parent.show();
    drainPaintEvents();

    check(view.parentWidget() == &parent, "activity view must remain a direct panel child");
    check(view.objectName() == QStringLiteral("trackActivityView"),
          "activity view must retain its object name");
    check(view.testAttribute(Qt::WA_OpaquePaintEvent),
          "activity view must paint an opaque surface");
    check(view.testAttribute(Qt::WA_TransparentForMouseEvents),
          "activity view must not handle track-row mouse events");
    check(view.focusPolicy() == Qt::NoFocus, "activity view must not enter the focus chain");
    check(view.width() == layout::space(layout::Space::One),
          "activity view must retain the fixed strip width");
    check(view.geometry() == QRect(12, 6, layout::space(layout::Space::One), kMeterHeight),
          "activity view must retain its assigned strip geometry");
    check(view.isVisible(), "activity view must be visible with its parent panel");

    const qreal devicePixelRatio = view.devicePixelRatioF();
    if (const char *requestedScale = std::getenv("QT_SCALE_FACTOR")) {
        char *end = nullptr;
        const double scale = std::strtod(requestedScale, &end);
        if (requestedScale[0] != '\0' && end && *end == '\0' && scale > 0.0) {
            check(std::abs(devicePixelRatio - scale) < 0.001,
                  "the requested Qt scale must reach the activity view");
        }
    }

    PaintCounter parentPaints;
    parent.installEventFilter(&parentPaints);
    reset(parentPaints);

    // Observe the model the QML delegates bind to: the batch contract is at
    // most one coalesced notification per presented tick.
    DataChangeReport dataChanges;
    int leftHeightRole = 0;
    int rightHeightRole = 0;
    const QVariant modelProperty =
        view.rootContext()->contextProperty(QStringLiteral("trackActivityModel"));
    auto *const activityModel =
        qobject_cast<QAbstractItemModel *>(modelProperty.value<QObject *>());
    check(activityModel, "the activity view must expose its row model to QML");
    if (activityModel) {
        const auto roleNames = activityModel->roleNames();
        leftHeightRole = roleNames.key(QByteArrayLiteral("leftHeight"), 0);
        rightHeightRole = roleNames.key(QByteArrayLiteral("rightHeight"), 0);
        check(leftHeightRole != 0 && rightHeightRole != 0,
              "row height roles must stay exposed to QML by name");
        QObject::connect(activityModel, &QAbstractItemModel::dataChanged, &view,
                         [&dataChanges](const QModelIndex &topLeft, const QModelIndex &bottomRight,
                                        const QList<int> &roles) {
                             ++dataChanges.count;
                             dataChanges.firstRow = topLeft.row();
                             dataChanges.lastRow = bottomRight.row();
                             dataChanges.roles = roles;
                         });
    }

    constexpr uint8_t kMidLevel = 128;
    dataChanges = {};
    view.present(activityWithLevels({{track, {kMidLevel, kMidLevel}}}), true);
    const QImage activeImage = captureFramebuffer(view);
    check(!activeImage.isNull(), "a presented activity tick must render the Quick activity frame");
    check(parentPaints.paints == 0, "a presented activity tick must not repaint the parent panel");
    check(dataChanges.count == 1, "a presented activity tick must notify the model exactly once");

    // One level step that stays inside the same physical pixel must leave the
    // frame, the model, and the panel untouched.
    const uint8_t sharedLevel = levelWithinPixel(kMidLevel, devicePixelRatio);
    check(sharedLevel != 255, "the raster must admit a sub-pixel level step");
    const uint8_t withinLevel =
        sharedLevel != 255 ? static_cast<uint8_t>(sharedLevel + 1) : static_cast<uint8_t>(255);
    dataChanges = {};
    view.present(activityWithLevels({{track, {withinLevel, withinLevel}}}), true);
    const QImage withinPixelImage = captureFramebuffer(view);
    check(withinPixelImage == activeImage,
          "a level change within one physical pixel must leave the frame unchanged");
    check(dataChanges.count == 0, "a sub-pixel level change must not notify the model");
    check(parentPaints.paints == 0, "a sub-pixel level change must not repaint the parent panel");

    const uint8_t acrossLevel = levelAcrossPixel(withinLevel, devicePixelRatio);
    dataChanges = {};
    view.present(activityWithLevels({{track, {acrossLevel, acrossLevel}}}), true);
    const QImage acrossPixelImage = captureFramebuffer(view);
    check(acrossPixelImage != activeImage,
          "a level change across a physical-pixel boundary must change the frame");
    check(dataChanges.count == 1, "a presented level change must notify the model exactly once");
    check(parentPaints.paints == 0,
          "a physical-pixel level change must not repaint the parent panel");

    reset(parentPaints);
    dataChanges = {};
    view.present(activityWithLevels({{track, {acrossLevel, acrossLevel}}}), false);
    (void)captureFramebuffer(view);
    check(dataChanges.count == 1, "a playing mode change must notify the model exactly once");
    check(parentPaints.paints == 0, "a mode change must not repaint the parent panel");

    // Paused fill drives every level to full: the frame must cover the strip
    // at the raster's physical dimensions.
    TrackActivity pausedFill;
    pausedFill.resetPaused();
    view.present(pausedFill, false);
    const QImage pausedImage = captureFramebuffer(view);
    check(!pausedImage.isNull(), "activity view must produce a framebuffer");
    check(pausedImage.width() == qRound(view.width() * devicePixelRatio) &&
              pausedImage.height() == qRound(view.height() * devicePixelRatio),
          "framebuffer dimensions must be physical-device-pixel dimensions");
    check(std::abs(pausedImage.devicePixelRatio() - devicePixelRatio) < 0.001,
          "framebuffer must preserve the activity view device-pixel ratio");
    check(isOpaque(pausedImage), "opaque Quick rendering must cover the entire strip");
    check(paintedRowsAt(pausedImage, pausedImage.width() / 4) == pausedImage.height(),
          "paused fill must cover the strip to the top");
    check(activeImage.pixelColor(activeImage.width() / 4, activeImage.height() / 4) !=
              pausedImage.pixelColor(pausedImage.width() / 4, pausedImage.height() / 4),
          "a partial playing bar must leave a dimmed background above it");

    // The playing cap stays a render-policy property exercised at its own
    // seam: playing heights clamp at maximumIntensity, paused heights do not.
    const track_activity_render::State capped{{1.0f, 1.0f}, true, 0.15f};
    const int cappedRows = track_activity_render::physicalHeight(capped, capped.intensity.left,
                                                                 kMeterHeight, devicePixelRatio);
    check(cappedRows == qRound(0.15 * kMeterHeight * devicePixelRatio),
          "playing activity must be capped at maximumIntensity in physical pixels");
    const track_activity_render::State uncapped{{1.0f, 1.0f}, false, 0.15f};
    check(track_activity_render::physicalHeight(uncapped, uncapped.intensity.left, kMeterHeight,
                                                devicePixelRatio) > cappedRows,
          "paused activity must ignore the playing cap");

    constexpr TrackActivityLevel kStereoLevel{255, 64};
    view.present(activityWithLevels({{track, kStereoLevel}}), true);
    const QImage stereoImage = captureFramebuffer(view);
    const int stereoLeftX = stereoImage.width() / 4;
    const int stereoRightX = stereoImage.width() * 3 / 4;
    const int topY = stereoImage.height() / 4;
    const int bottomY = stereoImage.height() - 1;
    check(stereoImage.pixelColor(stereoLeftX, topY) != stereoImage.pixelColor(stereoRightX, topY),
          "left and right stereo levels must render independently");
    check(stereoImage.pixelColor(stereoLeftX, bottomY) ==
              stereoImage.pixelColor(stereoRightX, bottomY),
          "both stereo levels must rise from the bottom origin");

    parent.resize(80, 2 * kMeterHeight + 12);
    const std::array twoTracks{
        TrackActivityView::TrackDefinition{track, QColor(Qt::red)},
        TrackActivityView::TrackDefinition{7, QColor(Qt::blue)},
    };
    view.setTracks(twoTracks, {kMeterHeight, kMeterHeight});
    dataChanges = {};
    view.present(activityWithLevels({{track, {255, 255}}, {7, {96, 96}}}), true);
    const QImage twoTrackImage = captureFramebuffer(view);
    check(twoTrackImage.height() == qRound(2 * kMeterHeight * devicePixelRatio),
          "one retained activity view must stack every track row");
    check(isOpaque(twoTrackImage), "the shared two-track activity column must remain opaque");
    check(twoTrackImage.pixelColor(twoTrackImage.width() / 4, twoTrackImage.height() / 4) !=
              twoTrackImage.pixelColor(twoTrackImage.width() / 4, twoTrackImage.height() * 3 / 4),
          "shared activity rows must retain independent identity colors");
    check(dataChanges.count == 1, "one presented tick must coalesce into a single notification");
    check(dataChanges.firstRow == 0 && dataChanges.lastRow == 1,
          "the coalesced notification must span the changed rows");
    if (activityModel) {
        check(dataChanges.roles == QList<int>{leftHeightRole, rightHeightRole},
              "the coalesced notification must carry exactly the affected height roles");
    }

    dataChanges = {};
    view.present(activityWithLevels({{track, {255, 255}}, {7, {96, 96}}}), true);
    drainPaintEvents();
    check(dataChanges.count == 0, "an identical repeated tick must not notify the model");

    constexpr auto forceQuickVariable = "PORYDAW_FORCE_QUICK_TRACK_ACTIVITY";
    const bool forceQuickWasSet = qEnvironmentVariableIsSet(forceQuickVariable);
    const QByteArray previousForceQuick = qgetenv(forceQuickVariable);
    qputenv(forceQuickVariable, QByteArrayLiteral("1"));
    {
        QWidget presentationParent;
        TrackActivityPresentation presentation(presentationParent);
        TrackActivity pausedActivity;
        pausedActivity.resetPaused();
        const std::array presentationTracks{
            TrackActivityPresentation::TrackDefinition{track, QColor(Qt::red)}};
        presentation.setTracks(presentationTracks, {kMeterHeight, kMeterHeight});
        presentation.present(pausedActivity, false);
        presentationParent.show();
        drainPaintEvents();
        auto *quickFallback =
            presentationParent.findChild<TrackActivityView *>(QStringLiteral("trackActivityView"));
        check(quickFallback && quickFallback->parentWidget() == &presentationParent,
              "Quick activity adapter was not retained behind the presentation facade");
    }
    if (forceQuickWasSet)
        qputenv(forceQuickVariable, previousForceQuick);
    else
        qunsetenv(forceQuickVariable);

    if (failures == 0)
        std::printf("trackactivitymetercheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
