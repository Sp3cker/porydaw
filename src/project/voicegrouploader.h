#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

#include <functional>
#include <memory>
#include <optional>

class QThread;
extern "C" {
#include "voicegroup_loader.h"
}

struct VoicegroupLoadRequest {
    QString projectRoot;
    QStringList candidates;
    std::optional<VoicegroupLoaderConfig> config;
};

// Copyable result envelope. A loaded voicegroup remains owned by the envelope
// until the UI thread explicitly adopts it with takeVoicegroup().
class VoicegroupLoadResult
{
  public:
    VoicegroupLoadResult() = default;

    bool succeeded() const;
    QString triedCandidates() const;
    QString errorText() const;
    LoadedVoiceGroup *takeVoicegroup();

  private:
    struct State;
    explicit VoicegroupLoadResult(std::shared_ptr<State> state);

    std::shared_ptr<State> m_state;

    friend class VoicegroupLoader;
};

// Owns one worker thread. All poryaaaa voicegroup_load calls submitted here
// execute serially on that thread; completions return to this object's thread.
class VoicegroupLoader final : public QObject
{
  public:
    using Completion = std::function<void(VoicegroupLoadResult)>;

    explicit VoicegroupLoader(QObject *parent = nullptr);
    ~VoicegroupLoader() override;

    void load(VoicegroupLoadRequest request, Completion completion);

  private:
    QThread *m_thread = nullptr;
    QObject *m_worker = nullptr;
};
