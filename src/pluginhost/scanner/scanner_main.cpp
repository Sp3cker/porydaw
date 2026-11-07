#include "pluginhost.h"
#include <cstdio>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#ifdef _WIN32
#include <vector>
#include <windows.h>
#include <shellapi.h>
#endif
namespace {
std::string quoted(const char* value) {
    std::ostringstream out;
    out << '"';
    for (const unsigned char* p = reinterpret_cast<const unsigned char*>(value); *p; ++p) {
        if (*p == '"' || *p == '\\') out << '\\' << *p;
        else if (*p < 0x20) out << "\\u" << std::hex << std::setfill('0') << std::setw(4) << unsigned(*p);
        else out << *p;
    }
    out << '"';
    return out.str();
}
int failure(const char* reason) {
    std::string line = reason;
    for (auto& character : line) if (character == '\n' || character == '\r') character = ' ';
    std::fprintf(stderr, "%s\n", line.c_str());
    return 1;
}
int scan(int argc, char** argv) {
    if (argc != 3 || std::string(argv[1]) != "scan") return failure("Usage: porydaw-vst3-host scan <modulePath>");
    pdph_module raw = nullptr;
    pdph_error error{};
    if (pdph_module_open(argv[2], &raw, &error) != PDPH_OK) return failure(error.message);
    std::unique_ptr<pdph_module_impl, decltype(&pdph_module_close)> module(raw, pdph_module_close);
    std::ostringstream json;
    json << "{\"version\":1,\"modulePath\":" << quoted(argv[2]) << ",\"classes\":[";
    const auto count = pdph_module_class_count(raw);
    for (int32_t index = 0; index < count; ++index) {
        pdph_class_info info{};
        if (pdph_module_class_info(raw, index, &info) != PDPH_OK) return failure("Could not read module class");
        pdph_plugin instance = nullptr;
        if (pdph_plugin_create(raw, info.uid, {}, &instance, &error) != PDPH_OK) return failure(error.message);
        std::unique_ptr<pdph_plugin_impl, decltype(&pdph_plugin_destroy)> plugin(instance, pdph_plugin_destroy);
        pdph_bus_counts buses{};
        if (pdph_plugin_buses(instance, &buses) != PDPH_OK) return failure("Could not read plugin buses");
        if (index) json << ',';
        json << "{\"uid\":\"";
        for (auto byte : info.uid) json << std::hex << std::setw(2) << std::setfill('0') << unsigned(byte);
        json << std::dec << "\",\"name\":" << quoted(info.name) << ",\"vendor\":" << quoted(info.vendor)
             << ",\"version\":" << quoted(info.version) << ",\"sdkVersion\":" << quoted(info.sdk_version)
             << ",\"category\":" << quoted(info.category) << ",\"subCategories\":" << quoted(info.sub_categories)
             << ",\"eventIn\":" << buses.event_in << ",\"eventOut\":" << buses.event_out
             << ",\"audioIn\":" << buses.audio_in << ",\"audioOut\":" << buses.audio_out << '}';
    }
    json << "]}";
    std::cout << json.str() << '\n';
    return 0;
}
}
int main(int argc, char** argv) {
    try { return scan(argc, argv); }
    catch (const std::exception& error) { return failure(error.what()); }
    catch (...) { return failure("Unexpected scanner exception"); }
}
#ifdef _WIN32
int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int) {
    int count = 0;
    auto wide = CommandLineToArgvW(GetCommandLineW(), &count);
    if (!wide) return failure("Could not read scanner arguments");
    std::vector<std::string> strings;
    for (int index = 0; index < count; ++index) {
        auto size = WideCharToMultiByte(CP_UTF8, 0, wide[index], -1, nullptr, 0, nullptr, nullptr);
        std::string value(size, '\0');
        WideCharToMultiByte(CP_UTF8, 0, wide[index], -1, value.data(), size, nullptr, nullptr);
        strings.push_back(std::move(value));
    }
    LocalFree(wide);
    std::vector<char*> arguments;
    for (auto& value : strings) arguments.push_back(value.data());
    return main(count, arguments.data());
}
#endif
