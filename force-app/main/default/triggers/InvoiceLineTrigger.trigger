trigger InvoiceLineTrigger on InvoiceLine__c(
  before insert,
  before update,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    InvoiceFieldCopyTriggerHandler.handleInvoiceLineBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
    InvoiceCanonicalService.applyRecognitionBucketCount(Trigger.new, Trigger.oldMap);
    InvoiceCanonicalService.applyYenCommaTexts(Trigger.new);
    InvoiceCanonicalService.assertAcceptanceRules(Trigger.new, Trigger.oldMap);
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
