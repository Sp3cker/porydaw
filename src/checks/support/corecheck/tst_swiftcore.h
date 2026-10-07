#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

class SwiftCoreTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SwiftCoreTest)

  public:
    SwiftCoreTest() = default;

  private slots:
    void midiCodec();
    void musicalSemantics();
    void playback();
    void audioController();
    void audioAudition();
    void resonance();
    void suppressionStartStop();
    void suppressionReplacement();
    void noteEdits();
    void documentHistory();
    void eventEdits();
    void xcmdEdits();
    void midiImport();
    void timeEdits();
    void projectSession();
    void bankHistory();
    void projectIdentity();
    void songModel();
    void midiCfg();
    void songsMk();
    void songCatalog();
    void synthCatalog();
    void voicegroupValues();
    void saveCore();
    void voicegroupEditing();
    void projectStoreChecks();
    void voicegroupContext();
    void voicegroupBankLogic();
    void projectStoreActor();
    void projectStoreOpen();
    void projectStoreReads();
    void projectStoreLoadBank();
    void projectStoreEdit();
    void projectStoreSave();
    void bankLeases();
    void exportChecks();
    void themeColor();
    void displayList();
    void sampleCheck();
    void sampleProcessing();
    void sampleStorage();
    void sampleEditor();
    void sampleRender();
    void sampleAnalysis();
    void samplePitch33();
    void samplePitch45();
    void samplePitch57();
    void samplePitch69();
    void samplePitch81();
    void samplePitch93();
    void voicegroupParity();
    void projectLayout();
    void keysplitTables();
    void bankOwnership();
    void voicegroupLocator();
};

int runSwiftCoreCheck(const QString &fixtureRoot, const QStringList &qtArguments);
