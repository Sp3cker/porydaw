.pragma library

function channels(value) {
    var color = typeof value === "string" ? Qt.color(value) : value
    return [Math.round(color.r * 255), Math.round(color.g * 255),
            Math.round(color.b * 255), Math.round(color.a * 255)]
}

function hexOf(pixel) {
    function h(c) { var s = c.toString(16).toUpperCase(); return s.length < 2 ? "0" + s : s }
    return "#" + h(pixel[0]) + h(pixel[1]) + h(pixel[2])
}

function colorsNear(actual, expected, tol) {
    var t = tol === undefined ? 2 : tol
    for (var i = 0; i < 3; ++i)
        if (Math.abs(actual[i] - expected[i]) > t)
            return false
    return true
}

function isPhysicalBlack(pixel) {
    return pixel[0] <= 16 && pixel[1] <= 16 && pixel[2] <= 16
}

function devicePixel(image, dpr, lx, ly) {
    var dx = Math.floor((lx + 0.5) * dpr)
    var dy = Math.floor((ly + 0.5) * dpr)
    if (dx < 0 || dy < 0 || dx >= image.width || dy >= image.height)
        return null
    return [image.red(dx, dy), image.green(dx, dy), image.blue(dx, dy), image.alpha(dx, dy)]
}

function flatAt(image, dpr, lx, ly) {
    var center = devicePixel(image, dpr, lx, ly)
    if (center === null)
        return null
    for (var y = -1; y <= 1; ++y)
        for (var x = -1; x <= 1; ++x) {
            var p = devicePixel(image, dpr, lx + x, ly + y)
            if (p === null || p[0] !== center[0] || p[1] !== center[1] || p[2] !== center[2])
                return null
        }
    return center
}

function fittedFrameThickness(w, h, requested, inset) {
    return Math.min(requested, Math.max(0, Math.floor((Math.min(w, h) - 1) / 2) - inset))
}

function finite(v) {
    return typeof v === "number" && isFinite(v)
}
