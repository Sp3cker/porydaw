#include "checks/trackheaders/tst_trackheaders.h"

#include <QtTest>

#include <QAbstractItemModel>
#include <QCoreApplication>

#include <algorithm>
#include <cstring>
#include <optional>
#include <vector>

#include "checks/support/quickframebuffer.h"
#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/activity/trackactivity.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/trackheadermodel.h"

namespace {

constexpr int kHeightTolerance = 1;

struct DataChange final {
    int first = -1;
    int last = -1;
    QList<int> roles;
};

QVariant rowData(const songview::TrackHeaderModel &model, int row, int role)
{
    return model.data(model.index(row, 0), role);
}

int pixelStride(const QImage &image)
{
    return image.depth() > 0 && image.depth() % 8 == 0 ? image.depth() / 8 : 0;
}

int changedBottomSpan(const QImage &before, const QImage &after, const QRect &logicalRect,
                      bool rightChannel)
{
    const int stride = pixelStride(before);
    if (before.isNull() || after.isNull() || before.size() != after.size() ||
        before.format() != after.format() || stride == 0 ||
        before.bytesPerLine() < before.width() * stride ||
        after.bytesPerLine() < after.width() * stride) {
        return 0;
    }
    const QRect device = checks::support::devicePixelRect(before, logicalRect);
    if (device.isEmpty() || !after.rect().contains(device))
        return 0;
    const int x =
        rightChannel ? device.right() - device.width() / 4 : device.x() + device.width() / 4;
    int changed = 0;
    bool seen = false;
    for (int y = device.bottom(); y >= device.top(); --y) {
        const uchar *const beforePixel = before.constScanLine(y) + x * stride;
        const uchar *const afterPixel = after.constScanLine(y) + x * stride;
        if (std::memcmp(beforePixel, afterPixel, stride) != 0) {
            seen = true;
            ++changed;
        } else if (seen) {
            break;
        }
    }
    return changed;
}

} // namespace

void TrackHeadersTest::activityRasterMatchesRolesAndIsSilentWhenUnchanged()
{
    TrackHeadersFixture &fx = fixture();
    songview::TrackHeaderModel &headers = fx.headers();
    const std::optional<int> sourceRow = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(sourceRow);

    QString error;
    const QImage before = fx.captureBand(error);
    QVERIFY2(!before.isNull(), qPrintable(error));
    std::vector<DataChange> changes;
    const QMetaObject::Connection observed = QObject::connect(
        &headers, &QAbstractItemModel::dataChanged, &headers,
        [&changes](const QModelIndex &first, const QModelIndex &last, const QList<int> &roles) {
            changes.push_back({first.row(), last.row(), roles});
        });

    TrackActivity activity;
    TrackActivityLevels levels{};
    levels[fx.sourceTrack()] = {255, 0};
    activity.advance(levels, 1.0F, true);
    headers.syncActivity(activity, true);
    QCOMPARE(int(changes.size()), 1);
    QCOMPARE(changes.front().first, *sourceRow);
    QCOMPARE(changes.front().last, *sourceRow);
    const QList<int> expectedRoles{songview::TrackHeaderModel::ActivityLeftHeightRole,
                                   songview::TrackHeaderModel::ActivityRightHeightRole};
    QCOMPARE(changes.front().roles, expectedRoles);
    const qreal leftHeight =
        rowData(headers, *sourceRow, songview::TrackHeaderModel::ActivityLeftHeightRole).toReal();
    QCOMPARE(
        rowData(headers, *sourceRow, songview::TrackHeaderModel::ActivityRightHeightRole).toReal(),
        0.0);
    QVERIFY(leftHeight > 0.0);
    checks::support::pumpQuick();
    const QImage after = fx.captureBand(error);
    QVERIFY2(!after.isNull(), qPrintable(error));
    const QRect leftMeter{0, *sourceRow * fx.rowHeight(), std::max(1, headers.activityWidth() / 2),
                          std::max(0, fx.rowHeight() - headers.separatorWidth())};
    const int observedLeft = changedBottomSpan(before, after, leftMeter, false);
    const int expectedLeft = qRound(leftHeight * after.devicePixelRatio());
    QVERIFY(observedLeft >= std::max(1, expectedLeft - kHeightTolerance));
    QVERIFY(observedLeft <= expectedLeft + kHeightTolerance);

    changes.clear();
    headers.syncActivity(activity, true);
    QVERIFY(changes.empty());
    QObject::disconnect(observed);
}

void TrackHeadersTest::voiceSubtitleFollowsProgramPosition()
{
    TrackHeadersFixture &fx = fixture();
    songview::TrackHeaderModel &headers = fx.headers();
    SongView &view = fx.view();
    SongDocument &doc = fx.tab().document();
    const std::optional<int> row = fx.rowForTrack(fx.voiceTrack());
    QVERIFY(row);

    // The header voice line is live: currentProgram is the last program
    // change at or before the display position — the playhead while playing,
    // the edit cursor otherwise — falling back to the track's first program
    // (which is what primes the engine before any change).
    const int base = view.currentProgram(fx.voiceTrack());
    const int atStart = base < 0 ? 4 : base;
    const int changed = atStart == 5 ? 6 : 5;
    const uint64_t vcTick = 480;
    if (base < 0)
        doc.addLanePoint(fx.voiceTrack(), DOC_CC_VOICE, 0, atStart);
    doc.addLanePoint(fx.voiceTrack(), DOC_CC_VOICE, vcTick, changed);
    QCoreApplication::processEvents();
    QCOMPARE(view.currentProgram(fx.voiceTrack()), atStart);
    view.setEditCursorTick(vcTick);
    QCOMPARE(view.currentProgram(fx.voiceTrack()), changed);
    view.setEditCursorTick(0);
    view.setPlayheadSample(view.timeline()->sampleForTick(vcTick), true);
    QCOMPARE(view.currentProgram(fx.voiceTrack()), changed);
    view.setPlayheadSample(0, false); // stopped: back to the edit cursor
    QCOMPARE(view.currentProgram(fx.voiceTrack()), atStart);

    // Header program presentation is a model-to-Quick contract: a transition
    // changes the subtitle role for just this record and the retained header
    // framebuffer.
    std::vector<DataChange> changes;
    const QMetaObject::Connection observed = QObject::connect(
        &headers, &QAbstractItemModel::dataChanged, &headers,
        [&changes](const QModelIndex &first, const QModelIndex &last, const QList<int> &roles) {
            changes.push_back({first.row(), last.row(), roles});
        });
    const QString beforeSubtitle =
        rowData(headers, *row, songview::TrackHeaderModel::SubtitleRole).toString();
    QString error;
    const QImage beforeProgram = fx.captureBand(error);
    QVERIFY2(!beforeProgram.isNull(), qPrintable(error));
    view.setEditCursorTick(vcTick);
    QCoreApplication::processEvents();
    const QString afterSubtitle =
        rowData(headers, *row, songview::TrackHeaderModel::SubtitleRole).toString();
    const QImage afterProgram = fx.captureBand(error);
    QVERIFY2(!afterProgram.isNull(), qPrintable(error));
    QVERIFY2(std::any_of(changes.cbegin(), changes.cend(),
                         [row = *row](const DataChange &change) {
                             return change.first == row && change.last == row &&
                                    change.roles.contains(songview::TrackHeaderModel::SubtitleRole);
                         }),
             "program change did not publish a bounded header subtitle role");
    QVERIFY2(beforeSubtitle != afterSubtitle, "program change did not alter the header subtitle");
    QVERIFY2(beforeProgram.size() == afterProgram.size() && beforeProgram != afterProgram,
             "program change did not alter the retained Quick header rendering");
    QObject::disconnect(observed);
    view.setEditCursorTick(0);
}
