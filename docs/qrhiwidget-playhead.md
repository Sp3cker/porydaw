# QRhiWidget for the playhead overlay

Status: superseded investigation, 2026-07-24

## Conclusion

This document records the investigation that preceded the current renderer
decision. It is not the production architecture.

The implemented split is:

- macOS: Core Animation.
- Windows and Linux: the current QPainter path.

`QRhiWidget` remains a possible bounded Linux experiment, and DirectComposition
remains a possible Windows experiment. Neither is part of the implemented
playhead architecture. The renderer selection in `CMakeLists.txt` is canonical.

The investigation found that `QRhiWidget` fixes one important part of the
non-macOS path: when only the `QRhiWidget` changes, Qt skips ordinary
backing-store repaint and reuses the cached backing-store texture. It does not
provide compositor-only movement. Every playhead move still renders the
widget's backing texture, then performs a full top-level QRhi composition and
present. DirectComposition and Core Animation can move an existing visual
without either render pass.

## Fit with the current code

`SongView::syncPlayheadOverlay()` computes one fractional timeline position and
submits it to `PlayheadOverlay::setPlayhead()`
([`src/ui/songview.cpp`](../src/ui/songview.cpp)). `PlayheadOverlay` already owns
the four source widgets, their timeline origins, visible clipping, theme state,
playing state, and event-list triangle direction
([`src/ui/playheadoverlay.cpp`](../src/ui/playheadoverlay.cpp)).
`TimelineSurface` keeps roll, lane, and strip content in DPR-aware pixmaps, so
playhead paints restore cached content rather than rebuild it
([`src/ui/songview.cpp`](../src/ui/songview.cpp)).

That is the right ownership split. A QRhi implementation should consume the
same final state; it should not compute song ticks, scrolling, visibility, or
theme policy.

The least disruptive prototype is a private `QRhiWidget` child owned by a
Linux presentation backend. It fills the existing `PlayheadOverlay`, while
`PlayheadOverlay` remains the geometry and state owner. The QRhi child must keep
stable, full-overlay geometry. Moving a narrow QRhi child each tick would
invalidate its old and new parent areas and bring backing-store work back into
the hot path.

## What one playhead move does

For a texture-only update, Qt 6.9 takes this path:

1. `QWidget::update()` puts a render-to-texture widget in a separate dirty list.
   It does not add the requested region to the normal backing-store dirty
   region. Qt also discards the requested subregion for this path.
2. The repaint manager sends the QRhi widget a paint event for its full
   `rect()`.
3. `QRhiWidget::paintEvent()` starts an offscreen frame, calls the subclass
   `render()`, and ends the offscreen frame.
4. With no ordinary widget damage, the repaint manager flushes with an empty
   backing-store region. The default compositor returns its cached
   backing-store texture without uploading it again.
5. Qt starts a top-level swapchain frame, draws the backing-store quad and
   texture-widget quad, then ends and presents the frame.

Sources:

- Qt repaint-manager dirty lists and full-rect texture paint:
  [`QWidgetRepaintManager::markDirty()` and `paintAndFlush()`](https://code.qt.io/cgit/qt/qtbase.git/tree/src/widgets/kernel/qwidgetrepaintmanager.cpp?h=6.9)
- QRhi widget offscreen render:
  [`QRhiWidget::paintEvent()`](https://code.qt.io/cgit/qt/qtbase.git/tree/src/widgets/kernel/qrhiwidget.cpp?h=6.9)
- Cached backing-store texture and full swapchain composition:
  [`QBackingStoreDefaultCompositor::toTexture()` and `flush()`](https://code.qt.io/cgit/qt/qtbase.git/tree/src/gui/painting/qbackingstoredefaultcompositor.cpp?h=6.9)

The decisive distinction is:

> A playhead-only QRhi update avoids ordinary QWidget repaint and cached
> backing-store upload, but it still causes a QRhi texture render and a
> full top-level composite/present.

The offscreen frame is also a submission boundary. Qt documents
`endOffscreenFrame()` as submitting and waiting for the offscreen work before
the later swapchain composition
([`QRhi`](https://doc.qt.io/qt-6.9/qrhi.html)).

## Transparency and stacking

A transparent overlay requires `Qt::WA_AlwaysStackOnTop`.

Without that attribute, Qt draws render-to-texture widgets before the raster
backing store and punches a transparent hole in the backing store where the
widget sits. Transparent QRhi pixels therefore do not reveal the ordinary
widgets beneath them as an overlay should.

With `WA_AlwaysStackOnTop`, Qt does not punch the hole and composites the QRhi
texture after the raster backing store with alpha blending. The generic widget
texture flags and compositor order implement this:

- [`QWidgetPrivate::textureListFlags()`](https://code.qt.io/cgit/qt/qtbase.git/tree/src/widgets/kernel/qwidget_p.h?h=6.9)
- [`QWidgetPrivate::drawWidget()`](https://code.qt.io/cgit/qt/qtbase.git/tree/src/widgets/kernel/qwidget.cpp?h=6.9)
- [`QBackingStoreDefaultCompositor::flush()`](https://code.qt.io/cgit/qt/qtbase.git/tree/src/gui/painting/qbackingstoredefaultcompositor.cpp?h=6.9)

Qt warns that `WA_AlwaysStackOnTop` prevents ordinary widgets in the same
top-level window from stacking above the texture widget
([QOpenGLWidget limitations](https://doc.qt.io/qt-6.9/qopenglwidget.html#limitations-and-other-considerations)).
That matches the playhead's intended place above the SongView surfaces, but it
needs checks for any in-window overlays that can intersect SongView. Separate
popup windows are not part of this widget stack.

`Qt::WA_TransparentForMouseEvents` should remain on the overlay so the GPU path
does not change input handling.

## Dirty updates and texture size

`QRhiWidget` has no public partial-update mode. `update(QRegion)` does not pass
that region to `render()`; the repaint manager asks the texture widget to paint
its full rectangle. With the default automatic render target, `beginPass()`
clears the color attachment, so the practical default is a full-overlay texture
clear and redraw on every move.

The application can call `setAutoRenderTarget(false)`, create a
`QRhiTextureRenderTarget` with `PreserveColorContents`, and use scissor
rectangles to clear the old playhead and draw the new one. This is application
managed, not QRhiWidget dirty-region support. Qt warns that preserving attachment
contents can cost more on some GPUs
([`QRhiTextureRenderTarget::PreserveColorContents`](https://doc.qt.io/qt-6.9/qrhitexturerendertarget.html)).
It also does not remove the later full-window composite and present.

`setFixedColorBufferSize()` cannot turn this into a small moving sprite. Qt
stretches a fixed-size texture across the widget's geometry. The alternative,
moving a narrow widget, invalidates parent backing-store areas. The viable
prototype therefore needs a full-size transparent texture, whose pixel size is
the overlay's logical size times DPR
([QRhiWidget](https://doc.qt.io/qt-6.9/qrhiwidget.html)).

## Top-level window and Linux backends

Adding one QRhiWidget changes the whole native top-level window to QRhi-based
flush. Raster QWidget content becomes a texture that Qt draws in a swapchain
pass on every flush. Qt uploads only the bounding rectangle of changed raster
content after the initial full upload, but it still draws the full backing-store
quad during composition.

A top-level widget window can use only one QRhi backend. The choice must happen
before display and applies to every QRhiWidget or QQuickWidget in that window.
This could constrain later GPU-backed UI work.

QRhiWidget defaults are:

- Metal on macOS.
- Direct3D 11 on Windows.
- OpenGL on Linux and other platforms.

On Linux this choice is the same under X11/xcb and Wayland. Both platform
plugins report QRhi rendering support through the default platform capability;
the OpenGL backend then needs a working GLX or EGL integration on xcb, and a
Wayland client-buffer/EGL integration on Wayland:

- [`QRhiWidget` backend selection](https://code.qt.io/cgit/qt/qtbase.git/tree/src/widgets/kernel/qrhiwidget.cpp?h=6.9)
- [`QXcbIntegration`](https://code.qt.io/cgit/qt/qtbase.git/tree/src/plugins/platforms/xcb/qxcbintegration.cpp?h=6.9)
- [`QWaylandIntegration`](https://code.qt.io/cgit/qt/qtwayland.git/tree/src/client/qwaylandintegration.cpp?h=6.9)
- [`QBackingStoreRhiSupport::create()`](https://code.qt.io/cgit/qt/qtbase.git/tree/src/gui/painting/qbackingstorerhisupport.cpp?h=6.9)

There is no automatic Linux OpenGL-to-Vulkan fallback in that creation path.
The application may request Vulkan early with `setApi()`, but a failed request
leaves no QRhi and emits `renderFailed()`. `QSG_RHI_PREFER_SOFTWARE_RENDERER`
passes a software preference into QRhi creation; unlike the Windows D3D path,
the Linux OpenGL path does not retry with a second backend.
If `QT_WIDGETS_RHI` and `QT_WIDGETS_RHI_BACKEND` force a top-level backend,
that global choice takes priority; it must agree with the QRhiWidget's API.

This makes fallback timing important. The prototype should decide and validate
the backend before showing the top-level window, then keep the QPainter overlay
available. After the top-level has adopted QRhi composition, there is no simple
documented switch back to raster; a production fallback needs top-level window
recreation or an application restart.

## Build and compatibility cost

QRhiWidget is public from Qt 6.7, but a useful subclass must use the QRhi family:

- Require Qt 6.7 or newer explicitly. The repo's CMake currently requests
  unversioned Qt 6, while CI installs Qt 6.9.
- Link `Qt6::GuiPrivate` and include `<rhi/qrhi.h>`.
- Treat each Qt minor as a source compatibility boundary. Qt gives QRhi,
  QShader, and related classes no source or binary compatibility guarantee
  across minor versions.
- Add Qt Shader Tools and `qt_add_shaders()` (or prebuild the same `.qsb`
  assets). The build step creates one packaged shader that QRhi can select from
  for OpenGL, Vulkan, Metal, and Direct3D.

Sources:

- [QRhiWidget compatibility and CMake requirements](https://doc.qt.io/qt-6.9/qrhiwidget.html)
- [Qt Shader Tools CMake integration](https://doc.qt.io/qt-6.9/qtshadertools-build.html)

Distribution builds that use system Qt packages may need the package that
contains Qt's private GUI headers, not only the normal Widgets development
package.

## Failure recovery and tests

The subclass must release all of its QRhi resources in both its destructor and
`releaseResources()`. Qt calls the latter when reparenting or replacement of
the top-level QRhi requires early cleanup. When top-level presentation reports
device loss, the widget repaint manager sends window-change events to texture
children, rebuilds the backing-store graphics device, and requests another
update. `renderFailed()` covers the case where no QRhi can be created and may
fire more than once. It is not a complete render-failure signal:
`QRhiWidget::paintEvent()` also returns without emitting it when
`beginOffscreenFrame()` fails.

`QWidget::grab()` on a QRhiWidget or an ancestor is supported, including
offscreen rendering. It performs a fresh QRhi render and GPU readback, so grabs
must stay outside paint and timing evidence. This fits the current
`rollcheckplayhead` structure, which freezes repaint evidence before most grabs,
but its expectations must change:

- A playhead move should repaint the QRhi widget only, not the ruler, roll,
  lanes, or strip.
- Timeline content-paint counters must remain unchanged.
- `marker.grab()` and `view.grab()` can still check pixels, stale positions,
  clipping, triangle direction, and fractional movement.
- Count `frameSubmitted` and `renderFailed` separately from QWidget paint
  events.

Source: [QRhiWidget grabbing and resource lifetime](https://doc.qt.io/qt-6.9/qrhiwidget.html).
Wayland's lack of `QScreen::grabWindow()` does not affect these QWidget-owned
grabs.

## Bounded prototype

Prototype Linux only and keep it behind an internal build switch until measured.
Use a stable, full-overlay QRhiWidget with:

- `WA_AlwaysStackOnTop`, `WA_TransparentForMouseEvents`, and straight-alpha
  output.
- No MSAA. Disable the automatic render target and create a custom target if
  the prototype is to omit the otherwise automatic depth/stencil buffer.
- Static vertex and pipeline resources.
- Per-frame x, playing state, color, and clip rectangles in a small dynamic
  buffer.
- No texture uploads or pipeline rebuilds when only x changes.

First measure the simple full-clear target. If its fill cost is material, add
one comparison with an application-managed preserved target and old/new
scissors. Do not keep both production modes.

Adopt it only if matched tests on X11 and Wayland show:

- zero ordinary timeline QWidget paints and zero backing-store uploads during a
  steady playhead move after warmup;
- better process CPU without a harmful GPU, latency, or frame-pacing increase;
- no regression during other top-level raster updates;
- correct 100%, 125%, 150%, and 200% DPR output, resize, scroll, event-list,
  tab, hide/show, theme, and failure-fallback behavior.

Compare that result with the current QPainter overlay, not with the native
Windows or macOS adapters. QRhiWidget's unavoidable offscreen frame plus
full-window composite makes it structurally less efficient than compositor
transform updates.
