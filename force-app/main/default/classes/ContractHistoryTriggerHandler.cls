/**
 * ContractHistory__c トリガ処理。
 * 見積削除時の関連整理、受注／アーカイブ遷移に伴う同期・請求調整を呼び出す。
 *
 * 不変条件: 契約期間明細・請求・請求明細は historystatus = Ordered のときだけ存在する。
 */
public without sharing class ContractHistoryTriggerHandler {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;
  private static final String HISTORY_STATUS_ARCHIVE = ContractDomainConstants.HISTORY_STATUS_ARCHIVE;

  public static final String ORDERED_TO_ARCHIVE_BLOCK_MESSAGE = '受注済み（Ordered）から Archive には変更できません。差し戻す場合は Estimate にしてください。';
  public static final String ARCHIVE_LEAVE_BLOCK_MESSAGE = 'Archive からのステータス変更はできません。';
  public static final String ORDER_PERMISSION_BLOCK_MESSAGE = '受注を実行する権限がありません。';
  public static final String REVERT_PERMISSION_BLOCK_MESSAGE = '差し戻しを実行する権限がありません。';

  public static void handleBeforeInsert(List<ContractHistory__c> newHistories) {
    enforceOrderAndRevertPermissions(newHistories, null);
    enforceOrderReadiness(newHistories, null);
    ContractHistoryStatusPathService.applyOnBeforeWrite(newHistories, null);
  }

  public static void handleBeforeDelete(List<ContractHistory__c> oldHistories) {
    Set<Id> historyIds = new Set<Id>();
    for (ContractHistory__c history : oldHistories) {
      if (history.Id != null) {
        historyIds.add(history.Id);
      }
    }
    if (historyIds.isEmpty()) {
      return;
    }

    // ロックありは行ごとに拒否。掃除は削除可能な履歴だけ（一括削除で未ロック行の請求孤児を残さない）
    Set<Id> deletableHistoryIds = new Set<Id>(historyIds);
    Boolean bypassIntegrity = ContractPermissionUtil.canBypassIntegrityGuards();
    if (!bypassIntegrity) {
      Set<Id> lockedHistoryIds = InvoiceLockUtil.queryHistoryIdsWithLockedInvoices(
        historyIds
      );
      for (ContractHistory__c history : oldHistories) {
        if (lockedHistoryIds.contains(history.Id)) {
          history.addError(InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE);
        }
      }
      deletableHistoryIds.removeAll(lockedHistoryIds);
    }
    if (deletableHistoryIds.isEmpty()) {
      return;
    }

    // Invoice__c は契約履歴 MD（連鎖削除）。ロック判定後の明示削除は孤児・順序制御の保険
    InvoiceCanonicalService.deleteInvoicesForHistories(deletableHistoryIds);
    // 期間明細は MD でも、Estimate 防御・孤児掃除のため明示削除
    List<InvoiceProduct__c> invoiceProducts = [
      SELECT Id
      FROM InvoiceProduct__c
      WHERE ContractHistory__c IN :deletableHistoryIds
      WITH SYSTEM_MODE
    ];
    if (!invoiceProducts.isEmpty()) {
      SystemContextAccess.deleteRecords(invoiceProducts);
    }
  }

  public static void handleBeforeUpdate(
    List<ContractHistory__c> newHistories,
    Map<Id, ContractHistory__c> oldMap
  ) {
    // 09/10・受注前提・Archive 不可逆は画面外 DML も含め全経路で強制（#99 でも解除しない）
    enforceOrderAndRevertPermissions(newHistories, oldMap);
    enforceOrderReadiness(newHistories, oldMap);
    ContractHistoryStatusPathService.applyOnBeforeWrite(newHistories, oldMap);

    Set<Id> leavingOrderedHistoryIds = new Set<Id>();
    Set<Id> revertToEstimateHistoryIds = new Set<Id>();
    for (ContractHistory__c history : newHistories) {
      ContractHistory__c oldHistory = oldMap.get(history.Id);
      if (oldHistory == null) {
        continue;
      }

      // Archive 離脱・Ordered→Archive は #99 でも不可（請求 purge / First-Latest ずれ / 請求未生成を防ぐ）
      if (
        oldHistory.historystatus__c == HISTORY_STATUS_ARCHIVE &&
        history.historystatus__c != HISTORY_STATUS_ARCHIVE
      ) {
        history.addError(ARCHIVE_LEAVE_BLOCK_MESSAGE);
        continue;
      }

      if (
        oldHistory.historystatus__c == HISTORY_STATUS_ORDERED &&
        history.historystatus__c == HISTORY_STATUS_ARCHIVE
      ) {
        history.addError(ORDERED_TO_ARCHIVE_BLOCK_MESSAGE);
        continue;
      }

      if (
        oldHistory.historystatus__c != HISTORY_STATUS_ORDERED ||
        history.historystatus__c == HISTORY_STATUS_ORDERED
      ) {
        continue;
      }
      if (history.historystatus__c == HISTORY_STATUS_ESTIMATE) {
        leavingOrderedHistoryIds.add(history.Id);
        revertToEstimateHistoryIds.add(history.Id);
      }
    }
    if (leavingOrderedHistoryIds.isEmpty()) {
      return;
    }
    if (ContractPermissionUtil.canBypassIntegrityGuards()) {
      return;
    }

    Set<Id> nonLatestHistoryIds = EstimateRevertInvoiceService.queryNonLatestOrderedHistoryIds(
      leavingOrderedHistoryIds
    );
    Set<Id> newerEstimateHistoryIds = EstimateRevertInvoiceService.queryHistoryIdsWithNewerEstimates(
      leavingOrderedHistoryIds
    );
    Set<Id> lockedInvoiceHistoryIds = InvoiceLockUtil.queryHistoryIdsWithLockedInvoices(
      revertToEstimateHistoryIds
    );
    for (ContractHistory__c history : newHistories) {
      if (!leavingOrderedHistoryIds.contains(history.Id)) {
        continue;
      }
      if (nonLatestHistoryIds.contains(history.Id)) {
        history.addError(
          EstimateRevertInvoiceService.NON_LATEST_ORDERED_REVERT_MESSAGE
        );
        continue;
      }
      if (newerEstimateHistoryIds.contains(history.Id)) {
        history.addError(
          EstimateRevertInvoiceService.NEWER_ESTIMATE_REVERT_MESSAGE
        );
        continue;
      }
      if (lockedInvoiceHistoryIds.contains(history.Id)) {
        history.addError(InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE);
      }
    }
  }

  public static void handleAfterInsert(List<ContractHistory__c> newHistories) {
    List<ContractHistory__c> insertedAsOrderedHistories = new List<ContractHistory__c>();
    Set<Id> insertedAsOrderedHistoryIds = new Set<Id>();

    for (ContractHistory__c history : newHistories) {
      if (history.historystatus__c == HISTORY_STATUS_ORDERED) {
        insertedAsOrderedHistories.add(history);
        insertedAsOrderedHistoryIds.add(history.Id);
      }
    }

    if (!insertedAsOrderedHistoryIds.isEmpty()) {
      InvoiceProductGenerationService.generateForHistories(
        insertedAsOrderedHistoryIds
      );
    }

    syncOrderedHistoriesOnInsert(newHistories);
    recalculateArr(newHistories);
  }

  public static void handleAfterDelete(List<ContractHistory__c> oldHistories) {
    List<ContractHistory__c> deletedOrderedHistories = new List<ContractHistory__c>();
    for (ContractHistory__c history : oldHistories) {
      if (history.historystatus__c == HISTORY_STATUS_ORDERED) {
        deletedOrderedHistories.add(history);
      }
    }
    if (!deletedOrderedHistories.isEmpty()) {
      ContractOrderedHistorySyncService.syncForHistories(
        deletedOrderedHistories
      );
    }
  }

  public static void handleAfterUpdate(
    List<ContractHistory__c> newHistories,
    Map<Id, ContractHistory__c> oldMap
  ) {
    Set<Id> orderedHistoryIds = new Set<Id>();
    Set<Id> revertToEstimateHistoryIds = new Set<Id>();
    Set<Id> archivedHistoryIds = new Set<Id>();
    List<ContractHistory__c> orderedTransitionHistories = new List<ContractHistory__c>();
    List<ContractHistory__c> revertToEstimateHistories = new List<ContractHistory__c>();

    for (ContractHistory__c history : newHistories) {
      ContractHistory__c oldHistory = oldMap.get(history.Id);

      if (
        oldHistory != null &&
        oldHistory.historystatus__c == HISTORY_STATUS_ORDERED &&
        history.historystatus__c == HISTORY_STATUS_ESTIMATE
      ) {
        revertToEstimateHistoryIds.add(history.Id);
        revertToEstimateHistories.add(history);
      }

      if (
        oldHistory != null &&
        oldHistory.historystatus__c != HISTORY_STATUS_ARCHIVE &&
        history.historystatus__c == HISTORY_STATUS_ARCHIVE
      ) {
        archivedHistoryIds.add(history.Id);
      }

      if (
        history.historystatus__c == HISTORY_STATUS_ORDERED &&
        (oldHistory == null ||
        oldHistory.historystatus__c != HISTORY_STATUS_ORDERED)
      ) {
        orderedTransitionHistories.add(history);
      }

      if (
        oldHistory != null &&
        oldHistory.historystatus__c == HISTORY_STATUS_ESTIMATE &&
        history.historystatus__c == HISTORY_STATUS_ORDERED
      ) {
        orderedHistoryIds.add(history.Id);
      }
    }

    if (!revertToEstimateHistoryIds.isEmpty()) {
      EstimateRevertInvoiceService.adjustForRevertedToEstimateHistories(
        revertToEstimateHistories
      );
      ContractOrderedHistorySyncService.syncForHistories(
        revertToEstimateHistories
      );
    }

    // Estimate→Archive 等で誤って残った期間明細／請求を掃除
    if (!archivedHistoryIds.isEmpty()) {
      InvoiceCanonicalService.purgeBillingForHistories(archivedHistoryIds);
    }

    if (!orderedHistoryIds.isEmpty()) {
      InvoiceProductGenerationService.generateForHistories(orderedHistoryIds);
    }

    if (!orderedTransitionHistories.isEmpty()) {
      ContractHistoryArchiveService.archiveSupersededEstimates(
        orderedTransitionHistories
      );
      ContractOrderedHistorySyncService.syncForHistories(
        orderedTransitionHistories
      );
    }
  }

  /**
   * Ordered になるとき受注前提（請求先・商品・Amount）を検証。
   * 受注ボタンもステータス直接変更も同じ ContractOrderValidationService。
   * 09 権限エラーがある場合は二重 addError で文言が上書きされないようスキップする。
   */
  private static void enforceOrderReadiness(
    List<ContractHistory__c> newHistories,
    Map<Id, ContractHistory__c> oldMap
  ) {
    if (newHistories == null || newHistories.isEmpty()) {
      return;
    }
    List<ContractHistory__c> becomingOrdered = new List<ContractHistory__c>();
    for (ContractHistory__c history : newHistories) {
      if (history == null) {
        continue;
      }
      ContractHistory__c oldHistory = oldMap == null
        ? null
        : oldMap.get(history.Id);
      String oldStatus = oldHistory == null
        ? null
        : oldHistory.historystatus__c;
      if (
        history.historystatus__c == HISTORY_STATUS_ORDERED &&
        oldStatus != HISTORY_STATUS_ORDERED
      ) {
        becomingOrdered.add(history);
      }
    }
    if (becomingOrdered.isEmpty()) {
      return;
    }
    // 権限拒否済みなら readiness は走らせない（addError 上書き防止）
    if (!ContractPermissionUtil.has(ContractPermissionUtil.ORDER)) {
      return;
    }
    ContractOrderValidationService.applyOrderReadinessErrors(becomingOrdered);
  }

  /**
   * 受注（→Ordered）は Contract_09、差し戻し（Ordered→Estimate）は Contract_10。
   * ウィザード以外の直接 DML でも同じ。整合性バイパス（#99）では解除しない。
   */
  private static void enforceOrderAndRevertPermissions(
    List<ContractHistory__c> newHistories,
    Map<Id, ContractHistory__c> oldMap
  ) {
    if (newHistories == null || newHistories.isEmpty()) {
      return;
    }

    Boolean canOrder = null;
    Boolean canRevert = null;
    for (ContractHistory__c history : newHistories) {
      if (history == null) {
        continue;
      }
      ContractHistory__c oldHistory = oldMap == null
        ? null
        : oldMap.get(history.Id);
      String oldStatus = oldHistory == null
        ? null
        : oldHistory.historystatus__c;
      String newStatus = history.historystatus__c;

      Boolean becomingOrdered =
        newStatus == HISTORY_STATUS_ORDERED &&
        oldStatus != HISTORY_STATUS_ORDERED;
      Boolean revertingToEstimate =
        oldStatus == HISTORY_STATUS_ORDERED &&
        newStatus == HISTORY_STATUS_ESTIMATE;

      if (becomingOrdered) {
        if (canOrder == null) {
          canOrder = ContractPermissionUtil.has(ContractPermissionUtil.ORDER);
        }
        if (canOrder != true) {
          history.addError(ORDER_PERMISSION_BLOCK_MESSAGE);
        }
      }
      if (revertingToEstimate) {
        if (canRevert == null) {
          canRevert = ContractPermissionUtil.has(ContractPermissionUtil.REVERT);
        }
        if (canRevert != true) {
          history.addError(REVERT_PERMISSION_BLOCK_MESSAGE);
        }
      }
    }
  }

  private static void syncOrderedHistoriesOnInsert(
    List<ContractHistory__c> histories
  ) {
    List<ContractHistory__c> orderedHistories = new List<ContractHistory__c>();
    for (ContractHistory__c history : histories) {
      if (history.historystatus__c == HISTORY_STATUS_ORDERED) {
        orderedHistories.add(history);
      }
    }

    if (!orderedHistories.isEmpty()) {
      ContractHistoryArchiveService.archiveSupersededEstimates(
        orderedHistories
      );
      ContractOrderedHistorySyncService.syncForHistories(orderedHistories);
    }
  }

  private static void recalculateArr(List<ContractHistory__c> histories) {
    Set<Id> historyIds = new Set<Id>();
    for (ContractHistory__c history : histories) {
      historyIds.add(history.Id);
    }
    ContractArrCalculationService.recalculateForHistories(historyIds);
  }
}
