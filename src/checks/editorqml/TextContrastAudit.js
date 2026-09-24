.pragma library

// Rendered text-contrast audit. Every visible, enabled text item is measured
// against the pixels actually drawn behind it: the text ink comes from the
// item's own color (alpha and inherited opacity composited over the measured
// surface), the surface is the dominant color of the grabbed glyph box. WCAG
// 2.x AA floors: 4.5:1 for body text, 3:1 for large text (>= 24 px, or bold
// >= 18.67 px). Text inside a disabled component is exempt (WCAG 1.4.3).

function linear(channel) {
    var c = channel / 255
    return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
}

function luminance(rgb) {
    return 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2])
}

function contrast(first, second) {
    var a = luminance(first), b = luminance(second)
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
}

function hex(rgb) {
    function h(c) { var s = Math.round(c).toString(16).toUpperCase(); return s.length < 2 ? "0" + s : s }
    return "#" + h(rgb[0]) + h(rgb[1]) + h(rgb[2])
}

function isTextItem(object) {
    return object !== null && typeof object === "object"
        && typeof object.text === "string" && object.color !== undefined
        && object.font !== undefined && object.horizontalAlignment !== undefined
        && object.contentWidth !== undefined && object.mapToItem !== undefined
}

function isPopup(object) {
    return object !== null && typeof object === "object"
        && typeof object.open === "function" && typeof object.close === "function"
        && object.opened !== undefined && object.contentItem !== undefined
        && object.mapToItem === undefined
}

function sceneRoot(item) {
    var root = item
    while (root.parent)
        root = root.parent
    return root
}

function effectiveOpacity(item) {
    var opacity = 1
    for (var it = item; it; it = it.parent)
        opacity *= it.opacity
    return opacity
}

function describe(item) {
    var parts = []
    for (var it = item; it && parts.length < 3; it = it.parent) {
        if (it.objectName && it.objectName.length > 0)
            parts.unshift(it.objectName)
    }
    if (parts.length === 0)
        parts.push(String(item).replace(/\(0x[0-9a-f]+.*$/, ""))
    return parts.join("/")
}

// Text items and popups reachable from `roots`, including popup objects kept
// in `data`, window-level declarations, menu-bar menus, and combo lists.
function collect(roots, texts, popups) {
    var seen = new Set()
    function visit(object) {
        if (!object || typeof object !== "object" || seen.has(object))
            return
        seen.add(object)
        if (isPopup(object)) {
            if (popups.indexOf(object) < 0)
                popups.push(object)
            return
        }
        if (isPopup(object.popup) && popups.indexOf(object.popup) < 0)
            popups.push(object.popup)
        if (isTextItem(object))
            texts.push(object)
        var lists = [object.data, object.contentData, object.menus]
        for (var l = 0; l < lists.length; ++l) {
            var list = lists[l]
            if (!list || typeof list === "string")
                continue
            for (var i = 0; i < list.length; ++i)
                visit(list[i])
        }
    }
    for (var r = 0; r < roots.length; ++r)
        visit(roots[r])
}

// The glyph box of a text item in its window's scene, clipped by every
// clipping ancestor. Null when nothing of it can be seen.
function glyphBox(item, root) {
    var w = Math.min(item.width, Math.max(0, item.contentWidth))
    var h = Math.min(item.height, Math.max(0, item.contentHeight))
    if (w < 1 || h < 1)
        return null
    var x = 0, y = 0
    var halign = item.effectiveHorizontalAlignment !== undefined
        ? item.effectiveHorizontalAlignment : item.horizontalAlignment
    if (halign === Qt.AlignRight)
        x = item.width - w
    else if (halign === Qt.AlignHCenter)
        x = (item.width - w) / 2
    if (item.verticalAlignment === Qt.AlignBottom)
        y = item.height - h
    else if (item.verticalAlignment === Qt.AlignVCenter)
        y = (item.height - h) / 2
    var tl = item.mapToItem(root, x, y)
    var br = item.mapToItem(root, x + w, y + h)
    var box = { x0: tl.x, y0: tl.y, x1: br.x, y1: br.y }
    for (var it = item.parent; it && it !== root; it = it.parent) {
        if (!it.clip)
            continue
        var a = it.mapToItem(root, 0, 0)
        var b = it.mapToItem(root, it.width, it.height)
        box.x0 = Math.max(box.x0, a.x); box.y0 = Math.max(box.y0, a.y)
        box.x1 = Math.min(box.x1, b.x); box.y1 = Math.min(box.y1, b.y)
    }
    box.x0 = Math.max(box.x0, 0); box.y0 = Math.max(box.y0, 0)
    box.x1 = Math.min(box.x1, root.width); box.y1 = Math.min(box.y1, root.height)
    return box.x1 - box.x0 >= 1 && box.y1 - box.y0 >= 1 ? box : null
}

function requiredRatio(item) {
    var px = item.font.pixelSize > 0 ? item.font.pixelSize : item.font.pointSize * 4 / 3
    var bold = item.font.bold || item.font.weight >= 700 // Font.Bold
    return px >= 24 || (bold && px >= 18.67) ? 3.0 : 4.5
}

// Measures one text item against a grab of its window root. Returns null when
// the item is exempt or not drawn, otherwise the measured record.
function measure(item, image, root) {
    if (!item.visible || !item.enabled || item.text.trim().length === 0)
        return null
    var opacity = effectiveOpacity(item) * item.color.a
    if (opacity < 0.05)
        return null
    var box = glyphBox(item, root)
    if (box === null)
        return null
    var scale = image.width / root.width
    var x0 = Math.floor(box.x0 * scale), y0 = Math.floor(box.y0 * scale)
    var x1 = Math.min(image.width, Math.ceil(box.x1 * scale))
    var y1 = Math.min(image.height, Math.ceil(box.y1 * scale))
    // About six full-width scanlines per glyph box, at most ~200 samples each:
    // enough for the dominant surface and to catch glyph stems.
    var rowStride = Math.max(1, Math.floor((y1 - y0) / 6))
    var colStride = Math.max(1, Math.ceil((x1 - x0) / 200))
    var counts = {}, best = null, bestCount = 0
    var samples = []
    for (var py = y0 + Math.floor(rowStride / 2); py < y1; py += rowStride) {
        for (var px = x0; px < x1; px += colStride) {
            var c = image.pixel(px, py)
            var rgb = [Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)]
            samples.push(rgb)
            var key = (rgb[0] << 16) | (rgb[1] << 8) | rgb[2]
            var n = (counts[key] || 0) + 1
            counts[key] = n
            if (n > bestCount) {
                bestCount = n
                best = rgb
            }
        }
    }
    if (best === null)
        return null
    var ink = [item.color.r * 255, item.color.g * 255, item.color.b * 255]
    var fg = [0, 1, 2].map(function(c) { return ink[c] * opacity + best[c] * (1 - opacity) })
    var spread = Math.hypot(fg[0] - best[0], fg[1] - best[1], fg[2] - best[2])
    // A glyph that was actually painted leaves pixels nearer its ink than its
    // surface; text hidden under an opaque sibling leaves none.
    var drawn = spread < 1
    for (var s = 0; s < samples.length && !drawn; ++s) {
        var p = samples[s]
        drawn = Math.hypot(p[0] - fg[0], p[1] - fg[1], p[2] - fg[2]) < spread / 2
    }
    if (!drawn)
        return null
    return {
        item: item, where: describe(item), text: item.text.substring(0, 40),
        fg: hex(fg), bg: hex(best), ratio: contrast(fg, best), required: requiredRatio(item)
    }
}

// Audits every text item under `subtree` (an item) in its window; `seeds`
// contribute further popups (window-level declarations, the menu bar).
// Returns the violations, the number of measured items, and the popups found.
function audit(subtree, grab, seeds) {
    var texts = [], popups = []
    collect([subtree].concat(seeds || []), texts, popups)
    var root = sceneRoot(subtree)
    var image = grab(root)
    var failures = [], measured = 0
    for (var i = 0; i < texts.length; ++i) {
        if (sceneRoot(texts[i]) !== root)
            continue
        var record = measure(texts[i], image, root)
        if (record === null)
            continue
        ++measured
        if (record.ratio + 1e-6 < record.required)
            failures.push(record)
    }
    return { failures: failures, measured: measured, popups: popups }
}

function format(context, record) {
    return context + " | " + record.where + " \"" + record.text + "\" " + record.fg
        + " on " + record.bg + " = " + record.ratio.toFixed(2) + " < " + record.required
}
