#include "project/banklease.h"
#include "project/swift_project_service.h"

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
