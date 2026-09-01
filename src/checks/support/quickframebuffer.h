#pragma once

#include <QImage>

class QString;
class SongView;
class QWidget;

namespace checks::support {

QImage captureQuickBand(SongView &view, QWidget &band, QString *error = nullptr);

} // namespace checks::support
