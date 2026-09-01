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

  /**
   * 請求の連続 DML 中は参照あり再計算を保留し、終了時に1回だけ流す。
   * トリガごとの契約サービス／請求再クエリを抑えて SOQL 101 を防ぐ。
   */
  private static Integer referenceRefreshDeferDepth = 0;
  private static Set<Id> deferredReferenceRefreshIds = new Set<Id>();
  private static Set<Id> markedHasReferenceTrueIds = new Set<Id>();

  public static void beginReferenceRefreshDefer() {
    referenceRefreshDeferDepth++;
  }

  public static void endReferenceRefreshDefer() {
    if (referenceRefreshDeferDepth > 0) {
      referenceRefreshDeferDepth--;
    }
    if (referenceRefreshDeferDepth == 0 && !deferredReferenceRefreshIds.isEmpty()) {
      Set<Id> pending = deferredReferenceRefreshIds;
      deferredReferenceRefreshIds = new Set<Id>();
      refreshHasReferenceNow(pending);
    }
  }

  /**
   * 仕様: Core 第3.3.3節。参照の増加は ON にするだけで、全件再走査しない。
   */
  public static void markHasReferenceTrue(Set<Id> billingAccountIds) {
    if (billingAccountIds == null || billingAccountIds.isEmpty()) {
      return;
    }
    if (referenceRefreshDeferDepth > 0) {
      deferredReferenceRefreshIds.addAll(billingAccountIds);
      return;
    }
    List<BillingAccount__c> updates = new List<BillingAccount__c>();
    for (Id accountId : billingAccountIds) {
      if (accountId == null || markedHasReferenceTrueIds.contains(accountId)) {
        continue;
      }
      markedHasReferenceTrueIds.add(accountId);
      updates.add(
        new BillingAccount__c(Id = accountId, HasReference__c = true)
      );
    }
    writeHasReference(updates);
  }

  /** 仕様: Core 第3.3.3節 */
  public static void refreshHasReference(Set<Id> billingAccountIds) {
    if (billingAccountIds == null || billingAccountIds.isEmpty()) {
      return;
    }
    if (referenceRefreshDeferDepth > 0) {
      deferredReferenceRefreshIds.addAll(billingAccountIds);
      return;
    }
    refreshHasReferenceNow(billingAccountIds);
  }

  private static void refreshHasReferenceNow(Set<Id> billingAccountIds) {
    Set<Id> referenced = new Set<Id>();
    for (AggregateResult row : [
      SELECT BiilingAcccount__c accountId
      FROM ContractService__c
      WHERE BiilingAcccount__c IN :billingAccountIds
      WITH SYSTEM_MODE
      GROUP BY BiilingAcccount__c
    ]) {
      Id accountId = (Id) row.get('accountId');
      if (accountId != null) {
        referenced.add(accountId);
      }
    }
    for (AggregateResult row : [
      SELECT BillingAccountSnapShot__c accountId
      FROM Invoice__c
      WHERE BillingAccountSnapShot__c IN :billingAccountIds
      WITH SYSTEM_MODE
      GROUP BY BillingAccountSnapShot__c
    ]) {
      Id accountId = (Id) row.get('accountId');
      if (accountId != null) {
        referenced.add(accountId);
      }
    }
    List<BillingAccount__c> updates = new List<BillingAccount__c>();
    for (Id accountId : billingAccountIds) {
      if (accountId == null) {
        continue;
      }
      Boolean hasReference = referenced.contains(accountId);
      if (hasReference) {
        markedHasReferenceTrueIds.add(accountId);
      } else {
        markedHasReferenceTrueIds.remove(accountId);
      }
      updates.add(
        new BillingAccount__c(
          Id = accountId,
          HasReference__c = hasReference
        )
      );
    }
    writeHasReference(updates);
  }

  private static void writeHasReference(List<BillingAccount__c> updates) {
    if (updates == null || updates.isEmpty()) {
      return;
    }
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
