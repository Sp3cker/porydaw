#pragma once

#include <QObject>
#include <QPointer>

class QEvent;
class QQuickItem;
class QQuickWindow;
class QQuickView;
class QQmlContext;
class QWidget;

class SongTabsModel;
class WorkspaceUi;

// Embeds one shared QQuickView; QML owns persistent pages and session commands.
// WorkspaceUi removes every page before this borrowed host is destroyed.
class WorkspaceQuickHost final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(WorkspaceQuickHost)

  public:
    // Model and command authority are borrowed and must outlive this host.
    WorkspaceQuickHost(SongTabsModel &model, WorkspaceUi &workspaceUi, QWidget &parent);
    ~WorkspaceQuickHost() override;

    // Embedded container owned by the supplied parent widget.
    QWidget *container() const noexcept { return m_container; }

    // The Quick window the pages render into; null only after teardown.
    QQuickWindow *window() const noexcept;

    // Sole explicit widget-to-editor focus entry.
    void focusEditor(Qt::FocusReason reason);

  protected:
    // Refreshes chrome after application appearance changes.
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    void refreshChrome();

    SongTabsModel &m_model;
    WorkspaceUi &m_workspaceUi;
    QQuickView *m_view = nullptr;
    QQmlContext *m_context = nullptr;
    // Guarded QML root used only by focusEditor().
    QPointer<QQuickItem> m_rootItem;
    QWidget *m_container = nullptr;
};
