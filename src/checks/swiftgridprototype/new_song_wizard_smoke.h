#pragma once

class QQuickWindow;
class QQuickItem;
class QObject;

// Prototype-host smoke: real window input, validation, typed Swift results,
// exactly-once completion, and dialog/popup keyboard ownership.
void runNewSongWizardSmoke(QQuickWindow *hostWindow, QQuickItem *wizardButton,
                           QObject *newSongWizard, QObject *newSongResult);
