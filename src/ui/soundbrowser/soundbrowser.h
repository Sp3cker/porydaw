#pragma once

#include <QList>
#include <QObject>
#include <QPair>
#include <QPointer>
#include <QString>
#include <QStringList>

#include <cstdint>
#include <memory>

#include "audio/auditionslots.h"
#include "project/projectworkspace.h"

class AudioEngine;

extern "C" {
#include "voicegroup_loader.h"
}

// What a picker row stands for, so the owner resolves its audition
// correctly: samples publish PCM, waves publish CGB wave bytes, keysplits
// resolve to whichever sub-voice the audition key lands on.
enum class VgAuditionKind { Sample, Wave, Keysplit };

// Row metadata the picker displays, resolved by the owner from the project's
// committed sample files (the same WaveData the engine would play).
struct SamplePickInfo {
    bool known = false; // symbol resolved to sample data
    bool looped = false;
    int rateHz = 0;
    double seconds = 0.0; // length at the sample's own rate
};

namespace soundbrowser {

// The one browse-audition coordinator: it owns symbol resolution, metadata,
// engine dispatch and per-owner start/stop for every browse surface (slot
// list, sample popup, voice picker, library preview). All methods run on the
// GUI thread. `owner` is the actual audition surface instance; only a
// QPointer to it is retained. The engine and the sample set stay borrowed.
enum class AuditionStatus { Started, NotReady, Unsupported, Busy, DecodeError };

struct AuditionResult {
    AuditionStatus status;
    QString message; // empty on success; descriptive failure text for the caller's status line
};

class SoundBrowser final : public QObject
{
    Q_OBJECT

  public:
    explicit SoundBrowser(AudioEngine &engine, QObject *parent = nullptr);
    ~SoundBrowser() override;

    void setProjectSamples(SampleSetLease samples, const VoicegroupCatalog &catalog);
    void clearProjectSamples();
    SamplePickInfo sampleInfo(const QString &symbol) const;
    void previewVoice(QObject *owner, int program, int key, int velocity);
    AuditionResult auditionSymbol(QObject *owner, const QString &symbol, VgAuditionKind kind,
                                  const AuditionSlots::Adsr &adsr);
    AuditionResult auditionExternalFile(QObject *owner, const QString &path, uint8_t key);
    void stop(QObject *owner);
    void stopAll();

  private:
    enum class RequestKind { Program, Symbol, External };

    void takeOwnership(QObject *owner, RequestKind kind);
    void clearActive();
    void releaseActive(); // clear ownership, then release both engine lanes
    void onOwnerDestroyed(QObject *dead);
    AudioEngine &m_engine; // borrowed; outlives this coordinator
    SampleSetLease m_samples;
    // Ordered symbol lists that supplied the retained set (Qt implicitly
    // shared); resolution indexes the set through these, never the catalog.
    QStringList m_directSound;
    QStringList m_progWave;
    QList<QPair<QString, QString>> m_keysplits;

    bool m_hasActive = false;
    RequestKind m_kind = RequestKind::Program;
    QPointer<QObject> m_owner;          // live handle for stop() matching
    QObject *m_ownerIdentity = nullptr; // raw identity for destroyed() matching; never dereferenced
    QMetaObject::Connection m_ownerGone;
    int m_program = -1;
    int m_key = -1;
};

} // namespace soundbrowser
