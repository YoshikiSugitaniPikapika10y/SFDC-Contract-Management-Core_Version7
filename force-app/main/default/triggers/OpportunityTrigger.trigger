trigger OpportunityTrigger on Opportunity (before insert, before update, after insert, after update) {
    OpportunityTriggerHandler.handle(Trigger.new, Trigger.oldMap, Trigger.operationType);
}