#pragma once

#include <QString>

#include "ui/editorviewstate.h"
#include "ui/songview.h"

// Per-song camera, grid, and automation-lane state (SPEC §4.4), stored as
// JSON in <projectroot>/.porydaw/<song>.json. Drawer chrome is app-global and
// does not belong in this codec. Sidecars are cosmetic only: a missing or
// unreadable file just means default view state, and a failed save is silent —
// never worth interrupting the user over. Creating `.porydaw/` also adds it to
// the project's .gitignore (project/sidecar.h).
namespace ViewSidecar {

// A detached capture. The codec never captures from or applies to a live
// SongView; within EditorViewState it persists only automation-lane fields.
struct Snapshot {
    SongView::ViewState view;
    EditorViewState editor;
};

QString pathFor(const QString &projectRoot, const QString &songLabel);

// False (snapshot untouched) when the sidecar is missing or malformed.
bool load(const QString &projectRoot, const QString &songLabel, Snapshot *snapshot);

// Creates <projectroot>/.porydaw/ on demand; no-op for an invalid view state
// (no song loaded).
bool save(const QString &projectRoot, const QString &songLabel, const Snapshot &snapshot);

} // namespace ViewSidecar
