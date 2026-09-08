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
    void quickPolarityAndEdges_data();
    void quickPolarityAndEdges();
    void automationHoverDecor();
    void positionOnlyDoesNotRebuild();
    void plotGeometryAndLifecycle();
#ifdef __APPLE__
    void nativeLayerLifecycle();
#endif

  private:
    QString m_projectRoot;
    QString m_songLabel;
};
