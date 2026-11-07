#include "pluginterfaces/base/ipluginbase.h"
#include <cstdlib>
extern "C" SMTG_EXPORT_SYMBOL Steinberg::IPluginFactory* PLUGIN_API GetPluginFactory() {
    std::abort();
}
