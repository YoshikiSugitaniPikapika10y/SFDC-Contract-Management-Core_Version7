/**
 * 契約サービスの FirstOrderedHistory / LatestOrderedHistory を
 * 受注済履歴から再計算して同期する。
 */
public without sharing class ContractOrderedHistorySyncService {
  private static final String HISTORY_STATUS_ORDERED = 'Ordered';

  public static void syncForHistories(List<ContractHistory__c> histories) {
    if (histories == null || histories.isEmpty()) {
      return;
    }

    Set<Id> serviceIds = new Set<Id>();
    for (ContractHistory__c history : histories) {
      if (history.ContractService__c != null) {
        serviceIds.add(history.ContractService__c);
      }
    }
    syncForServices(serviceIds);
  }

  public static void syncForServices(Set<Id> contractServiceIds) {
    if (contractServiceIds == null || contractServiceIds.isEmpty()) {
      return;
    }

    Map<Id, Id> firstHistoryIdByServiceId = new Map<Id, Id>();
    Map<Id, Id> latestHistoryIdByServiceId = new Map<Id, Id>();

    for (ContractHistory__c history : [
      SELECT Id, ContractService__c, Version__c
      FROM ContractHistory__c
      WHERE
        ContractService__c IN :contractServiceIds
        AND historystatus__c = :HISTORY_STATUS_ORDERED
      WITH SYSTEM_MODE
      ORDER BY ContractService__c, Version__c ASC NULLS LAST
    ]) {
      if (!firstHistoryIdByServiceId.containsKey(history.ContractService__c)) {
        firstHistoryIdByServiceId.put(history.ContractService__c, history.Id);
      }
      latestHistoryIdByServiceId.put(history.ContractService__c, history.Id);
    }

    Map<Id, ContractService__c> existingServices = new Map<Id, ContractService__c>(
      [
        SELECT Id, FirstOrderedHistory__c, LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id IN :contractServiceIds
        WITH SYSTEM_MODE
      ]
    );

    List<ContractService__c> servicesToUpdate = new List<ContractService__c>();
    for (Id serviceId : contractServiceIds) {
      ContractService__c existingService = existingServices.get(serviceId);
      if (existingService == null) {
        continue;
      }

      Id firstHistoryId = firstHistoryIdByServiceId.get(serviceId);
      Id latestHistoryId = latestHistoryIdByServiceId.get(serviceId);

      if (
        existingService.FirstOrderedHistory__c == firstHistoryId &&
        existingService.LatestOrderedHistory__c == latestHistoryId
      ) {
        continue;
      }

      servicesToUpdate.add(
        new ContractService__c(
          Id = serviceId,
          FirstOrderedHistory__c = firstHistoryId,
          LatestOrderedHistory__c = latestHistoryId
        )
      );
    }

    if (!servicesToUpdate.isEmpty()) {
      SystemContextAccess.updateRecords(servicesToUpdate);
    }

    ContractServiceLifecycleService.ensureLifecycleForServices(
      contractServiceIds
    );
  }
}
