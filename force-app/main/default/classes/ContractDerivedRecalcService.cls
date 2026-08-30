/**
 * 仕様: 共通基盤 第3.6節。102。First／Latest／Lifecycle、HasReference、StatusPath を Ordered から再計算する。
 * 入口は Developer Console。画面ボタンは置かない。
 */
public without sharing class ContractDerivedRecalcService {
  public static void recalculate(Set<Id> contractServiceIds) {
    if (!ContractPermissionUtil.hasFixContract()) {
      ContractPermissionUtil.assertHas(
        ContractPermissionUtil.FIX_CONTRACT,
        '契約と見積の再計算を実行する権限がありません。'
      );
    }
    if (contractServiceIds == null || contractServiceIds.isEmpty()) {
      return;
    }
    ContractServiceWriteGuard.allowPackageWrite(true);
    try {
      ContractOrderedHistorySyncService.syncForServices(contractServiceIds);
      ContractServiceLifecycleService.ensureLifecycleForServices(
        contractServiceIds
      );
      Set<Id> billingAccountIds = new Set<Id>();
      Set<Id> historyIds = new Set<Id>();
      for (ContractService__c service : [
        SELECT Id, BiilingAcccount__c
        FROM ContractService__c
        WHERE Id IN :contractServiceIds
        WITH SYSTEM_MODE
      ]) {
        if (service.BiilingAcccount__c != null) {
          billingAccountIds.add(service.BiilingAcccount__c);
        }
      }
      for (ContractHistory__c history : [
        SELECT Id
        FROM ContractHistory__c
        WHERE ContractService__c IN :contractServiceIds
        WITH SYSTEM_MODE
      ]) {
        historyIds.add(history.Id);
      }
      BillingAccountKeyService.refreshHasReference(billingAccountIds);
      ContractHistoryStatusPathService.syncForInvoiceParents(historyIds);
      for (Id serviceId : contractServiceIds) {
        ContractOperationLogService.write(
          'IrregularRecalc',
          null,
          'ContractService__c',
          String.valueOf(serviceId)
        );
      }
    } finally {
      ContractServiceWriteGuard.allowPackageWrite(false);
    }
  }
}
