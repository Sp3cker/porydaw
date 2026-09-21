import QtQml

QtObject {
    // Numeric contract from ui/mousehints/hintprofiles.h.
    enum Id {
        Empty = 0,
        TextSelection = 1,
        NativePageStep = 2,
        NativeSingleSelection = 3,
        NativeExtendedSelection = 4,
        NativeContiguousSelection = 5,
        NativeSpinBox = 6,
        NativeSpinEditor = 7,
        NativeFineSpinEditor = 8,
        NativeFinePageStep = 9,
        RollPlot = 10,
        RollGutter = 11,
        HorizontalScroll = 12,
        RulerSweep = 13,
        TrackScope = 14,
        AutomationNode = 15,
        AutomationOriginPhantom = 16,
        AutomationSweep = 17,
        AutomationPencil = 18,
        VelocityBackground = 19,
        VelocityGutter = 20,
        VoiceMarker = 21,
        PitchBendVertex = 22,
        PitchBendBackground = 23,
        EventRows = 24,
        GhostParameter = 25,
        DragScrub = 26,
        TapTempo = 27
    }
}
