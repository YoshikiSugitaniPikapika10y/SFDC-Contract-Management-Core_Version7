trigger BillingAccountTrigger on BillingAccount__c(
  before insert,
  before update,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    BillingAccountTriggerHandler.handleBeforeInsert(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    BillingAccountTriggerHandler.handleBeforeUpdate(
      Trigger.new,
      Trigger.oldMap
    );
  }
  if (Trigger.isAfter && Trigger.isInsert) {
    BillingAccountTriggerHandler.handleAfterInsert(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isUpdate) {
    BillingAccountTriggerHandler.handleAfterUpdate(
      Trigger.new,
      Trigger.oldMap
    );
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    BillingAccountTriggerHandler.handleAfterDelete(Trigger.old);
  }
}
