#pragma once

#include <QString>

class SongDocument;
class SongView;

struct RollCheckPsgVelocityMixedContext {
    SongDocument &document;
    SongView &view;
    const QString &songLabel;
    int track;
    int cgbSlot;
};

int runRollCheckPsgVelocityMixed(
    const RollCheckPsgVelocityMixedContext &context);
