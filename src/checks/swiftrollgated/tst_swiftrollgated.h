#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class QColor;
class QImage;
class QPoint;
class QQuickItem;
class QRectF;

namespace gridcheck {
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
    void failedOpenPreservesSceneAndSurfacesError();
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

  private:
    QString m_mode;
    QString m_projectRoot;
    QString m_songLabel;
};

int runSwiftGridBoundaryCheck(const QString &mode, const QString &projectRoot,
                              const QString &songLabel, const QStringList &qtArguments);
