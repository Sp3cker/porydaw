#pragma once

#include "checks/visual/visualbaseline.h"

#include <QImage>
#include <QList>
#include <QRect>
#include <QString>

class QQuickItem;
class QQuickWindow;
class SongView;

// Shared capture and popup helpers for the Qt Quick frozen-appearance
// baselines. Quick surfaces carry their own window, so a scenario grabs the
// framebuffer after a settled frame and freezes semantic regions from item
// scene geometry; popup content arrives asynchronously through the canvas'
// session, so opening waits live here rather than in each suite.
namespace checks::visual {

/// Grabs `window` after its scene has rendered: waits for exposure and a
/// requested frame, then grabWindow(). Returns a null image and, when `error`
/// is given, a description of why: the window never exposed, or the
/// framebuffer grab came back empty.
QImage grabQuick(QQuickWindow &window, QString *error);

/// Scene-space rectangle of the named item below `root` (visual-descendant
/// scan, so reparented QML delegates are found). Empty when the item is
/// absent or has no extent; visibility is not required because transparent
/// input items still own real bounds.
QRect quickItemBounds(QQuickItem *root, const QString &objectName);

/// `quickItemBounds` as a semantic region; bounds are empty when the item is
/// absent, so a scenario can pre-check or let compare() fail on them.
Region quickItemRegion(const QString &name, QQuickItem *root, const QString &objectName);

/// Grabs `window` and compares it against frozen baseline `id` with `regions`,
/// requiring every region to have visible bounds. `root` is the scenario's
/// scene root; the comparison reads only `window` and `regions`, whose bounds
/// are already in image coordinates. Returns true on match; on failure `error`
/// describes the first problem instead of failing the test.
bool expectQuickBaseline(const QString &id, QQuickWindow &window, QQuickItem *root,
                         const QList<Region> &regions, QString *error);

/// The live popup session's content item once `view`'s canvas opens a prompt,
/// or null when no session opens in time. Waits for the session and its
/// content slot together, so a callback-deferred open cannot race the caller.
QQuickItem *awaitPopupForm(SongView &view);

/// The live menu level's `quickMenuPanelRoot` once `view`'s canvas opens a
/// menu, or null. Panels are item-children of the session overlay but
/// QObject-children of the menu host, so findChild cannot reach them; the
/// overlay's visual children are scanned instead.
QQuickItem *awaitMenuPanel(SongView &view);

/// Moves focus off a blinking text field onto the steady control named
/// `objectName` inside `form` before the grab; an empty name leaves focus
/// untouched. Fails the test when `form` is missing or the named control does
/// not exist, so an unparked caret is never mistaken for a rendering defect.
void steadyPopupFocus(QQuickItem *form, const QString &objectName);

} // namespace checks::visual
