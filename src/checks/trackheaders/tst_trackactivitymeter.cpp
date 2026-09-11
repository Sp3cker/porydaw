#include "checks/trackheaders/tst_trackactivitymeter.h"

#include <QtTest>

#include <QAbstractItemModel>
#include <QImage>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSize>

#include <algorithm>
#include <cmath>
#include <memory>
#include <optional>

#include "checks/support/quickframebuffer.h"
#include "checks/trackheaders/trackheaderoracles.h"
#include "core/miditimeline.h"
#include "ui/activity/trackactivityrender.h"
#include "ui/songview.h"
#include "ui/songview/editactions.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"

namespace {

constexpr int kTrack = 3;
constexpr int kSecondTrack = 7;
constexpr float kConvergedSeconds = 60.0F;

struct DataChange final {
    int count = 0;
    int first = -1;
    int last = -1;
    QList<int> roles;
};

QImage captureRow(SongView &view, const songview::TrackHeaderModel &model, int row, QString &error)
{
    const auto &band = view.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
    const int height = std::max(0, model.rowHeight() - model.separatorWidth());
    if (!band || band->rect.isEmpty() || row < 0 || model.activityWidth() <= 0 || height <= 0) {
        error = QStringLiteral("track-header activity geometry is unavailable");
        return {};
    }
    const int y = band->rect.y() + qRound(row * model.rowHeight() - model.scrollY());
    return checks::support::captureQuickBand(
        view, QRect{band->rect.x(), y, model.activityWidth(), height}, &error);
}

int channelHeight(uint8_t level, int meterHeight, qreal dpr)
{
    const track_activity_render::State state{levelToIntensity({level, level}), true};
    return track_activity_render::physicalHeight(state, state.intensity.left, meterHeight, dpr);
}

uint8_t levelWithinPixel(uint8_t base, int meterHeight, qreal dpr)
{
    for (int level = base; level < 255; ++level) {
        if (channelHeight(uint8_t(level), meterHeight, dpr) ==
            channelHeight(uint8_t(level + 1), meterHeight, dpr)) {
            return uint8_t(level);
        }
    }
    return 255;
}

uint8_t levelAcrossPixel(uint8_t base, int meterHeight, qreal dpr)
{
    const int rows = channelHeight(base, meterHeight, dpr);
    for (int level = base + 1; level <= 255; ++level) {
        if (channelHeight(uint8_t(level), meterHeight, dpr) > rows)
            return uint8_t(level);
    }
    return 255;
}

QList<int> activityRoles(const songview::TrackHeaderModel &model)
{
    const QHash<int, QByteArray> roles = model.roleNames();
    return {roles.key(QByteArrayLiteral("activityLeftHeight")),
            roles.key(QByteArrayLiteral("activityRightHeight"))};
}

} // namespace

void TrackActivityMeterTest::init()
{
    m_view = std::make_unique<SongView>();
    m_timeline = std::make_shared<MidiTimeline>();
    m_timeline->tracks[kTrack].used = true;
    m_timeline->usedTrackCount = 1;
    m_view->setSong(m_timeline.get(), nullptr);
    auto *const editActions = new songview::EditActions(m_view.get());
    editActions->rebind(m_view.get());
    QVERIFY(checks::support::showQuickViewport(*m_view, QSize(720, 520)));
    m_quick = m_view->quickView();
    m_window = m_quick ? m_quick->quickWindow() : nullptr;
    QVERIFY(m_quick && m_window);
    m_model = m_view->findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"));
    QVERIFY(m_model);
    QVERIFY(QTest::qWaitFor([this] {
        QQuickItem *const root = m_quick ? m_quick->rootObject() : nullptr;
        auto *const input = root ? root->findChild<songview::TimelineInputItem *>(
                                       QStringLiteral("timelineTrackHeadersInput"))
                                 : nullptr;
        const auto &band =
            m_view->timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
        return m_window && m_window->isVisible() && m_window->isExposed() && input && band &&
               !band->rect.isEmpty() && input->width() > 0.0 && input->height() > 0.0;
    }));
}

void TrackActivityMeterTest::cleanup()
{
    m_window.clear();
    m_model.clear();
    m_quick.clear();
    if (m_view)
        m_view->setSong(nullptr, nullptr);
    m_view.reset();
    m_timeline.reset();
}

void TrackActivityMeterTest::present(const TrackActivityLevels &levels, bool playing)
{
    m_view->advanceTrackActivity(levels, kConvergedSeconds, playing);
}

int TrackActivityMeterTest::rowForTrack(int track) const
{
    const std::optional<int> row = trackheaders_test::rowForTrack(*m_model, track);
    return row.value_or(-1);
}

void TrackActivityMeterTest::roleScopedUpdatesAndPhysicalPixelBoundaries()
{
    const int row = rowForTrack(kTrack);
    QCOMPARE(m_model->rowCount(), 1);
    QCOMPARE(row, 0);
    const int meterHeight = std::max(0, m_model->rowHeight() - m_model->separatorWidth());
    QVERIFY(meterHeight > 0 && m_model->activityWidth() > 0);

    QString error;
    const QImage warm = captureRow(*m_view, *m_model, row, error);
    QVERIFY2(!warm.isNull(), qPrintable(error));
    const qreal dpr = warm.devicePixelRatio();
    QVERIFY(dpr > 0.0);
    QVERIFY(std::abs(dpr - m_quick->quickDevicePixelRatio()) < 0.001);

    const QList<int> roles = activityRoles(*m_model);
    QVERIFY(roles[0] != 0 && roles[1] != 0);
    DataChange changes;
    const QMetaObject::Connection connection =
        QObject::connect(m_model, &QAbstractItemModel::dataChanged, m_view.get(),
                         [&changes](const QModelIndex &first, const QModelIndex &last,
                                    const QList<int> &changedRoles) {
                             ++changes.count;
                             changes.first = first.row();
                             changes.last = last.row();
                             changes.roles = changedRoles;
                         });

    TrackActivityLevels levels{};
    levels[kTrack] = {128, 128};
    present(levels, true);
    const QImage active = captureRow(*m_view, *m_model, row, error);
    QVERIFY2(!active.isNull(), qPrintable(error));
    QCOMPARE(changes.count, 1);
    QCOMPARE(changes.first, row);
    QCOMPARE(changes.last, row);
    QCOMPARE(changes.roles, roles);

    const uint8_t shared = levelWithinPixel(128, meterHeight, dpr);
    QVERIFY(shared != 255);
    levels[kTrack] = {shared, shared};
    changes = {};
    present(levels, true);
    const QImage within = captureRow(*m_view, *m_model, row, error);
    QVERIFY2(!within.isNull(), qPrintable(error));
    levels[kTrack] = {uint8_t(shared + 1), uint8_t(shared + 1)};
    changes = {};
    present(levels, true);
    const QImage samePixel = captureRow(*m_view, *m_model, row, error);
    QVERIFY2(!samePixel.isNull(), qPrintable(error));
    QCOMPARE(samePixel, within);
    QCOMPARE(changes.count, 0);

    const uint8_t across = levelAcrossPixel(uint8_t(shared + 1), meterHeight, dpr);
    QVERIFY(across != 255);
    levels[kTrack] = {across, across};
    changes = {};
    present(levels, true);
    const QImage changed = captureRow(*m_view, *m_model, row, error);
    QVERIFY2(!changed.isNull(), qPrintable(error));
    QVERIFY(changed != within);
    QCOMPARE(changes.count, 1);
    QCOMPARE(changes.first, row);
    QCOMPARE(changes.last, row);
    QCOMPARE(changes.roles, roles);
    QObject::disconnect(connection);
}

void TrackActivityMeterTest::pauseRasterAndIntensityCapUseObservedDpr()
{
    const int row = rowForTrack(kTrack);
    QVERIFY(row >= 0);
    const int meterHeight = std::max(0, m_model->rowHeight() - m_model->separatorWidth());
    QString error;
    TrackActivityLevels levels{};
    levels[kTrack] = {128, 128};
    present(levels, true);
    const QImage active = captureRow(*m_view, *m_model, row, error);
    QVERIFY2(!active.isNull(), qPrintable(error));
    const qreal dpr = active.devicePixelRatio();
    DataChange changes;
    const QMetaObject::Connection connection = QObject::connect(
        m_model, &QAbstractItemModel::dataChanged, m_view.get(),
        [&changes](const QModelIndex &first, const QModelIndex &last, const QList<int> &roles) {
            ++changes.count;
            changes.first = first.row();
            changes.last = last.row();
            changes.roles = roles;
        });
    present({}, false);
    const QImage paused = captureRow(*m_view, *m_model, row, error);
    QVERIFY2(!paused.isNull(), qPrintable(error));
    QCOMPARE(changes.count, 1);
    QCOMPARE(changes.first, row);
    QCOMPARE(changes.last, row);
    QCOMPARE(changes.roles, activityRoles(*m_model));
    const auto &band = m_view->timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
    QVERIFY(band);
    const int y = band->rect.y() + qRound(row * m_model->rowHeight() - m_model->scrollY());
    const QPoint origin{band->rect.x(), y};
    QCOMPARE(paused.width(),
             trackheaders_test::devicePixelSpan(origin.x(), m_model->activityWidth(), dpr));
    QCOMPARE(paused.height(), trackheaders_test::devicePixelSpan(origin.y(), meterHeight, dpr));
    QCOMPARE(paused.devicePixelRatio(), dpr);
    QVERIFY(trackheaders_test::isOpaque(paused));
    int completeColumns = 0;
    for (const int x : {paused.width() / 4, paused.width() / 2, paused.width() * 3 / 4}) {
        const QColor bottom = paused.pixelColor(x, paused.height() - 1);
        int filled = 0;
        for (int yPixel = paused.height() - 1;
             yPixel >= 0 && paused.pixelColor(x, yPixel) == bottom; --yPixel) {
            ++filled;
        }
        if (filled >= paused.height() - 1)
            ++completeColumns;
    }
    QVERIFY(completeColumns >= 2);
    QVERIFY(active.pixelColor(active.width() / 4, active.height() / 4) !=
            paused.pixelColor(paused.width() / 4, paused.height() / 4));
    const track_activity_render::State capped{{1.0F, 1.0F}, true, 0.15F};
    const int cappedRows =
        track_activity_render::physicalHeight(capped, capped.intensity.left, meterHeight, dpr);
    QCOMPARE(cappedRows, qRound(0.15 * meterHeight * dpr));
    const track_activity_render::State uncapped{{1.0F, 1.0F}, false, 0.15F};
    QVERIFY(track_activity_render::physicalHeight(uncapped, uncapped.intensity.left, meterHeight,
                                                  dpr) > cappedRows);
    QObject::disconnect(connection);
}

void TrackActivityMeterTest::stereoRasterAndRebuiltTracksRetainIdentity()
{
    const int row = rowForTrack(kTrack);
    QVERIFY(row >= 0);
    QString error;
    TrackActivityLevels stereo{};
    stereo[kTrack] = {255, 64};
    present(stereo, true);
    const QImage image = captureRow(*m_view, *m_model, row, error);
    QVERIFY2(!image.isNull(), qPrintable(error));
    const int left = image.width() / 4;
    const int right = image.width() * 3 / 4;
    QVERIFY(image.pixelColor(left, image.height() / 8) !=
            image.pixelColor(right, image.height() / 8));
    QCOMPARE(image.pixelColor(left, image.height() - 1),
             image.pixelColor(right, image.height() - 1));

    m_view->setSong(nullptr, nullptr);
    m_timeline = std::make_shared<MidiTimeline>();
    m_timeline->tracks[kTrack].used = true;
    m_timeline->tracks[kSecondTrack].used = true;
    m_timeline->usedTrackCount = 2;
    m_view->setSong(m_timeline.get(), nullptr);
    checks::support::pumpQuick();
    const int first = rowForTrack(kTrack);
    const int second = rowForTrack(kSecondTrack);
    QCOMPARE(m_model->rowCount(), 2);
    QVERIFY(first >= 0 && second >= 0);
    DataChange changes;
    const QMetaObject::Connection connection = QObject::connect(
        m_model, &QAbstractItemModel::dataChanged, m_view.get(),
        [&changes](const QModelIndex &top, const QModelIndex &bottom, const QList<int> &roles) {
            ++changes.count;
            changes.first = top.row();
            changes.last = bottom.row();
            changes.roles = roles;
        });
    TrackActivityLevels levels{};
    levels[kTrack] = {255, 255};
    levels[kSecondTrack] = {96, 96};
    present(levels, true);
    const QImage firstImage = captureRow(*m_view, *m_model, first, error);
    QVERIFY2(!firstImage.isNull(), qPrintable(error));
    const QImage secondImage = captureRow(*m_view, *m_model, second, error);
    QVERIFY2(!secondImage.isNull(), qPrintable(error));
    QVERIFY(trackheaders_test::isOpaque(firstImage));
    QVERIFY(trackheaders_test::isOpaque(secondImage));
    QVERIFY(firstImage.pixelColor(firstImage.width() / 4, firstImage.height() - 1) !=
            secondImage.pixelColor(secondImage.width() / 4, secondImage.height() - 1));
    QCOMPARE(changes.count, 1);
    QCOMPARE(changes.first, std::min(first, second));
    QCOMPARE(changes.last, std::max(first, second));
    QCOMPARE(changes.roles, activityRoles(*m_model));
    changes = {};
    present(levels, true);
    checks::support::pumpQuick();
    QCOMPARE(changes.count, 0);
    QObject::disconnect(connection);
}

int runTrackActivityMeterCheck(const QStringList &qtArguments)
{
    TrackActivityMeterTest test;
    QStringList arguments{QStringLiteral("trackactivitymeter")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
