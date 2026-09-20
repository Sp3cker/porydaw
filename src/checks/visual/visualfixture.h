#pragma once

#include "checks/visual/visualbaseline.h"

#include <QList>
#include <QRect>
#include <QString>

class QAbstractItemView;
class QWidget;

// Shared scenario helpers for the QWidget frozen-appearance baselines: region
// lookup for named production children, focus parking before a grab, and the
// common compare path. One definition per semantic rule, so every suite pins
// the same bounds for the same surface and a converted surface can supply
// identical regions from its replacement renderer.
namespace checks::visual {

/// Rendered bounds of `child` inside the grabbed `root` image: the child's
/// visibleRegion (already clipped by ancestor viewports and masks) mapped into
/// root coordinates and intersected with root's rect. Empty when the child
/// paints nothing inside root — hidden, or scrolled fully out of its viewport.
Region childRegion(const QString &name, QWidget &root, const QWidget &child);

/// Appends the rendered region of the named descendant; false when no such
/// descendant exists, so the caller can QVERIFY with a useful message. A child
/// that exists but paints nothing contributes no region and still returns true.
bool appendNamedRegion(QList<Region> &regions, const QString &name, QWidget &root,
                       const QString &objectName);

/// Appends a structural child's rendered region; false when `child` is absent
/// or paints nothing — required chrome must fail setup, not silently skip.
bool appendRequiredRegion(QList<Region> &regions, const QString &name, QWidget &root,
                          const QWidget *child);

/// Parks focus on stable non-input chrome so no blinking caret lands in the
/// grab: a tab bar, else the dialog button box's Cancel button, else the first
/// push button. When no anchor exists, drops focus held by `widget` or one of
/// its descendants (QWidget::clearFocus alone cannot move a descendant's
/// focus) and pumps events.
void parkFocus(QWidget &widget);

/// Shows a top-level widget and settles it for capture: show, processEvents,
/// re-apply the requested size (Qt shrinks a first-shown top-level to the
/// available screen geometry), processEvents, then parkFocus.
void showSettled(QWidget &widget);

/// Merges caller subregions over automatic ones; a name present in
/// `overrides` wins, so a scenario can re-pin a named widget under a stable
/// semantic identifier.
QList<Region> mergeRegions(const QList<Region> &base, const QList<Region> &overrides);

/// The field widget a QFormLayout places beside the row whose label reads
/// `labelText`, with mnemonic '&' stripped from both sides. Null when no row
/// matches; the first matching row in the first matching form wins.
QWidget *formField(QWidget &container, const QString &labelText);

/// Appends the rendered region of a form field identified by its row label;
/// false when the row or its field is absent. A field scrolled out of its
/// viewport contributes no region and still returns true — it renders no
/// pixels in the grab.
bool appendFieldRegion(QList<Region> &regions, const QString &name, QWidget &root,
                       QWidget &container, const QString &labelText);

/// Appends the rendered region of a checkbox identified by its text; false
/// when no checkbox carries that text or it paints nothing.
bool appendCheckRegion(QList<Region> &regions, const QString &name, QWidget &root,
                       QWidget &container, const QString &text);

/// Assigns a semantic object name in the test only, for production children
/// that ship without one; widgetRegions() then picks them up automatically.
/// A child that already has a name keeps it.
void nameChild(QWidget *child, const QString &name);

/// The shared listPositionIndicator scrollbar name is not unique once several
/// lists live in one capture: rescope each to its owning list's object name so
/// every region stays semantically distinct.
void scopeIndicatorNames(QWidget &root);

/// Item rects report the full content row even when the viewport clips it;
/// this freezes the actually rendered (viewport-clipped) rect instead.
QRect clippedItemRect(QAbstractItemView &view, const QRect &itemRect);

/// Compares the shown widget against its frozen baseline using the automatic
/// named descendant regions merged with `extra` (semantic names win). Fails the
/// test through QVERIFY2 carrying the comparator's message.
void compareShown(const QString &id, QWidget &widget, const QList<Region> &extra);

} // namespace checks::visual
