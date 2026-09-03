#include "pluginmanifest.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QRegularExpression>

namespace scripting {

bool PluginManifest::validId(const QString &id)
{
    static const QRegularExpression pattern(QStringLiteral("^[a-z0-9][a-z0-9_-]*$"));
    return pattern.match(id).hasMatch();
}

bool PluginManifest::parse(const QByteArray &json, PluginManifest *out, QString *error)
{
    const auto fail = [&](const QString &why) {
        if (error)
            *error = why;
        return false;
    };
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &parseError);
    if (doc.isNull())
        return fail(QCoreApplication::translate("PluginManifest", "plugin.json: %1 at offset %2")
                        .arg(parseError.errorString())
                        .arg(parseError.offset));
    if (!doc.isObject())
        return fail(QCoreApplication::translate("PluginManifest",
                                                "plugin.json: top level must be an object"));
    const QJsonObject obj = doc.object();

    PluginManifest m;
    m.id = obj.value(QLatin1String("id")).toString();
    if (!validId(m.id))
        return fail(QCoreApplication::translate(
            "PluginManifest", "plugin.json: \"id\" must be lowercase letters, digits, '-' or '_'"));
    m.name = obj.value(QLatin1String("name")).toString();
    if (m.name.isEmpty())
        m.name = m.id;
    m.version = obj.value(QLatin1String("version")).toString(QStringLiteral("0.0.0"));
    m.description = obj.value(QLatin1String("description")).toString();
    const QJsonValue main = obj.value(QLatin1String("main"));
    if (main.isString() && !main.toString().isEmpty())
        m.main = main.toString();
    if (m.main.contains(QLatin1String("..")) || m.main.startsWith(QLatin1Char('/')))
        return fail(QCoreApplication::translate("PluginManifest",
                                                "plugin.json: \"main\" must stay inside the "
                                                "plugin directory"));

    const QJsonValue api = obj.value(QLatin1String("api"));
    if (api.isDouble()) {
        m.apiMajor = int(api.toDouble());
    } else if (api.isString()) {
        static const QRegularExpression leadingInt(QStringLiteral("^\\s*[>=^~]*\\s*(\\d+)"));
        const auto match = leadingInt.match(api.toString());
        m.apiMajor = match.hasMatch() ? match.captured(1).toInt() : 0;
    }
    if (m.apiMajor <= 0)
        return fail(
            QCoreApplication::translate("PluginManifest",
                                        "plugin.json: \"api\" must name the API major version (%1)")
                .arg(kApiMajor));
    if (m.apiMajor != kApiMajor)
        return fail(
            QCoreApplication::translate(
                "PluginManifest", "plugin needs scripting API %1 but this porydaw provides API %2")
                .arg(m.apiMajor)
                .arg(kApiMajor));

    for (const QJsonValue &v : obj.value(QLatin1String("permissions")).toArray()) {
        if (v.isString())
            m.permissions.append(v.toString());
    }
    *out = m;
    return true;
}

} // namespace scripting
