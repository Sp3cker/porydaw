#pragma once

#include <QString>

// The .porydaw/ sidecar directory at the project root: local sample provenance
// and recoverable trash that never belong in the repo, so creating it also
// adds it to the project's .gitignore.
namespace Sidecar {

QString dirPath(const QString &projectRoot);

// Creates <projectRoot>/.porydaw[/subdir] and, in a git checkout, appends
// ".porydaw/" to the root .gitignore unless some spelling of it is already
// listed. The .gitignore write is best-effort and silent on failure — like
// the sidecars themselves, never worth interrupting the user over.
bool ensureDir(const QString &projectRoot, const QString &subdir = QString());

} // namespace Sidecar
