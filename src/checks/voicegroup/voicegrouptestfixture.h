#pragma once

#include <cstdint>
#include <memory>

#include <QByteArray>
#include <QString>

#include "project/decompproject.h"
#include "project/voicegroupsource.h"

extern "C" {
#include "voicegroup_loader.h"
}

namespace checks {
class ProjectFixture;
}

namespace voicegroup_test {

struct ProjectSession {
    std::unique_ptr<checks::ProjectFixture> copy;
    DecompProject project;
    SongInfo song;
    VoicegroupSource source;
    LoadedVoiceGroup *baseline = nullptr;

    ProjectSession();
    ~ProjectSession();
    ProjectSession(const ProjectSession &) = delete;
    ProjectSession &operator=(const ProjectSession &) = delete;

    const QString &root() const noexcept;
    QByteArray rootUtf8() const;
    QByteArray loadNameUtf8() const;
};

std::unique_ptr<ProjectSession> openSession(const QString &stagedRoot, const QString &songLabel,
                                            QString &error);
std::unique_ptr<checks::ProjectFixture> copyProject(const QString &stagedRoot, QString &error);
QByteArray readFile(const QString &path);
bool writeFile(const QString &path, const QByteArray &contents, QString &error);

struct VoiceSnapshot {
    uint8_t type = 0;
    uint8_t key = 0;
    uint8_t panSweep = 0;
    uint8_t attack = 0;
    uint8_t decay = 0;
    uint8_t sustain = 0;
    uint8_t release = 0;
    QByteArray name;
    uintptr_t packed = 0;

    bool operator==(const VoiceSnapshot &other) const;
};

VoiceSnapshot snapshot(const LoadedVoiceGroup &group, int slot);
QByteArray loaderVoiceName(const QString &symbol);
bool isDirectSound(VgMacro macro);
bool isSquare1(VgMacro macro);
bool isNoise(VgMacro macro);
bool isProgWave(VgMacro macro);
bool sameVoiceFields(const VgVoice &actual, const VgVoice &expected);
bool sameResolvedTone(const ToneData &actualAggregate, const ToneData &expectedAggregate,
                      int midiKey);

} // namespace voicegroup_test
