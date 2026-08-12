/**
 * BillingAccount__c の共有マスタ更新ガード。
 * Ordered 実績がある請求アカウントを変更保存する場合、確認チェック必須。
 */
public without sharing class BillingAccountTriggerHandler {
  @TestVisible
  private static final String CONFIRM_FIELD = 'ConfirmSharedUpdate__c';

  @TestVisible
  private static final String ORDERED_USAGE_UPDATE_MESSAGE = '受注済み契約で使用中です。上書きすると今後の請求先が変わり、他契約にも影響します。同じ請求先として更新する場合は確認チェックを入れて再保存、契約ごとに分けたい場合は新規作成してください。';

  public static void handleBeforeUpdate(
    List<BillingAccount__c> newRecords,
    Map<Id, BillingAccount__c> oldMap
  ) {
    if (newRecords == null || newRecords.isEmpty() || oldMap == null) {
      return;
    }
    if (ContractPermissionUtil.canBypassIntegrityGuards()) {
      for (BillingAccount__c billingAccount : newRecords) {
        if (billingAccount.ConfirmSharedUpdate__c == true) {
          billingAccount.ConfirmSharedUpdate__c = false;
        }
      }
      return;
    }

    Set<Id> candidateIds = new Set<Id>();
    for (BillingAccount__c billingAccount : newRecords) {
      BillingAccount__c oldBillingAccount = oldMap.get(billingAccount.Id);
      if (oldBillingAccount == null) {
        continue;
      }
      if (hasNonConfirmFieldChanges(oldBillingAccount, billingAccount)) {
        candidateIds.add(billingAccount.Id);
      } else if (billingAccount.ConfirmSharedUpdate__c == true) {
        billingAccount.ConfirmSharedUpdate__c = false;
      }
    }
    if (candidateIds.isEmpty()) {
      return;
    }

    Set<Id> usedInOrderedIds = queryBillingAccountIdsUsedInOrdered(
      candidateIds
    );
    for (BillingAccount__c billingAccount : newRecords) {
      if (!candidateIds.contains(billingAccount.Id)) {
        continue;
      }
      if (!usedInOrderedIds.contains(billingAccount.Id)) {
        if (billingAccount.ConfirmSharedUpdate__c == true) {
          billingAccount.ConfirmSharedUpdate__c = false;
        }
        continue;
      }
      if (billingAccount.ConfirmSharedUpdate__c != true) {
        billingAccount.addError(ORDERED_USAGE_UPDATE_MESSAGE);
        continue;
      }
      billingAccount.ConfirmSharedUpdate__c = false;
    }
  }

  @TestVisible
  private static Boolean hasNonConfirmFieldChanges(
    BillingAccount__c oldBillingAccount,
    BillingAccount__c newBillingAccount
  ) {
    Map<String, Schema.SObjectField> fieldMap = BillingAccount__c.SObjectType.getDescribe()
      .fields.getMap();
    for (String fieldApiName : fieldMap.keySet()) {
      if (fieldApiName == CONFIRM_FIELD) {
        continue;
      }
      Schema.DescribeFieldResult describe = fieldMap.get(fieldApiName)
        .getDescribe();
      if (!describe.isUpdateable()) {
        continue;
      }
      Object oldValue = oldBillingAccount.get(fieldApiName);
      Object newValue = newBillingAccount.get(fieldApiName);
      if (oldValue != newValue) {
        return true;
      }
    }
    return false;
  }

  @TestVisible
  private static Set<Id> queryBillingAccountIdsUsedInOrdered(
    Set<Id> billingAccountIds
  ) {
    Set<Id> usedIds = new Set<Id>();
    if (billingAccountIds == null || billingAccountIds.isEmpty()) {
      return usedIds;
    }

    for (ContractHistory__c history : [
      SELECT ContractService__r.BiilingAcccount__c
      FROM ContractHistory__c
      WHERE
        historystatus__c = :ContractDomainConstants.HISTORY_STATUS_ORDERED
        AND ContractService__r.BiilingAcccount__c IN :billingAccountIds
      WITH SYSTEM_MODE
    ]) {
      Id billingAccountId = history.ContractService__r.BiilingAcccount__c;
      if (billingAccountId != null) {
        usedIds.add(billingAccountId);
      }
    }
    return usedIds;
  }
}
