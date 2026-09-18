#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void installGridSmoke(void);

#ifdef __cplusplus
}
void verifyGridAudio();
class QObject;
class QQuickWindow;
void verifyGridInteractions(QQuickWindow *window, QObject *model);
#endif
