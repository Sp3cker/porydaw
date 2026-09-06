#include "checks/nativegraphics/nativegraphics_fixture.h"

#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"

#include "ui/songview.h"

namespace checks::nativegraphics {

Rig::~Rig() = default;

std::unique_ptr<Rig> makeRig(const QString &projectRoot, const QString &songLabel,
                             const QSize &size, bool shown, QString &error)
{
    std::unique_ptr<ProjectFixture> project = ProjectFixture::copyOf(projectRoot, error);
    if (!project)
        return nullptr;

    std::unique_ptr<LoadedSong> loaded = LoadedSong::load(project->root(), songLabel, error);
    if (!loaded)
        return nullptr;

    std::unique_ptr<SongViewRig> song = SongViewRig::create(std::move(loaded), 48'000.0, error);
    if (!song)
        return nullptr;

    SongView &view = song->view();
    view.resize(size);
    if (shown)
        view.show();
    checks::support::pumpQuick();
    return std::make_unique<Rig>(std::move(project), std::move(song));
}

} // namespace checks::nativegraphics
