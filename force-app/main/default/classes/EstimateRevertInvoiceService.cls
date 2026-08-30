/**
 * 受注済→見積への差し戻し時に、関連する請求明細を調整する。
 */
public without sharing class EstimateRevertInvoiceService {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;

  public static final String NON_LATEST_ORDERED_REVERT_MESSAGE = '後続の受注済バージョンがあるため差し戻せません。新しい方から順に差し戻してください。';

  public static final String DRAFT_JOURNAL_REVERT_MESSAGE = '未確定請求に仕訳が残っているため差し戻せません。';

  /** 仕様: Core 第4.9節、第5.3節 */
  public static void archiveNewerEstimates(
    List<ContractHistory__c> revertedHistories
  ) {
    if (revertedHistories == null || revertedHistories.isEmpty()) {
      return;
    }
    Map<Id, Decimal> minVersionByServiceId = new Map<Id, Decimal>();
    Map<Id, String> parentKeyByServiceId = new Map<Id, String>();
    Set<Id> revertedIds = new Set<Id>();
    for (ContractHistory__c history : revertedHistories) {
      if (
        history == null ||
        history.Id == null ||
        history.ContractService__c == null ||
        history.Version__c == null
      ) {
        continue;
      }
      revertedIds.add(history.Id);
      Decimal current = minVersionByServiceId.get(history.ContractService__c);
      if (current == null || history.Version__c < current) {
        minVersionByServiceId.put(history.ContractService__c, history.Version__c);
        if (String.isNotBlank(history.BusinessOperationKey__c)) {
          parentKeyByServiceId.put(
            history.ContractService__c,
            history.BusinessOperationKey__c
          );
        }
      }
    }
    if (minVersionByServiceId.isEmpty()) {
      return;
    }
    List<ContractHistory__c> toArchive = new List<ContractHistory__c>();
    for (ContractHistory__c estimate : [
      SELECT Id, ContractService__c, Version__c
      FROM ContractHistory__c
      WHERE
        ContractService__c IN :minVersionByServiceId.keySet()
        AND historystatus__c = :HISTORY_STATUS_ESTIMATE
        AND Id NOT IN :revertedIds
      WITH SYSTEM_MODE
    ]) {
      Decimal baseline = minVersionByServiceId.get(estimate.ContractService__c);
      if (
        baseline != null &&
        estimate.Version__c != null &&
        estimate.Version__c > baseline
      ) {
        ContractHistory__c archived = new ContractHistory__c(
          Id = estimate.Id,
          historystatus__c = ContractDomainConstants.HISTORY_STATUS_ARCHIVE
        );
        String parentKey = parentKeyByServiceId.get(estimate.ContractService__c);
        if (String.isNotBlank(parentKey)) {
          archived.BusinessOperationKey__c = parentKey;
        }
        toArchive.add(archived);
      }
    }
    if (!toArchive.isEmpty()) {
      SystemContextAccess.updateRecords(toArchive);
    }
  }

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

    InvoiceLockUtil.assertNoLockedInvoices(revertedHistoryIds);
    assertNoDraftJournals(revertedHistoryIds);
    InvoiceCanonicalService.purgeBillingForHistories(revertedHistoryIds);
  }

  /** 仕様: Core 第5.3節、Accounting 第1.1節、第1.8.1節。Currentは論理削除・取消済元・取消仕訳を数えない。 */
  private static void assertNoDraftJournals(Set<Id> contractHistoryIds) {
    Set<Id> draftInvoiceIds = new Set<Id>();
    for (Invoice__c invoice : [
      SELECT Id, InvoiceTransactionStatus__c
      FROM Invoice__c
      WHERE ContractHistory__c IN :contractHistoryIds
      WITH SYSTEM_MODE
    ]) {
      if (
        !InvoiceTransactionStatusService.isCancelled(invoice) &&
        !InvoiceLockUtil.isActiveConfirmed(invoice)
      ) {
        draftInvoiceIds.add(invoice.Id);
      }
    }
    if (draftInvoiceIds.isEmpty()) {
      return;
    }
    for (Id invoiceId : draftInvoiceIds) {
      for (GlJournal__c journal : AccountingCurrentService.load(invoiceId)) {
        if (journal.TransactionStatus__c == 'Active') {
          throw new RevertException(DRAFT_JOURNAL_REVERT_MESSAGE);
        }
      }
    }
  }

  public class RevertException extends Exception {
  }

  public static Boolean isLatestOrderedHistory(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return false;
    }
    return !queryNonLatestOrderedHistoryIds(new Set<Id>{ contractHistoryId })
      .contains(contractHistoryId);
  }

  /**
   * 差し戻し beforeUpdate 用。履歴1回＋サービス単位の MAX(Version) 集計1回で
   * 「非最新 Ordered」と「後続 Estimate」を同時に判定する（SOQL 4→2）。
   */
  public class RevertBlockSets {
    public Set<Id> nonLatestOrderedHistoryIds = new Set<Id>();
    public Set<Id> newerEstimateHistoryIds = new Set<Id>();
  }

  public static RevertBlockSets queryRevertBlockSets(Set<Id> contractHistoryIds) {
    RevertBlockSets blocks = new RevertBlockSets();
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return blocks;
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
      return blocks;
    }

    Set<Id> contractServiceIds = new Set<Id>();
    for (ContractHistory__c history : historiesById.values()) {
      if (history.ContractService__c != null) {
        contractServiceIds.add(history.ContractService__c);
      }
    }
    if (contractServiceIds.isEmpty()) {
      return blocks;
    }

    Map<Id, Decimal> maxOrderedVersionByServiceId = new Map<Id, Decimal>();
    Map<Id, Decimal> maxEstimateVersionByServiceId = new Map<Id, Decimal>();
    for (AggregateResult result : [
      SELECT
        ContractService__c serviceId,
        historystatus__c status,
        MAX(Version__c) maxVersion
      FROM ContractHistory__c
      WHERE
        ContractService__c IN :contractServiceIds
        AND historystatus__c IN (:HISTORY_STATUS_ORDERED, :HISTORY_STATUS_ESTIMATE)
        AND Version__c != NULL
      WITH SYSTEM_MODE
      GROUP BY ContractService__c, historystatus__c
    ]) {
      Id serviceId = (Id) result.get('serviceId');
      String status = (String) result.get('status');
      Decimal maxVersion = (Decimal) result.get('maxVersion');
      if (status == HISTORY_STATUS_ORDERED) {
        maxOrderedVersionByServiceId.put(serviceId, maxVersion);
      } else if (status == HISTORY_STATUS_ESTIMATE) {
        maxEstimateVersionByServiceId.put(serviceId, maxVersion);
      }
    }

    for (ContractHistory__c history : historiesById.values()) {
      if (history.ContractService__c == null) {
        continue;
      }
      // Version 不明は最新と証明できないため差し戻し不可
      if (history.Version__c == null) {
        blocks.nonLatestOrderedHistoryIds.add(history.Id);
        continue;
      }
      Decimal maxOrderedVersion = maxOrderedVersionByServiceId.get(
        history.ContractService__c
      );
      if (maxOrderedVersion != null && maxOrderedVersion > history.Version__c) {
        blocks.nonLatestOrderedHistoryIds.add(history.Id);
      }
      Decimal maxEstimateVersion = maxEstimateVersionByServiceId.get(
        history.ContractService__c
      );
      if (
        maxEstimateVersion != null &&
        maxEstimateVersion > history.Version__c
      ) {
        blocks.newerEstimateHistoryIds.add(history.Id);
      }
    }
    return blocks;
  }

  /**
   * 同一契約サービス上、Ordered の MAX(Version) より小さい（または Version 不明の）履歴 ID。
   * LatestOrderedHistory__c ポインタは使わない（ずれても誤差し戻し／差し戻し不能にしない）。
   */
  public static Set<Id> queryNonLatestOrderedHistoryIds(
    Set<Id> contractHistoryIds
  ) {
    return queryRevertBlockSets(contractHistoryIds).nonLatestOrderedHistoryIds;
  }

  /**
   * 同一契約サービスに、対象より新しい Version の Estimate がある履歴 ID。
   */
  public static Set<Id> queryHistoryIdsWithNewerEstimates(
    Set<Id> contractHistoryIds
  ) {
    return queryRevertBlockSets(contractHistoryIds).newerEstimateHistoryIds;
  }

  public static Boolean hasNewerEstimateVersion(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return false;
    }
    return queryHistoryIdsWithNewerEstimates(new Set<Id>{ contractHistoryId })
      .contains(contractHistoryId);
  }
}
