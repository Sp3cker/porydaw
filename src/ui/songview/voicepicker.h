#pragma once

#include <QDialog>
#include <functional>

class QEvent;
class QListWidget;
class QListWidgetItem;
class QObject;
class SongView;
class QString;

namespace songview {

class VoicePickerDialog : public QDialog
{
  private:
    struct Geometry {
        int width;
        int height;

        static Geometry resolve();
    };

  public:
    VoicePickerDialog(SongView *sv, const QString &title, int initialVoice,
                      std::function<void(int, int)> audition);
    ~VoicePickerDialog() override;

    int selectedVoice() const;

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    void releaseVoice();

    Geometry m_geometry;
    QListWidget *m_list;
    std::function<void(int, int)> m_audition;
    int m_sounding = -1;
};

} // namespace songview
