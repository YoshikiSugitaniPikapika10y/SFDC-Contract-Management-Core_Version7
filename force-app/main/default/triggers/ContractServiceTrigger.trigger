trigger ContractServiceTrigger on ContractService__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && Trigger.isInsert) {
    ContractServiceWriteGuard.assertAllowedWrite(Trigger.new, null);
  }
  if (Trigger.isBefore && Trigger.isUpdate) {
    ContractServiceWriteGuard.assertAllowedWrite(Trigger.new, Trigger.oldMap);
  }
  if (Trigger.isBefore && Trigger.isDelete) {
    ContractServiceWriteGuard.assertNoDelete(Trigger.old);
    ContractServiceTriggerHandler.handleBeforeDelete(Trigger.old);
  }
  if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
    BillingAccountKeyService.refreshHasReference(
      ContractServiceTriggerHandler.collectBillingAccountIds(
        Trigger.new,
        Trigger.oldMap
      )
    );
    if (Trigger.isInsert) {
      ContractIrregularOperationLog.logCreate(Trigger.new);
    } else {
      ContractIrregularOperationLog.logUpdate(Trigger.new);
    }
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    BillingAccountKeyService.refreshHasReference(
      ContractServiceTriggerHandler.collectBillingAccountIds(Trigger.old, null)
    );
    ContractIrregularOperationLog.logDelete(Trigger.old);
  }
}
