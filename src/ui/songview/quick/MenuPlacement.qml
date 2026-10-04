pragma Singleton
import QtQuick

// Item-hosted menus stay inside their host; a submenu opens beside its row,
// flipping left when the right side lacks room.
QtObject {
    function clampAxis(requested: real, size: real, bounds: real): real {
        return Math.max(0, Math.min(requested, bounds - size))
    }

    function clampOrigin(requested: point, width: real, height: real,
                         boundsWidth: real, boundsHeight: real): point {
        return Qt.point(clampAxis(requested.x, width, boundsWidth),
                        clampAxis(requested.y, height, boundsHeight))
    }

    function flyoutOrigin(parentX: real, parentWidth: real, rowY: real, width: real,
                          height: real, boundsWidth: real, boundsHeight: real): point {
        const right = parentX + parentWidth
        return Qt.point(right + width <= boundsWidth ? right : Math.max(0, parentX - width),
                        clampAxis(rowY, height, boundsHeight))
    }
}
