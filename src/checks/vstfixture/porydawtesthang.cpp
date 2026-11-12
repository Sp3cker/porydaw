#include "pluginterfaces/base/ipluginbase.h"
#include <chrono>
#include <thread>
extern "C" SMTG_EXPORT_SYMBOL Steinberg::IPluginFactory* PLUGIN_API GetPluginFactory() {
    for (;;) std::this_thread::sleep_for(std::chrono::hours(24));
}
