#pragma once

#include <QPoint>
#include <QString>
#include <QWidget>

#include "core/songdocument.h"
#include "ui/songview.h"

int runPitchBendCheck(SongDocument &document, SongView &view, QWidget *roll, int engineTrack,
                      const DocNote &note, const QPoint &noteCenter, const QString &songLabel);
