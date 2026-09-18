#pragma once

#include "ui/songview.h"

#include <cstddef>

namespace songview {

struct EditCommandPolicy;
enum class EditDeliveryClass;

// Read-only accessors over the canonical command table in
// editcommandtable.cpp. The table itself stays anonymous in its TU — one
// row per SongView::EditCommand value, in enum order — so hosts iterate
// commands and read the columns they need through these functions.
std::size_t editCommandCount();
const char *editCommandId(SongView::EditCommand command);
bool editCommandCheckable(SongView::EditCommand command);
const char *editCommandWindowObjectName(SongView::EditCommand command);
EditDeliveryClass editCommandDelivery(SongView::EditCommand command);

// The policy row of one command, read out of the canonical table.
const EditCommandPolicy &editCommandPolicy(SongView::EditCommand command);

} // namespace songview
