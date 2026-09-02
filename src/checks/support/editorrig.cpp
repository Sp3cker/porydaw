#include "checks/support/editorrig.h"

#include <utility>

#include <QCoreApplication>
#include <QQuickItem>

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"

namespace checks {

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
    rig->m_view->resize(config.viewSize);
    // Production wiring order (SongTab): document first, then song.
    rig->m_view->setDocument(&document);
    rig->m_view->setSong(rig->m_timeline.get(), config.voicegroup);
    if (config.track >= 0)
        rig->m_view->selectTrack(config.track);
    rig->m_view->setDrawerActivePage(config.activePage);
    for (const EditorRigSection &section : config.sections) {
        rig->m_view->setDrawerSectionVisible(section.page, true);
        rig->m_view->setDrawerSectionHeight(section.page, section.height);
    }
    if (config.show) {
        rig->m_view->show();
        QCoreApplication::processEvents();
    }
    auto *quickCanvas = rig->m_view->findChild<songview::TimelineQuickView *>(
        QStringLiteral("timelineQuickCanvas"));
    rig->m_quickRoot = quickCanvas ? quickCanvas->rootObject() : nullptr;
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
