trigger InvoicePaymentTrigger on InvoicePayment__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore) {
    if (Trigger.isInsert) {
      InvoicePaymentTriggerHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
      InvoicePaymentTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isDelete) {
      InvoicePaymentTriggerHandler.handleBeforeDelete(Trigger.old);
    }
  }

  if (Trigger.isAfter) {
    if (Trigger.isInsert) {
      InvoicePaymentTriggerHandler.handleAfterInsert(Trigger.new);
      ContractIrregularOperationLog.logCreate(Trigger.new);
    } else if (Trigger.isUpdate) {
      InvoicePaymentTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
      ContractIrregularOperationLog.logUpdate(Trigger.new);
    } else if (Trigger.isDelete) {
      InvoicePaymentTriggerHandler.handleAfterDelete(Trigger.old);
      ContractIrregularOperationLog.logDelete(Trigger.old);
    }
  }
}
