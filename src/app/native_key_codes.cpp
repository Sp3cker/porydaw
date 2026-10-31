#include "native_key_codes.h"

#include <QtGui/qevent.h>

NativeKeyCodes::NativeKeyCodes(QObject *parent) : QObject(parent) {}

NativeKeyCodes::~NativeKeyCodes()
{
    if (m_target)
        m_target->removeEventFilter(this);
}

void NativeKeyCodes::setTarget(QQuickItem *target)
{
    if (m_target == target)
        return;
    if (m_target)
        m_target->removeEventFilter(this);
    m_target = target;
    if (m_target)
        m_target->installEventFilter(this);
    emit targetChanged();
}

bool NativeKeyCodes::eventFilter(QObject *watched, QEvent *event)
{
    switch (event->type()) {
    case QEvent::KeyPress:
    case QEvent::KeyRelease:
    case QEvent::ShortcutOverride: {
        const auto *key = static_cast<QKeyEvent *>(event);
        m_scanCode = key->nativeScanCode();
        m_virtualKey = key->nativeVirtualKey();
        break;
    }
    default:
        break;
    }
    return QObject::eventFilter(watched, event);
}
