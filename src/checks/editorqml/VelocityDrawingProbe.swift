import Foundation
import NativeDisplayList
import PorydawAppPresentation

@testable import PorydawApp

@MainActor
func velocityDrawingJSON(_ page: VelocityPage?) -> String {
    guard let page else { return "{}" }
    var records: [String] = []
    let data = page.displayList(list: 0)
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        var view = PdDlView()
        guard pd_dl_decode(raw.baseAddress, raw.count, &view), let header = view.header else { return }
        for index in 0..<Int(header.pointee.rectCount) {
            let rect = view.rects[index]
            guard rect.id != 0 else { continue }
            records.append(
                """
                {"id":"\(rect.id)","x":\(rect.x),"y":\(rect.y),"w":\(rect.w),"h":\(rect.h),
                "argb":\(rect.argb),"flags":\(rect.flags),"strokeWidth":\(rect.strokeWidth)}
                """)
        }
    }
    let geometry = VelocityNodeGeometry(baseFontPx: page.baseFontPx, devicePixelRatio: page.devicePixelRatio)
    let handles = page.publishedHandlesSnapshot.map { (handle: VelocityHandle) -> String in
        """
        {"noteIdText":"\(handle.noteID.rawValue)","tick":\(handle.tick),"endTick":\(handle.endTick),
        "x":\(handle.x),"endX":\(handle.endX),"y":\(handle.y),"value":\(handle.value),
        "selected":\(handle.selected),"hovered":\(handle.hovered),"preview":\(handle.preview),
        "dimmed":\(handle.dimmed),"outlineWidth":\(geometry.nodeOutlineDipWidth / page.devicePixelRatio),"hitRadius":\(geometry.hitRadius)}
        """
    }
    return "{\"records\":[\(records.joined(separator: ","))],\"handles\":[\(handles.joined(separator: ","))]}"
}
