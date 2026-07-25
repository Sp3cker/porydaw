#include "playheadoverlay.h"
#include "theme/themeruntime.h"

#include <QEvent>

namespace songview {

PlayheadOverlay::PlayheadOverlay(QWidget &owner, const Surfaces &surfaces)
    : QWidget(&owner), m_surfaces(surfaces), m_renderer(*this) {

  setAttribute(Qt::WA_TransparentForMouseEvents);
  setAttribute(Qt::WA_NoSystemBackground);

  // The filter chain is captured once, here: each surface's ancestors up
  // to the owner as they stand at construction. Reparenting a surface
  // afterwards would leave the new ancestors unwatched and geometry sync
  // silently stale — SongView must finish building its hierarchy before
  // creating the overlay.
  const auto observeSurfaceGeometry = [this, &owner](QWidget &surface) {
    for (QWidget *widget = &surface; widget; widget = widget->parentWidget()) {
      widget->installEventFilter(this);
      if (widget == &owner)
        break;
    }
  };
  observeSurfaceGeometry(m_surfaces.ruler);
  observeSurfaceGeometry(m_surfaces.roll);
  observeSurfaceGeometry(m_surfaces.lanes);
  observeSurfaceGeometry(m_surfaces.strip);

  synchronizeGeometry();
  show();
}

PlayheadOverlay::~PlayheadOverlay() = default;

void PlayheadOverlay::setPlayhead(qreal timelineX, bool visible, bool playing) {
  if (m_timelineX == timelineX && m_visible == visible && m_playing == playing)
    return;

  m_timelineX = timelineX;
  m_visible = visible;
  m_playing = playing;
  updatePresentation();
}

bool PlayheadOverlay::eventFilter(QObject *, QEvent *event) {
  switch (event->type()) {
  case QEvent::Show:
  case QEvent::Hide:
  case QEvent::Move:
  case QEvent::Resize:
  case QEvent::LayoutRequest:
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
  case QEvent::DevicePixelRatioChange:
#else
  case QEvent::ScreenChangeInternal:
#endif
    synchronizeGeometry();
    break;
  default:
    break;
  }
  return false;
}

void PlayheadOverlay::changeEvent(QEvent *event) {
  QWidget::changeEvent(event);
  switch (event->type()) {
  case QEvent::ApplicationPaletteChange:
  case QEvent::PaletteChange:
  case QEvent::StyleChange:
  case QEvent::FontChange:
    updatePresentation();
    break;
  default:
    break;
  }
}

void PlayheadOverlay::paintEvent(QPaintEvent *event) {
  m_renderer.paint(event);
}

QRect PlayheadOverlay::visibleSurfaceRect(const QWidget &surface,
                                          QWidget &owner, int origin) const {
  if (origin >= surface.width())
    return {};
  QPoint offset = surface.mapTo(&owner, QPoint(0, 0));
  QRect visible(offset + QPoint(origin, 0),
                QSize(surface.width() - origin, surface.height()));
  for (const QWidget *widget = &surface; widget;
       widget = widget->parentWidget()) {
    if (!widget->isVisible())
      return {};

    visible &= QRect(widget->mapTo(&owner, QPoint(0, 0)), widget->size());
    if (widget == &owner)
      break;
  }
  return visible;
}

void PlayheadOverlay::synchronizeGeometry() {
  QWidget *ownerWidget = parentWidget();
  Q_ASSERT(ownerWidget);
  QWidget &owner = *ownerWidget;

  const QRect rulerGeometry(m_surfaces.ruler.mapTo(&owner, QPoint(0, 0)),
                            m_surfaces.ruler.size());
  const int playheadTop = rulerGeometry.bottom() + 1;
  const QRect playheadGeometry(0, playheadTop, owner.width(),
                               owner.height() - playheadTop);
  const QRect rulerVisible =
      visibleSurfaceRect(m_surfaces.ruler, owner, m_surfaces.rulerOrigin);
  const QRect triangleClip(rulerVisible.left(), playheadTop,
                           rulerVisible.width(), kPlayheadTriangleHeight + 1);

  const QRegion visibleSurfaces =
      QRegion(
          visibleSurfaceRect(m_surfaces.roll, owner, m_surfaces.rollOrigin)) +
      visibleSurfaceRect(m_surfaces.lanes, owner, m_surfaces.lanesOrigin) +
      visibleSurfaceRect(m_surfaces.strip, owner, m_surfaces.stripOrigin);

  const int timelineOrigin =
      m_surfaces.ruler.mapTo(&owner, QPoint(m_surfaces.rulerOrigin, 0)).x();

  const bool overlayGeometryChanged = geometry() != owner.rect();
  if (overlayGeometryChanged)
    setGeometry(owner.rect());

  m_visibleSurfaceRegion = visibleSurfaces;
  m_playheadGeometry = playheadGeometry;
  m_triangleClip = triangleClip;
  m_timelineOrigin = timelineOrigin;

  updatePresentation();
  raise();
}

void PlayheadOverlay::updatePresentation() {
  QWidget *ownerWidget = parentWidget();
  Q_ASSERT(ownerWidget);
  QWidget &owner = *ownerWidget;

  PlayheadPresentation presentation;
  presentation.layout.overlayFrame = geometry();
  presentation.layout.visibleSurfaceRegion = m_visibleSurfaceRegion;
  presentation.layout.playheadGeometry = m_playheadGeometry;
  presentation.layout.triangleClip = m_triangleClip;
  presentation.layout.trianglePointsUp = !m_surfaces.roll.isVisible();
  presentation.layout.contentsScale = owner.devicePixelRatioF();
  presentation.appearance.themeColor =
      themes::color(themes::Role::song_view_playhead);
  presentation.appearance.playing = m_playing;
  presentation.state.finalX =
      static_cast<qreal>(m_timelineOrigin) + m_timelineX;
  presentation.state.visible = m_visible;

  m_renderer.synchronize(presentation);
}

} // namespace songview
