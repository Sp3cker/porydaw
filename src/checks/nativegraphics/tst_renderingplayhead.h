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
    void positionOnlyDoesNotRebuild();
    void plotGeometryAndLifecycle();

  private:
    QString m_projectRoot;
    QString m_songLabel;
};
