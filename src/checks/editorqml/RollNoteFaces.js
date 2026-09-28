.pragma library

function face(renderer, id) {
    if (!renderer)
        return null
    var f = renderer.noteFace("gridNote_" + id)
    if (!f || f.width === undefined || !(f.width > 0) || !(f.height > 0))
        return null
    return f
}

function rect(renderer, target, id) {
    var f = face(renderer, id)
    if (!f)
        return null
    var p = renderer.mapToItem(target, f.x, f.y)
    return { x: p.x, y: p.y, width: f.width, height: f.height, fill: f.fill }
}

function center(renderer, target, id) {
    var r = rect(renderer, target, id)
    return r ? Qt.point(r.x + r.width / 2, r.y + r.height / 2) : null
}

function point(renderer, target, id, dx, dy) {
    var r = rect(renderer, target, id)
    return r ? Qt.point(r.x + dx, r.y + dy) : null
}

function grab(testCase, item) {
    var root = item
    while (root.parent)
        root = root.parent
    testCase.wait(0)
    var image = testCase.grabImage(root)
    var dpr = image.width / root.width
    var origin = item.mapToItem(root, 0, 0)
    var ox = Math.round(origin.x * dpr)
    var oy = Math.round(origin.y * dpr)
    return {
        width: Math.round(item.width * dpr),
        height: Math.round(item.height * dpr),
        red: function(x, y) { return image.red(x + ox, y + oy) },
        green: function(x, y) { return image.green(x + ox, y + oy) },
        blue: function(x, y) { return image.blue(x + ox, y + oy) },
        alpha: function(x, y) { return image.alpha(x + ox, y + oy) },
        pixel: function(x, y) { return image.pixel(x + ox, y + oy) }
    }
}
