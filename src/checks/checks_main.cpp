#include <cstdio>

#include <QApplication>

#include "checkregistry.hpp"

int main(int argc, char *argv[])
{
    auto application = QApplication{argc, argv};
    const auto arguments = application.arguments();
    if (checks::writeManifest(arguments))
        return 0;
    const auto result = checks::runRequested(application, arguments);
    if (result)
        return *result;
    std::fprintf(stderr, "porydaw_checks: no check command supplied\n");
    return 2;
}
