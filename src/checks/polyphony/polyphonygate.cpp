#include "checks/polyphony/tst_polyphonycheck.h"

#include <QCoreApplication>
#include <QDockWidget>
#include <QtTest>

#include <utility>

#include "mainwindow.h"
#include "ui/polyphonypanel.h"

namespace checks {

PolyphonyGateTest::PolyphonyGateTest(QString screenshotPath)
    : m_screenshotPath(std::move(screenshotPath))
{}

PolyphonyGateTest::~PolyphonyGateTest() = default;

bool PolyphonyGateTest::prepareGateWindow()
{
    m_window = std::make_unique<MainWindow>();
    if (!m_window->m_audioOk)
        return false;
    m_window->show();
    QCoreApplication::processEvents();
    return m_window->isVisible();
}

void PolyphonyGateTest::cleanup()
{
    if (!m_window)
        return;
    m_window->m_polyPanel->setInvertChecked(false);
    m_window->m_polyDock->hide();
    QCoreApplication::processEvents();
    m_window->close();
    m_window.reset();
}

void PolyphonyGateTest::hiddenDockCheckboxIsInert()
{
    QVERIFY2(prepareGateWindow(), "polyphony gate requires a real initialized audio device");
    QVERIFY(!m_window->m_polyDock->isVisible());
    QVERIFY(!m_window->m_audio.polyDebugInvert());
    m_window->m_polyPanel->setInvertChecked(true);
    QVERIFY(!m_window->m_audio.polyDebugInvert());
}

void PolyphonyGateTest::visibleCheckedDockInverts()
{
    QVERIFY2(prepareGateWindow(), "polyphony gate requires a real initialized audio device");
    m_window->m_polyPanel->setInvertChecked(true);
    m_window->m_polyDock->show();
    QCoreApplication::processEvents();
    QVERIFY(m_window->m_polyDock->isVisible());
    QVERIFY(m_window->m_audio.polyDebugInvert());
}

void PolyphonyGateTest::closingDockSuspendsAndReopenResumes()
{
    QVERIFY2(prepareGateWindow(), "polyphony gate requires a real initialized audio device");
    m_window->m_polyPanel->setInvertChecked(true);
    m_window->m_polyDock->show();
    QCoreApplication::processEvents();
    QVERIFY(m_window->m_audio.polyDebugInvert());

    m_window->m_polyDock->close();
    QCoreApplication::processEvents();
    QVERIFY(!m_window->m_audio.polyDebugInvert());
    QVERIFY(m_window->m_polyPanel->invertChecked());

    m_window->m_polyDock->show();
    QCoreApplication::processEvents();
    QVERIFY(m_window->m_audio.polyDebugInvert());
}

void PolyphonyGateTest::uncheckingDockTurnsInvertOff()
{
    QVERIFY2(prepareGateWindow(), "polyphony gate requires a real initialized audio device");
    m_window->m_polyPanel->setInvertChecked(true);
    m_window->m_polyDock->show();
    QCoreApplication::processEvents();
    QVERIFY(m_window->m_audio.polyDebugInvert());
    m_window->m_polyPanel->setInvertChecked(false);
    QVERIFY(!m_window->m_audio.polyDebugInvert());
}

} // namespace checks

int runPolyCheck(const QString &screenshotPath, const QStringList &qtArguments)
{
    checks::PolyphonyGateTest test(screenshotPath);
    QStringList arguments{QStringLiteral("polycheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
