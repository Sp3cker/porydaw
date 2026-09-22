import PorydawCore

internal func xcmdPairEvent(_ index: UInt64, _ tick: Tick, _ stream: UInt8,
                            _ controller: UInt8, _ value: UInt8, _ channel: UInt8 = 0) -> Xcmd.Event {
    Xcmd.Event(index: index, tick: tick, stream: stream, controller: controller,
               value: value, channel: channel)
}
