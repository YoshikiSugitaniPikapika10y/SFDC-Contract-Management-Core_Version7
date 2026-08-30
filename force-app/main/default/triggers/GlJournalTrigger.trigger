trigger GlJournalTrigger on GlJournal__c(
  before update,
  before delete,
  after insert,
  after delete
) {
  if (Trigger.isBefore && Trigger.isUpdate) {
    GlJournalTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    GlJournalTriggerHandler.beforeDelete(Trigger.old);
  }
  if (Trigger.isAfter && Trigger.isInsert) {
    ContractIrregularOperationLog.logCreate(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    ContractIrregularOperationLog.logDelete(Trigger.old);
  }
}
