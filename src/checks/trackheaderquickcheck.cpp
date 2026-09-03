#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"

#include "core/miditimeline.h"
#include "ui/activity/trackactivity.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"

#include <QAbstractItemModel>
#include <QCoreApplication>
#include <QDialog>
#include <QElapsedTimer>
#include <QImage>
#include <QQuickItem>
#include <QThread>
#include <QTimer>
#include <QVariant>
#include <QWindow>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <optional>
#include <utility>
#include <vector>

namespace {

constexpr int kSongViewWidth = 1280;
constexpr int kSongViewHeight = 800;
constexpr int kHeaderLeft = 64;
constexpr int kHeaderTop = 96;
constexpr int kHeaderWidth = 360;
constexpr int kHeaderVisibleRows = 2;
constexpr int kExposurePollMilliseconds = 10;
constexpr int kExposureTimeoutMilliseconds = 1000;
constexpr int kWheelNotch = 120;
constexpr int kActivityHeightTolerancePixels = 1;
constexpr qreal kGeometryTolerance = 0.01;
constexpr qreal kWheelProbeCoordinate = 1.0;
constexpr qreal kPointerProbeExtent = 2.0;

// Native show and close transitions need all queued window-lifecycle events dispatched.
void processWindowEvents()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

// QML property and scene updates use the Quick-specific barrier after each visual state change.
void settleQuick()
{
    checks::support::pumpQuick();
}

bool waitForNativeWindowExposure(SongView &view)
{
    QElapsedTimer elapsed;
    elapsed.start();
    do {
        processWindowEvents();
        QWindow *const window = view.windowHandle();
        if (view.isVisible() && window && window->isExposed())
            return true;
        QThread::msleep(kExposurePollMilliseconds);
    } while (elapsed.elapsed() < kExposureTimeoutMilliseconds);
    return false;
}

void check(int &failures, bool condition, const char *message)
{
    if (condition)
        return;
    std::fprintf(stderr, "trackheaderquickcheck: FAIL: %s\n", message);
    ++failures;
}

bool near(qreal actual, qreal expected)
{
    return std::abs(actual - expected) <= kGeometryTolerance;
}

bool sameRect(const QRectF &actual, const QRectF &expected)
{
    return near(actual.x(), expected.x()) && near(actual.y(), expected.y()) &&
           near(actual.width(), expected.width()) && near(actual.height(), expected.height());
}

QVariant rowData(const songview::TrackHeaderModel &model, int row, int role)
{
    return model.data(model.index(row, 0), role);
}

std::vector<int> visibleTracks(const MidiTimeline &timeline)
{
    std::vector<int> tracks;
    for (int track = 0; track < 16; ++track) {
        if (timeline.tracks[track].used)
            tracks.push_back(track);
    }
    return tracks;
}

std::vector<int> modelTracks(const songview::TrackHeaderModel &model)
{
    std::vector<int> tracks;
    for (int row = 0; row < model.rowCount(); ++row) {
        if (!rowData(model, row, songview::TrackHeaderModel::IsAddTrackRole).toBool())
            tracks.push_back(rowData(model, row, songview::TrackHeaderModel::TrackRole).toInt());
    }
    return tracks;
}

std::optional<int> rowForTrack(const songview::TrackHeaderModel &model, int track)
{
    for (int row = 0; row < model.rowCount(); ++row) {
        if (!rowData(model, row, songview::TrackHeaderModel::IsAddTrackRole).toBool() &&
            rowData(model, row, songview::TrackHeaderModel::TrackRole).toInt() == track) {
            return row;
        }
    }
    return std::nullopt;
}

std::optional<int> addTrackRow(const songview::TrackHeaderModel &model)
{
    for (int row = 0; row < model.rowCount(); ++row) {
        if (rowData(model, row, songview::TrackHeaderModel::IsAddTrackRole).toBool())
            return row;
    }
    return std::nullopt;
}

std::optional<QPointF> inputPointForRow(int &failures, const songview::TrackHeaderModel &model,
                                        const songview::TimelineInputItem &input, int row,
                                        const QRectF &rowLocalRect, const char *message)
{
    const QRectF inputBounds = input.bounds();
    const QRectF inputRect =
        rowLocalRect.translated(0.0, row * model.rowHeight() - model.scrollY());
    check(failures, !rowLocalRect.isEmpty() && inputBounds.contains(inputRect), message);
    if (rowLocalRect.isEmpty() || !inputBounds.contains(inputRect))
        return std::nullopt;
    return inputRect.center();
}

songview::TimelinePointerInput pointerInput(const songview::TimelineInputItem &input,
                                            QPointF position, Qt::MouseButton button,
                                            Qt::MouseButtons buttons,
                                            Qt::KeyboardModifiers modifiers = Qt::NoModifier)
{
    return {position, input.mapToGlobal(position), button, buttons, modifiers};
}

songview::TimelineWheelInput wheelInput(const songview::TimelineInputItem &input, QPointF position,
                                        QPoint pixelDelta, QPoint angleDelta, bool inverted = false)
{
    return {position,       input.mapToGlobal(position), pixelDelta, angleDelta,
            Qt::NoModifier, Qt::NoScrollPhase,           inverted};
}

struct DataChange {
    int firstRow = -1;
    int lastRow = -1;
    QList<int> roles;
};

int pixelByteStride(const QImage &image)
{
    return image.depth() > 0 && image.depth() % 8 == 0 ? image.depth() / 8 : 0;
}

bool hasDistinctPixels(const QImage &image)
{
    const int stride = pixelByteStride(image);
    if (image.isNull() || image.size().isEmpty() || stride == 0 ||
        image.bytesPerLine() < image.width() * stride) {
        return false;
    }

    const uchar *const firstPixel = image.constScanLine(0);
    for (int y = 0; y < image.height(); ++y) {
        const uchar *const scanLine = image.constScanLine(y);
        for (int offset = 0; offset < image.width() * stride; offset += stride) {
            if (std::memcmp(scanLine + offset, firstPixel, stride) != 0)
                return true;
        }
    }
    return false;
}

int changedBottomSpan(const QImage &before, const QImage &after, const QRect &logicalRect)
{
    const int stride = pixelByteStride(before);
    if (before.isNull() || after.isNull() || before.size() != after.size() ||
        before.format() != after.format() || stride == 0 ||
        before.bytesPerLine() < before.width() * stride ||
        after.bytesPerLine() < after.width() * stride) {
        return 0;
    }

    const QRect deviceRect = checks::support::devicePixelRect(before, logicalRect);
    if (deviceRect.isEmpty() || !after.rect().contains(deviceRect))
        return 0;

    const int x = deviceRect.x() + deviceRect.width() / 2;
    int changedPixels = 0;
    bool reachedChangedPixels = false;
    for (int y = deviceRect.bottom(); y >= deviceRect.top(); --y) {
        const uchar *const beforePixel = before.constScanLine(y) + x * stride;
        const uchar *const afterPixel = after.constScanLine(y) + x * stride;
        if (std::memcmp(beforePixel, afterPixel, stride) != 0) {
            reachedChangedPixels = true;
            ++changedPixels;
        } else if (reachedChangedPixels) {
            break;
        }
    }
    return changedPixels;
}

} // namespace

int runTrackHeaderQuickCheck(const QString &projectRoot, const QString &songLabel)
{
    QString error;
    auto loadedSong = checks::LoadedSong::load(projectRoot, songLabel, error);
    if (!loadedSong) {
        std::fprintf(stderr, "trackheaderquickcheck: %s\n", qPrintable(error));
        return 1;
    }
    auto rig = checks::SongViewRig::create(std::move(loadedSong), 48000.0, error);
    if (!rig) {
        std::fprintf(stderr, "trackheaderquickcheck: %s\n", qPrintable(error));
        return 1;
    }

    int failures = 0;
    SongView &view = rig->view();
    SongDocument &document = rig->document();
    const std::vector<int> fixtureTracks = visibleTracks(rig->timeline());
    const auto finish = [&] {
        view.close();
        processWindowEvents();
        if (failures == 0)
            std::fprintf(stderr, "trackheaderquickcheck: PASS\n");
        return failures == 0 ? 0 : 1;
    };

    // QML evaluates bindings before TimelineInputItem attaches the production model. Exercise that
    // deliberately with an unattached model instead of relying on a hidden widget fallback.
    {
        TrackActivity startupActivity;
        songview::TrackHeaderModel startupModel(view);
        startupModel.rebuild(startupActivity, false);
        check(failures, startupModel.viewportHeight() == 0.0,
              "unattached model did not publish zero viewport height");
        check(failures, startupModel.maximumScrollY() == 0.0,
              "unattached model did not publish zero maximum scroll");
        check(failures,
              startupModel.rowCount() == int(fixtureTracks.size()) + int(document.canAddTrack()),
              "unattached model did not rebuild visible records and its add row");
        for (int row = 0; row < startupModel.rowCount(); ++row) {
            if (rowData(startupModel, row, songview::TrackHeaderModel::IsAddTrackRole).toBool())
                continue;
            check(
                failures,
                rowData(startupModel, row, songview::TrackHeaderModel::ActivityLeftHeightRole)
                            .toReal() == 0.0 &&
                    rowData(startupModel, row, songview::TrackHeaderModel::ActivityRightHeightRole)
                            .toReal() == 0.0,
                "unattached model exposed nonzero activity geometry");
        }
    }

    view.resize(kSongViewWidth, kSongViewHeight);
    view.show();
    processWindowEvents();

    auto *headers = view.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"),
                                                                 Qt::FindDirectChildrenOnly);
    auto *quick = view.findChild<songview::TimelineQuickView *>(
        QStringLiteral("timelineQuickCanvas"), Qt::FindDirectChildrenOnly);
    if (!headers || !quick || !quick->rootObject() || !quick->quickWindow()) {
        check(failures, false, "SongView did not create the Quick track-header model and host");
        return finish();
    }
    if (!waitForNativeWindowExposure(view)) {
        check(failures, false, "SongView did not create an exposed native window");
        return finish();
    }

    QQuickItem *const root = quick->rootObject();
    auto *band = root->findChild<QQuickItem *>(QStringLiteral("timelineQuickTrackHeaders"));
    auto *input =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineTrackHeadersInput"));
    auto *rows = root->findChild<QObject *>(QStringLiteral("timelineTrackHeaderRows"));
    auto *scrollbar = root->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderScrollBar"));
    auto *thumb = root->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderScrollThumb"));
    auto *rename = root->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderRename"));
    auto *marker =
        root->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderReorderMarker"));
    auto *toolTip = root->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderToolTip"));
    if (!band || !input || !rows || !scrollbar || !thumb || !rename || !marker || !toolTip) {
        check(failures, false, "Qt Quick track-header surface lacks a required named object");
        return finish();
    }

    const int rowHeight = headers->rowHeight();
    if (rowHeight <= 0) {
        check(failures, false, "track-header model published a nonpositive row height");
        return finish();
    }

    const QRect isolatedHeaderRect{kHeaderLeft, kHeaderTop, kHeaderWidth,
                                   rowHeight * kHeaderVisibleRows};
    songview::TimelineBandLayout isolatedLayout = view.timelineBandLayout();
    for (auto &geometry : isolatedLayout.bands)
        geometry.reset();
    isolatedLayout.geometry(songview::TimelineBand::TrackHeaders) =
        songview::TimelineBandGeometry{isolatedHeaderRect, 0};
    quick->setBandLayout(std::move(isolatedLayout));
    settleQuick();
    quick->syncAppearance();
    settleQuick();

    TrackActivity darkActivity;
    headers->rebuild(darkActivity, true);
    settleQuick();

    const QRect hostRect = quick->geometry();
    const QRectF localHeaderRect(isolatedHeaderRect.translated(-hostRect.topLeft()));
    check(failures, hostRect.contains(isolatedHeaderRect),
          "Quick host geometry did not enclose the isolated TrackHeaders rectangle");
    check(failures, root->property("trackHeadersBandVisible").toBool(),
          "Quick root did not mark the isolated TrackHeaders band visible");
    check(failures, sameRect(root->property("trackHeadersBandRect").toRectF(), localHeaderRect),
          "Quick root did not publish the isolated TrackHeaders rectangle");
    check(failures, band->isVisible(), "Quick header band was not visible");
    check(failures, near(band->x(), localHeaderRect.x()),
          "Quick header band x did not match its published rectangle");
    check(failures, near(band->y(), localHeaderRect.y()),
          "Quick header band y did not match its published rectangle");
    check(failures, near(band->width(), localHeaderRect.width()),
          "Quick header band width did not match its published rectangle");
    check(failures, near(band->height(), localHeaderRect.height()),
          "Quick header band height did not match its published rectangle");
    check(failures, input->isVisible(), "Quick header input was not visible");
    check(failures, near(input->width(), isolatedHeaderRect.width() - headers->scrollbarWidth()),
          "header input width did not match the model scrollbar allocation");
    check(failures, near(input->height(), isolatedHeaderRect.height()),
          "header input height did not match the isolated band");
    check(failures, near(scrollbar->x(), input->width()),
          "header scrollbar did not begin at the input edge");
    check(failures, near(scrollbar->width(), headers->scrollbarWidth()),
          "header scrollbar width did not match the model");
    check(failures, near(headers->viewportHeight(), isolatedHeaderRect.height()),
          "model viewport height did not follow the isolated Quick input");
    check(failures, headers->contentHeight() == headers->rowCount() * rowHeight,
          "model content height did not follow its row geometry");
    check(failures, !headers->appearance().isEmpty(),
          "model did not publish Quick appearance state");

    const auto checkRepeaterCount = [&] {
        check(failures, rows->property("count").toInt() == headers->rowCount(),
              "Quick row repeater did not mirror TrackHeaderModel rows");
    };
    checkRepeaterCount();

    QString captureError;
    const QImage initialHeaderFrame =
        checks::support::captureQuickBand(view, isolatedHeaderRect, &captureError);
    check(failures, !initialHeaderFrame.isNull(),
          "isolated TrackHeaders framebuffer capture failed");
    if (!initialHeaderFrame.isNull()) {
        check(failures, hasDistinctPixels(initialHeaderFrame),
              "isolated TrackHeaders framebuffer was visually blank");
    }

    check(failures, modelTracks(*headers) == fixtureTracks,
          "model rebuild did not preserve visible engine-track order");
    if (fixtureTracks.size() < 2 || !document.canAddTrack() || !addTrackRow(*headers)) {
        check(failures, false,
              "Route 101 fixture lacks the tracks or add capacity needed for header coverage");
        return finish();
    }

    const int sourceTrack = fixtureTracks.front();
    const int selectionTrack = fixtureTracks[1];
    const int reorderTargetTrack = fixtureTracks.back();
    const QString renamedName = QStringLiteral("HdrSrc");
    const std::optional<int> sourceRow = rowForTrack(*headers, sourceTrack);
    const std::optional<int> selectionRow = rowForTrack(*headers, selectionTrack);
    int voiceTrack = -1;
    for (int track : fixtureTracks) {
        if (view.currentProgram(track) >= 0) {
            voiceTrack = track;
            break;
        }
    }
    const std::optional<int> voiceRow =
        voiceTrack >= 0 ? rowForTrack(*headers, voiceTrack) : std::nullopt;
    if (!sourceRow || !selectionRow || !voiceRow) {
        check(failures, false, "Route 101 fixture lacks addressable track-header and voice rows");
        return finish();
    }

    const auto titlePoint = [&](int row, const char *message) {
        return inputPointForRow(
            failures, *headers, *input, row,
            rowData(*headers, row, songview::TrackHeaderModel::TitleRectRole).toRectF(), message);
    };
    const auto voicePoint = [&](int row, const char *message) {
        return inputPointForRow(failures, *headers, *input, row, headers->voiceLineRect(), message);
    };
    const auto mutePoint = [&](int row, const char *message) {
        return inputPointForRow(failures, *headers, *input, row, headers->muteButtonRect(),
                                message);
    };
    const auto soloPoint = [&](int row, const char *message) {
        return inputPointForRow(failures, *headers, *input, row, headers->soloButtonRect(),
                                message);
    };

    const auto exerciseSelectionAndVoice = [&] {
        headers->setScrollY(0.0);
        const std::optional<QPointF> body =
            titlePoint(*selectionRow, "selected header title rect was outside the Quick input");
        if (!body)
            return;
        check(failures,
              headers->pointerPress(pointerInput(*input, *body, Qt::LeftButton, Qt::LeftButton)),
              "plain header press was not handled");
        check(failures,
              headers->pointerRelease(pointerInput(*input, *body, Qt::LeftButton, Qt::NoButton)),
              "plain header release was not handled");
        check(failures, view.selectionModel().primaryTrack() == selectionTrack,
              "plain header click did not select its track");

        headers->setScrollY(qreal(*voiceRow * rowHeight));
        const std::optional<QPointF> voice =
            voicePoint(*voiceRow, "voice line rect was outside the Quick input");
        if (!voice) {
            headers->setScrollY(0.0);
            return;
        }

        int revealedProgram = -1;
        int revealCount = 0;
        const QMetaObject::Connection revealConnection =
            QObject::connect(&view, &SongView::revealVoiceRequested, &view,
                             [&revealedProgram, &revealCount](int program) {
                                 revealedProgram = program;
                                 ++revealCount;
                             });
        check(failures,
              headers->pointerMove(pointerInput(*input, *voice, Qt::NoButton, Qt::NoButton)),
              "voice hover was not handled");
        check(failures,
              rowData(*headers, *voiceRow, songview::TrackHeaderModel::VoiceHoveredRole).toBool(),
              "voice hover did not publish voiceHovered");
        check(failures,
              headers->pointerPress(pointerInput(*input, *voice, Qt::LeftButton, Qt::LeftButton)),
              "voice press was not handled");
        check(failures,
              rowData(*headers, *voiceRow, songview::TrackHeaderModel::VoicePressedRole).toBool(),
              "voice press did not publish voicePressed");
        check(failures, view.selectionModel().primaryTrack() == voiceTrack,
              "voice press did not select its track");
        check(failures,
              headers->pointerRelease(pointerInput(*input, *voice, Qt::LeftButton, Qt::NoButton)),
              "voice release was not handled");
        check(failures, revealCount == 1, "voice click did not request one voice reveal");
        check(failures, revealedProgram == view.currentProgram(voiceTrack),
              "voice click revealed the wrong program");
        check(failures,
              !rowData(*headers, *voiceRow, songview::TrackHeaderModel::VoicePressedRole).toBool(),
              "voice release left voicePressed set");
        QObject::disconnect(revealConnection);
        headers->setScrollY(0.0);
    };

    const auto exerciseMuteAndSolo = [&] {
        view.selectTrack(selectionTrack);
        view.setTrackMute(sourceTrack, false);
        const std::optional<QPointF> mute =
            mutePoint(*sourceRow, "mute button rect was outside the Quick input");
        const std::optional<QPointF> solo =
            soloPoint(*sourceRow, "solo button rect was outside the Quick input");
        const std::optional<QPointF> sourceTitle =
            titlePoint(*sourceRow, "source title rect was outside the Quick input");
        if (!mute || !solo || !sourceTitle)
            return;
        check(failures,
              headers->pointerMove(pointerInput(*input, *mute, Qt::NoButton, Qt::NoButton)),
              "mute hover was not handled");
        check(failures,
              rowData(*headers, *sourceRow, songview::TrackHeaderModel::MuteHoveredRole).toBool(),
              "mute hover did not publish muteHovered");
        headers->pointerLeave();
        check(failures,
              !rowData(*headers, *sourceRow, songview::TrackHeaderModel::MuteHoveredRole).toBool(),
              "pointer leave did not clear muteHovered");

        check(failures,
              headers->pointerPress(pointerInput(*input, *mute, Qt::LeftButton, Qt::LeftButton)),
              "mute press was not handled");
        check(failures,
              rowData(*headers, *sourceRow, songview::TrackHeaderModel::MutePressedRole).toBool(),
              "mute press did not publish mutePressed");
        check(failures,
              headers->pointerPress(pointerInput(*input, *sourceTitle, Qt::RightButton,
                                                 Qt::LeftButton | Qt::RightButton)),
              "right press with left held was not handled");
        check(failures,
              rowData(*headers, *sourceRow, songview::TrackHeaderModel::MutePressedRole).toBool(),
              "right press with left held did not preserve mutePressed");
        check(failures,
              headers->pointerRelease(
                  pointerInput(*input, *sourceTitle, Qt::RightButton, Qt::LeftButton)),
              "non-left mute release was not handled");
        check(failures, !view.trackMuted(sourceTrack),
              "non-left mute release changed the mute state");
        check(failures,
              !rowData(*headers, *sourceRow, songview::TrackHeaderModel::MutePressedRole).toBool(),
              "non-left mute release left mutePressed set");

        check(failures,
              headers->pointerPress(pointerInput(*input, *mute, Qt::LeftButton, Qt::LeftButton)),
              "cancellable mute press was not handled");
        headers->inputCancelled(songview::TimelineInputCancelReason::FocusLost);
        check(failures,
              !rowData(*headers, *sourceRow, songview::TrackHeaderModel::MutePressedRole).toBool(),
              "input cancellation did not clear mutePressed");
        check(failures, !view.trackMuted(sourceTrack), "input cancellation changed the mute state");
        check(failures,
              !headers->pointerRelease(pointerInput(*input, *mute, Qt::LeftButton, Qt::NoButton)),
              "input cancellation left a releasable mute press");

        check(failures,
              headers->pointerPress(pointerInput(*input, *mute, Qt::LeftButton, Qt::LeftButton)),
              "committing mute press was not handled");
        check(failures,
              headers->pointerRelease(pointerInput(*input, *mute, Qt::LeftButton, Qt::NoButton)),
              "committing mute release was not handled");
        check(failures, view.trackMuted(sourceTrack), "mute click did not toggle the mute state");
        check(failures,
              rowData(*headers, *sourceRow, songview::TrackHeaderModel::MuteCheckedRole).toBool(),
              "mute click did not publish muteChecked");
        check(failures, view.selectionModel().primaryTrack() == selectionTrack,
              "mute click changed the selected track");
        headers->activateMute(sourceTrack);
        check(failures, !view.trackMuted(sourceTrack),
              "accessible mute activation did not use the same model action");

        view.setTrackSolo(sourceTrack, false);
        check(failures,
              headers->pointerMove(pointerInput(*input, *solo, Qt::NoButton, Qt::NoButton)),
              "solo hover was not handled");
        check(failures,
              rowData(*headers, *sourceRow, songview::TrackHeaderModel::SoloHoveredRole).toBool(),
              "solo hover did not publish soloHovered");
        headers->pointerLeave();
        check(failures,
              !rowData(*headers, *sourceRow, songview::TrackHeaderModel::SoloHoveredRole).toBool(),
              "pointer leave did not clear soloHovered");
        check(failures,
              headers->pointerPress(pointerInput(*input, *solo, Qt::LeftButton, Qt::LeftButton)),
              "solo press was not handled");
        check(failures,
              headers->pointerRelease(pointerInput(*input, *solo, Qt::LeftButton, Qt::NoButton)),
              "solo release was not handled");
        check(failures, view.trackSoloed(sourceTrack), "solo click did not toggle the solo state");
        check(failures,
              rowData(*headers, *sourceRow, songview::TrackHeaderModel::SoloCheckedRole).toBool(),
              "solo click did not publish soloChecked");
        headers->activateSolo(sourceTrack);
        check(failures, !view.trackSoloed(sourceTrack),
              "accessible solo activation did not use the same model action");
    };

    const auto exerciseActivityAndScrolling = [&] {
        QString beforeActivityError;
        const QImage beforeActivity =
            checks::support::captureQuickBand(view, isolatedHeaderRect, &beforeActivityError);
        check(failures, !beforeActivity.isNull(),
              "could not capture the dark header activity framebuffer");

        std::vector<DataChange> activityChanges;
        const QMetaObject::Connection activityConnection =
            QObject::connect(headers, &QAbstractItemModel::dataChanged, headers,
                             [&activityChanges](const QModelIndex &first, const QModelIndex &last,
                                                const QList<int> &roles) {
                                 activityChanges.push_back({first.row(), last.row(), roles});
                             });
        TrackActivity activity;
        TrackActivityLevels levels{};
        levels[sourceTrack] = {255, 0};
        activity.advance(levels, 1.0f, true);
        headers->syncActivity(activity, true);
        check(failures, activityChanges.size() == 1,
              "activity update did not emit one bounded data change");
        if (activityChanges.size() == 1) {
            check(failures, activityChanges.front().firstRow == *sourceRow,
                  "activity update began at the wrong row");
            check(failures, activityChanges.front().lastRow == *sourceRow,
                  "activity update ended at the wrong row");
            check(failures,
                  activityChanges.front().roles ==
                      QList<int>{songview::TrackHeaderModel::ActivityLeftHeightRole,
                                 songview::TrackHeaderModel::ActivityRightHeightRole},
                  "activity update published unrelated model roles");
        }
        const qreal activeHeight =
            rowData(*headers, *sourceRow, songview::TrackHeaderModel::ActivityLeftHeightRole)
                .toReal();
        check(failures, activeHeight > 0.0, "activity update did not produce a left meter height");
        check(failures,
              rowData(*headers, *sourceRow, songview::TrackHeaderModel::ActivityRightHeightRole)
                      .toReal() == 0.0,
              "activity update did not keep the inactive right meter at zero");
        settleQuick();
        QString afterActivityError;
        const QImage afterActivity =
            checks::support::captureQuickBand(view, isolatedHeaderRect, &afterActivityError);
        check(failures, !afterActivity.isNull(),
              "could not capture the active header activity framebuffer");
        if (!beforeActivity.isNull() && !afterActivity.isNull() && activeHeight > 0.0) {
            const QRect logicalLeftMeter{0, *sourceRow * rowHeight,
                                         std::max(1, headers->activityWidth() / 2),
                                         std::max(0, rowHeight - headers->separatorWidth())};
            const int observedPixels =
                changedBottomSpan(beforeActivity, afterActivity, logicalLeftMeter);
            const int expectedPixels = qRound(activeHeight * afterActivity.devicePixelRatio());
            check(failures,
                  observedPixels >= std::max(1, expectedPixels - kActivityHeightTolerancePixels) &&
                      observedPixels <= expectedPixels + kActivityHeightTolerancePixels,
                  "painted left activity meter height did not match the model role");
        }
        activityChanges.clear();
        headers->syncActivity(activity, true);
        check(failures, activityChanges.empty(),
              "unchanged activity state emitted a model notification");
        QObject::disconnect(activityConnection);

        const qreal maximumScroll = headers->maximumScrollY();
        check(failures, maximumScroll > 0.0,
              "isolated header viewport did not make the model scrollable");
        if (maximumScroll <= 0.0)
            return;

        headers->setScrollY(maximumScroll + rowHeight);
        settleQuick();
        check(failures, near(headers->scrollY(), maximumScroll),
              "model scroll value did not clamp at its maximum");
        check(failures, scrollbar->isVisible(), "header scrollbar was not visible when scrollable");
        check(failures, thumb->isVisible(),
              "header scrollbar thumb was not visible when scrollable");
        check(failures, thumb->height() > 0.0, "header scrollbar thumb had no height");
        check(failures, thumb->y() >= 0.0, "header scrollbar thumb began above its track");
        check(failures, thumb->y() + thumb->height() <= scrollbar->height() + kGeometryTolerance,
              "header scrollbar thumb exceeded its track");

        headers->setScrollY(0.0);
        scrollbar->forceActiveFocus(Qt::TabFocusReason);
        checks::events::sendKey(*scrollbar, QEvent::KeyPress, Qt::Key_Down, Qt::NoModifier,
                                QString(), false, 1);
        checks::events::sendKey(*scrollbar, QEvent::KeyRelease, Qt::Key_Down, Qt::NoModifier,
                                QString(), false, 1);
        settleQuick();
        check(failures, near(headers->scrollY(), std::min<qreal>(rowHeight, maximumScroll)),
              "Down on the focused header scrollbar did not advance one row");

        const QPointF wheelProbe{kWheelProbeCoordinate, kWheelProbeCoordinate};
        const qreal atMaximum = headers->scrollY();
        check(failures, !headers->wheel(wheelInput(*input, wheelProbe, {}, QPoint{kWheelNotch, 0})),
              "horizontal wheel input was consumed by the header model");
        check(failures, near(headers->scrollY(), atMaximum),
              "horizontal wheel input changed header scrolling");
        headers->setScrollY(0.0);
        check(failures, headers->wheel(wheelInput(*input, wheelProbe, {}, QPoint{0, -kWheelNotch})),
              "vertical wheel input was not consumed by the header model");
        check(failures, headers->scrollY() > 0.0,
              "vertical wheel input did not update header scrolling");
        headers->setScrollY(0.0);
    };

    const auto exerciseTooltip = [&] {
        const std::optional<QPointF> tooltipPoint =
            titlePoint(*sourceRow, "tooltip source title rect was outside the Quick input");
        if (!tooltipPoint)
            return;
        check(failures,
              headers->pointerMove(pointerInput(*input, *tooltipPoint, Qt::NoButton, Qt::NoButton)),
              "header hover for tooltip was not handled");
        check(failures, headers->toolTipVisible(),
              "header hover did not publish tooltip visibility");
        check(failures, !headers->toolTipText().isEmpty(),
              "header hover did not publish tooltip text");
        check(failures, headers->toolTipPosition() == *tooltipPoint,
              "header hover did not publish tooltip position");
        settleQuick();
        // The locked Quick plan clamps the overlay tooltip to the Quick root, not to the header band.
        check(failures, toolTip->isVisible(), "Quick tooltip did not become visible");
        check(failures, toolTip->x() >= 0.0 && toolTip->y() >= 0.0,
              "Quick tooltip began outside the root");
        check(failures,
              toolTip->x() + toolTip->width() <= root->width() + kGeometryTolerance &&
                  toolTip->y() + toolTip->height() <= root->height() + kGeometryTolerance,
              "Quick tooltip did not clamp to the Quick root");
        headers->wheel(wheelInput(*input, *tooltipPoint, {}, QPoint{0, -kWheelNotch}));
        settleQuick();
        check(failures, !headers->toolTipVisible(), "scrolling did not clear model tooltip state");
        check(failures, !toolTip->isVisible(), "scrolling did not clear the Quick tooltip");
        headers->setScrollY(0.0);
    };

    const auto exerciseRename = [&]() -> std::optional<int> {
        const std::optional<QPointF> sourceTitle =
            titlePoint(*sourceRow, "rename source title rect was outside the Quick input");
        if (!sourceTitle)
            return std::nullopt;
        const QString originalName = document.trackName(sourceTrack);
        // rollcheckwindowing.cpp exercises the native QQuickWindow voice-line double-click picker.
        // This normalized-model path keeps double-click coverage focused on inline body rename.
        check(failures,
              headers->pointerDoubleClick(
                  pointerInput(*input, *sourceTitle, Qt::LeftButton, Qt::LeftButton)),
              "header body double-click was not handled");
        check(failures, headers->renamingTrack() == sourceTrack,
              "header body double-click did not begin inline rename");
        settleQuick();
        check(failures, rename->isVisible(), "inline rename editor was not visible");
        QQuickItem *const renameEditor = rename->parentItem();
        check(failures, renameEditor, "inline rename field did not have an editor parent");
        if (renameEditor) {
            check(failures, near(renameEditor->x(), headers->renameEditorRect().x()),
                  "inline rename editor x did not match the model");
            const qreal expectedY = *sourceRow * headers->rowHeight() - headers->scrollY() +
                                    headers->renameEditorRect().y();
            check(failures, near(renameEditor->y(), expectedY),
                  "inline rename editor y did not match its model row");
        }
        headers->finishRename(false, false);
        settleQuick();
        check(failures, headers->renamingTrack() == -1,
              "finishRename(false) did not clear inline rename state");
        check(failures, document.trackName(sourceTrack) == originalName,
              "finishRename(false) changed the track name");
        check(failures, !rename->isVisible(), "finishRename(false) left the Quick editor visible");

        headers->beginRename(sourceTrack);
        headers->setRenameDraft(QStringLiteral("Discard direct cancellation"));
        headers->cancelRename();
        check(failures, headers->renamingTrack() == -1,
              "cancelRename did not clear inline rename state");
        check(failures, document.trackName(sourceTrack) == originalName,
              "cancelRename changed the track name");

        headers->beginRename(sourceTrack);
        headers->setRenameDraft(QStringLiteral("Discard transient cancellation"));
        headers->cancelTransientState();
        settleQuick();
        check(failures, headers->renamingTrack() == -1,
              "transient cancellation did not clear inline rename state");
        check(failures, document.trackName(sourceTrack) == originalName,
              "transient cancellation changed the track name");
        check(failures, !rename->isVisible(),
              "transient cancellation left the Quick inline editor visible");

        headers->beginRename(sourceTrack);
        headers->setRenameDraft(renamedName);
        headers->finishRename(true, false);
        processWindowEvents();
        check(failures, headers->renamingTrack() == -1,
              "committed rename did not clear inline rename state");
        check(failures, document.trackName(sourceTrack) == renamedName,
              "committed rename did not write the model draft to its track");
        QString rebuildError;
        check(failures, rig->rebuildTimeline(rebuildError),
              "could not rebuild Route 101 after header rename");
        settleQuick();
        checkRepeaterCount();
        const std::optional<int> renamedSourceRow = rowForTrack(*headers, sourceTrack);
        check(failures, renamedSourceRow.has_value(), "renamed source track left the header model");
        if (!renamedSourceRow)
            return std::nullopt;
        check(failures,
              rowData(*headers, *renamedSourceRow, songview::TrackHeaderModel::TitleRole)
                  .toString()
                  .contains(renamedName),
              "rebuild did not publish the committed rename in the header model");
        return renamedSourceRow;
    };

    const auto exerciseReorder = [&](int reorderedSourceRow) {
        const std::optional<QPointF> reorderStart =
            titlePoint(reorderedSourceRow, "reorder source title rect was outside the Quick input");
        if (!reorderStart)
            return;

        const QPointF noOpDrop{reorderStart->x(), 0.0};
        const uint64_t revisionBeforeNoOp = document.revision();
        check(failures,
              headers->pointerPress(
                  pointerInput(*input, *reorderStart, Qt::LeftButton, Qt::LeftButton)),
              "no-op reorder press was not handled");
        check(failures,
              headers->pointerMove(pointerInput(*input, noOpDrop, Qt::NoButton, Qt::LeftButton)),
              "no-op reorder drag was not handled");
        check(failures, headers->reorderIndicatorVisible(),
              "no-op reorder drag did not show the indicator");
        check(failures, near(headers->reorderIndicatorY(), 0.0),
              "no-op reorder drag did not target the first slot");
        check(failures,
              headers->pointerRelease(pointerInput(*input, noOpDrop, Qt::LeftButton, Qt::NoButton)),
              "no-op reorder release was not handled");
        processWindowEvents();
        check(failures, document.revision() == revisionBeforeNoOp,
              "adjacent reorder slot mutated the document");

        const int trackRows = int(modelTracks(*headers).size());
        // A captured drag may leave the input item's bounds; the final drop slot is intentional.
        const QPointF endDrop{reorderStart->x(), qreal(trackRows * headers->rowHeight())};
        const uint64_t revisionBeforeCancel = document.revision();
        check(failures,
              headers->pointerPress(
                  pointerInput(*input, *reorderStart, Qt::LeftButton, Qt::LeftButton)),
              "cancellable reorder press was not handled");
        check(failures,
              headers->pointerMove(pointerInput(*input, endDrop, Qt::NoButton, Qt::LeftButton)),
              "cancellable reorder drag was not handled");
        check(failures, headers->reorderIndicatorVisible(),
              "cancellable reorder drag did not show the indicator");
        check(failures, near(headers->reorderIndicatorY(), trackRows * headers->rowHeight()),
              "cancellable reorder drag did not calculate the final slot");
        settleQuick();
        check(failures, marker->isVisible(), "Quick reorder marker did not become visible");
        check(failures, marker->y() >= 0.0,
              "Quick reorder marker began above the visible header band");
        check(failures, marker->y() + marker->height() <= input->height() + kGeometryTolerance,
              "Quick reorder marker did not clip the logical target to the band");
        headers->inputCancelled(songview::TimelineInputCancelReason::PointerUngrabbed);
        check(failures, !headers->reorderIndicatorVisible(),
              "input cancellation did not clear the reorder indicator");
        check(failures,
              !headers->pointerRelease(pointerInput(*input, endDrop, Qt::LeftButton, Qt::NoButton)),
              "input cancellation left a releasable reorder drag");
        check(failures, document.revision() == revisionBeforeCancel,
              "input cancellation committed the staged reorder");

        check(failures,
              headers->pointerPress(
                  pointerInput(*input, *reorderStart, Qt::LeftButton, Qt::LeftButton)),
              "non-left reorder press was not handled");
        check(failures,
              headers->pointerMove(pointerInput(*input, endDrop, Qt::NoButton, Qt::LeftButton)),
              "non-left reorder drag was not handled");
        check(
            failures,
            headers->pointerRelease(pointerInput(*input, endDrop, Qt::RightButton, Qt::LeftButton)),
            "non-left reorder release was not handled");
        check(failures, !headers->reorderIndicatorVisible(),
              "non-left reorder release left the indicator visible");
        check(failures, document.revision() == revisionBeforeCancel,
              "non-left reorder release committed a move");

        const uint64_t revisionBeforeMove = document.revision();
        check(failures,
              headers->pointerPress(
                  pointerInput(*input, *reorderStart, Qt::LeftButton, Qt::LeftButton)),
              "committing reorder press was not handled");
        check(failures,
              headers->pointerMove(pointerInput(*input, endDrop, Qt::NoButton, Qt::LeftButton)),
              "committing reorder drag was not handled");
        check(failures,
              headers->pointerRelease(pointerInput(*input, endDrop, Qt::LeftButton, Qt::NoButton)),
              "committing reorder release was not handled");
        processWindowEvents();
        check(failures, document.revision() > revisionBeforeMove,
              "final reorder did not mutate the document");
        check(failures, document.trackName(reorderTargetTrack) == renamedName,
              "final reorder did not move the renamed source to the target track");
        QString rebuildError;
        check(failures, rig->rebuildTimeline(rebuildError),
              "could not rebuild Route 101 after header reorder");
        settleQuick();
        checkRepeaterCount();
        const std::optional<int> movedRow = rowForTrack(*headers, reorderTargetTrack);
        check(failures, movedRow.has_value(), "reordered target track left the header model");
        if (!movedRow)
            return;
        check(failures,
              rowData(*headers, *movedRow, songview::TrackHeaderModel::TitleRole)
                  .toString()
                  .contains(renamedName),
              "rebuild did not publish the reordered header record");
    };

    const auto exerciseAddTrack = [&] {
        const std::optional<int> row = addTrackRow(*headers);
        if (!row) {
            check(failures, false, "reordered model lost its add-track row");
            return;
        }
        headers->setScrollY(headers->maximumScrollY());
        const qreal probeOffset = kPointerProbeExtent / 2.0;
        const std::optional<QPointF> addPoint = inputPointForRow(
            failures, *headers, *input, *row,
            QRectF{input->width() / 2.0 - probeOffset, headers->rowHeight() / 2.0 - probeOffset,
                   kPointerProbeExtent, kPointerProbeExtent},
            "add row rect was outside the Quick input");
        if (!addPoint) {
            headers->setScrollY(0.0);
            return;
        }
        const uint64_t revisionBeforeAdd = document.revision();
        const int rowCountBeforeAdd = headers->rowCount();
        const std::vector<int> tracksBeforeAdd = modelTracks(*headers);
        const int primaryBeforeAdd = view.selectionModel().primaryTrack();

        check(failures,
              headers->pointerMove(pointerInput(*input, *addPoint, Qt::NoButton, Qt::NoButton)),
              "add-row hover was not handled");
        check(failures,
              rowData(*headers, *row, songview::TrackHeaderModel::AddHoveredRole).toBool(),
              "add-row hover did not publish addHovered");
        headers->pointerLeave();
        check(failures,
              !rowData(*headers, *row, songview::TrackHeaderModel::AddHoveredRole).toBool(),
              "pointer leave did not clear addHovered");

        check(failures,
              headers->pointerPress(
                  pointerInput(*input, *addPoint, Qt::RightButton, Qt::RightButton)),
              "non-left add-row press was not handled");
        check(failures, view.selectionModel().primaryTrack() == primaryBeforeAdd,
              "non-left add-row press selected a track");
        check(failures, document.revision() == revisionBeforeAdd,
              "non-left add-row press mutated the document");

        check(
            failures,
            headers->pointerPress(pointerInput(*input, *addPoint, Qt::LeftButton, Qt::LeftButton)),
            "cancellable add-row press was not handled");
        check(failures,
              rowData(*headers, *row, songview::TrackHeaderModel::AddPressedRole).toBool(),
              "add-row press did not publish addPressed");
        headers->inputCancelled(songview::TimelineInputCancelReason::FocusLost);
        check(failures,
              !rowData(*headers, *row, songview::TrackHeaderModel::AddPressedRole).toBool(),
              "input cancellation did not clear addPressed");
        check(failures, document.revision() == revisionBeforeAdd,
              "input cancellation activated the add row");
        check(
            failures,
            !headers->pointerRelease(pointerInput(*input, *addPoint, Qt::LeftButton, Qt::NoButton)),
            "input cancellation left a releasable add-row press");

        check(
            failures,
            headers->pointerPress(pointerInput(*input, *addPoint, Qt::LeftButton, Qt::LeftButton)),
            "leaving add-row press was not handled");
        const QPointF addCancelPoint = *addPoint - QPointF{0.0, qreal(headers->rowHeight())};
        check(failures, input->bounds().contains(addCancelPoint),
              "add-row cancellation point left the Quick input");
        check(failures,
              headers->pointerRelease(
                  pointerInput(*input, addCancelPoint, Qt::LeftButton, Qt::NoButton)),
              "leaving add-row release was not handled");
        check(failures, document.revision() == revisionBeforeAdd,
              "leaving the add row before release activated it");
        check(failures,
              !rowData(*headers, *row, songview::TrackHeaderModel::AddPressedRole).toBool(),
              "leaving the add row left addPressed set");

        // Pointer release is canonical; Accessible.onPressAction calls the same activateAddTrack() body, so a direct call would duplicate this modal mutation.
        check(
            failures,
            headers->pointerPress(pointerInput(*input, *addPoint, Qt::LeftButton, Qt::LeftButton)),
            "committing add-row press was not handled");
        QTimer pickerPoll;
        pickerPoll.setInterval(0);
        bool pickerSeen = false;
        const QMetaObject::Connection pickerConnection =
            QObject::connect(&pickerPoll, &QTimer::timeout, &view, [&] {
                auto *dialog = view.findChild<QDialog *>();
                if (!dialog)
                    return;
                pickerSeen = true;
                dialog->accept();
            });
        pickerPoll.start();
        check(
            failures,
            headers->pointerRelease(pointerInput(*input, *addPoint, Qt::LeftButton, Qt::NoButton)),
            "committing add-row release was not handled");
        processWindowEvents();
        pickerPoll.stop();
        QObject::disconnect(pickerConnection);
        check(failures, pickerSeen, "add-row commit did not open its voice picker");
        check(failures, document.revision() > revisionBeforeAdd,
              "add-row commit did not mutate the document");

        QString rebuildError;
        check(failures, rig->rebuildTimeline(rebuildError),
              "could not rebuild Route 101 after adding a header track");
        settleQuick();
        checkRepeaterCount();
        const std::vector<int> tracksAfterAdd = modelTracks(*headers);
        const std::optional<int> rowAfterAdd = addTrackRow(*headers);
        check(failures, headers->rowCount() == rowCountBeforeAdd + 1,
              "add-row commit did not add one model row");
        check(failures, tracksAfterAdd.size() == tracksBeforeAdd.size() + 1,
              "add-row commit did not add one track record");
        check(failures, std::is_sorted(tracksAfterAdd.begin(), tracksAfterAdd.end()),
              "add-row rebuild did not preserve engine-track order");
        check(failures,
              std::includes(tracksAfterAdd.begin(), tracksAfterAdd.end(), tracksBeforeAdd.begin(),
                            tracksBeforeAdd.end()),
              "add-row rebuild discarded an existing track record");
        check(failures,
              std::adjacent_find(tracksAfterAdd.begin(), tracksAfterAdd.end()) ==
                  tracksAfterAdd.end(),
              "add-row rebuild did not create a distinct engine-track record");
        check(failures, rowAfterAdd && *rowAfterAdd == headers->rowCount() - 1,
              "add-row rebuild did not retain one trailing add row");
        headers->setScrollY(0.0);
    };

    exerciseSelectionAndVoice();
    exerciseMuteAndSolo();
    exerciseActivityAndScrolling();
    exerciseTooltip();
    const std::optional<int> renamedSourceRow = exerciseRename();
    if (!renamedSourceRow)
        return finish();
    exerciseReorder(*renamedSourceRow);
    exerciseAddTrack();
    return finish();
}
