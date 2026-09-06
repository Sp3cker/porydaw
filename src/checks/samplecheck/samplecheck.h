#pragma once

#include <QByteArray>
#include <QObject>
#include <QString>

namespace samplecheck {

class SampleProcessingTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SampleProcessingTest)

  public:
    explicit SampleProcessingTest(QString corpusRoot);

  private slots:
    void projectProbe();
    void projectSanitizeValidate();
    void projectInspect();
    void projectRegister();
    void projectDuplicate();
    void projectCrlf();
    void decodeWidths_data();
    void decodeWidths();
    void decodeStereoPolicy();
    void decodeAiff();
    void decodeRefusalBoundaries_data();
    void decodeRefusalBoundaries();
    void compressedContainers_data();
    void compressedContainers();
    void compressedRefusals();
    void optionalCorpus();

    void resamplePassband_data();
    void resamplePassband();
    void resampleAliasRejection_data();
    void resampleAliasRejection();
    void resampleDcGain();
    void resampleImpulseSymmetry();
    void resampleFrequencyAccuracy();
    void resampleIdentity();
    void quantizationVectors_data();
    void quantizationVectors();
    void quantizationU8Roundtrip();
    void quantizationDither();
    void markerMapping();
    void normalization_data();
    void normalization();
    void dspDeterminism();
    void parityCases_data();
    void parityCases();
    void parityLoopGeometry();
    void parityRiffPadding();
    void retuneVectors_data();
    void retuneVectors();

    void pitchMatrix_data();
    void pitchMatrix();
    void pitchNegativeCases();
    void loopAndCrossfade();
    void auditionSlotLifecycle();

    void pipelinePrefillCollision();
    void pipelinePreparedDefaults();
    void pipelineKeyOverride();
    void pipelineLoopToggle();
    void pipelineRateCommit_data();
    void pipelineRateCommit();
    void pipelineCropNormalize();

    void editorDrag();
    void editorPitchAdoption();
    void editorLoopPopulate();
    void editorLoopRefine();
    void editorCrossfade();
    void editorAuditionStrip();
    void editorUndo();
    void editorScroll();
    void editorSplitter();
    void editorCommit();
    void spaceAudition();

    void soundFontExtraction();
    void soundFontRefusals_data();
    void soundFontRefusals();
    void soundFontPicker();
    void engineLoop();
    void sidecarRoundtrip();
    void sidecarRerender();
    void sidecarTouchedSource();
    void sidecarFallback();
    void sampleUpdate();
    void sampleUpdateRefusals_data();
    void sampleUpdateRefusals();
    void sidecarEditDialog();
    void sidecarRemove();

  private:
    QString m_corpusRoot;
};

bool createWav2AgbProject(const QString &root);
QByteArray preparedSampleWav();
QByteArray hiResSampleWav();

} // namespace samplecheck
