/**
 * 受注済→見積への差し戻し時に、関連する請求明細を調整する。
 */
public without sharing class EstimateRevertInvoiceService {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;

  public static final String NON_LATEST_ORDERED_REVERT_MESSAGE = '後続の受注済バージョンがあるため差し戻せません。新しい方から順に差し戻してください。';

  public static final String NEWER_ESTIMATE_REVERT_MESSAGE = '後続の見積バージョンがあるため差し戻せません。後続の見積を先にアーカイブしてください。';

  public static final String DRAFT_JOURNAL_REVERT_MESSAGE = '未確定請求に仕訳が残っているため差し戻せません。';

  /** 仕様: Core 第4.9節、第5.3節、Accounting 第2.5節。消す未確定を参照する仕訳は請求削除の前に物理削除する。 */
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
    for (ContractHistory__c estimate : queryEstimatesNewerThanRevertedVersion(
      minVersionByServiceId,
      revertedIds
    )) {
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

  /** 仕様: Core 第5.3節、第5.5節、第12.4節。自分より新しいVersionのEstimateだけ取る。 */
  private static List<ContractHistory__c> queryEstimatesNewerThanRevertedVersion(
    Map<Id, Decimal> minVersionByServiceId,
    Set<Id> revertedIds
  ) {
    List<String> serviceClauses = new List<String>();
    for (Id serviceId : minVersionByServiceId.keySet()) {
      Decimal version = minVersionByServiceId.get(serviceId);
      if (serviceId == null || version == null) {
        continue;
      }
      serviceClauses.add(
        '(ContractService__c = \'' +
          String.escapeSingleQuotes(String.valueOf(serviceId)) +
          '\' AND Version__c > ' +
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
    if (revertedIds != null && !revertedIds.isEmpty()) {
      soql += ' AND Id NOT IN :revertedIds';
    }
    soql += ' WITH SYSTEM_MODE';
    return Database.query(soql);
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
    List<Invoice__c> invoices = queryInvoicesForRevert(revertedHistoryIds);
    deleteJournalsForDraftInvoices(invoices);
    InvoiceCanonicalService.purgeBillingForHistories(
      revertedHistoryIds,
      invoices
    );
  }

  /** 仕様: Core 第5.3節、Accounting 第2.5節。消す未確定を参照する仕訳は状態を問わず請求削除の前に物理削除する。取消済み請求の仕訳は残す。 */
  private static List<Invoice__c> queryInvoicesForRevert(Set<Id> contractHistoryIds) {
    invoiceSelectCount++;
    return [
      SELECT Id, InvoiceTransactionStatus__c
      FROM Invoice__c
      WHERE ContractHistory__c IN :contractHistoryIds
      WITH SYSTEM_MODE
    ];
  }

  private static void deleteJournalsForDraftInvoices(List<Invoice__c> invoices) {
    Set<Id> draftInvoiceIds = new Set<Id>();
    if (invoices == null) {
      return;
    }
    for (Invoice__c invoice : invoices) {
      if (InvoiceTransactionStatusService.isCancelled(invoice)) {
        continue;
      }
      draftInvoiceIds.add(invoice.Id);
    }
    if (draftInvoiceIds.isEmpty()) {
      return;
    }
    List<GlJournal__c> journals = [
      SELECT Id
      FROM GlJournal__c
      WHERE Invoice__c IN :draftInvoiceIds
      WITH SYSTEM_MODE
    ];
    if (journals.isEmpty()) {
      return;
    }
    Boolean previous = GlJournalTriggerHandler.allowRevertDraftJournalDelete;
    GlJournalTriggerHandler.allowRevertDraftJournalDelete = true;
    try {
      SystemContextAccess.deleteRecords(journals);
    } finally {
      GlJournalTriggerHandler.allowRevertDraftJournalDelete = previous;
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
    RevertBlockSets cached = cachedRevertBlockSets(contractHistoryIds);
    if (cached != null) {
      return cached;
    }
    RevertBlockSets blocks = new RevertBlockSets();
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return blocks;
    }

    historySelectCount++;
    Map<Id, ContractHistory__c> historiesById = new Map<Id, ContractHistory__c>(
      [
        SELECT Id, ContractService__c, Version__c
        FROM ContractHistory__c
        WHERE Id IN :contractHistoryIds
        WITH SYSTEM_MODE
      ]
    );
    return finishRevertBlockSets(contractHistoryIds, historiesById);
  }

  /**
   * 仕様: Core 第5.3節・第12.4節。ロック済み契約履歴の Version は取り直さない。
   */
  public static RevertBlockSets queryRevertBlockSets(
    List<ContractHistory__c> knownHistories
  ) {
    Map<Id, ContractHistory__c> historiesById = new Map<Id, ContractHistory__c>();
    if (knownHistories != null) {
      for (ContractHistory__c history : knownHistories) {
        if (history != null && history.Id != null) {
          historiesById.put(history.Id, history);
        }
      }
    }
    RevertBlockSets cached = cachedRevertBlockSets(historiesById.keySet());
    if (cached != null) {
      return cached;
    }
    return finishRevertBlockSets(historiesById.keySet(), historiesById);
  }

  @TestVisible
  static Integer historySelectCount = 0;
  @TestVisible
  static Integer invoiceSelectCount = 0;
  private static Set<Id> cachedBlockInputIds;
  private static RevertBlockSets cachedBlocks;

  private static RevertBlockSets cachedRevertBlockSets(Set<Id> contractHistoryIds) {
    if (
      contractHistoryIds == null ||
      contractHistoryIds.isEmpty() ||
      cachedBlockInputIds == null ||
      cachedBlocks == null ||
      !cachedBlockInputIds.equals(contractHistoryIds)
    ) {
      return null;
    }
    return cachedBlocks;
  }

  private static RevertBlockSets finishRevertBlockSets(
    Set<Id> contractHistoryIds,
    Map<Id, ContractHistory__c> historiesById
  ) {
    RevertBlockSets blocks = new RevertBlockSets();
    if (historiesById == null || historiesById.isEmpty()) {
      rememberRevertBlockSets(contractHistoryIds, blocks);
      return blocks;
    }

    Set<Id> contractServiceIds = new Set<Id>();
    for (ContractHistory__c history : historiesById.values()) {
      if (history.ContractService__c != null) {
        contractServiceIds.add(history.ContractService__c);
      }
    }
    if (contractServiceIds.isEmpty()) {
      rememberRevertBlockSets(contractHistoryIds, blocks);
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
    rememberRevertBlockSets(contractHistoryIds, blocks);
    return blocks;
  }

  @TestVisible
  static void clearRevertCachesForTest() {
    cachedBlockInputIds = null;
    cachedBlocks = null;
  }

  private static void rememberRevertBlockSets(
    Set<Id> contractHistoryIds,
    RevertBlockSets blocks
  ) {
    cachedBlockInputIds = contractHistoryIds == null
      ? null
      : new Set<Id>(contractHistoryIds);
    cachedBlocks = blocks;
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
