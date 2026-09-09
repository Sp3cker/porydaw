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
#include "ui/songview/quick/quickwindowinput.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace checks {

QuickSceneHost::QuickSceneHost(SongView &view, const QSize &size) : m_view(&view)
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
    // Size the viewport (the window's content item) and the window up
    // front so the canvas attaches with its canonical geometry already
    // fixed.
    m_window->resize(size);
    m_window->contentItem()->setSize(size);
    if (songview::TimelineQuickView *const canvas = view.quickView()) {
        canvas->attachScene(*m_window->engine(), *m_window->contentItem());
        // The standalone rig host selects its scene explicitly: one scene
        // per window here, and standalone domain views default ready.
        songview::QuickWindowInput::forWindow(*m_window).setSelectedScene(canvas);
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
    return *m_window->contentItem();
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
    // Production wiring order (SongTab): document first, then song; the
    // explicit host then attaches the real canvas into the rig's window
    // and engine with the canonical viewport geometry.
    rig->m_view->setDocument(&document);
    rig->m_view->setSong(rig->m_timeline.get(), config.voicegroup);
    rig->m_host = std::make_unique<QuickSceneHost>(*rig->m_view, config.viewSize);
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
    rig->m_quickRoot = quickCanvas->rootObject();
    rig->m_quickScene = rig->m_view->findChild<songview::TimelineQuickScene *>();
    rig->m_voiceInput = rig->inputItem(QStringLiteral("timelineVoiceChangesInput"));
    if (!rig->m_quickRoot || !rig->m_quickScene) {
        error = QStringLiteral("concrete SongView did not expose the Quick canvas root or scene");
        return nullptr;
    }
    if (!rig->m_voiceInput) {
        error = QStringLiteral("concrete SongView did not expose the voice Quick input item");
        return nullptr;
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
