#include "ui/activity/trackactivitypresentation.h"

#include "ui/activity/trackactivitypresentation_p.h"
#include "ui/activity/trackactivityview.h"

#include <QEvent>
#include <QGuiApplication>
#include <QWidget>

#include <vector>

namespace {

std::unique_ptr<track_activity_detail::Backend> makeBackend(QWidget &owner)
{
#ifdef Q_OS_MACOS
    if (QGuiApplication::platformName() == QLatin1String("cocoa") &&
        !qEnvironmentVariableIsSet("PORYDAW_FORCE_QUICK_TRACK_ACTIVITY")) {
        if (auto backend = track_activity_detail::makeMacBackend(owner))
            return backend;
    }
#endif
    return track_activity_detail::makeQuickBackend(owner);
}

} // namespace

namespace track_activity_detail {

namespace {

class QuickBackend final : public Backend
{
  public:
    explicit QuickBackend(QWidget &owner) : m_view(std::make_unique<TrackActivityView>(&owner)) {}

    void setTracks(std::span<const TrackActivityPresentation::TrackDefinition> tracks,
                   track_activity_render::RowGeometry geometry) override
    {
        Q_ASSERT(tracks.size() <= kMaxTracks);
        std::vector<TrackActivityView::TrackDefinition> definitions;
        definitions.reserve(tracks.size());
        for (const auto &definition : tracks)
            definitions.push_back({definition.track, definition.identityColor});
        m_view->move(0, 0);
        m_view->setTracks(definitions, geometry);
        m_view->raise();
    }

    void present(const TrackActivity &activity, bool playing) override
    {
        m_view->present(activity, playing);
    }

    void synchronize() override {}

  private:
    std::unique_ptr<TrackActivityView> m_view;
};

} // namespace

std::unique_ptr<Backend> makeQuickBackend(QWidget &owner)
{
    return std::make_unique<QuickBackend>(owner);
}

} // namespace track_activity_detail

TrackActivityPresentation::TrackActivityPresentation(QWidget &owner)
    : m_owner(owner)
    , m_backend(makeBackend(owner))
{
    observeOwnerGeometry();
    m_backend->synchronize();
}

TrackActivityPresentation::~TrackActivityPresentation()
{
    removeObservedChainFilters();
}

void TrackActivityPresentation::setTracks(std::span<const TrackDefinition> tracks,
                                          track_activity_render::RowGeometry geometry)
{
    m_backend->setTracks(tracks, geometry);
    // Definitions and geometry changed; redraw with the state cached here so
    // the owner never has to re-present after a reconfiguration.
    m_backend->present(m_activity, m_playing);
}

void TrackActivityPresentation::present(const TrackActivity &activity, bool playing)
{
    m_activity = activity;
    m_playing = playing;
    m_backend->present(activity, playing);
}

void TrackActivityPresentation::removeObservedChainFilters()
{
    for (const QPointer<QWidget> &widget : m_observedChain) {
        if (widget)
            widget->removeEventFilter(this);
    }
    m_observedChain.clear();
}

void TrackActivityPresentation::observeOwnerGeometry()
{
    // Ancestor widgets can be destroyed or reparented at any time, so the
    // chain holds non-owning QPointers and is rebuilt from scratch: drop every
    // previously installed filter before installing the current chain.
    removeObservedChainFilters();
    QWidget *const topLevel = m_owner.window();
    for (QWidget *widget = &m_owner; widget; widget = widget->parentWidget()) {
        widget->installEventFilter(this);
        m_observedChain.push_back(widget);
        if (widget == topLevel)
            break;
    }
}

bool TrackActivityPresentation::eventFilter(QObject *, QEvent *event)
{
    switch (event->type()) {
    case QEvent::ParentChange:
        observeOwnerGeometry();
        [[fallthrough]];
    case QEvent::Show:
    case QEvent::Hide:
    case QEvent::Move:
    case QEvent::Resize:
    case QEvent::LayoutRequest:
    case QEvent::WinIdChange:
    case QEvent::PaletteChange:
    case QEvent::ApplicationPaletteChange:
    case QEvent::StyleChange:
    case QEvent::ThemeChange:
        // QEvent::DevicePixelRatioChange was added in Qt 6.6 and the build
        // declares no higher Qt minimum, so earlier Qt 6 releases fall back
        // to the internal screen-change event.
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
    case QEvent::DevicePixelRatioChange:
#else
    case QEvent::ScreenChangeInternal:
#endif
        m_backend->synchronize();
        break;
    default:
        break;
    }
    return false;
}
