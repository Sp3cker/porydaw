#pragma once

#include <QObject>
#include <QString>

#ifdef __APPLE__
class RenderingPlayheadNativeTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(RenderingPlayheadNativeTest)

  public:
    RenderingPlayheadNativeTest(QString projectRoot, QString songLabel);

  private slots:
    void nativeLayerLifecycle();

  private:
    QString m_projectRoot;
    QString m_songLabel;
};
#endif
