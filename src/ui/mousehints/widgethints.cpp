#include "hintprofiles.h"
#include "mousehints.h"

#include <QAbstractItemView>
#include <QAbstractScrollArea>
#include <QAbstractSlider>
#include <QAbstractSpinBox>
#include <QApplication>
#include <QCursor>
#include <QEvent>
#include <QFontMetrics>
#include <QGuiApplication>
#include <QHeaderView>
#include <QLineEdit>
#include <QMetaObject>
#include <QMouseEvent>
#include <QPainter>
#include <QSizePolicy>
#include <QStatusBar>
#include <QStyle>
#include <QVariant>
#include <QWidget>
#include <QWindow>

#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

namespace ui {

namespace {

/// Dynamic-property key setWidgetProfile writes; the observer resolves it as
/// the widget family's complete replacement profile. Missing metadata means
/// infer the family; an explicit Empty is a complete blank override.
constexpr char profileProperty[] = "porydaw.mouseHintProfile";

/// The widget whose configuration selects the family profile: a scroll-area
/// viewport resolves to its owning area, everything else resolves to itself.
QWidget *profileOwner(QWidget *widget)
{
    if (auto *area = qobject_cast<QAbstractScrollArea *>(widget->parentWidget());
        area && widget == area->viewport())
        return area;
    return widget;
}

/// The style's spin-box step modifier (SH_SpinBox_StepModifier), or 0 when the
/// style defines none. Read from the widget's own style, never assumed.
int spinStepModifier(const QAbstractSpinBox &box)
{
    return box.style()->styleHint(QStyle::SH_SpinBox_StepModifier, nullptr, &box);
}

/// The spin box a widget's wheel events reach: the box itself, or the box
/// whose embedded line edit forwards wheel input to it.
QAbstractSpinBox *spinBoxFor(QWidget *widget, QWidget *owner)
{
    if (auto *spin = qobject_cast<QAbstractSpinBox *>(owner))
        return spin;
    if (auto *edit = qobject_cast<QLineEdit *>(widget))
        return qobject_cast<QAbstractSpinBox *>(edit->parentWidget());
    return nullptr;
}

/// Single-line caption for the middle status region. Paints right-elided text
/// resolved from theme roles at paint time, so theme and application-font
/// changes propagate without stored state. Noninteractive: transparent for
/// mouse events, no tooltip, no focus; the full text is the accessible
/// description.
class HintCaption final : public QWidget
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(HintCaption)

  public:
    explicit HintCaption(QWidget *parent) : QWidget(parent)
    {
        // Ignored horizontal policy plus zero minimum width: the hint can
        // never widen the bar or shift the meter.
        setSizePolicy(QSizePolicy::Ignored, QSizePolicy::Preferred);
        setMinimumWidth(0);
        setFocusPolicy(Qt::NoFocus);
        setAttribute(Qt::WA_TransparentForMouseEvents);
        setAccessibleName(tr("Mouse hint"));
    }

    void setText(const QString &text)
    {
        if (m_text == text)
            return;
        m_text = text;
        setAccessibleDescription(m_text);
        update();
    }

    QSize sizeHint() const override { return QSize(0, QFontMetrics(captionFont()).height()); }
    QSize minimumSizeHint() const override { return sizeHint(); }

  protected:
    void changeEvent(QEvent *event) override
    {
        QWidget::changeEvent(event);
        switch (event->type()) {
        case QEvent::ApplicationFontChange:
        case QEvent::FontChange:
            updateGeometry();
            break;
        case QEvent::ApplicationPaletteChange:
        case QEvent::PaletteChange:
        case QEvent::StyleChange:
        case QEvent::ThemeChange:
            update();
            break;
        default:
            break;
        }
    }

    void moveEvent(QMoveEvent *event) override
    {
        QWidget::moveEvent(event);
        update();
    }

    void paintEvent(QPaintEvent * /*event*/) override
    {
        if (m_text.isEmpty())
            return;
        QPainter painter(this);
        painter.setFont(captionFont());
        painter.setPen(themes::color(themes::Role::secondary_text));
        // The permanent slot is offset by the operational-message reservation.
        // Center on the bar, eliding symmetrically inside the available slot.
        const qreal center = parentWidget()->width() / 2.0 - x();
        const qreal halfWidth = qMax(0.0, qMin(center, width() - center));
        const QRectF textRect(center - halfWidth, 0, 2 * halfWidth, height());
        painter.drawText(
            textRect, Qt::AlignCenter,
            painter.fontMetrics().elidedText(m_text, Qt::ElideRight, int(textRect.width())));
    }

  private:
    QFont captionFont() const { return typography::regular(typography::caption(font())); }

    QString m_text;
};

} // namespace

/// The one application event filter installed by MouseHints::install. It is
/// observe-only — every path returns false — and resolves the hovered native
/// widget to one complete catalogue profile claimed through the service. It
/// also mirrors Qt's delivered WindowBlocked/WindowUnblocked bits onto each
/// QWindow and reconciles scope after native popup
/// registration/deregistration.
class WidgetHintsObserver final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(WidgetHintsObserver)

  public:
    WidgetHintsObserver(MouseHints &service, QObject *parent) : QObject(parent), m_service(&service)
    {
        // Inactive drops tracking state (the service clears and rejects);
        // reactivation re-derives the leaf under a possibly motionless cursor.
        connect(qApp, &QGuiApplication::applicationStateChanged, this,
                [this](Qt::ApplicationState state) {
                    if (state == Qt::ApplicationActive) {
                        queueScopeReconcile();
                    } else {
                        m_hover = nullptr;
                        m_pressed = nullptr;
                    }
                });
    }

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (!m_service)
            return false;
        switch (event->type()) {
        case QEvent::WindowBlocked:
        case QEvent::WindowUnblocked: {
            auto *window = qobject_cast<QWindow *>(watched);
            if (!window)
                return false;
            const bool blocked = event->type() == QEvent::WindowBlocked;
            window->setProperty(MouseHints::nativeWindowBlockedProperty, blocked);
            if (blocked)
                settleCovered();
            else
                queueScopeReconcile();
            return false;
        }
        default:
            break;
        }

        if (!watched->isWidgetType())
            return false;
        auto *widget = static_cast<QWidget *>(watched);
        switch (event->type()) {
        case QEvent::Enter:
            // A window container (embedded QQuickWindow) or QQuickWidget only
            // frames foreign input: its Enter must not claim an empty profile
            // over the embedded scene's current owner.
            if (!m_pressed && !isForeignHost(widget))
                setHover(widget);
            break;
        case QEvent::Leave:
            // A grab retains the pressed profile; membership settles on
            // release, not on a stray leave.
            if (m_pressed)
                break;
            if (m_hover == widget) {
                m_hover = nullptr;
                m_service->clear(widget);
            }
            break;
        case QEvent::MouseButtonPress:
        case QEvent::MouseButtonDblClick:
            // Propagated ancestor copies are non-spontaneous; only original
            // delivery identifies the actual pressed leaf.
            if (!event->spontaneous() || isForeignHost(widget))
                break;
            m_pressed = widget;
            m_hover = widget;
            claimHover();
            break;
        case QEvent::MouseButtonRelease:
            if (!event->spontaneous())
                break;
            // Only the final release ends the press: buttons() reports the
            // still-held remainder, so a chord partner keeps the originating
            // profile retained.
            if (m_pressed && static_cast<QMouseEvent *>(event)->buttons() == Qt::NoButton)
                settleRelease(static_cast<QMouseEvent *>(event));
            break;
        case QEvent::MouseMove:
            // During an implicit grab moves keep routing to the pressed
            // widget; its originating profile stays up unchanged.
            if (!event->spontaneous() || m_pressed || isForeignHost(widget))
                break;
            setHover(widget);
            break;
        case QEvent::Hide:
        case QEvent::HideToParent:
            onHidden(widget);
            break;
        case QEvent::Show:
            // Show precedes Qt's popup registration, so the covered-owner
            // check must run from a queued callback, not inline.
            if (isPopupScope(widget))
                queueScopeReconcile();
            break;
        case QEvent::StyleChange:
            if (widget == m_hover || widget == m_pressed)
                claimHover();
            break;
        case QEvent::DynamicPropertyChange: {
            const auto *change = static_cast<QDynamicPropertyChangeEvent *>(event);
            if (change->propertyName() == profileProperty &&
                (widget == m_hover || widget == m_pressed))
                claimHover();
            break;
        }
        default:
            break;
        }
        return false;
    }

  private:
    static bool isPopupScope(const QWidget *widget)
    {
        // QApplication::activePopupWidget tracks Qt::Popup windows only;
        // tooltips are a separate window type and never own input scope.
        return widget->isWindow() && (widget->windowType() & Qt::WindowType_Mask) == Qt::Popup;
    }

    /// Window containers and QQuickWidgets frame foreign input; the embedded
    /// scene owns its hint sources.
    static bool isForeignHost(const QWidget *widget)
    {
        return widget->inherits("QWindowContainer") || widget->inherits("QQuickWidget");
    }

    void setHover(QWidget *widget)
    {
        if (m_hover == widget)
            return;
        QWidget *old = m_hover;
        m_hover = widget;
        if (widget) {
            claimHover();
        } else if (old) {
            m_service->clear(old);
        }
    }

    void claimHover()
    {
        if (!m_hover)
            return;
        const hint_profiles::Id profile = resolveProfile(m_hover);
        switch (profile) {
        case hint_profiles::Id::NativeSpinBox:
        case hint_profiles::Id::NativeSpinEditor:
        case hint_profiles::Id::NativeFineSpinEditor:
            // The catalogue's spin profiles take the owning style's step
            // modifier, including a style's Qt::NoModifier.
            if (QAbstractSpinBox *spin = spinBoxFor(m_hover, profileOwner(m_hover)))
                m_service->claim(m_hover, profile, Qt::KeyboardModifiers(spinStepModifier(*spin)));
            else
                m_service->claim(m_hover, profile);
            break;
        default:
            m_service->claim(m_hover, profile);
            break;
        }
    }

    void settleRelease(const QMouseEvent *event)
    {
        QWidget *pressed = m_pressed;
        m_pressed = nullptr;
        const bool inside =
            pressed->rect().contains(pressed->mapFromGlobal(event->globalPosition().toPoint()));
        if (inside) {
            // Release inside keeps and refreshes the originating profile.
            m_hover = pressed;
            claimHover();
        } else {
            if (m_hover == pressed)
                m_hover = nullptr;
            m_service->clear(pressed);
            // The cursor may rest over a different leaf that never regained
            // membership during the grab; recover it discretely.
            queueScopeReconcile();
        }
    }

    void onHidden(QWidget *widget)
    {
        if (m_hover == widget) {
            m_hover = nullptr;
            m_service->clear(widget);
        }
        if (m_pressed == widget) {
            m_pressed = nullptr;
            m_service->clear(widget);
        }
        // Hide follows popup deregistration, so reconciliation can run inline
        // — but queueing keeps one coalesced path for every scope transition.
        if (isPopupScope(widget))
            queueScopeReconcile();
    }

    /// Clears tracking and ownership that a new modal block now covers.
    void settleCovered()
    {
        if (m_pressed && !m_service->allowsNativeInput(m_pressed)) {
            m_service->clear(m_pressed);
            m_pressed = nullptr;
        }
        if (m_hover && !m_service->allowsNativeInput(m_hover)) {
            m_service->clear(m_hover);
            m_hover = nullptr;
        }
        if (m_service->m_source && !m_service->allowsNativeInput(m_service->m_source))
            m_service->clearCurrentSource();
    }

    /// One coalesced queued reconciliation per scope transition burst.
    void queueScopeReconcile()
    {
        if (m_reconcileQueued)
            return;
        m_reconcileQueued = true;
        QMetaObject::invokeMethod(
            this,
            [this] {
                m_reconcileQueued = false;
                reconcileScope();
            },
            Qt::QueuedConnection);
    }

    void reconcileScope()
    {
        // A popup that just registered (or a window that just blocked) may
        // cover the pressed/hovered widget or the current owner; a recovered
        // scope may have left the cursor over a leaf that never received
        // Enter again.
        settleCovered();
        if (!m_pressed) {
            QWidget *under = QApplication::widgetAt(QCursor::pos());
            // A tooltip window never becomes the hint target; the widget
            // beneath it keeps conceptual membership. A foreign-window host
            // leaves the embedded scene's ownership untouched.
            if (under && (under->window()->windowType() == Qt::ToolTip || isForeignHost(under)))
                under = nullptr;
            QWidget *old = m_hover;
            m_hover = under;
            if (under) {
                claimHover();
            } else if (old) {
                m_service->clear(old);
            }
        }
        m_service->requestScopeRefresh();
    }

    // -- Family profile resolution ----------------------------------------

    /// One complete catalogue profile for the physical widget. Resolution
    /// runs on hover transitions only — never per pointer pixel; the
    /// catalogue owns rendered text and its cache.
    static hint_profiles::Id resolveProfile(QWidget *widget)
    {
        QWidget *owner = profileOwner(widget);
        // Custom metadata is a complete replacement profile, not a pointer
        // fragment: it already includes any inherited wheel alternatives.
        const QVariant custom = widget->property(profileProperty);
        const QVariant annotation =
            custom.isValid() || owner == widget ? custom : owner->property(profileProperty);
        if (annotation.isValid())
            return static_cast<hint_profiles::Id>(annotation.toInt());

        if (auto *view = qobject_cast<QAbstractItemView *>(owner);
            view && !qobject_cast<QHeaderView *>(view) &&
            view->window()->windowType() != Qt::Popup) {
            switch (view->selectionMode()) {
            case QAbstractItemView::SingleSelection:
                return hint_profiles::Id::NativeSingleSelection;
            case QAbstractItemView::ExtendedSelection:
                return hint_profiles::Id::NativeExtendedSelection;
            case QAbstractItemView::ContiguousSelection:
                return hint_profiles::Id::NativeContiguousSelection;
            default:
                break;
            }
        }
        if (qobject_cast<QAbstractSpinBox *>(owner))
            return hint_profiles::Id::NativeSpinBox;
        // QAbstractSliderPrivate::scrollByDelta pages on Control or Shift for
        // sliders, dials, scrollbars and scroll-area viewports that forward
        // wheel events to them; headers, popup views and no-selection views
        // have no pointer alternatives beyond that page step.
        if (qobject_cast<QAbstractItemView *>(owner) || qobject_cast<QAbstractSlider *>(owner) ||
            qobject_cast<QAbstractScrollArea *>(owner))
            return hint_profiles::Id::NativePageStep;
        if (auto *edit = qobject_cast<QLineEdit *>(widget))
            return qobject_cast<QAbstractSpinBox *>(edit->parentWidget())
                       ? hint_profiles::Id::NativeSpinEditor
                       : hint_profiles::Id::TextSelection;
        return hint_profiles::Id::Empty;
    }

    QPointer<MouseHints> m_service;
    QPointer<QWidget> m_hover;
    /// Actual pressed native source; QWidget::mouseGrabber() alone does not
    /// report implicit button-down routing.
    QPointer<QWidget> m_pressed;
    bool m_reconcileQueued = false;
};

void MouseHints::install(QStatusBar &bar)
{
    if (!m_nativeAdapter) {
        m_nativeAdapter = new WidgetHintsObserver(*this, qApp);
        qApp->installEventFilter(m_nativeAdapter);
    }
    // Per-bar idempotent: a second install on the same bar reuses the region.
    if (bar.findChild<HintCaption *>(QString(), Qt::FindDirectChildrenOnly))
        return;
    // The bar's own font paints the left operational text; sizing it to the
    // caption keeps both status texts at one size. typography::caption pins
    // the captured base pixel size, so HintCaption resolves the same size.
    bar.setFont(typography::regular(typography::caption(bar.font())));

    // Proven layout: an empty normal reservation (stretch 1, retained while
    // hidden) left of the permanent region, then the permanent hint caption
    // (stretch 2) before the existing zero-stretch permanent meter.
    auto *reservation = new QWidget(&bar);
    QSizePolicy policy(QSizePolicy::Expanding, QSizePolicy::Preferred);
    policy.setRetainSizeWhenHidden(true);
    reservation->setSizePolicy(policy);
    reservation->hide();
    bar.addWidget(reservation, 1);

    auto *caption = new HintCaption(&bar);
    bar.addPermanentWidget(caption, 2);
    connect(this, &MouseHints::hintChanged, caption,
            [caption](const QString &text) { caption->setText(text); });
}

void MouseHints::setWidgetProfile(QWidget &widget, ui::hint_profiles::Id profile)
{
    widget.setProperty(profileProperty, QVariant::fromValue(profile));
}

} // namespace ui

#include "widgethints.moc"
