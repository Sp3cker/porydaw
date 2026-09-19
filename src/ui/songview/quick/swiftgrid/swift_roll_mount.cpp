#include "swift_roll_mount.h"

#ifdef Q_OS_MACOS

#include "grid_host.h"
#include "intent_executor.h"
#include "session_feed.h"
#include "swift_grid_document_feed.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
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

} // namespace

namespace songview {

SwiftRollMount::SwiftRollMount() = default;

SwiftRollMount::~SwiftRollMount()
{
    unmount();
}

bool SwiftRollMount::mount(SongView &songView, QQuickView &view, uint64_t bandTargetId)
{
    if (m_mounted)
        return true;
    if (bandTargetId == 0) {
        qCritical("Swift roll overlay mount failed: band target id is null");
        return false;
    }

    initSwiftGridResources();

    m_songView = &songView;
    m_view = &view;

    // Step 1: Construct feeds, then the executor over the document feed's
    // id (the swiftdocfeed harness order: feed before executor, executor
    // unregisters in its dtor, everything dies before the view).
    m_feed = std::make_unique<SwiftGridDocumentFeed>(songView.document());
    const uint64_t token = m_feed->documentId();
    const QString tokenStr = QString::number(token);
    m_sessionFeed = std::make_unique<SwiftGridSessionFeed>(songView);
    const QString sessionStr = QString::number(m_sessionFeed->sessionId());
    m_executor = std::make_unique<SwiftGridIntentExecutor>(songView, token);

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
    initialProperties.insert(QStringLiteral("bandTarget"), QString::number(bandTargetId));
    initialProperties.insert(QStringLiteral("sessionToken"), sessionStr);

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

    // Step 3: Verify component success and bound delivery slots.
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

    // The overlay binds editing (session delivery + band surface) with the
    // ids above; without it the mount is a read-only shell, not production
    // editing.
    if (!m_sessionFeed->delivery()->fn) {
        qCritical("Swift roll overlay failed to bind editing session slot");
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

    // Step 4: Explicitly push initial snapshots without waiting for edit.
    m_feed->pushSnapshot();
    m_sessionFeed->pushSnapshot();

    // Palette after data: the reloadVisuals rebuild then runs once, with real
    // notes and final colors together instead of rebuilding empty first.
    applyHostPalette();

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

    // Direct theme-role mirrors. Derived colors below reuse the same canonical
    // helpers that render the C++ Quick bands (detail::gridLineColor,
    // mixTowardOklab), so pushed values cannot drift from the oracle (S-1).
    static constexpr struct {
        const char *qmlName;
        themes::Role role;
    } kRoleColors[] = {
        {"windowBackground", themes::Role::window_background},
        {"rollBackground", themes::Role::song_view_piano_roll_background},
        {"accidentalLane", themes::Role::song_view_piano_roll_accidental_lane},
        {"chromeBackground", themes::Role::song_view_timeline_chrome_background},
        {"separator", themes::Role::song_view_separator},
        {"outline", themes::Role::palette_outline},
        {"keyboardNatural", themes::Role::song_view_piano_keyboard_natural_key},
        {"keyboardBlack", themes::Role::song_view_piano_keyboard_black_key},
        {"keyboardSeparator", themes::Role::song_view_piano_keyboard_separator},
        {"keyboardLabel", themes::Role::song_view_piano_keyboard_label},
        {"keyboardActiveKey", themes::Role::song_view_piano_keyboard_active_key},
        {"gridLine", themes::Role::song_view_grid},
        {"gridLineBar", themes::Role::song_view_grid},
        {"noteVelocityZero", themes::Role::song_view_note_velocity_zero},
        {"implicitSignature", themes::Role::song_view_note_velocity_zero},
        {"selectionRing", themes::Role::song_view_edit_preview_outline},
        {"selectionFill", themes::Role::song_view_selection_fill},
        {"selectionEdge", themes::Role::song_view_selection_edge},
        {"primaryText", themes::Role::song_view_primary_text},
        {"windowText", themes::Role::window_text},
        {"secondaryText", themes::Role::song_view_secondary_text},
        {"editCursor", themes::Role::song_view_edit_cursor},
        {"playhead", themes::Role::song_view_playhead},
    };
    for (const auto &entry : kRoleColors)
        palette->setProperty(entry.qmlName, hexColor(entry.role));

    const QColor roll = themes::color(themes::Role::song_view_piano_roll_background);
    const QColor chrome = themes::color(themes::Role::song_view_timeline_chrome_background);
    const QColor activeKey = themes::color(themes::Role::song_view_piano_keyboard_active_key);

    palette->setProperty("gridLineSub1", hexColor(detail::gridLineColor(125)));
    palette->setProperty("gridLineSub2", hexColor(detail::gridLineColor(100)));
    palette->setProperty("gridLineSub3", hexColor(detail::gridLineColor(75)));
    palette->setProperty("gridLineBeat", hexColor(detail::gridLineColor(160)));
    palette->setProperty("gridLineBeatFine", hexColor(detail::gridLineColor(200)));
    palette->setProperty("rowLine", hexColor(detail::gridLineColor(50)));
    palette->setProperty("preRollMask",
                         hexColor(mixTowardOklab(roll, detail::gridLineColor(), 0.15)));
    palette->setProperty("rulerPreRollMask",
                         hexColor(mixTowardOklab(chrome, detail::gridLineColor(), 0.15)));

    QColor keyboardHover = activeKey;
    keyboardHover.setAlpha(80);
    palette->setProperty("keyboardHover", hexColor(keyboardHover));

    // rulerDetailText, noteBorder, hoverChipFill, and hoverChipText are
    // deliberately not pushed: GridPalette ports the oracle derivations (the
    // ruler recede blend, hover/note chrome), and no ruler or hover chip
    // renders through this host contract yet.

    QMetaObject::invokeMethod(grid, "reloadVisuals");
}

void SwiftRollMount::unmount()
{
    // Step 5: Disconnect observers and unregister/destroy executor + feeds
    // BEFORE deleting the overlay. Executor first (its slot borrows the
    // document id the feeds own), then the session and document feeds whose
    // slots point at Swift — only then is deleting the Swift grid safe.
    if (m_trackConnection) {
        QObject::disconnect(m_trackConnection);
        m_trackConnection = {};
    }

    m_executor.reset();
    m_sessionFeed.reset();
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

    m_executor.reset();
    m_sessionFeed.reset();
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
bool SwiftRollMount::mount(SongView &, QQuickView &, uint64_t)
{
    return false;
}
void SwiftRollMount::unmount() {}
void SwiftRollMount::updateBandGeometry(const std::optional<TimelineBandGeometry> &) {}
void SwiftRollMount::handleTransferredWindowDeath() {}
void SwiftRollMount::applyHostPalette() {}
} // namespace songview

#endif
