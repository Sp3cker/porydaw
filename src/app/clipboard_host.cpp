#include "app/native_host.h"

#include <QByteArray>
#include <QClipboard>
#include <QGuiApplication>
#include <QMimeData>
#include <QObject>
#include <QThread>

#include <limits>

namespace {
constexpr auto kClipMimeType = "application/x-porydaw-clip";

bool onGuiThread()
{
    return qApp && QThread::currentThread() == qApp->thread();
}
} // namespace

extern "C" bool pd_clipboard_write(const uint8_t *bytes, size_t count)
{
    if (!onGuiThread() || (bytes == nullptr && count != 0) ||
        count > size_t((std::numeric_limits<qsizetype>::max)())) {
        return false;
    }
    auto *mime = new QMimeData;
    const QByteArray payload =
        count == 0 ? QByteArray{}
                   : QByteArray(reinterpret_cast<const char *>(bytes), qsizetype(count));
    mime->setData(kClipMimeType, payload);
    QGuiApplication::clipboard()->setMimeData(mime);
    return true;
}

extern "C" bool pd_clipboard_read(void *context, PdConsumeBytesCallback consume)
{
    if (!onGuiThread() || consume == nullptr)
        return false;
    const QMimeData *mime = QGuiApplication::clipboard()->mimeData();
    if (!mime || !mime->hasFormat(kClipMimeType))
        return false;
    const QByteArray payload = mime->data(kClipMimeType);
    consume(context, reinterpret_cast<const uint8_t *>(payload.constData()),
            size_t(payload.size()));
    return true;
}

extern "C" void *pd_clipboard_observe(void *context, PdClipboardChangedCallback changed)
{
    if (!onGuiThread() || changed == nullptr)
        return nullptr;
    auto *clipboard = QGuiApplication::clipboard();
    auto *observer = new QObject(clipboard);
    QObject::connect(clipboard, &QClipboard::dataChanged, observer,
                     [context, changed] { changed(context); });
    return observer;
}

extern "C" void pd_clipboard_unobserve(void *token)
{
    if (onGuiThread())
        delete static_cast<QObject *>(token);
}
