#include "playheadoverlay.h"

#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <d2d1.h>
#include <d2d1helper.h>
#include <d3d11.h>
#include <dcomp.h>
#include <dxgi.h>
#include <windows.h>

#include <QDebug>
#include <QtMath>
#include <algorithm>
#include <array>
#include <memory>
#include <utility>
#include <vector>

namespace songview {

namespace {

constexpr int kSurfacePadding = 1;
constexpr wchar_t kHostWindowClass[] = L"PorydawDCompPlayheadHost";

template <class T>
class ComPtr
{
  public:
    ComPtr() = default;
    ~ComPtr() { reset(); }

    ComPtr(const ComPtr &) = delete;
    ComPtr &operator=(const ComPtr &) = delete;

    ComPtr(ComPtr &&other) noexcept : m_pointer(other.m_pointer) { other.m_pointer = nullptr; }

    ComPtr &operator=(ComPtr &&other) noexcept
    {
        if (this != &other) {
            reset();
            m_pointer = other.m_pointer;
            other.m_pointer = nullptr;
        }
        return *this;
    }

    T *get() const { return m_pointer; }
    T *operator->() const { return m_pointer; }
    explicit operator bool() const { return m_pointer != nullptr; }

    T **put()
    {
        reset();
        return &m_pointer;
    }

    void reset(T *pointer = nullptr)
    {
        if (m_pointer)
            m_pointer->Release();
        m_pointer = pointer;
    }

  private:
    T *m_pointer = nullptr;
};

LRESULT CALLBACK playheadHostWindowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    switch (message) {
    case WM_NCHITTEST:
        return HTTRANSPARENT;
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
    case WM_ERASEBKGND:
        return 1;
    default:
        return DefWindowProcW(hwnd, message, wParam, lParam);
    }
}

bool registerHostWindowClass()
{
    static const bool registered = [] {
        WNDCLASSEXW windowClass{};
        windowClass.cbSize = sizeof(windowClass);
        windowClass.lpfnWndProc = playheadHostWindowProc;
        windowClass.hInstance = GetModuleHandleW(nullptr);
        windowClass.lpszClassName = kHostWindowClass;
        return RegisterClassExW(&windowClass) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
    }();
    return registered;
}

QRect toNativeRect(const QRect &rect, qreal dpr)
{
    const int left = qFloor(qreal(rect.x()) * dpr);
    const int top = qFloor(qreal(rect.y()) * dpr);
    const int right = qCeil(qreal(rect.x() + rect.width()) * dpr);
    const int bottom = qCeil(qreal(rect.y() + rect.height()) * dpr);
    return QRect(left, top, std::max(0, right - left), std::max(0, bottom - top));
}

class DeviceResources final
{
  public:
    bool initialize()
    {
        constexpr UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
        HRESULT result =
            D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, nullptr, 0,
                              D3D11_SDK_VERSION, m_d3dDevice.put(), nullptr, nullptr);
        if (FAILED(result))
            return fail(result);

        result = m_d3dDevice->QueryInterface(__uuidof(IDXGIDevice),
                                             reinterpret_cast<void **>(m_dxgiDevice.put()));
        if (FAILED(result))
            return fail(result);

        result = DCompositionCreateDevice(m_dxgiDevice.get(), __uuidof(IDCompositionDevice),
                                          reinterpret_cast<void **>(m_dcompDevice.put()));
        if (FAILED(result))
            return fail(result);

        result = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, m_d2dFactory.put());
        if (FAILED(result))
            return fail(result);
        return true;
    }

    HRESULT lastError() const { return m_lastError; }
    IDCompositionDevice *composition() const { return m_dcompDevice.get(); }
    ID2D1Factory *d2dFactory() const { return m_d2dFactory.get(); }

  private:
    bool fail(HRESULT result)
    {
        m_lastError = result;
        return false;
    }

    HRESULT m_lastError = S_OK;
    ComPtr<ID3D11Device> m_d3dDevice;
    ComPtr<IDXGIDevice> m_dxgiDevice;
    ComPtr<IDCompositionDevice> m_dcompDevice;
    ComPtr<ID2D1Factory> m_d2dFactory;
};

std::shared_ptr<DeviceResources> acquireDeviceResources(HRESULT &error)
{
    static std::weak_ptr<DeviceResources> cachedDevice;
    if (auto device = cachedDevice.lock())
        return device;

    auto device = std::make_shared<DeviceResources>();
    if (!device->initialize()) {
        error = device->lastError();
        return {};
    }
    cachedDevice = device;
    return device;
}

struct VisualClip {
    QRect rect;
    ComPtr<IDCompositionVisual> clipVisual;
    ComPtr<IDCompositionRectangleClip> clip;
    ComPtr<IDCompositionVisual> contentVisual;
};

} // namespace

class PlayheadOverlay::Platform final
{
  public:
    explicit Platform(QWidget &owner) : m_owner(owner) {}

    ~Platform()
    {
        if (m_hostWindow)
            ShowWindow(m_hostWindow, SW_HIDE);
        m_bodyClips.clear();
        m_triangleClip = {};
        m_rootVisual.reset();
        m_target.reset();
        if (m_hostWindow)
            DestroyWindow(m_hostWindow);
    }

    bool setImages(const QColor &color)
    {
        if (m_color == color)
            return true;

        m_color = color;
        m_surfacesValid = false;
        if (!m_initialized || !m_hasLayout)
            return true;

        if (!createCachedSurfaces())
            return false;
        m_surfacesValid = true;
        return setVisualContent() && commit();
    }

    bool setLayout(const QSize &overlaySize, const QRegion &visibleSurfaceRegion,
                   const QRect &triangleClip, const QRect &bodyGeometry, qreal devicePixelRatio,
                   qreal finalX, bool visible, bool playing, bool trianglePointsUp)
    {
        QWidget *topLevel = m_owner.window();
        if (!topLevel || !topLevel->internalWinId())
            return false;
        if (!m_initialized) {
            if (!initialize())
                return false;
            m_initialized = true;
        }
        if (!ensureHostWindow() || !updateHostPlacement())
            return false;

        const qreal dpr = std::max<qreal>(devicePixelRatio, 1.0);
        const bool surfacesChanged = !m_surfacesValid || m_devicePixelRatio != dpr ||
                                     m_playheadHeight != bodyGeometry.height();
        const bool clipsChanged =
            !m_visualTreeValid || m_devicePixelRatio != dpr || m_overlaySize != overlaySize ||
            m_visibleSurfaceRegion != visibleSurfaceRegion || m_triangleClipRect != triangleClip;

        m_devicePixelRatio = dpr;
        m_overlaySize = overlaySize;
        m_visibleSurfaceRegion = visibleSurfaceRegion;
        m_triangleClipRect = triangleClip;
        m_playheadHeight = bodyGeometry.height();
        m_bodyTop = bodyGeometry.top();
        m_triangleTop = triangleClip.top();
        m_finalX = finalX;
        m_visible = visible;
        m_playing = playing;
        m_trianglePointsUp = trianglePointsUp;

        if (surfacesChanged) {
            if (!createCachedSurfaces())
                return false;
            m_surfacesValid = true;
        }
        if (clipsChanged) {
            if (!rebuildVisualTree())
                return false;
            m_visualTreeValid = true;
        }
        if (!setVisualContent() || !setVisualLayout() || !setVisualPosition())
            return false;
        m_hasLayout = true;
        return commit();
    }

    bool setPosition(qreal finalX, bool visible, bool playing, bool trianglePointsUp)
    {
        if (!m_initialized || !m_hasLayout || !reassertHostOrder())
            return false;

        const bool positionChanged = m_finalX != finalX;
        const bool contentChanged =
            m_visible != visible || m_playing != playing || m_trianglePointsUp != trianglePointsUp;
        if (!positionChanged && !contentChanged)
            return true;

        m_finalX = finalX;
        m_visible = visible;
        m_playing = playing;
        m_trianglePointsUp = trianglePointsUp;
        if ((contentChanged && !setVisualContent()) || (positionChanged && !setVisualPosition())) {
            return false;
        }
        return commit();
    }

    bool failed() const { return FAILED(m_lastError); }

    QString error() const
    {
        return QStringLiteral("DirectComposition HRESULT 0x%1")
            .arg(static_cast<quint32>(m_lastError), 8, 16, QLatin1Char('0'));
    }

  private:
    bool initialize()
    {
        // The body and triangle are rasterized only when layout, DPI, or color
        // changes. Every content visual shares one translate transform, so a
        // normal playhead tick is one SetOffsetX call and one Commit.
        if (!registerHostWindowClass()) {
            m_lastError = HRESULT_FROM_WIN32(GetLastError());
            return false;
        }

        m_device = acquireDeviceResources(m_lastError);
        if (!m_device)
            return false;

        HRESULT result = m_device->composition()->CreateVisual(m_rootVisual.put());
        if (FAILED(result))
            return fail(result);
        result = m_device->composition()->CreateTranslateTransform(m_playheadTransform.put());
        if (FAILED(result))
            return fail(result);
        return ensureHostWindow();
    }

    bool fail(HRESULT result)
    {
        m_lastError = result;
        return false;
    }

    bool ensureHostWindow()
    {
        QWidget *topLevel = m_owner.window();
        if (!topLevel)
            return fail(E_HANDLE);
        const HWND ownerWindow = reinterpret_cast<HWND>(topLevel->internalWinId());
        if (!ownerWindow)
            return fail(E_HANDLE);
        if (m_hostWindow && m_ownerWindow == ownerWindow && IsWindow(m_hostWindow))
            return true;

        if (m_hostWindow) {
            ShowWindow(m_hostWindow, SW_HIDE);
            m_target.reset();
            DestroyWindow(m_hostWindow);
            m_hostWindow = nullptr;
            m_hostVisible = false;
        }

        constexpr DWORD extendedStyle =
            WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_NOREDIRECTIONBITMAP;
        m_hostWindow = CreateWindowExW(extendedStyle, kHostWindowClass, L"", WS_CHILD, 0, 0, 1, 1,
                                       ownerWindow, nullptr, GetModuleHandleW(nullptr), nullptr);
        if (!m_hostWindow)
            return fail(HRESULT_FROM_WIN32(GetLastError()));

        m_ownerWindow = ownerWindow;
        m_hostGeometry = {};
        HRESULT result =
            m_device->composition()->CreateTargetForHwnd(m_hostWindow, TRUE, m_target.put());
        if (FAILED(result))
            return fail(result);
        result = m_target->SetRoot(m_rootVisual.get());
        if (FAILED(result))
            return fail(result);
        return true;
    }

    bool updateHostPlacement()
    {
        QWidget *topLevel = m_owner.window();
        if (!topLevel || !m_ownerWindow || !m_hostWindow)
            return fail(E_HANDLE);

        const qreal dpr = std::max<qreal>(topLevel->devicePixelRatioF(), 1.0);
        const QPoint ownerOffset = m_owner.mapTo(topLevel, QPoint(0, 0));
        const int x = qRound(qreal(ownerOffset.x()) * dpr);
        const int y = qRound(qreal(ownerOffset.y()) * dpr);
        const int width = qCeil(qreal(m_owner.width()) * dpr);
        const int height = qCeil(qreal(m_owner.height()) * dpr);
        const QRect geometry(x, y, width, height);
        const bool shouldShow = width > 0 && height > 0 && m_owner.isVisible() &&
                                topLevel->isVisible() && !topLevel->isMinimized() &&
                                !topLevel->testAttribute(Qt::WA_DontShowOnScreen);
        const bool hostIsTopmost = GetWindow(m_hostWindow, GW_HWNDPREV) == nullptr;

        if (width > 0 && height > 0 && (geometry != m_hostGeometry || !hostIsTopmost) &&
            !SetWindowPos(m_hostWindow, HWND_TOP, x, y, width, height,
                          SWP_NOACTIVATE | SWP_NOSENDCHANGING)) {
            return fail(HRESULT_FROM_WIN32(GetLastError()));
        }
        m_hostGeometry = geometry;

        if (shouldShow != m_hostVisible) {
            if (shouldShow) {
                if (!SetWindowPos(m_hostWindow, HWND_TOP, 0, 0, 0, 0,
                                  SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)) {
                    return fail(HRESULT_FROM_WIN32(GetLastError()));
                }
            } else {
                ShowWindow(m_hostWindow, SW_HIDE);
            }
            m_hostVisible = shouldShow;
        }
        return true;
    }

    bool reassertHostOrder()
    {
        QWidget *topLevel = m_owner.window();
        const HWND ownerWindow =
            topLevel ? reinterpret_cast<HWND>(topLevel->internalWinId()) : nullptr;
        if (!ownerWindow || ownerWindow != m_ownerWindow || !m_hostWindow ||
            !IsWindow(m_hostWindow)) {
            return fail(E_HANDLE);
        }
        if (GetWindow(m_hostWindow, GW_HWNDPREV) == nullptr)
            return true;
        if (!SetWindowPos(m_hostWindow, HWND_TOP, 0, 0, 0, 0,
                          SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_NOSENDCHANGING)) {
            return fail(HRESULT_FROM_WIN32(GetLastError()));
        }
        return true;
    }

    bool createSurface(UINT width, UINT height, ComPtr<IDCompositionSurface> &surface)
    {
        if (width == 0 || height == 0) {
            surface.reset();
            return true;
        }
        const HRESULT result =
            m_device->composition()->CreateSurface(width, height, DXGI_FORMAT_B8G8R8A8_UNORM,
                                                   DXGI_ALPHA_MODE_PREMULTIPLIED, surface.put());
        return SUCCEEDED(result) || fail(result);
    }

    template <class Paint>
    bool paintSurface(IDCompositionSurface *surface, Paint paint)
    {
        if (!surface)
            return true;

        ComPtr<IDXGISurface> dxgiSurface;
        POINT updateOffset{};
        HRESULT result =
            surface->BeginDraw(nullptr, __uuidof(IDXGISurface),
                               reinterpret_cast<void **>(dxgiSurface.put()), &updateOffset);
        if (FAILED(result))
            return fail(result);

        ComPtr<ID2D1RenderTarget> renderTarget;
        const D2D1_RENDER_TARGET_PROPERTIES properties = D2D1::RenderTargetProperties(
            D2D1_RENDER_TARGET_TYPE_DEFAULT,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96.0f,
            96.0f);
        result = m_device->d2dFactory()->CreateDxgiSurfaceRenderTarget(
            dxgiSurface.get(), properties, renderTarget.put());
        if (FAILED(result)) {
            surface->EndDraw();
            return fail(result);
        }

        renderTarget->BeginDraw();
        renderTarget->SetTransform(
            D2D1::Matrix3x2F::Translation(float(updateOffset.x), float(updateOffset.y)));
        renderTarget->Clear(D2D1::ColorF(0.0f, 0.0f));
        const HRESULT paintResult = paint(*renderTarget.get());
        result = renderTarget->EndDraw();
        const HRESULT endDrawResult = surface->EndDraw();
        if (FAILED(paintResult))
            return fail(paintResult);
        if (FAILED(result))
            return fail(result);
        if (FAILED(endDrawResult))
            return fail(endDrawResult);
        return true;
    }

    D2D1_COLOR_F d2dColor(qreal alpha) const
    {
        return D2D1::ColorF(float(m_color.redF()), float(m_color.greenF()), float(m_color.blueF()),
                            float(alpha));
    }

    bool paintBody(IDCompositionSurface *surface, bool playing)
    {
        return paintSurface(surface, [&](ID2D1RenderTarget &target) -> HRESULT {
            const float dpr = float(m_devicePixelRatio);
            const float center = float(m_bodyCenter);
            const float height = float(m_bodySurfaceHeight);
            const float left = float(playheadGlowLeftExtent(playing)) * dpr;
            const float right = float(playheadGlowRightExtent(playing)) * dpr;
            const qreal peak = playheadPeakAlpha(playing);

            std::array<D2D1_GRADIENT_STOP, 9> stops{};
            for (int i = 0; i < int(stops.size()); ++i) {
                const qreal t = qreal(i) / qreal(stops.size() - 1);
                stops[std::size_t(i)].position = float(t);
                stops[std::size_t(i)].color = d2dColor(peak * t * t);
            }

            ComPtr<ID2D1GradientStopCollection> gradientStops;
            HRESULT result = target.CreateGradientStopCollection(
                stops.data(), UINT32(stops.size()), D2D1_GAMMA_2_2, D2D1_EXTEND_MODE_CLAMP,
                gradientStops.put());
            if (FAILED(result))
                return result;

            if (left > 0.0f) {
                ComPtr<ID2D1LinearGradientBrush> brush;
                const D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES gradient =
                    D2D1::LinearGradientBrushProperties(D2D1::Point2F(center - left, 0.0f),
                                                        D2D1::Point2F(center, 0.0f));
                result =
                    target.CreateLinearGradientBrush(gradient, gradientStops.get(), brush.put());
                if (FAILED(result))
                    return result;
                target.FillRectangle(D2D1::RectF(center - left, 0.0f, center, height), brush.get());
            }

            if (right > 0.0f) {
                ComPtr<ID2D1LinearGradientBrush> brush;
                const D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES gradient =
                    D2D1::LinearGradientBrushProperties(D2D1::Point2F(center + right, 0.0f),
                                                        D2D1::Point2F(center, 0.0f));
                result =
                    target.CreateLinearGradientBrush(gradient, gradientStops.get(), brush.put());
                if (FAILED(result))
                    return result;
                target.FillRectangle(D2D1::RectF(center, 0.0f, center + right, height),
                                     brush.get());
            }

            ComPtr<ID2D1SolidColorBrush> core;
            result = target.CreateSolidColorBrush(d2dColor(m_color.alphaF()), core.put());
            if (FAILED(result))
                return result;
            target.DrawLine(D2D1::Point2F(center, 0.0f), D2D1::Point2F(center, height), core.get(),
                            float(playheadLineWidth() * m_devicePixelRatio));
            return S_OK;
        });
    }

    bool paintTriangle(IDCompositionSurface *surface, bool pointsUp)
    {
        return paintSurface(surface, [&](ID2D1RenderTarget &target) -> HRESULT {
            const float dpr = float(m_devicePixelRatio);
            const float padding = float(kSurfacePadding) * dpr;
            const float center = float(m_triangleCenter);
            const float halfWidth = float(playheadTriangleHalfWidth()) * dpr;
            const float height = float(playheadTriangleHeight()) * dpr;

            ComPtr<ID2D1PathGeometry> path;
            HRESULT result = m_device->d2dFactory()->CreatePathGeometry(path.put());
            if (FAILED(result))
                return result;
            ComPtr<ID2D1GeometrySink> sink;
            result = path->Open(sink.put());
            if (FAILED(result))
                return result;
            if (pointsUp) {
                sink->BeginFigure(D2D1::Point2F(center - halfWidth, padding + height),
                                  D2D1_FIGURE_BEGIN_FILLED);
                sink->AddLine(D2D1::Point2F(center + halfWidth, padding + height));
                sink->AddLine(D2D1::Point2F(center, padding));
            } else {
                sink->BeginFigure(D2D1::Point2F(center - halfWidth, padding),
                                  D2D1_FIGURE_BEGIN_FILLED);
                sink->AddLine(D2D1::Point2F(center + halfWidth, padding));
                sink->AddLine(D2D1::Point2F(center, padding + height));
            }
            sink->EndFigure(D2D1_FIGURE_END_CLOSED);
            result = sink->Close();
            if (FAILED(result))
                return result;

            ComPtr<ID2D1SolidColorBrush> brush;
            result = target.CreateSolidColorBrush(d2dColor(m_color.alphaF()), brush.put());
            if (FAILED(result))
                return result;
            target.FillGeometry(path.get(), brush.get());
            return S_OK;
        });
    }

    bool createCachedSurfaces()
    {
        const qreal dpr = m_devicePixelRatio;
        m_bodySurfaceWidth = qCeil(qreal(2 * (playheadGlowRadius() + kSurfacePadding)) * dpr);
        m_bodySurfaceHeight = qCeil(qreal(m_playheadHeight) * dpr);
        m_bodyCenter = qreal(playheadGlowRadius() + kSurfacePadding) * dpr;
        m_triangleSurfaceWidth =
            qCeil(qreal(2 * (playheadTriangleHalfWidth() + kSurfacePadding)) * dpr);
        m_triangleSurfaceHeight =
            qCeil(qreal(playheadTriangleHeight() + 2 * kSurfacePadding) * dpr);
        m_triangleCenter = qreal(playheadTriangleHalfWidth() + kSurfacePadding) * dpr;

        if (!createSurface(UINT(m_bodySurfaceWidth), UINT(m_bodySurfaceHeight), m_bodyPaused) ||
            !createSurface(UINT(m_bodySurfaceWidth), UINT(m_bodySurfaceHeight), m_bodyPlaying) ||
            !createSurface(UINT(m_triangleSurfaceWidth), UINT(m_triangleSurfaceHeight),
                           m_triangleDown) ||
            !createSurface(UINT(m_triangleSurfaceWidth), UINT(m_triangleSurfaceHeight),
                           m_triangleUp)) {
            return false;
        }
        return paintBody(m_bodyPaused.get(), false) && paintBody(m_bodyPlaying.get(), true) &&
               paintTriangle(m_triangleDown.get(), false) &&
               paintTriangle(m_triangleUp.get(), true);
    }

    bool createVisualClip(const QRect &rect, VisualClip &visual)
    {
        visual.rect = rect;
        HRESULT result = m_device->composition()->CreateVisual(visual.clipVisual.put());
        if (FAILED(result))
            return fail(result);
        result = m_device->composition()->CreateVisual(visual.contentVisual.put());
        if (FAILED(result))
            return fail(result);
        result = m_device->composition()->CreateRectangleClip(visual.clip.put());
        if (FAILED(result))
            return fail(result);

        visual.clip->SetLeft(0.0f);
        visual.clip->SetTop(0.0f);
        visual.clip->SetRight(float(rect.width()));
        visual.clip->SetBottom(float(rect.height()));
        visual.clipVisual->SetOffsetX(float(rect.x()));
        visual.clipVisual->SetOffsetY(float(rect.y()));
        visual.clipVisual->SetClip(visual.clip.get());
        visual.contentVisual->SetTransform(m_playheadTransform.get());
        visual.contentVisual->SetBitmapInterpolationMode(
            DCOMPOSITION_BITMAP_INTERPOLATION_MODE_LINEAR);
        result = visual.clipVisual->AddVisual(visual.contentVisual.get(), FALSE, nullptr);
        if (FAILED(result))
            return fail(result);
        result = m_rootVisual->AddVisual(visual.clipVisual.get(), TRUE, nullptr);
        return SUCCEEDED(result) || fail(result);
    }

    bool rebuildVisualTree()
    {
        HRESULT result = m_rootVisual->RemoveAllVisuals();
        if (FAILED(result))
            return fail(result);
        m_bodyClips.clear();
        m_triangleClip = {};

        for (const QRect &logicalRect : m_visibleSurfaceRegion) {
            const QRect rect = toNativeRect(logicalRect, m_devicePixelRatio);
            if (rect.isEmpty())
                continue;
            VisualClip visual;
            if (!createVisualClip(rect, visual)) {
                return false;
            }
            m_bodyClips.push_back(std::move(visual));
        }

        const QRect triangleRect = toNativeRect(m_triangleClipRect, m_devicePixelRatio);
        if (!triangleRect.isEmpty() && !createVisualClip(triangleRect, m_triangleClip)) {
            return false;
        }
        return true;
    }

    bool setVisualContent()
    {
        IDCompositionSurface *bodySurface = m_playing ? m_bodyPlaying.get() : m_bodyPaused.get();
        for (VisualClip &visual : m_bodyClips) {
            const HRESULT result =
                visual.contentVisual->SetContent(m_visible ? bodySurface : nullptr);
            if (FAILED(result))
                return fail(result);
        }

        if (m_triangleClip.contentVisual) {
            const HRESULT result = m_triangleClip.contentVisual->SetContent(
                m_visible ? (m_trianglePointsUp ? m_triangleUp.get() : m_triangleDown.get())
                          : nullptr);
            if (FAILED(result))
                return fail(result);
        }
        return true;
    }

    bool setVisualLayout()
    {
        const float dpr = float(m_devicePixelRatio);
        for (VisualClip &visual : m_bodyClips) {
            visual.contentVisual->SetOffsetX(float(-m_bodyCenter - visual.rect.x()));
            visual.contentVisual->SetOffsetY(float(m_bodyTop * dpr - visual.rect.y()));
        }

        if (m_triangleClip.contentVisual) {
            m_triangleClip.contentVisual->SetOffsetX(
                float(-m_triangleCenter - m_triangleClip.rect.x()));
            m_triangleClip.contentVisual->SetOffsetY(float(
                m_triangleTop * dpr - qreal(kSurfacePadding) * dpr - m_triangleClip.rect.y()));
        }
        return true;
    }

    bool setVisualPosition()
    {
        const HRESULT result =
            m_playheadTransform->SetOffsetX(float(m_finalX * m_devicePixelRatio));
        return SUCCEEDED(result) || fail(result);
    }

    bool commit()
    {
        const HRESULT result = m_device->composition()->Commit();
        return SUCCEEDED(result) || fail(result);
    }

    QWidget &m_owner;
    std::shared_ptr<DeviceResources> m_device;
    HRESULT m_lastError = S_OK;

    HWND m_ownerWindow = nullptr;
    HWND m_hostWindow = nullptr;
    bool m_hostVisible = false;
    QRect m_hostGeometry;
    ComPtr<IDCompositionTarget> m_target;
    ComPtr<IDCompositionVisual> m_rootVisual;
    ComPtr<IDCompositionTranslateTransform> m_playheadTransform;
    std::vector<VisualClip> m_bodyClips;
    VisualClip m_triangleClip;

    ComPtr<IDCompositionSurface> m_bodyPaused;
    ComPtr<IDCompositionSurface> m_bodyPlaying;
    ComPtr<IDCompositionSurface> m_triangleDown;
    ComPtr<IDCompositionSurface> m_triangleUp;

    QSize m_overlaySize;
    QRegion m_visibleSurfaceRegion;
    QRect m_triangleClipRect;
    QColor m_color;
    qreal m_devicePixelRatio = 0.0;
    int m_playheadHeight = -1;
    int m_bodyTop = 0;
    int m_triangleTop = 0;
    qreal m_finalX = 0.0;
    bool m_visible = false;
    bool m_playing = false;
    bool m_trianglePointsUp = false;

    int m_bodySurfaceWidth = 0;
    int m_bodySurfaceHeight = 0;
    qreal m_bodyCenter = 0.0;
    int m_triangleSurfaceWidth = 0;
    int m_triangleSurfaceHeight = 0;
    qreal m_triangleCenter = 0.0;
    bool m_surfacesValid = false;
    bool m_visualTreeValid = false;
    bool m_hasLayout = false;
    bool m_initialized = false;
};

void PlayheadOverlay::initializePlatform(QWidget &owner)
{
    m_platform.reset(new Platform(owner));
}

void PlayheadOverlay::setPlatformLayout()
{
    Q_ASSERT(m_platform);
    if (!m_platform->setLayout(size(), m_visibleSurfaceRegion, m_triangleClip, m_bodyGeometry,
                               m_devicePixelRatio, finalX(), m_visible, m_playing,
                               m_trianglePointsUp) &&
        m_platform->failed()) {
        qWarning().noquote() << "Native playhead failed; using QWidget fallback:"
                             << m_platform->error();
        m_platform.reset();
    }
}

void PlayheadOverlay::setPlatformImages()
{
    Q_ASSERT(m_platform);
    if (!m_platform->setImages(m_color) && m_platform->failed()) {
        qWarning().noquote() << "Native playhead failed; using QWidget fallback:"
                             << m_platform->error();
        m_platform.reset();
    }
}

bool PlayheadOverlay::setPlatformPosition()
{
    Q_ASSERT(m_platform);
    const bool applied =
        m_platform->setPosition(finalX(), m_visible, m_playing, m_trianglePointsUp);
    if (!applied && m_platform->failed()) {
        qWarning().noquote() << "Native playhead failed; using QWidget fallback:"
                             << m_platform->error();
        m_platform.reset();
    }
    return applied;
}

void PlayheadOverlay::PlatformDeleter::operator()(Platform *platform) const
{
    delete platform;
}

} // namespace songview
