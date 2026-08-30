/**
 * 請求アカウントキーの確定と参照ありの更新。
 */
public without sharing class BillingAccountKeyService {
  public static final String KEY_CHANGE_MESSAGE = '請求アカウントキーは作成後に変更できません。';
  public static final String HAS_REFERENCE_CHANGE_MESSAGE = '参照ありは利用者が変更できません。';

  @TestVisible
  static Boolean allowHasReferenceWrite;

  /** 仕様: Core 第3.3.1節 */
  public static void assignOnInsert(List<BillingAccount__c> accounts) {
    if (accounts == null || accounts.isEmpty()) {
      return;
    }
    for (BillingAccount__c account : accounts) {
      if (account == null) {
        continue;
      }
      if (String.isNotBlank(account.BillingAccountKey__c)) {
        account.BillingAccountKey__c = account.BillingAccountKey__c.trim();
      }
    }
  }

  /** 仕様: Core 第3.3.1節。Id採番後に空キーへ18桁Idを入れる。 */
  public static void fillBlankKeys(List<BillingAccount__c> accounts) {
    if (accounts == null || accounts.isEmpty()) {
      return;
    }
    List<BillingAccount__c> toUpdate = new List<BillingAccount__c>();
    for (BillingAccount__c account : accounts) {
      if (account == null || account.Id == null) {
        continue;
      }
      if (String.isBlank(account.BillingAccountKey__c)) {
        toUpdate.add(
          new BillingAccount__c(
            Id = account.Id,
            BillingAccountKey__c = String.valueOf(account.Id)
          )
        );
      }
    }
    if (!toUpdate.isEmpty()) {
      Boolean previousSkip = ContractOperationLogService.skipMasterWrites;
      ContractOperationLogService.skipMasterWrites = true;
      try {
        SystemContextAccess.updateRecords(toUpdate);
      } finally {
        ContractOperationLogService.skipMasterWrites = previousSkip;
      }
    }
  }

  /** 仕様: Core 第3.3.1節 */
  public static void rejectKeyChange(
    List<BillingAccount__c> newRecords,
    Map<Id, BillingAccount__c> oldMap
  ) {
    if (newRecords == null || oldMap == null) {
      return;
    }
    for (BillingAccount__c account : newRecords) {
      BillingAccount__c prior = oldMap.get(account.Id);
      if (prior == null) {
        continue;
      }
      if (account.isSet(BillingAccount__c.BillingAccountKey__c)) {
        String nextKey = String.isBlank(account.BillingAccountKey__c)
          ? null
          : account.BillingAccountKey__c.trim();
        String priorKey = String.isBlank(prior.BillingAccountKey__c)
          ? null
          : prior.BillingAccountKey__c.trim();
        if (priorKey != null && priorKey != nextKey) {
          account.addError(KEY_CHANGE_MESSAGE);
        }
        if (String.isNotBlank(account.BillingAccountKey__c)) {
          account.BillingAccountKey__c = account.BillingAccountKey__c.trim();
        }
      }
      if (
        account.isSet(BillingAccount__c.HasReference__c) &&
        allowHasReferenceWrite != true &&
        prior.HasReference__c != account.HasReference__c
      ) {
        account.addError(HAS_REFERENCE_CHANGE_MESSAGE);
      }
    }
  }

  /** 仕様: Core 第3.3.3節 */
  public static void refreshHasReference(Set<Id> billingAccountIds) {
    if (billingAccountIds == null || billingAccountIds.isEmpty()) {
      return;
    }
    Set<Id> referenced = new Set<Id>();
    for (ContractService__c service : [
      SELECT BiilingAcccount__c
      FROM ContractService__c
      WHERE BiilingAcccount__c IN :billingAccountIds
      WITH SYSTEM_MODE
    ]) {
      if (service.BiilingAcccount__c != null) {
        referenced.add(service.BiilingAcccount__c);
      }
    }
    for (Invoice__c invoice : [
      SELECT BillingAccountSnapShot__c
      FROM Invoice__c
      WHERE BillingAccountSnapShot__c IN :billingAccountIds
      WITH SYSTEM_MODE
    ]) {
      if (invoice.BillingAccountSnapShot__c != null) {
        referenced.add(invoice.BillingAccountSnapShot__c);
      }
    }
    List<BillingAccount__c> updates = new List<BillingAccount__c>();
    for (Id accountId : billingAccountIds) {
      updates.add(
        new BillingAccount__c(
          Id = accountId,
          HasReference__c = referenced.contains(accountId)
        )
      );
    }
    if (!updates.isEmpty()) {
      Boolean previous = allowHasReferenceWrite;
      Boolean previousSkip = ContractOperationLogService.skipMasterWrites;
      allowHasReferenceWrite = true;
      ContractOperationLogService.skipMasterWrites = true;
      try {
        SystemContextAccess.updateRecords(updates);
      } finally {
        allowHasReferenceWrite = previous;
        ContractOperationLogService.skipMasterWrites = previousSkip;
      }
    }
  }
}
