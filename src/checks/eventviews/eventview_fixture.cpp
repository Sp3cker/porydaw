#include "checks/eventviews/eventview_fixture.h"

#include <QComboBox>
#include <QCoreApplication>
#include <QMenu>
#include <QMetaObject>
#include <QTableView>

#include <algorithm>
#include <optional>
#include <utility>

#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "project/voicegroupsource.h"
#include "ui/eventlistview.h"
#include "ui/songtab.h"

namespace checks::eventviews {
namespace {

SmfEvent event(uint64_t tick, uint8_t status, uint8_t data0 = 0, uint8_t data1 = 0)
{
    SmfEvent value;
    value.tick = tick;
    value.status = status;
    value.data0 = data0;
    value.data1 = data1;
    return value;
}

SmfEvent meta(uint64_t tick, uint8_t type, QByteArray payload)
{
    SmfEvent value;
    value.tick = tick;
    value.status = 0xff;
    value.metaType = type;
    value.blob = std::move(payload);
    return value;
}

SmfFile fixtureSmf(FixtureShape shape)
{
    SmfFile smf;
    smf.format = 1;
    smf.division = shape == FixtureShape::Signatures ? 48 : 24;

    if (shape == FixtureShape::Empty) {
        smf.tracks.push_back(SmfTrack{{}, 120});
        return smf;
    }
    if (shape == FixtureShape::EotCoincident) {
        smf.tracks.push_back(SmfTrack{{meta(120, 0x06, QByteArrayLiteral("at end"))}, 120});
        return smf;
    }

    SmfTrack primary;
    primary.events = {
        meta(0, 0x58, QByteArray::fromHex("04021808")),
        meta(0, 0x06, QByteArrayLiteral("fixture marker")),
        event(0, 0xc0, 0),
        event(8, 0xb0, 7, 80),
        event(12, 0x90, 60, 90),
        event(30, 0x80, 60),
        meta(50, 0x58, QByteArray::fromHex("03021808")),
        event(60, 0xb0, 7, 20),
        event(60, 0xb0, 10, 30),
        event(70, 0x90, 64, 70),
        event(90, 0x80, 64),
    };
    if (shape == FixtureShape::Tempo)
        primary.events.insert(primary.events.begin(), meta(0, 0x51, QByteArray::fromHex("07a120")));
    if (shape == FixtureShape::Signatures)
        primary.events.insert(primary.events.begin() + 7,
                              meta(36, 0x58, QByteArray::fromHex("06031808")));
    primary.endTick = shape == FixtureShape::Long ? 500 : 120;
    if (shape == FixtureShape::Long) {
        for (uint64_t tick = 100; tick < 500; tick++)
            primary.events.push_back(event(tick, 0xb0, 11, uint8_t(tick % 127)));
    }
    smf.tracks.push_back(std::move(primary));
    smf.tracks.push_back(SmfTrack{{meta(5, 0x06, QByteArrayLiteral("metadata only"))}, 120});
    smf.tracks.push_back(SmfTrack{{event(0, 0xc1, 1), event(24, 0xb1, 7, 64),
                                   event(48, 0x90 | 1, 67, 90), event(72, 0x80 | 1, 67)},
                                  120});
    return smf;
}

SongInfo fixtureSong()
{
    SongInfo song;
    song.label = QStringLiteral("eventviews-fixture");
    song.hasMid = true;
    return song;
}

EventWidgets locateWidgets(SongView &view)
{
    view.setEventListVisible(true);
    QCoreApplication::processEvents();

    EventWidgets widgets;
    widgets.events = view.findChild<EventListView *>();
    widgets.table = view.findChild<QTableView *>(QStringLiteral("eventListTable"));
    widgets.chunkCombo = view.findChild<QComboBox *>(QStringLiteral("eventListChunk"));
    widgets.filterMenu = view.findChild<QMenu *>(QStringLiteral("eventListFilterMenu"));
    widgets.model =
        widgets.table ? static_cast<eventlist::EventTableModel *>(widgets.table->model()) : nullptr;
    return widgets;
}

} // namespace

std::unique_ptr<EventViewRigFixture> EventViewRigFixture::create(FixtureShape shape, QString &error)
{
    error.clear();
    auto fixture = std::unique_ptr<EventViewRigFixture>(new EventViewRigFixture);
    if (!fixture->m_document.adoptSmf(fixtureSmf(shape), fixtureSong(), &error))
        return nullptr;

    EditorRigConfig config;
    config.viewSize = QSize(1000, 640);
    config.sampleRate = 48000.0;
    config.show = true;
    fixture->m_rig = EditorRig::create(fixture->m_document, config, error);
    if (!fixture->m_rig)
        return nullptr;
    return fixture;
}

EventViewRigFixture::~EventViewRigFixture() = default;

SongDocument &EventViewRigFixture::document() noexcept
{
    return m_document;
}

SongView &EventViewRigFixture::view() noexcept
{
    return m_rig->view();
}

EventWidgets EventViewRigFixture::openEventList()
{
    return locateWidgets(view());
}

std::unique_ptr<EventViewTabFixture> EventViewTabFixture::create(FixtureShape shape, QString &error)
{
    error.clear();
    const std::optional<SongName> name = SongName::create(QStringLiteral("eventviews-fixture"));
    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("eventviews-fixture"), QString());
    if (!name || !identity) {
        error = QStringLiteral("could not construct the EventViews fixture identity");
        return nullptr;
    }

    auto fixture = std::unique_ptr<EventViewTabFixture>(new EventViewTabFixture);
    fixture->m_bank.voices[0].type = VOICE_DIRECTSOUND;
    fixture->m_bank.voices[1].type = VOICE_SQUARE_1;
    fixture->m_bank.voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    fixture->m_bank.voices[3].type = VOICE_NOISE;
    fixture->m_tab = std::make_unique<SongTab>(std::move(*name));
    fixture->m_tab->resize(1000, 640);
    fixture->m_tab->setSampleRate(48000.0);
    fixture->m_tab->applyMidiStage(fixtureSong(), fixtureSmf(shape),
                                   track_limits::kHardwareCapacity);
    if (!fixture->m_tab->presentationError().isEmpty()) {
        error = fixture->m_tab->presentationError();
        return nullptr;
    }
    fixture->m_tab->applyBankView(
        LoadedBankView{*identity, borrowVoicegroupLease(&fixture->m_bank), QString()});
    fixture->m_tab->applyVoicegroupBound(*identity);
    if (!fixture->m_tab->isReady()) {
        error = QStringLiteral("SongTab did not become ready");
        return nullptr;
    }
    fixture->m_tab->show();
    QCoreApplication::processEvents();
    return fixture;
}

EventViewTabFixture::~EventViewTabFixture() = default;

SongDocument &EventViewTabFixture::document() noexcept
{
    return m_tab->document();
}

SongView &EventViewTabFixture::view() noexcept
{
    return m_tab->view();
}

SongTab &EventViewTabFixture::tab() noexcept
{
    return *m_tab;
}

EventWidgets EventViewTabFixture::openEventList()
{
    return locateWidgets(view());
}
FixtureOpen<EventViewRigFixture> openRigFixture(FixtureShape shape)
{
    FixtureOpen<EventViewRigFixture> opened;
    opened.fixture = EventViewRigFixture::create(shape, opened.error);
    return opened;
}

FixtureOpen<EventViewTabFixture> openTabFixture(FixtureShape shape)
{
    FixtureOpen<EventViewTabFixture> opened;
    opened.fixture = EventViewTabFixture::create(shape, opened.error);
    return opened;
}

bool trackIsSorted(const SmfTrack &track)
{
    return std::is_sorted(
        track.events.begin(), track.events.end(),
        [](const SmfEvent &left, const SmfEvent &right) { return left.tick < right.tick; });
}

int rowForTickAndType(const eventlist::EventTableModel &model, uint64_t tick, int type)
{
    for (int row = 0; row + 1 < model.rowCount(); row++) {
        if (model.data(model.index(row, eventlist::EventTableModel::ColTick), Qt::EditRole)
                    .toULongLong() == tick &&
            model.data(model.index(row, eventlist::EventTableModel::ColType), Qt::EditRole)
                    .toInt() == type)
            return row;
    }
    return -1;
}

int chunkForTrack(const SongDocument &document, int engineTrack)
{
    return document.smfTrackFor(engineTrack);
}

bool selectChunk(QComboBox &combo, int chunk)
{
    const int index = combo.findData(chunk);
    if (index < 0)
        return false;
    combo.setCurrentIndex(index);
    return QMetaObject::invokeMethod(&combo, "activated", Qt::DirectConnection, Q_ARG(int, index));
}

} // namespace checks::eventviews
