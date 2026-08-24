#include "voicegrouploader.h"

#include "voicegroupsource.h"

#include <QCoreApplication>
#include <QMetaObject>
#include <QThread>

#include <utility>

struct VoicegroupLoadResult::State {
    ~State()
    {
        if (voicegroup)
            voicegroup_free(voicegroup);
    }

    LoadedVoiceGroup *voicegroup = nullptr;
    std::unique_ptr<VoicegroupSource> editableSource;
    QString tried;
    QString error;
    QString editableSourceError;
};

VoicegroupLoadResult::VoicegroupLoadResult(std::shared_ptr<State> state) : m_state(std::move(state))
{}

bool VoicegroupLoadResult::succeeded() const
{
    return m_state && m_state->voicegroup;
}

QString VoicegroupLoadResult::triedCandidates() const
{
    return m_state ? m_state->tried : QString();
}

QString VoicegroupLoadResult::errorText() const
{
    return m_state ? m_state->error : QString();
}

QString VoicegroupLoadResult::editableSourceErrorText() const
{
    return m_state ? m_state->editableSourceError : QString();
}

LoadedVoiceGroup *VoicegroupLoadResult::takeVoicegroup()
{
    return m_state ? std::exchange(m_state->voicegroup, nullptr) : nullptr;
}

std::unique_ptr<VoicegroupSource> VoicegroupLoadResult::takeEditableSource()
{
    return m_state ? std::move(m_state->editableSource) : nullptr;
}

VoicegroupLoader::VoicegroupLoader(QObject *parent) : QObject(parent), m_thread(new QThread(this))
{
    m_worker = new QObject;
    m_worker->moveToThread(m_thread);
    connect(m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    m_thread->start();
}

VoicegroupLoader::~VoicegroupLoader()
{
    m_thread->quit();
    m_thread->wait();
}

void VoicegroupLoader::load(VoicegroupLoadRequest request, Completion completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    QMetaObject::invokeMethod(
        m_worker,
        [this, request = std::move(request), completion = std::move(completion)]() mutable {
            auto state = std::make_shared<VoicegroupLoadResult::State>();
            state->tried = request.candidates.join(QStringLiteral(", "));
            const QByteArray root = request.projectRoot.toLocal8Bit();
            const VoicegroupLoaderConfig *config = request.config ? &*request.config : nullptr;
            for (const QString &candidate : request.candidates) {
                const QByteArray name = candidate.toLocal8Bit();
                state->voicegroup = voicegroup_load(root.constData(), name.constData(), config);
                if (state->voicegroup)
                    break;
            }
            if (!state->voicegroup) {
                state->error =
                    state->tried.isEmpty()
                        ? QCoreApplication::translate("VoicegroupLoader",
                                                      "No voicegroup candidates were provided.")
                        : QCoreApplication::translate("VoicegroupLoader",
                                                      "Could not load the voicegroup (tried: %1).")
                              .arg(state->tried);
            }
            if (request.editableSourceArg) {
                auto source = std::make_unique<VoicegroupSource>();
                if (source->open(request.projectRoot, *request.editableSourceArg,
                                 &state->editableSourceError)) {
                    state->editableSource = std::move(source);
                }
            }
            auto result = VoicegroupLoadResult(std::move(state));
            QMetaObject::invokeMethod(
                this,
                [completion = std::move(completion), result = std::move(result)]() mutable {
                    if (completion)
                        completion(std::move(result));
                },
                Qt::QueuedConnection);
        },
        Qt::QueuedConnection);
}
