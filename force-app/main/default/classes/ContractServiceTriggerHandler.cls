/**
 * ContractService__c トリガ処理。
 * 受注済みサービスの削除抑止など、サービス単位の整合を守る。
 */
public without sharing class ContractServiceTriggerHandler {
  @TestVisible
  private static final String ORDERED_DELETE_BLOCK_MESSAGE = '受注済みの契約サービスは削除できません。誤受注の場合は、最新の受注履歴を見積に戻してから対応してください。';
  @TestVisible
  private static final String LOCKED_INVOICE_DELETE_BLOCK_MESSAGE = '請求済またはエクスポート済の請求があるため、契約サービスを削除できません。';
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;

  /** 仕様: Core 第3.3.1節 */
  public static Set<Id> collectBillingAccountIds(
    List<ContractService__c> records,
    Map<Id, ContractService__c> oldMap
  ) {
    Set<Id> ids = new Set<Id>();
    if (records == null) {
      return ids;
    }
    for (ContractService__c record : records) {
      if (record != null && record.BiilingAcccount__c != null) {
        ids.add(record.BiilingAcccount__c);
      }
      if (oldMap != null && record != null) {
        ContractService__c prior = oldMap.get(record.Id);
        if (prior != null && prior.BiilingAcccount__c != null) {
          ids.add(prior.BiilingAcccount__c);
        }
      }
    }
    return ids;
  }

  /** 仕様: 共通基盤 第3.6節。物理削除は 101／103（hasDeleteRecords。101 は 103 を含む）。 */
  public static void handleBeforeDelete(List<ContractService__c> oldServices) {
    if (oldServices == null || oldServices.isEmpty()) {
      return;
    }
    if (ContractPermissionUtil.hasDeleteRecords()) {
      return;
    }

    Map<Id, ContractService__c> servicesById = new Map<Id, ContractService__c>(
      oldServices
    );
    Set<Id> candidateServiceIds = new Set<Id>();
    for (ContractService__c service : oldServices) {
      if (service != null && service.Id != null) {
        candidateServiceIds.add(service.Id);
      }
    }
    if (candidateServiceIds.isEmpty()) {
      return;
    }

    // Latest ポインタではなく、実 Ordered 履歴の有無で判定する
    Set<Id> orderedServiceIds = queryServiceIdsWithOrderedHistories(
      candidateServiceIds
    );
    Set<Id> remainingServiceIds = new Set<Id>();
    for (Id serviceId : candidateServiceIds) {
      ContractService__c service = servicesById.get(serviceId);
      if (service == null) {
        continue;
      }
      if (orderedServiceIds.contains(serviceId)) {
        service.addError(ORDERED_DELETE_BLOCK_MESSAGE);
      } else {
        remainingServiceIds.add(serviceId);
      }
    }

    if (remainingServiceIds.isEmpty()) {
      return;
    }

    for (
      Id blockedServiceId : queryServiceIdsWithLockedInvoices(
        remainingServiceIds
      )
    ) {
      ContractService__c service = servicesById.get(blockedServiceId);
      if (service != null) {
        service.addError(LOCKED_INVOICE_DELETE_BLOCK_MESSAGE);
      }
    }
  }

  private static Set<Id> queryServiceIdsWithOrderedHistories(
    Set<Id> contractServiceIds
  ) {
    Set<Id> orderedServiceIds = new Set<Id>();
    for (AggregateResult result : [
      SELECT ContractService__c serviceId
      FROM ContractHistory__c
      WHERE
        ContractService__c IN :contractServiceIds
        AND historystatus__c = :HISTORY_STATUS_ORDERED
      WITH SYSTEM_MODE
      GROUP BY ContractService__c
    ]) {
      orderedServiceIds.add((Id) result.get('serviceId'));
    }
    return orderedServiceIds;
  }

  private static Set<Id> queryServiceIdsWithLockedInvoices(
    Set<Id> contractServiceIds
  ) {
    Set<Id> blockedServiceIds = new Set<Id>();
    if (contractServiceIds == null || contractServiceIds.isEmpty()) {
      return blockedServiceIds;
    }
    String lockedAggSoql =
      'SELECT ContractService__c serviceId' +
      ' FROM Invoice__c' +
      ' WHERE ContractService__c IN :contractServiceIds' +
      ' AND ' +
      InvoiceLockUtil.SOQL_IS_LOCKED +
      ' WITH SYSTEM_MODE' +
      ' GROUP BY ContractService__c';
    for (AggregateResult result : Database.query(lockedAggSoql)) {
      blockedServiceIds.add((Id) result.get('serviceId'));
    }
    return blockedServiceIds;
  }
}
