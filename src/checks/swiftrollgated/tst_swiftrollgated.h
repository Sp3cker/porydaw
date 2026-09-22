#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class QColor;
class QImage;
class QPoint;
class QQuickItem;
class QQuickWindow;
class QRectF;

namespace gridcheck {
bool activateWindow(QQuickWindow *window);
bool awaitFrame(QQuickWindow *window);
QColor pixelAt(const QImage &image, const QPoint &logicalPoint);
bool colorsNear(const QColor &actual, const QColor &expected);
QQuickItem *visualDescendant(QQuickItem *root, const QString &name);
int visiblePrimitiveCount(QQuickItem *root, const QRectF &sceneClip);
} // namespace gridcheck

class SwiftRollGatedTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SwiftRollGatedTest)

  public:
    SwiftRollGatedTest(QString mode, QString projectRoot, QString songLabel);

  private slots:
    void init();
    void failedReopenLeavesEmptyStripAndSurfacesError();
    void pointerDrawMoveAndNeighborTrim();
    void resizeEdgesRespectMinimumDuration();
    void windowUndoRedoRerenders();
    void rightDragSelectionCommits();
    void escapeCancelsSelectionBand();
    void ungrabCancelsSelectionBand();
    void trackFollowAndSessionReplacement();
    void focusedGridCommandRouting();
    void bareSpaceKeepsWindowPriority();
    void hostClipboardRoundTripAndReplacement();
    void selectionReticleRasterTranslucency();
    void noteRasterParity();
    void chromeRasterParity();
    void drawerAutomationHoverRaster_data();
    void drawerAutomationHoverRaster();
    void drawerVoicePreviewTransaction_data();
    void drawerVoicePreviewTransaction();
    void drawerGripKeyboardIsolation();
    void songTabsGeometryAndSelection();
    void songTabsScrollControlsAndGridInput();
    void songTabsOpenCreatesIndependentWorkspace();
    void songTabsSwitchPreservesPageState();
    void songTabsPointerReorderPreservesIdentities();
    void songTabsBackgroundClosePreservesActive();
    void songTabsFinalCloseEmptyAndReopen();
    void songTabsReopenExistingFocusesTab();
    // Declared last: the Save path writes a song into the shared scratch
    // project, so the scenarios that read the pristine fixture run first.
    void songTabsDirtyCancelDiscardSave();

  private:
    QString m_mode;
    QString m_projectRoot;
    QString m_songLabel;
};

int runSwiftGridBoundaryCheck(const QString &mode, const QString &projectRoot,
                              const QString &songLabel, const QStringList &qtArguments);
