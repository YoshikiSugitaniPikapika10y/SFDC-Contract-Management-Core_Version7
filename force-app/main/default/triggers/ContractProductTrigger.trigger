trigger ContractProductTrigger on ContractProduct__c (before insert, before update, after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        ContractProductTriggerHandler.handleBeforeInsertOrUpdate(Trigger.new);
    }

    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        ContractProductTriggerHandler.handleAfterChange(
            Trigger.new,
            Trigger.isUpdate ? Trigger.oldMap : null
        );
        if (Trigger.isInsert) {
            ContractIrregularOperationLog.logCreate(Trigger.new);
        } else {
            ContractIrregularOperationLog.logUpdate(Trigger.new);
        }
    }

    if (Trigger.isAfter && Trigger.isDelete) {
        ContractProductTriggerHandler.handleAfterDelete(Trigger.old);
        ContractIrregularOperationLog.logDelete(Trigger.old);
    }

    if (Trigger.isAfter && Trigger.isUndelete) {
        ContractProductTriggerHandler.handleAfterChange(Trigger.new, null);
    }
}