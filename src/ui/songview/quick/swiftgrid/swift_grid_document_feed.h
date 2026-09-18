#pragma once

#include <QObject>

#include "document_feed.h"

class SongDocument;

// The document outlives this GUI-thread observer. Destroy the observer before
// releasing the Swift recipient so no callback can borrow a released context.
class SwiftGridDocumentFeed final : public QObject
{
  public:
    explicit SwiftGridDocumentFeed(const SongDocument &document);
    ~SwiftGridDocumentFeed() override;

    uint64_t documentId() const { return m_documentId; }
    SgdDelivery *delivery() { return &m_delivery; }
    void pushSnapshot();

  private:
    const SongDocument &m_document;
    const uint64_t m_documentId;
    SgdDelivery m_delivery{};
    QMetaObject::Connection m_documentChanged;
};
