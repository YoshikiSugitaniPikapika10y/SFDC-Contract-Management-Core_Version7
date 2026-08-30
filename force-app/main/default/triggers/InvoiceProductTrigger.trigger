trigger InvoiceProductTrigger on InvoiceProduct__c(
  before insert,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    InvoiceFieldCopyTriggerHandler.handlePeriodLineBeforeInsert(Trigger.new);
  }
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
