trigger BillingAccountTrigger on BillingAccount__c(before update) {
  if (Trigger.isBefore && Trigger.isUpdate) {
    BillingAccountTriggerHandler.handleBeforeUpdate(
      Trigger.new,
      Trigger.oldMap
    );
  }
}
