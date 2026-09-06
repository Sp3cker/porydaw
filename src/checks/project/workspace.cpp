#include <QtTest>

#include <QDir>
#include <QSettings>
#include <QTemporaryDir>
#include <QTimer>

#include <algorithm>

#include <deque>
#include <memory>
#include <optional>
#include <utility>
#include <variant>

#include "project/projectidentity.h"
#include "project/projectworkspace.h"
#include "project/songregistry.h"
#include "project/voicegroupsource.h"

namespace {

using Entry = std::variant<ProjectState, ProjectEvent, SongUpdate>;

int stateCount(const std::deque<Entry> &log)
{
    int count = 0;
    for (const Entry &entry : log)
        count += std::holds_alternative<ProjectState>(entry) ? 1 : 0;
    return count;
}

const ProjectState *lastState(const std::deque<Entry> &log)
{
    for (auto it = log.rbegin(); it != log.rend(); ++it)
        if (const auto *const state = std::get_if<ProjectState>(&*it))
            return state;
    return nullptr;
}

bool lastStateIs(const std::deque<Entry> &log, ProjectOpenState state)
{
    const ProjectState *const last = lastState(log);
    return last && last->state == state;
}

template <typename Match>
int indexOf(const std::deque<Entry> &log, int begin, Match &&match)
{
    for (int index = std::max(begin, 0); index < static_cast<int>(log.size()); ++index)
        if (match(log[index]))
            return index;
    return -1;
}

int stateIndexOf(const std::deque<Entry> &log, ProjectOpenState state)
{
    return indexOf(log, 0, [state](const Entry &entry) {
        const auto *const candidate = std::get_if<ProjectState>(&entry);
        return candidate && candidate->state == state;
    });
}

bool isTerminal(const SongUpdate &update)
{
    return std::holds_alternative<VoicegroupBound>(update.payload) ||
           std::holds_alternative<SongFailed>(update.payload);
}

int terminalCount(const std::deque<Entry> &log, const SongName &song)
{
    int count = 0;
    for (const Entry &entry : log) {
        const auto *const update = std::get_if<SongUpdate>(&entry);
        count += update && update->song == song && isTerminal(*update) ? 1 : 0;
    }
    return count;
}

int terminalIndexOf(const std::deque<Entry> &log, const SongName &song)
{
    return indexOf(log, 0, [&song](const Entry &entry) {
        const auto *const update = std::get_if<SongUpdate>(&entry);
        return update && update->song == song && isTerminal(*update);
    });
}

bool hasPublishedCatalog(const Entry &entry)
{
    const auto *const state = std::get_if<ProjectState>(&entry);
    return state && !state->catalog.groupArgs.isEmpty();
}

template <typename Failure>
const Failure *mutationFailure(const Entry &entry)
{
    const auto *const event = std::get_if<ProjectEvent>(&entry);
    const auto *const failure = event ? std::get_if<ProjectMutationFailure>(event) : nullptr;
    return failure ? std::get_if<Failure>(failure) : nullptr;
}

int firstFilledSlot(const LoadedBankView &view)
{
    for (int index = 0; index < view.slotViews.size(); ++index)
        if (view.slotViews[index].voice.has_value())
            return index;
    return -1;
}

enum class CatalogCase { Refresh, DuplicateVoicegroup };
enum class EditCase { Conflict, Applied, HardFailure };

class ProjectWorkspaceTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(ProjectWorkspaceTest)

  public:
    explicit ProjectWorkspaceTest(QString stagedRoot) : m_stagedRoot(std::move(stagedRoot)) {}

  private slots:
    void init();
    void cleanup();
    void openRefusedWhileLoading_errorPresent_pathNotWritten();
    void successWritesLastPath_failedRetainsSnapshot();
    void startupLoadingLeadsReadyLeadsSongs_selectedFirstInOrder();
    void missingSavedNameReconcileFailure();
    void autoCatalogExactlyOnceAfterAllTerminals();
    void catalogReplaceVsUnkeyedFailure_data();
    void catalogReplaceVsUnkeyedFailure();
    void planEventsForwardKeyed();
    void silentCompletionsAdvanceFifoWithoutPublication();
    void reloadStagesMidiViewBound();
    void editConflict_appliedReceipt_hardFailure_data();
    void editConflict_appliedReceipt_hardFailure();

  private:
    template <typename Ready>
    bool waitFor(Ready &&ready, QString &error);
    void clearSavedProjectSettings();
    void seedStartupSettings();
    void startWorkspace();
    bool openReady(QString &error);
    bool startRestoredStartup(QString &error);
    bool waitForStartupTerminals(const SongName &route101, const SongName &petalburg,
                                 const SongName &missing, QString &error);
    void verifyStateErrorInvariant();

    QString m_stagedRoot;
    std::unique_ptr<QTemporaryDir> m_settingsDirectory;
    std::unique_ptr<ProjectWorkspace> m_workspace;
    QEventLoop m_loop;
    std::deque<Entry> m_log;
};

template <typename Ready>
bool ProjectWorkspaceTest::waitFor(Ready &&ready, QString &error)
{
    bool timedOut = false;
    QTimer timer;
    timer.setSingleShot(true);
    timer.setInterval(30000);
    QObject::connect(&timer, &QTimer::timeout, &m_loop, [&] {
        timedOut = true;
        m_loop.quit();
    });
    while (!timedOut && !ready()) {
        timer.start();
        m_loop.exec();
    }
    timer.stop();
    if (ready())
        return true;
    error = QStringLiteral("timed out waiting for ProjectWorkspace publication");
    return false;
}

void ProjectWorkspaceTest::clearSavedProjectSettings()
{
    QSettings settings;
    settings.remove(QStringLiteral("lastProjectDir"));
    settings.remove(QStringLiteral("lastOpenSongs"));
    settings.remove(QStringLiteral("lastSongLabel"));
    settings.sync();
}

void ProjectWorkspaceTest::seedStartupSettings()
{
    QSettings settings;
    settings.setValue(QStringLiteral("lastProjectDir"), m_stagedRoot);
    settings.setValue(QStringLiteral("lastOpenSongs"),
                      QStringList{QStringLiteral("mus_petalburg"), QStringLiteral("mus_route101"),
                                  QStringLiteral("porydaw_missing_song")});
    settings.setValue(QStringLiteral("lastSongLabel"), QStringLiteral("mus_route101"));
    settings.sync();
}

void ProjectWorkspaceTest::startWorkspace()
{
    m_log.clear();
    m_workspace = std::make_unique<ProjectWorkspace>();
    const auto record = [this](auto value) {
        m_log.emplace_back(std::move(value));
        m_loop.quit();
    };
    connect(m_workspace.get(), &ProjectWorkspace::projectStatePublished, m_workspace.get(),
            [record](ProjectState state) { record(std::move(state)); });
    connect(m_workspace.get(), &ProjectWorkspace::projectEventPublished, m_workspace.get(),
            [record](ProjectEvent event) { record(std::move(event)); });
    connect(m_workspace.get(), &ProjectWorkspace::songUpdatePublished, m_workspace.get(),
            [record](SongUpdate update) { record(std::move(update)); });
}

bool ProjectWorkspaceTest::openReady(QString &error)
{
    startWorkspace();
    m_workspace->openProject(OpenProjectInput{m_stagedRoot});
    return waitFor(
        [this] {
            const ProjectState *const state = lastState(m_log);
            return state && state->state == ProjectOpenState::Ready &&
                   !state->catalog.groupArgs.isEmpty();
        },
        error);
}

bool ProjectWorkspaceTest::startRestoredStartup(QString &error)
{
    Q_UNUSED(error);
    seedStartupSettings();
    startWorkspace();
    return true;
}

bool ProjectWorkspaceTest::waitForStartupTerminals(const SongName &route101,
                                                   const SongName &petalburg,
                                                   const SongName &missing, QString &error)
{
    return waitFor(
        [&] {
            return terminalCount(m_log, route101) >= 1 && terminalCount(m_log, petalburg) >= 1 &&
                   terminalCount(m_log, missing) >= 1;
        },
        error);
}

void ProjectWorkspaceTest::verifyStateErrorInvariant()
{
    for (const Entry &entry : m_log) {
        const auto *const state = std::get_if<ProjectState>(&entry);
        if (state)
            QCOMPARE(state->error.has_value(), state->state == ProjectOpenState::Failed);
    }
}

void ProjectWorkspaceTest::init()
{
    m_settingsDirectory = std::make_unique<QTemporaryDir>();
    QVERIFY2(m_settingsDirectory->isValid(), "could not create isolated QSettings directory");
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settingsDirectory->path());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, m_settingsDirectory->path());
    clearSavedProjectSettings();
}

void ProjectWorkspaceTest::cleanup()
{
    verifyStateErrorInvariant();
    m_workspace.reset();
    clearSavedProjectSettings();
    m_log.clear();
    m_settingsDirectory.reset();
}

void ProjectWorkspaceTest::openRefusedWhileLoading_errorPresent_pathNotWritten()
{
    startWorkspace();
    const QString goneRoot = m_stagedRoot + QStringLiteral("/gone");
    m_workspace->openProject(OpenProjectInput{goneRoot});
    QCOMPARE(stateCount(m_log), 1);
    m_workspace->openProject(OpenProjectInput{m_stagedRoot});
    QCOMPARE(stateCount(m_log), 1);

    QString error;
    QVERIFY2(waitFor([this] { return lastStateIs(m_log, ProjectOpenState::Failed); }, error),
             qPrintable(error));
    const ProjectState *const failed = lastState(m_log);
    QVERIFY(failed);
    if (failed)
        QVERIFY(failed->error && !failed->error->isEmpty());
    const QSettings settings;
    QVERIFY(!settings.contains(QStringLiteral("lastProjectDir")));

    m_workspace->openProject(OpenProjectInput{m_stagedRoot});
    QVERIFY2(waitFor([this] { return lastStateIs(m_log, ProjectOpenState::Ready); }, error),
             qPrintable(error));
    QCOMPARE(QSettings().value(QStringLiteral("lastProjectDir")).toString(),
             QDir(m_stagedRoot).absolutePath());
}

void ProjectWorkspaceTest::successWritesLastPath_failedRetainsSnapshot()
{
    QString error;
    QVERIFY2(openReady(error), qPrintable(error));
    const QString goneRoot = m_stagedRoot + QStringLiteral("/gone");
    m_workspace->openProject(OpenProjectInput{goneRoot});
    QVERIFY2(waitFor([this] { return lastStateIs(m_log, ProjectOpenState::Failed); }, error),
             qPrintable(error));
    const ProjectState *const failed = lastState(m_log);
    QVERIFY(failed);
    if (failed) {
        QCOMPARE(failed->snapshot.root(), QDir(m_stagedRoot).absolutePath());
        QVERIFY(failed->snapshot.isOpen());
    }

    m_workspace->openProject(OpenProjectInput{m_stagedRoot});
    QVERIFY2(waitFor(
                 [this] {
                     const ProjectState *const state = lastState(m_log);
                     return state && state->state == ProjectOpenState::Ready &&
                            !state->catalog.groupArgs.isEmpty();
                 },
                 error),
             qPrintable(error));
    QCOMPARE(QSettings().value(QStringLiteral("lastProjectDir")).toString(),
             QDir(m_stagedRoot).absolutePath());
}

void ProjectWorkspaceTest::startupLoadingLeadsReadyLeadsSongs_selectedFirstInOrder()
{
    QString error;
    QVERIFY2(startRestoredStartup(error), qPrintable(error));
    const std::optional<SongName> route101 = SongName::create(QStringLiteral("mus_route101"));
    const std::optional<SongName> petalburg = SongName::create(QStringLiteral("mus_petalburg"));
    const std::optional<SongName> missing =
        SongName::create(QStringLiteral("porydaw_missing_song"));
    QVERIFY(route101);
    QVERIFY(petalburg);
    QVERIFY(missing);
    if (!(route101 && petalburg && missing))
        return;
    QVERIFY2(waitForStartupTerminals(*route101, *petalburg, *missing, error), qPrintable(error));

    const int loading = stateIndexOf(m_log, ProjectOpenState::Loading);
    const int ready = stateIndexOf(m_log, ProjectOpenState::Ready);
    const int selected = terminalIndexOf(m_log, *route101);
    const int rest = terminalIndexOf(m_log, *petalburg);
    const int failed = terminalIndexOf(m_log, *missing);
    QCOMPARE(loading, 0);
    QVERIFY(ready > loading);
    QVERIFY(selected > ready);
    QVERIFY(rest > ready);
    QVERIFY(failed > ready);
    QVERIFY(selected < rest);
    QVERIFY(rest < failed);
}

void ProjectWorkspaceTest::missingSavedNameReconcileFailure()
{
    QString error;
    QVERIFY2(startRestoredStartup(error), qPrintable(error));
    const std::optional<SongName> route101 = SongName::create(QStringLiteral("mus_route101"));
    const std::optional<SongName> petalburg = SongName::create(QStringLiteral("mus_petalburg"));
    const std::optional<SongName> missing =
        SongName::create(QStringLiteral("porydaw_missing_song"));
    QVERIFY(route101);
    QVERIFY(petalburg);
    QVERIFY(missing);
    if (!(route101 && petalburg && missing))
        return;
    QVERIFY2(waitForStartupTerminals(*route101, *petalburg, *missing, error), qPrintable(error));

    bool found = false;
    for (const Entry &entry : m_log) {
        const auto *const update = std::get_if<SongUpdate>(&entry);
        if (!update || update->song != *missing)
            continue;
        const auto *const failure = std::get_if<SongFailed>(&update->payload);
        if (!failure)
            continue;
        found = true;
        QCOMPARE(failure->stage, SongStage::Reconcile);
        QVERIFY(!failure->message.isEmpty());
    }
    QVERIFY(found);
}

void ProjectWorkspaceTest::autoCatalogExactlyOnceAfterAllTerminals()
{
    QString error;
    QVERIFY2(startRestoredStartup(error), qPrintable(error));
    const int startupMark = static_cast<int>(m_log.size());
    const std::optional<SongName> route101 = SongName::create(QStringLiteral("mus_route101"));
    const std::optional<SongName> petalburg = SongName::create(QStringLiteral("mus_petalburg"));
    const std::optional<SongName> missing =
        SongName::create(QStringLiteral("porydaw_missing_song"));
    QVERIFY(route101);
    QVERIFY(petalburg);
    QVERIFY(missing);
    if (!(route101 && petalburg && missing))
        return;
    QVERIFY2(waitForStartupTerminals(*route101, *petalburg, *missing, error), qPrintable(error));
    const int ready = stateIndexOf(m_log, ProjectOpenState::Ready);
    const int selected = terminalIndexOf(m_log, *route101);
    const int rest = terminalIndexOf(m_log, *petalburg);
    const int failed = terminalIndexOf(m_log, *missing);

    QVERIFY2(
        waitFor(
            [this, startupMark] { return indexOf(m_log, startupMark, hasPublishedCatalog) >= 0; },
            error),
        qPrintable(error));
    const int catalogIndex = indexOf(m_log, startupMark, hasPublishedCatalog);
    QVERIFY(catalogIndex > ready);
    QVERIFY(catalogIndex > selected);
    QVERIFY(catalogIndex > rest);
    QVERIFY(catalogIndex > failed);

    int catalogCount = 0;
    for (int index = startupMark; index < static_cast<int>(m_log.size()); ++index) {
        catalogCount += hasPublishedCatalog(m_log[index]) ? 1 : 0;
        QVERIFY(mutationFailure<CatalogMutationFailed>(m_log[index]) == nullptr);
    }
    QCOMPARE(catalogCount, 1);
}

void ProjectWorkspaceTest::catalogReplaceVsUnkeyedFailure_data()
{
    QTest::addColumn<int>("catalogCase");
    QTest::newRow("refresh-replaces-catalog") << static_cast<int>(CatalogCase::Refresh);
    QTest::newRow("duplicate-voicegroup-is-unkeyed-failure")
        << static_cast<int>(CatalogCase::DuplicateVoicegroup);
}

void ProjectWorkspaceTest::catalogReplaceVsUnkeyedFailure()
{
    QFETCH(int, catalogCase);
    QString error;
    QVERIFY2(openReady(error), qPrintable(error));
    const int mark = static_cast<int>(m_log.size());

    if (static_cast<CatalogCase>(catalogCase) == CatalogCase::Refresh) {
        m_workspace->submit(ProjectOperation{RefreshCatalogInput{}});
        QVERIFY2(
            waitFor([this, mark] { return indexOf(m_log, mark, hasPublishedCatalog) >= 0; }, error),
            qPrintable(error));
        QCOMPARE(static_cast<int>(m_log.size()), mark + 1);
        return;
    }

    const ProjectState *const state = lastState(m_log);
    QVERIFY(state);
    if (!state)
        return;
    QVERIFY(!state->catalog.groupArgs.isEmpty());
    if (state->catalog.groupArgs.isEmpty())
        return;
    const QString duplicateName = state->catalog.groupArgs.first().mid(1);
    m_workspace->submit(
        ProjectOperation{CreateVoicegroupInput{duplicateName, QString{}, QString{}}});
    QVERIFY2(waitFor(
                 [this, mark] {
                     return indexOf(m_log, mark, [](const Entry &entry) {
                                return mutationFailure<CatalogMutationFailed>(entry) != nullptr;
                            }) >= 0;
                 },
                 error),
             qPrintable(error));
    QCOMPARE(static_cast<int>(m_log.size()), mark + 1);
}

void ProjectWorkspaceTest::planEventsForwardKeyed()
{
    QString error;
    QVERIFY2(openReady(error), qPrintable(error));
    const std::optional<SongName> route101 = SongName::create(QStringLiteral("mus_route101"));
    QVERIFY(route101);
    if (!route101)
        return;
    const QString constant = SongRegistry::constantForLabel(route101->value());

    int mark = static_cast<int>(m_log.size());
    m_workspace->submit(ProjectOperation{
        RegistrationPlanInput{route101->value(), constant, QStringLiteral("MUSIC_PLAYER_BGM")}});
    QVERIFY2(waitFor(
                 [this, mark] {
                     return indexOf(m_log, mark, [](const Entry &entry) {
                                const auto *const event = std::get_if<ProjectEvent>(&entry);
                                return event &&
                                       std::holds_alternative<RegistrationPlanResult>(*event);
                            }) >= 0;
                 },
                 error),
             qPrintable(error));
    const auto *const registrationEvent = std::get_if<ProjectEvent>(&m_log[mark]);
    QVERIFY(registrationEvent);
    if (!registrationEvent)
        return;
    const auto *const registration = std::get_if<RegistrationPlanResult>(registrationEvent);
    QVERIFY(registration);
    if (registration)
        QVERIFY(registration->song == *route101);

    mark = static_cast<int>(m_log.size());
    m_workspace->submit(ProjectOperation{DeletionPlanInput{*route101, constant}});
    QVERIFY2(waitFor(
                 [this, mark] {
                     return indexOf(m_log, mark, [](const Entry &entry) {
                                const auto *const event = std::get_if<ProjectEvent>(&entry);
                                return event && std::holds_alternative<DeletionPlanResult>(*event);
                            }) >= 0;
                 },
                 error),
             qPrintable(error));
    const auto *const deletionEvent = std::get_if<ProjectEvent>(&m_log[mark]);
    QVERIFY(deletionEvent);
    if (!deletionEvent)
        return;
    const auto *const deletion = std::get_if<DeletionPlanResult>(deletionEvent);
    QVERIFY(deletion);
    if (deletion)
        QVERIFY(deletion->song == *route101);
}

void ProjectWorkspaceTest::silentCompletionsAdvanceFifoWithoutPublication()
{
    QString error;
    QVERIFY2(openReady(error), qPrintable(error));
    const int mark = static_cast<int>(m_log.size());
    m_workspace->submit(ProjectOperation{CleanupPreviewInput{}});
    m_workspace->submit(ProjectOperation{CleanupPreviewInput{}});
    m_workspace->submit(ProjectOperation{ProbeSamplesInput{}});
    QVERIFY2(waitFor([this, mark] { return static_cast<int>(m_log.size()) > mark; }, error),
             qPrintable(error));
    QCOMPARE(static_cast<int>(m_log.size()), mark + 1);
    const auto *const event = std::get_if<ProjectEvent>(&m_log[mark]);
    QVERIFY(event);
    if (event)
        QVERIFY(std::holds_alternative<SamplesProbed>(*event));
}

void ProjectWorkspaceTest::reloadStagesMidiViewBound()
{
    QString error;
    QVERIFY2(openReady(error), qPrintable(error));
    const std::optional<SongName> route101 = SongName::create(QStringLiteral("mus_route101"));
    QVERIFY(route101);
    if (!route101)
        return;

    const int mark = static_cast<int>(m_log.size());
    m_workspace->submit(ProjectOperation{OpenSongInput{*route101}});
    QVERIFY2(waitFor([this, mark] { return static_cast<int>(m_log.size()) >= mark + 3; }, error),
             qPrintable(error));
    QCOMPARE(static_cast<int>(m_log.size()), mark + 3);
    const auto *const midi = std::get_if<SongUpdate>(&m_log[mark]);
    const auto *const viewEvent = std::get_if<ProjectEvent>(&m_log[mark + 1]);
    const auto *const bound = std::get_if<SongUpdate>(&m_log[mark + 2]);
    QVERIFY(midi);
    QVERIFY(viewEvent);
    QVERIFY(bound);
    if (midi) {
        QVERIFY(std::holds_alternative<MidiStage>(midi->payload));
        QVERIFY(midi->song == *route101);
    }
    if (viewEvent)
        QVERIFY(std::holds_alternative<LoadedBankView>(*viewEvent));
    if (bound) {
        QVERIFY(std::holds_alternative<VoicegroupBound>(bound->payload));
        QVERIFY(bound->song == *route101);
    }
}

void ProjectWorkspaceTest::editConflict_appliedReceipt_hardFailure_data()
{
    QTest::addColumn<int>("editCase");
    QTest::newRow("expected-blank-conflict") << static_cast<int>(EditCase::Conflict);
    QTest::newRow("scalar-edit-view-and-receipt") << static_cast<int>(EditCase::Applied);
    QTest::newRow("unknown-voicegroup-hard-failure") << static_cast<int>(EditCase::HardFailure);
}

void ProjectWorkspaceTest::editConflict_appliedReceipt_hardFailure()
{
    QFETCH(int, editCase);
    QString error;
    QVERIFY2(openReady(error), qPrintable(error));
    const std::optional<SongName> route101 = SongName::create(QStringLiteral("mus_route101"));
    QVERIFY(route101);
    if (!route101)
        return;

    int mark = static_cast<int>(m_log.size());
    m_workspace->submit(ProjectOperation{OpenSongInput{*route101}});
    QVERIFY2(waitFor([this, mark] { return static_cast<int>(m_log.size()) >= mark + 3; }, error),
             qPrintable(error));
    QCOMPARE(static_cast<int>(m_log.size()), mark + 3);
    const auto *const viewEvent = std::get_if<ProjectEvent>(&m_log[mark + 1]);
    QVERIFY(viewEvent);
    if (!viewEvent)
        return;
    const auto *const view = std::get_if<LoadedBankView>(viewEvent);
    QVERIFY(view);
    if (!view)
        return;
    const int filled = firstFilledSlot(*view);
    QVERIFY(filled >= 0);
    if (filled < 0)
        return;

    // Do not retain a pointer into the publication deque after an async submit.
    const VoicegroupId bankId = view->id;
    const VgVoice voice = *view->slotViews[filled].voice;
    mark = static_cast<int>(m_log.size());

    switch (static_cast<EditCase>(editCase)) {
    case EditCase::Conflict:
        m_workspace->submit(ProjectOperation{
            VoicegroupEditInput{bankId, SetVoicegroupSlot{filled, voice, std::nullopt}}});
        QVERIFY2(waitFor(
                     [this, mark] {
                         return indexOf(m_log, mark, [](const Entry &entry) {
                                    const auto *const event = std::get_if<ProjectEvent>(&entry);
                                    return event &&
                                           std::holds_alternative<VoicegroupEditConflict>(*event);
                                }) >= 0;
                     },
                     error),
                 qPrintable(error));
        break;
    case EditCase::Applied: {
        VgVoice edited = voice;
        ++edited.key;
        m_workspace->submit(ProjectOperation{
            VoicegroupEditInput{bankId, SetVoicegroupSlot{filled, edited, voice}}});
        QVERIFY2(
            waitFor([this, mark] { return static_cast<int>(m_log.size()) >= mark + 2; }, error),
            qPrintable(error));
        QCOMPARE(static_cast<int>(m_log.size()), mark + 2);
        const auto *const appliedView = std::get_if<ProjectEvent>(&m_log[mark]);
        const auto *const receipt = std::get_if<ProjectEvent>(&m_log[mark + 1]);
        QVERIFY(appliedView);
        QVERIFY(receipt);
        if (appliedView)
            QVERIFY(std::holds_alternative<LoadedBankView>(*appliedView));
        if (receipt) {
            const auto *const applied = std::get_if<VoicegroupEditApplied>(receipt);
            QVERIFY(applied);
            if (applied)
                QVERIFY(applied->voicegroup == bankId);
        }
        break;
    }
    case EditCase::HardFailure: {
        const std::optional<VoicegroupId> ghost =
            VoicegroupId::create(QStringLiteral("sound/voicegroups/porydaw_ghost.inc"), QString{});
        QVERIFY(ghost);
        if (!ghost)
            return;
        m_workspace->submit(ProjectOperation{
            VoicegroupEditInput{*ghost, SetVoicegroupSlot{0, voice, std::nullopt}}});
        QVERIFY2(waitFor(
                     [this, mark, &ghost] {
                         return indexOf(m_log, mark, [&ghost](const Entry &entry) {
                                    const auto *const failure =
                                        mutationFailure<VoicegroupMutationFailed>(entry);
                                    return failure && failure->voicegroup == *ghost &&
                                           !failure->message.isEmpty();
                                }) >= 0;
                     },
                     error),
                 qPrintable(error));
        break;
    }
    }
}

} // namespace

int runProjectWorkspaceCheck(const QString &stagedRoot, const QStringList &qtArguments)
{
    ProjectWorkspaceTest test(stagedRoot);
    QStringList arguments{QStringLiteral("project-workspace")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "workspace.moc"
