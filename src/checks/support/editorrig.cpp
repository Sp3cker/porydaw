#include "checks/support/editorrig.h"

#include <utility>

#include <QCoreApplication>
#include <QQuickItem>
#include <QQuickView>
#include <QQuickWindow>
#include <QSurfaceFormat>

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace checks {

QuickSceneHost::QuickSceneHost(SongView &view, const QSize &size, bool attachScene) : m_view(&view)
{
    // Canvas component creation resolves the timeline QML types, so they
    // must be registered before the window's engine builds the scene.
    songview::TimelineQuickView::registerQuickTypes();
    m_window = std::make_unique<QQuickView>();
    // Production surface stanza (WorkspaceQuickHost / TimelineQuickView): an
    // alpha8 transparent canvas the native layers composite over.
    QSurfaceFormat surfaceFormat = m_window->format();
    surfaceFormat.setAlphaBufferSize(8);
    m_window->setFormat(surfaceFormat);
    m_window->setColor(Qt::transparent);
    m_window->setResizeMode(QQuickView::SizeRootObjectToView);
    m_window->resize(size);
    m_viewport = new QQuickItem(m_window->contentItem());
    m_viewport->setSize(size);
    QQuickView *const window = m_window.get();
    QQuickItem *const viewport = m_viewport;
    QObject::connect(window, &QQuickWindow::widthChanged, viewport,
                     [window, viewport] { viewport->setWidth(window->width()); });
    QObject::connect(window, &QQuickWindow::heightChanged, viewport,
                     [window, viewport] { viewport->setHeight(window->height()); });
    if (!attachScene)
        return;
    if (songview::TimelineQuickView *const canvas = view.quickView()) {
        canvas->attachScene(*m_window->engine(), *m_viewport);
        // Standalone checks explicitly select their only page.
        canvas->setPageSelected(true);
    }
}

QuickSceneHost::~QuickSceneHost()
{
    // Detach while the view, engine, and window are all alive; the canvas
    // unbinds and unloads before its host window is destroyed.
    if (SongView *const view = m_view.data()) {
        if (songview::TimelineQuickView *const canvas = view->quickView())
            canvas->detachScene();
    }
}

QQuickWindow &QuickSceneHost::window() noexcept
{
    return *m_window;
}

QQmlEngine &QuickSceneHost::engine() noexcept
{
    return *m_window->engine();
}

QQuickItem &QuickSceneHost::viewport() noexcept
{
    return *m_viewport;
}

std::unique_ptr<EditorRig> EditorRig::create(SongDocument &document, const EditorRigConfig &config,
                                             QString &error)
{
    error.clear();
    auto timeline = document.buildTimeline(config.sampleRate);
    if (!timeline) {
        error = QStringLiteral("could not build song timeline");
        return nullptr;
    }

    auto rig = std::unique_ptr<EditorRig>(new EditorRig(document));
    rig->m_voicegroup = config.voicegroup;
    rig->m_timeline = std::move(timeline);
    songview::TimelineQuickView *const quickCanvas = rig->m_view->quickView();
    if (!quickCanvas) {
        error = QStringLiteral("SongView did not expose the Quick canvas");
        return nullptr;
    }
    // Match SongTab wiring order before attaching the canvas.
    rig->m_view->setDocument(&document);
    rig->m_view->setSong(rig->m_timeline.get(), config.voicegroup);
    rig->m_host =
        std::make_unique<QuickSceneHost>(*rig->m_view, config.viewSize, config.attachScene);
    if (config.track >= 0)
        rig->m_view->selectTrack(config.track);
    rig->m_view->setDrawerActivePage(config.activePage);
    for (const EditorRigSection &section : config.sections) {
        rig->m_view->setDrawerSectionVisible(section.page, true);
        rig->m_view->setDrawerSectionHeight(section.page, section.height);
    }
    if (config.show) {
        rig->m_host->window().show();
        QCoreApplication::processEvents();
    }
    rig->m_quickScene = rig->m_view->findChild<songview::TimelineQuickScene *>();
    if (!rig->m_quickScene) {
        error = QStringLiteral("concrete SongView did not expose the Quick canvas root or scene");
        return nullptr;
    }
    if (!config.attachScene) {
        // Custom-viewport callers resolve QML items after their explicit attach.
        rig->m_quickRoot = nullptr;
        rig->m_voiceInput = nullptr;
    } else {
        rig->m_quickRoot = quickCanvas->rootObject();
        rig->m_voiceInput = rig->inputItem(QStringLiteral("timelineVoiceChangesInput"));
        if (!rig->m_quickRoot) {
            error =
                QStringLiteral("concrete SongView did not expose the Quick canvas root or scene");
            return nullptr;
        }
        if (!rig->m_voiceInput) {
            error = QStringLiteral("concrete SongView did not expose the voice Quick input item");
            return nullptr;
        }
    }
    if (config.timeZoom > 0.0)
        rig->m_view->setEditorTimeZoom(config.timeZoom);
    if (config.applyEditCursor)
        rig->m_view->setEditCursorTick(config.editCursorTick);
    QCoreApplication::processEvents();
    return rig;
}

EditorRig::EditorRig(SongDocument &document)
    : m_document(document)
    , m_view(std::make_unique<SongView>())
{}

EditorRig::~EditorRig()
{
    // Detach and tear down the hosted canvas while every bound model still
    // lives, then unbind the borrowed song and document.
    m_host.reset();
    m_view->setSong(nullptr, nullptr);
    m_view->setDocument(nullptr);
}

SongDocument &EditorRig::document() noexcept
{
    return m_document;
}

SongView &EditorRig::view() noexcept
{
    return *m_view;
}

QuickSceneHost &EditorRig::host() noexcept
{
    return *m_host;
}

const QuickSceneHost &EditorRig::host() const noexcept
{
    return *m_host;
}

const MidiTimeline &EditorRig::timeline() const noexcept
{
    return *m_timeline;
}

LoadedVoiceGroup *EditorRig::voicegroup() const noexcept
{
    return m_voicegroup;
}

songview::TimelineInputItem &EditorRig::voiceInput() noexcept
{
    return *m_voiceInput;
}

songview::TimelineQuickScene *EditorRig::quickScene() noexcept
{
    return m_quickScene;
}

QQuickItem *EditorRig::quickRoot() noexcept
{
    return m_quickRoot;
}

songview::TimelineInputItem *EditorRig::inputItem(const QString &objectName) const
{
    return m_quickRoot ? m_quickRoot->findChild<songview::TimelineInputItem *>(objectName)
                       : nullptr;
}

} // namespace checks
