#include "checks/timelinepan/timelinepanfixture.h"

#include <QAbstractItemModel>
#include <QByteArray>
#include <QColor>
#include <QEvent>
#include <QFontMetrics>
#include <QImage>
#include <QList>
#include <QModelIndex>
#include <QPersistentModelIndex>
#include <QPoint>
#include <QQuickItem>
#include <QRectF>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QScopeGuard>
#include <QSignalSpy>
#include <QStringList>
#include <QtTest>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "core/miditimeline.h"
#include "ui/layout.h"
#include "ui/pitchprojection.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <memory>
#include <optional>
#include <tuple>
#include <utility>
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

constexpr char kDrumPadName[] = "Kick";
constexpr char kDrumPadLongName[] = "Fixture Drum Pad With A Long Name";

// The bank borrows only this fixture's storage; moving it would invalidate
// those pointers. Each scenario owns its own independent tables.
class DrumBankFixture final
{
    Q_DISABLE_COPY_MOVE(DrumBankFixture)

  public:
    DrumBankFixture(int program, int namedKey, int unnamedKey, int longKey)
    {
        m_tones[unnamedKey].type = VOICE_NOISE;
        std::strncpy(m_names[namedKey], kDrumPadName, VG_VOICE_NAME_LEN - 1);
        std::strncpy(m_names[longKey], kDrumPadLongName, VG_VOICE_NAME_LEN - 1);
        bank.voices[program].type = VOICE_KEYSPLIT_ALL;
        bank.voices[program].subGroup = m_tones;
        bank.subGroups = m_subGroups;
        bank.subGroupVoiceNames = m_subGroupNames;
        bank.subGroupCount = 1;
        bank.subGroupCapacity = 1;
    }

    LoadedVoiceGroup bank{};

  private:
    ToneData m_tones[VOICEGROUP_SIZE]{};
    char m_names[VOICEGROUP_SIZE][VG_VOICE_NAME_LEN]{};
    ToneData *m_subGroups[1]{m_tones};
    char (*m_subGroupNames[1])[VG_VOICE_NAME_LEN]{m_names};
};

QRectF padRowRect(const SongView &view, int key)
{
    const auto &projection = view.pitchProjection();
    return projection.rowRect(projection.rowForPitch(key), 0, view.pianoKeyboardWidth(),
                              view.camera().keyHeight(), view.camera().scrollY(),
                              view.quickView()->quickDevicePixelRatio());
}

// Choose input targets through the public projection, not a second camera.
// Keep an accidental as the named pad so its light text is always exercised.
std::optional<std::array<int, 3>> drumPadKeys(const SongView &view, qreal plotHeight)
{
    int accidental = -1;
    std::vector<int> naturals;
    const auto &projection = view.pitchProjection();
    for (int row = 0; row < projection.visibleRowCount(); ++row) {
        const int key = projection.visiblePitchAt(row);
        const QRectF rect = padRowRect(view, key);
        if (rect.top() < 0 || rect.bottom() > plotHeight)
            continue;
        if (songview::detail::isBlackKey(key))
            accidental = key;
        else
            naturals.push_back(key);
    }
    if (accidental < 0 || naturals.size() < 2)
        return std::nullopt;
    return std::array<int, 3>{accidental, naturals.front(), naturals.back()};
}

QModelIndex keyboardRecordAt(const QAbstractItemModel &model, qreal rowY)
{
    for (int row = 0; row < model.rowCount(); ++row) {
        const QModelIndex index = model.index(row, 0);
        const QRectF rect = model.data(index, songview::TimelineQuickTextModel::RectRole).toRectF();
        if (rowY >= rect.top() && rowY < rect.bottom())
            return index;
    }
    return {};
}

void hoverPadRow(const SongView &view, songview::TimelineInputItem &gutter, int key)
{
    checks::events::sendMouse(gutter, QEvent::MouseMove,
                              QPointF(4.0, padRowRect(view, key).center().y()), Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
    checks::support::pumpQuick();
}

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
    void drumGutterLabelsAndHover();
    void drumGutterTrackSwitch();
    void drumClassificationIgnoresProgramChanges();
    void hoverChipOverlayUnclipped();

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

void TimelinePanTest::drumGutterLabelsAndHover()
{
    using namespace songview;
    SongView &view = m_fixture.view();
    TimelineQuickScene *const scene = m_fixture.scene();
    QAbstractItemModel *const model = scene->pianoKeyboardTextModel();
    QVERIFY(model);

    const MidiTimeline *const timeline = view.timeline();
    QVERIFY(timeline);
    const int primaryTrack = view.selectionModel().primaryTrack();
    const int firstProgram = timeline->tracks[primaryTrack].firstProgram;
    const int program = firstProgram < 0 ? 0 : firstProgram;
    QVERIFY(program < VOICEGROUP_SIZE);

    QQuickItem *const root = view.quickView()->rootObject();
    QVERIFY(root);
    auto *const rollInput =
        root->findChild<TimelineInputItem *>(QStringLiteral("timelineRollInput"));
    auto *const gutterInput =
        root->findChild<TimelineInputItem *>(QStringLiteral("timelineRollGutterInput"));
    QVERIFY(rollInput);
    QVERIFY(gutterInput);

    const std::optional<std::array<int, 3>> padKeys = drumPadKeys(view, rollInput->height());
    QVERIFY2(padKeys.has_value(), "Fixture must expose an accidental and two natural pad rows");
    const int namedKey = (*padKeys)[0];
    const int unnamedKey = (*padKeys)[1];
    const int longKey = (*padKeys)[2];

    DrumBankFixture fixture(program, namedKey, unnamedKey, longKey);
    const LoadedVoiceGroup *const originalBank = view.voicegroup();
    const auto restoreBank =
        qScopeGuard([&view, originalBank] { view.setVoicegroup(originalBank); });
    view.setVoicegroup(&fixture.bank);
    checks::support::pumpQuick();

    const QModelIndex namedIndex =
        keyboardRecordAt(*model, padRowRect(view, namedKey).center().y());
    const QModelIndex unnamedIndex =
        keyboardRecordAt(*model, padRowRect(view, unnamedKey).center().y());
    const QModelIndex longIndex = keyboardRecordAt(*model, padRowRect(view, longKey).center().y());
    QVERIFY(namedIndex.isValid());
    QVERIFY(unnamedIndex.isValid());
    QVERIFY(longIndex.isValid());
    QCOMPARE(model->data(namedIndex, TimelineQuickTextModel::TextRole).toString(),
             QStringLiteral("Kick"));
    QVERIFY(detail::isBlackKey(namedKey));
    QCOMPARE(model->data(namedIndex, TimelineQuickTextModel::ColorRole).value<QColor>(),
             themes::color(themes::Role::song_view_piano_keyboard_natural_key));
    const QString longText = model->data(longIndex, TimelineQuickTextModel::TextRole).toString();
    const QRectF longRect = model->data(longIndex, TimelineQuickTextModel::RectRole).toRectF();
    QVERIFY(longText.contains(QChar(0x2026)));
    QVERIFY(longText != QString::fromUtf8(kDrumPadLongName));
    const auto geometry = pianoroll_detail::PianoRollGeometry::resolve(view.pianoKeyboardWidth());
    QCOMPARE(longRect.width(),
             qreal(view.pianoKeyboardWidth() - geometry.pianoKeyboardLabelRightInset));
    QCOMPARE(longRect.left(), 0.0);
    QCOMPARE(longRect.top(), padRowRect(view, longKey).top());
    QCOMPARE(longRect.height(), padRowRect(view, longKey).height());
    const QFontMetrics labelMetrics(
        model->data(longIndex, TimelineQuickTextModel::FontRole).value<QFont>());
    QVERIFY(labelMetrics.horizontalAdvance(longText) <= longRect.width());
    QVERIFY(longText.startsWith(QStringLiteral("Fixture")));
    QVERIFY(longText.endsWith(QChar(0x2026)));
    QCOMPARE(model->data(unnamedIndex, TimelineQuickTextModel::TextRole).toString(),
             detail::keyName(unnamedKey));

    // Gutter hover publishes the full, un-elided label on the scene-level
    // hover chip at measured width, on-screen and wide enough for the text
    // plus the geometry's horizontal padding.
    const int chipPadding = pianoroll_detail::PianoRollGeometry::resolve(view.pianoKeyboardWidth())
                                .keyboardHoverChipHorizontalPadding;
    hoverPadRow(view, *gutterInput, longKey);
    QVERIFY(scene->hoverChipVisible());
    QCOMPARE(scene->hoverChipText(), QString::fromUtf8(kDrumPadLongName));
    const QRectF longChip = scene->hoverChipRect();
    QVERIFY(longChip.left() >= layout::space(layout::Space::Zero));
    QVERIFY(longChip.width() >= qreal(QFontMetrics(scene->hoverChipFont())
                                          .horizontalAdvance(QString::fromUtf8(kDrumPadLongName)) +
                                      chipPadding));
    hoverPadRow(view, *gutterInput, unnamedKey);
    QVERIFY(scene->hoverChipVisible());
    QCOMPARE(scene->hoverChipText(), detail::keyName(unnamedKey));
    const QRectF unnamedChip = scene->hoverChipRect();
    QVERIFY(unnamedChip.left() >= layout::space(layout::Space::Zero));
    QVERIFY(
        unnamedChip.width() >=
        qreal(QFontMetrics(scene->hoverChipFont()).horizontalAdvance(detail::keyName(unnamedKey)) +
              chipPadding));
}

void TimelinePanTest::drumGutterTrackSwitch()
{
    using namespace songview;
    SongView &view = m_fixture.view();
    QAbstractItemModel *const model = m_fixture.scene()->pianoKeyboardTextModel();
    QVERIFY(model);

    const MidiTimeline *const timeline = view.timeline();
    QVERIFY(timeline);
    const int primaryTrack = view.selectionModel().primaryTrack();
    const int firstProgram = timeline->tracks[primaryTrack].firstProgram;
    const int program = firstProgram < 0 ? 0 : firstProgram;
    QVERIFY(program < VOICEGROUP_SIZE);

    // The switch must change classification: a second used track whose
    // initial program is not the drum program.
    int otherTrack = -1;
    bool secondUsed = false;
    for (int track = 0; track < 16; ++track) {
        if (track == primaryTrack || !timeline->tracks[track].used)
            continue;
        secondUsed = true;
        const int otherProgram =
            timeline->tracks[track].firstProgram < 0 ? 0 : timeline->tracks[track].firstProgram;
        if (otherProgram != program) {
            otherTrack = track;
            break;
        }
    }
    QVERIFY2(secondUsed, "Fixture must contain a second used track");
    QVERIFY2(otherTrack >= 0, "Fixture must contain a track with a different initial program");

    QQuickItem *const root = view.quickView()->rootObject();
    QVERIFY(root);
    auto *const rollInput =
        root->findChild<TimelineInputItem *>(QStringLiteral("timelineRollInput"));
    QVERIFY(rollInput);

    const auto padKeys = drumPadKeys(view, rollInput->height());
    QVERIFY(padKeys.has_value());
    const int namedKey = (*padKeys)[0];
    DrumBankFixture fixture(program, namedKey, (*padKeys)[1], (*padKeys)[2]);
    const LoadedVoiceGroup *const originalBank = view.voicegroup();
    const auto restoreBank =
        qScopeGuard([&view, originalBank] { view.setVoicegroup(originalBank); });
    view.setVoicegroup(&fixture.bank);
    checks::support::pumpQuick();

    const qreal namedY = padRowRect(view, namedKey).center().y();
    const auto padText = [&] {
        return model->data(keyboardRecordAt(*model, namedY), TimelineQuickTextModel::TextRole)
            .toString();
    };
    QCOMPARE(padText(), QStringLiteral("Kick"));
    const int drumRowCount = model->rowCount();

    view.selectTrack(otherTrack);
    checks::support::pumpQuick();
    QCOMPARE(view.selectionModel().primaryTrack(), otherTrack);
    QVERIFY(model->rowCount() > 0);
    QVERIFY(model->rowCount() < drumRowCount);
    QVERIFY(!keyboardRecordAt(*model, namedY).isValid());
    for (int row = 0; row < model->rowCount(); ++row) {
        const QString text =
            model->data(model->index(row, 0), TimelineQuickTextModel::TextRole).toString();
        QVERIFY2(text.startsWith(QLatin1Char('C')) && !text.contains(QLatin1Char('#')),
                 qPrintable(text));
    }

    view.selectTrack(primaryTrack);
    checks::support::pumpQuick();
    QCOMPARE(view.selectionModel().primaryTrack(), primaryTrack);
    QCOMPARE(model->rowCount(), drumRowCount);
    QCOMPARE(padText(), QStringLiteral("Kick"));
}

void TimelinePanTest::drumClassificationIgnoresProgramChanges()
{
    using namespace songview;
    SongView &view = m_fixture.view();
    const MidiTimeline *const originalTimeline = view.timeline();
    QVERIFY(originalTimeline);
    const int track = view.selectionModel().primaryTrack();
    const int initial = std::max(0, originalTimeline->tracks[track].firstProgram);
    QVERIFY(initial < VOICEGROUP_SIZE);
    MidiTimeline timeline = *originalTimeline;
    timeline.tracks[track].firstProgram = initial;
    const auto laterChange = std::find_if(timeline.events.begin(), timeline.events.end(),
                                          [=](const TimelineEvent &event) {
                                              return event.track == track && event.type == 0xC &&
                                                     event.tick > 0 && event.data0 != initial;
                                          });
    Tick changeTick;
    int melodic;
    if (laterChange != timeline.events.end()) {
        changeTick = laterChange->tick;
        melodic = laterChange->data0;
    } else {
        // Some input songs never change voices. Supply two real timeline
        // events through the public document-swap surface in that case.
        changeTick = Tick(timeline.ticksPerBeat);
        melodic = (initial + 1) % VOICEGROUP_SIZE;
        std::erase_if(timeline.events, [=](const TimelineEvent &event) {
            return event.track == track && event.type == 0xC;
        });
        timeline.events.push_back({0, 0, 0xC, uint8_t(track), uint8_t(initial), 0, {}});
        timeline.events.push_back({timeline.sampleForTick(changeTick),
                                   changeTick,
                                   0xC,
                                   uint8_t(track),
                                   uint8_t(melodic),
                                   0,
                                   {}});
        std::stable_sort(timeline.events.begin(), timeline.events.end(),
                         [](const TimelineEvent &a, const TimelineEvent &b) {
                             return a.samplePos < b.samplePos;
                         });
        timeline.lengthTicks = std::max(timeline.lengthTicks, changeTick + 1);
        timeline.lengthSamples =
            std::max(timeline.lengthSamples, timeline.sampleForTick(timeline.lengthTicks));
    }
    QVERIFY(changeTick > 0);
    QVERIFY(melodic != initial);
    QQuickItem *const root = view.quickView()->rootObject();
    QVERIFY(root);
    auto *const rollInput =
        root->findChild<TimelineInputItem *>(QStringLiteral("timelineRollInput"));
    QVERIFY(rollInput);
    const auto keys = drumPadKeys(view, rollInput->height());
    QVERIFY(keys.has_value());
    DrumBankFixture fixture(initial, (*keys)[0], (*keys)[1], (*keys)[2]);
    QVERIFY(!(fixture.bank.voices[melodic].type & VOICE_KEYSPLIT_ALL));
    const LoadedVoiceGroup *const originalBank = view.voicegroup();
    const auto restore = qScopeGuard([&] {
        view.setPlayheadSample(0, false);
        view.updateSong(originalTimeline);
        view.setVoicegroup(originalBank);
    });
    view.setFollowPlayhead(false);
    view.updateSong(&timeline);
    view.setVoicegroup(&fixture.bank);
    QAbstractItemModel *const model = m_fixture.scene()->pianoKeyboardTextModel();
    QVERIFY(model);
    const auto padText = [&] {
        // Force a real keyboard synchronization at each position; otherwise
        // stale text could mask a resolver incorrectly using currentProgram.
        view.quickView()->requestUpdate(PianoRollQuickDirty::KeyboardText);
        checks::support::pumpQuick();
        return model
            ->data(keyboardRecordAt(*model, padRowRect(view, (*keys)[0]).center().y()),
                   TimelineQuickTextModel::TextRole)
            .toString();
    };
    view.setPlayheadSample(0, false);
    view.setEditCursorTick(0);
    QCOMPARE(view.currentProgram(track), initial);
    QCOMPARE(padText(), QStringLiteral("Kick"));
    view.setEditCursorTick(changeTick);
    QCOMPARE(view.currentProgram(track), melodic);
    QCOMPARE(padText(), QStringLiteral("Kick"));
    view.setEditCursorTick(0);
    // One sample past the rounded event boundary avoids inverse-conversion
    // roundoff placing the playhead fractionally before the change tick.
    view.setPlayheadSample(timeline.sampleForTick(changeTick) + 1, true);
    QVERIFY(view.playheadTick() >= double(changeTick));
    QCOMPARE(view.currentProgram(track), melodic);
    QCOMPARE(padText(), QStringLiteral("Kick"));
    view.setPlayheadSample(0, true);
    QCOMPARE(view.currentProgram(track), initial);
    QCOMPARE(padText(), QStringLiteral("Kick"));
    QCOMPARE(view.selectionModel().primaryTrack(), track);
}

void TimelinePanTest::hoverChipOverlayUnclipped()
{
    using namespace songview;
    SongView &view = m_fixture.view();
    TimelineQuickScene *const scene = m_fixture.scene();

    const MidiTimeline *const timeline = view.timeline();
    QVERIFY(timeline);
    const int primaryTrack = view.selectionModel().primaryTrack();
    const int firstProgram = timeline->tracks[primaryTrack].firstProgram;
    const int program = firstProgram < 0 ? 0 : firstProgram;
    QVERIFY(program < VOICEGROUP_SIZE);

    QQuickItem *const root = view.quickView()->rootObject();
    QVERIFY(root);
    auto *const rollInput =
        root->findChild<TimelineInputItem *>(QStringLiteral("timelineRollInput"));
    auto *const gutterInput =
        root->findChild<TimelineInputItem *>(QStringLiteral("timelineRollGutterInput"));
    auto *const plotBox = root->findChild<QQuickItem *>(QStringLiteral("timelineQuickRollPlot"));
    auto *const gutterBox =
        root->findChild<QQuickItem *>(QStringLiteral("timelineQuickRollGutter"));
    QVERIFY(rollInput);
    QVERIFY(gutterInput);
    QVERIFY(plotBox);
    QVERIFY(gutterBox);

    const std::optional<std::array<int, 3>> padKeys = drumPadKeys(view, rollInput->height());
    QVERIFY2(padKeys.has_value(), "Fixture must expose an accidental and two natural pad rows");
    const int namedKey = (*padKeys)[0];
    const int unnamedKey = (*padKeys)[1];
    const int longKey = (*padKeys)[2];

    DrumBankFixture fixture(program, namedKey, unnamedKey, longKey);
    const LoadedVoiceGroup *const originalBank = view.voicegroup();
    const auto restoreBank =
        qScopeGuard([&view, originalBank] { view.setVoicegroup(originalBank); });
    const auto leaveGutter = qScopeGuard([&] {
        checks::events::sendMouse(*gutterInput, QEvent::Leave, QPointF(), Qt::NoButton,
                                  Qt::NoButton, Qt::NoModifier);
        checks::support::pumpQuick();
    });
    view.setVoicegroup(&fixture.bank);
    checks::support::pumpQuick();

    // Hover the long-named pad: the scene publishes the full-width chip.
    hoverPadRow(view, *gutterInput, longKey);
    QVERIFY(scene->hoverChipVisible());
    QCOMPARE(scene->hoverChipText(), QString::fromUtf8(kDrumPadLongName));

    auto *const chip = root->findChild<QQuickItem *>(QStringLiteral("timelineQuickPianoHoverChip"));
    auto *const chipText =
        root->findChild<QQuickItem *>(QStringLiteral("timelineQuickPianoHoverChipText"));
    QVERIFY(chip);
    QVERIFY(chipText);

    // The chip overlay lives on the unclipped roll band root — reached
    // through the plot box's parent — not inside the clipped gutter box.
    QQuickItem *const bandRoot = plotBox->parentItem();
    QVERIFY(bandRoot);
    QVERIFY(!bandRoot->clip());
    QCOMPARE(chip->parentItem(), bandRoot);
    QCOMPARE(chipText->parentItem(), bandRoot);
    QVERIFY(chip->z() > plotBox->z());
    QVERIFY(chip->z() > gutterBox->z());
    QVERIFY(chipText->z() > chip->z());

    // Locate a realized fixed label by its displayed text, independently of
    // delegate class names or sibling order, then check its visual ancestry.
    QVERIFY(gutterBox->clip());
    QQuickItem *fixedLabel = nullptr;
    QList<QQuickItem *> pendingItems{root};
    while (!pendingItems.isEmpty()) {
        QQuickItem *const item = pendingItems.takeLast();
        if (item->property("text").toString() == QString::fromUtf8(kDrumPadName)) {
            fixedLabel = item;
            break;
        }
        pendingItems.append(item->childItems());
    }
    QVERIFY(fixedLabel);
    QVERIFY(fixedLabel->isVisible());
    QQuickItem *labelAncestor = fixedLabel->parentItem();
    while (labelAncestor && labelAncestor != gutterBox)
        labelAncestor = labelAncestor->parentItem();
    QCOMPARE(labelAncestor, gutterBox);
    QCOMPARE(gutterInput->parentItem(), gutterBox);

    // The full pad-name chip is wider than the fixed gutter and its
    // scene-mapped right edge crosses the gutter boundary into the plot.
    QVERIFY(chip->width() > qreal(view.pianoKeyboardWidth()));
    QCOMPARE(chip->width(), scene->hoverChipRect().width());
    QCOMPARE(chip->x(), scene->hoverChipRect().x());
    QCOMPARE(chipText->property("text").toString(), QString::fromUtf8(kDrumPadLongName));
    QVERIFY(chip->isVisible());
    QVERIFY(chipText->isVisible());
    QCOMPARE(chipText->x(), chip->x());
    QCOMPARE(chipText->y(), chip->y());
    QCOMPARE(chipText->width(), chip->width());
    QCOMPARE(chipText->height(), chip->height());
    const qreal contentWidth = chipText->property("contentWidth").toReal();
    const qreal contentHeight = chipText->property("contentHeight").toReal();
    QVERIFY(contentWidth > 0);
    QVERIFY(contentHeight > 0);
    QVERIFY(contentWidth <= chipText->width());
    QVERIFY(contentHeight <= chipText->height());
    QVERIFY(!chipText->clip());
    QCOMPARE(chipText->property("horizontalAlignment").toInt(), int(Qt::AlignHCenter));
    QCOMPARE(chipText->property("verticalAlignment").toInt(), int(Qt::AlignVCenter));
    const QRectF contentRect((chipText->width() - contentWidth) / 2,
                             (chipText->height() - contentHeight) / 2, contentWidth, contentHeight);
    const QRectF contentSceneRect = chipText->mapRectToScene(contentRect);
    const QPointF chipSceneRight = chip->mapToScene(QPointF(chip->width(), 0));
    const QPointF gutterSceneRight = gutterBox->mapToScene(QPointF(gutterBox->width(), 0));
    QVERIFY(chipSceneRight.x() > gutterSceneRight.x());
    QVERIFY(contentSceneRect.right() > gutterSceneRight.x());
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
