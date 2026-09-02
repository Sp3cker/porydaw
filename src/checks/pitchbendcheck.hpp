#pragma once

#include <QPoint>
#include <QString>

#include "core/songdocument.h"
#include "ui/songview.h"

namespace songview {
class TimelineInputItem;
}

int runPitchBendCheck(SongDocument &document, SongView &view, songview::TimelineInputItem *roll,
                      int engineTrack, const DocNote &note, const QPoint &noteCenter,
                      const QString &songLabel);
