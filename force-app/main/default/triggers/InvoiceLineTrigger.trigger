trigger InvoiceLineTrigger on InvoiceLine__c(before insert) {
  if (Trigger.isBefore && Trigger.isInsert) {
    InvoiceFieldCopyTriggerHandler.handleInvoiceLineBeforeInsert(Trigger.new);
  }
}
