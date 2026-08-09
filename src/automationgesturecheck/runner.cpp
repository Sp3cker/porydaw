#include "domains.h"

#include <algorithm>
#include <array>
#include <cstdio>

#include "rig.h"

namespace {

using AutomationGestureDomain = void (*)(AutomationGestureCheckRig &,
                                         const AutomationGestureCheck &);

struct Domain {
    const char *name;
    AutomationGestureDomain check;
};

constexpr std::array kDomains{
    Domain{"action", checkAutomationPencilAction},
    Domain{"mapping", checkAutomationPencilMapping},
    Domain{"stroke", checkAutomationPencilStroke},
    Domain{"ownership", checkAutomationPencilOwnership},
    Domain{"transactions", checkAutomationPencilTransactions},
};

} // namespace

int runAutomationGestureCheck(const QString &project, const QString &song, const QString &domain)
{
    const auto matchingDomain =
        std::find_if(kDomains.cbegin(), kDomains.cend(), [&domain](const Domain &candidate) {
            return domain == QLatin1String(candidate.name);
        });
    if (!domain.isEmpty() && matchingDomain == kDomains.cend()) {
        std::fprintf(stderr, "porydaw: unknown automation gesture check domain: %s\n",
                     qUtf8Printable(domain));
        return 2;
    }

    auto failures = 0;
    const auto runDomain = [&project, &song, &failures](const Domain &candidate) {
        QString error;
        auto rig = AutomationGestureCheckRig::create(project, song, error);
        if (!rig) {
            std::fprintf(stderr, "automation-gesture-check[%s]: %s\n", candidate.name,
                         qUtf8Printable(error));
            ++failures;
            return;
        }
        const auto check = [&failures, name = candidate.name](bool condition,
                                                              const QString &message) {
            if (condition)
                return;
            std::fprintf(stderr, "automation-gesture-check[%s]: %s\n", name,
                         qUtf8Printable(message));
            ++failures;
        };
        candidate.check(*rig, check);
    };

    if (domain.isEmpty()) {
        for (const auto &candidate : kDomains)
            runDomain(candidate);
    } else {
        runDomain(*matchingDomain);
    }
    return failures == 0 ? 0 : 1;
}
