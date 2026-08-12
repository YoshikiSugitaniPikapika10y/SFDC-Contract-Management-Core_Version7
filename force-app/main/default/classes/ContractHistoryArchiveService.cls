/**
 * 新しい見積が受注されたときなど、古い見積履歴を Archive にする。
 */
public without sharing class ContractHistoryArchiveService {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ARCHIVE = ContractDomainConstants.HISTORY_STATUS_ARCHIVE;

  public static void archiveSupersededEstimates(
    List<ContractHistory__c> newlyOrderedHistories
  ) {
    if (newlyOrderedHistories == null || newlyOrderedHistories.isEmpty()) {
      return;
    }

    Map<Id, Decimal> maxOrderedVersionByServiceId = new Map<Id, Decimal>();
    Set<Id> orderedHistoryIds = new Set<Id>();
    for (ContractHistory__c orderedHistory : newlyOrderedHistories) {
      if (
        orderedHistory == null ||
        orderedHistory.Id == null ||
        orderedHistory.ContractService__c == null ||
        orderedHistory.Version__c == null
      ) {
        continue;
      }
      orderedHistoryIds.add(orderedHistory.Id);
      Id serviceId = orderedHistory.ContractService__c;
      Decimal version = orderedHistory.Version__c;
      if (
        !maxOrderedVersionByServiceId.containsKey(serviceId) ||
        version > maxOrderedVersionByServiceId.get(serviceId)
      ) {
        maxOrderedVersionByServiceId.put(serviceId, version);
      }
    }
    if (maxOrderedVersionByServiceId.isEmpty()) {
      return;
    }

    Set<Id> serviceIds = maxOrderedVersionByServiceId.keySet();
    Decimal maxVersionOverall = null;
    for (Decimal version : maxOrderedVersionByServiceId.values()) {
      if (maxVersionOverall == null || version > maxVersionOverall) {
        maxVersionOverall = version;
      }
    }

    List<ContractHistory__c> historiesToArchive = new List<ContractHistory__c>();
    for (ContractHistory__c estimateHistory : [
      SELECT Id, ContractService__c, Version__c
      FROM ContractHistory__c
      WHERE
        ContractService__c IN :serviceIds
        AND historystatus__c = :HISTORY_STATUS_ESTIMATE
        AND Version__c <= :maxVersionOverall
        AND Id NOT IN :orderedHistoryIds
      WITH SYSTEM_MODE
    ]) {
      Decimal serviceMax = maxOrderedVersionByServiceId.get(
        estimateHistory.ContractService__c
      );
      if (
        serviceMax == null ||
        estimateHistory.Version__c == null ||
        estimateHistory.Version__c > serviceMax
      ) {
        continue;
      }
      historiesToArchive.add(
        new ContractHistory__c(
          Id = estimateHistory.Id,
          historystatus__c = HISTORY_STATUS_ARCHIVE
        )
      );
    }

    if (!historiesToArchive.isEmpty()) {
      SystemContextAccess.updateRecords(historiesToArchive);
    }
  }
}
