#pragma once

// C-ABI surface — parsed by the Swift Clang importer in C mode. Nothing
// C++-only may appear outside the __cplusplus guards.
#include "voicegroup_loader.h"

typedef struct PdBankLease PdBankLease;

// Swift-owned file-I/O handler record. VoicegroupFileIo.user points at one of
// these for the context's lifetime; Swift allocates, fills, and frees it.
// readBatch fans out inside Swift; releaseBatch frees every populated blob.
typedef struct PdFileIoHandler {
    void *context;
    bool (*readBatch)(void *context, const char *const *paths, size_t count,
                      VoicegroupFileBlob *out, char *error, size_t errorCapacity);
    void (*releaseBatch)(void *context, VoicegroupFileBlob *blobs, size_t count);
} PdFileIoHandler;

#ifdef __cplusplus
extern "C" {
#endif

// The single C trampoline pair for VoicegroupFileIo callbacks. Install as
// VoicegroupFileIo{user: handler, readBatch: pd_fileio_read_batch,
// releaseBatch: pd_fileio_release_batch}.
bool pd_fileio_read_batch(void *user, const char *const *paths, size_t count,
                          VoicegroupFileBlob *out, char *error, size_t errorCapacity);
void pd_fileio_release_batch(void *user, VoicegroupFileBlob *blobs, size_t count);

#ifdef __cplusplus
} // extern "C"
#endif

#ifdef __cplusplus

#include "projectidentity.h"

#include <QString>
#include <memory>
#include <utility>

class VoicegroupLease;

// Adopts one worker-owned bank exactly once; the last lease releases it with
// voicegroup_free.
VoicegroupLease wrapVoicegroupLease(LoadedVoiceGroup *raw);
VoicegroupLease wrapVoicegroupLease(LoadedVoiceGroup *raw, std::shared_ptr<void> retained);
// Releases a stale worker result without publishing it: the temporary lease
// adopts the bank, so no porydaw code frees a bank by hand.
void discardVoicegroup(LoadedVoiceGroup *raw);
// Borrows a bank porydaw does not own (check fixtures): never frees.
VoicegroupLease borrowVoicegroupLease(LoadedVoiceGroup *raw);

// A loaded bank owned through plain value semantics. poryaaaa hands out a
// mutable LoadedVoiceGroup* and frees it with voicegroup_free, but porydaw
// publishes banks as immutable, so the public surface is only the const
// borrow. AudioEngine alone may unwrap the legacy mutable borrow to feed
// poryaaaa entry points, which only read the bank.
class VoicegroupLease
{
  public:
    VoicegroupLease() = default;

    const LoadedVoiceGroup *get() const { return m_bank.get(); }
    const LoadedVoiceGroup *operator->() const { return m_bank.get(); }
    explicit operator bool() const { return m_bank != nullptr; }
    void reset() { m_bank.reset(); }

  private:
    friend class AudioEngine;
    friend VoicegroupLease wrapVoicegroupLease(LoadedVoiceGroup *raw);
    friend VoicegroupLease wrapVoicegroupLease(LoadedVoiceGroup *raw,
                                               std::shared_ptr<void> retained);
    friend void discardVoicegroup(LoadedVoiceGroup *raw);
    friend VoicegroupLease borrowVoicegroupLease(LoadedVoiceGroup *raw);

    // Legacy mutable borrow required by unchanged poryaaaa; porydaw never
    // writes through it.
    LoadedVoiceGroup *borrow() const { return m_bank.get(); }

    std::shared_ptr<LoadedVoiceGroup> m_bank;
};

inline VoicegroupLease wrapVoicegroupLease(LoadedVoiceGroup *raw)
{
    VoicegroupLease lease;
    if (raw)
        lease.m_bank.reset(raw, &voicegroup_free);
    return lease;
}

inline VoicegroupLease wrapVoicegroupLease(LoadedVoiceGroup *raw, std::shared_ptr<void> retained)
{
    VoicegroupLease lease;
    if (raw) {
        lease.m_bank = std::shared_ptr<LoadedVoiceGroup>(
            raw, [retained = std::move(retained)](LoadedVoiceGroup *bank) {
                (void)retained;
                voicegroup_free(bank);
            });
    }
    return lease;
}

inline void discardVoicegroup(LoadedVoiceGroup *raw)
{
    wrapVoicegroupLease(raw);
}

inline VoicegroupLease borrowVoicegroupLease(LoadedVoiceGroup *raw)
{
    VoicegroupLease lease;
    if (raw)
        lease.m_bank = std::shared_ptr<LoadedVoiceGroup>(std::shared_ptr<LoadedVoiceGroup>(), raw);
    return lease;
}

PdBankLease *pd_bank_lease_box(const VoicegroupId &id, VoicegroupLease lease,
                               const QString &loadName);
#endif
