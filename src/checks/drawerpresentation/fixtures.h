#pragma once

#include <memory>
#include <vector>

#include <QByteArray>
#include <QColor>
#include <QEvent>
#include <QPointF>
#include <QRect>
#include <QString>
#include <QTemporaryDir>

#include "core/songdocument.h"
#include "ui/editorviewstate.h"
#include "ui/songtab.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/timelinebandlayout.h"

extern "C" {
#include "voicegroup_loader.h"
}

class MidiTimeline;
class SongView;
class VelocityArea;
class DrawerChrome;
class QQuickItem;
class QObject;

namespace checks {
class EditorRig;
}
namespace songview {
class TimelineInputItem;
class TimelineQuickView;
} // namespace songview

namespace checks::drawerpresentation {

struct Snapshot {
    QByteArray smf;
    uint64_t revision = 0;
    int undoIndex = 0;

    bool operator==(const Snapshot &) const = default;
};

struct DrawerFixture {
    LoadedVoiceGroup voicegroup{};
    std::unique_ptr<SongTab> tab;
    SongView *view = nullptr;
    songview::TimelineQuickView *quick = nullptr;
    QQuickItem *quickRoot = nullptr;
    songview::TimelineInputItem *voiceHandle = nullptr;
    songview::TimelineInputItem *velocityHandle = nullptr;
    songview::TimelineInputItem *automationHandle = nullptr;
    songview::TimelineInputItem *bar = nullptr;
    songview::TimelineInputItem *detent = nullptr;

    DrawerFixture() = default;
    ~DrawerFixture();
    DrawerFixture(DrawerFixture &&) noexcept = default;
    DrawerFixture &operator=(DrawerFixture &&) noexcept = default;

    DrawerFixture(const DrawerFixture &) = delete;
    DrawerFixture &operator=(const DrawerFixture &) = delete;

    bool create(QString &error);
    void destroy();
    DrawerChrome &chrome() const;
    QRect bandRect(songview::TimelineBand band) const;
    void clickToggle(EditorDrawerPage page) const;
};

struct VoiceFixture {
    QTemporaryDir directory;
    SongDocument document;
    LoadedVoiceGroup voicegroup{};
    std::unique_ptr<checks::EditorRig> rig;

    bool create(QString &error);
    void destroy();
    Snapshot snapshot();
    QRect bandRect() const;
    QRect plotRect() const;
    int fixedSpan() const;
    double xForTick(double tick) const;
    songview::TimelineInputItem &input() const;
    songview::TimelineQuickScene *scene() const;
};

struct VoiceTransactionFixture {
    LoadedVoiceGroup voicegroup{};
    std::unique_ptr<SongTab> tab;

    ~VoiceTransactionFixture();
    bool create(QString &error);
    void destroy();
    SongDocument &document();
    Snapshot snapshot();
    QRect bandRect();
    double xForTick(double tick);
    SongView &view();
    songview::TimelineInputItem &input();
};

struct VelocityTransactionFixture {
    LoadedVoiceGroup voicegroup{};
    std::unique_ptr<SongTab> tab;
    std::vector<DocNote> notes;

    ~VelocityTransactionFixture();
    bool create(QString &error);
    void destroy();
    SongDocument &document();
    Snapshot snapshot();
    SongView &view();
    VelocityArea &area();
    songview::TimelineInputItem &input();
    double xForTick(double tick);
};

struct VelocityFixture {
    QTemporaryDir directory;
    SongDocument document;
    LoadedVoiceGroup voicegroup{};
    std::unique_ptr<checks::EditorRig> rig;
    std::vector<DocNote> notes;
    VelocityArea *area = nullptr;
    DrawerChrome *drawerChrome = nullptr;
    songview::TimelineInputItem *inputItem = nullptr;
    songview::TimelineInputItem *gutterItem = nullptr;
    songview::TimelineInputItem *barItem = nullptr;
    songview::TimelineInputItem *detentItem = nullptr;

    bool create(QString &error);
    void destroy();
    Snapshot snapshot();
    QRect bandRect() const;
    QRect plotRect() const;
    int fixedSpan() const;
    double xForTick(double tick) const;
    void refresh(bool playing = false, double playheadTick = 0.0);
};

void pump();
void sendMouse(songview::TimelineInputItem &input, QEvent::Type type, const QPointF &position,
               Qt::MouseButton button = Qt::NoButton, Qt::MouseButtons buttons = Qt::NoButton,
               Qt::KeyboardModifiers modifiers = Qt::NoModifier);
void sendKey(QObject &target, int key, Qt::KeyboardModifiers modifiers = Qt::NoModifier);

bool layerTouches(const songview::TimelineQuickScene &scene, songview::TimelineQuickLayer layer,
                  const QRectF &probe, const QColor &color);
bool layerEmpty(const songview::TimelineQuickScene &scene, songview::TimelineQuickLayer layer);

} // namespace checks::drawerpresentation
