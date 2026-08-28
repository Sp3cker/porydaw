#pragma once

#include <QUndoCommand>
#include <QUndoStack>

#include <cstdint>
#include <memory>
#include <optional>
#include <variant>

#include "project/voicegroupsource.h"

class DocumentStateIdentity
{
  public:
    DocumentStateIdentity() = default;
    friend bool operator==(const DocumentStateIdentity &, const DocumentStateIdentity &) = default;

  private:
    friend class SongHistory;
    friend class SongDocument;
    explicit DocumentStateIdentity(uint64_t value) : m_value(value) {}
    uint64_t m_value = 0;
};

enum class HistoryKind { Document, SharedBank };

// One undo/redo step: a document entry crosses synchronously, a shared-bank
// entry yields the exact draft the worker must confirm.
struct DocumentHistoryApplied {};
using HistoryRequest = std::variant<DocumentHistoryApplied, VoicegroupEditInput>;

class SongHistory
{
  public:
    explicit SongHistory(QUndoStack &stack);

    bool canUndo() const;
    bool canRedo() const;
    DocumentStateIdentity currentDocumentIdentity() const;
    DocumentStateIdentity savedDocumentIdentity() const;
    void markDocumentSaved(DocumentStateIdentity identity);
    void sealBankMerge();
    HistoryRequest requestUndo();
    HistoryRequest requestRedo();
    void
    pushConfirmedBank(VoicegroupEditInput draft,
                      std::optional<VoicegroupSource::BlankSlotMaterialization> materialization);
    void crossConfirmedBankUndo(
        std::optional<VoicegroupSource::BlankSlotMaterialization> materialization);
    void crossConfirmedBankRedo(
        std::optional<VoicegroupSource::BlankSlotMaterialization> materialization);
    void resolveBankUndoConflict();
    void resolveBankRedoConflict();
    void pushDocument(std::unique_ptr<QUndoCommand> command);
    void clear();

  private:
    class Entry;

    uint64_t mintIdentity();
    Entry *entryAt(int index) const;

    QUndoStack &m_stack;
    uint64_t m_nextIdentity = 1;
    DocumentStateIdentity m_baseIdentity;
    DocumentStateIdentity m_savedIdentity;
};
