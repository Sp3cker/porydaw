#include "ui/activity/trackactivitypresentation_p.h"

#include "ui/activity/trackactivityrender.h"
#include "ui/layout.h"
#include "ui/nativelayerutils_macos_p.h"
#include "ui/theme/themeruntime.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <QPoint>
#include <QRect>
#include <QWidget>

#include <algorithm>
#include <array>
#include <memory>
#include <utility>
#include <vector>

#if __has_feature(objc_arc)
#error trackactivityrenderer_macos.mm must be compiled without ARC
#endif

namespace track_activity_detail {
namespace {

using native_layer::DisabledActionTransaction;
using native_layer::RetainedCoreFoundation;
using native_layer::RetainedObject;
using native_layer::setLayerRect;

void setLayerColor(CALayer *layer, const QColor &color)
{
    auto nativeColor = RetainedCoreFoundation<CGColor>{
        CGColorCreateSRGB(color.redF(), color.greenF(), color.blueF(), color.alphaF())};
    layer.backgroundColor = nativeColor.get();
}

struct RowLayers {
    explicit RowLayers(int sourceTrack, QColor sourceColor)
        : track(sourceTrack)
        , identityColor(std::move(sourceColor))
        , background([CALayer new])
        , left([CALayer new])
        , right([CALayer new])
    {}

    RowLayers(const RowLayers &) = delete;
    RowLayers &operator=(const RowLayers &) = delete;
    RowLayers(RowLayers &&) noexcept = default;
    RowLayers &operator=(RowLayers &&) noexcept = default;

    int track;
    QColor identityColor;
    RetainedObject<CALayer> background;
    RetainedObject<CALayer> left;
    RetainedObject<CALayer> right;
    track_activity_render::RenderKey renderKey{-1, -1, false};
};

class MacBackend final : public Backend
{
  public:
    explicit MacBackend(QWidget &owner)
        : m_owner(owner)
        , m_rootLayer([CALayer new])
        , m_clipMask([CAShapeLayer new])
    {
        DisabledActionTransaction transaction;
        m_rootLayer.get().name = @"PorydawTrackActivityLayer";
        m_rootLayer.get().anchorPoint = CGPointZero;
        m_rootLayer.get().geometryFlipped = NO;
        m_rootLayer.get().hidden = YES;
        m_clipMask.get().anchorPoint = CGPointZero;
        auto maskColor = RetainedCoreFoundation<CGColor>{CGColorCreateSRGB(1.0, 1.0, 1.0, 1.0)};
        m_clipMask.get().fillColor = maskColor.get();
        m_rootLayer.get().mask = m_clipMask.get();
    }

    ~MacBackend() override
    {
        DisabledActionTransaction transaction;
        [m_rootLayer.get() removeFromSuperlayer];
    }

    void setTracks(std::span<const TrackActivityPresentation::TrackDefinition> tracks,
                   track_activity_render::RowGeometry geometry) override
    {
        Q_ASSERT(geometry.stride > 0);
        Q_ASSERT(geometry.meterHeight > 0 && geometry.meterHeight <= geometry.stride);
        Q_ASSERT(tracks.size() <= kMaxTracks);
        DisabledActionTransaction transaction;
        for (auto &row : m_rows)
            [row.background.get() removeFromSuperlayer];
        m_rows.clear();
        m_rows.reserve(std::min(tracks.size(), kMaxTracks));
        for (auto index = std::size_t{0}; index < std::min(tracks.size(), kMaxTracks); ++index) {
            const auto &definition = tracks[index];
            auto &row = m_rows.emplace_back(definition.track, definition.identityColor);
            const std::array<CALayer *, 3> layers = {row.background.get(), row.left.get(),
                                                     row.right.get()};
            for (CALayer *layer : layers) {
                layer.anchorPoint = CGPointZero;
                layer.contentsScale = m_devicePixelRatio;
            }
            row.background.get().name = @"PorydawTrackActivityRow";
            row.background.get().masksToBounds = YES;
            row.left.get().name = @"PorydawTrackActivityLeft";
            row.right.get().name = @"PorydawTrackActivityRight";
            [row.background.get() addSublayer:row.left.get()];
            [row.background.get() addSublayer:row.right.get()];
            [m_rootLayer.get() addSublayer:row.background.get()];
        }
        m_geometry = geometry;
        synchronizeWithinTransaction(true);
    }

    void present(const TrackActivity &activity, bool playing) override
    {
        m_activity = activity;
        m_playing = playing;
        const qreal devicePixelRatio = std::max<qreal>(m_owner.devicePixelRatioF(), 1.0);
        if (m_devicePixelRatio != devicePixelRatio) {
            synchronize();
            return;
        }
        DisabledActionTransaction transaction;
        applyRows(false);
    }

    void synchronize() override
    {
        DisabledActionTransaction transaction;
        synchronizeWithinTransaction(true);
    }

  private:
    int stripWidth() const { return layout::space(layout::Space::One); }
    int stripHeight() const { return static_cast<int>(m_rows.size()) * m_geometry.stride; }

    QRect stripGeometry(QWidget &topLevel) const
    {
        return {m_owner.mapTo(&topLevel, QPoint(0, 0)), QSize(stripWidth(), stripHeight())};
    }

    QRect visibleStripRect(QWidget &topLevel, const QRect &strip) const
    {
        if (m_rows.empty() || !m_owner.isVisibleTo(&topLevel))
            return {};
        auto visible = strip;
        for (const QWidget *widget = &m_owner; widget; widget = widget->parentWidget()) {
            if (!widget->isVisible())
                return {};
            visible &= QRect(widget->mapTo(&topLevel, QPoint(0, 0)), widget->size());
            if (widget == &topLevel)
                break;
        }
        return visible;
    }

    void attachToNativeView()
    {
        QWidget *const topLevel = m_owner.window();
        WId topLevelWId = topLevel ? topLevel->internalWinId() : 0;
        if (topLevelWId == 0 && topLevel && topLevel->isVisible())
            topLevelWId = topLevel->winId();
        auto *ownerView = topLevelWId ? reinterpret_cast<NSView *>(topLevelWId) : nullptr;
        if (ownerView == m_attachedView &&
            (!ownerView || m_rootLayer.get().superlayer == ownerView.layer)) {
            return;
        }
        [m_rootLayer.get() removeFromSuperlayer];
        m_attachedView = nullptr;
        if (ownerView) {
            [ownerView.layer addSublayer:m_rootLayer.get()];
            m_attachedView = ownerView;
        }
    }

    void updateColors()
    {
        setLayerColor(m_rootLayer.get(), themes::color(themes::Role::song_view_separator));
        for (auto &row : m_rows) {
            const auto colors = track_activity_render::colors(row.identityColor);
            setLayerColor(row.background.get(), colors.dim);
            setLayerColor(row.left.get(), colors.active);
            setLayerColor(row.right.get(), colors.active);
        }
    }

    void applyRows(bool force)
    {
        const qreal halfWidth = qreal(stripWidth()) * 0.5;
        for (auto &row : m_rows) {
            const track_activity_render::State state{m_activity.intensity(row.track), m_playing,
                                                     1.0f};
            const auto key =
                track_activity_render::renderKey(state, m_geometry.meterHeight, m_devicePixelRatio);
            if (!force && row.renderKey == key)
                continue;
            row.renderKey = key;
            const qreal leftHeight = track_activity_render::snappedHeight(
                state, state.intensity.left, m_geometry.meterHeight, m_devicePixelRatio);
            const qreal rightHeight = track_activity_render::snappedHeight(
                state, state.intensity.right, m_geometry.meterHeight, m_devicePixelRatio);
            setLayerRect(row.left.get(), CGRectMake(0.0, m_geometry.meterHeight - leftHeight,
                                                    halfWidth, leftHeight));
            setLayerRect(row.right.get(),
                         CGRectMake(halfWidth, m_geometry.meterHeight - rightHeight, halfWidth,
                                    rightHeight));
        }
    }

    void synchronizeWithinTransaction(bool forceRows)
    {
        attachToNativeView();
        if (m_attachedView && m_rootLayer.get() != m_attachedView.layer.sublayers.lastObject) {
            [m_attachedView.layer addSublayer:m_rootLayer.get()];
        }
        m_devicePixelRatio = std::max<qreal>(m_owner.devicePixelRatioF(), 1.0);
        QWidget *const topLevel = m_owner.window();
        const QRect rootGeometry = topLevel ? stripGeometry(*topLevel) : QRect{};
        const QRect visible = topLevel ? visibleStripRect(*topLevel, rootGeometry) : QRect{};
        const auto rootRect = CGRectMake(rootGeometry.x(), rootGeometry.y(), rootGeometry.width(),
                                         rootGeometry.height());
        const auto rootBounds = CGRectMake(0.0, 0.0, rootGeometry.width(), rootGeometry.height());
        setLayerRect(m_rootLayer.get(), rootRect);
        setLayerRect(m_clipMask.get(), rootBounds);
        auto clipPath = RetainedCoreFoundation<CGPath>{CGPathCreateMutable()};
        if (!visible.isEmpty()) {
            const QRect relative = visible.translated(-rootGeometry.topLeft());
            CGPathAddRect(
                clipPath.get(), nullptr,
                CGRectMake(relative.x(), relative.y(), relative.width(), relative.height()));
        }
        m_clipMask.get().path = clipPath.get();
        m_rootLayer.get().contentsScale = m_devicePixelRatio;
        m_clipMask.get().contentsScale = m_devicePixelRatio;
        updateColors();
        for (auto index = std::size_t{0}; index < m_rows.size(); ++index) {
            auto &row = m_rows[index];
            row.background.get().contentsScale = m_devicePixelRatio;
            row.left.get().contentsScale = m_devicePixelRatio;
            row.right.get().contentsScale = m_devicePixelRatio;
            setLayerRect(row.background.get(), CGRectMake(0.0, qreal(index) * m_geometry.stride,
                                                          stripWidth(), m_geometry.meterHeight));
        }
        applyRows(forceRows);
        m_rootLayer.get().hidden = !m_attachedView || m_rows.empty() || visible.isEmpty();
    }

    QWidget &m_owner;
    NSView *m_attachedView = nullptr;
    RetainedObject<CALayer> m_rootLayer;
    RetainedObject<CAShapeLayer> m_clipMask;
    std::vector<RowLayers> m_rows;
    track_activity_render::RowGeometry m_geometry{};
    TrackActivity m_activity;
    bool m_playing = false;
    qreal m_devicePixelRatio = 1.0;
};

} // namespace

std::unique_ptr<Backend> makeMacBackend(QWidget &owner)
{
    return std::make_unique<MacBackend>(owner);
}

} // namespace track_activity_detail
