#pragma once

#include <QStringList>
#include <QtGlobal>

class QColor;
class QImage;
class QPixmap;
class QRect;
class SongView;

namespace songview {
class PlayheadOverlay;
}

namespace rollcheck::rendering {

bool usesNativeMacPlayheadRenderer();
QPixmap grabPlayheadOverlay(SongView &view, songview::PlayheadOverlay &marker,
                            QStringList &failures);
songview::PlayheadOverlay *findPlayheadOverlay(SongView &view);
qreal playheadCenter(const QPixmap &pixmap, const QColor &playheadColor, int minimumAlpha = 80);
bool hasPlayheadRedLine(const QImage &image, qreal devicePixelRatio, qreal logicalX,
                        const QRect &logicalArea, const QColor &playheadColor);
int playheadRedWidth(const QImage &image, qreal devicePixelRatio, qreal logicalX, int logicalY,
                     const QColor &playheadColor);
void processPaints();

} // namespace rollcheck::rendering
