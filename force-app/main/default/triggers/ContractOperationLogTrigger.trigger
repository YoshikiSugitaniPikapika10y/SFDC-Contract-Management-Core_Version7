trigger ContractOperationLogTrigger on ContractOperationLog__c(
  before insert,
  before update,
  before delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    ContractOperationLogTriggerHandler.assertInsertAllowed(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    ContractOperationLogTriggerHandler.rejectMutation(Trigger.new);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    ContractOperationLogTriggerHandler.assertDeleteAllowed(Trigger.old);
  }
}
