#include "checks/timelinepan/timelinepanfixture.h"

#include <QAbstractItemModel>
#include <QByteArray>
#include <QImage>
#include <QList>
#include <QPersistentModelIndex>
#include <QPoint>
#include <QRectF>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSignalSpy>
#include <QStringList>
#include <QtTest>

#include "checks/support/quickframebuffer.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <memory>
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
    void geometryCountsSurviveReuse();
    void fullRefreshWinsOverPan_data();
    void fullRefreshWinsOverPan();

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

void TimelinePanTest::geometryCountsSurviveReuse()
{
    struct Result {
        std::atomic<bool> started{false};
        std::atomic<bool> done{false};
        std::vector<bool> stages;
    };
    auto result = std::make_shared<Result>();
    QQuickWindow *window = m_fixture.view().quickView()->quickWindow();
    QVERIFY(window);
    // Create, inspect and destroy all scene graph objects on the render thread.
    const auto connection = connect(
        window, &QQuickWindow::beforeSynchronizing, window,
        [result] {
            if (result->started.exchange(true))
                return;
            using namespace songview;
            using Vertex = std::tuple<float, float, int, int, int, int>;
            TimelineQuickLayerData data;
            std::unique_ptr<QSGNode> node;
            std::vector<Vertex> expected;
            const auto inspect = [&] {
                std::vector<Vertex> actual;
                for (auto *child = node->firstChild(); child; child = child->nextSibling()) {
                    if (child->isSubtreeBlocked())
                        continue;
                    const auto *geometry = static_cast<QSGGeometryNode *>(child)->geometry();
                    if (geometry->drawingMode() != QSGGeometry::DrawTriangles)
                        return false;
                    const auto *vertices = geometry->vertexDataAsColoredPoint2D();
                    for (int index = 0; index < geometry->vertexCount(); ++index) {
                        const auto &v = vertices[index];
                        actual.emplace_back(v.x, v.y, v.r, v.g, v.b, v.a);
                    }
                }
                return actual == expected;
            };
            const auto sync = [&](const TimelineQuickLayerData *source) {
                node.reset(timeline_quick::syncLayerNode(node.release(), source));
                result->stages.push_back(inspect());
            };
            const auto populate = [&](int rectCount, int triangleCount, int offset) {
                timeline_quick::resetLayer(data);
                expected.clear();
                const QColor translucent(200, 100, 50, 128);
                for (int index = 0; index < rectCount; ++index) {
                    const float x = float(index + offset);
                    data.rects.push_back(
                        {QRectF(x, 2, 3, 4), Qt::red, Qt::green, Qt::blue, translucent});
                    expected.emplace_back(x, 2, 255, 0, 0, 255);
                    expected.emplace_back(x, 6, 100, 50, 25, 128);
                    expected.emplace_back(x + 3, 2, 0, 255, 0, 255);
                    expected.emplace_back(x + 3, 2, 0, 255, 0, 255);
                    expected.emplace_back(x, 6, 100, 50, 25, 128);
                    expected.emplace_back(x + 3, 6, 0, 0, 255, 255);
                }
                for (int index = 0; index < triangleCount; ++index) {
                    const float x = float(index + offset);
                    data.triangles.push_back(
                        {{x, 8}, {x + 1, 10}, {x + 2, 8}, Qt::blue, translucent, Qt::red});
                    expected.emplace_back(x, 8, 0, 0, 255, 255);
                    expected.emplace_back(x + 1, 10, 100, 50, 25, 128);
                    expected.emplace_back(x + 2, 8, 255, 0, 0, 255);
                }
            };
            // Mixed primitives straddle a chunk boundary; assertions concern only
            // the ordered colored vertices Qt will draw, not the pooling policy.
            populate(255, 5, 0);
            sync(&data);
            sync(&data); // Unchanged revision.
            populate(1, 1, 10);
            sync(&data);
            populate(0, 0, 0);
            sync(&data);
            populate(520, 7, 20);
            sync(&data);
            std::vector<Vertex> saved;
            expected.swap(saved);
            sync(nullptr);
            expected.swap(saved);
            sync(&data); // Reattach the same data and revision after no data.
            populate(255, 5, 30);
            sync(&data);
            node.reset();
            result->done.store(true, std::memory_order_release);
        },
        Qt::DirectConnection);
    window->update();
    checks::support::pumpQuick();
    QTRY_VERIFY(result->done.load(std::memory_order_acquire));
    disconnect(connection);
    QCOMPARE(result->stages.size(), std::size_t(8));
    for (std::size_t stage = 0; stage < result->stages.size(); ++stage)
        QVERIFY2(result->stages[stage], qPrintable(QStringLiteral("Geometry stage %1").arg(stage)));
}

void TimelinePanTest::fullRefreshWinsOverPan_data()
{
    QTest::addColumn<bool>("panFirst");
    QTest::newRow("full-then-pan") << false;
    QTest::newRow("pan-then-full") << true;
}

void TimelinePanTest::fullRefreshWinsOverPan()
{
    QFETCH(bool, panFirst);
    using namespace songview;
    SongView &view = m_fixture.view();
    TimelineQuickView *const quick = view.quickView();
    const TimelineQuickScene &scene = *m_fixture.scene();
    checks::support::pumpQuick();
    const auto automationBefore = orderedRects(scene, TimelineQuickLayer::AutomationGutterChrome);
    const auto voiceBefore = orderedRects(scene, TimelineQuickLayer::VoiceChangesGutterChrome);
    const auto &layout = view.timelineBandLayout();
    QVERIFY(layout.geometry(TimelineBand::Automation));
    QVERIFY(layout.geometry(TimelineBand::VoiceChanges));
    const int automationHeight = layout.geometry(TimelineBand::Automation)->rect.height() + 24;
    const int voiceHeight = layout.geometry(TimelineBand::VoiceChanges)->rect.height() + 24;
    const qreal scrollBefore = view.camera().scrollX();
    const auto resizeDrawers = [&] {
        view.setDrawerSectionHeight(EditorDrawerPage::Automations, automationHeight);
        view.setDrawerSectionHeight(EditorDrawerPage::VoiceChanges, voiceHeight);
    };
    const auto pan = [&] { quick->setHorizontalScroll(scrollBefore + 8.0); };

    // These public setters enqueue their refreshes synchronously. Do not pump
    // events (including through the wheel helper) between the two requests:
    // both must reach the same deferred Quick flush.
    if (panFirst) {
        pan();
        resizeDrawers();
    } else {
        resizeDrawers();
        pan();
    }
    QVERIFY(closeEnough(view.camera().scrollX() - scrollBefore, 8.0));
    checks::support::pumpQuick();
    const auto automationCoalesced =
        orderedRects(scene, TimelineQuickLayer::AutomationGutterChrome);
    const auto voiceCoalesced = orderedRects(scene, TimelineQuickLayer::VoiceChangesGutterChrome);
    const QImage coalesced = m_fixture.render();
    QVERIFY(!coalesced.isNull());

    // Same final camera/layout, now without a pan bit: this is the rendering
    // oracle, including gutter colors and QML text, not dirty/revision metadata.
    quick->requestTimelineUpdate(TimelineQuickDirty::All);
    quick->requestAutomationUpdate(AutomationRefresh::All);
    checks::support::pumpQuick();
    const QImage full = m_fixture.render();
    QVERIFY(!full.isNull());
    const auto automationFull = orderedRects(scene, TimelineQuickLayer::AutomationGutterChrome);
    const auto voiceFull = orderedRects(scene, TimelineQuickLayer::VoiceChangesGutterChrome);
    QVERIFY(automationFull != automationBefore);
    QVERIFY(voiceFull != voiceBefore);
    QVERIFY(automationCoalesced == automationFull);
    QVERIFY(voiceCoalesced == voiceFull);
    QCOMPARE(coalesced, full);
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
    QAbstractItemModel *const voiceChangesModel = m_fixture.scene()->voiceChangesGutterTextModel();
    TextModelSpies voiceChanges(*voiceChangesModel);
    QVERIFY(voiceChanges.isValid());

    QVERIFY(closeEnough(panOnce(pixelDelta), expectedDelta));
    QTRY_VERIFY(closeEnough(songView.quickView()->horizontalScrollValue(), before + expectedDelta));

    if (expectedDelta == 0.0) {
        QCOMPARE(voiceChanges.signalCount(), 0);
    }
}

void TimelinePanTest::gutterLabelsSurvivePan()
{
    QAbstractItemModel *const voiceChangesModel = m_fixture.scene()->voiceChangesGutterTextModel();
    const std::vector<QRectF> voiceChangesBefore = labelRects(*voiceChangesModel);
    TextModelSpies voiceChanges(*voiceChangesModel);
    QVERIFY(voiceChanges.isValid());

    for (int count = 0; count < 8; ++count)
        QVERIFY(closeEnough(panOnce(kLegacyPanPixelDelta), 8.0));

    QCOMPARE(voiceChanges.structuralChangeCount(), 0);
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
