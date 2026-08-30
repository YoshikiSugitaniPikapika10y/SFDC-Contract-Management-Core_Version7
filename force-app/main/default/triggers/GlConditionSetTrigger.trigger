trigger GlConditionSetTrigger on GlConditionSet__c(
  before insert,
  before update,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    GlConditionSetTriggerHandler.beforeInsertUpdate(Trigger.new);
  } else if (Trigger.isBefore && Trigger.isUpdate) {
    GlConditionSetTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
    ContractMasterOperationLog.logSave(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    ContractMasterOperationLog.logDelete(Trigger.old);
  }
}
