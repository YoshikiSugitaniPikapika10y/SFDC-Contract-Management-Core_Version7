trigger ContractServiceTrigger on ContractService__c (before delete) {
    if (Trigger.isBefore && Trigger.isDelete) {
        ContractServiceTriggerHandler.handleBeforeDelete(Trigger.old);
    }
}
