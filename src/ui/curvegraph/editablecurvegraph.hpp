#pragma once

#include <QColor>
#include <QFocusEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPaintEvent>
#include <QPoint>
#include <QPointF>
#include <QRect>
#include <QString>
#include <QWheelEvent>
#include <QWidget>
#include <functional>
#include <optional>
#include <vector>
#include <variant>

class QPainter;

namespace songview {

struct CurvePoint {
    double x = 0.0;
    double y = 0.0;
};

struct CurveColors {
    QColor background;
    QColor grid;
    QColor separator;
    QColor curve;
    QColor endpoint;
    QColor focus;
    QColor previewOutline;
    QColor text;
};

class EditableCurveGraph final : public QWidget
{
  public:
    enum class Sampling { Normal, Fine };
    enum class CurveAxisMapping { Linear, BipolarCenter };

    struct CurveAxisSpec {
        double minimum = 0.0;
        double maximum = 1.0;
        CurveAxisMapping mapping = CurveAxisMapping::Linear;
        double quantizationStep = 0.0;
        int zeroDetentPixels = 0;
    };

    struct CurveSamplingPolicy {
        double endpointInset = 1.0;
        double interiorStep = 1.0;
        std::function<double(double, Sampling)> snap;
        std::function<double(double, Sampling)> nextSample;
        std::function<double(Sampling)> lastEditable;
    };

    struct CurveSegmentPolicy {
        double linearSampleSpacing = 0.0;
        bool allLinear = false;
    };

    struct CurveTextPolicy {
        QString zeroLabel;
        bool showZeroLabel = false;
        std::function<QString(double)> formatLiveValue;
        std::function<QString(bool)> formatRangeLimit;
    };

    struct CurveSpec {
        CurveAxisSpec xAxis;
        CurveAxisSpec yAxis;
        double defaultY = 0.0;
        bool lockStartEndpointY = false;
        CurveSamplingPolicy sampling;
        CurveSegmentPolicy segments;
        QRect canvasRect = QRect(52, 44, 280, 112);
        QString title;
        QString startLabel;
        QString endLabel;
        std::vector<double> gridLines;
        CurveTextPolicy text;
        CurveColors colors;
        std::function<bool(const QKeyEvent &)> matchesAuditionKey;
    };

    struct Callbacks {
        std::function<void()> previewChanged;
        std::function<void()> commitRequested;
        std::function<void()> cancelRequested;
        std::function<void()> auditionRequested;
        std::function<void(int)> wheelChanged;
    };

    explicit EditableCurveGraph(CurveSpec spec, QWidget *parent = nullptr);

    void setSpec(CurveSpec spec);
    void setPoints(std::vector<CurvePoint> points);
    const std::vector<CurvePoint> &points() const;
    void resetCurve();
    std::optional<double> selectedX() const;
    void setSelectedX(std::optional<double> x);
    std::optional<CurvePoint> hitTest(const QPointF &position) const;
    bool removeSelectedPoint();
    QPoint pointPosition(const CurvePoint &point) const;
    void setKeyboardFraction(double fraction);
    void cancelGesture();
    bool handleKeyPress(QKeyEvent *event);
    void setCallbacks(Callbacks callbacks);

    QRect canvasRect() const;
    bool hasGesture() const;
    double liveValue() const;

  protected:
    void paintEvent(QPaintEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;

  private:
    enum class StrokeMode { Freehand, AngledLine };

    struct StrokeState {
        StrokeMode mode = StrokeMode::Freehand;
        std::vector<CurvePoint> snapshot;
        double anchorX = 0.0;
        double anchorY = 0.0;
        double previousX = 0.0;
        double previousY = 0.0;
    };

    struct VertexDragState {
        std::vector<CurvePoint> snapshot;
        QPointF pressPosition;
        double originalX = 0.0;
        bool hasMoved = false;
    };

    static constexpr int kAxisGutter = 52;
    static constexpr int kAxisLabelHeight = 20;
    static constexpr int kNodeHitRadius = 8;
    static constexpr int kNodePaintRadius = 3;
    static constexpr int kSelectedNodeRingRadius = 6;

    void paintGrid(QPainter &painter);
    void paintCurve(QPainter &painter);
    void paintAxes(QPainter &painter);
    void paintFocus(QPainter &painter);
    void updateGesture(const QPointF &position, Qt::KeyboardModifiers modifiers);
    void updateStroke(const QPointF &position);
    void updateVertexDrag(const QPointF &position, Qt::KeyboardModifiers modifiers);
    void finishGesture();
    void replaceSegment(double x0, double y0, double x1, double y1, Sampling sampling);
    void materializeEndpoints();
    bool isLineGesture() const;
    bool isLinearSegment(double x0, double x1) const;
    Sampling gestureSampling() const;
    double tickAtFraction(double fraction, Sampling sampling) const;
    double xAtPosition(qreal x, Sampling sampling) const;
    double yAt(qreal y) const;
    double endpointValue() const;
    double valueAtX(double x) const;
    double minimumInteriorX() const;
    double maximumInteriorX() const;
    double snapX(double x, Sampling sampling) const;
    double nextSampleX(double x, Sampling sampling) const;
    double lastEditableX(Sampling sampling) const;
    double valueAtPixel(qreal pixel, const CurveAxisSpec &axis, bool vertical) const;
    int pixelAtValue(double value, const CurveAxisSpec &axis, bool vertical) const;
    double quantizeAxisValue(double value, const CurveAxisSpec &axis) const;
    double bipolarFractionAtValue(double value, const CurveAxisSpec &axis) const;
    double bipolarValueAtFraction(double fraction, const CurveAxisSpec &axis) const;
    int pixelX(double x) const;
    int pixelY(double y) const;
    void insertOrReplace(double x, double y);
    void sortPoints();

    CurveSpec m_spec;
    std::vector<CurvePoint> m_points;
    double m_keyboardX = 0.0;
    double m_liveValue = 0.0;
    double m_rangeWheelRemainder = 0.0;
    std::variant<std::monostate, StrokeState, VertexDragState> m_gesture;
    std::optional<double> m_selectedX;
    Callbacks m_callbacks;
};
} // namespace songview
