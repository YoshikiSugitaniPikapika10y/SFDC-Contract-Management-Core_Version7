trigger GlConditionRuleTrigger on GlConditionRule__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && Trigger.isDelete) {
    GlConditionRuleTriggerHandler.beforeDelete(Trigger.old);
  } else if (Trigger.isBefore) {
    GlConditionRuleTriggerHandler.beforeInsertUpdate(Trigger.new);
  }
  if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
    ContractMasterOperationLog.logSave(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    ContractMasterOperationLog.logDelete(Trigger.old);
  }
}
