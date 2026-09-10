#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class DrawerPresentationTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(DrawerPresentationTest)

  public:
    DrawerPresentationTest() = default;

  private slots:
    void drawerSurfaceAndChrome();
    void drawerToggleTransactions_data();
    void drawerToggleTransactions();
    void drawerZeroHeightKeyboardToggle();
    void drawerKeyboardResizeAndHover();
    void drawerStackAndCanonicalInputs();
    void drawerResizeTransactions_data();
    void drawerResizeTransactions();
    void drawerVoiceHandleOverflowsToAutomation();
    void drawerVoiceOverflowReversesToOriginalHeights();
    void drawerCollapseAndActivePage();
    void drawerFocusFallback();
    void drawerHostClampAndHeaderRouting();

    // Inline Quick value prompt coverage (Cleanup phase 4).
    void valuePromptTempoLimitsAcceptAndClamp();
    void valuePromptCcCenterOffsetInsertionCommit();
    void valuePromptEscapeCancelsAndReturnsFocus();
    void valuePromptFocusLossDocumentChangeAndPageHideCancel();
    void valuePromptCancelAndLateAcceptWriteNothing();

    void voiceSurfaceAndPaintLifecycle();
    void voiceHoverLifecycle();
    void voiceRefreshLifecycle();
    void voicePickerTransactions();
    void voiceContextMenuTransactions();
    void voiceMenuTargetHoldsAcrossCameraScroll();
    void voiceMenuStaleDocumentRejectsPick();
    void voiceMenuOutsideRightDismissesWithoutRetarget();
    void voiceMenuForeignTakeoverStaysUsable();
    void voiceMarkerDragTransactions();
    void voiceCameraTransactions();
};

class VelocityPageTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VelocityPageTest)

  public:
    VelocityPageTest(QString scratchProject, QString songLabel);

  private slots:
    void fixtureRoute101AndInputGeometry();
    void chromeAndContinuousAxis();
    void continuousGraduationDensity();
    void gridAndPanClamp();
    void psgAxisContexts_data();
    void psgAxisContexts();
    void hoveredPsgContext();
    void psgRenderingAndDetentToggle();
    void editCursorAndContextRounding();
    void transientBandAndStackedNodes();
    void rampAndRollPreview();
    void velocityGestureTransactions();
    void textRetentionAndPlayheadPerformance();

  private:
    QString m_scratchProject;
    QString m_songLabel;
};

int runEditorDrawerCheck(const QStringList &qtArguments);
int runVelocityPageCheck(const QString &scratchProject, const QString &songLabel,
                         const QStringList &qtArguments);
