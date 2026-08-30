trigger InvoicePaymentAllocationTrigger on InvoicePaymentAllocation__c(
  before insert,
  before update,
  after insert,
  after update,
  after delete
) {
  // 仕様: Core 第8.6節、Accounting 第4.4節
  if (Trigger.isBefore) {
    InvoicePaymentAllocationService.guardHistoricalAmounts(
      Trigger.new,
      Trigger.isUpdate ? Trigger.oldMap : null
    );
  }
  // 仕様: 共通基盤 第12章・第3.6節
  if (Trigger.isAfter && Trigger.isInsert) {
    ContractIrregularOperationLog.logCreate(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isUpdate) {
    ContractIrregularOperationLog.logUpdate(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    ContractIrregularOperationLog.logDelete(Trigger.old);
  }
}
