// THROWAWAY native-host prototype — NOT production code.
// Question under test: can the composition prototype run embedded through the
// real QWidget -> QQuickView -> createWindowContainer seam, with a real
// QAction transport shortcut and NO custom focus management layer?
// Build/run via: deno run --allow-run --allow-read --allow-write --allow-env src/ui/songview/quick/composition-prototype/native_host.ts [--build-only]
#include <QAction>
#include <QApplication>
#include <QBoxLayout>
#include <QFontMetrics>
#include <QPushButton>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickView>
#include <QWidget>

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <absolute path to CompositionPrototype.qml>\n", argv[0]);
        return 2;
    }
    const QUrl qmlUrl = QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1]));

    QApplication app(argc, argv);

    // Font-scaled viewport: the QML root sizes itself in units of
    // u = max(8, font.pixelSize); mirror that here so the window fits.
    const int u = qMax(8, app.font().pixelSize() > 0 ? app.font().pixelSize()
                                                     : QFontMetrics(app.font()).height());
    QWidget shell;
    shell.setWindowTitle(QStringLiteral("Composition Prototype — native host"));

    auto *view = new QQuickView; // container takes ownership below
    view->setResizeMode(QQuickView::SizeRootObjectToView);
    view->setColor(QColor(QStringLiteral("#1e1e1e")));
    view->setSource(qmlUrl);
    if (view->status() != QQuickView::Ready) {
        for (const auto &e : view->errors())
            fprintf(stderr, "QML error: %s\n", qPrintable(e.toString()));
        return 3;
    }

    QQuickItem *root = view->rootObject();
    root->setProperty("nativeHost", true);

    // createWindowContainer reparents the QQuickView's window into the
    // widget tree: the QML scene dies with the container, before the
    // QApplication/engine dependencies it uses.
    QWidget *container = QWidget::createWindowContainer(view, &shell);
    container->setFocusPolicy(Qt::StrongFocus);
    container->setMinimumSize(u * 44, u * 32);

    auto *returnButton = new QPushButton(QStringLiteral("Return to editor"), &shell);

    auto *layout = new QVBoxLayout(&shell);
    layout->setContentsMargins(u / 2, u / 2, u / 2, u / 2);
    layout->setSpacing(u / 2);
    layout->addWidget(returnButton, 0, Qt::AlignLeft);
    layout->addWidget(container, 1);

    // Transport: a real QAction with WindowShortcut context on the outer
    // widget. TextFields inside the scene keep native shortcut precedence —
    // no key forwarding, no focus event filter.
    auto *transport = new QAction(QStringLiteral("Transport"), &shell);
    transport->setShortcut(QKeySequence(Qt::Key_Space));
    transport->setShortcutContext(Qt::WindowShortcut);
    QObject::connect(transport, &QAction::triggered, &shell, [root] {
        const int count = root->property("transportCount").toInt() + 1;
        root->setProperty("transportCount", count);
        printf("NATIVE_TRANSPORT %d\n", count);
        fflush(stdout);
    });
    shell.addAction(transport);

    // Explicit seam back into the QML editor FocusScope: ordinary container
    // focus plus the root's enterEditor(). Click-only; no timers.
    QObject::connect(returnButton, &QPushButton::clicked, &shell, [container, root] {
        container->setFocus(Qt::OtherFocusReason);
        QMetaObject::invokeMethod(root, "enterEditor",
                                  Q_ARG(QVariant, QVariant(Qt::OtherFocusReason)));
    });

    shell.resize(u * 46, u * 35);
    shell.show();
    container->setFocus(Qt::OtherFocusReason); // initial focus through the container

    printf("NATIVE_PROTOTYPE_READY\n");
    fflush(stdout);

    return app.exec();
}
