#pragma once

#include "project/voicegroupsource.h"

#include <QString>

#include <QPointer>
#include <QtGlobal>

#include <cstdint>
#include <memory>

class QImage;
class QPoint;

class QQuickItem;
class QQuickWindow;
class SongTab;
class SongView;

namespace checks {
class QuickSceneHost;
}

namespace songview {
class TimelineInputItem;
class TimelineQuickScene;
} // namespace songview

namespace checks::timelinepan {

class TimelinePanFixture final
{
  public:
    TimelinePanFixture(const QString &projectRoot, const QString &songLabel);
    ~TimelinePanFixture();

    bool load(QString &error);
    void show();
    bool isReady(bool requiresExposedWindow);

    SongView &view() const;
    songview::TimelineQuickScene *scene() const;

    qreal pan(const QPoint &pixelDelta);
    QImage render() const;
    QImage capture(QString *error) const;
    bool measureSelectedPan(uint64_t beats, qint64 *elapsedMilliseconds, QString *error);

    void cleanup();

  private:
    bool setSelection(uint64_t endTick);

    QString m_projectRoot;
    QString m_songLabel;
    LoadedVoiceGroup m_bank = {};
    std::unique_ptr<SongTab> m_tab;
    std::unique_ptr<checks::QuickSceneHost> m_host;
    QPointer<QQuickWindow> m_window;
    QPointer<QQuickItem> m_root;
    songview::TimelineInputItem *m_input = nullptr;
    songview::TimelineQuickScene *m_scene = nullptr;
};

} // namespace checks::timelinepan
