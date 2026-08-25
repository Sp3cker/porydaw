#include "projectio.h"

#include <QMetaObject>
#include <QThread>

#include <optional>
#include <utility>

ProjectSnapshot::ProjectSnapshot(QString root, QVector<SongInfo> songs,
                                 QHash<QString, int> trackBudgets)
    : m_root(std::move(root))
    , m_songs(std::move(songs))
    , m_trackBudgets(std::move(trackBudgets))
{}

bool ProjectSnapshot::isOpen() const
{
    return !m_root.isEmpty();
}

const QString &ProjectSnapshot::root() const
{
    return m_root;
}

const QVector<SongInfo> &ProjectSnapshot::songs() const
{
    return m_songs;
}

int ProjectSnapshot::trackBudgetFor(const SongInfo &song) const
{
    return m_trackBudgets.value(song.label, 16);
}

class ProjectIo::Worker final : public QObject
{
  public:
    ProjectOpenResult prepareProject(const QString &root, uint64_t generation)
    {
        if (QThread::currentThread() != thread())
            return {{}, QStringLiteral("Project open did not run on the project thread.")};
        m_candidate.reset();
        m_candidateGeneration = 0;
        auto candidate = DecompProject{};
        auto error = QString{};
        if (!candidate.open(root, &error))
            return {{}, std::move(error)};
        auto trackBudgets = QHash<QString, int>{};
        trackBudgets.reserve(candidate.songs().size());
        for (const auto &song : candidate.songs())
            trackBudgets.insert(song.label, candidate.trackBudgetFor(song));
        auto snapshot =
            ProjectSnapshot{candidate.root(), candidate.songs(), std::move(trackBudgets)};
        m_candidate = std::move(candidate);
        m_candidateGeneration = generation;
        return {std::move(snapshot), {}};
    }

    bool commitProject(uint64_t generation)
    {
        Q_ASSERT(QThread::currentThread() == thread());
        if (!m_candidate || generation != m_candidateGeneration)
            return false;
        m_project = std::move(*m_candidate);
        m_candidate.reset();
        m_candidateGeneration = 0;
        return true;
    }

  private:
    DecompProject m_project;
    std::optional<DecompProject> m_candidate;
    uint64_t m_candidateGeneration = 0;
};

ProjectIo::ProjectIo(QObject *parent) : QObject(parent), m_thread(new QThread(this))
{
    m_worker = new Worker;
    m_worker->moveToThread(m_thread);
    connect(m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    m_thread->start();
}

ProjectIo::~ProjectIo()
{
    Q_ASSERT(QThread::currentThread() == thread());
    ++m_generation;
    m_completion = {};
    m_thread->quit();
    m_thread->wait();
}

void ProjectIo::openProject(QString root, OpenCompletion completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    const uint64_t generation = ++m_generation;
    m_completion = std::move(completion);
    QMetaObject::invokeMethod(
        m_worker,
        [this, root = std::move(root), generation]() mutable {
            auto result = m_worker->prepareProject(root, generation);
            QMetaObject::invokeMethod(
                this,
                [this, generation, result = std::move(result)]() mutable {
                    if (generation != m_generation)
                        return;
                    if (result.succeeded()) {
                        auto committed = false;
                        const auto invoked = QMetaObject::invokeMethod(
                            m_worker,
                            [this, generation, &committed] {
                                committed = m_worker->commitProject(generation);
                            },
                            Qt::BlockingQueuedConnection);
                        if (!invoked || !committed)
                            result = {{}, QStringLiteral("Project open result became stale.")};
                    }
                    auto completion = std::move(m_completion);
                    if (completion)
                        completion(std::move(result));
                },
                Qt::QueuedConnection);
        },
        Qt::QueuedConnection);
}
