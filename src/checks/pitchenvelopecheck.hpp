#pragma once

#include <QString>
#include <QWidget>

#include "core/songdocument.h"
#include "ui/songview.h"

int runPitchEnvelopeCheck(SongDocument &document, SongView &view, QWidget *roll,
                          const DocNote &fixtureNote, const QString &songLabel);
