#pragma once

#include <QString>

namespace scripting {

// Add Plugin…: accepts either a plugin folder or its plugin.json and installs
// that folder into `pluginsRoot` as <pluginsRoot>/<basename>, copied whole
// (nested files included). False with *error (translated, user-facing) set
// when the selection is invalid, when the plugins folder is the source or
// lies inside it (symlinks included, so the copy can never walk into itself),
// or when the destination is taken — by a folder, a file, or even a broken
// link. Nothing is overwritten: the tree is built in a hidden staging folder
// next to the destination and renamed into place, so a plugin becomes visible
// only once it is complete, and a failed install leaves neither a destination
// nor staging debris. The caller reloads the host after true.
bool installPlugin(const QString &selection, const QString &pluginsRoot, QString *error = nullptr);

} // namespace scripting
