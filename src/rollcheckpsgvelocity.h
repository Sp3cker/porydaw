#pragma once

#include <QPoint>
#include <QString>

extern "C" {
#include "voicegroup_loader.h"
}

class SongDocument;
class SongView;

struct RollCheckPsgVelocityContext {
    SongDocument &document;
    SongView &view;
    const LoadedVoiceGroup *voicegroup;
    const QString &songLabel;
    int track;
    QPoint restoreLatchCenter;
};

int runRollCheckPsgVelocity(const RollCheckPsgVelocityContext &context);
