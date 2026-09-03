#include "scriptconsole.h"

#include <QFontDatabase>
#include <QKeyEvent>
#include <QLineEdit>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QScrollBar>
#include <QTextCharFormat>
#include <QTextCursor>
#include <QVBoxLayout>

#include "scripthost.h"
#include "ui/layout.h"

namespace scripting {

namespace {
constexpr int kMaxLines = 2000;
constexpr int kMaxHistory = 100;
} // namespace

ScriptConsole::ScriptConsole(ScriptHost &host, QWidget *parent) : QWidget(parent), m_host(host)
{
    m_output = new QPlainTextEdit(this);
    m_output->setObjectName(QStringLiteral("scriptConsoleOutput"));
    m_output->setReadOnly(true);
    m_output->setMaximumBlockCount(kMaxLines);
    m_output->setFont(QFontDatabase::systemFont(QFontDatabase::FixedFont));
    m_output->setLineWrapMode(QPlainTextEdit::NoWrap);

    m_input = new QLineEdit(this);
    m_input->setObjectName(QStringLiteral("scriptConsoleInput"));
    m_input->setPlaceholderText(tr("JavaScript, e.g. porydaw.song.notes({track: 0}).length"));
    m_input->setFont(m_output->font());
    m_input->setClearButtonEnabled(true);
    m_input->installEventFilter(this);

    auto *layout = new QVBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(::layout::space(::layout::Space::One));
    layout->addWidget(m_output, 1);
    layout->addWidget(m_input);

    connect(m_input, &QLineEdit::returnPressed, this, &ScriptConsole::submit);
    connect(&m_host, &ScriptHost::message, this, &ScriptConsole::append);
}

void ScriptConsole::clear()
{
    m_output->clear();
}

void ScriptConsole::append(const QString &pluginId, int level, const QString &text)
{
    QTextCharFormat format;
    const QPalette pal = palette();
    if (level >= 2)
        format.setForeground(QColor(0xd0, 0x40, 0x40));
    else if (level == 1)
        format.setForeground(QColor(0xc0, 0x80, 0x20));
    else
        format.setForeground(pal.color(QPalette::Text));
    QTextCursor cursor(m_output->document());
    cursor.movePosition(QTextCursor::End);
    if (!m_output->document()->isEmpty())
        cursor.insertBlock();
    const QString prefix = pluginId.isEmpty() ? QString() : QStringLiteral("[%1] ").arg(pluginId);
    cursor.insertText(prefix + text, format);
    m_output->verticalScrollBar()->setValue(m_output->verticalScrollBar()->maximum());
}

void ScriptConsole::submit()
{
    const QString code = m_input->text().trimmed();
    if (code.isEmpty())
        return;
    m_input->clear();
    m_history.removeAll(code);
    m_history.append(code);
    while (m_history.size() > kMaxHistory)
        m_history.removeFirst();
    m_historyIndex = m_history.size();
    append(QString(), 0, QStringLiteral("> ") + code);
    const QString result = m_host.evalConsole(code);
    if (!result.isNull())
        append(QString(), 0, result);
}

bool ScriptConsole::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_input && event->type() == QEvent::KeyPress) {
        auto *key = static_cast<QKeyEvent *>(event);
        if (key->key() == Qt::Key_Up || key->key() == Qt::Key_Down) {
            if (m_history.isEmpty())
                return true;
            m_historyIndex += key->key() == Qt::Key_Up ? -1 : 1;
            m_historyIndex = std::clamp(m_historyIndex, 0, int(m_history.size()));
            m_input->setText(m_historyIndex < m_history.size() ? m_history.at(m_historyIndex)
                                                               : QString());
            return true;
        }
    }
    return QWidget::eventFilter(watched, event);
}

} // namespace scripting
