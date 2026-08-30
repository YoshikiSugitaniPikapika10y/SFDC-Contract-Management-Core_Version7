trigger GlAccountingTagRuleTrigger on GlAccountingTagRule__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && Trigger.isDelete) {
    AccountingTagEvaluationService.preventEnabledDelete(Trigger.old);
  } else if (Trigger.isBefore) {
    AccountingTagEvaluationService.validateOnSave(Trigger.new);
  }
  if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
    ContractMasterOperationLog.logSave(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    ContractMasterOperationLog.logDelete(Trigger.old);
  }
}
