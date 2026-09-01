#pragma once

#include <QImage>

class QRect;
class QString;
class SongView;
class QWidget;

namespace checks::support {

QImage captureQuickBand(SongView &view, const QRect &rectInSongView, QString *error = nullptr);
QImage captureQuickBand(SongView &view, QWidget &band, QString *error = nullptr);

} // namespace checks::support
