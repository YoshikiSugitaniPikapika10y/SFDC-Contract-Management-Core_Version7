trigger GlAccountMapTrigger on GlAccountMap__c(
  before insert,
  before update,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
    GlConditionSetTriggerHandler.assertTenantSetsHaveRules(Trigger.new);
  }
  if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
    ContractMasterOperationLog.logSave(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    ContractMasterOperationLog.logDelete(Trigger.old);
  }
}
