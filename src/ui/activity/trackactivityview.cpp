#include "ui/activity/trackactivityview.h"

#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

#include <QAbstractListModel>
#include <QDebug>
#include <QEvent>
#include <QHash>
#include <QQmlContext>
#include <QQmlError>
#include <QUrl>
#include <QVariant>
#include <QtGlobal>

#include <algorithm>
#include <cstddef>
#include <vector>

// One row per used track. Colors resolve once per setTracks: the identity
// fill, and its dimmed form at OKLab lightness minus 0.18.
class TrackActivityView::Model final : public QAbstractListModel
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(Model)

  public:
    enum Role : int {
        RowYRole = Qt::UserRole + 1,
        MeterHeightRole,
        DimColorRole,
        ActiveColorRole,
        LeftHeightRole,
        RightHeightRole,
    };

    struct Row {
        int track = -1;
        QColor identityColor;
        QColor dimColor;
        QColor activeColor;
        track_activity_render::State state;
    };

    explicit Model(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void reset(std::span<const TrackDefinition> tracks, RowGeometry geometry,
               qreal devicePixelRatio);
    // One coalesced tick: replays the activity into every row in place and
    // emits at most one dataChanged spanning the rows whose rendered heights
    // moved. The view queries the device pixel ratio once per tick.
    void present(const TrackActivity &activity, bool playing, qreal devicePixelRatio);
    void refreshPixelSnapping(qreal devicePixelRatio);

  private:
    void emitHeightRange(int firstChanged, int lastChanged);
    qreal snappedHeight(const track_activity_render::State &state, float channelIntensity) const;

    std::vector<Row> m_rows;
    RowGeometry m_geometry = {};
    qreal m_devicePixelRatio = 1.0;
    QHash<int, QByteArray> m_roleNames;
};

TrackActivityView::Model::Model(QObject *parent) : QAbstractListModel(parent)
{
    m_roleNames.insert(RowYRole, QByteArrayLiteral("rowY"));
    m_roleNames.insert(MeterHeightRole, QByteArrayLiteral("meterHeight"));
    m_roleNames.insert(DimColorRole, QByteArrayLiteral("dimColor"));
    m_roleNames.insert(ActiveColorRole, QByteArrayLiteral("activeColor"));
    m_roleNames.insert(LeftHeightRole, QByteArrayLiteral("leftHeight"));
    m_roleNames.insert(RightHeightRole, QByteArrayLiteral("rightHeight"));
}

int TrackActivityView::Model::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return static_cast<int>(m_rows.size());
}

QVariant TrackActivityView::Model::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= static_cast<int>(m_rows.size()))
        return {};
    const Row &row = m_rows[static_cast<std::size_t>(index.row())];
    switch (role) {
    case RowYRole:
        return qreal(index.row()) * m_geometry.stride;
    case MeterHeightRole:
        return m_geometry.meterHeight;
    case DimColorRole:
        return row.dimColor;
    case ActiveColorRole:
        return row.activeColor;
    case LeftHeightRole:
        return snappedHeight(row.state, row.state.intensity.left);
    case RightHeightRole:
        return snappedHeight(row.state, row.state.intensity.right);
    }
    return {};
}

QHash<int, QByteArray> TrackActivityView::Model::roleNames() const
{
    return m_roleNames;
}

void TrackActivityView::Model::reset(std::span<const TrackDefinition> tracks, RowGeometry geometry,
                                     qreal devicePixelRatio)
{
    std::vector<Row> rows;
    rows.reserve(tracks.size());
    for (const TrackDefinition &definition : tracks) {
        auto &row = rows.emplace_back();
        row.track = definition.track;
        row.identityColor = definition.identityColor;
        const auto colors = track_activity_render::colors(definition.identityColor);
        row.dimColor = colors.dim;
        row.activeColor = colors.active;
    }

    // Identical configuration (a rebuild that kept every track and identity
    // color) keeps the live delegates — and their painted state — instead of
    // resetting the model. Painted state is per-tick data reapplied by
    // present(), so it takes no part in the comparison. The dim/active colors
    // derive from the identity color, so the identity covers the rest.
    const auto sameRow = [](const Row &a, const Row &b) {
        return a.track == b.track && a.identityColor == b.identityColor;
    };
    if (devicePixelRatio == m_devicePixelRatio && geometry == m_geometry &&
        rows.size() == m_rows.size() &&
        std::equal(rows.begin(), rows.end(), m_rows.begin(), sameRow))
        return;

    beginResetModel();
    m_geometry = geometry;
    m_devicePixelRatio = devicePixelRatio;
    m_rows = std::move(rows);
    endResetModel();
}

void TrackActivityView::Model::present(const TrackActivity &activity, bool playing,
                                       qreal devicePixelRatio)
{
    const bool resnap = m_devicePixelRatio != devicePixelRatio;
    int firstChanged = -1;
    int lastChanged = -1;
    for (std::size_t row = 0; row < m_rows.size(); ++row) {
        const track_activity_render::State next{activity.intensity(m_rows[row].track), playing};
        // The shared state equality retains unchanged rows without
        // recomputing render keys: only a state change or a density change
        // can move a rendered height.
        if (!resnap && next == m_rows[row].state)
            continue;
        const auto oldKey = track_activity_render::renderKey(
            m_rows[row].state, m_geometry.meterHeight, m_devicePixelRatio);
        const auto newKey =
            track_activity_render::renderKey(next, m_geometry.meterHeight, devicePixelRatio);
        m_rows[row].state = next;
        if (oldKey == newKey)
            continue;
        if (firstChanged < 0)
            firstChanged = static_cast<int>(row);
        lastChanged = static_cast<int>(row);
    }
    m_devicePixelRatio = devicePixelRatio;
    emitHeightRange(firstChanged, lastChanged);
}

void TrackActivityView::Model::refreshPixelSnapping(qreal devicePixelRatio)
{
    if (m_rows.empty() || m_devicePixelRatio == devicePixelRatio)
        return;
    int firstChanged = -1;
    int lastChanged = -1;
    for (std::size_t row = 0; row < m_rows.size(); ++row) {
        const auto &state = m_rows[row].state;
        const auto oldKey =
            track_activity_render::renderKey(state, m_geometry.meterHeight, m_devicePixelRatio);
        const auto newKey =
            track_activity_render::renderKey(state, m_geometry.meterHeight, devicePixelRatio);
        if (oldKey == newKey)
            continue;
        if (firstChanged < 0)
            firstChanged = static_cast<int>(row);
        lastChanged = static_cast<int>(row);
    }
    m_devicePixelRatio = devicePixelRatio;
    emitHeightRange(firstChanged, lastChanged);
}

void TrackActivityView::Model::emitHeightRange(int firstChanged, int lastChanged)
{
    if (firstChanged < 0)
        return;
    // Retained once: a braced list would allocate on every emitted tick.
    // Heights are the only roles a presented tick can affect.
    static const QList<int> kHeightRoles{LeftHeightRole, RightHeightRole};
    emit dataChanged(index(firstChanged), index(lastChanged), kHeightRoles);
}

qreal TrackActivityView::Model::snappedHeight(const track_activity_render::State &state,
                                              float channelIntensity) const
{
    // Whole device pixels expressed back in logical coordinates, so each
    // channel bar lands exactly on the raster's pixel grid.
    return track_activity_render::snappedHeight(state, channelIntensity, m_geometry.meterHeight,
                                                m_devicePixelRatio);
}

TrackActivityView::TrackActivityView(QWidget *parent)
    : QQuickWidget(parent)
    , m_model(new Model(this))
{
    setObjectName(QStringLiteral("trackActivityView"));
    setAttribute(Qt::WA_TransparentForMouseEvents);
    setAttribute(Qt::WA_OpaquePaintEvent, true);
    setFocusPolicy(Qt::NoFocus);
    setResizeMode(QQuickWidget::SizeRootObjectToView);
    setFixedWidth(layout::space(layout::Space::One));
    rootContext()->setContextProperty(QStringLiteral("trackActivityModel"), m_model);
    setClearColor(themes::color(themes::Role::song_view_separator));
    setSource(QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/TrackActivityView.qml")));
    if (status() != QQuickWidget::Ready) {
        for (const QQmlError &error : errors())
            qCritical().noquote() << error.toString();
        qFatal("Qt Quick track activity QML failed to load");
    }
    if (!rootObject())
        qFatal("Qt Quick track activity QML has no root object");
}

void TrackActivityView::setTracks(std::span<const TrackDefinition> tracks, RowGeometry geometry)
{
    // Exactly the rows' extent: below the last row the panel shows through.
    setFixedHeight(static_cast<int>(tracks.size()) * geometry.stride);
    setVisible(!tracks.empty());
    m_model->reset(tracks, geometry, devicePixelRatioF());
}

void TrackActivityView::present(const TrackActivity &activity, bool playing)
{
    // One density query per tick regardless of row count.
    m_model->present(activity, playing, devicePixelRatioF());
}

void TrackActivityView::changeEvent(QEvent *event)
{
    QQuickWidget::changeEvent(event);
    switch (event->type()) {
    case QEvent::PaletteChange:
    case QEvent::ApplicationPaletteChange:
    case QEvent::StyleChange:
    case QEvent::ThemeChange:
        setClearColor(themes::color(themes::Role::song_view_separator));
        break;
        // QEvent::DevicePixelRatioChange exists only since Qt 6.6 and the build
        // keeps a lower minimum, so earlier Qt 6 falls back to the screen-change
        // notification that accompanies every raster density change.
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
    case QEvent::DevicePixelRatioChange:
#else
    case QEvent::ScreenChangeInternal:
#endif
        m_model->refreshPixelSnapping(devicePixelRatioF());
        break;
    default:
        break;
    }
}

#include "trackactivityview.moc"
