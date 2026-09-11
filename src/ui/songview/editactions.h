#pragma once

#include "ui/songview.h"

#include <QMetaObject>
#include <QObject>
#include <QPointer>

#include <array>
#include <cstddef>
#include <optional>
#include <vector>

class QAction;
class QWidget;

namespace songview {

class EditActions final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(EditActions)

  public:
    explicit EditActions(QObject *parent = nullptr);

    QAction *action(SongView::EditCommand command) const;
    void installWindowShortcuts(QWidget &window);
    std::optional<SongView::EditCommand> editorCommandForKey(int key,
                                                             Qt::KeyboardModifiers modifiers) const;
    void rebind(SongView *target);
    SongView *target() const;
    void refresh();

  private:
    static constexpr std::size_t cActionCount =
        static_cast<std::size_t>(SongView::EditCommand::MoveEventDown) + 1;

    void observeTarget(SongView &target);
    void disconnectTargetObservations();
    void updateClipboardEligibility();
    void execute(SongView::EditCommand command);
    bool copyFocusedText() const;
    bool focusedTextTarget() const;
    void refreshCheckedStates(SongView *target);

    std::array<QAction *, cActionCount> m_actions{};
    QPointer<SongView> m_target;
    std::vector<QMetaObject::Connection> m_targetConnections;
    bool m_clipboardEligible = false;
};

} // namespace songview
