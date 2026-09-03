#pragma once

#include <QWidget>

class QLineEdit;
class QPlainTextEdit;

namespace scripting {

class ScriptHost;

// View → Script Console (SPEC §6.1): every plugin's log lines and errors,
// plus a REPL line that evaluates against the host's console engine (the
// full porydaw API, no plugin). Up/Down recall the input history.
class ScriptConsole : public QWidget
{
    Q_OBJECT
  public:
    explicit ScriptConsole(ScriptHost &host, QWidget *parent = nullptr);

    QPlainTextEdit *output() const { return m_output; }
    QLineEdit *input() const { return m_input; }
    void clear();

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    void append(const QString &pluginId, int level, const QString &text);
    void submit();

    ScriptHost &m_host;
    QPlainTextEdit *m_output = nullptr;
    QLineEdit *m_input = nullptr;
    QStringList m_history;
    int m_historyIndex = 0;
};

} // namespace scripting
