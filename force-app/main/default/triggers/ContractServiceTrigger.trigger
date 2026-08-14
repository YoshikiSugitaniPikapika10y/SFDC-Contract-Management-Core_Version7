trigger ContractServiceTrigger on ContractService__c (
  before insert,
  before update,
  before delete,
  after insert,
  after update
) {
  if (Trigger.isBefore && Trigger.isDelete) {
    ContractServiceTriggerHandler.handleBeforeDelete(Trigger.old);
    return;
  }
  if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
    RenewEstimateAutoCreateService.validateBeforeSave(
      Trigger.new,
      Trigger.oldMap
    );
    return;
  }
  if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
    RenewEstimateAutoCreateService.createRenewEstimates(
      Trigger.new,
      Trigger.oldMap
    );
  }
}
