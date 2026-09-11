#pragma once

#include <QObject>
#include <QString>
#include <QTemporaryDir>

#include "ui/keymap.h"

class KeymapCheckTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(KeymapCheckTest)

  public:
    KeymapCheckTest() = default;

  private slots:
    void initTestCase();

    void defaultMatching_data();
    void defaultMatching();
    void modifierChords();

  private:
    bool matches(const QString &id, int key, Qt::KeyboardModifiers modifiers) const;
    QTemporaryDir m_settingsDirectory;
};

int runKeymapCheck(const QStringList &qtArguments);
