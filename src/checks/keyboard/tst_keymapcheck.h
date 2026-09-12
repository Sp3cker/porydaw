#pragma once

#include <QObject>
#include <QString>

#include "ui/keymap.h"

class KeymapCheckTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(KeymapCheckTest)

  public:
    KeymapCheckTest() = default;

  private slots:
    void keymapSettingsSeedsAreIgnored();

    void defaultMatching_data();
    void defaultMatching();
    void modifierChords();

  private:
    bool matches(const QString &id, int key, Qt::KeyboardModifiers modifiers) const;
    // No QSettings isolation: keymapSettingsSeedsAreIgnored() seeds the real
    // user-scope keymap/ store on purpose.
};

int runKeymapCheck(const QStringList &qtArguments);
