#include "project/banklease.h"
#include <cstring>

struct PdBankLease {
    VoicegroupId id;
    VoicegroupLease lease;
    QString loadName;
};

PdBankLease *pd_bank_lease_box(const VoicegroupId &id, VoicegroupLease lease,
                               const QString &loadName)
{
    return new PdBankLease{id, std::move(lease), loadName};
}
PdBankLease *pd_bank_lease_adopt(const PdAdoptedBank *adopted)
{
    if (!adopted || !adopted->bank || (adopted->retained && !adopted->releaseRetained))
        return nullptr;
    const auto id = VoicegroupId::create(
        QString::fromUtf8(adopted->sourceRelativePath ? adopted->sourceRelativePath : ""),
        QString::fromUtf8(adopted->sectionLabel ? adopted->sectionLabel : ""));
    if (!id)
        return nullptr;

    // Swift's BankHandle owns the loader bank and its minted storage. The
    // retained handle lives until the last adopted box drops its alias; only
    // the handle's deinit calls voicegroup_free, never a C++ lease deleter.
    VoicegroupLease lease =
        adopted->retained
            ? wrapVoicegroupBorrow(
                  adopted->bank, std::shared_ptr<void>(adopted->retained, adopted->releaseRetained))
            : borrowVoicegroupLease(adopted->bank);
    return pd_bank_lease_box(*id, std::move(lease),
                             QString::fromUtf8(adopted->loadName ? adopted->loadName : ""));
}

void pd_bank_lease_release(PdBankLease *lease)
{
    delete lease;
}

uintptr_t pd_bank_lease_bank_token(const PdBankLease *lease)
{
    if (!lease || !lease->lease)
        return 0;
    return reinterpret_cast<uintptr_t>(lease->lease.get());
}

const VoicegroupLease &pd_bank_lease_native(const PdBankLease *lease)
{
    return lease->lease;
}

const VoicegroupId &pd_bank_lease_identity(const PdBankLease *lease)
{
    return lease->id;
}

bool pd_fileio_read_batch(void *user, const char *const *paths, size_t count,
                          VoicegroupFileBlob *out, char *error, size_t errorCapacity)
{
    const auto *handler = static_cast<const PdFileIoHandler *>(user);
    if (!handler || !handler->readBatch) {
        if (error && errorCapacity > 0) {
            static constexpr char kMessage[] = "Invalid voicegroup file-I/O handler.";
            const size_t length = std::char_traits<char>::length(kMessage);
            const size_t copy = length < errorCapacity - 1 ? length : errorCapacity - 1;
            std::memcpy(error, kMessage, copy);
            error[copy] = '\0';
        }
        return false;
    }
    return handler->readBatch(handler->context, paths, count, out, error, errorCapacity);
}

void pd_fileio_release_batch(void *user, VoicegroupFileBlob *blobs, size_t count)
{
    const auto *handler = static_cast<const PdFileIoHandler *>(user);
    if (!handler || !handler->releaseBatch)
        return;
    handler->releaseBatch(handler->context, blobs, count);
}
