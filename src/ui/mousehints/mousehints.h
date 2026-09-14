#pragma once

#include "ui/mousehints/hintprofiles.h"

#include <QObject>
#include <QPointer>
#include <QString>

class QStatusBar;
class QWidget;
class QWindow;

namespace ui {

class WidgetHintsObserver;

/// Application-wide owner of the middle status-bar hint that lists a hovered
/// target's existing modifier-dependent mouse alternatives. One instance lives
/// under the live QApplication on the GUI thread; it tracks the single current
/// hint source (a QWidget or QQuickItem), its text, and the native/application
/// input scope that gates claims. Producers classify existing targets into
/// hint_profiles::Id; the owned catalogue renders their wording.
class MouseHints final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(MouseHints)

  public:
    /// The application-owned service. Callers must hold a live QApplication on
    /// the GUI thread; teardown must not recreate it.
    static MouseHints &instance();

    /// Installs native observation and the middle status region once. Qt owns
    /// the bar's children, not the service. Defined in widgethints.cpp.
    void install(QStatusBar &bar);

    /// Makes `source` the current hint owner with `profile`. Replaces
    /// ownership even for an identical profile; Empty is a real claim by a
    /// no-hint target. Sources outside the current native/application input
    /// scope are rejected.
    Q_INVOKABLE void claim(QObject *source, ui::hint_profiles::Id profile);

    /// Ends `source`'s ownership. Only the current owner can clear; unhover
    /// uses this rather than claiming an empty profile.
    Q_INVOKABLE void clear(QObject *source);

    QObject *currentSource() const { return m_source; }
    QString currentText() const { return m_text; }

    /// Replaces the widget family's inferred hint with a complete profile
    /// whose catalogue entry already includes inherited wheel behavior.
    /// Defined in widgethints.cpp.
    static void setWidgetProfile(QWidget &widget, ui::hint_profiles::Id profile);

    /// The same native/application input-scope predicate claim() applies,
    /// exposed for a physical host's discrete resync. This is not action
    /// eligibility.
    bool allowsNativeInput(QObject *source) const;

  signals:
    /// Emitted only when the displayed text changes, not on owner identity
    /// changes alone.
    void hintChanged(const QString &text);
    /// One coalesced queued notification after native input-scope recovery or
    /// application reactivation. Receivers re-evaluate their current target.
    void scopeRefresh();

  private:
    explicit MouseHints(QObject *parent);

    /// The QWindow a source's input arrives through: the widget's window
    /// handle or the item's QQuickWindow.
    static QWindow *sourceWindow(QObject *source);
    void observeSource(QObject *source);
    void clearCurrentSource();
    /// Queues one scopeRefresh emission; repeated requests coalesce.
    void requestScopeRefresh();

    /// claim() plus the native spin style's step modifier; the catalogue
    /// resolves the profile's rendered text only after scope admission.
    /// WidgetHintsObserver is the only caller.
    void claim(QObject *source, ui::hint_profiles::Id profile, Qt::KeyboardModifiers stepModifier);

    /// Dynamic-property key the observer mirrors Qt's delivered
    /// WindowBlocked/WindowUnblocked state onto each observed QWindow.
    static constexpr char nativeWindowBlockedProperty[] = "porydaw.nativeWindowBlocked";

    friend class WidgetHintsObserver;

    QPointer<QObject> m_source;
    QString m_text;
    /// Application-lifetime catalogue; renders each profile's wording lazily
    /// on first claim.
    ui::hint_profiles::Catalog m_profiles;
    /// The one application observer created by install(); repeated MainWindow
    /// installations reuse it.
    QPointer<WidgetHintsObserver> m_nativeAdapter;
    bool m_scopeRefreshQueued = false;
};

} // namespace ui
