#pragma once

#include <QObject>

class EventViewsChromeTest final : public QObject
{
    Q_OBJECT

  public:
    EventViewsChromeTest() = default;

  private:
    Q_DISABLE_COPY_MOVE(EventViewsChromeTest)

  private slots:
    void visibilityAndTrackSelection();
    void rowMirrorPlusEot_data();
    void rowMirrorPlusEot();
    void monoTypography();
    void columnResizeDrag();
    void drawerFocusKeepsNavigation();
    void scrollbarWheelClamps();
    void filterMenuSession();
    void rowMenuActivationCloses();
    void filterMatrix_data();
    void filterMatrix();
    void viewStateRoundTrip();
};

class EventViewsEditsTest final : public QObject
{
    Q_OBJECT

  public:
    EventViewsEditsTest() = default;

  private:
    Q_DISABLE_COPY_MOVE(EventViewsEditsTest)

  private slots:
    void tickEditQueued();
    void tick64BitExact();
    void tickHighBitExact();
    void tickHighBitThroughEditor();
    void channelAndDataConversions();
    void rawTempoAtomic();
    void insertCopy();
    void drawerClickAfterEditOwnsDelete();
    void sameTickReorder();
    void deleteMatrix();
};

class EventViewsRemapTest final : public QObject
{
    Q_OBJECT

  public:
    EventViewsRemapTest() = default;

  private:
    Q_DISABLE_COPY_MOVE(EventViewsRemapTest)

  private slots:
    void notifyOrder();
    void anchorFollowsMove();
    void deletedChunkUnselects();
    void metadataChunkTransition();
    void tempoProjectionRows();
};

class EventViewsPlayheadTest final : public QObject
{
    Q_OBJECT

  public:
    EventViewsPlayheadTest() = default;

  private:
    Q_DISABLE_COPY_MOVE(EventViewsPlayheadTest)

  private slots:
    void tintLastOfRun_data();
    void tintLastOfRun();
    void focusCommitsCursor();
    void focusedSiblingWins();
    void samplePathAndProgrammaticRestore();
    void followScroll();
};

class ViewBucketsGridTest final : public QObject
{
    Q_OBJECT

  public:
    ViewBucketsGridTest() = default;

  private:
    Q_DISABLE_COPY_MOVE(ViewBucketsGridTest)

  private slots:
    void bucketSum_data();
    void bucketSum();
    void quirkProjection();
    void snapLadder_data();
    void snapLadder();
    void gridLinesSnappable_data();
    void gridLinesSnappable();
    void paintSmoke();
};
