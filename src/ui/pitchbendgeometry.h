#pragma once

#include <QRect>
#include <QSize>
#include <QtGlobal>

class QFont;

namespace songview {

// resolve() stays in the Widgets-linked pitchbendgraph_render.cpp.
struct PitchBendGeometry {
    static PitchBendGeometry resolve(const QFont &font, qreal dpr);

    QSize popupSize;
    int headerHeight = 0;
    int graphHeight = 0;
    int outerInset = 0;
    int titleHeight = 0;
    int descriptionHeight = 0;
    int controlsHeight = 0;
    int fieldWidth = 0;
    int fieldHeight = 0;
    int resetWidth = 0;
    int resetHeight = 0;
    int axisLabelHeight = 0;
    QRect canvas; // Graph-local canvas rectangle; labels align around it.
    qreal zeroDetent = 0.0;
    qreal nodeHitRadius = 0.0;
    qreal nodePaintRadius = 0.0;
    qreal selectedRingRadius = 0.0;
    qreal curveStroke = 0.0;
    qreal scrubThreshold = 0.0;
    qreal hairline = 0.0;
};

} // namespace songview
