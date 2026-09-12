#include "themecontroller.h"

#include "theme.h"
#include "themeresolver.h"
#include "themeruntime.h"

#include <QApplication>
#include <QSettings>
#include <QtGlobal>
#include <algorithm>

namespace themes {
namespace {

const auto modeKey = QStringLiteral("theme/mode");
const auto gridLineContrastKey = QStringLiteral("theme/grid-line-contrast");

bool isValid(const ThemeSelection &selection)
{
    // Dialog drafts are always in range; retain this guard as deliberate API defense.
    return selection.gridLineContrast >= 0 && selection.gridLineContrast <= 100;
}

} // namespace

ThemeController::ThemeController(QApplication &application, QSettings &settings)
    : m_application(application)
    , m_settings(settings)
{}

void ThemeController::restore()
{
    removeLegacyCustomKeys();
    // Reading and writing settings is intentional startup repair: it removes
    // stale keys and canonicalizes malformed, partial, or lowercase settings.
    m_selection = readStoredSelection();
    writeStoredSelection(m_selection);
    apply(m_application, resolve(m_selection));
}

void ThemeController::preview(const ThemeSelection &candidate)
{
    if (isValid(candidate))
        apply(m_application, resolve(candidate));
}

bool ThemeController::commit(const ThemeSelection &candidate)
{
    if (!isValid(candidate))
        return false;
    writeStoredSelection(candidate);
    apply(m_application, resolve(candidate));
    m_selection = candidate;
    return true;
}

void ThemeController::discardPreview()
{
    apply(m_application, resolve(m_selection));
}

const ThemeSelection &ThemeController::committedSelection() const
{
    return m_selection;
}

Theme ThemeController::resolve(const ThemeSelection &selection) const
{
    switch (selection.mode) {
    case ThemeMode::Vanilla:
        return withGridLineContrast(vanilla(), selection.gridLineContrast);
    case ThemeMode::DarkNeutralHigh:
        return withGridLineContrast(darkNeutralHigh(), selection.gridLineContrast);
    case ThemeMode::Immaterial:
        return withGridLineContrast(immaterial(), selection.gridLineContrast);
    }
    Q_UNREACHABLE();
}

void ThemeController::removeLegacyCustomKeys()
{
    if (m_settings.contains(QStringLiteral("theme/primary")) ||
        m_settings.contains(QStringLiteral("theme/accent"))) {
        m_settings.remove(QStringLiteral("theme/primary"));
        m_settings.remove(QStringLiteral("theme/accent"));
    }
}

ThemeSelection ThemeController::readStoredSelection() const
{
    auto contrastValid = false;
    const auto storedContrast =
        m_settings.value(gridLineContrastKey, defaultGridLineContrast).toInt(&contrastValid);
    const auto gridLineContrast =
        contrastValid ? std::clamp(storedContrast, 0, 100) : defaultGridLineContrast;
    const auto mode = m_settings.value(modeKey).toString();
    if (mode == QStringLiteral("vanilla"))
        return ThemeSelection{ThemeMode::Vanilla, gridLineContrast};
    if (mode == QStringLiteral("dark-neutral-high"))
        return ThemeSelection{ThemeMode::DarkNeutralHigh, gridLineContrast};
    if (mode == QStringLiteral("immaterial"))
        return ThemeSelection{ThemeMode::Immaterial, gridLineContrast};
    return ThemeSelection{ThemeMode::Vanilla, gridLineContrast};
}

void ThemeController::writeStoredSelection(const ThemeSelection &selection)
{
    m_settings.setValue(gridLineContrastKey, selection.gridLineContrast);
    switch (selection.mode) {
    case ThemeMode::Vanilla:
        m_settings.setValue(modeKey, QStringLiteral("vanilla"));
        return;
    case ThemeMode::DarkNeutralHigh:
        m_settings.setValue(modeKey, QStringLiteral("dark-neutral-high"));
        return;
    case ThemeMode::Immaterial:
        m_settings.setValue(modeKey, QStringLiteral("immaterial"));
        return;
    }
    Q_UNREACHABLE();
}

} // namespace themes
