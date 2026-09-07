#pragma once

#include <QPoint>
#include <QQuickItem>
#include <QQuickWindow>
#include <QString>
#include <QtTest>

#include <array>

#include "checks/quickpopupguard.h"

namespace checks::voicepicker {

struct Picker final {
    songview::QuickPopupSession *session = nullptr;
    QQuickWindow *window = nullptr;
    QQuickItem *root = nullptr;
    QQuickItem *search = nullptr;
    QQuickItem *list = nullptr;
    QQuickItem *accept = nullptr;
    QQuickItem *cancel = nullptr;

    explicit operator bool() const noexcept
    {
        return session && window && root && search && list && accept && cancel;
    }
};

inline QQuickItem *visualDescendant(QQuickItem *root, const QString &objectName)
{
    if (!root)
        return nullptr;
    if (root->objectName() == objectName)
        return root;
    for (QQuickItem *const child : root->childItems())
        if (QQuickItem *const found = visualDescendant(child, objectName))
            return found;
    return nullptr;
}

inline Picker active(SongView &view)
{
    songview::QuickPopupSession *const session = quick_popup::popupSession(view);
    QQuickWindow *const window = session && session->isOpen() ? session->window() : nullptr;
    if (!session || !window)
        return {};
    return {
        .session = session,
        .window = window,
        .root = quick_popup::promptItem(*session, QLatin1String("voicePickerPrompt")),
        .search = quick_popup::promptItem(*session, QLatin1String("voicePickerSearch")),
        .list = quick_popup::promptItem(*session, QLatin1String("voicePickerList")),
        .accept = quick_popup::promptItem(*session, QLatin1String("voicePickerAccept")),
        .cancel = quick_popup::promptItem(*session, QLatin1String("voicePickerCancel")),
    };
}

inline QQuickItem *row(const Picker &picker, int program)
{
    return visualDescendant(picker.root, QStringLiteral("voicePickerRow_%1").arg(program));
}

inline QPoint center(const QQuickItem &item)
{
    return item.mapToScene(QPointF(item.width() / 2.0, item.height() / 2.0)).toPoint();
}

inline void filter(const Picker &picker, const QString &text)
{
    QTest::keyClick(picker.window, Qt::Key_A, Qt::ControlModifier);
    QTest::keyClick(picker.window, Qt::Key_Backspace);
    for (const QChar character : text) {
        Qt::Key key = Qt::Key_unknown;
        if (character >= QLatin1Char('0') && character <= QLatin1Char('9'))
            key = Qt::Key(Qt::Key_0 + character.unicode() - QLatin1Char('0').unicode());
        else if (character >= QLatin1Char('a') && character <= QLatin1Char('z'))
            key = Qt::Key(Qt::Key_A + character.unicode() - QLatin1Char('a').unicode());
        else if (character == QLatin1Char('-'))
            key = Qt::Key_Minus;
        Q_ASSERT(key != Qt::Key_unknown);
        QTest::keyClick(picker.window, key);
    }
}

inline void accept(const Picker &picker)
{
    QTest::mouseClick(picker.window, Qt::LeftButton, Qt::NoModifier, center(*picker.accept));
}

inline void cancel(const Picker &picker)
{
    QTest::mouseClick(picker.window, Qt::LeftButton, Qt::NoModifier, center(*picker.cancel));
}

inline void hold(const Picker &picker, int program)
{
    QQuickItem *const item = row(picker, program);
    if (item)
        QTest::mousePress(picker.window, Qt::LeftButton, Qt::NoModifier, center(*item));
}

inline void release(const Picker &picker, int program)
{
    QQuickItem *const item = row(picker, program);
    if (item)
        QTest::mouseRelease(picker.window, Qt::LeftButton, Qt::NoModifier, center(*item));
}

inline bool dismissOutside(const Picker &picker)
{
    if (!picker.window || !picker.root || picker.window->width() < 3 || picker.window->height() < 3)
        return false;
    const int xInset = picker.window->width() / 8 > 0 ? picker.window->width() / 8 : 1;
    const int yInset = picker.window->height() / 8 > 0 ? picker.window->height() / 8 : 1;
    const std::array<QPoint, 4> candidates = {
        QPoint{xInset, yInset},
        QPoint{picker.window->width() - 1 - xInset, yInset},
        QPoint{xInset, picker.window->height() - 1 - yInset},
        QPoint{picker.window->width() - 1 - xInset, picker.window->height() - 1 - yInset},
    };
    for (const QPoint &target : candidates) {
        if (target.isNull())
            continue;
        const QPointF rootPoint = picker.root->mapFromScene(QPointF(target));
        if (picker.root->contains(rootPoint))
            continue;
        QTest::mouseClick(picker.window, Qt::LeftButton, Qt::NoModifier, target);
        return true;
    }
    return false;
}

} // namespace checks::voicepicker
