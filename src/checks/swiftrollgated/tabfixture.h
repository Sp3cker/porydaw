#pragma once

#include "app/RewriteWindow.h"

#include <QByteArray>
#include <QColor>
#include <QImage>
#include <QList>
#include <QObject>
#include <QPoint>
#include <QRectF>
#include <QString>

#include <optional>

class QAbstractItemModel;
class QQuickItem;
class QQuickView;

/// The song tab strip as the gate drives it: the production window, the one
/// QQuickView it mounts the surface in, the strip items the object names name,
/// and the model and sessions behind them.
///
/// The scenarios own the contract; this unit owns the plumbing that reaches it:
/// object-name lookup through the window's content item (the close gate's dialog
/// is a popup parented to the window's overlay, not to the mounted root),
/// pointer input on the strip controls, real grid edits through the session, and
/// the raster and file comparisons the scenarios assert on.
namespace tabcheck {

constexpr int kOpenTimeoutMs = 15'000;
constexpr int kSettleTimeoutMs = 5'000;
// The narrowest window the strip scenario tries: four song tabs overflow far
// above this floor, so narrowing always ends in an overflowing strip.
constexpr int kMinWindowWidth = 320;
constexpr int kCloseExtent = 20;
// One pointer press/release pair settles a strip button before the next state
// read; the strip republishes selection through QML property changes.
constexpr int kInputSettleMs = 30;

// The staged project ships four playable songs whose voicegroup (`_fixture_rich`)
// is part of this check's fixture, so the tab scenarios open real second, third
// and fourth documents (see checkcatalog.cpp's swiftrollgated entry).
constexpr auto kSecondSong = "mus_littleroot_test";
constexpr auto kThirdSong = "mus_route102";
constexpr auto kFourthSong = "mus_gym";

/// One published grid note, the shape the roll's noteSummary carries.
struct TabNote {
    quint64 id = 0;
    int tick = 0;
    int duration = 0;
    int pitch = 0;
    int track = 0;
    int velocity = 0;
    bool selected = false;
};

/// The strip's production box metrics, keyed by the resolved tab-label font.
/// SongTabs.qml sizes the strip from the application font and the measured body
/// line spacing (layout.cpp spacing plus Fusion's fixed style metrics); the
/// prototype branch captured the three boxes the platform font scales resolve
/// to. `Application.font` is typography's base pixel size scaled by 1.125, so
/// the 12/13/16 base sizes land on labels of 14/15/18 pixels, and the harness
/// desktop resolves the 15-pixel row.
struct TabMetrics {
    int labelFontPx;
    int stripHeight;
    int tabHeight;
};

const TabMetrics *tabMetricsFor(int labelFontPx);

QRectF sceneRectOf(QQuickItem *item);
int changedPixels(const QImage &before, const QImage &after, const QRectF &logicalRegion);
int matchingColorCount(const QImage &image, const QRectF &logicalRegion, const QColor &expected);
/// Device pixels inside `logicalRegion` that are not `expected`. Used for the
/// empty strip's blank page: with no tab mounted the page stack shows nothing
/// but the window's own roll background.
int pixelsDifferingFrom(const QImage &image, const QRectF &logicalRegion, const QColor &expected);

/// The tab button's caption text item, the item the strip lays out its label in.
QQuickItem *captionOf(QQuickItem *button);
QString songPath(const QString &projectRoot, const QString &label);
QByteArray songBytes(const QString &path);
bool writeSongBytes(const QString &path, const QByteArray &bytes);

class TabScene
{
  public:
    bool open(const QString &projectRoot, const QString &songLabel, QString *error);
    RewriteWindow m_window;
    QQuickView *m_view = nullptr;
    QQuickItem *m_content = nullptr;
    QQuickItem *m_root = nullptr;
    QObject *m_session = nullptr;
    QObject *m_controller = nullptr;
    QAbstractItemModel *m_tabs = nullptr;
    QQuickItem *item(const QString &name) const;
    QQuickItem *strip() const;
    QQuickItem *pages() const;
    QQuickItem *page(int tabId) const;
    QQuickItem *pageItem(int tabId, const QString &name) const;
    QQuickItem *selectButton(int tabId) const;
    QQuickItem *closeButton(int tabId) const;
    QQuickItem *scrollLeft() const;
    QQuickItem *scrollRight() const;
    /// The page's own surface item: the `EditorSurface` the tab mounts.
    QQuickItem *pageSurface(int tabId) const;
    QQuickItem *noteItem(int tabId, quint64 noteId) const;
    int tabCount() const;
    int selectedId() const;
    int selectedIndex() const;
    int pendingCloseId() const;
    /// The application session's undo flag, which tracks the *selected* tab's
    /// document history. Read it after selecting the tab under test.
    bool canUndo() const;
    /// The tab session at one strip row, the identity the page and the model
    /// agree on.
    QObject *sessionAt(int row) const;
    int idAt(int row) const;
    int rowForId(int tabId) const;
    /// The session the page named `songTab_<tabId>` presents.
    QObject *pageSession(int tabId) const;
    /// The grid behind one tab, read from the page the tab owns.
    QObject *grid(int tabId) const;
    QObject *gridAt(int row) const;
    bool pageReady(int tabId) const;
    /// Opens `label` in a tab and waits for its page and grid. Tab semantics own
    /// the label: an already-open label focuses its tab instead, which the
    /// reopen scenario drives deliberately, so callers only pass labels that are
    /// not open yet.
    bool openSong(const QString &label, int *tabId, QString *error);
    /// Narrows the window until the strip's tabs overflow it, which is what
    /// exposes the native scroll controls, and keeps the widest overflowing
    /// window so the mounted roll stays as wide as the scenarios' grid input
    /// needs.
    bool narrowUntilStripOverflows(QString *error);
    bool clickItem(QQuickItem *target, QString *error);
    /// Delivers one vertical wheel notch at the centre of `target` on the mounted
    /// view, the way the roll receives a trackpad scroll.
    void wheelVertical(QQuickItem &target, int angle);
    /// Whether a tab's button lies inside the strip's scrolled viewport.
    bool tabButtonVisible(int tabId) const;
    /// Scrolls the strip until `tabId`'s button is inside the viewport, the way
    /// a user reaches a clipped tab with the native scroll controls.
    bool revealTab(int tabId, QString *error);
    /// Selects a tab by clicking it in the strip, revealing it first when the row
    /// is scrolled away.
    bool select(int tabId, QString *error);
    /// Clicks a tab's close control. A dirty tab raises the close gate instead of
    /// closing, so the caller decides what the gate means for it.
    bool clickClose(int tabId, QString *error);
    /// Clicks a button of the close gate's dialog. The dialog is a popup
    /// parented to the window's overlay, and its content arrives with it, so the
    /// lookup waits for the button to be presented.
    bool clickDialogButton(const QString &name, QString *error);
    bool awaitFrame(QString *error);
    QList<TabNote> notes(int tabId) const;
    int selectedNoteCount(int tabId) const;
    /// The scene-space centre of one published note.
    QPoint noteCenter(int tabId, quint64 noteId) const;
    /// A note that lies wholly inside a tab's pointer surface.
    std::optional<TabNote> firstVisibleNote(int tabId) const;
    /// A note whose centre a click can land on. A narrow window can clip the
    /// right edge of the roll, so this asks only for the hit point rather than
    /// the whole note.
    std::optional<TabNote> firstClickableNote(int tabId) const;
    QPoint pointFor(int tabId, int tick, int pitch) const;
    /// A real edit through the session: draws one note by pointer drag in an
    /// empty lane of the tab's own page, the way a user pencils a note in.
    bool drawNote(int tabId, TabNote *drawn, QString *error);
};

} // namespace tabcheck
