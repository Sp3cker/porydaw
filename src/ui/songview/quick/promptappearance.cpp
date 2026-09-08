// One builder for the QVariantMap chrome keys every canvas prompt bridge
// publishes; consolidated from five identical per-feature copies.
#include "ui/songview/quick/promptappearance.h"

#include "ui/layout.h"
#include "ui/theme/themeruntime.h"

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {

QVariantMap promptDialogAppearance(const QFont &font)
{
    QVariantMap appearance;
    appearance.insert(QStringLiteral("font"), font);
    appearance.insert(QStringLiteral("background"), themes::color(themes::Role::window_background));
    appearance.insert(QStringLiteral("outline"), themes::color(themes::Role::palette_outline));
    appearance.insert(QStringLiteral("text"), themes::color(themes::Role::window_text));
    appearance.insert(QStringLiteral("focus"), themes::color(themes::Role::focus_outline));
    appearance.insert(QStringLiteral("buttonBackground"),
                      themes::color(themes::Role::button_background));
    appearance.insert(QStringLiteral("buttonText"), themes::color(themes::Role::button_text));
    appearance.insert(QStringLiteral("pressedBackground"),
                      themes::color(themes::Role::button_pressed_background));
    appearance.insert(QStringLiteral("pressedText"),
                      themes::color(themes::Role::button_pressed_text));
    appearance.insert(QStringLiteral("borderWidth"), lyt::singlePixel());
    appearance.insert(QStringLiteral("radius"), lyt::space(Space::Half));
    appearance.insert(QStringLiteral("dialogPadding"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("horizontalPadding"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("verticalPadding"), lyt::space(Space::Half));
    appearance.insert(QStringLiteral("buttonPadding"), lyt::space(Space::One));
    appearance.insert(QStringLiteral("spacing"), lyt::space(Space::One));
    // DragInput scrub threshold; prompts without a DragInput never read it.
    appearance.insert(QStringLiteral("dragThreshold"), lyt::fontPxF(1.0));
    return appearance;
}

} // namespace songview
