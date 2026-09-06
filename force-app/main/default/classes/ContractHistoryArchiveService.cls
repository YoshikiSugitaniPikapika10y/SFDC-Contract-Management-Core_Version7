/**
 * 新しい見積が受注されたときなど、古い見積履歴を Archive にする。
 */
public without sharing class ContractHistoryArchiveService {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ARCHIVE = ContractDomainConstants.HISTORY_STATUS_ARCHIVE;

  /** 仕様: Core 第5.2節、第5.5節、第12.4節 */
  public static void archiveSupersededEstimates(
    List<ContractHistory__c> newlyOrderedHistories
  ) {
    if (newlyOrderedHistories == null || newlyOrderedHistories.isEmpty()) {
      return;
    }

    Map<Id, Decimal> maxOrderedVersionByServiceId = new Map<Id, Decimal>();
    Map<Id, String> parentKeyByServiceId = new Map<Id, String>();
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
        if (String.isNotBlank(orderedHistory.BusinessOperationKey__c)) {
          parentKeyByServiceId.put(
            serviceId,
            orderedHistory.BusinessOperationKey__c
          );
        }
      }
    }
    if (maxOrderedVersionByServiceId.isEmpty()) {
      return;
    }

    List<ContractHistory__c> historiesToArchive = new List<ContractHistory__c>();
    for (ContractHistory__c estimateHistory : queryEstimatesAtOrBelowOrderedVersion(
      maxOrderedVersionByServiceId,
      orderedHistoryIds
    )) {
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
      ContractHistory__c archived = new ContractHistory__c(
        Id = estimateHistory.Id,
        historystatus__c = HISTORY_STATUS_ARCHIVE
      );
      String parentKey = parentKeyByServiceId.get(
        estimateHistory.ContractService__c
      );
      if (String.isNotBlank(parentKey)) {
        archived.BusinessOperationKey__c = parentKey;
      }
      historiesToArchive.add(archived);
    }

    if (!historiesToArchive.isEmpty()) {
      SystemContextAccess.updateRecords(historiesToArchive);
    }
  }

  /** 仕様: Core 第5.2節、第5.5節、第12.4節。受注Version以下の他Estimateだけ取る。 */
  private static List<ContractHistory__c> queryEstimatesAtOrBelowOrderedVersion(
    Map<Id, Decimal> maxOrderedVersionByServiceId,
    Set<Id> orderedHistoryIds
  ) {
    List<String> serviceClauses = new List<String>();
    for (Id serviceId : maxOrderedVersionByServiceId.keySet()) {
      Decimal version = maxOrderedVersionByServiceId.get(serviceId);
      if (serviceId == null || version == null) {
        continue;
      }
      serviceClauses.add(
        '(ContractService__c = \'' +
          String.escapeSingleQuotes(String.valueOf(serviceId)) +
          '\' AND Version__c <= ' +
          String.valueOf(version) +
          ')'
      );
    }
    if (serviceClauses.isEmpty()) {
      return new List<ContractHistory__c>();
    }
    String soql =
      'SELECT Id, ContractService__c, Version__c FROM ContractHistory__c WHERE historystatus__c = :HISTORY_STATUS_ESTIMATE AND (' +
      String.join(serviceClauses, ' OR ') +
      ')';
    if (orderedHistoryIds != null && !orderedHistoryIds.isEmpty()) {
      soql += ' AND Id NOT IN :orderedHistoryIds';
    }
    soql += ' WITH SYSTEM_MODE';
    return Database.query(soql);
  }
}
