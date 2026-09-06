#pragma once

#include <QKeySequence>
#include <QObject>
#include <QString>
#include <QTemporaryDir>

#include "ui/keymap.h"

class QComboBox;
class QDialog;
class QKeySequenceEdit;
class QLineEdit;
class QPushButton;
class QWidget;
class QTreeWidget;
class QTreeWidgetItem;

class KeymapCheckTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(KeymapCheckTest)

  public:
    KeymapCheckTest() = default;

  private slots:
    void initTestCase();
    void init();
    void cleanup();

    void shippedTable();
    void preferencesDefaultBinding();
    void defaultMatching_data();
    void defaultMatching();
    void overrideReplacesDefaultAndPersists();
    void unbindPersistsEmptyDelta();
    void resetSemantics();
    void snapshotRestore();
    void attachedActionTracksBinding();
    void conflicts_data();
    void conflicts();
    void routedCommandConflicts_data();
    void routedCommandConflicts();
    void modifierChords();

    void columnFitsContent();
    void keypadCaptureShedsKeypadModifier();
    void filterNarrowsRows_data();
    void filterNarrowsRows();
    void stealUnbindsConflictAndPreservesScroll();
    void perRowResetRestoresBothSides();
    void modifierChordPicker();

  private:
    bool matches(const QString &id, int key, Qt::KeyboardModifiers modifiers) const;
    static QTreeWidgetItem *findCommandItem(QTreeWidget *tree, const QString &id);
    static QPushButton *findButton(QWidget *root, const QString &text);
    static void showDialog(QDialog &dialog);
    keymap::Registry::OverrideSnapshot m_snapshot;
    QTemporaryDir m_settingsDirectory;
};

int runKeymapCheck(const QStringList &qtArguments);
