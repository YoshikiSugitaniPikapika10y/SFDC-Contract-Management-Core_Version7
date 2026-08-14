/**
 * 受注済→見積への差し戻し時に、関連する請求明細を調整する。
 */
public without sharing class EstimateRevertInvoiceService {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;

  public static final String NON_LATEST_ORDERED_REVERT_MESSAGE = '後続の受注済バージョンがあるため差し戻せません。新しい方から順に差し戻してください。';

  public static final String NEWER_ESTIMATE_REVERT_MESSAGE = '後続の見積 Version があるため差し戻せません。新しい見積を Archive してから差し戻してください。';

  public static void adjustForRevertedToEstimateHistories(
    List<ContractHistory__c> revertedHistories
  ) {
    if (revertedHistories == null || revertedHistories.isEmpty()) {
      return;
    }

    Set<Id> revertedHistoryIds = new Set<Id>();
    for (ContractHistory__c revertedHistory : revertedHistories) {
      if (revertedHistory.Id != null) {
        revertedHistoryIds.add(revertedHistory.Id);
      }
    }
    if (revertedHistoryIds.isEmpty()) {
      return;
    }

    // beforeUpdate で請求書ロック有無を弾いている前提。防御として再検査し、当該 Version は全削除。
    InvoiceLockUtil.assertNoLockedInvoices(revertedHistoryIds);
    InvoiceCanonicalService.purgeBillingForHistories(revertedHistoryIds);
  }

  public static Boolean isLatestOrderedHistory(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return false;
    }
    return !queryNonLatestOrderedHistoryIds(new Set<Id>{ contractHistoryId })
      .contains(contractHistoryId);
  }

  /**
   * 同一契約サービス上、Ordered の MAX(Version) より小さい（または Version 不明の）履歴 ID。
   * LatestOrderedHistory__c ポインタは使わない（ずれても誤差し戻し／差し戻し不能にしない）。
   */
  public static Set<Id> queryNonLatestOrderedHistoryIds(
    Set<Id> contractHistoryIds
  ) {
    Set<Id> blockedHistoryIds = new Set<Id>();
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return blockedHistoryIds;
    }

    Map<Id, ContractHistory__c> historiesById = new Map<Id, ContractHistory__c>(
      [
        SELECT Id, ContractService__c, Version__c
        FROM ContractHistory__c
        WHERE Id IN :contractHistoryIds
        WITH SYSTEM_MODE
      ]
    );
    if (historiesById.isEmpty()) {
      return blockedHistoryIds;
    }

    Set<Id> contractServiceIds = new Set<Id>();
    for (ContractHistory__c history : historiesById.values()) {
      if (history.ContractService__c != null) {
        contractServiceIds.add(history.ContractService__c);
      }
    }
    if (contractServiceIds.isEmpty()) {
      return blockedHistoryIds;
    }

    Map<Id, Decimal> maxOrderedVersionByServiceId = new Map<Id, Decimal>();
    for (AggregateResult result : [
      SELECT ContractService__c serviceId, MAX(Version__c) maxVersion
      FROM ContractHistory__c
      WHERE
        ContractService__c IN :contractServiceIds
        AND historystatus__c = :HISTORY_STATUS_ORDERED
        AND Version__c != NULL
      WITH SYSTEM_MODE
      GROUP BY ContractService__c
    ]) {
      maxOrderedVersionByServiceId.put(
        (Id) result.get('serviceId'),
        (Decimal) result.get('maxVersion')
      );
    }

    for (ContractHistory__c history : historiesById.values()) {
      if (history.ContractService__c == null) {
        continue;
      }
      // Version 不明は最新と証明できないため差し戻し不可
      if (history.Version__c == null) {
        blockedHistoryIds.add(history.Id);
        continue;
      }
      if (
        !maxOrderedVersionByServiceId.containsKey(history.ContractService__c)
      ) {
        continue;
      }
      Decimal maxOrderedVersion = maxOrderedVersionByServiceId.get(
        history.ContractService__c
      );
      if (maxOrderedVersion != null && maxOrderedVersion > history.Version__c) {
        blockedHistoryIds.add(history.Id);
      }
    }
    return blockedHistoryIds;
  }

  /**
   * 同一契約サービスに、対象より新しい Version の Estimate がある履歴 ID。
   */
  public static Set<Id> queryHistoryIdsWithNewerEstimates(
    Set<Id> contractHistoryIds
  ) {
    Set<Id> blockedHistoryIds = new Set<Id>();
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return blockedHistoryIds;
    }

    Map<Id, ContractHistory__c> historiesById = new Map<Id, ContractHistory__c>(
      [
        SELECT Id, ContractService__c, Version__c
        FROM ContractHistory__c
        WHERE Id IN :contractHistoryIds
        WITH SYSTEM_MODE
      ]
    );
    if (historiesById.isEmpty()) {
      return blockedHistoryIds;
    }

    Set<Id> contractServiceIds = new Set<Id>();
    for (ContractHistory__c history : historiesById.values()) {
      if (history.ContractService__c != null) {
        contractServiceIds.add(history.ContractService__c);
      }
    }
    if (contractServiceIds.isEmpty()) {
      return blockedHistoryIds;
    }

    Map<Id, Decimal> maxEstimateVersionByServiceId = new Map<Id, Decimal>();
    for (AggregateResult result : [
      SELECT ContractService__c serviceId, MAX(Version__c) maxVersion
      FROM ContractHistory__c
      WHERE
        ContractService__c IN :contractServiceIds
        AND historystatus__c = :HISTORY_STATUS_ESTIMATE
        AND Version__c != NULL
      WITH SYSTEM_MODE
      GROUP BY ContractService__c
    ]) {
      maxEstimateVersionByServiceId.put(
        (Id) result.get('serviceId'),
        (Decimal) result.get('maxVersion')
      );
    }

    for (ContractHistory__c history : historiesById.values()) {
      if (
        history.ContractService__c == null ||
        history.Version__c == null ||
        !maxEstimateVersionByServiceId.containsKey(history.ContractService__c)
      ) {
        continue;
      }
      Decimal maxEstimateVersion = maxEstimateVersionByServiceId.get(
        history.ContractService__c
      );
      if (
        maxEstimateVersion != null &&
        maxEstimateVersion > history.Version__c
      ) {
        blockedHistoryIds.add(history.Id);
      }
    }
    return blockedHistoryIds;
  }

  public static Boolean hasNewerEstimateVersion(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return false;
    }
    return queryHistoryIdsWithNewerEstimates(new Set<Id>{ contractHistoryId })
      .contains(contractHistoryId);
  }
}
