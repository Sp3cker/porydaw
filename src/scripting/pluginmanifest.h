#pragma once

#include <QByteArray>
#include <QString>
#include <QStringList>

namespace scripting {

// The scripting API's version (docs/scripting/PLAN.md §1 stance 7): a
// plugin's manifest names the major it was written against and the loader
// refuses any other. Minor/patch are informational (porydaw.api.version).
constexpr int kApiMajor = 1;
constexpr const char *kApiVersion = "1.0.0";

// plugin.json, one per plugin directory:
//
//   { "id": "legato-tools", "name": "Legato Tools", "version": "1.0.0",
//     "api": 1, "main": "main.js", "description": "…" }
//
// id: required, [a-z0-9_-]+, also the directory's expected name. api:
// required, the API major (a number, or a string whose leading integer is
// the major, so "1.0" and ">=1.0" also read as 1). main defaults to
// main.js, relative to the plugin directory.
struct PluginManifest {
    QString id;
    QString name;
    QString version;
    QString main = QStringLiteral("main.js");
    QString description;
    int apiMajor = 0;
    QStringList permissions;

    // Parses the JSON; on failure returns false with a user-facing reason.
    static bool parse(const QByteArray &json, PluginManifest *out, QString *error);
    static bool validId(const QString &id);
};

} // namespace scripting
