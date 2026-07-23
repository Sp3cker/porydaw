#include <QElapsedTimer>
#include <QString>

#include <cstdio>

#include "rollcheckfixture.hpp"

// --rollcheck <projectRoot> <song> [shot.png]: piano-roll gesture check.
// Each scenario opens an independent baseline fixture and undoes only its own
// commands. The drawn-notes fixture supplies the optional pre-undo screenshot.
int runRollCheck(const QString &projectRoot, const QString &songLabel,
                 const QString &screenshotPath)
{
    QElapsedTimer timer;
    timer.start();
    const auto runScenario = [&projectRoot, &songLabel](auto scenario)
    {
        RollCheckFixture fixture(songLabel);
        QString error;
        if (!fixture.open(projectRoot, &error))
        {
            if (!error.isEmpty())
                std::fprintf(stderr, "rollcheck: %s\n", qUtf8Printable(error));
            return fixture.failures() == 0 ? 1 : fixture.failures();
        }
        scenario(fixture);
        return fixture.failures();
    };

    auto failures = 0;
    failures += runScenario([](RollCheckFixture &fixture)
                            { runRollStaticViewScenario(fixture); });
    failures += runScenario([&screenshotPath](RollCheckFixture &fixture)
                            {
                                runRollDrawnNotesScenario(fixture,
                                                          screenshotPath);
                            });
    failures += runScenario([](RollCheckFixture &fixture)
                            { runRollEditingScenario(fixture); });
    failures += runScenario([](RollCheckFixture &fixture)
                            { runRollNavigationScenario(fixture); });
    failures += runScenario([](RollCheckFixture &fixture)
                            { runRollTimeRangeScenario(fixture); });
    failures += runScenario([](RollCheckFixture &fixture)
                            { runRollTrackHeaderScenario(fixture); });

    if (failures == 0)
    {
        std::printf("rollcheck: OK %s (%lld ms)\n", qUtf8Printable(songLabel),
                    static_cast<long long>(timer.elapsed()));
    }
    return failures == 0 ? 0 : 1;
}
