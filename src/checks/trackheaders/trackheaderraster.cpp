#include "checks/trackheaders/tst_trackheaders.h"

#include <QtTest>

#include <QAbstractItemModel>

#include <cstring>
#include <optional>
#include <vector>

#include "checks/support/quickframebuffer.h"
#include "ui/activity/trackactivity.h"
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
