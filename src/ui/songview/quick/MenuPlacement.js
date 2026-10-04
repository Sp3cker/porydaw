.pragma library
// Item-hosted menus stay inside their host; a submenu opens beside its row,
// flipping left when the right side lacks room.

function clampAxis(requested, size, bounds) {
    return Math.max(0, Math.min(requested, bounds - size))
}

function clampOrigin(requested, width, height, boundsWidth, boundsHeight) {
    return Qt.point(clampAxis(requested.x, width, boundsWidth),
                    clampAxis(requested.y, height, boundsHeight))
}

function flyoutOrigin(parentX, parentWidth, rowY, width, height, boundsWidth, boundsHeight) {
    const right = parentX + parentWidth
    return Qt.point(right + width <= boundsWidth ? right : Math.max(0, parentX - width),
                    clampAxis(rowY, height, boundsHeight))
}
