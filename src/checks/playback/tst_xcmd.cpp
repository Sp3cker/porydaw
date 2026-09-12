#include "checks/playback/tst_xcmd.h"

#include <span>

#include <QTest>

namespace checks {

xcmd::Event ev(uint64_t index, Tick tick, uint8_t stream, uint8_t controller, uint8_t value,
               uint8_t channel)
{
    xcmd::Event event;
    event.index = index;
    event.tick = tick;
    event.stream = stream;
    event.controller = controller;
    event.value = value;
    event.channel = channel;
    return event;
}

xcmd::Projection project(const std::vector<xcmd::Event> &events)
{
    return xcmd::projectEvents(std::span<const xcmd::Event>(events));
}

} // namespace checks

int runXcmdCheck(const QStringList &qtArguments)
{
    checks::XcmdTest test;
    QStringList arguments{QStringLiteral("xcmdcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
