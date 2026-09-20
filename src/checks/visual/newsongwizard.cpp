// Visual baseline check for the reusable QML New Song wizard
// (src/ui/newsong/NewSongWizard.qml). The wizard is a standalone
// ApplicationWindow driven by a detached controller; this suite hosts it in a
// real QQuickWindow offscreen, drives it with StubWizardController — the test
// double that mirrors the Swift NewSongWizardController contract, whose drift
// the startup gate below rejects — and freezes semantic region bounds plus
// rendered pixels through checks::visual::compare. The vanilla draft supplies
// the same catalog and content the QWidget baseline shows so the two surfaces
// can be compared directly; the rejected draft pins the identity and sound
// error bands a valid draft never populates.

#include "checks/visual/newsongwizardstub.h"
#include "checks/visual/visualquick.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFont>
#include <QGuiApplication>
#include <QPointer>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QtTest>

#include "checks/support/quickframebuffer.h"
#include "ui/theme/theme.h"
#include "ui/theme/theme_roles.h"
#include "ui/theme/themeresolver.h"

#ifndef PORYDAW_CHECK_SOURCE_DIR
#define PORYDAW_CHECK_SOURCE_DIR ""
#endif

namespace {

// The project root baked in at configure time: the two files the stub mirrors
// are parsed from the source tree, not from the build tree.
QString readSourceFile(const QString &relativePath, QString &error)
{
    QFile file(QDir(QString::fromUtf8(PORYDAW_CHECK_SOURCE_DIR)).absoluteFilePath(relativePath));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        error = relativePath + QStringLiteral(": ") + file.errorString();
        return {};
    }
    return QString::fromUtf8(file.readAll());
}

// The distinct first-capture-group matches, in file order. Duplicates collapse
// so the drift gate reports a renamed member once.
QStringList distinctCaptures(const QString &text, const QRegularExpression &pattern)
{
    QStringList names;
    QRegularExpressionMatchIterator matches = pattern.globalMatch(text);
    while (matches.hasNext()) {
        const QString name = matches.next().captured(1);
        if (!names.contains(name))
            names.append(name);
    }
    return names;
}

// Every name the stub publishes as a Qt property or method.
QSet<QString> stubMemberNames(const QMetaObject &metaObject)
{
    QSet<QString> names;
    for (int index = 0; index < metaObject.propertyCount(); ++index)
        names.insert(QString::fromUtf8(metaObject.property(index).name()));
    for (int index = 0; index < metaObject.methodCount(); ++index)
        names.insert(QString::fromUtf8(metaObject.method(index).name()));
    return names;
}

QStringList membersMissingFrom(const QSet<QString> &declared, const QStringList &referenced)
{
    QStringList missing;
    for (const QString &name : referenced) {
        if (!declared.contains(name))
            missing.append(name);
    }
    return missing;
}

// Map the resolved theme onto the palette keys NewSongWizard.qml reads. The
// wizard's `colors` contract names the same roles the prototype supplies.
QVariantMap wizardColors(const themes::Theme &theme)
{
    const auto pick = [&theme](themes::Role role) {
        return theme.color(role).name(QColor::HexArgb);
    };
    return {
        {QStringLiteral("windowBackground"), pick(themes::Role::window_background)},
        {QStringLiteral("chromeBackground"), pick(themes::Role::toolbar_background)},
        {QStringLiteral("separator"), pick(themes::Role::menu_separator)},
        {QStringLiteral("outline"), pick(themes::Role::palette_outline)},
        {QStringLiteral("tabHoverBackground"), pick(themes::Role::tab_hover_background)},
        {QStringLiteral("inputBackground"), pick(themes::Role::input_background)},
        {QStringLiteral("tabSelectedBackground"), pick(themes::Role::tab_selected_background)},
        {QStringLiteral("windowText"), pick(themes::Role::window_text)},
        {QStringLiteral("secondaryText"), pick(themes::Role::secondary_text)},
        {QStringLiteral("buttonBackground"), pick(themes::Role::button_background)},
        {QStringLiteral("buttonHoverBackground"), pick(themes::Role::button_hover_background)},
        {QStringLiteral("buttonPressedBackground"), pick(themes::Role::button_pressed_background)},
        {QStringLiteral("playhead"), pick(themes::Role::song_view_playhead)},
    };
}

// The identity page's frozen regions. The error scenario pins the same names
// and bounds, so the band's rectangle is compared with and without a message.
QList<checks::visual::Region> identityPageRegions(QQuickItem *root)
{
    return {
        checks::visual::quickItemRegion(QStringLiteral("wizard.name"), root,
                                        QStringLiteral("newSongName")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.constant"), root,
                                        QStringLiteral("newSongConstant")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.player"), root,
                                        QStringLiteral("newSongPlayer")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.identity-error"), root,
                                        QStringLiteral("newSongIdentityError")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.next"), root,
                                        QStringLiteral("newSongNext")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.cancel"), root,
                                        QStringLiteral("newSongCancel")),
    };
}

// The sound page's frozen regions, shared by its valid and rejected drafts.
QList<checks::visual::Region> soundPageRegions(QQuickItem *root)
{
    return {
        checks::visual::quickItemRegion(QStringLiteral("wizard.voicegroup"), root,
                                        QStringLiteral("newSongVoicegroup")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.volume"), root,
                                        QStringLiteral("newSongVolume")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.reverb"), root,
                                        QStringLiteral("newSongReverb")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.priority"), root,
                                        QStringLiteral("newSongPriority")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.exact-gate"), root,
                                        QStringLiteral("newSongExactGate")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.extended-clocks"), root,
                                        QStringLiteral("newSongExtendedClocks")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.no-compression"), root,
                                        QStringLiteral("newSongNoCompression")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.sound-error"), root,
                                        QStringLiteral("newSongSoundError")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.back"), root,
                                        QStringLiteral("newSongBack")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.finish"), root,
                                        QStringLiteral("newSongFinish")),
        checks::visual::quickItemRegion(QStringLiteral("wizard.cancel"), root,
                                        QStringLiteral("newSongCancel")),
    };
}
// A page switch re-hints the window width, and the button-row spacer expands
// over several frames — a single rendered frame can still catch the row
// mid-layout. Poll the trailing button's x until it stops moving so the frozen
// bounds describe the settled surface, not a transition frame.
void settleButtonRow(QQuickWindow *window, QQuickItem *root)
{
    if (!window || !root)
        return;
    int lastX = -1;
    for (int attempt = 0; attempt < 20; ++attempt) {
        checks::support::waitForQuickFrame(*window);
        checks::support::pumpQuick();
        const int x = checks::visual::quickItemBounds(root, QStringLiteral("newSongCancel")).x();
        if (x == lastX)
            return;
        lastX = x;
    }
}

} // namespace

class VisualNewSongWizardTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VisualNewSongWizardTest)

  public:
    VisualNewSongWizardTest() = default;

  private slots:
    void initTestCase();
    void cleanup();

    void identityPageVanilla();
    void soundPageVanilla();
    void identityErrorVanilla();
    void soundErrorVanilla();

  private:
    /// Which draft the stub is seeded with before the wizard is built: the
    /// valid catalog the QWidget baseline shows, or the rejected draft the
    /// error bands exist for.
    enum class Fixture { Vanilla, Errors };

    /// Fails when NewSongWizard.qml or NewSongWizardController.swift names a
    /// controller member StubWizardController does not declare.
    void verifyStubMirrorsSources();
    bool createWizard(QString &error, Fixture fixture = Fixture::Vanilla);
    void destroyWizard();

    QQmlEngine m_engine;
    StubWizardController m_controller;
    QPointer<QQuickWindow> m_host;
    QPointer<QQuickWindow> m_window;
    QPointer<QQuickItem> m_root;
};

void VisualNewSongWizardTest::initTestCase()
{
    checks::visual::prepare(*static_cast<QApplication *>(QCoreApplication::instance()));
    verifyStubMirrorsSources();
}

// The stub hand-mirrors the Swift controller with no compiler coupling, so an
// in-flight rename there or in the QML would silently weaken every later
// check. Both sources are parsed and every member they name must exist as a Qt
// property or method on the stub; extra stub members (the setters and the seed
// fixtures the scenarios drive) are expected.
void VisualNewSongWizardTest::verifyStubMirrorsSources()
{
    const QSet<QString> declared = stubMemberNames(*m_controller.metaObject());

    QString error;
    const QString qml = readSourceFile(QStringLiteral("src/ui/newsong/NewSongWizard.qml"), error);
    QVERIFY2(!qml.isNull(), qPrintable(error));
    const QStringList qmlMembers = distinctCaptures(
        qml, QRegularExpression(QStringLiteral("\\bcontroller\\.([A-Za-z_][A-Za-z0-9_]*)")));
    QVERIFY2(!qmlMembers.isEmpty(), "NewSongWizard.qml references no controller member to check");
    const QStringList qmlMissing = membersMissingFrom(declared, qmlMembers);
    const QString qmlReport =
        QStringLiteral("NewSongWizard.qml binds controller members the stub lacks: ") +
        qmlMissing.join(QStringLiteral(", "));
    QVERIFY2(qmlMissing.isEmpty(), qPrintable(qmlReport));

    const QString swift =
        readSourceFile(QStringLiteral("src/ui/newsong/NewSongWizardController.swift"), error);
    QVERIFY2(!swift.isNull(), qPrintable(error));
    const QStringList swiftMembers = distinctCaptures(
        swift,
        QRegularExpression(QStringLiteral("public\\s+(?:var|func)\\s+([A-Za-z_][A-Za-z0-9_]*)")));
    QVERIFY2(!swiftMembers.isEmpty(),
             "NewSongWizardController.swift declares no public member to check");
    const QStringList swiftMissing = membersMissingFrom(declared, swiftMembers);
    const QString swiftReport =
        QStringLiteral("NewSongWizardController.swift declares members the stub lacks: ") +
        swiftMissing.join(QStringLiteral(", "));
    QVERIFY2(swiftMissing.isEmpty(), qPrintable(swiftReport));
}

void VisualNewSongWizardTest::cleanup()
{
    destroyWizard();
}

bool VisualNewSongWizardTest::createWizard(QString &error, Fixture fixture)
{
    switch (fixture) {
    case Fixture::Vanilla:
        m_controller.seedFixture();
        break;
    case Fixture::Errors:
        m_controller.seedErrorFixture();
        break;
    }
    m_controller.setActive(true);

    // A host window supplies the transient parent so the wizard stacks as a
    // dialog exactly as it does under the prototype.
    m_host = new QQuickWindow();
    m_host->resize(640, 480);
    m_host->show();

    const QUrl url = QUrl::fromLocalFile(
        QDir(QString::fromUtf8(PORYDAW_CHECK_SOURCE_DIR))
            .absoluteFilePath(QStringLiteral("src/ui/newsong/NewSongWizard.qml")));
    QQmlComponent component(&m_engine, url);
    if (component.isError()) {
        error = component.errorString();
        return false;
    }

    const themes::Theme theme = themes::vanilla();
    QObject *object = component.createWithInitialProperties(
        {{QStringLiteral("controller"), QVariant::fromValue(&m_controller)},
         {QStringLiteral("colors"), wizardColors(theme)},
         // prepare() installed the bundled font at the profile's base size, so
         // this surface freezes the same metrics as the QWidget baselines.
         {QStringLiteral("font"), QVariant::fromValue(QGuiApplication::font())},
         {QStringLiteral("transientParent"), QVariant::fromValue(m_host.data())}});
    if (!object) {
        error = component.errorString();
        return false;
    }
    m_window = qobject_cast<QQuickWindow *>(object);
    if (!m_window) {
        error = QStringLiteral("NewSongWizard root is not a QQuickWindow");
        delete object;
        return false;
    }
    m_root = m_window->contentItem();
    if (!m_root) {
        error = QStringLiteral("NewSongWizard window has no content item");
        return false;
    }

    if (!QTest::qWaitFor(
            [this] { return m_window && m_window->isVisible() && m_window->isExposed(); })) {
        error = QStringLiteral("NewSongWizard window did not become exposed");
        return false;
    }
    return checks::support::waitForQuickFrame(*m_window, &error);
}

void VisualNewSongWizardTest::destroyWizard()
{
    if (m_window)
        m_window->close();
    delete m_window;
    delete m_host;
    m_window.clear();
    m_host.clear();
    m_root.clear();
}

void VisualNewSongWizardTest::identityPageVanilla()
{
    QString error;
    QVERIFY2(createWizard(error), qPrintable(error));
    m_controller.setPage(0);
    settleButtonRow(m_window, m_root);
    QVERIFY2(checks::visual::expectQuickBaseline(QStringLiteral("newsongwizard/identity-vanilla"),
                                                 *m_window, m_root.data(),
                                                 identityPageRegions(m_root.data()), &error),
             qPrintable(error));
}

void VisualNewSongWizardTest::soundPageVanilla()
{
    QString error;
    QVERIFY2(createWizard(error), qPrintable(error));
    m_controller.setPage(1);
    settleButtonRow(m_window, m_root);
    QVERIFY2(checks::visual::expectQuickBaseline(QStringLiteral("newsongwizard/sound-vanilla"),
                                                 *m_window, m_root.data(),
                                                 soundPageRegions(m_root.data()), &error),
             qPrintable(error));
}

void VisualNewSongWizardTest::identityErrorVanilla()
{
    QString error;
    QVERIFY2(createWizard(error, Fixture::Errors), qPrintable(error));
    m_controller.setPage(0);
    settleButtonRow(m_window, m_root);
    QVERIFY2(checks::visual::expectQuickBaseline(QStringLiteral("wizard/identity-error-vanilla"),
                                                 *m_window, m_root.data(),
                                                 identityPageRegions(m_root.data()), &error),
             qPrintable(error));
}
void VisualNewSongWizardTest::soundErrorVanilla()
{
    QString error;
    QVERIFY2(createWizard(error, Fixture::Errors), qPrintable(error));
    m_controller.setPage(1);
    settleButtonRow(m_window, m_root);
    QVERIFY2(checks::visual::expectQuickBaseline(QStringLiteral("wizard/sound-error-vanilla"),
                                                 *m_window, m_root.data(),
                                                 soundPageRegions(m_root.data()), &error),
             qPrintable(error));
}

int runVisualNewSongWizardCheck(QApplication &, const QStringList &qtArguments)
{
    VisualNewSongWizardTest test;
    QStringList arguments{QStringLiteral("visual-newsongwizard")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "newsongwizard.moc"
