#include "hintprofiles.h"

#include <QCoreApplication>
#include <QKeyCombination>
#include <QKeySequence>
#include <QStringList>

#include "ui/keymap.h"

namespace ui::hint_profiles {
namespace {

// QKeySequence renders the platform's native modifier labels and order
// (⌃⌥⇧⌘ on macOS, translated "Ctrl+Alt+…" elsewhere). A modifier-only
// combination carries no key, so non-Apple formats append their separator
// after the last label; drop it, then re-join with the operation so the
// fragment reads like the platform's own shortcut text.
QString fragment(Qt::KeyboardModifiers modifiers, const QString &operation)
{
    QString label = QKeySequence(QKeyCombination::fromCombined(modifiers.toInt()))
                        .toString(QKeySequence::NativeText);
    QString separator;
    if (label.endsWith(u'+')) {
        separator = QStringLiteral("+");
        label.chop(1);
    }
    if (label.isEmpty())
        return operation;
    return label + separator + u' ' + operation;
}

// Native modifier label without an operation, e.g. "⌃" or "Ctrl". Mirrors
// fragment's modifier-only rendering so "Shift or Alt" reads as two
// equivalent chords rather than a combined Shift+Alt.
QString modifierLabel(Qt::KeyboardModifiers modifiers)
{
    QString label = QKeySequence(QKeyCombination::fromCombined(modifiers.toInt()))
                        .toString(QKeySequence::NativeText);
    if (label.endsWith(u'+'))
        label.chop(1);
    return label;
}

// The style's spin-box step modifier applies only to the three native spin
// profiles; every other profile's cache key and rendering ignore it.
bool usesStepModifier(Id profile)
{
    return profile == Id::NativeSpinBox || profile == Id::NativeSpinEditor ||
           profile == Id::NativeFineSpinEditor;
}

// Control or Shift wheel page step, shared by item views, headers, popup
// views and generic scroll areas/sliders.
QString pageStep()
{
    return QCoreApplication::translate("MouseHints", "%1 or %2 wheel: page step")
        .arg(modifierLabel(Qt::ControlModifier), modifierLabel(Qt::ShiftModifier));
}

QString render(Id profile, Qt::KeyboardModifiers stepModifier)
{
    const QString separator = QStringLiteral(" · ");
    switch (profile) {
    case Id::Empty:
        return {};
    case Id::TextSelection:
        return fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "click: extend selection"));
    case Id::NativePageStep:
        return pageStep();
    case Id::NativeSingleSelection:
        return fragment(Qt::ControlModifier,
                        QCoreApplication::translate("MouseHints", "click: deselect item")) +
               separator + pageStep();
    case Id::NativeExtendedSelection:
        return fragment(Qt::ControlModifier,
                        QCoreApplication::translate("MouseHints", "click: toggle item")) +
               separator +
               fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "click: select range")) +
               separator + pageStep();
    case Id::NativeContiguousSelection:
        return fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "click: select range")) +
               separator + pageStep();
    case Id::NativeSpinBox:
        // A zero style modifier removes the accelerated-step alternative,
        // leaving the spin body blank.
        if (stepModifier == Qt::NoModifier)
            return {};
        return fragment(stepModifier, QCoreApplication::translate(
                                          "MouseHints", "wheel or arrow click: step by ten"));
    case Id::NativeSpinEditor: {
        // The ordinary embedded editor keeps its text-selection description;
        // the style modifier adds the wheel step-by-ten alternative.
        QString text =
            fragment(Qt::ShiftModifier,
                     QCoreApplication::translate("MouseHints", "click: extend selection"));
        if (stepModifier != Qt::NoModifier)
            text += separator + fragment(stepModifier, QCoreApplication::translate(
                                                           "MouseHints", "wheel: step by ten"));
        return text;
    }
    case Id::NativeFineSpinEditor: {
        // The overridden editor's fine drag replaces the generic
        // text-selection profile; the style modifier still adds the wheel
        // step-by-ten alternative.
        QString text = fragment(Qt::ShiftModifier,
                                QCoreApplication::translate("MouseHints", "drag: adjust finely"));
        if (stepModifier != Qt::NoModifier)
            text += separator + fragment(stepModifier, QCoreApplication::translate(
                                                           "MouseHints", "wheel: step by ten"));
        return text;
    }
    case Id::NativeFinePageStep:
        return fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "drag: adjust finely")) +
               separator + pageStep();
    case Id::RollNoteBody:
    case Id::RollNoteEdge:
    case Id::RollPlot:
    case Id::RollGutter: {
        const Qt::KeyboardModifiers velocityChord =
            keymap::Registry::instance().modifierBinding(QStringLiteral("roll.velocity_drag"));
        // Right-button alternatives apply over notes and background alike;
        // the marquee decision reads Control at release, not at press.
        const QString plotAlternatives =
            fragment(Qt::ShiftModifier,
                     QCoreApplication::translate("MouseHints", "right-drag: select time")) +
            separator +
            fragment(Qt::ControlModifier,
                     QCoreApplication::translate("MouseHints",
                                                 "right-drag release: add marquee notes")) +
            separator +
            fragment(Qt::ControlModifier,
                     QCoreApplication::translate("MouseHints", "wheel: zoom key height")) +
            separator +
            fragment(Qt::ShiftModifier,
                     QCoreApplication::translate("MouseHints", "wheel: scroll horizontally"));
        if (profile == Id::RollPlot)
            return plotAlternatives;
        if (profile == Id::RollGutter)
            return fragment(Qt::ControlModifier,
                            QCoreApplication::translate("MouseHints", "wheel: zoom key height")) +
                   separator +
                   fragment(Qt::ShiftModifier, QCoreApplication::translate(
                                                   "MouseHints", "wheel: scroll horizontally"));
        if (profile == Id::RollNoteEdge)
            return fragment(Qt::ControlModifier,
                            QCoreApplication::translate("MouseHints",
                                                        "drag: add to selection and resize")) +
                   separator + plotAlternatives;
        return fragment(velocityChord,
                        QCoreApplication::translate("MouseHints", "drag: adjust velocity")) +
               separator +
               fragment(Qt::ControlModifier,
                        QCoreApplication::translate("MouseHints", "click: toggle selection")) +
               separator + plotAlternatives;
    }
    case Id::HorizontalScroll:
        return fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "wheel: scroll horizontally"));
    case Id::RulerSweep:
        // The sweep's track scope is the primary track plus every track
        // whose notes intersect the swept time — described unconditionally,
        // never gated on what the sweep would currently select.
        return fragment(Qt::ControlModifier,
                        QCoreApplication::translate("MouseHints",
                                                    "drag: select time across tracks with notes")) +
               separator +
               fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "wheel: scroll horizontally"));
    case Id::TrackScope:
        // Control toggles the track's scope membership, Shift extends a
        // range, and Control+Shift is not an additive-range chord.
        return fragment(Qt::ControlModifier,
                        QCoreApplication::translate("MouseHints", "click: toggle track scope")) +
               separator +
               fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "click: select track range"));
    case Id::AutomationNode:
        // Shift constrains to an axis, Alt drags on the fine time grid,
        // Control snaps the value toward the lane's neutral value.
        return fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "drag: constrain to axis")) +
               separator +
               fragment(Qt::AltModifier,
                        QCoreApplication::translate("MouseHints", "drag: fine time grid")) +
               separator +
               fragment(Qt::ControlModifier,
                        QCoreApplication::translate("MouseHints", "drag: snap to neutral value")) +
               separator +
               fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "wheel: scroll horizontally"));
    case Id::AutomationOriginPhantom:
        // The drag edits only the source event's value — no time move, so
        // Alt's fine time grid is not claimed.
        return fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "drag: constrain to value")) +
               separator +
               fragment(Qt::ControlModifier,
                        QCoreApplication::translate("MouseHints", "drag: snap to neutral value")) +
               separator +
               fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "wheel: scroll horizontally"));
    case Id::AutomationSweep:
        // The Shift ramp mode is captured at press while Alt/Control stay
        // live; Alt's fine placement covers the actual right-band and
        // insertion double-click paths, not a plain click.
        return fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "drag: draw ramp")) +
               separator +
               fragment(Qt::AltModifier,
                        QCoreApplication::translate("MouseHints",
                                                    "drag or double-click: fine time grid")) +
               separator +
               fragment(Qt::ControlModifier,
                        QCoreApplication::translate("MouseHints", "drag: snap to neutral value")) +
               separator +
               fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "wheel: scroll horizontally"));
    case Id::AutomationPencil:
        // Control draws freehand and Shift holds the value constant. Alt
        // claims only the right-band's fine placement — it never changes
        // pencil stroke sampling.
        return fragment(Qt::ControlModifier,
                        QCoreApplication::translate("MouseHints", "drag: draw freehand")) +
               separator +
               fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "drag: hold value")) +
               separator +
               fragment(Qt::AltModifier,
                        QCoreApplication::translate("MouseHints", "right-drag: fine time grid")) +
               separator +
               fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "wheel: scroll horizontally"));
    case Id::VelocityNote: {
        const Qt::KeyboardModifiers detentChord =
            keymap::Registry::instance().modifierBinding(QStringLiteral("velocity.detent_unlock"));
        QStringList noteParts = {
            fragment(detentChord,
                     QCoreApplication::translate("MouseHints", "click: toggle selection")),
            fragment(Qt::ShiftModifier,
                     QCoreApplication::translate("MouseHints", "drag: draw ramp")),
            fragment(Qt::ControlModifier,
                     QCoreApplication::translate("MouseHints", "right-click: toggle selection")),
            fragment(Qt::ControlModifier,
                     QCoreApplication::translate("MouseHints", "right-drag: marquee adds notes")),
            fragment(Qt::ShiftModifier,
                     QCoreApplication::translate("MouseHints", "wheel: scroll horizontally")),
        };
        // The shipped detent-unlock chord is also the additive-selection
        // modifier, so one fragment describes the drag's combined result; a
        // distinct chord would get its own plain drag entry instead.
        if (detentChord == Qt::ControlModifier) {
            noteParts.prepend(fragment(
                detentChord, QCoreApplication::translate(
                                 "MouseHints", "drag: adjust velocity without detents, preserving "
                                               "selection")));
        } else {
            noteParts.prepend(
                fragment(Qt::ControlModifier,
                         QCoreApplication::translate(
                             "MouseHints", "drag: adjust velocity preserving selection")));
            noteParts.prepend(
                fragment(detentChord, QCoreApplication::translate(
                                          "MouseHints", "drag: adjust velocity without detents")));
        }
        return noteParts.join(separator);
    }
    case Id::VelocityBackground: {
        const Qt::KeyboardModifiers detentChord =
            keymap::Registry::instance().modifierBinding(QStringLiteral("velocity.detent_unlock"));
        return fragment(detentChord, QCoreApplication::translate(
                                         "MouseHints", "drag: paint velocities without detents")) +
               separator +
               fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "drag: draw ramp")) +
               separator +
               fragment(Qt::ControlModifier, QCoreApplication::translate(
                                                 "MouseHints", "right-drag: marquee adds notes")) +
               separator +
               fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "wheel: scroll horizontally"));
    }
    case Id::VelocityGutter: {
        // The gutter ruler's exact-chord click sets an exact velocity; it
        // has no Shift carve-out and no wheel alternative.
        const Qt::KeyboardModifiers detentChord =
            keymap::Registry::instance().modifierBinding(QStringLiteral("velocity.detent_unlock"));
        return fragment(detentChord,
                        QCoreApplication::translate("MouseHints", "click: set exact velocity"));
    }
    case Id::VoiceMarker:
        return fragment(Qt::AltModifier,
                        QCoreApplication::translate("MouseHints", "drag: move with fine time")) +
               separator +
               fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "wheel: scroll horizontally"));
    case Id::PitchBendVertex:
        return fragment(Qt::AltModifier,
                        QCoreApplication::translate("MouseHints", "drag: move in time finely"));
    case Id::PitchBendBackground:
        // Shift and Alt are two equivalent chords for the same line-drawing
        // alternative, never a combined Shift+Alt.
        return QCoreApplication::translate("MouseHints", "%1 or %2 drag: draw line")
            .arg(modifierLabel(Qt::ShiftModifier), modifierLabel(Qt::AltModifier));
    case Id::EventRows:
        // The combined chord is an additive range, unlike the track
        // header's Control precedence.
        return fragment(Qt::ControlModifier,
                        QCoreApplication::translate("MouseHints", "click: toggle row")) +
               separator +
               fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "click: select range")) +
               separator +
               fragment(Qt::ControlModifier | Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "click: add range"));
    case Id::GhostParameter:
        return fragment(Qt::ControlModifier,
                        QCoreApplication::translate("MouseHints", "click: toggle ghost parameter"));
    case Id::DragScrub:
        return fragment(Qt::ShiftModifier,
                        QCoreApplication::translate("MouseHints", "drag: adjust finely")) +
               separator +
               fragment(Qt::ControlModifier,
                        QCoreApplication::translate("MouseHints", "wheel: step by ten"));
    }
    Q_UNREACHABLE();
}

} // namespace

QString Catalog::text(Id profile, Qt::KeyboardModifiers stepModifier)
{
    if (!usesStepModifier(profile))
        stepModifier = Qt::NoModifier;
    const quint64 key = quint64(profile) << 32 | quint64(quint32(stepModifier.toInt()));
    const auto it = m_cache.constFind(key);
    if (it != m_cache.constEnd())
        return *it;
    // Empty rendered text is a valid cached result, so entry presence — not
    // null/empty content — marks a hit.
    return m_cache.insert(key, render(profile, stepModifier)).value();
}

} // namespace ui::hint_profiles
