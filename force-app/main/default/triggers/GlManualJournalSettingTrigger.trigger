trigger GlManualJournalSettingTrigger on GlManualJournalSetting__c(
  before delete,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && Trigger.isDelete) {
    ManualJournalService.preventReferencedSettingDelete(Trigger.old);
  }
  if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
    ContractMasterOperationLog.logSave(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    ContractMasterOperationLog.logDelete(Trigger.old);
  }
}
