# Pinned Tempo lane completion record

Superseded by [`tempo-slot-plan.md`](tempo-slot-plan.md), the authoritative
implementation and behavior record.

The abandoned standalone `songview::TempoStrip` design was not shipped. Tempo
remains `AutomationCanvas` node-stack slot 0 and is painted and routed as the
drawer viewport's sticky bottom layer.
