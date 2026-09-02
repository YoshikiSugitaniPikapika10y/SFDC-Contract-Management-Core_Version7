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

  public static final String ORDERED_TO_ARCHIVE_BLOCK_MESSAGE = '受注済みから不採用には変更できません。差し戻す場合は見積にしてください。';
  public static final String ARCHIVE_LEAVE_BLOCK_MESSAGE = 'Archive からのステータス変更はできません。';
  public static final String ORDER_PERMISSION_BLOCK_MESSAGE = '受注を実行する権限がありません。';
  public static final String REVERT_PERMISSION_BLOCK_MESSAGE = '差し戻しを実行する権限がありません。';
  public static final String RENEW_REQUEST_NOT_ALLOWED_MESSAGE =
    '更新商談の作成要求は、更新商談機能がONのTermのNew・Change・Renewだけにできます。';

  /** 仕様: Core 第3.2節、第4.9節、第5.2節、第11.5節 */
  public static void handleBeforeInsert(List<ContractHistory__c> newHistories) {
    // Cancel Ordered は契約サービスの終端。見積作成を含む直接 DML でも後続 Version を作らせない。
    ContractHistoryTerminalService.applyVersionAfterCancelErrors(newHistories);
    ContractHistoryOpportunityGuard.assertRequired(newHistories);
    rejectManualRenewEstimateAutoCreatedChange(newHistories, null);
    rejectDisallowedRenewOpportunityRequests(newHistories);
    enforceOrderAndRevertPermissions(newHistories, null);
    enforceOrderReadiness(newHistories, null);
    ContractHistoryStatusPathService.applyOnBeforeWrite(newHistories, null);
  }

  /** 仕様: Core 第4.11節、共通基盤 第3.6節。01〜21・101・102 は拒否。103・104 だけ通す。 */
  public static void handleBeforeDelete(List<ContractHistory__c> oldHistories) {
    if (ContractPermissionUtil.hasDeleteRecords()) {
      return;
    }
    for (ContractHistory__c history : oldHistories) {
      if (history == null) {
        continue;
      }
      history.addError('契約履歴は物理削除できません。見積を閉じる場合はArchiveしてください。');
    }
  }

  /** 仕様: Core 第3.2節、第4.9節、第5.2節、第11.5節 */
  public static void handleBeforeUpdate(
    List<ContractHistory__c> newHistories,
    Map<Id, ContractHistory__c> oldMap
  ) {
    // 09/10・受注前提・Archive 不可逆は画面外 DML も含め全経路で強制（#99 でも解除しない）
    ContractHistoryOpportunityGuard.assertRequired(newHistories);
    rejectManualRenewEstimateAutoCreatedChange(newHistories, oldMap);
    rejectDisallowedRenewOpportunityRequests(newHistories);
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

      // Archive は終端。前回契約履歴リンクを切り、後続バージョン関連リストにも出さない
      if (
        oldHistory.historystatus__c != HISTORY_STATUS_ARCHIVE &&
        history.historystatus__c == HISTORY_STATUS_ARCHIVE
      ) {
        history.PreviousHistory__c = null;
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
        history.OrderDate__c = null;
      }
    }
    if (leavingOrderedHistoryIds.isEmpty()) {
      return;
    }

    EstimateRevertInvoiceService.RevertBlockSets revertBlocks = EstimateRevertInvoiceService.queryRevertBlockSets(
      leavingOrderedHistoryIds
    );
    Set<Id> nonLatestHistoryIds = revertBlocks.nonLatestOrderedHistoryIds;
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

    ContractArrCalculationService.beginRecalcDefer();
    ContractHistoryStatusPathService.beginPathSyncDefer();
    BillingAccountKeyService.beginReferenceRefreshDefer();
    ContractServiceLifecycleService.beginLifecycleDefer();
    try {
      if (!insertedAsOrderedHistoryIds.isEmpty()) {
        InvoiceProductGenerationService.generateForHistories(
          insertedAsOrderedHistoryIds
        );
      }
      syncOrderedHistoriesOnInsert(newHistories);
      if (!insertedAsOrderedHistoryIds.isEmpty()) {
        recalculateArr(newHistories);
      }
    } finally {
      ContractServiceLifecycleService.endLifecycleDefer();
      BillingAccountKeyService.endReferenceRefreshDefer();
      ContractHistoryStatusPathService.endPathSyncDefer();
      ContractArrCalculationService.endRecalcDefer();
    }
    ContractIrregularOperationLog.logCreate(newHistories);
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
    ContractIrregularOperationLog.logDelete(oldHistories);
  }

  /** 仕様: Core 第6.1節 */
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
      EstimateRevertInvoiceService.archiveNewerEstimates(
        revertToEstimateHistories
      );
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

    if (!orderedHistoryIds.isEmpty() || !orderedTransitionHistories.isEmpty()) {
      ContractArrCalculationService.beginRecalcDefer();
      ContractHistoryStatusPathService.beginPathSyncDefer();
      BillingAccountKeyService.beginReferenceRefreshDefer();
      ContractServiceLifecycleService.beginLifecycleDefer();
      try {
        if (!orderedHistoryIds.isEmpty()) {
          InvoiceProductGenerationService.generateForHistories(
            orderedHistoryIds
          );
        }
        if (!orderedTransitionHistories.isEmpty()) {
          ContractHistoryArchiveService.archiveSupersededEstimates(
            orderedTransitionHistories
          );
          ContractOrderedHistorySyncService.syncForHistories(
            orderedTransitionHistories
          );
        }
      } finally {
        ContractServiceLifecycleService.endLifecycleDefer();
        BillingAccountKeyService.endReferenceRefreshDefer();
        ContractHistoryStatusPathService.endPathSyncDefer();
        ContractArrCalculationService.endRecalcDefer();
      }
    }
    ContractIrregularOperationLog.logUpdate(newHistories);
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
   * 受注（→Ordered）は 06、差し戻し（Ordered→Estimate）は 07。
   * ウィザード以外の直接 DML でも同じ。101〜104 では代替しない。
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

  public static Boolean allowRenewEstimateAutoCreatedWrite;

  /** 仕様: Core 第4.9節 */
  private static void rejectManualRenewEstimateAutoCreatedChange(
    List<ContractHistory__c> newHistories,
    Map<Id, ContractHistory__c> oldMap
  ) {
    if (newHistories == null || allowRenewEstimateAutoCreatedWrite == true) {
      return;
    }
    for (ContractHistory__c history : newHistories) {
      if (history == null) {
        continue;
      }
      Boolean nextValue = history.RenewEstimateAutoCreated__c == true;
      if (oldMap == null) {
        if (nextValue) {
          history.addError('自動作成印は利用者が変更できません。');
        }
        continue;
      }
      ContractHistory__c prior = oldMap.get(history.Id);
      if (prior != null && prior.RenewEstimateAutoCreated__c != nextValue) {
        history.addError('自動作成印は利用者が変更できません。');
      }
    }
  }

  /** 仕様: Core 第5.2節、第11.5節 */
  private static void rejectDisallowedRenewOpportunityRequests(
    List<ContractHistory__c> newHistories
  ) {
    if (newHistories == null) {
      return;
    }
    List<ContractHistory__c> requested = new List<ContractHistory__c>();
    Set<Id> serviceIds = new Set<Id>();
    for (ContractHistory__c history : newHistories) {
      if (history == null || history.CreateRenewOpportunity__c != true) {
        continue;
      }
      requested.add(history);
      if (history.ContractService__c != null) {
        serviceIds.add(history.ContractService__c);
      }
    }
    if (requested.isEmpty()) {
      return;
    }
    Boolean switchOn = ContractDocumentSettingService.requireRenewOpportunitySwitch();
    Map<Id, ContractService__c> services = serviceIds.isEmpty()
      ? new Map<Id, ContractService__c>()
      : new Map<Id, ContractService__c>(
          [
            SELECT Id, Lifecycle__c
            FROM ContractService__c
            WHERE Id IN :serviceIds
            WITH SYSTEM_MODE
          ]
        );
    for (ContractHistory__c history : requested) {
      if (!switchOn) {
        history.addError(RENEW_REQUEST_NOT_ALLOWED_MESSAGE);
        continue;
      }
      ContractService__c service = services.get(history.ContractService__c);
      ContractHistory__c probe = new ContractHistory__c();
      probe.Id = history.Id;
      probe.Type__c = history.Type__c;
      probe.ContractService__c = history.ContractService__c;
      probe.ContractService__r = service;
      Boolean lifecycleUnset =
        service == null || String.isBlank(service.Lifecycle__c);
      if (history.Id == null && lifecycleUnset) {
        if (
          history.Type__c == ContractDomainConstants.HISTORY_TYPE_CANCEL
        ) {
          history.addError(RENEW_REQUEST_NOT_ALLOWED_MESSAGE);
        }
        continue;
      }
      if (OrderCreateController.shouldSkipRenewOpportunity(probe)) {
        history.addError(RENEW_REQUEST_NOT_ALLOWED_MESSAGE);
      }
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
