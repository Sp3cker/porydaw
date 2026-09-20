#include "checks/visual/visualfixture.h"

#include <QAbstractItemView>
#include <QApplication>
#include <QCheckBox>
#include <QDialogButtonBox>
#include <QFormLayout>
#include <QLabel>
#include <QPushButton>
#include <QScrollBar>
#include <QSet>
#include <QTabBar>
#include <QtTest>

namespace checks::visual {

Region childRegion(const QString &name, QWidget &root, const QWidget &child)
{
    const QPoint offset = child.mapTo(&root, QPoint(0, 0));
    const QRect bounds = child.visibleRegion().boundingRect().translated(offset);
    return {name, bounds.intersected(root.rect())};
}

bool appendNamedRegion(QList<Region> &regions, const QString &name, QWidget &root,
                       const QString &objectName)
{
    const QWidget *child = root.findChild<QWidget *>(objectName);
    if (!child)
        return false;
    const Region region = childRegion(name, root, *child);
    if (!region.bounds.isEmpty())
        regions.append(region);
    return true;
}

bool appendRequiredRegion(QList<Region> &regions, const QString &name, QWidget &root,
                          const QWidget *child)
{
    if (!child)
        return false;
    const Region region = childRegion(name, root, *child);
    if (region.bounds.isEmpty())
        return false;
    regions.append(region);
    return true;
}

void parkFocus(QWidget &widget)
{
    QWidget *anchor = widget.findChild<QTabBar *>();
    if (!anchor)
        if (auto *buttons = widget.findChild<QDialogButtonBox *>())
            anchor = buttons->button(QDialogButtonBox::Cancel);
    if (!anchor)
        anchor = widget.findChild<QPushButton *>();
    if (anchor && anchor->isVisible() && anchor->focusPolicy() != Qt::NoFocus)
        anchor->setFocus(Qt::OtherFocusReason);
    else if (QWidget *focused = QApplication::focusWidget())
        if (focused == &widget || widget.isAncestorOf(focused))
            focused->clearFocus();
    QApplication::processEvents();
}

void showSettled(QWidget &widget)
{
    const QSize requested = widget.size();
    widget.show();
    QApplication::processEvents();
    widget.resize(requested);
    QApplication::processEvents();
    parkFocus(widget);
}

QList<Region> mergeRegions(const QList<Region> &base, const QList<Region> &overrides)
{
    QSet<QString> overrideNames;
    for (const Region &region : overrides)
        overrideNames.insert(region.name);
    QList<Region> merged;
    for (const Region &region : base)
        if (!overrideNames.contains(region.name))
            merged.append(region);
    merged.append(overrides);
    return merged;
}

QWidget *formField(QWidget &container, const QString &labelText)
{
    const QString wanted = QString(labelText).remove(QLatin1Char('&'));
    for (QFormLayout *form : container.findChildren<QFormLayout *>()) {
        for (int row = 0; row < form->rowCount(); ++row) {
            QLayoutItem *labelItem = form->itemAt(row, QFormLayout::LabelRole);
            auto *label = labelItem ? qobject_cast<QLabel *>(labelItem->widget()) : nullptr;
            if (!label || label->text().remove(QLatin1Char('&')) != wanted)
                continue;
            QLayoutItem *fieldItem = form->itemAt(row, QFormLayout::FieldRole);
            return fieldItem ? fieldItem->widget() : nullptr;
        }
    }
    return nullptr;
}

bool appendFieldRegion(QList<Region> &regions, const QString &name, QWidget &root,
                       QWidget &container, const QString &labelText)
{
    // False only when the row or its field is absent; a field scrolled out of
    // the viewport contributes no region (it renders no pixels in the grab).
    QWidget *field = formField(container, labelText);
    if (!field)
        return false;
    const Region region = childRegion(name, root, *field);
    if (!region.bounds.isEmpty())
        regions.append(region);
    return true;
}

bool appendCheckRegion(QList<Region> &regions, const QString &name, QWidget &root,
                       QWidget &container, const QString &text)
{
    for (QCheckBox *box : container.findChildren<QCheckBox *>())
        if (box->text() == text)
            return appendRequiredRegion(regions, name, root, box);
    return false;
}

void nameChild(QWidget *child, const QString &name)
{
    if (child && child->objectName().isEmpty())
        child->setObjectName(name);
}

void scopeIndicatorNames(QWidget &root)
{
    const auto scrollBars =
        root.findChildren<QScrollBar *>(QStringLiteral("listPositionIndicator"));
    int index = 0;
    for (QScrollBar *bar : scrollBars) {
        QString scope;
        for (QWidget *ancestor = bar->parentWidget(); ancestor;
             ancestor = ancestor->parentWidget()) {
            if (!ancestor->objectName().isEmpty() &&
                !ancestor->objectName().startsWith(QLatin1String("qt_"))) {
                scope = ancestor->objectName();
                break;
            }
        }
        if (scope.isEmpty())
            scope = QStringLiteral("list.%1").arg(index);
        bar->setObjectName(scope + QStringLiteral(".position-indicator"));
        ++index;
    }
}

QRect clippedItemRect(QAbstractItemView &view, const QRect &itemRect)
{
    return itemRect.intersected(view.viewport()->rect());
}

void compareShown(const QString &id, QWidget &widget, const QList<Region> &extra)
{
    QString error;
    QVERIFY2(compareWidget(id, widget, mergeRegions(widgetRegions(widget), extra), &error),
             qPrintable(error));
}

} // namespace checks::visual
