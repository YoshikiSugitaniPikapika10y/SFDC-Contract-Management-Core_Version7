trigger GlAccountTrigger on GlAccount__c(
  before delete,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && Trigger.isDelete) {
    GlAccountTriggerHandler.beforeDelete(Trigger.old);
  }
  if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
    ContractMasterOperationLog.logSave(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    ContractMasterOperationLog.logDelete(Trigger.old);
  }
}
