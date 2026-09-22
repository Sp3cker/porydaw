#include "ui/editordrawer/tempolane.h"

#include <algorithm>

#include <QCoreApplication>

#include "core/timedefaults.h"

namespace {

QString translated(const char *text)
{
    return QCoreApplication::translate("TempoLane", text);
}

} // namespace

TempoLane::TempoLane(SongDocument &document) noexcept : m_document(document) {}

NodeValuePrompt TempoLane::valuePrompt(int storedValue) const
{
    return {translated("Set tempo"),
            translated("BPM:"),
            std::clamp(storedValue, CoreTimeDefaults::kMinTempoBpm, CoreTimeDefaults::kMaxTempoBpm),
            CoreTimeDefaults::kMinTempoBpm,
            CoreTimeDefaults::kMaxTempoBpm,
            0};
}
