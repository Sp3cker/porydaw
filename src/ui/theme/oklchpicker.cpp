#include "oklchpicker.h"
#include "themeresolver.h"

#include "ui/layout.h"

#include <QMouseEvent>
#include <QPainter>

#include <algorithm>
#include <cmath>

namespace {
constexpr double fullTurn = 360.0;
constexpr double pi = 3.141592653589793238462643383279502884;
constexpr double minimumPairContrast = 3.0;
// Picker geometry and marker-stroke factors, expressed as em fractions of the
// 12 px reference font so proportions survive font scaling.
constexpr double planeInsetEm = 8.0 / 12.0;
constexpr double hueBarWidthEm = 24.0 / 12.0;
constexpr double planeHueGapEm = 10.0 / 12.0;
constexpr double markerOuterRadiusEm = 6.0 / 12.0;
constexpr double markerInnerRadiusEm = 5.0 / 12.0;
constexpr double markerStrokeEm = 2.0 / 12.0;
} // namespace

OklchPicker::OklchPicker(QWidget *parent) : QWidget(parent)
{
    setMinimumSize(::layout::fontPx(27), ::layout::fontPx(18));
    setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
    setMouseTracking(true);
    setFocusPolicy(Qt::NoFocus);
}

void OklchPicker::setSelection(const QColor &selected, const QColor &other, bool hasOther)
{
    const auto nextSelected = selected.isValid() ? selected : QColor(128, 128, 128);
    const auto nextOklch = themes::oklchFromColor(nextSelected);
    const auto nextHasOther = hasOther && other.isValid();
    // Plane pixels depend on hue and the comparison-color constraint; changing
    // only the selected lightness/chroma moves the marker over the same image.
    if (!qFuzzyCompare(m_oklch.hue + 1.0, nextOklch.hue + 1.0) || m_other != other ||
        m_hasOther != nextHasOther)
        m_planeImage = {};
    m_selected = nextSelected;
    m_other = other;
    m_hasOther = nextHasOther;
    m_oklch = nextOklch;
    update();
}

void OklchPicker::paintEvent(QPaintEvent *)
{
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing, false);
    painter.fillRect(rect(), palette().brush(QPalette::Base));

    const PickerRects rects = pickerRects();
    const int hairline = ::layout::singlePixel();
    const qreal markerStroke = ::layout::fontPxF(markerStrokeEm);
    const qreal outerRadius = ::layout::fontPxF(markerOuterRadiusEm);
    const qreal innerRadius = ::layout::fontPxF(markerInnerRadiusEm);

    ensurePlane(rects.plane.size());
    painter.drawImage(rects.plane.topLeft(), m_planeImage);

    // Close the cyclic gradient with hue zero. OKLCh uses [0, 360), so sampled
    // positions below stop just short of the otherwise equivalent 360 endpoint.
    QLinearGradient hueGradient(rects.hue.topLeft(), rects.hue.bottomLeft());
    for (int i = 0; i <= 12; ++i) {
        const double hue = i == 12 ? 0.0 : fullTurn * static_cast<double>(i) / 12.0;
        hueGradient.setColorAt(static_cast<double>(i) / 12.0, inGamutHueColor(hue));
    }
    painter.fillRect(rects.hue, hueGradient);
    painter.save();
    painter.setPen(Qt::NoPen);
    for (int y = 0; y < rects.hue.height(); ++y) {
        themes::Oklch candidate{m_oklch.lightness, m_oklch.chroma,
                                (fullTurn - 1.0e-6) * static_cast<double>(y) /
                                    std::max(1, rects.hue.height() - 1)};
        if (!candidateAllowed(candidate))
            painter.fillRect(rects.hue.left(), rects.hue.top() + y, rects.hue.width(), 1,
                             QColor(0, 0, 0, 120));
    }
    painter.restore();
    painter.setPen(QPen(palette().color(QPalette::Mid), hairline));
    painter.drawRect(rects.plane);
    painter.drawRect(rects.hue);

    // selectionMarkerRect is the canonical marker position; its rect already
    // spans the whole ring, so its center anchors both strokes here.
    const QPointF marker = selectionMarkerRect(rects.plane).center();
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setPen(QPen(Qt::black, markerStroke));
    painter.drawEllipse(marker, outerRadius, outerRadius);
    painter.setPen(QPen(Qt::white, hairline));
    painter.drawEllipse(marker, innerRadius, innerRadius);

    const int hueY = rects.hue.top() + qRound(std::fmod(std::max(0.0, m_oklch.hue), fullTurn) /
                                              fullTurn * (rects.hue.height() - 1));
    const int hueOverhang = ::layout::fontPx(markerStrokeEm);
    painter.setPen(QPen(Qt::black, markerStroke));
    painter.drawLine(rects.hue.left() - hueOverhang, hueY, rects.hue.right() + hueOverhang, hueY);
    painter.setPen(QPen(Qt::white, hairline));
    painter.drawLine(rects.hue.left(), hueY, rects.hue.right(), hueY);
}

void OklchPicker::mousePressEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton) {
        m_dragging = true;
        chooseAt(event->position().toPoint());
        event->accept();
        return;
    }
    QWidget::mousePressEvent(event);
}

void OklchPicker::mouseMoveEvent(QMouseEvent *event)
{
    if (m_dragging && (event->buttons() & Qt::LeftButton)) {
        chooseAt(event->position().toPoint());
        event->accept();
        return;
    }
    QWidget::mouseMoveEvent(event);
}

void OklchPicker::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton) {
        m_dragging = false;
        event->accept();
        return;
    }
    QWidget::mouseReleaseEvent(event);
}

QColor OklchPicker::inGamutHueColor(double hue)
{
    for (auto chroma = 0.18; chroma >= 0.0; chroma -= 0.01) {
        const auto color = themes::colorFromOklch(themes::Oklch{0.7, chroma, hue});
        if (color.isValid())
            return color;
    }
    return QColor(128, 128, 128);
}

void OklchPicker::ensurePlane(const QSize &size)
{
    if (!m_planeImage.isNull() && m_planeImage.size() == size)
        return;
    m_planeImage = QImage(size, QImage::Format_RGB32);
    const auto cosine = std::cos(m_oklch.hue * pi / 180.0);
    const auto sine = std::sin(m_oklch.hue * pi / 180.0);
    const auto otherOpaque = m_other.alpha() == 255;
    const auto otherLuminance = themes::relativeLuminance(m_other);
    for (int y = 0; y < m_planeImage.height(); ++y) {
        const auto lightness =
            1.0 - static_cast<double>(y) / std::max(1, m_planeImage.height() - 1);
        auto *pixels = reinterpret_cast<QRgb *>(m_planeImage.scanLine(y));
        for (int x = 0; x < m_planeImage.width(); ++x) {
            const auto chroma =
                0.4 * static_cast<double>(x) / std::max(1, m_planeImage.width() - 1);
            const auto alternate = ((x + y) / 4) % 2 == 0;
            themes::SrgbSample sample;
            const auto lab = themes::Oklab{lightness, chroma * cosine, chroma * sine};
            if (!themes::sampleSrgb(lab, sample)) {
                pixels[x] = alternate ? qRgb(96, 96, 96) : qRgb(176, 176, 176);
                continue;
            }
            if (m_hasOther && (!otherOpaque || themes::contrastRatioFromLuminance(
                                                   themes::relativeLuminance(sample),
                                                   otherLuminance) < minimumPairContrast)) {
                pixels[x] = alternate ? qRgb(64, 64, 64) : qRgb(232, 232, 232);
                continue;
            }
            pixels[x] = qRgb(sample.red, sample.green, sample.blue);
        }
    }
}

OklchPicker::PickerRects OklchPicker::pickerRects() const
{
    const int inset = ::layout::fontPx(planeInsetEm);
    const int hueWidth = ::layout::fontPx(hueBarWidthEm);
    const int gap = ::layout::fontPx(planeHueGapEm);
    const QRect plane(inset, inset, std::max(1, width() - hueWidth - gap - 2 * inset),
                      std::max(1, height() - 2 * inset));
    // Inclusive QRect edges: the hue bar starts one gap past the plane's
    // right edge.
    const QRect hue(plane.right() + gap, plane.top(), hueWidth, plane.height());
    return {plane, hue};
}

QRect OklchPicker::selectionMarkerRect(const QRect &plane) const
{
    // Full repaint coverage: the outer radius plus half the black stroke and
    // one logical pixel of antialias bleed, rounded outward.
    const qreal coverage = ::layout::fontPxF(markerOuterRadiusEm) +
                           ::layout::fontPxF(markerStrokeEm) / 2.0 + ::layout::singlePixel();
    const int half = static_cast<int>(std::ceil(coverage));
    const double chroma = std::clamp(m_oklch.chroma, 0.0, maxChroma);
    const double lightness = std::clamp(m_oklch.lightness, 0.0, 1.0);
    const QPoint marker(plane.left() + qRound(chroma / maxChroma * (plane.width() - 1)),
                        plane.top() + qRound((1.0 - lightness) * (plane.height() - 1)));
    return {marker.x() - half, marker.y() - half, 2 * half + 1, 2 * half + 1};
}

bool OklchPicker::candidateAllowed(const themes::Oklch &candidate, QColor *converted) const
{
    const QColor color = themes::colorFromOklch(candidate);
    if (!color.isValid())
        return false;
    if (m_hasOther && !themes::isValidColorPair(color, m_other))
        return false;
    if (converted)
        *converted = color;
    return true;
}

void OklchPicker::chooseAt(const QPoint &point)
{
    const PickerRects rects = pickerRects();
    const QRect previousMarker = selectionMarkerRect(rects.plane);
    themes::Oklch candidate = m_oklch;
    if (rects.plane.contains(point)) {
        candidate.lightness = 1.0 - std::clamp(static_cast<double>(point.y() - rects.plane.top()) /
                                                   std::max(1, rects.plane.height() - 1),
                                               0.0, 1.0);
        candidate.chroma =
            maxChroma * std::clamp(static_cast<double>(point.x() - rects.plane.left()) /
                                       std::max(1, rects.plane.width() - 1),
                                   0.0, 1.0);
    } else if (rects.hue.contains(point)) {
        // Keep the bottom pixel inside the [0, 360) hue domain.
        candidate.hue =
            (fullTurn - 1.0e-6) * std::clamp(static_cast<double>(point.y() - rects.hue.top()) /
                                                 std::max(1, rects.hue.height() - 1),
                                             0.0, 1.0);
    } else {
        return;
    }

    QColor color;
    if (!candidateAllowed(candidate, &color))
        return;
    const bool hueChanged = !qFuzzyCompare(m_oklch.hue + 1.0, candidate.hue + 1.0);
    m_oklch = candidate;
    m_selected = color;
    if (hueChanged) {
        m_planeImage = {};
        update();
    } else {
        // selectionMarkerRect already spans ring, stroke and antialias bleed,
        // so the union alone covers both marker positions.
        update(previousMarker.united(selectionMarkerRect(rects.plane)));
    }
    emit colorSelected(color);
}
