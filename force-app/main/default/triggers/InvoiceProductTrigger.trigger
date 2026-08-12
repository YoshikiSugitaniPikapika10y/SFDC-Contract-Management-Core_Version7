trigger InvoiceProductTrigger on InvoiceProduct__c(
  before insert
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    InvoiceFieldCopyTriggerHandler.handlePeriodLineBeforeInsert(Trigger.new);
  }
}
