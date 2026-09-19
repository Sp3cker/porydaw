#include "swift_roll_mount.h"

#ifdef Q_OS_MACOS

#include "grid_host.h"
#include "swift_grid_document_feed.h"
#include "ui/songview.h"
#include "ui/songview/timelinebandlayout.h"

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

    // Step 4: Explicitly push initial snapshot without waiting for edit.
    m_feed->pushSnapshot();

    m_mounted = true;
    return true;
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
