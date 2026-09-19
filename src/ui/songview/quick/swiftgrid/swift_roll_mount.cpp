#include "swift_roll_mount.h"

#ifdef Q_OS_MACOS

#include "grid_host.h"
#include "swift_grid_document_feed.h"
#include "ui/songview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/theme/themeruntime.h"

#include <QColor>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QUrl>
#include <QVariantMap>

// Resource basename swift_grid_qml initialized at global namespace per R2.
static void initSwiftGridResources()
{
    Q_INIT_RESOURCE(swift_grid_qml);
}

namespace {

QString hexColor(const QColor &color)
{
    return color.name(QColor::HexArgb);
}

QString hexColor(themes::Role role)
{
    return hexColor(themes::color(role));
}

QString hexColorWithAlpha(const QColor &color, int alpha)
{
    QColor withAlpha = color;
    withAlpha.setAlpha(alpha);
    return withAlpha.name(QColor::HexArgb);
}

QString mixTowardBlack(const QColor &color, qreal t)
{
    QColor mixed = color;
    mixed.setRedF(color.redF() * (1.0 - t));
    mixed.setGreenF(color.greenF() * (1.0 - t));
    mixed.setBlueF(color.blueF() * (1.0 - t));
    return mixed.name(QColor::HexArgb);
}

} // namespace

namespace songview {

SwiftRollMount::SwiftRollMount() = default;

SwiftRollMount::~SwiftRollMount()
{
    unmount();
}

bool SwiftRollMount::mount(SongView &songView, QQuickView &view)
{
    if (m_mounted)
        return true;

    initSwiftGridResources();

    m_songView = &songView;
    m_view = &view;

    // Step 1: Construct feed, mint token and register its empty endpoint.
    m_feed = std::make_unique<SwiftGridDocumentFeed>(songView.document());
    const uint64_t token = m_feed->documentId();
    const QString tokenStr = QString::number(token);

    // Step 2: Register grid types and create QML component.
    sg_register_grid_types();

    QQmlEngine *engine = view.engine();
    if (!engine) {
        qCritical("Swift roll overlay mount failed: view engine is null");
        unmount();
        return false;
    }

    QQmlComponent component(engine, QUrl(QStringLiteral("qrc:/swiftgrid/SwiftRollOverlay.qml")));
    if (component.isError()) {
        for (const QQmlError &err : component.errors())
            qCritical().noquote() << "Swift roll overlay component error:" << err.toString();
        unmount();
        return false;
    }

    const int initialTrack = songView.selectionModel().primaryTrack();
    QVariantMap initialProperties;
    initialProperties.insert(QStringLiteral("documentToken"), tokenStr);
    initialProperties.insert(QStringLiteral("selectedTrack"), initialTrack);

    QObject *object = component.createWithInitialProperties(initialProperties);
    if (!object) {
        qCritical("Swift roll overlay component creation failed");
        for (const QQmlError &err : component.errors())
            qCritical().noquote() << "Swift roll overlay component error:" << err.toString();
        unmount();
        return false;
    }

    QQuickItem *const contentItem = view.contentItem();
    if (!contentItem) {
        qCritical("Swift roll overlay mount failed: view contentItem is null");
        delete object;
        unmount();
        return false;
    }

    object->setParent(contentItem);

    // Step 3: Verify component success and a bound delivery slot.
    m_overlayItem = qobject_cast<QQuickItem *>(object);
    if (!m_overlayItem) {
        qCritical("Swift roll overlay root object is not a QQuickItem");
        delete object;
        unmount();
        return false;
    }

    if (!m_feed->delivery()->fn) {
        qCritical("Swift roll overlay failed to bind document delivery slot");
        unmount();
        return false;
    }

    m_overlayItem->setParentItem(contentItem);
    m_overlayItem->setZ(100.0);
    m_overlayItem->setFocus(false);
    m_trackConnection =
        QObject::connect(&songView, &SongView::selectedTrackChanged, m_overlayItem.data(),
                         [overlay = m_overlayItem](int track) {
                             if (overlay) {
                                 overlay->setProperty("selectedTrack", track);
                             }
                         });
    applyHostPalette();

    // Step 4: Explicitly push initial snapshot without waiting for edit.
    m_feed->pushSnapshot();

    m_mounted = true;
    return true;
}

void SwiftRollMount::applyHostPalette()
{
    if (!m_overlayItem)
        return;

    QObject *const grid = m_overlayItem->findChild<QObject *>(QStringLiteral("swiftGridModel"));
    if (!grid)
        return;
    QObject *const palette = grid->property("palette").value<QObject *>();
    if (!palette)
        return;

    const QColor roll = themes::color(themes::Role::song_view_piano_roll_background);
    const QColor chrome = themes::color(themes::Role::song_view_timeline_chrome_background);
    const QColor gridLine = themes::color(themes::Role::song_view_grid);
    const QColor activeKey = themes::color(themes::Role::song_view_piano_keyboard_active_key);
    const int gridAlpha = gridLine.alpha();

    palette->setProperty("windowBackground", hexColor(themes::Role::window_background));
    palette->setProperty("rollBackground", hexColor(roll));
    palette->setProperty("accidentalLane",
                         hexColor(themes::Role::song_view_piano_roll_accidental_lane));
    palette->setProperty("chromeBackground", hexColor(chrome));
    palette->setProperty("separator", hexColor(themes::Role::song_view_separator));
    palette->setProperty("outline", hexColor(themes::Role::palette_outline));
    palette->setProperty("keyboardNatural",
                         hexColor(themes::Role::song_view_piano_keyboard_natural_key));
    palette->setProperty("keyboardBlack",
                         hexColor(themes::Role::song_view_piano_keyboard_black_key));
    palette->setProperty("keyboardSeparator",
                         hexColor(themes::Role::song_view_piano_keyboard_separator));
    palette->setProperty("keyboardLabel", hexColor(themes::Role::song_view_piano_keyboard_label));
    palette->setProperty("keyboardActiveKey", hexColor(activeKey));
    palette->setProperty("keyboardHover", hexColorWithAlpha(activeKey, 80));
    palette->setProperty("gridLine", hexColor(gridLine));
    palette->setProperty("gridLineSub1", hexColorWithAlpha(gridLine, gridAlpha * 125 / 255));
    palette->setProperty("gridLineSub2", hexColorWithAlpha(gridLine, gridAlpha * 100 / 255));
    palette->setProperty("gridLineSub3", hexColorWithAlpha(gridLine, gridAlpha * 75 / 255));
    palette->setProperty("gridLineBeat", hexColorWithAlpha(gridLine, gridAlpha * 160 / 255));
    palette->setProperty("gridLineBeatFine", hexColorWithAlpha(gridLine, gridAlpha * 200 / 255));
    palette->setProperty("gridLineBar", hexColor(gridLine));
    palette->setProperty("rowLine", hexColorWithAlpha(gridLine, gridAlpha * 50 / 255));
    palette->setProperty("preRollMask", mixTowardBlack(roll, 0.15));
    palette->setProperty("rulerPreRollMask", mixTowardBlack(chrome, 0.15));
    palette->setProperty("noteVelocityZero", hexColor(themes::Role::song_view_note_velocity_zero));
    palette->setProperty("selectionRing", hexColor(themes::Role::song_view_edit_preview_outline));
    palette->setProperty("selectionFill", hexColor(themes::Role::song_view_selection_fill));
    palette->setProperty("selectionEdge", hexColor(themes::Role::song_view_selection_edge));
    palette->setProperty("primaryText", hexColor(themes::Role::song_view_primary_text));
    palette->setProperty("windowText", hexColor(themes::Role::window_text));
    palette->setProperty("secondaryText", hexColor(themes::Role::song_view_secondary_text));
    palette->setProperty("editCursor", hexColor(themes::Role::song_view_edit_cursor));
    palette->setProperty("playhead", hexColor(themes::Role::song_view_playhead));
    palette->setProperty("implicitSignature", hexColor(themes::Role::song_view_note_velocity_zero));
    palette->setProperty("rulerDetailText", hexColor(themes::Role::song_view_secondary_text));

    QMetaObject::invokeMethod(grid, "reloadVisuals");
}

void SwiftRollMount::unmount()
{
    // Step 5: Disconnect observers and unregister/destroy feed BEFORE deleting overlay.
    if (m_trackConnection) {
        QObject::disconnect(m_trackConnection);
        m_trackConnection = {};
    }

    m_feed.reset();

    if (m_overlayItem) {
        delete m_overlayItem.data();
        m_overlayItem.clear();
    }

    m_songView.clear();
    m_view.clear();
    m_mounted = false;
}

void SwiftRollMount::updateBandGeometry(const std::optional<TimelineBandGeometry> &rollGeometry)
{
    if (!m_overlayItem)
        return;

    if (!rollGeometry.has_value()) {
        m_overlayItem->setVisible(false);
        return;
    }

    const QRect rect = rollGeometry->rect;
    m_overlayItem->setX(rect.x());
    m_overlayItem->setY(rect.y());
    m_overlayItem->setWidth(rect.width());
    m_overlayItem->setHeight(rect.height());
    m_overlayItem->setVisible(true);
}

void SwiftRollMount::handleTransferredWindowDeath()
{
    if (m_trackConnection) {
        QObject::disconnect(m_trackConnection);
        m_trackConnection = {};
    }

    m_feed.reset();
    m_overlayItem.clear();
    m_songView.clear();
    m_view.clear();
    m_mounted = false;
}

} // namespace songview

#else // !Q_OS_MACOS

namespace songview {
SwiftRollMount::SwiftRollMount() = default;
SwiftRollMount::~SwiftRollMount() = default;
bool SwiftRollMount::mount(SongView &, QQuickView &)
{
    return false;
}
void SwiftRollMount::unmount() {}
void SwiftRollMount::updateBandGeometry(const std::optional<TimelineBandGeometry> &) {}
void SwiftRollMount::handleTransferredWindowDeath() {}
} // namespace songview

#endif
