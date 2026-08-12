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
   * Ordered 同期後に呼ぶ。
   * First Ordered あり＋未設定 → 付与。First Ordered なし＋設定済 → クリア。
   */
  public static void ensureLifecycleForServices(Set<Id> contractServiceIds) {
    if (contractServiceIds == null || contractServiceIds.isEmpty()) {
      return;
    }

    Map<Id, ContractService__c> services = new Map<Id, ContractService__c>(
      [
        SELECT Id, Lifecycle__c, FirstOrderedHistory__c
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
      Boolean hasRecurring = hasRecurringByHistoryId.get(
          service.FirstOrderedHistory__c
        ) == true;
      toUpdate.add(
        new ContractService__c(
          Id = service.Id,
          Lifecycle__c = hasRecurring ? LIFECYCLE_TERM : LIFECYCLE_SPOT
        )
      );
    }

    if (!toUpdate.isEmpty()) {
      SystemContextAccess.updateRecords(toUpdate);
    }
  }

  /**
   * 既存サービスの Lifecycle を一括バックフィル（匿名 Apex / 運用用）。
   */
  public static Integer backfillAllBlankLifecycles() {
    List<ContractService__c> blankServices = [
      SELECT Id, Lifecycle__c, FirstOrderedHistory__c
      FROM ContractService__c
      WHERE Lifecycle__c = NULL AND FirstOrderedHistory__c != NULL
      WITH SYSTEM_MODE
      LIMIT 10000
    ];
    if (blankServices.isEmpty()) {
      return 0;
    }
    Set<Id> serviceIds = new Map<Id, ContractService__c>(blankServices).keySet();
    ensureLifecycleForServices(serviceIds);
    return blankServices.size();
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
        Quantity__c,
        Product__r.BillingType__c
      FROM ContractProduct__c
      WHERE
        ContractHistory__c IN :historyIds
        AND Quantity__c > 0
      WITH SYSTEM_MODE
    ]) {
      String billingType = String.isNotBlank(product.BillingType__c)
        ? product.BillingType__c
        : product.Product__r.BillingType__c;
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
      SELECT ContractService__c
      FROM ContractHistory__c
      WHERE Id IN :historyIds AND ContractService__c != NULL
      WITH SYSTEM_MODE
    ]) {
      serviceIds.add(history.ContractService__c);
    }
    ensureLifecycleForServices(serviceIds);
  }

  public static Boolean isSpotLifecycle(String lifecycle) {
    return lifecycle == LIFECYCLE_SPOT;
  }

  public static Boolean isTermLifecycle(String lifecycle) {
    return lifecycle == LIFECYCLE_TERM;
  }
}
