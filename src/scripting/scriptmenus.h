#pragma once

#include <QAction>
#include <QDeadlineTimer>
#include <QJSValue>
#include <QMenu>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QVariantMap>

class QPainter;
class SongView;
struct RollOverlayGeometry;

namespace scripting {

class ScriptHost;
class Painter;
struct Plugin;
class MenuHandle;

// porydaw.ui.menu / porydaw.ui.contextMenu items and porydaw.ui.overlay
// (docs/scripting/API.md, Phase 4). Every handle here is parented under
// Plugin::uiRoot, which ScriptHost::teardown deletes before the engine —
// the handles hold QJSValue callbacks into it.

// One menu entry. Owns its QAction, so deleting the handle (remove(), or
// the plugin's teardown) takes the entry out of whichever menu shows it.
class MenuItemHandle : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString label READ label WRITE setLabel)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled)
    Q_PROPERTY(bool visible READ visible WRITE setVisible)
    Q_PROPERTY(bool checked READ checked WRITE setChecked)
  public:
    // spec: {label, action?: full keymap id, checkable?, checked?, enabled?,
    // tooltip?}. `run` is called on trigger (with the checked state);
    // without it, `action` runs through the host. `shouldShow`, when
    // callable, is asked each time the item's menu opens (shouldShow()).
    MenuItemHandle(ScriptHost &host, Plugin &plugin, const QVariantMap &spec, const QJSValue &run,
                   const QJSValue &shouldShow, QObject *parent);
    QAction *action() const { return m_action; }
    // The script's shouldShow() verdict for the menu opening now: true
    // without a predicate, and when the predicate throws (the error is
    // logged; a hidden entry would only hide the bug). The entry also
    // stays out while `visible` is false.
    bool shouldShow();
    QString label() const { return m_label; }
    void setLabel(const QString &label);
    bool enabled() const;
    void setEnabled(bool on);
    bool visible() const;
    void setVisible(bool on);
    bool checked() const;
    void setChecked(bool on);
    Q_INVOKABLE void remove();

  private:
    // "Label<TAB>Shortcut": the keymap binding of the linked command as a
    // display-only hint (a real shortcut on a menu-bar action would fire
    // window-wide, clashing with the roll-context dispatch).
    void refreshText();

    ScriptHost &m_host;
    Plugin &m_plugin;
    QPointer<QAction> m_action;
    QString m_label;
    QString m_commandId;
    QJSValue m_run;
    QJSValue m_shouldShow;
    bool m_visible = true; // the `visible` property; the action's follows shouldShow too
    bool m_settingValue = false;
};

// A menu: the plugin's own submenu of the window's Plugins menu, a nested
// submenu of it, or (surface non-empty) a context-menu extension whose
// items are appended to the roll's note menu or the time-selection menu
// as they open (ScriptHost::appendContextMenu).
class MenuHandle : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString label READ label WRITE setLabel)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled)
    Q_PROPERTY(bool visible READ visible WRITE setVisible)
  public:
    // Menu-bar menu: owns `menu` (deleted with the handle).
    MenuHandle(ScriptHost &host, Plugin &plugin, QMenu *menu, QObject *parent);
    // Context-menu extension for `surface` ("notes" | "range").
    MenuHandle(ScriptHost &host, Plugin &plugin, const QString &surface, QObject *parent);
    ~MenuHandle() override;
    QMenu *menu() const { return m_menu; }
    QString label() const;
    void setLabel(const QString &label);
    bool enabled() const;
    void setEnabled(bool on);
    bool visible() const;
    void setVisible(bool on);
    Q_INVOKABLE QObject *addItem(const QVariantMap &spec, const QJSValue &run,
                                 const QJSValue &shouldShow);
    Q_INVOKABLE void addSeparator();
    Q_INVOKABLE QObject *addMenu(const QString &label);
    // Removes every item (and submenu) added so far.
    Q_INVOKABLE void clear();

  private:
    // Menu-bar menus: re-asks every item's shouldShow() as the menu opens.
    void refreshItems();

    ScriptHost &m_host;
    Plugin &m_plugin;
    QPointer<QMenu> m_menu;
    QString m_surface;
    bool m_visible = true;
    bool m_enabled = true;
};

// The `v` an overlay paint callback receives: the roll's geometry for the
// paint in progress. Coordinates are widget pixels with (0, 0) at the
// top-left of the note area (the keyboard column excluded).
class OverlayView : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double width READ width)
    Q_PROPERTY(double height READ height)
    Q_PROPERTY(double from READ from)
    Q_PROPERTY(double to READ to)
    Q_PROPERTY(double keyHeight READ keyHeight)
    Q_PROPERTY(double pxPerBeat READ pxPerBeat)
    Q_PROPERTY(int track READ track)
  public:
    explicit OverlayView(QObject *parent) : QObject(parent) {}
    void begin(SongView &view, const RollOverlayGeometry &geometry);
    void end();
    double width() const;
    double height() const;
    double from() const { return m_from; }
    double to() const { return m_to; }
    double keyHeight() const { return m_keyHeight; }
    double pxPerBeat() const { return m_pxPerBeat; }
    int track() const { return m_track; }
    Q_INVOKABLE double x(double tick) const;
    Q_INVOKABLE double tick(double x) const;
    Q_INVOKABLE double keyTop(int key) const;
    Q_INVOKABLE double keyBottom(int key) const;
    Q_INVOKABLE int key(double y) const;

  private:
    const RollOverlayGeometry *m_geometry = nullptr;
    double m_from = 0.0;
    double m_to = 0.0;
    double m_keyHeight = 0.0;
    double m_pxPerBeat = 0.0;
    int m_track = 0;
};

// porydaw.ui.overlay: a paint(g, v) callback drawn over the piano roll's
// notes, on the active song's view, whenever the roll repaints. Same
// error handling as a canvas: a throwing paint is logged and held back
// for a second.
class OverlayHandle : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(bool visible READ visible WRITE setVisible)
    Q_PROPERTY(bool active READ active)
  public:
    OverlayHandle(ScriptHost &host, Plugin &plugin, const QString &id, const QJSValue &paint,
                  QObject *parent);
    QString id() const { return m_id; }
    bool visible() const { return m_visible && !m_removed; }
    void setVisible(bool on);
    bool active() const { return !m_removed; }
    Q_INVOKABLE void repaint();
    Q_INVOKABLE void remove();
    void paint(QPainter &painter, SongView &view, const RollOverlayGeometry &geometry);
    int paintCount() const { return m_paintCount; }
    int errorCount() const { return m_errorCount; }

  private:
    ScriptHost &m_host;
    Plugin &m_plugin;
    QString m_id;
    QJSValue m_paint;
    Painter *m_g;
    OverlayView *m_view;
    QJSValue m_gValue;
    QJSValue m_viewValue;
    bool m_visible = true;
    bool m_removed = false;
    bool m_painting = false;
    int m_paintCount = 0;
    int m_errorCount = 0;
    QDeadlineTimer m_errorHold;
};

} // namespace scripting
