#!/usr/bin/env python3
"""Regenerate the UI icon font from resources/icons/manifest.json.

Usage: python3 tools/gen_ui_icons.py --fontawesome <fontawesome-pro-5.x-desktop dir>

Outputs:
  resources/icons/PorydawIcons.otf  one CFF font: Font Awesome glyphs copied from their
                                    style's face plus custom glyphs from resources/icons/sources
  src/ui/icons/Icons.qml            QML singleton mapping each key to its codepoint

Every icon is a glyph, so the app loads no images (and no Qt image plugins) for icons.
Codepoints are pinned in the manifest's "codepoints"; a new key takes the next one above
the highest pin and is pinned there. Requires fontTools.
"""

import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

from fontTools.fontBuilder import FontBuilder
from fontTools.misc.timeTools import epoch_diff
from fontTools.misc.transform import Transform
from fontTools.pens.basePen import BasePen
from fontTools.pens.boundsPen import ControlBoundsPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.reverseContourPen import ReverseContourPen
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.transformPen import TransformPen
from fontTools.svgLib.path import parse_path
from fontTools.ttLib import TTFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
ICONS = os.path.join(ROOT, "resources", "icons")
MANIFEST = os.path.join(ICONS, "manifest.json")
FONT_OUT = os.path.join(ICONS, "PorydawIcons.otf")
QML_OUT = os.path.join(ROOT, "src", "ui", "icons", "Icons.qml")

FAMILY, PS_NAME = "Porydaw Icons", "PorydawIcons"
FIRST_CODEPOINT = 0xE000
# Font Awesome's em: one 512-unit line from descender -64 to ascender 448.
EM, ASCENT, DESCENT = 512, 448, -64
FACES = {
    "solid": "Font Awesome 5 Pro-Solid-900.otf",
    "regular": "Font Awesome 5 Pro-Regular-400.otf",
    "light": "Font Awesome 5 Pro-Light-300.otf",
}
SVG_NS = "{http://www.w3.org/2000/svg}"


def fontawesome_glyphs(fa_dir, style, icons, metadata):
    """Record each named icon's outline and advance from the style's face."""
    face = TTFont(os.path.join(fa_dir, "otfs", FACES[style]))
    if face["head"].unitsPerEm != EM:
        sys.exit(f"{FACES[style]} has unitsPerEm {face['head'].unitsPerEm}, expected {EM}")
    cmap, glyph_set, hmtx = face.getBestCmap(), face.getGlyphSet(), face["hmtx"]
    glyphs = {}
    for key, fa_name in icons.items():
        entry = metadata.get(fa_name)
        if entry is None or style not in entry["styles"]:
            sys.exit(f"Font Awesome has no {style} icon named {fa_name!r} (key {key!r})")
        name = cmap[int(entry["unicode"], 16)]
        outline = RecordingPen()
        glyph_set[name].draw(outline)
        glyphs[key] = (outline, hmtx[name][0])
    return glyphs


def parse_matrix(text):
    match = re.fullmatch(r"\s*matrix\(([^)]*)\)\s*", text)
    if not match:
        sys.exit(f"unsupported SVG transform {text!r}; only matrix(...) is handled")
    return Transform(*(float(v) for v in re.split(r"[\s,]+", match.group(1).strip())))


def style_value(element, name):
    if name in element.attrib:
        return element.attrib[name]
    for declaration in element.get("style", "").split(";"):
        prop, _, value = declaration.partition(":")
        if prop.strip() == name:
            return value.strip()
    return None


def svg_paths(element, transform, fill_rule):
    """Yield (path data, transform, fill rule) for every path, composing ancestor state."""
    if element.get("transform"):
        transform = transform.transform(parse_matrix(element.get("transform")))
    fill_rule = style_value(element, "fill-rule") or fill_rule
    tag = element.tag.removeprefix(SVG_NS)
    if tag == "path":
        yield element.get("d"), transform, fill_rule
    elif tag not in ("svg", "g"):
        sys.exit(f"unsupported SVG element <{tag}>; convert shapes to paths")
    for child in element:
        yield from svg_paths(child, transform, fill_rule)


class PolygonPen(BasePen):
    """Flattens a contour into polygon points, sampling each curve segment."""

    STEPS = 8

    def __init__(self):
        super().__init__(None)
        self.points = []

    def _moveTo(self, point):
        self.points.append(point)

    def _lineTo(self, point):
        self.points.append(point)

    def _curveToOne(self, c1, c2, end):
        (x0, y0), steps = self._getCurrentPoint(), self.STEPS
        for i in range(1, steps + 1):
            t = i / steps
            a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
            self.points.append((a * x0 + b * c1[0] + c * c2[0] + d * end[0],
                                a * y0 + b * c1[1] + c * c2[1] + d * end[1]))

    def _qCurveToOne(self, control, end):
        (x0, y0), steps = self._getCurrentPoint(), self.STEPS
        for i in range(1, steps + 1):
            t = i / steps
            a, b, c = (1 - t) ** 2, 2 * (1 - t) * t, t * t
            self.points.append((a * x0 + b * control[0] + c * end[0],
                                a * y0 + b * control[1] + c * end[1]))


def contour_points(contour):
    pen = PolygonPen()
    replay(contour, pen)
    return pen.points


def signed_area(points):
    return sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(points, points[1:] + points[:1])) / 2


def contains(polygon, point):
    x, y = point
    inside = False
    for (x0, y0), (x1, y1) in zip(polygon, polygon[1:] + polygon[:1]):
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            inside = not inside
    return inside


def split_contours(recording):
    """One contour per subpath: each starts at a moveTo, closed or not."""
    contours = []
    for operator, args in recording.value:
        if operator == "moveTo" or not contours or contours[-1][-1][0] in ("closePath", "endPath"):
            contours.append([])
        contours[-1].append((operator, args))
    return contours


def replay(contour, pen):
    for operator, args in contour:
        getattr(pen, operator)(*args)


def nonzero_evenodd(recording, pen):
    """Orient contours by nesting depth so nonzero filling matches even-odd filling."""
    contours = split_contours(recording)
    polygons = [contour_points(c) for c in contours]
    for index, (contour, polygon) in enumerate(zip(contours, polygons)):
        depth = sum(contains(other, polygon[0])
                    for other_index, other in enumerate(polygons) if other_index != index)
        wants_positive = depth % 2 == 0
        if (signed_area(polygon) > 0) == wants_positive:
            replay(contour, pen)
        else:
            replay(contour, ReverseContourPen(pen))


def custom_glyph(svg_name):
    """Record an SVG's filled paths in font units, its viewBox scaled onto the em."""
    root = ET.parse(os.path.join(ICONS, "sources", svg_name)).getroot()
    min_x, min_y, width, height = (float(v) for v in root.get("viewBox").split())
    scale = EM / height
    # SVG y grows downward; the viewBox top lands on the ascender.
    to_font = Transform(scale, 0, 0, -scale, -min_x * scale, ASCENT + min_y * scale)
    outline = RecordingPen()
    for data, transform, fill_rule in svg_paths(root, Transform(), "nonzero"):
        path = RecordingPen()
        parse_path(data, TransformPen(path, to_font.transform(transform)))
        if fill_rule == "evenodd":
            nonzero_evenodd(path, outline)
        else:
            path.replay(outline)
    return outline, round(width * scale)


def assign_codepoints(keys, pinned):
    """Pinned keys keep their codepoint; new keys take the next ones above the highest pin."""
    codepoints = {key: int(pinned[key], 16) for key in keys if key in pinned}
    if len(set(codepoints.values())) != len(codepoints):
        sys.exit("two icons pin the same codepoint")
    following = max(codepoints.values(), default=FIRST_CODEPOINT - 1) + 1
    for key in sorted(set(keys) - set(codepoints)):
        codepoints[key], following = following, following + 1
    return codepoints


def build_font(glyphs, codepoints):
    keys = sorted(glyphs, key=codepoints.get)
    charstrings, metrics = {}, {}
    notdef = T2CharStringPen(EM, None)
    charstrings[".notdef"], metrics[".notdef"] = notdef.getCharString(), (EM, 0)
    for key in keys:
        outline, advance = glyphs[key]
        bounds = ControlBoundsPen(None)
        outline.replay(bounds)
        pen = T2CharStringPen(advance, None)
        outline.replay(pen)
        charstrings[key] = pen.getCharString()
        metrics[key] = (advance, round(bounds.bounds[0]) if bounds.bounds else 0)

    builder = FontBuilder(EM, isTTF=False)
    # A fixed timestamp (1970-01-01) keeps regeneration byte-identical.
    builder.updateHead(created=-epoch_diff, modified=-epoch_diff)
    builder.font.recalcTimestamp = False
    builder.setupGlyphOrder([".notdef"] + keys)
    builder.setupCharacterMap({codepoints[key]: key for key in keys})
    builder.setupCFF(PS_NAME, {"FullName": FAMILY, "FamilyName": FAMILY}, charstrings, {})
    builder.setupHorizontalMetrics(metrics)
    builder.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT, lineGap=0)
    builder.setupNameTable({"familyName": FAMILY, "styleName": "Regular",
                            "uniqueFontIdentifier": PS_NAME, "fullName": FAMILY,
                            "psName": PS_NAME})
    # One em of line height everywhere (fsSelection USE_TYPO_METRICS), so glyphs centre alike.
    builder.setupOS2(version=4, sTypoAscender=ASCENT, sTypoDescender=DESCENT, sTypoLineGap=0,
                     usWinAscent=ASCENT, usWinDescent=-DESCENT, fsSelection=0x40 | 0x80,
                     achVendID="PRDW")
    builder.setupPost()
    builder.save(FONT_OUT)


def qml_singleton(glyphs, codepoints):
    lines = [
        "// Generated by tools/gen_ui_icons.py from resources/icons/manifest.json; do not edit.",
        "pragma Singleton",
        "import QtQuick",
        "",
        "QtObject {",
        f'    readonly property string family: "{FAMILY}"',
    ]
    for key in sorted(glyphs):
        # Wide glyphs shrink to fit a square box, exactly as their SVG viewBox did.
        fit = min(1.0, EM / glyphs[key][1])
        lines.append(f'    readonly property var {key}: ({{ glyph: "\\u{codepoints[key]:04x}", '
                     f"fit: {fit:.4f} }})")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fontawesome", required=True,
                        help="Font Awesome Pro 5 desktop package (contains otfs/ and metadata/)")
    args = parser.parse_args()

    with open(MANIFEST) as handle:
        manifest = json.load(handle)
    with open(os.path.join(args.fontawesome, "metadata", "icons.json")) as handle:
        metadata = json.load(handle)

    glyphs = {}
    sources = [(style, icons) for style, icons in manifest["fontAwesome"].items()]
    for style, icons in sources:
        for key, glyph in fontawesome_glyphs(args.fontawesome, style, icons, metadata).items():
            if key in glyphs:
                sys.exit(f"duplicate icon key {key!r}")
            glyphs[key] = glyph
    for key, svg_name in manifest["custom"].items():
        if key in glyphs:
            sys.exit(f"duplicate icon key {key!r}")
        glyphs[key] = custom_glyph(svg_name)

    codepoints = assign_codepoints(glyphs, manifest.get("codepoints", {}))
    build_font(glyphs, codepoints)
    manifest["codepoints"] = {key: f"{codepoints[key]:04X}"
                              for key in sorted(codepoints, key=codepoints.get)}
    with open(MANIFEST, "w") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")
    os.makedirs(os.path.dirname(QML_OUT), exist_ok=True)
    with open(QML_OUT, "w") as handle:
        handle.write(qml_singleton(glyphs, codepoints))
    print(f"regenerated {len(glyphs)} icons: {', '.join(sorted(glyphs))}")


if __name__ == "__main__":
    main()
