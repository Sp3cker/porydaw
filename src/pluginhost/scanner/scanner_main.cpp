#include "pluginhost.h"
#include "helper/host.h"
#include <QVarLengthArray>
#include <charconv>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <memory>
#include <string>
#ifdef _WIN32
#include <vector>
#include <windows.h>
#include <shellapi.h>
#endif
namespace {
constexpr char hexDigits[] = "0123456789abcdef";
void appendQuoted(std::string& out, const char* value) {
    out += '"';
    for (const unsigned char* p = reinterpret_cast<const unsigned char*>(value); *p; ++p) {
        if (*p == '"' || *p == '\\') { out += '\\'; out += static_cast<char>(*p); }
        else if (*p < 0x20) { out += "\\u00"; out += hexDigits[*p >> 4]; out += hexDigits[*p & 15]; }
        else out += static_cast<char>(*p);
    }
    out += '"';
}
void appendNumber(std::string& out, int32_t value) {
    char bytes[12];
    const auto result = std::to_chars(bytes, bytes + sizeof(bytes), value);
    out.append(bytes, result.ptr);
}
int failure(const char* reason) {
    QVarLengthArray<char, sizeof(pdph_error::message)> line;
    line.reserve(static_cast<qsizetype>(std::strlen(reason)) + 1);
    for (const char* character = reason; *character; ++character)
        line.append(*character == '\n' || *character == '\r' ? ' ' : *character);
    line.append('\0');
    std::fprintf(stderr, "%s\n", line.constData());
    return 1;
}
int scan(int argc, char** argv) {
    if (argc != 3 || std::strcmp(argv[1], "scan") != 0) return failure("Usage: porydaw-vst3-host scan <modulePath>");
    pdph_module raw = nullptr;
    pdph_error error{};
    if (pdph_module_open(argv[2], &raw, &error) != PDPH_OK) return failure(error.message);
    std::unique_ptr<pdph_module_impl, decltype(&pdph_module_close)> module(raw, pdph_module_close);
    std::string json = "{\"version\":1,\"modulePath\":";
    appendQuoted(json, argv[2]); json += ",\"classes\":[";
    const auto count = pdph_module_class_count(raw);
    for (int32_t index = 0; index < count; ++index) {
        pdph_class_info info{};
        if (pdph_module_class_info(raw, index, &info) != PDPH_OK) return failure("Could not read module class");
        pdph_bus_counts buses{};
        if (pdph_module_class_buses(raw, index, &buses, &error) != PDPH_OK) return failure(error.message);
        if (index) json += ',';
        json += "{\"uid\":\"";
        for (auto byte : info.uid) { json += hexDigits[byte >> 4]; json += hexDigits[byte & 15]; }
        json += "\",\"name\":"; appendQuoted(json, info.name);
        json += ",\"vendor\":"; appendQuoted(json, info.vendor);
        json += ",\"version\":"; appendQuoted(json, info.version);
        json += ",\"sdkVersion\":"; appendQuoted(json, info.sdk_version);
        json += ",\"category\":"; appendQuoted(json, info.category);
        json += ",\"subCategories\":"; appendQuoted(json, info.sub_categories);
        json += ",\"eventIn\":"; appendNumber(json, buses.event_in);
        json += ",\"eventOut\":"; appendNumber(json, buses.event_out);
        json += ",\"audioIn\":"; appendNumber(json, buses.audio_in);
        json += ",\"audioOut\":"; appendNumber(json, buses.audio_out);
        json += '}';
    }
    json += "]}";
    std::cout << json << '\n';
    return 0;
}
}
int main(int argc, char** argv) {
    try {
        if (argc > 1 && std::strcmp(argv[1], "host") == 0) return pdph::helper::run(argc, argv);
        return scan(argc, argv);
    }
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
