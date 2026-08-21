#pragma once

#include <QWidget>

class QEvent;
class QComboBox;
class QKeySequenceEdit;
class QLabel;
class QLineEdit;
class QPushButton;
class QTreeWidget;
class QTreeWidgetItem;

// Edit-menu widget over keymap::Registry. Assign and Reset actions mutate the
// registry immediately; an owning dialog can provide transactional Cancel
// behavior by snapshotting and restoring registry overrides.
class KeyboardShortcutsWidget : public QWidget
{
    Q_OBJECT

  public:
    explicit KeyboardShortcutsWidget(QWidget *parent = nullptr);

  protected:
    void changeEvent(QEvent *event) override;

  private:
    void rebuildTree();
    void applyFilter();
    void currentRowChanged();
    void captureChanged();
    void assign();
    void clearBinding();
    void resetBinding();
    void resetAll();
    QString currentCommandId() const;

    QLineEdit *m_filter = nullptr;
    QTreeWidget *m_tree = nullptr;
    QKeySequenceEdit *m_capture = nullptr;
    // Modifier commands (hold-and-drag gestures) pick from a chord list
    // instead of the key-sequence capture; the two swap per selected row.
    QComboBox *m_modCapture = nullptr;
    QPushButton *m_assignButton = nullptr;
    QPushButton *m_clearButton = nullptr;
    QPushButton *m_resetButton = nullptr;
    QLabel *m_conflictLabel = nullptr;
    QPushButton *m_resetAllButton = nullptr;
    // Guards the tree-refresh feedback loop while an assignment is applied.
    bool m_applying = false;
};
