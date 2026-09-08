#include "checks/nativegraphics/nativegraphics_fixture.h"

#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"

namespace checks::nativegraphics {

Rig::~Rig() = default;

std::unique_ptr<Rig> makeRig(const QString &projectRoot, const QString &songLabel,
                             const QSize &size, QString &error)
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

    // Shared direct unhosted framing: the real Quick window is resized,
    // exposed, and pumped so window-driven layout settles.
    if (!checks::support::showQuickViewport(song->view(), size)) {
        error = QStringLiteral("SongView rig exposed no Quick window");
        return nullptr;
    }
    return std::make_unique<Rig>(std::move(project), std::move(song));
}

} // namespace checks::nativegraphics
