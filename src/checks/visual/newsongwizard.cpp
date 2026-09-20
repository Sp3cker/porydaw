// Visual baseline check for the reusable QML New Song wizard
// (src/ui/newsong/NewSongWizard.qml). The wizard is a standalone
// ApplicationWindow driven by a detached controller; this suite hosts it in a
// real QQuickWindow offscreen, drives it with a stub that mirrors the Swift
// NewSongWizardController contract, and freezes semantic region bounds plus
// rendered pixels through checks::visual::compare. The stub supplies the same
// catalog and draft content the QWidget baseline uses so the two surfaces can
// be compared directly.

#include "checks/visual/visualbaseline.h"

#include <QCoreApplication>
#include <QFont>
#include <QGuiApplication>
#include <QImage>
#include <QPointer>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QString>
#include <QVariantMap>
#include <QtTest>

#include "checks/support/quickframebuffer.h"
#include "checks/support/timelinequickcheck.h"
#include "ui/theme/theme.h"
#include "ui/theme/theme_roles.h"
#include "ui/theme/themeresolver.h"

#ifndef PORYDAW_CHECK_SOURCE_DIR
#define PORYDAW_CHECK_SOURCE_DIR ""
#endif

namespace {

// Mirrors the @QtBridgeable NewSongWizardController surface the QML binds to.
// Only the visual contract is reproduced: snapshot properties plus the
// user-action methods. Setters emit the matching NOTIFY so the QML bindings
// re-read; the stub performs no validation of its own.
class StubWizardController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(int page READ page NOTIFY pageChanged)
    Q_PROPERTY(QString name READ name NOTIFY nameChanged)
    Q_PROPERTY(QString constant READ constant NOTIFY constantChanged)
    Q_PROPERTY(QStringList playerNames READ playerNames NOTIFY playerNamesChanged)
    Q_PROPERTY(int playerIndex READ playerIndex NOTIFY playerIndexChanged)
    Q_PROPERTY(QStringList voicegroupNames READ voicegroupNames NOTIFY voicegroupNamesChanged)
    Q_PROPERTY(int voicegroupIndex READ voicegroupIndex NOTIFY voicegroupIndexChanged)
    Q_PROPERTY(QString voicegroupText READ voicegroupText NOTIFY voicegroupTextChanged)
    Q_PROPERTY(int masterVolume READ masterVolume NOTIFY masterVolumeChanged)
    Q_PROPERTY(int reverb READ reverb NOTIFY reverbChanged)
    Q_PROPERTY(int priority READ priority NOTIFY priorityChanged)
    Q_PROPERTY(bool exactGate READ exactGate NOTIFY exactGateChanged)
    Q_PROPERTY(bool extendedClocks READ extendedClocks NOTIFY extendedClocksChanged)
    Q_PROPERTY(bool noCompression READ noCompression NOTIFY noCompressionChanged)
    Q_PROPERTY(QString identityError READ identityError NOTIFY identityErrorChanged)
    Q_PROPERTY(QString soundError READ soundError NOTIFY soundErrorChanged)
    Q_PROPERTY(bool canNext READ canNext NOTIFY canNextChanged)
    Q_PROPERTY(bool canFinish READ canFinish NOTIFY canFinishChanged)

  public:
    explicit StubWizardController(QObject *parent = nullptr) : QObject(parent) {}

    bool active() const { return m_active; }
    int page() const { return m_page; }
    QString name() const { return m_name; }
    QString constant() const { return m_constant; }
    QStringList playerNames() const { return m_playerNames; }
    int playerIndex() const { return m_playerIndex; }
    QStringList voicegroupNames() const { return m_voicegroupNames; }
    int voicegroupIndex() const { return m_voicegroupIndex; }
    QString voicegroupText() const { return m_voicegroupText; }
    int masterVolume() const { return m_masterVolume; }
    int reverb() const { return m_reverb; }
    int priority() const { return m_priority; }
    bool exactGate() const { return m_exactGate; }
    bool extendedClocks() const { return m_extendedClocks; }
    bool noCompression() const { return m_noCompression; }
    QString identityError() const { return m_identityError; }
    QString soundError() const { return m_soundError; }
    bool canNext() const { return m_canNext; }
    bool canFinish() const { return m_canFinish; }

    // User-action entry points the QML calls; the stub applies the same
    // deterministic transitions a real session would for the states under
    // test so Return/click paths stay live.
    Q_INVOKABLE void begin() { setActive(true); }
    Q_INVOKABLE void next() { setPage(1); }
    Q_INVOKABLE void back() { setPage(0); }
    Q_INVOKABLE void finish() { setActive(false); }
    Q_INVOKABLE void cancel() { setActive(false); }
    Q_INVOKABLE void editName(const QString &text) { setName(text); }
    Q_INVOKABLE void editConstant(const QString &text) { setConstant(text); }
    Q_INVOKABLE void selectPlayer(int index) { setPlayerIndex(index); }
    Q_INVOKABLE void selectVoicegroup(int index) { setVoicegroupIndex(index); }
    Q_INVOKABLE void editVoicegroup(const QString &text) { setVoicegroupText(text); }
    Q_INVOKABLE void setMasterVolume(int value) { applyMasterVolume(value); }
    Q_INVOKABLE void setReverb(int value) { applyReverb(value); }
    Q_INVOKABLE void setPriority(int value) { applyPriority(value); }
    Q_INVOKABLE void setExactGate(bool value) { applyExactGate(value); }
    Q_INVOKABLE void setExtendedClocks(bool value) { applyExtendedClocks(value); }
    Q_INVOKABLE void setNoCompression(bool value) { applyNoCompression(value); }

    // Direct state setters for the check; each emits its NOTIFY.
    void setActive(bool value)
    {
        if (m_active == value)
            return;
        m_active = value;
        emit activeChanged();
    }
    void setPage(int value)
    {
        if (m_page == value)
            return;
        m_page = value;
        emit pageChanged();
    }
    void setName(const QString &value)
    {
        if (m_name == value)
            return;
        m_name = value;
        emit nameChanged();
    }
    void setConstant(const QString &value)
    {
        if (m_constant == value)
            return;
        m_constant = value;
        emit constantChanged();
    }
    void setPlayerIndex(int value)
    {
        if (m_playerIndex == value)
            return;
        m_playerIndex = value;
        emit playerIndexChanged();
    }
    void setVoicegroupIndex(int value)
    {
        if (m_voicegroupIndex == value)
            return;
        m_voicegroupIndex = value;
        emit voicegroupIndexChanged();
    }
    void setVoicegroupText(const QString &value)
    {
        if (m_voicegroupText == value)
            return;
        m_voicegroupText = value;
        emit voicegroupTextChanged();
    }
    void applyMasterVolume(int value)
    {
        if (m_masterVolume == value)
            return;
        m_masterVolume = value;
        emit masterVolumeChanged();
    }
    void applyReverb(int value)
    {
        if (m_reverb == value)
            return;
        m_reverb = value;
        emit reverbChanged();
    }
    void applyPriority(int value)
    {
        if (m_priority == value)
            return;
        m_priority = value;
        emit priorityChanged();
    }
    void applyExactGate(bool value)
    {
        if (m_exactGate == value)
            return;
        m_exactGate = value;
        emit exactGateChanged();
    }
    void applyExtendedClocks(bool value)
    {
        if (m_extendedClocks == value)
            return;
        m_extendedClocks = value;
        emit extendedClocksChanged();
    }
    void applyNoCompression(bool value)
    {
        if (m_noCompression == value)
            return;
        m_noCompression = value;
        emit noCompressionChanged();
    }
    void setIdentityError(const QString &value)
    {
        if (m_identityError == value)
            return;
        m_identityError = value;
        emit identityErrorChanged();
    }
    void setSoundError(const QString &value)
    {
        if (m_soundError == value)
            return;
        m_soundError = value;
        emit soundErrorChanged();
    }
    void setCanNext(bool value)
    {
        if (m_canNext == value)
            return;
        m_canNext = value;
        emit canNextChanged();
    }
    void setCanFinish(bool value)
    {
        if (m_canFinish == value)
            return;
        m_canFinish = value;
        emit canFinishChanged();
    }

    // Seed the same catalog and draft the QWidget baseline shows.
    void seedFixture()
    {
        m_playerNames = {QStringLiteral("Background music (MUSIC_PLAYER_BGM)"),
                         QStringLiteral("Sound effect (MUSIC_PLAYER_SE)")};
        m_playerIndex = 0;
        m_voicegroupNames = {QStringLiteral("(create a new voicegroup for this song)"),
                             QStringLiteral("abandoned_ship"), QStringLiteral("se"),
                             QStringLiteral("mus_existing_bank")};
        m_voicegroupIndex = 1;
        m_voicegroupText = QStringLiteral("abandoned_ship");
        m_name = QStringLiteral("mus_visual_check");
        m_constant = QStringLiteral("MUS_VISUAL_CHECK");
        m_masterVolume = 100;
        m_reverb = 50;
        m_priority = 0;
        m_exactGate = true;
        m_extendedClocks = false;
        m_noCompression = false;
        m_canNext = true;
        m_canFinish = true;
    }

  signals:
    void activeChanged();
    void pageChanged();
    void nameChanged();
    void constantChanged();
    void playerNamesChanged();
    void playerIndexChanged();
    void voicegroupNamesChanged();
    void voicegroupIndexChanged();
    void voicegroupTextChanged();
    void masterVolumeChanged();
    void reverbChanged();
    void priorityChanged();
    void exactGateChanged();
    void extendedClocksChanged();
    void noCompressionChanged();
    void identityErrorChanged();
    void soundErrorChanged();
    void canNextChanged();
    void canFinishChanged();

  private:
    bool m_active = false;
    int m_page = 0;
    QString m_name;
    QString m_constant;
    QStringList m_playerNames;
    int m_playerIndex = 0;
    QStringList m_voicegroupNames;
    int m_voicegroupIndex = 0;
    QString m_voicegroupText;
    int m_masterVolume = 100;
    int m_reverb = 50;
    int m_priority = 0;
    bool m_exactGate = true;
    bool m_extendedClocks = false;
    bool m_noCompression = false;
    QString m_identityError;
    QString m_soundError;
    bool m_canNext = false;
    bool m_canFinish = false;
};

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

  private:
    bool createWizard(QString &error);
    void destroyWizard();
    QImage grab(QString &error);
    QRect itemBounds(const QString &objectName) const;
    checks::visual::Region region(const QString &name, const QRect &bounds) const;
    checks::visual::Region itemRegion(const QString &name, const QString &objectName) const;
    void expectBaseline(const QString &id, const QList<checks::visual::Region> &regions);

    QQmlEngine m_engine;
    StubWizardController m_controller;
    QPointer<QQuickWindow> m_host;
    QPointer<QQuickWindow> m_window;
    QPointer<QQuickItem> m_root;
};

void VisualNewSongWizardTest::initTestCase()
{
    checks::visual::prepare(*static_cast<QApplication *>(QCoreApplication::instance()));
}

void VisualNewSongWizardTest::cleanup()
{
    destroyWizard();
}

bool VisualNewSongWizardTest::createWizard(QString &error)
{
    m_controller.seedFixture();
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

QImage VisualNewSongWizardTest::grab(QString &error)
{
    if (!m_window || !checks::support::waitForQuickFrame(*m_window, &error))
        return {};
    const QImage image = m_window->grabWindow();
    if (image.isNull())
        error = QStringLiteral("NewSongWizard framebuffer grab is empty");
    return image;
}

QRect VisualNewSongWizardTest::itemBounds(const QString &objectName) const
{
    QQuickItem *const item = checks::support::visualDescendant(m_root.data(), objectName);
    if (!item || item->width() <= 0 || item->height() <= 0)
        return {};
    const QPointF topLeft = item->mapToScene(QPointF{});
    return {qRound(topLeft.x()), qRound(topLeft.y()), qRound(item->width()),
            qRound(item->height())};
}

checks::visual::Region VisualNewSongWizardTest::region(const QString &name,
                                                       const QRect &bounds) const
{
    return {name, bounds};
}

checks::visual::Region VisualNewSongWizardTest::itemRegion(const QString &name,
                                                           const QString &objectName) const
{
    return region(name, itemBounds(objectName));
}

void VisualNewSongWizardTest::expectBaseline(const QString &id,
                                             const QList<checks::visual::Region> &regions)
{
    QString error;
    const QImage image = grab(error);
    QVERIFY2(!image.isNull(), qPrintable(error));
    for (const checks::visual::Region &entry : regions)
        QVERIFY2(!entry.bounds.isEmpty(), qPrintable(entry.name + " has no visible bounds"));
    QVERIFY2(checks::visual::compare(id, image, regions, &error), qPrintable(error));
}

void VisualNewSongWizardTest::identityPageVanilla()
{
    QString error;
    QVERIFY2(createWizard(error), qPrintable(error));
    m_controller.setPage(0);
    checks::support::pumpQuick();
    expectBaseline(
        QStringLiteral("newsongwizard/identity-vanilla"),
        {itemRegion(QStringLiteral("wizard.name"), QStringLiteral("newSongName")),
         itemRegion(QStringLiteral("wizard.constant"), QStringLiteral("newSongConstant")),
         itemRegion(QStringLiteral("wizard.player"), QStringLiteral("newSongPlayer")),
         itemRegion(QStringLiteral("wizard.identity-error"),
                    QStringLiteral("newSongIdentityError")),
         itemRegion(QStringLiteral("wizard.next"), QStringLiteral("newSongNext")),
         itemRegion(QStringLiteral("wizard.cancel"), QStringLiteral("newSongCancel"))});
}

void VisualNewSongWizardTest::soundPageVanilla()
{
    QString error;
    QVERIFY2(createWizard(error), qPrintable(error));
    m_controller.setPage(1);
    checks::support::pumpQuick();
    expectBaseline(
        QStringLiteral("newsongwizard/sound-vanilla"),
        {itemRegion(QStringLiteral("wizard.voicegroup"), QStringLiteral("newSongVoicegroup")),
         itemRegion(QStringLiteral("wizard.volume"), QStringLiteral("newSongVolume")),
         itemRegion(QStringLiteral("wizard.reverb"), QStringLiteral("newSongReverb")),
         itemRegion(QStringLiteral("wizard.priority"), QStringLiteral("newSongPriority")),
         itemRegion(QStringLiteral("wizard.exact-gate"), QStringLiteral("newSongExactGate")),
         itemRegion(QStringLiteral("wizard.extended-clocks"),
                    QStringLiteral("newSongExtendedClocks")),
         itemRegion(QStringLiteral("wizard.no-compression"),
                    QStringLiteral("newSongNoCompression")),
         itemRegion(QStringLiteral("wizard.sound-error"), QStringLiteral("newSongSoundError")),
         itemRegion(QStringLiteral("wizard.back"), QStringLiteral("newSongBack")),
         itemRegion(QStringLiteral("wizard.finish"), QStringLiteral("newSongFinish")),
         itemRegion(QStringLiteral("wizard.cancel"), QStringLiteral("newSongCancel"))});
}

int runVisualNewSongWizardCheck(QApplication &, const QStringList &qtArguments)
{
    VisualNewSongWizardTest test;
    QStringList arguments{QStringLiteral("visual-newsongwizard")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "newsongwizard.moc"
