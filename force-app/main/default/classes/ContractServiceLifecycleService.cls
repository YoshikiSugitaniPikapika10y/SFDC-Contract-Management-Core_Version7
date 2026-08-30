/**
 * 契約サービス Lifecycle（Term / Spot）の確定・バックフィル。
 * V1 Ordered 時に継続課金の有無で決定する。
 * Ordered が無くなった（V1 差し戻し）ときはクリアし、再受注で再判定する。
 * Term↔Spot の直接切替はしない（VR Lifecycle_Immutable）。
 */
public without sharing class ContractServiceLifecycleService {
  private static final String LIFECYCLE_TERM = ContractDomainConstants.LIFECYCLE_TERM;
  private static final String LIFECYCLE_SPOT = ContractDomainConstants.LIFECYCLE_SPOT;

  /**
   * 仕様: Core 第3.4.2節。
   * Version 1受注で空から Term/Spot を確定する。差し戻しで Ordered 0件なら空に戻す。
   * First Ordered が Version 1以外なのに Lifecycle が空なら推測して埋めずエラー。
   */
  public static void ensureLifecycleForServices(Set<Id> contractServiceIds) {
    if (contractServiceIds == null || contractServiceIds.isEmpty()) {
      return;
    }

    Map<Id, ContractService__c> services = new Map<Id, ContractService__c>(
      [
        SELECT
          Id,
          Lifecycle__c,
          FirstOrderedHistory__c,
          FirstOrderedHistory__r.Version__c
        FROM ContractService__c
        WHERE Id IN :contractServiceIds
        WITH SYSTEM_MODE
      ]
    );

    Set<Id> firstHistoryIds = new Set<Id>();
    for (ContractService__c service : services.values()) {
      if (
        String.isBlank(service.Lifecycle__c) &&
        service.FirstOrderedHistory__c != null
      ) {
        Decimal version = service.FirstOrderedHistory__r == null
          ? null
          : service.FirstOrderedHistory__r.Version__c;
        if (version != 1) {
          throw new LifecycleException(
            'Lifecycleが空のままOrderedがある契約サービスは、推測して埋められません。'
          );
        }
        firstHistoryIds.add(service.FirstOrderedHistory__c);
      }
    }

    Map<Id, Boolean> hasRecurringByHistoryId = firstHistoryIds.isEmpty()
      ? new Map<Id, Boolean>()
      : loadHasRecurringByHistoryId(firstHistoryIds);
    Set<Id> historiesWithProducts = firstHistoryIds.isEmpty()
      ? new Set<Id>()
      : loadHistoryIdsWithProducts(firstHistoryIds);

    List<ContractService__c> toUpdate = new List<ContractService__c>();
    for (ContractService__c service : services.values()) {
      if (service.FirstOrderedHistory__c == null) {
        if (String.isNotBlank(service.Lifecycle__c)) {
          toUpdate.add(
            new ContractService__c(Id = service.Id, Lifecycle__c = null)
          );
        }
        continue;
      }
      if (String.isNotBlank(service.Lifecycle__c)) {
        continue;
      }
      if (!historiesWithProducts.contains(service.FirstOrderedHistory__c)) {
        continue;
      }
      Boolean hasRecurring =
        hasRecurringByHistoryId.get(service.FirstOrderedHistory__c) == true;
      toUpdate.add(
        new ContractService__c(
          Id = service.Id,
          Lifecycle__c = hasRecurring ? LIFECYCLE_TERM : LIFECYCLE_SPOT
        )
      );
    }

    if (!toUpdate.isEmpty()) {
      Boolean previousWrite = ContractServiceWriteGuard.isPackageWriteAllowed();
      ContractServiceWriteGuard.allowPackageWrite(true);
      try {
        SystemContextAccess.updateRecords(toUpdate);
      } finally {
        ContractServiceWriteGuard.allowPackageWrite(previousWrite);
      }
    }
  }

  /** 仕様: Core 第3.4.2節。一括補完は持たない。 */
  public static Integer backfillAllBlankLifecycles() {
    throw new LifecycleException('Lifecycleの一括補完は持たない。導入作業で直してください。');
  }

  private static Map<Id, Boolean> loadHasRecurringByHistoryId(
    Set<Id> historyIds
  ) {
    Map<Id, Boolean> result = new Map<Id, Boolean>();
    for (Id historyId : historyIds) {
      result.put(historyId, false);
    }
    for (ContractProduct__c product : [
      SELECT
        Id,
        ContractHistory__c,
        BillingType__c,
        Quantity__c
      FROM ContractProduct__c
      WHERE ContractHistory__c IN :historyIds AND Quantity__c > 0
      WITH SYSTEM_MODE
    ]) {
      String billingType = ContractMetadataService.resolveLineBillingType(
        product
      );
      if (ContractMetadataService.isRecurringBillingType(billingType)) {
        result.put(product.ContractHistory__c, true);
      }
    }
    return result;
  }

  private static Set<Id> loadHistoryIdsWithProducts(Set<Id> historyIds) {
    Set<Id> result = new Set<Id>();
    if (historyIds == null || historyIds.isEmpty()) {
      return result;
    }
    for (AggregateResult row : [
      SELECT ContractHistory__c
      FROM ContractProduct__c
      WHERE ContractHistory__c IN :historyIds
      WITH SYSTEM_MODE
      GROUP BY ContractHistory__c
    ]) {
      Id historyId = (Id) row.get('ContractHistory__c');
      if (historyId != null) {
        result.add(historyId);
      }
    }
    return result;
  }

  public static void ensureLifecycleForHistories(Set<Id> historyIds) {
    if (historyIds == null || historyIds.isEmpty()) {
      return;
    }
    Set<Id> serviceIds = new Set<Id>();
    for (ContractHistory__c history : [
      SELECT
        ContractService__c,
        ContractService__r.Lifecycle__c,
        ContractService__r.FirstOrderedHistory__c
      FROM ContractHistory__c
      WHERE Id IN :historyIds AND ContractService__c != NULL
      WITH SYSTEM_MODE
    ]) {
      // ContractProduct の変更経路では、Lifecycle が確定済みなら不変。
      // 未受注（FirstOrdered なし）の Estimate 商品追加でも判定はまだ不要。
      // Ordered 同期・差し戻しは syncForServices から直接再評価される。
      if (
        history.ContractService__r != null &&
        String.isBlank(history.ContractService__r.Lifecycle__c) &&
        history.ContractService__r.FirstOrderedHistory__c != null
      ) {
        serviceIds.add(history.ContractService__c);
      }
    }
    if (!serviceIds.isEmpty()) {
      ensureLifecycleForServices(serviceIds);
    }
  }

  public static Boolean isSpotLifecycle(String lifecycle) {
    return lifecycle == LIFECYCLE_SPOT;
  }

  public static Boolean isTermLifecycle(String lifecycle) {
    return lifecycle == LIFECYCLE_TERM;
  }

  public class LifecycleException extends Exception {
  }
}
