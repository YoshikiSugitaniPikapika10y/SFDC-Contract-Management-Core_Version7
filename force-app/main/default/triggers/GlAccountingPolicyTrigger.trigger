trigger GlAccountingPolicyTrigger on GlAccountingPolicy__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    GlAccountingPolicyTriggerHandler.beforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    GlAccountingPolicyTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    GlAccountingPolicyTriggerHandler.beforeDelete(Trigger.old);
  }
  if (Trigger.isAfter && Trigger.isInsert) {
    ContractMasterOperationLog.logSave(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isUpdate) {
    GlAccountingPolicyTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    ContractMasterOperationLog.logDelete(Trigger.old);
  }
}
