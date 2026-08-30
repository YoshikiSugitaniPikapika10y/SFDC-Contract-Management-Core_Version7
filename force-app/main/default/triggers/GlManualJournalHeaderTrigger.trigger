trigger GlManualJournalHeaderTrigger on GlManualJournalHeader__c(
  after insert,
  after update,
  after delete
) {
  // 仕様: 共通基盤 第12章・第3.6節
  if (Trigger.isInsert) {
    ContractIrregularOperationLog.logCreate(Trigger.new);
  }
  if (Trigger.isUpdate) {
    ContractIrregularOperationLog.logUpdate(Trigger.new);
  }
  if (Trigger.isDelete) {
    ContractIrregularOperationLog.logDelete(Trigger.old);
  }
}
