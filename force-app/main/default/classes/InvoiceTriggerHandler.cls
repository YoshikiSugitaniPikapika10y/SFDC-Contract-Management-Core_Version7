public without sharing class InvoiceTriggerHandler {
  public static void handleBeforeUpdate(
    List<Invoice__c> newRecords,
    Map<Id, Invoice__c> oldMap
  ) {
    InvoiceLockUtil.blockLockedRowDml(newRecords, oldMap);
  }

  public static void handleBeforeDelete(List<Invoice__c> oldRecords) {
    InvoiceLockUtil.blockLockedRowDml(oldRecords, null);
  }

  public static void handleAfterInsert(List<Invoice__c> newRecords) {
    ContractHistoryStatusPathService.syncForInvoices(newRecords);
  }

  public static void handleAfterUpdate(
    List<Invoice__c> newRecords,
    Map<Id, Invoice__c> oldMap
  ) {
    Set<Id> historyIds = new Set<Id>();
    for (Invoice__c invoice : newRecords) {
      if (invoice == null) {
        continue;
      }
      Invoice__c prior = oldMap == null ? null : oldMap.get(invoice.Id);
      if (
        prior == null ||
        invoice.ContractHistory__c != prior.ContractHistory__c ||
        invoice.SystemIntegrationDate__c != prior.SystemIntegrationDate__c ||
        invoice.PaymentClearingCompletedDate__c !=
        prior.PaymentClearingCompletedDate__c
      ) {
        if (invoice.ContractHistory__c != null) {
          historyIds.add(invoice.ContractHistory__c);
        }
        if (prior != null && prior.ContractHistory__c != null) {
          historyIds.add(prior.ContractHistory__c);
        }
      }
    }
    ContractHistoryStatusPathService.syncForInvoiceParents(historyIds);
  }

  public static void handleAfterDelete(List<Invoice__c> oldRecords) {
    ContractHistoryStatusPathService.syncForInvoices(oldRecords);
  }

  public static void handleAfterUndelete(List<Invoice__c> newRecords) {
    ContractHistoryStatusPathService.syncForInvoices(newRecords);
  }
}
