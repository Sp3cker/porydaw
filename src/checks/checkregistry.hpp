#pragma once

#include <optional>

#include <QStringList>

class QApplication;

namespace checks {

bool writeManifest(const QStringList &arguments);
std::optional<int> runRequested(QApplication &application, const QStringList &arguments);

} // namespace checks
