#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

// Test double for the @QtBridgeable NewSongWizardController the QML New Song
// wizard (src/ui/newsong/NewSongWizard.qml) binds to. The check hosts that
// wizard offscreen without the Swift bridge, so this stub reproduces the Swift
// surface the QML expects — the same property names, user-action methods, and
// initial values — and performs no validation of its own: it is seeded with the
// draft the scenario wants frozen. VisualNewSongWizardTest::initTestCase()
// fails when either NewSongWizard.qml or NewSongWizardController.swift names a
// member this class does not declare, so a rename on either side cannot
// silently weaken the suite.
//
// The class lives beside its only user rather than inside newsongwizard.cpp
// because it mirrors a file in src/ui/newsong: a Swift rename changes this
// type, a scenario change usually does not.
class StubWizardController final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(StubWizardController)

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

    // Direct state setters for the checks; each emits its NOTIFY, so a
    // scenario may seed the draft in any order.
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
    void setPlayerNames(const QStringList &value)
    {
        if (m_playerNames == value)
            return;
        m_playerNames = value;
        emit playerNamesChanged();
    }
    void setPlayerIndex(int value)
    {
        if (m_playerIndex == value)
            return;
        m_playerIndex = value;
        emit playerIndexChanged();
    }
    void setVoicegroupNames(const QStringList &value)
    {
        if (m_voicegroupNames == value)
            return;
        m_voicegroupNames = value;
        emit voicegroupNamesChanged();
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

    // Seed the same catalog and draft the QWidget baseline shows. Every write
    // goes through the emitting setter, so no binding can read a half-applied
    // draft whichever order the seed's writes reach the QML in.
    void seedFixture()
    {
        setPlayerNames({QStringLiteral("Background music (MUSIC_PLAYER_BGM)"),
                        QStringLiteral("Sound effect (MUSIC_PLAYER_SE)")});
        setPlayerIndex(0);
        setVoicegroupNames({QStringLiteral("(create a new voicegroup for this song)"),
                            QStringLiteral("abandoned_ship"), QStringLiteral("se"),
                            QStringLiteral("mus_existing_bank")});
        setVoicegroupIndex(1);
        setVoicegroupText(QStringLiteral("abandoned_ship"));
        setName(QStringLiteral("mus_visual_check"));
        setConstant(QStringLiteral("MUS_VISUAL_CHECK"));
        applyMasterVolume(100);
        applyReverb(50);
        applyPriority(0);
        applyExactGate(true);
        applyExtendedClocks(false);
        applyNoCompression(false);
        setCanNext(true);
        setCanFinish(true);
    }

    // The rejected draft the wizard's error bands exist for: a name the
    // identity validator refuses, and the voicegroup collision the sound page
    // reports while the draft creates a new voicegroup. Texts mirror
    // NewSongDraft.identityValidation()/soundValidation(), and both pages'
    // primary actions are inert, as a failing draft leaves them.
    void seedErrorFixture()
    {
        seedFixture();
        setName(QStringLiteral("My Song"));
        setConstant(QStringLiteral("MY_SONG"));
        setIdentityError(
            QStringLiteral("Use lowercase letters, numbers, and underscores; start with a "
                           "letter or underscore."));
        setCanNext(false);
        setVoicegroupIndex(0);
        setVoicegroupText(QStringLiteral("My Song"));
        setSoundError(QStringLiteral("A voicegroup named voicegroup_My Song already exists — "
                                     "pick it from the list instead."));
        setCanFinish(false);
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
    // The Swift controller starts on "no voicegroup selected" (-1), not on the
    // first catalog entry.
    int m_voicegroupIndex = -1;
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
