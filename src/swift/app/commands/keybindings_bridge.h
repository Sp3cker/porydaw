#pragma once

#include <QtCore/qlist.h>
#include <QtGui/qkeysequence.h>

inline int porydawStandardKeyBindingCount(int standard)
{
    return int(QKeySequence::keyBindings(QKeySequence::StandardKey(standard)).size());
}

inline QKeySequence porydawStandardKeyBindingAt(int standard, int index)
{
    return QKeySequence::keyBindings(QKeySequence::StandardKey(standard)).at(index);
}
