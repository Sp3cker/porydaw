#include "checkregistry.hpp"
#include "checkcatalog.h"

#include "ui/applicationstartup.h"

#include <algorithm>
#include <cstdio>

#include <QApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QSettings>
#include <QTemporaryDir>

namespace checks {
namespace {
using detail::BinaryKind;
using detail::CheckDefinition;
using detail::FixtureRootKind;
using detail::Framework;
using detail::ScratchKind;
using detail::StartupKind;
using detail::Windowing;

QJsonObject jsonObject(const QMap<QString, QString> &values)
{
    auto result = QJsonObject{};
    for (auto it = values.cbegin(); it != values.cend(); ++it)
        result.insert(it.key(), it.value());
    return result;
}

QString jsonName(ScratchKind kind)
{
    switch (kind) {
    case ScratchKind::Unused:
        return QStringLiteral("unused");
    case ScratchKind::ExistingDirectory:
        return QStringLiteral("existing-directory");
    case ScratchKind::MustNotExistPath:
        return QStringLiteral("must-not-exist-path");
    }
    Q_UNREACHABLE();
}

QString jsonName(FixtureRootKind kind)
{
    switch (kind) {
    case FixtureRootKind::None:
        return QStringLiteral("none");
    case FixtureRootKind::DecompProject:
        return QStringLiteral("decomp-project");
    case FixtureRootKind::SongsMkProject:
        return QStringLiteral("songs-mk-project");
    }
    Q_UNREACHABLE();
}

QString jsonName(BinaryKind kind)
{
    switch (kind) {
    case BinaryKind::Checks:
        return QStringLiteral("checks");
    case BinaryKind::Application:
        return QStringLiteral("application");
    }
    Q_UNREACHABLE();
}

QString jsonName(Windowing windowing)
{
    switch (windowing) {
    case Windowing::Offscreen:
        return QStringLiteral("offscreen");
    case Windowing::WindowSystem:
        return QStringLiteral("window-system");
    }
    Q_UNREACHABLE();
}

QString jsonName(Framework framework)
{
    switch (framework) {
    case Framework::QtTest:
        return QStringLiteral("qt-test");
    case Framework::Process:
        return QStringLiteral("process");
    }
    Q_UNREACHABLE();
}

QJsonObject manifestEntry(const CheckDefinition &definition)
{
    auto entry = QJsonObject{
        {QStringLiteral("name"), QString::fromUtf8(definition.name)},
        {QStringLiteral("argv"), QJsonArray::fromStringList(definition.argv)},
        {QStringLiteral("scratchKind"), jsonName(definition.scratchKind)},
        {QStringLiteral("fixtureRootKind"), jsonName(definition.fixtureRootKind)},
        {QStringLiteral("fixtureFiles"), QJsonArray::fromStringList(definition.fixtureFiles)},
        {QStringLiteral("binary"), jsonName(definition.binary)},
        {QStringLiteral("windowing"), jsonName(definition.windowing)},
        {QStringLiteral("framework"), jsonName(definition.framework)},
        {QStringLiteral("optIn"), definition.optIn},
    };
    if (!definition.environment.isEmpty())
        entry.insert(QStringLiteral("environment"), jsonObject(definition.environment));
    if (!definition.optionalArgumentEnvironment.isEmpty())
        entry.insert(QStringLiteral("optionalArgumentEnvironment"),
                     jsonObject(definition.optionalArgumentEnvironment));
    return entry;
}

} // namespace

bool writeManifest(const QStringList &arguments)
{
    if (!arguments.contains(QStringLiteral("--manifest")))
        return false;
    auto checks = QJsonArray{};
    for (const auto &definition : detail::catalog())
        checks.push_back(manifestEntry(definition));
    const auto document = QJsonDocument{QJsonObject{
        {QStringLiteral("checks"), checks},
    }};
    const auto json = document.toJson(QJsonDocument::Compact);
    std::fwrite(json.constData(), 1, size_t(json.size()), stdout);
    std::fputc('\n', stdout);
    return true;
}

std::optional<int> runRequested(QApplication &application, const QStringList &arguments)
{
    // The check command is anchored at argv[1]; a terminal "--qt" separator
    // splits Qt test payload off before any check argument is interpreted, so
    // optional check arguments (sample corpus, screenshots) can never eat Qt
    // flags. The payload is forwarded to the row's single qExec verbatim.
    const auto qtSeparator = arguments.indexOf(QStringLiteral("--qt"));
    for (const auto &definition : detail::catalog()) {
        if (!definition.handler || arguments.value(1) != definition.argv.value(0))
            continue;
        auto qtArguments = QStringList{};
        auto checkArguments = arguments.mid(1);
        if (qtSeparator > 0) {
            qtArguments = arguments.mid(qtSeparator + 1);
            checkArguments = arguments.mid(1, qtSeparator - 1);
        }
        const auto requiredArguments = std::count_if(
            definition.argv.cbegin(), definition.argv.cend(), [&](const auto &argument) {
                return !definition.optionalArgumentEnvironment.contains(argument);
            });
        if (checkArguments.size() < requiredArguments) {
            std::fprintf(stderr, "porydaw_checks: %s requires %lld argument(s)\n", definition.name,
                         static_cast<long long>(requiredArguments - 1));
            return 2;
        }
        if (definition.startup == StartupKind::HandlerOwned)
            return definition.handler(application, checkArguments, qtArguments);
        auto settingsDirectory = QTemporaryDir{};
        if (!settingsDirectory.isValid())
            return 1;
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDirectory.path());
        if (!ui::initializePorydawApplication(application))
            return 1;
        return definition.handler(application, checkArguments, qtArguments);
    }
    return std::nullopt;
}

} // namespace checks
