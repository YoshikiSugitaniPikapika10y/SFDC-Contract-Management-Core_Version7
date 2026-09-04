/**
 * 仕様: 共通基盤.md 第12章・第3.6節。101〜103の例外書き込みは1件1行。
 * 正規手続き・エンジン・インストールは書かない。
 */
public without sharing class ContractIrregularOperationLog {
  public static Boolean skipRegularPath() {
    return ContractOperationLogService.skipInstallWrites == true ||
      ContractServiceWriteGuard.isPackageWriteAllowed() ||
      InvoiceLockUtil.allowLockedStatusWrite == true ||
      InvoicePaymentService.allowLifecycleWrite == true ||
      InvoicePaymentAllocationService.allowHistoricalAmountWrite == true ||
      ManualJournalService.allowLifecycleWrite == true ||
      JournalLockService.allowLockWrite == true ||
      GlJournalTriggerHandler.allowEngineWrite == true;
  }

  public static void logCreate(List<SObject> rows) {
    if (skipRegularPath() || !ContractPermissionUtil.hasMigrateAll()) {
      return;
    }
    ContractOperationLogService.writeMasters('IrregularCreate', rows);
  }

  public static void logUpdate(List<SObject> rows) {
    if (
      skipRegularPath() ||
      (
        !ContractPermissionUtil.hasFixContract() &&
        !ContractPermissionUtil.hasMigrateAll()
      )
    ) {
      return;
    }
    ContractOperationLogService.writeMasters('IrregularUpdate', rows);
  }

  public static void logDelete(List<SObject> rows) {
    if (skipRegularPath() || !ContractPermissionUtil.hasDeleteRecords()) {
      return;
    }
    ContractOperationLogService.writeMasters('IrregularDelete', rows);
  }
}
