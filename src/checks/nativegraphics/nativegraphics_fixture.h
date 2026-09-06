#pragma once

#include <QSize>
#include <QString>

#include <memory>

namespace checks {
class ProjectFixture;
class SongViewRig;
} // namespace checks

namespace checks::nativegraphics {

struct Rig final {
    ~Rig();

    std::unique_ptr<ProjectFixture> project;
    std::unique_ptr<SongViewRig> song;
};

std::unique_ptr<Rig> makeRig(const QString &projectRoot, const QString &songLabel,
                             const QSize &size, bool shown, QString &error);

} // namespace checks::nativegraphics
