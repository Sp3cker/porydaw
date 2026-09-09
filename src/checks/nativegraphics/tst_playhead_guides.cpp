#include <QtTest>

#include <QImage>
#include <QObject>
#include <QPointF>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QRectF>
#include <QSize>
#include <QSizeF>
#include <QString>
#include <QStringList>

#include <array>
#include <cmath>
#include <cstdint>
#include <memory>
#include <optional>
#include <utility>

#include "checks/nativegraphics/nativegraphics_fixture.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "checks/support/timelinequickcheck.h"
#include "core/miditimeline.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickchrome.h"
#include "ui/songview/quick/timelinequickview.h"

namespace {

class PlayheadGuidesTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(PlayheadGuidesTest)

  public:
    PlayheadGuidesTest(QString projectRoot, QString songLabel)
        : m_projectRoot(std::move(projectRoot))
        , m_songLabel(std::move(songLabel))
    {}

  private slots:
    void devicePixelRect();
    void guidesResizeScrollAndOwnership();
    void guidesTrackCanvasItemInsideWindow();
    void followScroll();

  private:
    QString m_projectRoot;
    QString m_songLabel;
};

QSize staticSize()
{
    return QSize{90 * layout::space(layout::Space::One), 65 * layout::space(layout::Space::One)};
}
constexpr qreal kGuideTolerance = 0.2;

struct ChromePair {
    const char *name;
    songview::TimelineChromeItem *hover = nullptr;
    songview::TimelineChromeItem *edit = nullptr;
};

std::array<ChromePair, 7> chromePairs(QQuickItem &root)
{
    std::array<ChromePair, 7> pairs{{{"Ruler"},
                                     {"Roll"},
                                     {"Automation"},
                                     {"Velocity"},
                                     {"VoiceChanges"},
                                     {"OtherEvents"},
                                     {"TrackHeaders"}}};
    for (ChromePair &pair : pairs) {
        const QString prefix = QStringLiteral("timelineQuick") + QString::fromLatin1(pair.name);
        pair.hover =
            root.findChild<songview::TimelineChromeItem *>(prefix + QStringLiteral("HoverChrome"));
        pair.edit =
            root.findChild<songview::TimelineChromeItem *>(prefix + QStringLiteral("EditChrome"));
    }
    return pairs;
}

bool allGuidesVisible(const std::array<ChromePair, 7> &pairs, bool hover, bool edit)
{
    for (const ChromePair &pair : pairs) {
        const bool bandVisible = pair.hover->parentItem()->isVisible();
        if (pair.hover->isVisible() != (hover && bandVisible) ||
            pair.edit->isVisible() != (edit && bandVisible))
            return false;
    }
    return true;
}

std::unique_ptr<checks::nativegraphics::Rig> staticRig(const QString &projectRoot,
                                                       const QString &songLabel)
{
    QString error;
    std::unique_ptr<checks::nativegraphics::Rig> rig =
        checks::nativegraphics::makeRig(projectRoot, songLabel, staticSize(), error);
    if (!rig)
        QTest::qFail(qPrintable(error), __FILE__, __LINE__);
    return rig;
}

void PlayheadGuidesTest::devicePixelRect()
{
    const QRect logicalRect{3, 2, 5, 4};
    QImage dprOne{QSize{16, 10}, QImage::Format_ARGB32_Premultiplied};
    dprOne.setDevicePixelRatio(1.0);
    QCOMPARE(checks::support::devicePixelRect(dprOne, logicalRect), logicalRect);

    QImage dprTwo{QSize{32, 20}, QImage::Format_ARGB32_Premultiplied};
    dprTwo.setDevicePixelRatio(2.0);
    const QRect doubleRect{6, 4, 10, 8};
    QCOMPARE(checks::support::devicePixelRect(dprTwo, logicalRect), doubleRect);

    QImage dprOnePointFive{QSize{12, 14}, QImage::Format_ARGB32_Premultiplied};
    dprOnePointFive.setDevicePixelRatio(1.5);
    const QRect fractionalRect{4, 3, 8, 6};
    const QRect roundingRect{1, 1, 4, 4};
    QCOMPARE(checks::support::devicePixelRect(dprOnePointFive, logicalRect), fractionalRect);
    QCOMPARE(checks::support::devicePixelRect(dprOnePointFive, QRect{1, 1, 2, 2}), roundingRect);
}

void PlayheadGuidesTest::guidesResizeScrollAndOwnership()
{
    std::unique_ptr<checks::nativegraphics::Rig> rig = staticRig(m_projectRoot, m_songLabel);
    QVERIFY(rig);
    SongView &view = rig->song->view();
    auto *quick = view.quickView();
    QVERIFY(quick && quick->rootObject());
    QQuickItem *root = quick->rootObject();
    const std::array<ChromePair, 7> pairs = chromePairs(*root);
    for (const ChromePair &pair : pairs) {
        QVERIFY2(pair.hover && pair.edit, pair.name);
    }

    const std::optional<songview::TimelineBandGeometry> &ruler =
        view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    QVERIFY(ruler);
    const auto songX = [&view, &ruler](uint64_t tick) {
        return qreal(ruler->plotRect.x()) + view.camera().contentX(tick);
    };
    // The Quick window is the full canonical viewport, so song-view x and
    // Quick-root x are the same coordinate; no host translation remains.
    const auto rootX = [](qreal x) { return x; };

    const qreal beforeStart = songX(0) - layout::singlePixel();
    view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
    quick->synchronizeGuides(view.timelineSplitX(), beforeStart);
    quick->publishHover(songview::TimelineQuickHoverOwner::Automation, 0, beforeStart);
    checks::support::pumpQuick();
    QVERIFY(!quick->hoverVisible());
    QVERIFY(!quick->editVisible());
    QVERIFY(allGuidesVisible(pairs, false, false));

    const uint64_t tick = uint64_t((std::max)(0.0, view.camera().tickAtContentX(1.0)));
    view.setEditCursorTick(0);
    quick->synchronizeGuides(view.timelineSplitX(), songX(0));
    checks::support::pumpQuick();
    QVERIFY(quick->editVisible());
    QVERIFY(!quick->hoverVisible());
    QVERIFY(allGuidesVisible(pairs, false, true));
    QVERIFY(qAbs(quick->editRootContentX() - rootX(songX(0))) <= kGuideTolerance);

    // Hover replaces the edit guide; their relative z-order is not observable.
    quick->publishHover(songview::TimelineQuickHoverOwner::Automation, tick, songX(tick));
    checks::support::pumpQuick();
    QVERIFY(quick->hoverVisible());
    QVERIFY(allGuidesVisible(pairs, true, false));
    QVERIFY(qAbs(quick->hoverRootContentX() - rootX(songX(tick))) <= kGuideTolerance);
    for (const ChromePair &pair : pairs) {
        QVERIFY(qAbs(checks::support::quickRootX(*pair.hover, *root) - rootX(songX(tick))) <=
                kGuideTolerance);
        QVERIFY(qAbs(checks::support::quickRootX(*pair.edit, *root) - rootX(songX(0))) <=
                kGuideTolerance);
    }

    view.publishTimelineQuickHover(songview::TimelineQuickHoverOwner::VoiceChanges, tick + 1);
    view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
    checks::support::pumpQuick();
    QVERIFY(quick->hoverVisible());
    QVERIFY(qAbs(quick->hoverRootContentX() - rootX(songX(tick + 1))) <= kGuideTolerance);
    view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::VoiceChanges);
    checks::support::pumpQuick();
    QVERIFY(!quick->hoverVisible());
    QVERIFY(quick->editVisible());
    QVERIFY(allGuidesVisible(pairs, false, true));
    // Window-level resize stands in for the widget envelope: the canonical
    // viewport itself shrinks and restores, and guide alignment survives.
    QQuickWindow *window = quick->quickWindow();
    QVERIFY(window);
    const QSize originalSize = window->size();
    const QSize shrunkSize(originalSize.width(),
                           originalSize.height() - 4 * layout::space(layout::Space::One));
    window->resize(shrunkSize);
    checks::support::pumpQuick();
    QVERIFY(qAbs(quick->editRootContentX() - rootX(songX(0))) <= kGuideTolerance);
    window->resize(originalSize);
    checks::support::pumpQuick();

    const SongView::ViewState original = view.viewState();
    const qreal editBeforeScroll = quick->editRootContentX();
    view.setEditorHorizontalScroll(original.scrollPx + view.camera().pxPerBeat());
    checks::support::pumpQuick();
    QVERIFY(view.camera().scrollX() != original.scrollPx);
    QVERIFY(quick->editRootContentX() != editBeforeScroll);
    QVERIFY(qAbs(quick->editRootContentX() - rootX(songX(0))) <= kGuideTolerance);
}

void PlayheadGuidesTest::guidesTrackCanvasItemInsideWindow()
{
    std::unique_ptr<checks::nativegraphics::Rig> rig = staticRig(m_projectRoot, m_songLabel);
    QVERIFY(rig);
    SongView &view = rig->song->view();
    auto *quick = view.quickView();
    QVERIFY(quick && quick->rootObject());
    QQuickItem *root = quick->rootObject();
    QQuickWindow *window = quick->quickWindow();
    QVERIFY(window);
    const std::array<ChromePair, 7> pairs = chromePairs(*root);
    for (const ChromePair &pair : pairs) {
        QVERIFY2(pair.hover && pair.edit, pair.name);
    }

    const std::optional<songview::TimelineBandGeometry> &ruler =
        view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    QVERIFY(ruler);
    const auto songX = [&view, &ruler](uint64_t tick) {
        return qreal(ruler->plotRect.x()) + view.camera().contentX(tick);
    };
    const int unit = layout::space(layout::Space::One);
    const QSize roomySize(view.timelineSplitX() + 80 * unit, staticSize().height() + 24 * unit);
    window->resize(roomySize);
    checks::support::pumpQuick();
    const QSize windowSize = window->size();
    QCOMPARE(windowSize, roomySize);
    QCOMPARE(QSize(qRound(root->width()), qRound(root->height())), windowSize);
    const std::optional<songview::TimelineBandGeometry> &rollBefore =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    const std::optional<songview::TimelineBandGeometry> &otherBefore =
        view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents);
    QVERIFY(rollBefore && otherBefore);
    const qreal rulerPlotWidthBefore = ruler->plotRect.width();
    const qreal rollPlotTopBefore = rollBefore->plotRect.y();
    const qreal rollPlotWidthBefore = rollBefore->plotRect.width();
    const qreal rollPlotHeightBefore = rollBefore->plotRect.height();
    const qreal otherPlotTopBefore = otherBefore->plotRect.y();
    const QPointF canvasOffset{2.0 * unit, qreal(unit)};
    const QSizeF canvasShrink{6.0 * unit, 4.0 * unit};
    QVERIFY(rulerPlotWidthBefore > canvasShrink.width());
    QVERIFY(rollPlotWidthBefore > canvasShrink.width());
    QVERIFY(rollPlotHeightBefore > canvasShrink.height());
    QQuickItem &page = rig->song->viewport();
    page.setPosition(canvasOffset);
    page.setSize(
        QSizeF{page.width() - canvasShrink.width(), page.height() - canvasShrink.height()});
    checks::support::pumpQuick();
    QCOMPARE(window->size(), windowSize);
    QCOMPARE(page.position(), canvasOffset);
    QCOMPARE(root->position(), QPointF());
    const QSizeF expectedCanvasSize{windowSize.width() - canvasShrink.width(),
                                    windowSize.height() - canvasShrink.height()};
    QCOMPARE(page.size(), expectedCanvasSize);
    QCOMPARE(root->size(), expectedCanvasSize);

    view.clearTimelineQuickHover(songview::TimelineQuickHoverOwner::Automation);
    const uint64_t tick = uint64_t((std::max)(0.0, view.camera().tickAtContentX(1.0)));
    view.setEditCursorTick(0);
    quick->synchronizeGuides(view.timelineSplitX(), songX(0));
    checks::support::pumpQuick();
    QVERIFY(!quick->hoverVisible());
    QVERIFY(quick->editVisible());
    QVERIFY(allGuidesVisible(pairs, false, true));
    QVERIFY(qAbs(quick->editRootContentX() - songX(0)) <= kGuideTolerance);
    const qreal canvasSceneX = root->mapToScene(QPointF{}).x();
    for (const ChromePair &pair : pairs) {
        QVERIFY(qAbs(checks::support::quickRootX(*pair.edit, *root) - songX(0)) <= kGuideTolerance);
        QVERIFY(qAbs(pair.edit->mapToScene(QPointF{}).x() - (canvasSceneX + songX(0))) <=
                kGuideTolerance);
    }
    quick->publishHover(songview::TimelineQuickHoverOwner::Automation, tick, songX(tick));
    checks::support::pumpQuick();
    QVERIFY(quick->hoverVisible());
    QVERIFY(allGuidesVisible(pairs, true, false));
    QVERIFY(qAbs(quick->hoverRootContentX() - songX(tick)) <= kGuideTolerance);
    const std::optional<songview::TimelineBandGeometry> &rulerNow =
        view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    const std::optional<songview::TimelineBandGeometry> &rollNow =
        view.timelineBandLayout().geometry(songview::TimelineBand::Roll);
    const std::optional<songview::TimelineBandGeometry> &otherNow =
        view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents);
    QVERIFY(rulerNow && rollNow && otherNow);
    QCOMPARE(rulerNow->plotRect.width(), qRound(rulerPlotWidthBefore - canvasShrink.width()));
    QCOMPARE(rollNow->plotRect.y(), qRound(rollPlotTopBefore));
    QCOMPARE(otherNow->plotRect.y(), qRound(otherPlotTopBefore - canvasShrink.height()));
    QCOMPARE(rollNow->plotRect.width(), qRound(rollPlotWidthBefore - canvasShrink.width()));
    const QRect overlayNow = view.editorDrawer() ? view.editorDrawer()->overlayRect() : QRect{};
    const int stackBottomNow = otherNow->rect.top() - 1;
    const int expectedRollBottom =
        overlayNow.isEmpty() ? stackBottomNow : std::min(stackBottomNow, overlayNow.top() - 1);
    QCOMPARE(rollNow->rect.bottom(), expectedRollBottom);
    QCOMPARE(rollNow->plotRect.height(), expectedRollBottom - rollNow->plotRect.y() + 1);
    const ChromePair &rulerPair = pairs[0];
    const ChromePair &rollPair = pairs[1];
    const ChromePair &otherPair = pairs[5]; // OtherEvents
    QVERIFY2(qAbs(rulerPair.hover->width() - qreal(rulerNow->plotRect.width())) <= kGuideTolerance,
             qPrintable(QStringLiteral("ruler chrome width actual=%1 canonical plot=%2")
                            .arg(rulerPair.hover->width())
                            .arg(rulerNow->plotRect.width())));
    QVERIFY(qAbs(rollPair.hover->mapToScene(QPointF{}).y() - root->mapToScene(QPointF{}).y() -
                 qreal(rollNow->plotRect.y())) <= kGuideTolerance);
    QVERIFY2(qAbs(rollPair.hover->height() - qreal(rollNow->plotRect.height())) <= kGuideTolerance,
             qPrintable(QStringLiteral("roll chrome height actual=%1 canonical plot=%2")
                            .arg(rollPair.hover->height())
                            .arg(rollNow->plotRect.height())));
    QVERIFY(qAbs(otherPair.hover->mapToScene(QPointF{}).y() - root->mapToScene(QPointF{}).y() -
                 qreal(otherNow->plotRect.y())) <= kGuideTolerance);
    QVERIFY2(qAbs(rollPair.hover->width() - qreal(rollNow->plotRect.width())) <= kGuideTolerance,
             qPrintable(QStringLiteral("roll chrome width actual=%1 canonical plot=%2")
                            .arg(rollPair.hover->width())
                            .arg(rollNow->plotRect.width())));
}

void PlayheadGuidesTest::followScroll()
{
    std::unique_ptr<checks::nativegraphics::Rig> rig = staticRig(m_projectRoot, m_songLabel);
    QVERIFY(rig);
    SongView &view = rig->song->view();
    SongView::ViewState parked = view.viewState();
    parked.scrollPx = 0.0;
    parked.pxPerBeat = 512.0;
    view.applyViewState(parked);
    view.setFollowPlayhead(true);
    const uint64_t endTick = rig->song->timeline().lengthTicks;
    QVERIFY(endTick > 1);
    auto *quick = view.quickView();
    QVERIFY(quick && quick->quickWindow());
    const uint64_t farTick =
        (std::min)(endTick - 1,
                   uint64_t(quick->quickWindow()->width() * 4.0 / view.camera().pxPerTick()) + 1);
    QVERIFY(farTick > 0);
    const uint64_t sample = rig->song->timeline().sampleForTick(farTick);
    view.setPlayheadSample(sample, true);
    checks::support::pumpQuick();
    QVERIFY(view.camera().scrollX() > 0.0);

    view.applyViewState(parked);
    view.setFollowPlayhead(false);
    view.setPlayheadSample(sample, true);
    checks::support::pumpQuick();
    QCOMPARE(view.camera().scrollX(), 0.0);
    view.setFollowPlayhead(true);
    view.setPlayheadSample(sample, true);
    checks::support::pumpQuick();
    QVERIFY(view.camera().scrollX() > 0.0);
}

} // namespace

int runPlayheadGuidesCheck(const QString &projectRoot, const QString &songLabel,
                           const QStringList &qtArguments)
{
    PlayheadGuidesTest test{projectRoot, songLabel};
    QStringList arguments{QStringLiteral("playhead-guides")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_playhead_guides.moc"
