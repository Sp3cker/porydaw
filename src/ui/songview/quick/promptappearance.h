// --------------------------------------------------------- Prompt appearance

#pragma once

#include <QFont>
#include <QVariantMap>

namespace songview {

/// Shared appearance for the canvas prompt family (VelocityPrompt,
/// TimeSignaturePrompt, InsertTimePrompt, CcDeleteConfirm, VoicePickerPrompt):
/// theme colors and layout geometry under the keys their QML chrome and
/// DragInput fields read. Owners pass the resolving font — the application
/// font or the input host's — and may add feature-local sizing keys on top.
QVariantMap promptDialogAppearance(const QFont &font);

} // namespace songview
