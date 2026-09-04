public without sharing class GlAccountingPolicyTriggerHandler {
  /** 仕様: Accounting 第3.1節、第5.7節 */
  public static void beforeInsert(List<GlAccountingPolicy__c> newRecords) {
    Integer existing = [SELECT COUNT() FROM GlAccountingPolicy__c WITH SYSTEM_MODE];
    if (existing + newRecords.size() > 1) {
      for (GlAccountingPolicy__c row : newRecords) {
        row.addError('Accounting会計方針は組織内1件だけです。');
      }
      return;
    }
    for (GlAccountingPolicy__c row : newRecords) {
      assertAllowedPatterns(row);
    }
  }

  /** 仕様: Accounting 第3.1節、第5.7節、Core 第11.8節 */
  public static void beforeUpdate(
    List<GlAccountingPolicy__c> newRecords,
    Map<Id, GlAccountingPolicy__c> oldMap
  ) {
    if (GlAccountingPolicyService.allowFreezeWrite == true) {
      return;
    }
    if (ContractPermissionUtil.hasMigrateAll()) {
      return;
    }
    Boolean terminal = GlAccountingPolicyService.hasTerminalInvoice();
    for (GlAccountingPolicy__c row : newRecords) {
      GlAccountingPolicy__c previous = oldMap.get(row.Id);
      if (previous.FrozenAt__c != null || terminal) {
        row.addError(
          terminal && previous.FrozenAt__c == null
            ? '確定済みまたは取消済みの請求があるため会計方針は変更できません。'
            : '固定済みの会計方針は変更できません。'
        );
        continue;
      }
      assertAllowedPatterns(row);
    }
  }

  /** 仕様: Accounting 第3.1節、共通基盤 第3.6節。固定後の削除は 101 だけ。103 では回避しない。 */
  public static void beforeDelete(List<GlAccountingPolicy__c> oldRecords) {
    Boolean migrateAll = ContractPermissionUtil.hasMigrateAll();
    Boolean deleteRecords = ContractPermissionUtil.hasDeleteRecords();
    Boolean terminal = GlAccountingPolicyService.hasTerminalInvoice();
    for (GlAccountingPolicy__c row : oldRecords) {
      Boolean frozen = row.FrozenAt__c != null || terminal;
      if (frozen) {
        if (migrateAll) {
          continue;
        }
        row.addError(
          terminal && row.FrozenAt__c == null
            ? '確定済みまたは取消済みの請求があるため会計方針は削除できません。'
            : '固定済みの会計方針は削除できません。'
        );
        continue;
      }
      if (!deleteRecords) {
        row.addError('Accounting会計方針は削除できません。');
      }
    }
  }

  /** 仕様: 共通基盤.md 第12章。101の方針固定解除は IrregularUpdate。それ以外のマスタ保存は SaveAccountingMaster。 */
  public static void afterUpdate(
    List<GlAccountingPolicy__c> newRecords,
    Map<Id, GlAccountingPolicy__c> oldMap
  ) {
    if (GlAccountingPolicyService.allowFreezeWrite == true) {
      return;
    }
    List<SObject> unfrozen = new List<SObject>();
    List<SObject> saved = new List<SObject>();
    for (GlAccountingPolicy__c row : newRecords) {
      GlAccountingPolicy__c previous = oldMap == null ? null : oldMap.get(row.Id);
      if (
        previous != null &&
        previous.FrozenAt__c != null &&
        row.FrozenAt__c == null &&
        ContractPermissionUtil.hasMigrateAll()
      ) {
        unfrozen.add(row);
      } else {
        saved.add(row);
      }
    }
    ContractIrregularOperationLog.logUpdate(unfrozen);
    ContractMasterOperationLog.logSave(saved);
  }

  private static void assertAllowedPatterns(GlAccountingPolicy__c row) {
    try {
      GlAccountingPolicyService.deriveAllowedPatternKeys(row);
    } catch (GlAccountingPolicyService.PolicyException ex) {
      row.addError(ex.getMessage());
    }
  }
}