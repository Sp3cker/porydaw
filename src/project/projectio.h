#pragma once

#include <QHash>
#include <QObject>
#include <QString>
#include <QVector>

#include <cstdint>
#include <functional>

#include "decompproject.h"

class QThread;

class ProjectSnapshot
{
  public:
    ProjectSnapshot() = default;
    ProjectSnapshot(QString root, QVector<SongInfo> songs, QHash<QString, int> trackBudgets);

    bool isOpen() const;
    const QString &root() const;
    const QVector<SongInfo> &songs() const;
    int trackBudgetFor(const SongInfo &song) const;

  private:
    QString m_root;
    QVector<SongInfo> m_songs;
    QHash<QString, int> m_trackBudgets;
};

struct ProjectOpenResult {
    ProjectSnapshot snapshot;
    QString error;

    bool succeeded() const { return snapshot.isOpen(); }
};

// GUI-facing owner of the project worker thread. Operations execute serially
// on that thread and deliver copied results back on this object's thread.
class ProjectIo final : public QObject
{
  public:
    using OpenCompletion = std::function<void(ProjectOpenResult)>;

    explicit ProjectIo(QObject *parent = nullptr);
    ~ProjectIo() override;

    void openProject(QString root, OpenCompletion completion);

  private:
    class Worker;

    QThread *m_thread = nullptr;
    Worker *m_worker = nullptr;
    OpenCompletion m_completion;
    uint64_t m_generation = 0;
};
