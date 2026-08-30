trigger EstimateNoteMasterTrigger on EstimateNoteMaster__c(
  after insert,
  after update,
  after delete
) {
  if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
    ContractMasterOperationLog.logNoteSave(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    ContractMasterOperationLog.logNoteDelete(Trigger.old);
  }
}
