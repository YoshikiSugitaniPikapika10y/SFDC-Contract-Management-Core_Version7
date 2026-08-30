trigger FieldCopyDefinitionTrigger on FieldCopyDefinition__c(
  before insert,
  before update,
  after insert,
  after update,
  after delete
) {
  if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
    FieldCopyDefinitionService.validateDefinitions(Trigger.new);
  }
  if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
    ContractMasterOperationLog.logFieldCopySave(Trigger.new);
  }
  if (Trigger.isAfter && Trigger.isDelete) {
    ContractMasterOperationLog.logFieldCopyDelete(Trigger.old);
  }
}
