#pragma once

#include <QObject>
#include <QString>

class RenderingPlayheadTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(RenderingPlayheadTest)

  public:
    RenderingPlayheadTest(QString projectRoot, QString songLabel);

  private slots:
    void devicePixelRect();
    void quickPolarityAndEdges_data();
    void quickPolarityAndEdges();
    void guidesResizeScrollAndOwnership();
    void followScroll();
    void automationHoverDecor();
    void positionOnlyDoesNotRebuild();
    void quickUpdateRequestControl();
    void plotGeometryAndLifecycle();
#ifdef __APPLE__
    void nativeLayerLifecycle();
#endif

  private:
    QString m_projectRoot;
    QString m_songLabel;
};
