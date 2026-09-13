#pragma once

#include <QAbstractListModel>
#include <QAction>
#include <QFont>
#include <QHash>
#include <QKeySequence>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QQuickWindow>
#include <QRectF>
#include <QString>
#include <QTimer>
#include <QVariantMap>
#include <QVector>
#include <vector>

class QEvent;
class QKeyEvent;
class QQuickItem;

namespace songview {

/// Measured row metrics for one menu level (defined in quickmenulayout.h).
struct MenuMetrics;

/// One typed menu row. Menus never carry QVariant command maps: owners build
/// vectors of values and hand them to a QuickMenuModel. Value rows dispatch
/// their integer ids; action-backed rows borrow the represented QAction.
///
/// A row is either a separator (`separator = true`; text/id are ignored) or a
/// normal entry. Checkable rows render a check mark while checked; `stayOpen` keeps the
/// menu session alive across activation so persistent filter toggles do not
/// close the menu — the owner rebuilds the model and the session survives.
/// Rows with non-empty `children` expose a submenu model through
/// QuickMenuModel::submenuForRow(). Action-backed rows retain the action
/// identity and project scalar display roles at menu-open time. The host
/// guards that identity before triggering.
struct QuickMenuItem {
    Q_GADGET
    Q_PROPERTY(int id MEMBER id FINAL)
    Q_PROPERTY(QString text MEMBER text FINAL)
    Q_PROPERTY(QString shortcutText MEMBER shortcutText FINAL)
    Q_PROPERTY(bool enabled MEMBER enabled FINAL)
    Q_PROPERTY(bool checkable MEMBER checkable FINAL)
    Q_PROPERTY(bool checked MEMBER checked FINAL)
    Q_PROPERTY(bool separator MEMBER separator FINAL)
    Q_PROPERTY(bool stayOpen MEMBER stayOpen FINAL)
    Q_PROPERTY(bool hasSubmenu READ hasSubmenu FINAL)

    // Q_GADGET leaves private access behind; restore the struct default.
  public:
    enum class Backing {
        Value,
        Action,
    };

    int id = 0;
    QString text;
    QString shortcutText;
    bool enabled = true;
    bool checkable = false;
    bool checked = false;
    bool separator = false;
    bool stayOpen = false;
    Backing backing = Backing::Value;
    QPointer<QAction> action;
    std::vector<QuickMenuItem> children;

    bool hasSubmenu() const { return !children.empty(); }
    bool isActionBacked() const { return backing == Backing::Action; }

    /// Snapshots the action's presentation text/enabled/checked at open time,
    /// retains a guarded non-owning identity the host triggers, requires the
    /// QAction to outlive the open menu, and retires the level on changed().
    static QuickMenuItem fromAction(QAction &source, int id);

    static QuickMenuItem makeSeparator();
};

/// Roles are explicit typed values served from the owned rows (never maps):
/// `itemId`, `text`, `shortcutText`, `checkable`, `checked`, `enabled`,
/// `separator`, `hasSubmenu`. Submenus are child QuickMenuModels parented to
/// this model and created lazily from the row's children, so owners only ever
/// build vectors of values.
///
/// setItems() replaces all rows and clears cached submenu models (they are
/// QObject children and die with it). A value-only session survives a rebuild:
/// the host re-resolves the highlighted row by id after modelReset(). An
/// action-backed root is instead retired so its scalar action projection is
/// never reused.
///
/// activated(id) dispatches value rows only: ordinary picks arrive AFTER the
/// host cleared the session, while stayOpen toggles arrive with the session
/// kept alive. Action-backed rows trigger their QAction through QuickMenuHost.
class QuickMenuModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged FINAL)

  public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        TextRole,
        ShortcutRole,
        CheckableRole,
        CheckedRole,
        EnabledRole,
        SeparatorRole,
        HasSubmenuRole,
    };
    Q_ENUM(Roles)

    explicit QuickMenuModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const;
    const std::vector<QuickMenuItem> &items() const { return m_items; }
    /// Rows are owned here; the pointer is valid until the next setItems().
    const QuickMenuItem *itemAt(int row) const;
    /// First row carrying the id, or -1.
    int rowForId(int id) const;

    /// Replaces all rows, discards cached submenu models and resets the model.
    void setItems(std::vector<QuickMenuItem> items);
    /// Flips a row's checked flag in place (stayOpen toggles); false if out of
    /// range or not a normal row.
    bool setItemChecked(int row, bool checked);

    /// Lazily creates (and caches) the child model for a row's children,
    /// parented to this model. Null when out of range or for separators.
    Q_INVOKABLE QuickMenuModel *submenuForRow(int row);

  signals:
    void activated(int id);
    void countChanged();

  private:
    void clearSubmenus();

    std::vector<QuickMenuItem> m_items;
    std::vector<QPointer<QuickMenuModel>> m_submenus;
};

/// Typed-menu adapter for a QuickPopupSession. It owns menu measurement,
/// navigation (keyboard, hover, type-ahead), submenu stacking and the typed
/// model contract; the shared session owns outside presses and lifecycle.
///
/// QuickMenuPanel.qml instances are parented beneath the session overlay root.
/// The adapter filters only KeyPress and KeyRelease while its own menu session
/// is active. Forms never pass through this keyboard path.
class QuickPopupSession;

class QuickMenuHost : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isOpen READ isOpen NOTIFY isOpenChanged FINAL)
    Q_PROPERTY(QuickMenuModel *rootModel READ rootModel NOTIFY rootChanged FINAL)
    Q_PROPERTY(QuickMenuModel *currentModel READ currentModel NOTIFY currentChanged FINAL)
    Q_PROPERTY(QQuickWindow *window READ window NOTIFY windowChanged FINAL)
    Q_PROPERTY(
        QVariantMap appearance READ appearance WRITE setAppearance NOTIFY appearanceChanged FINAL)

  public:
    explicit QuickMenuHost(QObject *parent = nullptr);
    ~QuickMenuHost() override;

    bool isOpen() const { return !m_levels.isEmpty(); }
    QuickMenuModel *rootModel() const;
    QuickMenuModel *currentModel() const;
    QQuickWindow *window() const;
    void setPopupSession(QuickPopupSession *session);
    const QVariantMap &appearance() const { return m_appearance; }
    void setAppearance(QVariantMap appearance);

    /// Opens (or replaces) this typed menu at a scene position. The shared
    /// popup session ends any foreign owner before this adapter publishes its
    /// menu panels.
    Q_INVOKABLE void open(QuickMenuModel *model, const QPointF &scenePos);
    Q_INVOKABLE void close();
    Q_INVOKABLE void cancel();

    // Panel-facing interaction (QuickMenuPanel.qml calls these).
    Q_INVOKABLE void hoverRow(QQuickItem *panel, int row);
    Q_INVOKABLE void activateRow(QQuickItem *panel, int row);

  signals:
    void isOpenChanged();
    void rootChanged();
    void currentChanged();
    void windowChanged();
    void appearanceChanged();
    void cancelled();
    void closed();
    // Emitted after a guarded QAction-backed row triggers successfully. Menu
    // owners use this only for focus completion.
    void actionActivated(QAction *action);
    // Emitted when a right-press outside the canvas dismissed THIS host's
    // menu session (never a foreign popup's). The scene position is the
    // press point; owners retarget or stay dismissed from here. The paired
    // release is swallowed by the shared session.
    void outsideRightPressed(const QPointF &scenePos);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    struct Level {
        QPointer<QuickMenuModel> model;
        QPointer<QQuickItem> panel;
        int highlightedRow = -1;
        int rememberedId = 0;
        QMetaObject::Connection resetConnection;
        QMetaObject::Connection modelDestroyedConnection;
        std::vector<QMetaObject::Connection> actionConnections;
    };

    QQuickItem *createPanel(QuickMenuModel *model, bool rootLevel, const MenuMetrics &layout);
    void pushLevel(QuickMenuModel *model, const QRectF &anchor, bool rootLevel);
    void popLevel(bool notifyState = true);
    void popToLevel(QQuickItem *panel);
    void teardown(bool notifyState = true);
    void handleSessionCancelled();
    void handleSessionClosed();
    void handleSessionOutsideRightPressed(QObject *dismissedOwner, const QPointF &scenePos);
    void handleLevelReset(QuickMenuModel *model);
    void triggerActionBackedRow(QAction *action);
    void layoutLevel(Level &level, const QRectF &anchor, bool rootLevel);
    void applyLevel(Level &level, const MenuMetrics &layout, const QRectF &anchor, bool rootLevel);
    void relayoutRoot();
    void setHighlight(Level &level, int row);
    void syncPanelHighlight(Level &level);
    void openSubmenuForRow(int row);
    QRectF rowSceneRect(QQuickItem *panel, int row) const;
    bool moveSelection(int delta);
    void handleKeyPress(QKeyEvent *event);
    void typeAhead(const QString &text);
    Level *currentLevel();
    QVector<Level> m_levels;
    QPointer<QuickPopupSession> m_popupSession;
    QVariantMap m_appearance;
    QString m_typeAhead;
    QTimer m_typeAheadReset;
    QPointF m_anchor;
    bool m_filterInstalled = false;
    bool m_sessionActive = false;
    bool m_waitingForClosed = false;
};

} // namespace songview
