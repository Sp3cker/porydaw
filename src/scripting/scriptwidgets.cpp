#include "scriptwidgets.h"

#include <QBoxLayout>
#include <QCheckBox>
#include <QComboBox>
#include <QDockWidget>
#include <QEvent>
#include <QFontMetricsF>
#include <QJSEngine>
#include <QLabel>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QPushButton>
#include <QRegularExpression>
#include <QSlider>
#include <QWheelEvent>

#include <algorithm>
#include <cmath>

#include "scripthost.h"
#include "ui/layout.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

namespace scripting {

namespace {

constexpr int kPaintErrorHoldMs = 1000;

double finite(double v, double fallback = 0.0)
{
    return std::isfinite(v) ? v : fallback;
}

bool parseChannel(const QString &s, bool alpha, int *out)
{
    bool ok = false;
    const QString t = s.trimmed();
    if (alpha) {
        double a = t.toDouble(&ok);
        if (!ok)
            return false;
        *out = std::clamp(int(std::lround(a * 255.0)), 0, 255);
        return true;
    }
    if (t.endsWith(QLatin1Char('%'))) {
        double p = t.chopped(1).toDouble(&ok);
        if (!ok)
            return false;
        *out = std::clamp(int(std::lround(p * 2.55)), 0, 255);
        return true;
    }
    double v = t.toDouble(&ok);
    if (!ok)
        return false;
    *out = std::clamp(int(std::lround(v)), 0, 255);
    return true;
}

} // namespace

bool parseColor(const QVariant &value, QColor *out)
{
    if (value.canConvert<QVariantList>() && value.userType() != QMetaType::QString) {
        const QVariantList list = value.toList();
        if (list.size() < 3 || list.size() > 4)
            return false;
        int c[4] = {0, 0, 0, 255};
        for (int i = 0; i < list.size(); i++) {
            bool ok = false;
            const double v = list[i].toDouble(&ok);
            if (!ok || !std::isfinite(v))
                return false;
            c[i] = i == 3 ? std::clamp(int(std::lround(v * 255.0)), 0, 255)
                          : std::clamp(int(std::lround(v)), 0, 255);
        }
        *out = QColor(c[0], c[1], c[2], c[3]);
        return true;
    }
    const QString s = value.toString().trimmed();
    if (s.isEmpty())
        return false;
    if (s.startsWith(QLatin1Char('#'))) {
        const QString hex = s.mid(1);
        bool ok = false;
        const uint v = hex.toUInt(&ok, 16);
        if (!ok)
            return false;
        switch (hex.size()) {
        case 3:
            *out = QColor(((v >> 8) & 0xF) * 17, ((v >> 4) & 0xF) * 17, (v & 0xF) * 17);
            return true;
        case 4:
            *out = QColor(((v >> 12) & 0xF) * 17, ((v >> 8) & 0xF) * 17, ((v >> 4) & 0xF) * 17,
                          (v & 0xF) * 17);
            return true;
        case 6:
            *out = QColor((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
            return true;
        case 8:
            *out = QColor((v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
            return true;
        default:
            return false;
        }
    }
    static const QRegularExpression rgb(
        QStringLiteral("^rgba?\\s*\\(\\s*([^,\\s]+)\\s*,\\s*([^,\\s]+)\\s*,\\s*([^,\\s)]+)\\s*"
                       "(?:,\\s*([^\\s)]+)\\s*)?\\)$"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch m = rgb.match(s);
    if (m.hasMatch()) {
        int c[4] = {0, 0, 0, 255};
        for (int i = 0; i < 3; i++) {
            if (!parseChannel(m.captured(i + 1), false, &c[i]))
                return false;
        }
        if (!m.captured(4).isEmpty() && !parseChannel(m.captured(4), true, &c[3]))
            return false;
        *out = QColor(c[0], c[1], c[2], c[3]);
        return true;
    }
    if (s.compare(QLatin1String("transparent"), Qt::CaseInsensitive) == 0) {
        *out = QColor(0, 0, 0, 0);
        return true;
    }
    if (!QColor::isValidColor(s))
        return false;
    *out = QColor(s);
    return true;
}

QString colorToCss(const QColor &color)
{
    if (color.alpha() == 255)
        return color.name(QColor::HexRgb);
    // QColor::HexArgb puts alpha first; CSS wants it last.
    return QStringLiteral("#%1%2%3%4")
        .arg(color.red(), 2, 16, QLatin1Char('0'))
        .arg(color.green(), 2, 16, QLatin1Char('0'))
        .arg(color.blue(), 2, 16, QLatin1Char('0'))
        .arg(color.alpha(), 2, 16, QLatin1Char('0'));
}

// ---- Painter ----

Painter::Painter(ScriptHost &host, Plugin &plugin, CanvasWidget *canvas)
    : QObject(canvas)
    , m_host(host)
    , m_plugin(plugin)
    , m_canvas(canvas)
{}

void Painter::begin(QPainter *painter, double width, double height)
{
    m_painter = painter;
    m_width = width;
    m_height = height;
    m_saveDepth = 0;
}

void Painter::end()
{
    // A script that saved more than it restored must not leave the
    // widget's painter transformed.
    while (m_saveDepth > 0) {
        m_painter->restore();
        m_saveDepth--;
    }
    m_painter = nullptr;
}

double Painter::dpr() const
{
    return m_canvas ? m_canvas->devicePixelRatioF() : 1.0;
}

bool Painter::active(const char *api) const
{
    if (m_painter)
        return true;
    if (QJSEngine *e = m_plugin.engine.get())
        e->throwError(QJSValue::TypeError,
                      QStringLiteral("%1: the canvas painter is only usable inside paint()")
                          .arg(QLatin1String(api)));
    return false;
}

bool Painter::color(const QVariant &value, const char *api, QColor *out) const
{
    if (parseColor(value, out))
        return true;
    if (QJSEngine *e = m_plugin.engine.get())
        e->throwError(
            QJSValue::TypeError,
            QStringLiteral("%1: bad color '%2'").arg(QLatin1String(api), value.toString()));
    return false;
}

QFont Painter::fontFor(const QVariantMap &opts) const
{
    QFont f = m_canvas ? m_canvas->font() : QFont();
    const double size = finite(opts.value(QStringLiteral("size"), 1.0).toDouble(), 1.0);
    if (size > 0.0 && size != 1.0) {
        const double pt = f.pointSizeF() > 0 ? f.pointSizeF() : 10.0;
        f.setPointSizeF(std::clamp(pt * size, 4.0, 200.0));
    }
    if (opts.value(QStringLiteral("bold")).toBool())
        f = typography::bold(f);
    return f;
}

void Painter::clear(const QVariant &color)
{
    if (!active("clear"))
        return;
    QColor c;
    if (!this->color(color, "clear", &c))
        return;
    m_painter->save();
    m_painter->resetTransform();
    m_painter->setCompositionMode(QPainter::CompositionMode_Source);
    m_painter->fillRect(QRectF(0, 0, m_width, m_height), c);
    m_painter->restore();
}

void Painter::fillRect(double x, double y, double w, double h, const QVariant &color)
{
    if (!active("fillRect"))
        return;
    QColor c;
    if (!this->color(color, "fillRect", &c))
        return;
    m_painter->fillRect(QRectF(finite(x), finite(y), finite(w), finite(h)), c);
}

void Painter::strokeRect(double x, double y, double w, double h, const QVariant &color,
                         double lineWidth)
{
    if (!active("strokeRect"))
        return;
    QColor c;
    if (!this->color(color, "strokeRect", &c))
        return;
    m_painter->setPen(QPen(c, std::max(0.0, finite(lineWidth, 1.0))));
    m_painter->setBrush(Qt::NoBrush);
    m_painter->drawRect(QRectF(finite(x), finite(y), finite(w), finite(h)));
}

void Painter::fillRoundRect(double x, double y, double w, double h, double radius,
                            const QVariant &color)
{
    if (!active("fillRoundRect"))
        return;
    QColor c;
    if (!this->color(color, "fillRoundRect", &c))
        return;
    QPainterPath path;
    path.addRoundedRect(QRectF(finite(x), finite(y), finite(w), finite(h)),
                        std::max(0.0, finite(radius)), std::max(0.0, finite(radius)));
    m_painter->fillPath(path, c);
}

void Painter::line(double x1, double y1, double x2, double y2, const QVariant &color,
                   double lineWidth)
{
    if (!active("line"))
        return;
    QColor c;
    if (!this->color(color, "line", &c))
        return;
    m_painter->setPen(QPen(c, std::max(0.0, finite(lineWidth, 1.0))));
    m_painter->drawLine(QPointF(finite(x1), finite(y1)), QPointF(finite(x2), finite(y2)));
}

void Painter::fillCircle(double cx, double cy, double r, const QVariant &color)
{
    if (!active("fillCircle"))
        return;
    QColor c;
    if (!this->color(color, "fillCircle", &c))
        return;
    m_painter->setPen(Qt::NoPen);
    m_painter->setBrush(c);
    m_painter->drawEllipse(QPointF(finite(cx), finite(cy)), finite(r), finite(r));
}

void Painter::strokeCircle(double cx, double cy, double r, const QVariant &color, double lineWidth)
{
    if (!active("strokeCircle"))
        return;
    QColor c;
    if (!this->color(color, "strokeCircle", &c))
        return;
    m_painter->setPen(QPen(c, std::max(0.0, finite(lineWidth, 1.0))));
    m_painter->setBrush(Qt::NoBrush);
    m_painter->drawEllipse(QPointF(finite(cx), finite(cy)), finite(r), finite(r));
}

void Painter::fillEllipse(double x, double y, double w, double h, const QVariant &color)
{
    if (!active("fillEllipse"))
        return;
    QColor c;
    if (!this->color(color, "fillEllipse", &c))
        return;
    m_painter->setPen(Qt::NoPen);
    m_painter->setBrush(c);
    m_painter->drawEllipse(QRectF(finite(x), finite(y), finite(w), finite(h)));
}

namespace {

QPolygonF toPolygon(const QVariantList &points)
{
    QPolygonF poly;
    if (!points.isEmpty() && points.first().canConvert<QVariantMap>()) {
        for (const QVariant &p : points) {
            const QVariantMap m = p.toMap();
            poly << QPointF(finite(m.value(QStringLiteral("x")).toDouble()),
                            finite(m.value(QStringLiteral("y")).toDouble()));
        }
        return poly;
    }
    for (int i = 0; i + 1 < points.size(); i += 2)
        poly << QPointF(finite(points[i].toDouble()), finite(points[i + 1].toDouble()));
    return poly;
}

} // namespace

void Painter::fillPolygon(const QVariantList &points, const QVariant &color)
{
    if (!active("fillPolygon"))
        return;
    QColor c;
    if (!this->color(color, "fillPolygon", &c))
        return;
    m_painter->setPen(Qt::NoPen);
    m_painter->setBrush(c);
    m_painter->drawPolygon(toPolygon(points));
}

void Painter::strokePolyline(const QVariantList &points, const QVariant &color, double lineWidth,
                             bool close)
{
    if (!active("strokePolyline"))
        return;
    QColor c;
    if (!this->color(color, "strokePolyline", &c))
        return;
    QPen pen(c, std::max(0.0, finite(lineWidth, 1.0)));
    pen.setJoinStyle(Qt::RoundJoin);
    m_painter->setPen(pen);
    m_painter->setBrush(Qt::NoBrush);
    const QPolygonF poly = toPolygon(points);
    if (close)
        m_painter->drawPolygon(poly);
    else
        m_painter->drawPolyline(poly);
}

void Painter::text(double x, double y, const QString &text, const QVariant &color,
                   const QVariantMap &opts)
{
    if (!active("text"))
        return;
    QColor c;
    if (!this->color(color, "text", &c))
        return;
    const QFont f = fontFor(opts);
    const QFontMetricsF fm(f);
    double px = finite(x), py = finite(y);
    const QString align = opts.value(QStringLiteral("align")).toString();
    const double w = fm.horizontalAdvance(text);
    if (align == QLatin1String("center"))
        px -= w / 2.0;
    else if (align == QLatin1String("right"))
        px -= w;
    const QString baseline = opts.value(QStringLiteral("baseline")).toString();
    if (baseline == QLatin1String("top"))
        py += fm.ascent();
    else if (baseline == QLatin1String("middle"))
        py += fm.ascent() / 2.0 - fm.descent() / 2.0;
    else if (baseline == QLatin1String("bottom"))
        py -= fm.descent();
    m_painter->setFont(f);
    m_painter->setPen(c);
    m_painter->drawText(QPointF(px, py), text);
}

QVariantMap Painter::measureText(const QString &text, const QVariantMap &opts)
{
    const QFontMetricsF fm(fontFor(opts));
    return QVariantMap{{QStringLiteral("width"), fm.horizontalAdvance(text)},
                       {QStringLiteral("height"), fm.height()},
                       {QStringLiteral("ascent"), fm.ascent()},
                       {QStringLiteral("descent"), fm.descent()}};
}

void Painter::image(int id, double dx, double dy, double dw, double dh, double sx, double sy,
                    double sw, double sh)
{
    if (!active("image"))
        return;
    const auto it = m_plugin.images.find(id);
    if (it == m_plugin.images.end()) {
        if (QJSEngine *e = m_plugin.engine.get())
            e->throwError(QJSValue::TypeError,
                          QStringLiteral("image: no image with id %1").arg(id));
        return;
    }
    const QImage &img = it->second;
    sx = std::clamp(finite(sx), 0.0, double(img.width()));
    sy = std::clamp(finite(sy), 0.0, double(img.height()));
    if (!(finite(sw, -1.0) > 0.0))
        sw = img.width() - sx;
    if (!(finite(sh, -1.0) > 0.0))
        sh = img.height() - sy;
    sw = std::min(sw, img.width() - sx);
    sh = std::min(sh, img.height() - sy);
    if (!(finite(dw, -1.0) > 0.0))
        dw = sw;
    if (!(finite(dh, -1.0) > 0.0))
        dh = sh;
    if (sw <= 0.0 || sh <= 0.0)
        return;
    m_painter->drawImage(QRectF(finite(dx), finite(dy), dw, dh), img, QRectF(sx, sy, sw, sh));
}

void Painter::save()
{
    if (!active("save"))
        return;
    if (m_saveDepth >= 64) {
        if (QJSEngine *e = m_plugin.engine.get())
            e->throwError(QJSValue::RangeError, QStringLiteral("save: too many nested saves"));
        return;
    }
    m_painter->save();
    m_saveDepth++;
}

void Painter::restore()
{
    if (!active("restore"))
        return;
    if (m_saveDepth <= 0)
        return;
    m_painter->restore();
    m_saveDepth--;
}

void Painter::translate(double dx, double dy)
{
    if (active("translate"))
        m_painter->translate(finite(dx), finite(dy));
}

void Painter::rotate(double degrees)
{
    if (active("rotate"))
        m_painter->rotate(finite(degrees));
}

void Painter::scale(double sx, double sy)
{
    if (active("scale"))
        m_painter->scale(finite(sx, 1.0), finite(sy, 1.0));
}

void Painter::opacity(double alpha)
{
    if (active("opacity"))
        m_painter->setOpacity(std::clamp(finite(alpha, 1.0), 0.0, 1.0));
}

void Painter::clip(double x, double y, double w, double h)
{
    if (active("clip"))
        m_painter->setClipRect(QRectF(finite(x), finite(y), finite(w), finite(h)),
                               Qt::IntersectClip);
}

void Painter::antialias(bool on)
{
    if (active("antialias"))
        m_painter->setRenderHint(QPainter::Antialiasing, on);
}

// ---- CanvasWidget ----

CanvasWidget::CanvasWidget(ScriptHost &host, Plugin &plugin, QWidget *parent)
    : QWidget(parent)
    , m_host(host)
    , m_plugin(plugin)
    , m_g(new Painter(host, plugin, this))
{
    // Never steal keyboard focus from the roll: plugin docks are
    // displays, and bare-letter shortcuts belong to the focused surface.
    setFocusPolicy(Qt::NoFocus);
    setMouseTracking(true);
    setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
    setMinimumSize(16, 16);
}

CanvasWidget::~CanvasWidget() = default;

void CanvasWidget::setMouse(const QJSValue &fn)
{
    m_mouse = fn;
}

void CanvasWidget::paintEvent(QPaintEvent *)
{
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing, true);
    p.setRenderHint(QPainter::SmoothPixmapTransform, true);
    p.fillRect(rect(), themes::color(themes::Role::window_background));
    p.setPen(themes::color(themes::Role::window_text));
    if (m_painting || !m_paint.isCallable() || m_plugin.state != PluginState::Loaded)
        return;
    if (!m_errorHold.isForever() && !m_errorHold.hasExpired())
        return;
    if (m_gValue.isUndefined() && m_plugin.engine) {
        QJSEngine::setObjectOwnership(m_g, QJSEngine::CppOwnership);
        m_gValue = m_plugin.engine->newQObject(m_g);
    }
    m_painting = true;
    m_g->begin(&p, width(), height());
    const QJSValue result = m_host.invoke(m_plugin, m_paint, {m_gValue});
    m_g->end();
    m_painting = false;
    m_paintCount++;
    if (result.isError()) {
        m_errorCount++;
        m_errorHold = QDeadlineTimer(kPaintErrorHoldMs);
    }
}

void CanvasWidget::sendMouse(const QString &type, const QPointF &pos, Qt::MouseButton button,
                             Qt::MouseButtons buttons, const QPointF &delta)
{
    if (!m_mouse.isCallable() || !m_plugin.engine)
        return;
    const auto name = [](Qt::MouseButton b) {
        switch (b) {
        case Qt::LeftButton:
            return QStringLiteral("left");
        case Qt::RightButton:
            return QStringLiteral("right");
        case Qt::MiddleButton:
            return QStringLiteral("middle");
        default:
            return QStringLiteral("none");
        }
    };
    QVariantMap ev{{QStringLiteral("type"), type},
                   {QStringLiteral("x"), pos.x()},
                   {QStringLiteral("y"), pos.y()},
                   {QStringLiteral("button"), name(button)},
                   {QStringLiteral("left"), bool(buttons & Qt::LeftButton)},
                   {QStringLiteral("right"), bool(buttons & Qt::RightButton)},
                   {QStringLiteral("middle"), bool(buttons & Qt::MiddleButton)}};
    if (type == QLatin1String("wheel")) {
        ev.insert(QStringLiteral("deltaX"), delta.x());
        ev.insert(QStringLiteral("deltaY"), delta.y());
    }
    m_host.invoke(m_plugin, m_mouse, {m_plugin.engine->toScriptValue(ev)});
}

void CanvasWidget::mousePressEvent(QMouseEvent *event)
{
    sendMouse(QStringLiteral("press"), event->position(), event->button(), event->buttons(), {});
}

void CanvasWidget::mouseMoveEvent(QMouseEvent *event)
{
    sendMouse(QStringLiteral("move"), event->position(), Qt::NoButton, event->buttons(), {});
}

void CanvasWidget::mouseReleaseEvent(QMouseEvent *event)
{
    sendMouse(QStringLiteral("release"), event->position(), event->button(), event->buttons(), {});
}

void CanvasWidget::mouseDoubleClickEvent(QMouseEvent *event)
{
    sendMouse(QStringLiteral("doubleclick"), event->position(), event->button(), event->buttons(),
              {});
}

void CanvasWidget::wheelEvent(QWheelEvent *event)
{
    // Steps of ±1 per notch, like a browser's deltaY sign convention
    // (positive = wheel down / away).
    const QPoint deg = event->angleDelta();
    sendMouse(QStringLiteral("wheel"), event->position(), Qt::NoButton, event->buttons(),
              QPointF(-deg.x() / 120.0, -deg.y() / 120.0));
    event->accept();
}

void CanvasWidget::leaveEvent(QEvent *)
{
    sendMouse(QStringLiteral("leave"), QPointF(-1, -1), Qt::NoButton, Qt::NoButton, {});
}

void CanvasWidget::changeEvent(QEvent *event)
{
    QWidget::changeEvent(event);
    // Theme swaps arrive as palette/font changes; scripts read
    // porydaw.ui.theme at paint time, so a repaint is all they need.
    if (event->type() == QEvent::PaletteChange || event->type() == QEvent::FontChange ||
        event->type() == QEvent::ApplicationPaletteChange)
        update();
}

// ---- WidgetHandle ----

WidgetHandle::WidgetHandle(ScriptHost &host, Plugin &plugin, const QString &kind, QWidget *widget,
                           QBoxLayout *layout)
    : QObject(widget)
    , m_host(host)
    , m_plugin(plugin)
    , m_kind(kind)
    , m_widget(widget)
    , m_layout(layout)
{}

QString WidgetHandle::text() const
{
    if (auto *l = qobject_cast<QLabel *>(m_widget))
        return l->text();
    if (auto *b = qobject_cast<QAbstractButton *>(m_widget))
        return b->text();
    if (auto *c = qobject_cast<QComboBox *>(m_widget))
        return c->currentText();
    return QString();
}

void WidgetHandle::setText(const QString &text)
{
    if (auto *l = qobject_cast<QLabel *>(m_widget))
        l->setText(text);
    else if (auto *b = qobject_cast<QAbstractButton *>(m_widget))
        b->setText(text);
}

double WidgetHandle::value() const
{
    if (auto *s = qobject_cast<QSlider *>(m_widget))
        return s->value();
    if (auto *c = qobject_cast<QComboBox *>(m_widget))
        return c->currentIndex();
    if (auto *b = qobject_cast<QCheckBox *>(m_widget))
        return b->isChecked() ? 1 : 0;
    return 0;
}

void WidgetHandle::setValue(double value)
{
    if (!std::isfinite(value))
        return;
    m_settingValue = true;
    if (auto *s = qobject_cast<QSlider *>(m_widget))
        s->setValue(int(std::lround(value)));
    else if (auto *c = qobject_cast<QComboBox *>(m_widget))
        c->setCurrentIndex(int(std::lround(value)));
    else if (auto *b = qobject_cast<QCheckBox *>(m_widget))
        b->setChecked(value != 0.0);
    m_settingValue = false;
}

bool WidgetHandle::checked() const
{
    if (auto *b = qobject_cast<QAbstractButton *>(m_widget))
        return b->isChecked();
    return false;
}

void WidgetHandle::setChecked(bool on)
{
    if (auto *b = qobject_cast<QAbstractButton *>(m_widget)) {
        m_settingValue = true;
        b->setChecked(on);
        m_settingValue = false;
    }
}

int WidgetHandle::index() const
{
    if (auto *c = qobject_cast<QComboBox *>(m_widget))
        return c->currentIndex();
    return -1;
}

void WidgetHandle::setIndex(int index)
{
    if (auto *c = qobject_cast<QComboBox *>(m_widget)) {
        m_settingValue = true;
        c->setCurrentIndex(index);
        m_settingValue = false;
    }
}

bool WidgetHandle::enabled() const
{
    return m_widget && m_widget->isEnabled();
}

void WidgetHandle::setEnabled(bool on)
{
    if (m_widget)
        m_widget->setEnabled(on);
}

bool WidgetHandle::visible() const
{
    return m_widget && !m_widget->isHidden();
}

void WidgetHandle::setVisible(bool on)
{
    if (m_widget)
        m_widget->setVisible(on);
}

double WidgetHandle::width() const
{
    return m_widget ? m_widget->width() : 0;
}

double WidgetHandle::height() const
{
    return m_widget ? m_widget->height() : 0;
}

bool WidgetHandle::isContainer(const char *api) const
{
    if (m_layout && m_widget)
        return true;
    if (QJSEngine *e = m_plugin.engine.get())
        e->throwError(QJSValue::TypeError,
                      QStringLiteral("%1: only a row, column or dock root can hold widgets")
                          .arg(QLatin1String(api)));
    return false;
}

QObject *WidgetHandle::adopt(WidgetHandle *child)
{
    m_layout->addWidget(child->widget());
    // Handles are children of their widgets; the wrapper must not delete
    // C++-owned objects when collected.
    QJSEngine::setObjectOwnership(child, QJSEngine::CppOwnership);
    return child;
}

QObject *WidgetHandle::addLabel(const QString &text)
{
    if (!isContainer("label"))
        return nullptr;
    auto *label = new QLabel(text, m_widget);
    label->setWordWrap(true);
    return adopt(new WidgetHandle(m_host, m_plugin, QStringLiteral("label"), label, nullptr));
}

QObject *WidgetHandle::addButton(const QString &text, const QJSValue &onClick)
{
    if (!isContainer("button"))
        return nullptr;
    auto *button = new QPushButton(text, m_widget);
    button->setFocusPolicy(Qt::NoFocus);
    auto *handle = new WidgetHandle(m_host, m_plugin, QStringLiteral("button"), button, nullptr);
    handle->m_callback = onClick;
    connect(button, &QPushButton::clicked, handle,
            [handle] { handle->m_host.invoke(handle->m_plugin, handle->m_callback, {}); });
    return adopt(handle);
}

QObject *WidgetHandle::addCheckbox(const QString &text, bool checked, const QJSValue &onChange)
{
    if (!isContainer("checkbox"))
        return nullptr;
    auto *box = new QCheckBox(text, m_widget);
    box->setChecked(checked);
    box->setFocusPolicy(Qt::NoFocus);
    auto *handle = new WidgetHandle(m_host, m_plugin, QStringLiteral("checkbox"), box, nullptr);
    handle->m_callback = onChange;
    connect(box, &QCheckBox::toggled, handle, [handle](bool on) {
        if (!handle->m_settingValue)
            handle->m_host.invoke(handle->m_plugin, handle->m_callback, {QJSValue(on)});
    });
    return adopt(handle);
}

QObject *WidgetHandle::addSlider(int min, int max, int value, const QJSValue &onChange,
                                 const QVariantMap &opts)
{
    if (!isContainer("slider"))
        return nullptr;
    const bool vertical = opts.value(QStringLiteral("vertical")).toBool();
    auto *slider = new QSlider(vertical ? Qt::Vertical : Qt::Horizontal, m_widget);
    slider->setRange(std::min(min, max), std::max(min, max));
    slider->setValue(value);
    slider->setFocusPolicy(Qt::NoFocus);
    auto *handle = new WidgetHandle(m_host, m_plugin, QStringLiteral("slider"), slider, nullptr);
    handle->m_callback = onChange;
    connect(slider, &QSlider::valueChanged, handle, [handle](int v) {
        if (!handle->m_settingValue)
            handle->m_host.invoke(handle->m_plugin, handle->m_callback, {QJSValue(v)});
    });
    return adopt(handle);
}

QObject *WidgetHandle::addCombo(const QStringList &items, int index, const QJSValue &onChange)
{
    if (!isContainer("combo"))
        return nullptr;
    auto *combo = new QComboBox(m_widget);
    combo->addItems(items);
    combo->setCurrentIndex(index);
    combo->setFocusPolicy(Qt::NoFocus);
    auto *handle = new WidgetHandle(m_host, m_plugin, QStringLiteral("combo"), combo, nullptr);
    handle->m_callback = onChange;
    connect(combo, &QComboBox::currentIndexChanged, handle, [handle](int i) {
        if (!handle->m_settingValue)
            handle->m_host.invoke(handle->m_plugin, handle->m_callback, {QJSValue(i)});
    });
    return adopt(handle);
}

QObject *WidgetHandle::addCanvas(const QVariantMap &opts, const QJSValue &paint,
                                 const QJSValue &mouse)
{
    if (!isContainer("canvas"))
        return nullptr;
    auto *canvas = new CanvasWidget(m_host, m_plugin, m_widget);
    canvas->setPaint(paint);
    canvas->setMouse(mouse);
    const int minW = opts.value(QStringLiteral("minWidth"), 16).toInt();
    const int minH = opts.value(QStringLiteral("minHeight"), 16).toInt();
    canvas->setMinimumSize(std::clamp(minW, 1, 4096), std::clamp(minH, 1, 4096));
    return adopt(new WidgetHandle(m_host, m_plugin, QStringLiteral("canvas"), canvas, nullptr));
}

QObject *WidgetHandle::addRow()
{
    if (!isContainer("row"))
        return nullptr;
    auto *w = new QWidget(m_widget);
    auto *layout = new QHBoxLayout(w);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(layout::space(layout::Space::One));
    return adopt(new WidgetHandle(m_host, m_plugin, QStringLiteral("row"), w, layout));
}

QObject *WidgetHandle::addColumn()
{
    if (!isContainer("column"))
        return nullptr;
    auto *w = new QWidget(m_widget);
    auto *layout = new QVBoxLayout(w);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(layout::space(layout::Space::One));
    return adopt(new WidgetHandle(m_host, m_plugin, QStringLiteral("column"), w, layout));
}

void WidgetHandle::addStretch()
{
    if (isContainer("stretch"))
        m_layout->addStretch(1);
}

void WidgetHandle::addSpacing(int px)
{
    if (isContainer("spacing"))
        m_layout->addSpacing(std::clamp(px, 0, 4096));
}

void WidgetHandle::setMinimumSize(int w, int h)
{
    if (m_widget)
        m_widget->setMinimumSize(std::clamp(w, 0, 4096), std::clamp(h, 0, 4096));
}

void WidgetHandle::setToolTip(const QString &text)
{
    if (m_widget)
        m_widget->setToolTip(text);
}

void WidgetHandle::repaint()
{
    if (m_widget)
        m_widget->update();
}

void WidgetHandle::setItems(const QStringList &items)
{
    if (auto *c = qobject_cast<QComboBox *>(m_widget)) {
        m_settingValue = true;
        c->clear();
        c->addItems(items);
        m_settingValue = false;
    }
}

// ---- DockHandle ----

DockHandle::DockHandle(ScriptHost &host, Plugin &plugin, QDockWidget *dock, WidgetHandle *root,
                       WidgetHandle *canvas)
    // Parented to a facade, not the dock: the handle outlives close() so a
    // script can still read `open` (false) and calling into it is inert.
    : QObject(plugin.facades.empty() ? nullptr : plugin.facades.front().get())
    , m_host(host)
    , m_plugin(plugin)
    , m_id(dock->objectName())
    , m_dock(dock)
    , m_root(root)
    , m_canvas(canvas)
{}

QString DockHandle::title() const
{
    return m_dock ? m_dock->windowTitle() : QString();
}

void DockHandle::setTitle(const QString &title)
{
    if (m_dock)
        m_dock->setWindowTitle(title);
}

bool DockHandle::visible() const
{
    return m_dock && !m_dock->isHidden();
}

void DockHandle::setVisible(bool on)
{
    if (m_dock)
        m_dock->setVisible(on);
}

void DockHandle::raise()
{
    if (m_dock) {
        m_dock->show();
        m_dock->raise();
    }
}

void DockHandle::close()
{
    if (!m_dock)
        return;
    // Deferred: close() may run from one of the dock's own callbacks.
    QDockWidget *dock = m_dock;
    m_dock.clear();
    dock->hide();
    dock->deleteLater();
}

DockHandle *createDock(ScriptHost &host, Plugin &plugin, const QVariantMap &spec,
                       const QJSValue &build, const QJSValue &paint, const QJSValue &mouse,
                       QString *error)
{
    const QString id = spec.value(QStringLiteral("id")).toString();
    static const QRegularExpression idRe(QStringLiteral("^[A-Za-z0-9_-]{1,64}$"));
    if (!idRe.match(id).hasMatch()) {
        *error = QStringLiteral("ui.dock: id must be 1-64 letters, digits, '_' or '-'");
        return nullptr;
    }
    const QString objectName =
        QStringLiteral("plugin.") + plugin.manifest.id + QLatin1Char('.') + id;
    for (const QPointer<QDockWidget> &existing : plugin.docks) {
        if (existing && existing->objectName() == objectName) {
            *error = QStringLiteral("ui.dock: a dock with id '%1' is already open").arg(id);
            return nullptr;
        }
    }
    QString title = spec.value(QStringLiteral("title")).toString();
    if (title.isEmpty())
        title = plugin.manifest.name.isEmpty() ? id : plugin.manifest.name;
    const QString areaName = spec.value(QStringLiteral("area"), QStringLiteral("right")).toString();
    Qt::DockWidgetArea area = Qt::RightDockWidgetArea;
    if (areaName == QLatin1String("left"))
        area = Qt::LeftDockWidgetArea;
    else if (areaName == QLatin1String("bottom"))
        area = Qt::BottomDockWidgetArea;
    else if (areaName == QLatin1String("top"))
        area = Qt::TopDockWidgetArea;
    else if (areaName != QLatin1String("right")) {
        *error = QStringLiteral("ui.dock: area must be left, right, top or bottom");
        return nullptr;
    }
    if (!paint.isCallable() && !build.isCallable()) {
        *error = QStringLiteral("ui.dock: expected a paint(g) or build(root) function");
        return nullptr;
    }

    auto *dock = new QDockWidget(title);
    dock->setObjectName(objectName);
    dock->setFeatures(QDockWidget::DockWidgetMovable | QDockWidget::DockWidgetClosable);
    auto *body = new QWidget(dock);
    auto *layout = new QVBoxLayout(body);
    const int margin = layout::space(layout::Space::One);
    layout->setContentsMargins(margin, margin, margin, margin);
    layout->setSpacing(margin);
    dock->setWidget(body);
    auto *root = new WidgetHandle(host, plugin, QStringLiteral("column"), body, layout);
    QJSEngine::setObjectOwnership(root, QJSEngine::CppOwnership);
    const int minW = std::clamp(spec.value(QStringLiteral("minWidth"), 120).toInt(), 16, 4096);
    const int minH = std::clamp(spec.value(QStringLiteral("minHeight"), 60).toInt(), 16, 4096);
    WidgetHandle *canvas = nullptr;
    if (paint.isCallable()) {
        // Single-canvas shorthand: the canvas fills the dock edge to edge.
        layout->setContentsMargins(0, 0, 0, 0);
        canvas = static_cast<WidgetHandle *>(root->addCanvas(
            QVariantMap{{QStringLiteral("minWidth"), minW}, {QStringLiteral("minHeight"), minH}},
            paint, mouse));
    } else {
        body->setMinimumSize(minW, minH);
    }
    auto *handle = new DockHandle(host, plugin, dock, root, canvas);
    QJSEngine::setObjectOwnership(handle, QJSEngine::CppOwnership);
    host.registerDock(plugin, dock, area);
    if (build.isCallable()) {
        // build(root) runs after the dock is on the window so a script can
        // ask handles for sizes. An exception here still leaves the dock.
        QJSValue rootValue = plugin.engine->newQObject(root);
        host.invoke(plugin, build, {rootValue});
    }
    return handle;
}

} // namespace scripting
