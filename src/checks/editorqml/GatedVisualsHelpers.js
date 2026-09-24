.pragma library

function channels(hex) {
    var v = parseInt(hex.slice(1), 16)
    if (hex.length === 9)
        return [(v >> 16) & 255, (v >> 8) & 255, v & 255, (v >> 24) & 255]
    return [(v >> 16) & 255, (v >> 8) & 255, v & 255, 255]
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
