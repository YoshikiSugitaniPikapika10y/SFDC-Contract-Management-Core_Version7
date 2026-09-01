public without sharing class InvoiceTriggerHandler {
  /** 仕様: Core 第7.11節 */
  public static void handleBeforeInsert(List<Invoice__c> newRecords) {
    InvoiceTransactionStatusService.rejectDirectStatusEdits(newRecords, null);
  }

  public static void handleBeforeUpdate(
    List<Invoice__c> newRecords,
    Map<Id, Invoice__c> oldMap
  ) {
    InvoiceTransactionStatusService.rejectDirectStatusEdits(newRecords, oldMap);
    InvoiceLockUtil.blockLockedRowDml(newRecords, oldMap);
  }

  public static void handleBeforeDelete(List<Invoice__c> oldRecords) {
    InvoiceLockUtil.blockLockedRowDml(oldRecords, null);
  }

  /** 仕様: Core 第3.3.3節、第5.7節 */
  public static void handleAfterInsert(List<Invoice__c> newRecords) {
    ContractHistoryStatusPathService.syncForInvoices(newRecords);
    BillingAccountKeyService.markHasReferenceTrue(
      collectBillingAccountIds(newRecords, null)
    );
    ContractIrregularOperationLog.logCreate(newRecords);
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
    Set<Id> billingAccountIds = new Set<Id>();
    for (Invoice__c invoice : newRecords) {
      if (invoice == null) {
        continue;
      }
      Invoice__c prior = oldMap == null ? null : oldMap.get(invoice.Id);
      if (
        prior == null ||
        invoice.BillingAccountSnapShot__c != prior.BillingAccountSnapShot__c
      ) {
        if (invoice.BillingAccountSnapShot__c != null) {
          billingAccountIds.add(invoice.BillingAccountSnapShot__c);
        }
        if (prior != null && prior.BillingAccountSnapShot__c != null) {
          billingAccountIds.add(prior.BillingAccountSnapShot__c);
        }
      }
    }
    if (!billingAccountIds.isEmpty()) {
      BillingAccountKeyService.refreshHasReference(billingAccountIds);
    }
    ContractIrregularOperationLog.logUpdate(newRecords);
  }

  public static void handleAfterDelete(List<Invoice__c> oldRecords) {
    ContractHistoryStatusPathService.syncForInvoices(oldRecords);
    BillingAccountKeyService.refreshHasReference(
      collectBillingAccountIds(oldRecords, null)
    );
    ContractIrregularOperationLog.logDelete(oldRecords);
  }

  public static void handleAfterUndelete(List<Invoice__c> newRecords) {
    ContractHistoryStatusPathService.syncForInvoices(newRecords);
    BillingAccountKeyService.markHasReferenceTrue(
      collectBillingAccountIds(newRecords, null)
    );
  }

  private static Set<Id> collectBillingAccountIds(
    List<Invoice__c> records,
    Map<Id, Invoice__c> oldMap
  ) {
    Set<Id> ids = new Set<Id>();
    if (records == null) {
      return ids;
    }
    for (Invoice__c record : records) {
      if (record != null && record.BillingAccountSnapShot__c != null) {
        ids.add(record.BillingAccountSnapShot__c);
      }
      if (oldMap != null && record != null) {
        Invoice__c prior = oldMap.get(record.Id);
        if (prior != null && prior.BillingAccountSnapShot__c != null) {
          ids.add(prior.BillingAccountSnapShot__c);
        }
      }
    }
    return ids;
  }
}
