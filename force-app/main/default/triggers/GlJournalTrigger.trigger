trigger GlJournalTrigger on GlJournal__c(
  before update,
  before delete,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && Trigger.isUpdate) {
    GlJournalTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    GlJournalTriggerHandler.beforeDelete(Trigger.old);
  }
  if (Trigger.isAfter && Trigger.isInsert) {
    GlJournalTriggerHandler.afterChange(Trigger.new);
    ContractIrregularOperationLog.logCreate(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isUpdate) {
    GlJournalTriggerHandler.afterChange(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    GlJournalTriggerHandler.afterChange(Trigger.old);
    ContractIrregularOperationLog.logDelete(Trigger.old);
  }
}
