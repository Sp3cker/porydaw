#pragma once

class QApplication;
class QSettings;

namespace themes {

struct Theme;

enum class ThemeMode { Vanilla, DarkNeutralHigh, Immaterial };

inline constexpr auto defaultGridLineContrast = 50;

struct ThemeSelection {
    ThemeMode mode = ThemeMode::Vanilla;
    int gridLineContrast = defaultGridLineContrast;
};

/// Owns the application's current theme.
///
/// Dialogs send the active mode and grid-line contrast here. They do not
/// apply colors or write settings themselves, so previews have one known
/// committed theme to return to.
class ThemeController
{
  public:
    ThemeController(QApplication &application, QSettings &settings);

    void restore();
    void preview(const ThemeSelection &candidate);
    bool commit(const ThemeSelection &candidate);
    void discardPreview();
    const ThemeSelection &committedSelection() const;

  private:
    void writeStoredSelection(const ThemeSelection &selection);
    Theme resolve(const ThemeSelection &selection) const;
    void removeLegacyCustomKeys();
    ThemeSelection readStoredSelection() const;

    QApplication &m_application;
    QSettings &m_settings;
    ThemeSelection m_selection;
};

} // namespace themes
