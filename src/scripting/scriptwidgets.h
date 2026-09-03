#pragma once

#include <QColor>
#include <QDeadlineTimer>
#include <QJSValue>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>
#include <QWidget>

class QBoxLayout;
class QDockWidget;
class QPainter;

namespace scripting {

class ScriptHost;
struct Plugin;
class CanvasWidget;

// porydaw.ui.dock's widget primitives (docs/scripting/PLAN.md §5, design
// B): real QWidgets behind thin QObject handles that scripts hold, plus a
// canvas whose paint callback draws through a QPainter facade. Handles
// are children of their widgets, so a dock's teardown releases every
// QJSValue callback before the plugin's engine goes (ScriptHost::teardown
// deletes docks first).

// CSS-ish colors for scripts: "#rgb", "#rrggbb", "#rrggbbaa", "rgb(r,g,b)",
// "rgba(r,g,b,a)", SVG color names, or [r, g, b, a?] arrays (0-255, a
// 0-1). False when unparseable.
bool parseColor(const QVariant &value, QColor *out);
// "#rrggbb" or "#rrggbbaa" (CSS order), what porydaw.ui.theme returns.
QString colorToCss(const QColor &color);

// The `g` a canvas paint callback receives. Valid only during that paint:
// every call outside throws. Coordinates are in device-independent
// pixels; (0, 0) is the canvas' top-left.
class Painter : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double width READ width)
    Q_PROPERTY(double height READ height)
    Q_PROPERTY(double dpr READ dpr)
  public:
    Painter(ScriptHost &host, Plugin &plugin, CanvasWidget *canvas);
    // The paint window: set by the canvas around the callback.
    void begin(QPainter *painter, double width, double height);
    void end();
    double width() const { return m_width; }
    double height() const { return m_height; }
    double dpr() const;

    Q_INVOKABLE void clear(const QVariant &color);
    Q_INVOKABLE void fillRect(double x, double y, double w, double h, const QVariant &color);
    Q_INVOKABLE void strokeRect(double x, double y, double w, double h, const QVariant &color,
                                double lineWidth);
    Q_INVOKABLE void fillRoundRect(double x, double y, double w, double h, double radius,
                                   const QVariant &color);
    Q_INVOKABLE void line(double x1, double y1, double x2, double y2, const QVariant &color,
                          double lineWidth);
    Q_INVOKABLE void fillCircle(double cx, double cy, double r, const QVariant &color);
    Q_INVOKABLE void strokeCircle(double cx, double cy, double r, const QVariant &color,
                                  double lineWidth);
    Q_INVOKABLE void fillEllipse(double x, double y, double w, double h, const QVariant &color);
    // points: [x0, y0, x1, y1, ...] or [{x, y}, ...].
    Q_INVOKABLE void fillPolygon(const QVariantList &points, const QVariant &color);
    Q_INVOKABLE void strokePolyline(const QVariantList &points, const QVariant &color,
                                    double lineWidth, bool close);
    // opts: {size: pt multiplier (1 = the UI font), bold, align:
    // "left"|"center"|"right", baseline: "top"|"middle"|"bottom"|"alphabetic"}.
    Q_INVOKABLE void text(double x, double y, const QString &text, const QVariant &color,
                          const QVariantMap &opts);
    Q_INVOKABLE QVariantMap measureText(const QString &text, const QVariantMap &opts);
    // An image from porydaw.ui.loadImage. Negative dw/dh keep the source
    // size; sx/sy/sw/sh pick a sub-rectangle (sprite sheets), sw/sh <= 0
    // meaning "to the edge".
    Q_INVOKABLE void image(int id, double dx, double dy, double dw, double dh, double sx, double sy,
                           double sw, double sh);
    Q_INVOKABLE void save();
    Q_INVOKABLE void restore();
    Q_INVOKABLE void translate(double dx, double dy);
    Q_INVOKABLE void rotate(double degrees);
    Q_INVOKABLE void scale(double sx, double sy);
    Q_INVOKABLE void opacity(double alpha);
    Q_INVOKABLE void clip(double x, double y, double w, double h);
    Q_INVOKABLE void antialias(bool on);

  private:
    bool active(const char *api) const;
    bool color(const QVariant &value, const char *api, QColor *out) const;
    QFont fontFor(const QVariantMap &opts) const;

    ScriptHost &m_host;
    Plugin &m_plugin;
    CanvasWidget *m_canvas;
    QPainter *m_painter = nullptr;
    double m_width = 0.0;
    double m_height = 0.0;
    int m_saveDepth = 0;
};

// A script-painted surface. paintEvent clears to the window background
// and runs the plugin's paint(g) under the watchdog; a paint that throws
// is logged and paints are suspended for a moment so a per-frame error
// doesn't flood the console. Mouse events reach mouse(ev) when given.
class CanvasWidget : public QWidget
{
    Q_OBJECT
  public:
    CanvasWidget(ScriptHost &host, Plugin &plugin, QWidget *parent);
    ~CanvasWidget() override;
    void setPaint(const QJSValue &fn) { m_paint = fn; }
    void setMouse(const QJSValue &fn);
    Painter *painter() const { return m_g; }
    int paintCount() const { return m_paintCount; }
    int errorCount() const { return m_errorCount; }

  protected:
    void paintEvent(QPaintEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void leaveEvent(QEvent *event) override;
    void changeEvent(QEvent *event) override;

  private:
    void sendMouse(const QString &type, const QPointF &pos, Qt::MouseButton button,
                   Qt::MouseButtons buttons, const QPointF &delta);

    ScriptHost &m_host;
    Plugin &m_plugin;
    QJSValue m_paint;
    QJSValue m_mouse;
    QJSValue m_gValue; // the JS wrapper of m_g, made once
    Painter *m_g;
    bool m_painting = false;
    int m_paintCount = 0;
    int m_errorCount = 0;
    QDeadlineTimer m_errorHold; // paints skipped until this expires
};

// A script's handle on one widget. `kind` decides which members apply;
// the rest are inert. Containers (row/column/the dock root) build
// children through the add* calls, in order.
class WidgetHandle : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString kind READ kind CONSTANT)
    Q_PROPERTY(QString text READ text WRITE setText)
    Q_PROPERTY(double value READ value WRITE setValue)
    Q_PROPERTY(bool checked READ checked WRITE setChecked)
    Q_PROPERTY(int index READ index WRITE setIndex)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled)
    Q_PROPERTY(bool visible READ visible WRITE setVisible)
    Q_PROPERTY(double width READ width)
    Q_PROPERTY(double height READ height)
  public:
    WidgetHandle(ScriptHost &host, Plugin &plugin, const QString &kind, QWidget *widget,
                 QBoxLayout *layout);
    QString kind() const { return m_kind; }
    QWidget *widget() const { return m_widget; }
    QString text() const;
    void setText(const QString &text);
    double value() const;
    void setValue(double value);
    bool checked() const;
    void setChecked(bool on);
    int index() const;
    void setIndex(int index);
    bool enabled() const;
    void setEnabled(bool on);
    bool visible() const;
    void setVisible(bool on);
    double width() const;
    double height() const;

    // Containers.
    Q_INVOKABLE QObject *addLabel(const QString &text);
    Q_INVOKABLE QObject *addButton(const QString &text, const QJSValue &onClick);
    Q_INVOKABLE QObject *addCheckbox(const QString &text, bool checked, const QJSValue &onChange);
    // Integer slider. opts: {vertical}.
    Q_INVOKABLE QObject *addSlider(int min, int max, int value, const QJSValue &onChange,
                                   const QVariantMap &opts);
    Q_INVOKABLE QObject *addCombo(const QStringList &items, int index, const QJSValue &onChange);
    // opts: {paint, mouse, minWidth, minHeight}.
    Q_INVOKABLE QObject *addCanvas(const QVariantMap &opts, const QJSValue &paint,
                                   const QJSValue &mouse);
    Q_INVOKABLE QObject *addRow();
    Q_INVOKABLE QObject *addColumn();
    Q_INVOKABLE void addStretch();
    Q_INVOKABLE void addSpacing(int px);
    // Any widget.
    Q_INVOKABLE void setMinimumSize(int w, int h);
    Q_INVOKABLE void setToolTip(const QString &text);
    // Canvas: schedules a repaint.
    Q_INVOKABLE void repaint();
    // Combo: replaces the items.
    Q_INVOKABLE void setItems(const QStringList &items);

  private:
    QObject *adopt(WidgetHandle *child);
    bool isContainer(const char *api) const;

    ScriptHost &m_host;
    Plugin &m_plugin;
    QString m_kind;
    QPointer<QWidget> m_widget;
    QBoxLayout *m_layout = nullptr; // containers only
    QJSValue m_callback;
    bool m_settingValue = false;
};

// The handle porydaw.ui.dock returns: the QDockWidget plus its root
// column. close() disposes the dock (and every handle under it).
class DockHandle : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(QString title READ title WRITE setTitle)
    Q_PROPERTY(bool visible READ visible WRITE setVisible)
    Q_PROPERTY(bool open READ isOpen)
    // The dock's body (a column container); with the paint shorthand,
    // `canvas` is the one canvas it holds (null otherwise).
    Q_PROPERTY(QObject *root READ root CONSTANT)
    Q_PROPERTY(QObject *canvas READ canvas CONSTANT)
  public:
    DockHandle(ScriptHost &host, Plugin &plugin, QDockWidget *dock, WidgetHandle *root,
               WidgetHandle *canvas);
    QString id() const { return m_id; }
    QString title() const;
    void setTitle(const QString &title);
    bool visible() const;
    void setVisible(bool on);
    bool isOpen() const { return !m_dock.isNull(); }
    QObject *root() const { return m_root; }
    QObject *canvas() const { return m_canvas; }
    Q_INVOKABLE void show() { setVisible(true); }
    Q_INVOKABLE void hide() { setVisible(false); }
    Q_INVOKABLE void raise();
    Q_INVOKABLE void close();

  private:
    ScriptHost &m_host;
    Plugin &m_plugin;
    QString m_id;
    QPointer<QDockWidget> m_dock;
    QPointer<WidgetHandle> m_root;
    QPointer<WidgetHandle> m_canvas;
};

// Builds a dock from a porydaw.ui.dock spec. Returns the handle (a child
// of the dock) or nullptr with *error set.
DockHandle *createDock(ScriptHost &host, Plugin &plugin, const QVariantMap &spec,
                       const QJSValue &build, const QJSValue &paint, const QJSValue &mouse,
                       QString *error);

} // namespace scripting
