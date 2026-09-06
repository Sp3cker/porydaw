#include "checks/keyboard/tst_keymapcheck.h"

#include <QAbstractItemView>
#include <QComboBox>
#include <QDialog>
#include <QKeySequenceEdit>
#include <QLineEdit>
#include <QPushButton>
#include <QScrollBar>
#include <QTreeWidget>
#include <QVBoxLayout>
#include <QtTest>

#include "ui/keyboardshortcutsdialog.h"

QTreeWidgetItem *KeymapCheckTest::findCommandItem(QTreeWidget *tree, const QString &id)
{
    for (int categoryIndex = 0; categoryIndex < tree->topLevelItemCount(); ++categoryIndex) {
        QTreeWidgetItem *const category = tree->topLevelItem(categoryIndex);
        for (int commandIndex = 0; commandIndex < category->childCount(); ++commandIndex) {
            QTreeWidgetItem *const item = category->child(commandIndex);
            if (item->data(0, Qt::UserRole).toString() == id)
                return item;
        }
    }
    return nullptr;
}

QPushButton *KeymapCheckTest::findButton(QWidget *root, const QString &text)
{
    const QList<QPushButton *> buttons = root->findChildren<QPushButton *>();
    for (QPushButton *const button : buttons) {
        if (button->text() == text)
            return button;
    }
    return nullptr;
}

void KeymapCheckTest::showDialog(QDialog &dialog)
{
    dialog.resize(520, 560);
    dialog.show();
    QTRY_VERIFY(dialog.isVisible());
}

void KeymapCheckTest::columnFitsContent()
{
    QDialog dialog;
    auto *const layout = new QVBoxLayout(&dialog);
    layout->addWidget(new KeyboardShortcutsWidget(&dialog));
    showDialog(dialog);

    auto *const tree = dialog.findChild<QTreeWidget *>();
    QVERIFY(tree);
    const int contentWidth = static_cast<QAbstractItemView *>(tree)->sizeHintForColumn(0);
    QVERIFY(tree->columnWidth(0) >= contentWidth);
}

void KeymapCheckTest::keypadCaptureShedsKeypadModifier()
{
    QDialog dialog;
    auto *const layout = new QVBoxLayout(&dialog);
    layout->addWidget(new KeyboardShortcutsWidget(&dialog));
    showDialog(dialog);

    auto *const tree = dialog.findChild<QTreeWidget *>();
    auto *const capture = dialog.findChild<QKeySequenceEdit *>();
    QPushButton *const assign = findButton(&dialog, QStringLiteral("&Assign"));
    QVERIFY(tree);
    QVERIFY(capture);
    QVERIFY(assign);

    QTreeWidgetItem *const copy = findCommandItem(tree, QStringLiteral("roll.copy"));
    QVERIFY(copy);
    tree->setCurrentItem(copy);
    const QKeySequence keypadShiftUp(
        QKeyCombination(Qt::ShiftModifier | Qt::KeypadModifier, Qt::Key_Up));
    const QKeySequence shiftUp(QKeyCombination(Qt::ShiftModifier, Qt::Key_Up));
    capture->setKeySequence(keypadShiftUp);
    QCOMPARE(capture->keySequence(), shiftUp);
    assign->click();
    QCOMPARE(keymap::Registry::instance().bindings(QStringLiteral("roll.copy")),
             QList<QKeySequence>{shiftUp});
}

void KeymapCheckTest::filterNarrowsRows_data()
{
    QTest::addColumn<QString>("filter");
    QTest::addColumn<QString>("id");
    QTest::addColumn<bool>("visible");

    QTest::newRow("transpose-hides-find")
        << QStringLiteral("Transpose") << QStringLiteral("songs.find") << false;
    QTest::newRow("transpose-keeps-transpose")
        << QStringLiteral("Transpose") << QStringLiteral("roll.transpose_up") << true;
}

void KeymapCheckTest::filterNarrowsRows()
{
    QFETCH(QString, filter);
    QFETCH(QString, id);
    QFETCH(bool, visible);

    QDialog dialog;
    auto *const layout = new QVBoxLayout(&dialog);
    layout->addWidget(new KeyboardShortcutsWidget(&dialog));
    showDialog(dialog);

    auto *const tree = dialog.findChild<QTreeWidget *>();
    auto *const filterEdit = dialog.findChild<QLineEdit *>();
    QVERIFY(tree);
    QVERIFY(filterEdit);
    filterEdit->setText(filter);
    QTreeWidgetItem *const item = findCommandItem(tree, id);
    QVERIFY(item);
    QCOMPARE(!item->isHidden(), visible);
}

void KeymapCheckTest::stealUnbindsConflictAndPreservesScroll()
{
    auto &registry = keymap::Registry::instance();
    QDialog dialog;
    auto *const layout = new QVBoxLayout(&dialog);
    layout->addWidget(new KeyboardShortcutsWidget(&dialog));
    showDialog(dialog);

    auto *const tree = dialog.findChild<QTreeWidget *>();
    auto *const capture = dialog.findChild<QKeySequenceEdit *>();
    QPushButton *const assign = findButton(&dialog, QStringLiteral("&Assign"));
    QVERIFY(tree);
    QVERIFY(capture);
    QVERIFY(assign);

    QTreeWidgetItem *const copy = findCommandItem(tree, QStringLiteral("roll.copy"));
    QVERIFY(copy);
    tree->setCurrentItem(copy);
    capture->setKeySequence(QKeySequence(QStringLiteral("Ctrl+S")));
    QScrollBar *const scrollBar = tree->verticalScrollBar();
    QVERIFY(scrollBar);
    const int scrollBeforeAssign = scrollBar->maximum() / 2;
    scrollBar->setValue(scrollBeforeAssign);
    assign->click();

    QCOMPARE(registry.bindings(QStringLiteral("roll.copy")),
             QList<QKeySequence>{QKeySequence(QStringLiteral("Ctrl+S"))});
    QVERIFY(registry.isOverridden(QStringLiteral("file.save_song")));
    QVERIFY(registry.bindings(QStringLiteral("file.save_song")).isEmpty());
    QCOMPARE(scrollBar->value(), scrollBeforeAssign);

    QTreeWidgetItem *const updatedCopy = findCommandItem(tree, QStringLiteral("roll.copy"));
    QVERIFY(updatedCopy);
    QVERIFY(updatedCopy->text(1).contains(
        QKeySequence(QStringLiteral("Ctrl+S")).toString(QKeySequence::NativeText)));
    QVERIFY(updatedCopy->font(1).bold());
}

void KeymapCheckTest::perRowResetRestoresBothSides()
{
    auto &registry = keymap::Registry::instance();
    QDialog dialog;
    auto *const layout = new QVBoxLayout(&dialog);
    layout->addWidget(new KeyboardShortcutsWidget(&dialog));
    showDialog(dialog);

    auto *const tree = dialog.findChild<QTreeWidget *>();
    auto *const capture = dialog.findChild<QKeySequenceEdit *>();
    QPushButton *const assign = findButton(&dialog, QStringLiteral("&Assign"));
    QPushButton *const reset = findButton(&dialog, QStringLiteral("&Reset"));
    QVERIFY(tree);
    QVERIFY(capture);
    QVERIFY(assign);
    QVERIFY(reset);

    QTreeWidgetItem *const copy = findCommandItem(tree, QStringLiteral("roll.copy"));
    QVERIFY(copy);
    tree->setCurrentItem(copy);
    capture->setKeySequence(QKeySequence(QStringLiteral("Ctrl+S")));
    assign->click();

    tree->setCurrentItem(findCommandItem(tree, QStringLiteral("roll.copy")));
    reset->click();
    QVERIFY(!registry.isOverridden(QStringLiteral("roll.copy")));
    QTreeWidgetItem *const saveSong = findCommandItem(tree, QStringLiteral("file.save_song"));
    QVERIFY(saveSong);
    tree->setCurrentItem(saveSong);
    reset->click();
    QVERIFY(matches(QStringLiteral("file.save_song"), Qt::Key_S, Qt::ControlModifier));
}

void KeymapCheckTest::modifierChordPicker()
{
    auto &registry = keymap::Registry::instance();
    QDialog dialog;
    auto *const layout = new QVBoxLayout(&dialog);
    layout->addWidget(new KeyboardShortcutsWidget(&dialog));
    showDialog(dialog);

    auto *const tree = dialog.findChild<QTreeWidget *>();
    auto *const capture = dialog.findChild<QKeySequenceEdit *>();
    auto *const picker = dialog.findChild<QComboBox *>();
    QPushButton *const assign = findButton(&dialog, QStringLiteral("&Assign"));
    QPushButton *const reset = findButton(&dialog, QStringLiteral("&Reset"));
    QVERIFY(tree);
    QVERIFY(capture);
    QVERIFY(picker);
    QVERIFY(assign);
    QVERIFY(reset);

    QTreeWidgetItem *const unlock = findCommandItem(tree, QStringLiteral("velocity.detent_unlock"));
    QVERIFY(unlock);
    QVERIFY(unlock->parent());
    QCOMPARE(unlock->parent()->text(0), QStringLiteral("Velocity"));
    QCOMPARE(unlock->text(0), QStringLiteral("Unlock Detents (Hold)"));
#ifdef Q_OS_MACOS
    QCOMPARE(unlock->text(1), QStringLiteral("⌘"));
#else
    QCOMPARE(unlock->text(1), QStringLiteral("Ctrl"));
#endif
    tree->setCurrentItem(unlock);
    QVERIFY(picker->isVisible());
    QVERIFY(!capture->isVisible());
    const int unlockControlIndex = picker->findData(int(Qt::ControlModifier));
    const int unlockAltIndex = picker->findData(int(Qt::AltModifier));
    const int unlockControlAltIndex =
        picker->findData(int((Qt::ControlModifier | Qt::AltModifier).toInt()));
    QVERIFY(unlockControlIndex >= 0);
    QCOMPARE(picker->currentIndex(), unlockControlIndex);
    QCOMPARE(picker->count(), 3);
    QVERIFY(unlockAltIndex >= 0);
    QVERIFY(unlockControlAltIndex >= 0);
    QVERIFY(picker->findData(int(Qt::ShiftModifier)) < 0);
    QVERIFY(picker->findData(int((Qt::ControlModifier | Qt::ShiftModifier).toInt())) < 0);
    QVERIFY(picker->findData(int((Qt::ShiftModifier | Qt::AltModifier).toInt())) < 0);

#ifdef Q_OS_MACOS
    QCOMPARE(picker->itemText(unlockControlIndex), QStringLiteral("⌘"));
#else
    QCOMPARE(picker->itemText(unlockControlIndex), QStringLiteral("Ctrl"));
#endif

    QTreeWidgetItem *const drag = findCommandItem(tree, QStringLiteral("roll.velocity_drag"));
    QVERIFY(drag);
    tree->setCurrentItem(drag);
    QVERIFY(picker->isVisible());
    QVERIFY(!capture->isVisible());
    const int altIndex = picker->findData(int(Qt::AltModifier));
    const int controlIndex = picker->findData(int(Qt::ControlModifier));
    const int controlShiftIndex =
        picker->findData(int((Qt::ControlModifier | Qt::ShiftModifier).toInt()));
    const int shiftIndex = picker->findData(int(Qt::ShiftModifier));
    const int controlAltIndex =
        picker->findData(int((Qt::ControlModifier | Qt::AltModifier).toInt()));
    const int shiftAltIndex = picker->findData(int((Qt::ShiftModifier | Qt::AltModifier).toInt()));

    QVERIFY(altIndex >= 0);
    QVERIFY(controlIndex >= 0);
    QVERIFY(controlShiftIndex >= 0);
    QVERIFY(shiftIndex >= 0);
    QVERIFY(controlAltIndex >= 0);
    QVERIFY(shiftAltIndex >= 0);
    QCOMPARE(picker->count(), 6);
#ifdef Q_OS_MACOS
    QCOMPARE(picker->itemText(controlIndex), QStringLiteral("⌘"));
    QCOMPARE(picker->itemText(altIndex), QStringLiteral("⌥"));
    QCOMPARE(picker->itemText(controlShiftIndex), QStringLiteral("⇧⌘"));
#endif

    picker->setCurrentIndex(altIndex);
    assign->click();
    QCOMPARE(registry.modifierBinding(QStringLiteral("roll.velocity_drag")), Qt::AltModifier);
    QTreeWidgetItem *const updatedDrag =
        findCommandItem(tree, QStringLiteral("roll.velocity_drag"));
    QVERIFY(updatedDrag);
#ifdef Q_OS_MACOS
    QCOMPARE(updatedDrag->text(1), QStringLiteral("⌥"));
#else
    QCOMPARE(updatedDrag->text(1), QStringLiteral("Alt"));
#endif
    tree->setCurrentItem(updatedDrag);
    reset->click();
    QCOMPARE(registry.modifierBinding(QStringLiteral("roll.velocity_drag")), Qt::ControlModifier);
    tree->setCurrentItem(findCommandItem(tree, QStringLiteral("roll.copy")));
    QVERIFY(!picker->isVisible());
    QVERIFY(capture->isVisible());
}

int runKeymapCheck(const QStringList &qtArguments)
{
    KeymapCheckTest test;
    QStringList arguments{QStringLiteral("keymapcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
