#pragma once

#include <functional>

#include <QString>

class AutomationGestureCheckRig;

using AutomationGestureCheck = std::function<void(bool, const QString &)>;

void checkAutomationPencilAction(AutomationGestureCheckRig &rig,
                                 const AutomationGestureCheck &check);
void checkAutomationPencilMapping(AutomationGestureCheckRig &rig,
                                  const AutomationGestureCheck &check);
void checkAutomationPencilStroke(AutomationGestureCheckRig &rig,
                                 const AutomationGestureCheck &check);
void checkAutomationPencilOwnership(AutomationGestureCheckRig &rig,
                                    const AutomationGestureCheck &check);
void checkAutomationPencilTransactions(AutomationGestureCheckRig &rig,
                                       const AutomationGestureCheck &check);
void checkTempoInteractions(AutomationGestureCheckRig &rig, const AutomationGestureCheck &check);
