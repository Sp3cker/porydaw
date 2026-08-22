#pragma once

// The AutomationGestureCheck callback alias and the Check wrapper live in
// support.h (private to this suite) to keep one definition for every domain.
#include "support.h"

class AutomationGestureCheckRig;

void checkAutomationPencilAction(AutomationGestureCheckRig &rig,
                                 const AutomationGestureCheck &check);
void checkAutomationPencilCursor(AutomationGestureCheckRig &rig,
                                 const AutomationGestureCheck &check);
void checkAutomationPencilMapping(AutomationGestureCheckRig &rig,
                                  const AutomationGestureCheck &check);
void checkAutomationPencilStroke(AutomationGestureCheckRig &rig,
                                 const AutomationGestureCheck &check);
void checkAutomationPencilOwnership(AutomationGestureCheckRig &rig,
                                    const AutomationGestureCheck &check);
void checkAutomationPencilTransactions(AutomationGestureCheckRig &rig,
                                       const AutomationGestureCheck &check);
void checkNodeLaneParity(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check);
void checkNodeContract(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check);
void checkNodeLaneHoverParity(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check);
void checkAutomationLifecycle(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check);
