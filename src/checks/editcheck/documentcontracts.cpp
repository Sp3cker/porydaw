#include "checks/editcheck/support.h"

namespace editcheck {

int documentContractFailures()
{
    auto failures = documentPublicationTempoVelocityRemapFailures();
    failures += documentTrackDuplicationOwnershipFailures();
    failures += documentTrackGlobalMetadataFailures();
    failures += documentMoveIdentityFailures();
    failures += documentMovePublicationFailures();
    return failures;
}

} // namespace editcheck
