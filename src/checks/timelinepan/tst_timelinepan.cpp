#include "checks/timelinepan/timelinepanfixture.h"

#include <QAbstractItemModel>
#include <QByteArray>
#include <QList>
#include <QPersistentModelIndex>
#include <QPoint>
#include <QRectF>
#include <QSignalSpy>
#include <QStringList>
#include <QtTest>

#include "checks/support/quickframebuffer.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <tuple>
#include <vector>

namespace {

constexpr qreal kCameraTolerance = 0.01;
constexpr QPoint kLegacyPanPixelDelta{-8, 0};

bool closeEnough(qreal actual, qreal expected)
{
    return std::abs(actual - expected) <= kCameraTolerance;
}

std::vector<QRectF> orderedRects(const songview::TimelineQuickScene &scene,
                                 songview::TimelineQuickLayer layer)
{
    std::vector<QRectF> result;
    for (const auto &primitive : scene.layer(layer).rects)
        result.push_back(primitive.rect);
    std::sort(result.begin(), result.end(), [](const QRectF &a, const QRectF &b) {
        return std::tuple(a.x(), a.y(), a.width(), a.height()) <
               std::tuple(b.x(), b.y(), b.width(), b.height());
    });
    return result;
}

std::vector<QRectF> labelRects(const QAbstractItemModel &model)
{
    std::vector<QRectF> result;
    result.reserve(static_cast<std::size_t>(model.rowCount()));
    for (int row = 0; row < model.rowCount(); ++row)
        result.push_back(
            model.data(model.index(row, 0), songview::TimelineQuickTextModel::RectRole).toRectF());
    return result;
}

class TextModelSpies final
{
  public:
    explicit TextModelSpies(QAbstractItemModel &model)
        : m_rowsRemoved(&model, &QAbstractItemModel::rowsRemoved)
        , m_rowsInserted(&model, &QAbstractItemModel::rowsInserted)
        , m_rowsMoved(&model, &QAbstractItemModel::rowsMoved)
        , m_modelReset(&model, &QAbstractItemModel::modelReset)
        , m_layoutChanged(
              &model,
              static_cast<void (QAbstractItemModel::*)(const QList<QPersistentModelIndex> &,
                                                       QAbstractItemModel::LayoutChangeHint)>(
                  &QAbstractItemModel::layoutChanged))
        , m_dataChanged(&model, &QAbstractItemModel::dataChanged)
    {}

    bool isValid() const
    {
        return m_rowsRemoved.isValid() && m_rowsInserted.isValid() && m_rowsMoved.isValid() &&
               m_modelReset.isValid() && m_layoutChanged.isValid() && m_dataChanged.isValid();
    }

    int structuralChangeCount() const
    {
        return m_rowsRemoved.count() + m_rowsInserted.count() + m_rowsMoved.count() +
               m_modelReset.count() + m_layoutChanged.count();
    }

    int signalCount() const { return structuralChangeCount() + m_dataChanged.count(); }

  private:
    QSignalSpy m_rowsRemoved;
    QSignalSpy m_rowsInserted;
    QSignalSpy m_rowsMoved;
    QSignalSpy m_modelReset;
    QSignalSpy m_layoutChanged;
    QSignalSpy m_dataChanged;
};

class TimelinePanTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(TimelinePanTest)

  public:
    TimelinePanTest(const QString &projectRoot, const QString &songLabel)
        : m_fixture(projectRoot, songLabel)
    {}

    ~TimelinePanTest() override = default;

  private slots:
    void init();
    void cleanup();

    void dashPhasePreservesClip_data();
    void dashPhasePreservesClip();

    void wheelPansCamera_data();
    void wheelPansCamera();
    void gutterLabelsSurvivePan();

  private:
    qreal panOnce(const QPoint &pixelDelta);

    checks::timelinepan::TimelinePanFixture m_fixture;
};

void TimelinePanTest::init()
{
    if (QByteArray(QTest::currentTestFunction()) == QByteArrayLiteral("dashPhasePreservesClip"))
        return;

    QString error;
    QVERIFY2(m_fixture.load(error), qPrintable(error));
    m_fixture.show();
    QTRY_VERIFY(m_fixture.isReady(false));
}

void TimelinePanTest::cleanup()
{
    m_fixture.cleanup();
}

void TimelinePanTest::dashPhasePreservesClip_data()
{
    QTest::addColumn<qreal>("start");
    QTest::addColumn<qreal>("across");

    for (const qreal start : {-1000.25, -7.5, 0.0, 17.25}) {
        for (const qreal across : {-1.0, 0.25, 30.0, 59.75, 100.25}) {
            const QByteArray row = QByteArray("start-") + QByteArray::number(start) + "-across-" +
                                   QByteArray::number(across);
            QTest::newRow(row.constData()) << start << across;
        }
    }
}

void TimelinePanTest::dashPhasePreservesClip()
{
    QFETCH(qreal, start);
    QFETCH(qreal, across);

    using namespace songview;
    using namespace songview::timeline_quick;
    constexpr auto layer = TimelineQuickLayer::AutomationSelection;
    const QRectF clip(0.0, 0.0, 100.0, 60.0);
    TimelineQuickScene reference;
    TimelineQuickScene bounded;

    for (qreal at = start; at < 200.0; at += 5.75) {
        addHorizontalLine(reference.layer(layer), at, std::min(at + 4.5, 200.0), across, 1.0,
                          Qt::red, clip);
        addVerticalLine(reference.layer(layer), across, at, std::min(at + 4.5, 200.0), 1.0, Qt::red,
                        clip);
    }
    addDashedHorizontal(bounded.layer(layer), start, 200.0, across, 1.0, 4.5, 1.25, Qt::red, clip);
    addDashedVertical(bounded.layer(layer), across, start, 200.0, 1.0, 4.5, 1.25, Qt::red, clip);

    // Exact same-binary geometry is intentional for this deterministic clipping oracle.
    QVERIFY(orderedRects(reference, layer) == orderedRects(bounded, layer));
}

void TimelinePanTest::wheelPansCamera_data()
{
    QTest::addColumn<QPoint>("pixelDelta");
    QTest::addColumn<qreal>("expectedDelta");

    QTest::newRow("legacy-pixel-left-8") << kLegacyPanPixelDelta << 8.0;
    // Direct synthetic delivery must not create camera or model work for an empty wheel event.
    QTest::newRow("safe-zero-delta") << QPoint{} << 0.0;
}

qreal TimelinePanTest::panOnce(const QPoint &pixelDelta)
{
    const qreal delta = m_fixture.pan(pixelDelta);
    checks::support::pumpQuick();
    return delta;
}

void TimelinePanTest::wheelPansCamera()
{
    QFETCH(QPoint, pixelDelta);
    QFETCH(qreal, expectedDelta);

    SongView &songView = m_fixture.view();
    const qreal before = songView.camera().scrollX();
    QAbstractItemModel *const automationModel = m_fixture.scene()->automationTextModel();
    QAbstractItemModel *const voiceChangesModel = m_fixture.scene()->voiceChangesGutterTextModel();
    TextModelSpies automation(*automationModel);
    TextModelSpies voiceChanges(*voiceChangesModel);
    QVERIFY(automation.isValid());
    QVERIFY(voiceChanges.isValid());

    QVERIFY(closeEnough(panOnce(pixelDelta), expectedDelta));
    QTRY_VERIFY(closeEnough(songView.quickView()->horizontalScrollValue(), before + expectedDelta));

    if (expectedDelta == 0.0) {
        QCOMPARE(automation.signalCount(), 0);
        QCOMPARE(voiceChanges.signalCount(), 0);
    }
}

void TimelinePanTest::gutterLabelsSurvivePan()
{
    QAbstractItemModel *const automationModel = m_fixture.scene()->automationTextModel();
    QAbstractItemModel *const voiceChangesModel = m_fixture.scene()->voiceChangesGutterTextModel();
    const std::vector<QRectF> automationBefore = labelRects(*automationModel);
    const std::vector<QRectF> voiceChangesBefore = labelRects(*voiceChangesModel);
    TextModelSpies automation(*automationModel);
    TextModelSpies voiceChanges(*voiceChangesModel);
    QVERIFY(automation.isValid());
    QVERIFY(voiceChanges.isValid());

    for (int count = 0; count < 8; ++count)
        QVERIFY(closeEnough(panOnce(kLegacyPanPixelDelta), 8.0));

    QCOMPARE(automation.structuralChangeCount(), 0);
    QCOMPARE(voiceChanges.structuralChangeCount(), 0);
    QVERIFY(labelRects(*automationModel) == automationBefore);
    QVERIFY(labelRects(*voiceChangesModel) == voiceChangesBefore);
}

} // namespace

int runTimelinePanCheck(const QString &projectRoot, const QString &songLabel,
                        const QStringList &qtArguments)
{
    TimelinePanTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("timelinepan")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_timelinepan.moc"
