#pragma once

#include <QHash>
#include <QObject>
#include <QString>

namespace ui::hint_profiles {
Q_NAMESPACE

enum class Id {
    Empty = 0,
    TextSelection,
    NativePageStep,
    NativeSingleSelection,
    NativeExtendedSelection,
    NativeContiguousSelection,
    NativeSpinBox,
    NativeSpinEditor,
    NativeFineSpinEditor,
    NativeFinePageStep,
    RollPlot,
    RollGutter,
    HorizontalScroll,
    RulerSweep,
    TrackScope,
    AutomationNode,
    AutomationOriginPhantom,
    AutomationSweep,
    AutomationPencil,
    VelocityBackground,
    VelocityGutter,
    VoiceMarker,
    PitchBendVertex,
    PitchBendBackground,
    EventRows,
    GhostParameter,
    DragScrub,
};
Q_ENUM_NS(Id)

class Catalog
{
  public:
    QString text(Id profile, Qt::KeyboardModifiers stepModifier = Qt::NoModifier);

  private:
    QHash<quint64, QString> m_cache;
};

} // namespace ui::hint_profiles
