trigger InvoiceTrigger on Invoice__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete,
  after undelete
) {
  if (Trigger.isBefore) {
    if (Trigger.isInsert) {
      InvoiceTriggerHandler.handleBeforeInsert(Trigger.new);
      InvoiceFieldCopyTriggerHandler.handleInvoiceBeforeInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
      InvoiceTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isDelete) {
      InvoiceTriggerHandler.handleBeforeDelete(Trigger.old);
    }
  }

  if (Trigger.isAfter) {
    if (Trigger.isInsert) {
      InvoiceTriggerHandler.handleAfterInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
      InvoiceTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isDelete) {
      InvoiceTriggerHandler.handleAfterDelete(Trigger.old);
    } else if (Trigger.isUndelete) {
      InvoiceTriggerHandler.handleAfterUndelete(Trigger.new);
    }
  }
}
