/**
 * 契約サービスへ書いてよい経路以外を拒否する。
 */
public without sharing class ContractServiceWriteGuard {
  public static final String CREATE_BLOCK_MESSAGE = '契約サービスは新規見積の保存だけで作成できます。';
  public static final String UPDATE_BLOCK_MESSAGE = '契約サービスの直書きはできません。新規見積、契約サービスを編集、受注、差し戻しから更新してください。';
  public static final String DELETE_BLOCK_MESSAGE = '契約サービスは削除できません。';
  public static final String SYSTEM_FIELD_BLOCK_MESSAGE = '取引先、Lifecycle、First Ordered、Latest Ordered、契約期間状態は利用者が変更できません。';

  @TestVisible
  private static Boolean allowPackageWrite;

  @TestVisible
  static Boolean enforceInTest;

  public static void allowPackageWrite(Boolean allowed) {
    allowPackageWrite = allowed;
  }

  public static Boolean isPackageWriteAllowed() {
    return allowPackageWrite == true;
  }

  /** 仕様: Core 第3.4節・第3.4.2節、共通基盤 第3.6節。102 はシステム項目以外の更新。104 は全部操作。 */
  public static void assertAllowedWrite(
    List<ContractService__c> newRecords,
    Map<Id, ContractService__c> oldMap
  ) {
    if (newRecords == null) {
      return;
    }
    if (isPackageWriteAllowed() || bypassForTest()) {
      return;
    }
    if (ContractPermissionUtil.hasMigrateAll()) {
      return;
    }
    if (ContractPermissionUtil.hasFixContract() && oldMap != null) {
      for (ContractService__c service : newRecords) {
        if (service == null) {
          continue;
        }
        ContractService__c prior = oldMap.get(service.Id);
        if (prior != null && touchesSystemFields(prior, service)) {
          service.addError(SYSTEM_FIELD_BLOCK_MESSAGE);
        }
      }
      return;
    }
    for (ContractService__c service : newRecords) {
      if (service == null) {
        continue;
      }
      if (oldMap == null) {
        service.addError(CREATE_BLOCK_MESSAGE);
        continue;
      }
      ContractService__c prior = oldMap.get(service.Id);
      if (prior == null) {
        service.addError(CREATE_BLOCK_MESSAGE);
        continue;
      }
      if (touchesSystemFields(prior, service)) {
        service.addError(SYSTEM_FIELD_BLOCK_MESSAGE);
        continue;
      }
      service.addError(UPDATE_BLOCK_MESSAGE);
    }
  }

  /** 仕様: Core 第3.4節、共通基盤 第3.6節。削除は 101／103。 */
  public static void assertNoDelete(List<ContractService__c> oldRecords) {
    if (
      oldRecords == null ||
      isPackageWriteAllowed() ||
      bypassForTest() ||
      ContractPermissionUtil.hasDeleteRecords()
    ) {
      return;
    }
    for (ContractService__c service : oldRecords) {
      if (service != null) {
        service.addError(DELETE_BLOCK_MESSAGE);
      }
    }
  }

  private static Boolean bypassForTest() {
    return Test.isRunningTest() && enforceInTest != true;
  }

  /** 仕様: Core 第3.4節。取引先、Lifecycle、First Ordered、Latest Orderedは利用者が変更できない。 */
  private static Boolean touchesSystemFields(
    ContractService__c prior,
    ContractService__c current
  ) {
    return prior.Account__c != current.Account__c ||
      prior.Lifecycle__c != current.Lifecycle__c ||
      prior.FirstOrderedHistory__c != current.FirstOrderedHistory__c ||
      prior.LatestOrderedHistory__c != current.LatestOrderedHistory__c;
  }
}
