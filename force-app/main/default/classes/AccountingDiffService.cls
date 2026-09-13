public without sharing class AccountingDiffService {
  public class DiffException extends Exception {
  }

  @TestVisible
  static Integer copySourceSelectCount = 0;
  @TestVisible
  static Integer invoiceCopySourceSelectCount = 0;
  @TestVisible
  static Integer cancelReasonSelectCount = 0;
  @TestVisible
  static Boolean paymentCancelIncludeLineCandidates;
  @TestVisible
  static Boolean paymentCancelIncludeManualCandidates;
  private static Map<Id, CancelReasonSnapshot> rememberedManualCancelReasons = new Map<Id, CancelReasonSnapshot>();
  private static Map<Id, CancelReasonSnapshot> rememberedPaymentCancelReasons = new Map<Id, CancelReasonSnapshot>();
  private static Map<Id, CancelReasonSnapshot> rememberedInvoiceCancelReasons = new Map<Id, CancelReasonSnapshot>();

  /**
   * 仕様: Accounting 第4.2節・第8.8節。入出金取消の同一処理で売上・手動候補の載せ方を渡す。
   */
  public static void setPaymentCancelCandidateScope(
    Boolean includeLineCandidates,
    Boolean includeManualCandidates
  ) {
    paymentCancelIncludeLineCandidates = includeLineCandidates;
    paymentCancelIncludeManualCandidates = includeManualCandidates;
  }

  public static void clearPaymentCancelCandidateScope() {
    paymentCancelIncludeLineCandidates = null;
    paymentCancelIncludeManualCandidates = null;
  }

  public class ReverseDateCount {
    @AuraEnabled
    public Date reverseDate;
    @AuraEnabled
    public Integer journalCount;
  }

  public class CancelPreview {
    @AuraEnabled
    public Integer logicalDeleteCount;
    @AuraEnabled
    public Integer reverseCount;
    @AuraEnabled
    public List<ReverseDateCount> reverseDateCounts;
    @AuraEnabled
    public Boolean hasFutureReverseDate;
    @AuraEnabled
    public String displayText;
  }

  /** 仕様: Accounting 第1.8.1節、第8.2節、第8.4節、第8.5節、第8.7節、第8.8節、第9.1節、日付仕様 第7.3節 */
  public static void applyForInvoice(
    Id invoiceId,
    String eventKey,
    String operationKey,
    Date cancellationDate
  ) {
    applyForInvoice(invoiceId, eventKey, operationKey, cancellationDate, null);
  }

  /**
   * 仕様: Accounting 第8.2節、Core 第7.9.7節。同一処理で対象請求を行ロック済みなら取り直さない。
   */
  public static void applyForInvoice(
    Id invoiceId,
    String eventKey,
    String operationKey,
    Date cancellationDate,
    Invoice__c knownLockedInvoice
  ) {
    applyForInvoice(
      invoiceId,
      eventKey,
      operationKey,
      cancellationDate,
      knownLockedInvoice,
      null
    );
  }

  /**
   * 仕様: Accounting 第8.1節・第8.2節・第8.8節。
   * restrictLineIds がある検収日変更は、その請求明細に紐づく仕訳だけをDiffする。
   */
  public static void applyForInvoice(
    Id invoiceId,
    String eventKey,
    String operationKey,
    Date cancellationDate,
    Invoice__c knownLockedInvoice,
    Set<Id> restrictLineIds
  ) {
    if (invoiceId == null) {
      throw new DiffException('請求が指定されていません。');
    }
    // 仕様: Core 第11.4.2節
    FieldCopyDefinitionService.validateAllDefinitions();
    AccountingEventFixedCatalog.require(eventKey);
    if (String.isBlank(operationKey)) {
      throw new DiffException('業務操作キーがありません。');
    }
    Boolean includeLineCandidates = true;
    Boolean includeManualCandidates = true;
    if (
      (eventKey == AccountingEventFixedCatalog.PAYMENT_CANCELLED.key ||
      eventKey == AccountingEventFixedCatalog.PAYMENT_RECORDED.key) &&
      paymentCancelIncludeLineCandidates != null
    ) {
      includeLineCandidates = paymentCancelIncludeLineCandidates;
      includeManualCandidates = paymentCancelIncludeManualCandidates == true;
    }
    Invoice__c invoice = knownLockedInvoice != null &&
      knownLockedInvoice.Id == invoiceId
      ? knownLockedInvoice
      : AccountingCauseLockService.lockInvoice(invoiceId);
    invoice = AccountingGoalService.prepareInvoiceForGoal(invoice);
    GlAccountingPolicy__c policy = eventKey ==
      AccountingEventFixedCatalog.BILLING_CONFIRMED.key
      ? GlAccountingPolicyService.freezeOnFirstConfirm()
      : GlAccountingPolicyService.requireOrgPolicy();
    // 仕様: Accounting 第8.1節・第8.2節。検収日変更は変えた明細だけをDiffする。未指定は請求書全体にしない。
    Set<Id> scopedLineIds = restrictLineIdsForEvent(eventKey, restrictLineIds);
    // 仕様: Accounting 第8.2節手順2。ロック後に集めたCurrentは取り直さない。
    List<GlJournal__c> current = AccountingCurrentService.load(invoiceId);
    assertCurrentIntegrity(current);
    if (policy.AccountingEnabled__c != true) {
      if (isCancelEvent(eventKey)) {
        cancelCurrent(
          invoiceId,
          current,
          eventKey,
          operationKey,
          cancellationDate
        );
      }
      clearRememberedCancelReasons();
      return;
    }
    if (
      !InvoiceTransactionStatusService.isConfirmed(invoice) &&
      !InvoiceTransactionStatusService.isCancelled(invoice)
    ) {
      clearRememberedCancelReasons();
      return;
    }
    List<GlJournal__c> diffCurrent = journalsForGoalScope(
      current,
      scopedLineIds,
      includeLineCandidates,
      includeManualCandidates
    );
    List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
      invoice,
      policy,
      current,
      scopedLineIds,
      includeLineCandidates,
      includeManualCandidates
    );
    try {
      persistDiff(
        invoice,
        goals,
        diffCurrent,
        current,
        eventKey,
        operationKey,
        cancellationDate,
        scopedLineIds
      );
      persistHistoricalBreakdown(goals, scopedLineIds);
      AccountingTagEvaluationService.evaluateForInvoice(
        invoiceId,
        invoice,
        AccountingCurrentService.load(invoiceId)
      );
    } finally {
      clearRememberedCancelReasons();
    }
  }

  /**
   * 仕様: Accounting 第2.4節、Core 第7.9.5節。
   * 取消ヘッダーへ書いた理由を同一処理の逆仕訳へ渡し、取り直さない。
   */
  public static void rememberManualCancelReason(
    Id headerId,
    String reason,
    String reasonText
  ) {
    if (headerId == null) {
      return;
    }
    CancelReasonSnapshot snapshot = new CancelReasonSnapshot();
    snapshot.reason = reason;
    snapshot.reasonText = reasonText;
    rememberedManualCancelReasons.put(headerId, snapshot);
  }

  /** 仕様: Accounting 第8.2節、Core 第7.9.5節。入出金へ書いた理由を逆仕訳へ渡し取り直さない。 */
  public static void rememberPaymentCancelReason(
    Id paymentId,
    String reason,
    String reasonText
  ) {
    if (paymentId == null) {
      return;
    }
    CancelReasonSnapshot snapshot = new CancelReasonSnapshot();
    snapshot.reason = reason;
    snapshot.reasonText = reasonText;
    rememberedPaymentCancelReasons.put(paymentId, snapshot);
  }

  /** 仕様: Accounting 第8.2節、Core 第7.9.5節。元請求へ書いた理由を逆仕訳へ渡し取り直さない。 */
  public static void rememberInvoiceCancelReason(
    Id invoiceId,
    String reason,
    String reasonText
  ) {
    if (invoiceId == null) {
      return;
    }
    CancelReasonSnapshot snapshot = new CancelReasonSnapshot();
    snapshot.reason = reason;
    snapshot.reasonText = reasonText;
    rememberedInvoiceCancelReasons.put(invoiceId, snapshot);
  }

  private static void clearRememberedCancelReasons() {
    rememberedManualCancelReasons.clear();
    rememberedPaymentCancelReasons.clear();
    rememberedInvoiceCancelReasons.clear();
  }

  private class PersistPlan {
    List<GlJournal__c> inserts;
    List<GlJournal__c> logicalDeletes;
    List<GlJournal__c> reversals;
  }

  /** 仕様: Accounting 第1.8.1節、第8.2節、第8.8節 */
  private static PersistPlan collectPersistDiff(
    Invoice__c invoice,
    List<AccountingGoalService.GoalJournal> goals,
    List<GlJournal__c> current,
    String eventKey,
    String operationKey
  ) {
    return collectPersistDiff(
      invoice,
      goals,
      current,
      eventKey,
      operationKey,
      null
    );
  }

  /** 仕様: Accounting 第1.8.1節、第8.1節、第8.2節、第8.8節 */
  private static PersistPlan collectPersistDiff(
    Invoice__c invoice,
    List<AccountingGoalService.GoalJournal> goals,
    List<GlJournal__c> current,
    String eventKey,
    String operationKey,
    Set<Id> restrictLineIds
  ) {
    Map<String, GlJournal__c> activeByLine = new Map<String, GlJournal__c>();
    for (GlJournal__c journal : current) {
      if (journal.TransactionStatus__c != 'Active') {
        continue;
      }
      if (!inDiffLineScope(journal, restrictLineIds)) {
        continue;
      }
      if (activeByLine.containsKey(journal.JournalLineKey__c)) {
        throw new DiffException('同じ仕訳行キーがCurrent内で重複しています。');
      }
      activeByLine.put(journal.JournalLineKey__c, journal);
    }
    CopySourceBundle copySources = loadCopySources(invoice, goals);
    Set<String> goalKeys = new Set<String>();
    PersistPlan plan = new PersistPlan();
    plan.inserts = new List<GlJournal__c>();
    plan.logicalDeletes = new List<GlJournal__c>();
    plan.reversals = new List<GlJournal__c>();
    for (AccountingGoalService.GoalJournal goal : goals) {
      GlJournal__c next = goal.record;
      if (!inDiffLineScope(next, restrictLineIds)) {
        continue;
      }
      next.AccountingEventKey__c = eventKey;
      next.BusinessOperationKey__c = operationKey;
      applyJournalCopy(next, copySources);
      goalKeys.add(next.JournalLineKey__c);
      GlJournal__c existing = activeByLine.get(next.JournalLineKey__c);
      if (existing == null) {
        next.IdempotencyKey__c = idempotencyKey(
          goal,
          operationKey,
          next.JournalLineKey__c
        );
        plan.inserts.add(next);
        continue;
      }
      if (sameContent(existing, next)) {
        continue;
      }
      // 仕様: Core 第11.4.4節、Accounting 第8.7節。差替えinsertは人が直した画面定義項目を載せない。
      carryScreenJournalExtraFields(existing, next);
      if (existing.IsLocked__c == true) {
        plan.reversals.add(existing);
        next.IdempotencyKey__c = idempotencyKey(
          goal,
          operationKey,
          next.JournalLineKey__c
        );
        plan.inserts.add(next);
      } else {
        existing.TransactionStatus__c = 'LogicallyDeleted';
        plan.logicalDeletes.add(existing);
        next.IdempotencyKey__c = idempotencyKey(
          goal,
          operationKey,
          next.JournalLineKey__c
        );
        plan.inserts.add(next);
      }
    }
    for (GlJournal__c existing : activeByLine.values()) {
      if (goalKeys.contains(existing.JournalLineKey__c)) {
        continue;
      }
      if (existing.IsLocked__c == true) {
        plan.reversals.add(existing);
      } else {
        existing.TransactionStatus__c = 'LogicallyDeleted';
        plan.logicalDeletes.add(existing);
      }
    }
    return plan;
  }

  /** 仕様: Accounting 第1.8.1節、第8.2節、第8.8節 */
  private static void persistDiff(
    Invoice__c invoice,
    List<AccountingGoalService.GoalJournal> goals,
    List<GlJournal__c> current,
    String eventKey,
    String operationKey,
    Date cancellationDate
  ) {
    persistDiff(
      invoice,
      goals,
      current,
      current,
      eventKey,
      operationKey,
      cancellationDate,
      null
    );
  }

  private static void persistDiff(
    Invoice__c invoice,
    List<AccountingGoalService.GoalJournal> goals,
    List<GlJournal__c> diffCurrent,
    List<GlJournal__c> rememberCurrent,
    String eventKey,
    String operationKey,
    Date cancellationDate
  ) {
    persistDiff(
      invoice,
      goals,
      diffCurrent,
      rememberCurrent,
      eventKey,
      operationKey,
      cancellationDate,
      null
    );
  }

  private static void persistDiff(
    Invoice__c invoice,
    List<AccountingGoalService.GoalJournal> goals,
    List<GlJournal__c> diffCurrent,
    List<GlJournal__c> rememberCurrent,
    String eventKey,
    String operationKey,
    Date cancellationDate,
    Set<Id> restrictLineIds
  ) {
    PersistPlan plan = collectPersistDiff(
      invoice,
      goals,
      diffCurrent,
      eventKey,
      operationKey,
      restrictLineIds
    );
    // 仕様: Accounting 第8.5節・第8.8節、Core 第7.9.6節。この操作のDiffで逆仕訳になるLockだけ取消基準日を取る。
    assertCancellationDateIfReversals(plan.reversals, cancellationDate);
    Boolean previous = GlJournalTriggerHandler.allowEngineWrite;
    GlJournalTriggerHandler.allowEngineWrite = true;
    try {
      if (isCancelEvent(eventKey)) {
        applyCancelAuditToJournals(
          plan.logicalDeletes,
          invoice.Id,
          eventKey,
          operationKey
        );
      }
      if (!plan.logicalDeletes.isEmpty()) {
        update plan.logicalDeletes;
      }
      for (GlJournal__c original : plan.reversals) {
        plan.inserts.add(
          reversalOf(
            original,
            eventKey,
            operationKey,
            cancellationDate,
            cancelReasonOf(original, invoice.Id, eventKey)
          )
        );
        original.TransactionStatus__c = 'Cancelled';
        if (isCancelEvent(eventKey)) {
          applyCancelAuditToJournal(
            original,
            invoice.Id,
            eventKey,
            operationKey,
            null,
            rememberedManualCancelReasons
          );
        }
      }
      if (!plan.reversals.isEmpty()) {
        update plan.reversals;
      }
      if (!plan.inserts.isEmpty()) {
        insert plan.inserts;
      }
      rememberCurrentAfterPersist(invoice.Id, rememberCurrent, plan);
    } catch (Exception ex) {
      AccountingCurrentService.invalidate(invoice.Id);
      throw ex;
    } finally {
      GlJournalTriggerHandler.allowEngineWrite = previous;
    }
  }

  /** 仕様: Core 第7.9.6節、Accounting 第8.5節・第8.8節、日付仕様 第7.3節 */
  public static CancelPreview previewApply(
    Id invoiceId,
    String eventKey,
    Date cancellationDate
  ) {
    return previewApply(invoiceId, eventKey, cancellationDate, null);
  }

  /**
   * 仕様: Accounting 第8.2節。同一処理で行ロック済みならプレビューも取り直さない。
   */
  public static CancelPreview previewApply(
    Id invoiceId,
    String eventKey,
    Date cancellationDate,
    Invoice__c knownLockedInvoice
  ) {
    return previewApply(
      invoiceId,
      eventKey,
      cancellationDate,
      knownLockedInvoice,
      null
    );
  }

  /**
   * 仕様: Accounting 第8.1節・第8.2節・第8.8節。
   */
  public static CancelPreview previewApply(
    Id invoiceId,
    String eventKey,
    Date cancellationDate,
    Invoice__c knownLockedInvoice,
    Set<Id> restrictLineIds
  ) {
    if (invoiceId == null) {
      throw new DiffException('請求が指定されていません。');
    }
    AccountingEventFixedCatalog.require(eventKey);
    Boolean includeLineCandidates = true;
    Boolean includeManualCandidates = true;
    if (
      (eventKey == AccountingEventFixedCatalog.PAYMENT_CANCELLED.key ||
      eventKey == AccountingEventFixedCatalog.PAYMENT_RECORDED.key) &&
      paymentCancelIncludeLineCandidates != null
    ) {
      includeLineCandidates = paymentCancelIncludeLineCandidates;
      includeManualCandidates = paymentCancelIncludeManualCandidates == true;
    }
    if (!isPaymentEvent(eventKey)) {
      if (AccountingGoalService.collectedLines(invoiceId).isEmpty()) {
        AccountingGoalService.invalidateCauseCache(invoiceId);
      }
    }
    Invoice__c invoice = knownLockedInvoice != null &&
      knownLockedInvoice.Id == invoiceId
      ? knownLockedInvoice
      : AccountingCauseLockService.lockInvoice(invoiceId);
    GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
    Set<Id> scopedLineIds = restrictLineIdsForEvent(eventKey, restrictLineIds);
    // 仕様: Accounting 第8.2節手順2。ロック後に集めたCurrentは取り直さない。
    List<GlJournal__c> current = AccountingCurrentService.load(invoiceId);
    assertCurrentIntegrity(current);
    if (policy.AccountingEnabled__c != true) {
      return emptyPreview();
    }
    if (
      !InvoiceTransactionStatusService.isConfirmed(invoice) &&
      !InvoiceTransactionStatusService.isCancelled(invoice)
    ) {
      return emptyPreview();
    }
    List<GlJournal__c> diffCurrent = journalsForGoalScope(
      current,
      scopedLineIds,
      includeLineCandidates,
      includeManualCandidates
    );
    List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
      invoice,
      policy,
      current,
      scopedLineIds,
      includeLineCandidates,
      includeManualCandidates
    );
    PersistPlan plan = collectPersistDiff(
      invoice,
      goals,
      diffCurrent,
      eventKey,
      'PREVIEW',
      scopedLineIds
    );
    return previewFromPlan(
      plan.logicalDeletes,
      plan.reversals,
      cancellationDate
    );
  }

  /** 仕様: Core 第7.9.6節、Accounting 第8.5節、日付仕様 第7.3節、第8章 */
  public static CancelPreview previewCancel(
    Id invoiceId,
    String eventKey,
    Date cancellationDate,
    Id excludingPaymentId,
    Id excludingHeaderId
  ) {
    if (invoiceId == null) {
      throw new DiffException('請求が指定されていません。');
    }
    AccountingEventFixedCatalog.require(eventKey);
    List<GlJournal__c> current = AccountingCurrentService.load(invoiceId);
    assertCurrentIntegrity(current);
    Set<Id> activePayments = activePaymentIdsForCancel(current, eventKey);
    Set<Id> activeHeaders = activeHeaderIdsForCancel(current, eventKey);
    if (excludingPaymentId != null) {
      activePayments.remove(excludingPaymentId);
    }
    if (excludingHeaderId != null) {
      activeHeaders.remove(excludingHeaderId);
    }
    List<GlJournal__c> unlocked = new List<GlJournal__c>();
    List<GlJournal__c> locked = new List<GlJournal__c>();
    for (GlJournal__c journal : current) {
      if (journal.TransactionStatus__c != 'Active') {
        continue;
      }
      if (!isCancelTarget(journal, eventKey, activePayments, activeHeaders)) {
        continue;
      }
      if (journal.IsLocked__c == true) {
        locked.add(journal);
      } else {
        unlocked.add(journal);
      }
    }
    CancelPreview preview = new CancelPreview();
    preview.logicalDeleteCount = unlocked.size();
    preview.reverseCount = locked.size();
    preview.reverseDateCounts = new List<ReverseDateCount>();
    preview.hasFutureReverseDate = false;
    Map<Date, Integer> countByDate = new Map<Date, Integer>();
    // 仕様: 日付仕様 第8章
    Date operationDay = InvoiceTransactionStatusService.organizationToday();
    for (GlJournal__c original : locked) {
      Date reverseDate = reversalDateOf(original, cancellationDate);
      Integer currentCount = countByDate.containsKey(reverseDate)
        ? countByDate.get(reverseDate)
        : 0;
      countByDate.put(reverseDate, currentCount + 1);
      if (reverseDate != null && reverseDate > operationDay) {
        preview.hasFutureReverseDate = true;
      }
    }
    List<Date> dates = new List<Date>(countByDate.keySet());
    dates.sort();
    for (Date reverseDate : dates) {
      ReverseDateCount row = new ReverseDateCount();
      row.reverseDate = reverseDate;
      row.journalCount = countByDate.get(reverseDate);
      preview.reverseDateCounts.add(row);
    }
    preview.displayText = toDisplayText(preview);
    return preview;
  }

  public static CancelPreview emptyConfirmPreview() {
    return emptyPreview();
  }

  private static CancelPreview emptyPreview() {
    return previewFromPlan(
      new List<GlJournal__c>(),
      new List<GlJournal__c>(),
      null
    );
  }

  private static CancelPreview previewFromPlan(
    List<GlJournal__c> logicalDeletes,
    List<GlJournal__c> reversals,
    Date cancellationDate
  ) {
    CancelPreview preview = new CancelPreview();
    preview.logicalDeleteCount = logicalDeletes == null
      ? 0
      : logicalDeletes.size();
    preview.reverseCount = reversals == null ? 0 : reversals.size();
    preview.reverseDateCounts = new List<ReverseDateCount>();
    preview.hasFutureReverseDate = false;
    Map<Date, Integer> countByDate = new Map<Date, Integer>();
    // 仕様: 日付仕様 第8章
    Date operationDay = InvoiceTransactionStatusService.organizationToday();
    if (reversals != null) {
      for (GlJournal__c original : reversals) {
        Date reverseDate = reversalDateOf(original, cancellationDate);
        Integer currentCount = countByDate.containsKey(reverseDate)
          ? countByDate.get(reverseDate)
          : 0;
        countByDate.put(reverseDate, currentCount + 1);
        if (reverseDate != null && reverseDate > operationDay) {
          preview.hasFutureReverseDate = true;
        }
      }
    }
    List<Date> dates = new List<Date>(countByDate.keySet());
    dates.sort();
    for (Date reverseDate : dates) {
      ReverseDateCount row = new ReverseDateCount();
      row.reverseDate = reverseDate;
      row.journalCount = countByDate.get(reverseDate);
      preview.reverseDateCounts.add(row);
    }
    preview.displayText = toDisplayText(preview);
    return preview;
  }

  public static String toDisplayText(CancelPreview preview) {
    List<String> lines = new List<String>{
      '論理削除件数: ' + String.valueOf(preview.logicalDeleteCount),
      '逆仕訳件数: ' + String.valueOf(preview.reverseCount),
      '実際の逆仕訳日:'
    };
    if (
      preview.reverseDateCounts == null || preview.reverseDateCounts.isEmpty()
    ) {
      lines.add('なし');
    } else {
      for (ReverseDateCount row : preview.reverseDateCounts) {
        lines.add(
          String.valueOf(row.reverseDate) +
            ': ' +
            String.valueOf(row.journalCount) +
            '件'
        );
      }
    }
    lines.add(
      '将来日付: ' + (preview.hasFutureReverseDate == true ? 'あり' : 'なし')
    );
    return String.join(lines, '\n');
  }

  /** 仕様: Accounting 第8.5節・第8.8節、Core 第7.9.6節。保存時だけ未入力を拒否する。プレビューは件数を返す。 */
  private static void assertCancellationDateIfReversals(
    List<GlJournal__c> reversals,
    Date cancellationDate
  ) {
    if (reversals != null && !reversals.isEmpty() && cancellationDate == null) {
      throw new DiffException(
        'ロック済み仕訳がある取消では取消基準日が必要です。'
      );
    }
  }

  private static Boolean isCancelEvent(String eventKey) {
    return eventKey == AccountingEventFixedCatalog.BILLING_CANCELLED.key ||
      eventKey == AccountingEventFixedCatalog.PAYMENT_CANCELLED.key ||
      eventKey == AccountingEventFixedCatalog.MANUAL_JOURNAL.key;
  }

  private static Boolean isPaymentEvent(String eventKey) {
    return eventKey == AccountingEventFixedCatalog.PAYMENT_RECORDED.key ||
      eventKey == AccountingEventFixedCatalog.PAYMENT_CANCELLED.key;
  }

  /** 仕様: Accounting 第2.4節、第8.2節、第8.5節、第8.8節、Core 第7.9.3節・第7.9.5節 */
  private static void cancelCurrent(
    Id invoiceId,
    List<GlJournal__c> current,
    String eventKey,
    String operationKey,
    Date cancellationDate
  ) {
    Set<Id> activePayments = activePaymentIdsForCancel(current, eventKey);
    Set<Id> activeHeaders = activeHeaderIdsForCancel(current, eventKey);
    List<GlJournal__c> unlocked = new List<GlJournal__c>();
    List<GlJournal__c> locked = new List<GlJournal__c>();
    for (GlJournal__c journal : current) {
      if (journal.TransactionStatus__c != 'Active') {
        continue;
      }
      if (!isCancelTarget(journal, eventKey, activePayments, activeHeaders)) {
        continue;
      }
      if (journal.IsLocked__c == true) {
        locked.add(journal);
      } else {
        journal.TransactionStatus__c = 'LogicallyDeleted';
        unlocked.add(journal);
      }
    }
    assertCancellationDateIfReversals(locked, cancellationDate);
    applyCancelAuditToJournals(unlocked, invoiceId, eventKey, operationKey);
    Boolean previous = GlJournalTriggerHandler.allowEngineWrite;
    GlJournalTriggerHandler.allowEngineWrite = true;
    try {
      if (!unlocked.isEmpty()) {
        update unlocked;
      }
      List<GlJournal__c> inserts = new List<GlJournal__c>();
      for (GlJournal__c original : locked) {
        CancelReasonSnapshot reason = cancelReasonOf(
          original,
          invoiceId,
          eventKey
        );
        inserts.add(
          reversalOf(original, eventKey, operationKey, cancellationDate, reason)
        );
        original.TransactionStatus__c = 'Cancelled';
        applyCancelAuditToJournal(original, invoiceId, eventKey, operationKey);
      }
      if (!locked.isEmpty()) {
        update locked;
      }
      if (!inserts.isEmpty()) {
        insert inserts;
      }
      PersistPlan plan = new PersistPlan();
      plan.inserts = inserts;
      plan.logicalDeletes = unlocked;
      plan.reversals = locked;
      rememberCurrentAfterPersist(invoiceId, current, plan);
    } catch (Exception ex) {
      AccountingCurrentService.invalidate(invoiceId);
      throw ex;
    } finally {
      GlJournalTriggerHandler.allowEngineWrite = previous;
    }
  }

  private class CancelReasonSnapshot {
    String reason;
    String reasonText;
  }

  /** 仕様: Accounting 第2.4節。請求の原因項目は CHANGE-221。 */
  private static CancelReasonSnapshot cancelReasonOf(
    GlJournal__c journal,
    Id invoiceId,
    String eventKey
  ) {
    CancelReasonSnapshot snapshot = new CancelReasonSnapshot();
    if (eventKey == AccountingEventFixedCatalog.PAYMENT_CANCELLED.key) {
      if (journal == null || journal.InvoicePayment__c == null) {
        return snapshot;
      }
      CancelReasonSnapshot remembered = rememberedPaymentCancelReasons.get(
        journal.InvoicePayment__c
      );
      if (remembered != null) {
        return remembered;
      }
      cancelReasonSelectCount++;
      List<InvoicePayment__c> payments = [
        SELECT CancellationReason__c, CancellationReasonText__c
        FROM InvoicePayment__c
        WHERE Id = :journal.InvoicePayment__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!payments.isEmpty()) {
        snapshot.reason = payments[0].CancellationReason__c;
        snapshot.reasonText = payments[0].CancellationReasonText__c;
      }
      return snapshot;
    }
    if (eventKey == AccountingEventFixedCatalog.MANUAL_JOURNAL.key) {
      if (journal == null || journal.GlManualJournalHeader__c == null) {
        return snapshot;
      }
      CancelReasonSnapshot remembered = rememberedManualCancelReasons.get(
        journal.GlManualJournalHeader__c
      );
      if (remembered != null) {
        return remembered;
      }
      cancelReasonSelectCount++;
      List<GlManualJournalHeader__c> headers = [
        SELECT CancellationReason__c, CancellationReasonText__c
        FROM GlManualJournalHeader__c
        WHERE Id = :journal.GlManualJournalHeader__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!headers.isEmpty()) {
        snapshot.reason = headers[0].CancellationReason__c;
        snapshot.reasonText = headers[0].CancellationReasonText__c;
      }
      return snapshot;
    }
    if (eventKey == AccountingEventFixedCatalog.BILLING_CANCELLED.key) {
      if (
        invoiceId == null ||
        !Schema.sObjectType.Invoice__c.fields.getMap()
          .containsKey('CancellationReason__c')
      ) {
        return snapshot;
      }
      CancelReasonSnapshot remembered = rememberedInvoiceCancelReasons.get(
        invoiceId
      );
      if (remembered != null) {
        return remembered;
      }
      cancelReasonSelectCount++;
      List<Invoice__c> invoices = Database.query(
        'SELECT CancellationReason__c, CancellationReasonText__c ' +
        'FROM Invoice__c WHERE Id = :invoiceId WITH SYSTEM_MODE LIMIT 1'
      );
      if (!invoices.isEmpty()) {
        snapshot.reason = (String) invoices[0].get('CancellationReason__c');
        snapshot.reasonText = (String) invoices[0]
          .get('CancellationReasonText__c');
      }
    }
    return snapshot;
  }

  private static void applyCancelAuditToJournals(
    List<GlJournal__c> journals,
    Id invoiceId,
    String eventKey,
    String operationKey
  ) {
    if (journals == null || journals.isEmpty()) {
      return;
    }
    Map<Id, CancelReasonSnapshot> byPayment = new Map<Id, CancelReasonSnapshot>();
    Map<Id, CancelReasonSnapshot> byHeader = new Map<Id, CancelReasonSnapshot>();
    CancelReasonSnapshot invoiceReason = null;
    if (eventKey == AccountingEventFixedCatalog.BILLING_CANCELLED.key) {
      invoiceReason = rememberedInvoiceCancelReasons.get(invoiceId);
    } else if (eventKey == AccountingEventFixedCatalog.PAYMENT_CANCELLED.key) {
      Set<Id> paymentIds = new Set<Id>();
      for (GlJournal__c journal : journals) {
        if (journal != null && journal.InvoicePayment__c != null) {
          paymentIds.add(journal.InvoicePayment__c);
        }
      }
      if (!paymentIds.isEmpty()) {
        Set<Id> missingPaymentIds = new Set<Id>();
        for (Id paymentId : paymentIds) {
          CancelReasonSnapshot remembered = rememberedPaymentCancelReasons.get(
            paymentId
          );
          if (remembered != null) {
            byPayment.put(paymentId, remembered);
          } else {
            missingPaymentIds.add(paymentId);
          }
        }
        if (!missingPaymentIds.isEmpty()) {
          cancelReasonSelectCount++;
          for (InvoicePayment__c payment : [
            SELECT Id, CancellationReason__c, CancellationReasonText__c
            FROM InvoicePayment__c
            WHERE Id IN :missingPaymentIds
            WITH SYSTEM_MODE
          ]) {
            CancelReasonSnapshot snapshot = new CancelReasonSnapshot();
            snapshot.reason = payment.CancellationReason__c;
            snapshot.reasonText = payment.CancellationReasonText__c;
            byPayment.put(payment.Id, snapshot);
          }
        }
      }
    } else if (eventKey == AccountingEventFixedCatalog.MANUAL_JOURNAL.key) {
      Set<Id> headerIds = new Set<Id>();
      Set<Id> missingHeaderIds = new Set<Id>();
      for (GlJournal__c journal : journals) {
        if (journal != null && journal.GlManualJournalHeader__c != null) {
          headerIds.add(journal.GlManualJournalHeader__c);
        }
      }
      for (Id headerId : headerIds) {
        CancelReasonSnapshot remembered = rememberedManualCancelReasons.get(
          headerId
        );
        if (remembered != null) {
          byHeader.put(headerId, remembered);
        } else {
          missingHeaderIds.add(headerId);
        }
      }
      if (!missingHeaderIds.isEmpty()) {
        cancelReasonSelectCount++;
        for (GlManualJournalHeader__c header : [
          SELECT Id, CancellationReason__c, CancellationReasonText__c
          FROM GlManualJournalHeader__c
          WHERE Id IN :missingHeaderIds
          WITH SYSTEM_MODE
        ]) {
          CancelReasonSnapshot snapshot = new CancelReasonSnapshot();
          snapshot.reason = header.CancellationReason__c;
          snapshot.reasonText = header.CancellationReasonText__c;
          byHeader.put(header.Id, snapshot);
        }
      }
    }
    for (GlJournal__c journal : journals) {
      applyCancelAuditToJournal(
        journal,
        invoiceId,
        eventKey,
        operationKey,
        byPayment,
        byHeader
      );
    }
  }

  private static void applyCancelAuditToJournal(
    GlJournal__c journal,
    Id invoiceId,
    String eventKey,
    String operationKey
  ) {
    applyCancelAuditToJournal(
      journal,
      invoiceId,
      eventKey,
      operationKey,
      null,
      null
    );
  }

  private static void applyCancelAuditToJournal(
    GlJournal__c journal,
    Id invoiceId,
    String eventKey,
    String operationKey,
    Map<Id, CancelReasonSnapshot> byPayment,
    Map<Id, CancelReasonSnapshot> byHeader
  ) {
    if (journal == null) {
      return;
    }
    journal.BusinessOperationKey__c = operationKey;
    CancelReasonSnapshot reason;
    if (
      eventKey == AccountingEventFixedCatalog.PAYMENT_CANCELLED.key &&
      byPayment != null &&
      journal.InvoicePayment__c != null
    ) {
      reason = byPayment.get(journal.InvoicePayment__c);
    } else if (
      eventKey == AccountingEventFixedCatalog.MANUAL_JOURNAL.key &&
      byHeader != null &&
      journal.GlManualJournalHeader__c != null
    ) {
      reason = byHeader.get(journal.GlManualJournalHeader__c);
    } else if (
      eventKey == AccountingEventFixedCatalog.BILLING_CANCELLED.key &&
      rememberedInvoiceCancelReasons.containsKey(invoiceId)
    ) {
      reason = rememberedInvoiceCancelReasons.get(invoiceId);
    } else {
      reason = cancelReasonOf(journal, invoiceId, eventKey);
    }
    if (reason != null && !String.isBlank(reason.reason)) {
      journal.CancellationReason__c = reason.reason;
      journal.CancellationReasonText__c = reason.reasonText;
    }
  }

  private static Boolean isCancelTarget(
    GlJournal__c journal,
    String eventKey,
    Set<Id> activePayments,
    Set<Id> activeHeaders
  ) {
    if (eventKey == AccountingEventFixedCatalog.BILLING_CANCELLED.key) {
      return true;
    }
    if (eventKey == AccountingEventFixedCatalog.PAYMENT_CANCELLED.key) {
      return journal.InvoicePayment__c != null &&
        !activePayments.contains(journal.InvoicePayment__c);
    }
    if (eventKey == AccountingEventFixedCatalog.MANUAL_JOURNAL.key) {
      return journal.GlManualJournalHeader__c != null &&
        !activeHeaders.contains(journal.GlManualJournalHeader__c);
    }
    return false;
  }

  /**
   * 仕様: Accounting 第8.2節手順2、第8.8節、Core 第12.4節。
   * 請求取消は Current 全部が対象なので入出金・手動ヘッダーを照会しない。
   */
  private static Set<Id> activePaymentIdsForCancel(
    List<GlJournal__c> current,
    String eventKey
  ) {
    if (eventKey == AccountingEventFixedCatalog.BILLING_CANCELLED.key) {
      return new Set<Id>();
    }
    return activePaymentIds(current);
  }

  private static Set<Id> activeHeaderIdsForCancel(
    List<GlJournal__c> current,
    String eventKey
  ) {
    if (eventKey == AccountingEventFixedCatalog.BILLING_CANCELLED.key) {
      return new Set<Id>();
    }
    return activeHeaderIds(current);
  }

  private static Set<Id> activePaymentIds(List<GlJournal__c> current) {
    Set<Id> ids = new Set<Id>();
    for (GlJournal__c journal : current) {
      if (journal.InvoicePayment__c != null) {
        ids.add(journal.InvoicePayment__c);
      }
    }
    if (ids.isEmpty()) {
      return new Set<Id>();
    }
    Set<Id> active = new Set<Id>();
    for (InvoicePayment__c payment : [
      SELECT Id
      FROM InvoicePayment__c
      WHERE Id IN :ids AND PaymentTransactionStatus__c = 'Active'
      WITH SYSTEM_MODE
    ]) {
      active.add(payment.Id);
    }
    return active;
  }

  private static Set<Id> activeHeaderIds(List<GlJournal__c> current) {
    Set<Id> ids = new Set<Id>();
    for (GlJournal__c journal : current) {
      if (journal.GlManualJournalHeader__c != null) {
        ids.add(journal.GlManualJournalHeader__c);
      }
    }
    if (ids.isEmpty()) {
      return new Set<Id>();
    }
    Set<Id> active = new Set<Id>();
    for (GlManualJournalHeader__c header : [
      SELECT Id
      FROM GlManualJournalHeader__c
      WHERE Id IN :ids AND TransactionStatus__c = 'Active'
      WITH SYSTEM_MODE
    ]) {
      active.add(header.Id);
    }
    return active;
  }

  private static void assertCurrentIntegrity(List<GlJournal__c> current) {
    Map<Id, GlJournal__c> byId = new Map<Id, GlJournal__c>();
    Map<Id, List<GlJournal__c>> reversalsByOriginal = new Map<Id, List<GlJournal__c>>();
    for (GlJournal__c journal : current) {
      byId.put(journal.Id, journal);
      if (journal.TransactionStatus__c != 'Reversal') {
        continue;
      }
      if (journal.OriginalJournal__c == null) {
        throw new DiffException('取消仕訳の取消元がありません。');
      }
      if (!reversalsByOriginal.containsKey(journal.OriginalJournal__c)) {
        reversalsByOriginal.put(
          journal.OriginalJournal__c,
          new List<GlJournal__c>()
        );
      }
      reversalsByOriginal.get(journal.OriginalJournal__c).add(journal);
    }
    for (Id originalId : reversalsByOriginal.keySet()) {
      List<GlJournal__c> reversals = reversalsByOriginal.get(originalId);
      if (reversals.size() != 1) {
        throw new DiffException('同じ元仕訳を参照する取消仕訳が複数あります。');
      }
      GlJournal__c original = byId.get(originalId);
      if (original == null) {
        throw new DiffException('取消仕訳の取消元がありません。');
      }
      if (original.Amount__c != reversals[0].Amount__c) {
        throw new DiffException('取消仕訳の金額が元仕訳と一致しません。');
      }
    }
  }

  /** 仕様: Accounting 第2.4節、第8.5節、第8.8節、日付仕様 第7.3節 */
  private static GlJournal__c reversalOf(
    GlJournal__c original,
    String eventKey,
    String operationKey,
    Date cancellationDate,
    CancelReasonSnapshot reason
  ) {
    if (cancellationDate == null) {
      throw new DiffException(
        'ロック済み仕訳の逆仕訳には取消基準日が必要です。'
      );
    }
    Date postingDate = reversalDateOf(original, cancellationDate);
    // 仕様: Accounting 第8.8節。請求明細・仕訳パターンキー・売上計上回番号は clone で元のまま保持する。
    GlJournal__c reversal = original.clone(false, true, false, false);
    reversal.DebitSlotKey__c = original.CreditSlotKey__c;
    reversal.CreditSlotKey__c = original.DebitSlotKey__c;
    reversal.DebitAccountAssignment__c = original.CreditAccountAssignment__c;
    reversal.CreditAccountAssignment__c = original.DebitAccountAssignment__c;
    reversal.DebitAccount__c = original.CreditAccount__c;
    reversal.CreditAccount__c = original.DebitAccount__c;
    reversal.PostingDate__c = postingDate;
    reversal.TransactionStatus__c = 'Reversal';
    // 仕様: Accounting 第8.8節。取消仕訳の IsLocked__c は True。取消元は元の Lock のまま True。
    reversal.IsLocked__c = true;
    reversal.OriginalJournal__c = original.Id;
    reversal.AccountingEventKey__c = eventKey;
    reversal.BusinessOperationKey__c = operationKey;
    if (reason != null && !String.isBlank(reason.reason)) {
      reversal.CancellationReason__c = reason.reason;
      reversal.CancellationReasonText__c = reason.reasonText;
    } else {
      reversal.CancellationReason__c = null;
      reversal.CancellationReasonText__c = null;
    }
    reversal.GenerationUnitKey__c = null;
    reversal.JournalLineKey__c = null;
    reversal.IdempotencyKey__c = hashKey(
      new List<String>{ 'REV', String.valueOf(original.Id) }
    );
    return reversal;
  }

  /** 仕様: Accounting 第8.5節、日付仕様 第7.3節 */
  private static Date reversalDateOf(
    GlJournal__c original,
    Date cancellationDate
  ) {
    return cancellationDate >= original.PostingDate__c
      ? cancellationDate
      : original.PostingDate__c;
  }

  /**
   * 仕様: Accounting 第4.2節・第8.2節・第8.8節。
   * 入出金取消は変えない売上・税・手動をDiff比較から外す。検収日変更は明細限定のまま。
   */
  /**
   * 仕様: Accounting 第8.1節・第8.2節。検収日変更に明細集合が無ければ請求書全体をDiffしない。
   */
  private static Set<Id> restrictLineIdsForEvent(
    String eventKey,
    Set<Id> restrictLineIds
  ) {
    if (
      eventKey == AccountingEventFixedCatalog.ACCEPTANCE_DATE_CHANGED.key &&
      restrictLineIds == null
    ) {
      return new Set<Id>();
    }
    return restrictLineIds;
  }

  /** 仕様: Accounting 第8.2節・第8.8節。明細限定のCurrentだけをDiffする。 */
  private static Boolean inDiffLineScope(
    GlJournal__c journal,
    Set<Id> restrictLineIds
  ) {
    if (restrictLineIds == null) {
      return true;
    }
    return journal != null &&
      journal.InvoiceLine__c != null &&
      restrictLineIds.contains(journal.InvoiceLine__c);
  }

  private static List<GlJournal__c> journalsForGoalScope(
    List<GlJournal__c> current,
    Set<Id> restrictLineIds,
    Boolean includeLineCandidates,
    Boolean includeManualCandidates
  ) {
    if (restrictLineIds != null) {
      return journalsForLines(current, restrictLineIds);
    }
    if (includeLineCandidates == true && includeManualCandidates == true) {
      return current;
    }
    if (current == null) {
      return current;
    }
    List<GlJournal__c> scoped = new List<GlJournal__c>();
    for (GlJournal__c journal : current) {
      if (journal == null) {
        continue;
      }
      if (journal.GlManualJournalHeader__c != null) {
        if (includeManualCandidates == true) {
          scoped.add(journal);
        }
        continue;
      }
      if (journal.InvoicePayment__c != null) {
        scoped.add(journal);
        continue;
      }
      if (journal.InvoiceLine__c != null && includeLineCandidates == true) {
        scoped.add(journal);
      }
    }
    return scoped;
  }

  /**
   * 仕様: Accounting 第8.2節・第8.8節。検収日変更は変えた請求明細のCurrentだけをDiffする。
   */
  private static List<GlJournal__c> journalsForLines(
    List<GlJournal__c> current,
    Set<Id> restrictLineIds
  ) {
    if (restrictLineIds == null || current == null) {
      return current;
    }
    if (restrictLineIds.isEmpty()) {
      return new List<GlJournal__c>();
    }
    List<GlJournal__c> scoped = new List<GlJournal__c>();
    for (GlJournal__c journal : current) {
      if (
        journal != null &&
        journal.InvoiceLine__c != null &&
        restrictLineIds.contains(journal.InvoiceLine__c)
      ) {
        scoped.add(journal);
      }
    }
    return scoped;
  }

  /** 仕様: Accounting 第4.4節、第5.2.15節、第5.2.16節、第8.2節、第8.4節、Core 第8.6節 */
  private static void persistHistoricalBreakdown(
    List<AccountingGoalService.GoalJournal> goals
  ) {
    persistHistoricalBreakdown(goals, null);
  }

  private static void persistHistoricalBreakdown(
    List<AccountingGoalService.GoalJournal> goals,
    Set<Id> restrictLineIds
  ) {
    if (goals == null || goals.isEmpty()) {
      return;
    }
    Id invoiceId = goals[0].record == null ? null : goals[0].record.Invoice__c;
    if (invoiceId == null) {
      return;
    }
    Map<Id, InvoicePaymentAllocation__c> updates = new Map<Id, InvoicePaymentAllocation__c>();
    Map<Id, InvoicePaymentAllocation__c> collected = AccountingGoalService.collectedAllocations(
      invoiceId
    );
    for (AccountingGoalService.GoalJournal goal : goals) {
      GlJournal__c journal = goal.record;
      if (journal == null || journal.InvoicePaymentAllocation__c == null) {
        continue;
      }
      Boolean negativeCash =
        journal.JournalPatternKey__c ==
        JournalPatternFixedCatalog.PAYMENT_INVOICE_HISTORICAL_NEGATIVE_CASH.key;
      Boolean positiveCash =
        journal.JournalPatternKey__c ==
        JournalPatternFixedCatalog.PAYMENT_INVOICE_HISTORICAL_POSITIVE_CASH.key;
      if (!positiveCash && !negativeCash) {
        continue;
      }
      if (restrictLineIds != null && !restrictLineIds.isEmpty()) {
        Id lineId = journal.InvoiceLine__c;
        InvoicePaymentAllocation__c collectedRow = collected.get(
          journal.InvoicePaymentAllocation__c
        );
        if (lineId == null && collectedRow != null) {
          lineId = collectedRow.InvoiceLine__c;
        }
        if (lineId == null || !restrictLineIds.contains(lineId)) {
          continue;
        }
      }
      InvoicePaymentAllocation__c allocation = updates.get(
        journal.InvoicePaymentAllocation__c
      );
      if (allocation == null) {
        allocation = collected.get(journal.InvoicePaymentAllocation__c);
        if (allocation == null) {
          allocation = new InvoicePaymentAllocation__c(
            Id = journal.InvoicePaymentAllocation__c,
            HistoricalUacAmount__c = 0,
            HistoricalSpAmount__c = 0
          );
        } else {
          allocation.HistoricalUacAmount__c = 0;
          allocation.HistoricalSpAmount__c = 0;
        }
        updates.put(allocation.Id, allocation);
      }
      Decimal magnitude = nvl(journal.Amount__c);
      String counterpart = journal.DebitSlotKey__c ==
        AccountingSlotFixedCatalog.Cash.key
        ? journal.CreditSlotKey__c
        : journal.DebitSlotKey__c;
      if (counterpart == AccountingSlotFixedCatalog.UnappliedCash.key) {
        Decimal signed = negativeCash ? -magnitude : magnitude;
        allocation.HistoricalUacAmount__c =
          nvl(allocation.HistoricalUacAmount__c) + signed;
      }
      if (counterpart == AccountingSlotFixedCatalog.SuspensePayment.key) {
        Decimal signed = negativeCash ? magnitude : -magnitude;
        allocation.HistoricalSpAmount__c =
          nvl(allocation.HistoricalSpAmount__c) + signed;
      }
    }
    List<InvoicePaymentAllocation__c> toWrite = new List<InvoicePaymentAllocation__c>();
    for (InvoicePaymentAllocation__c allocation : updates.values()) {
      Decimal uac = nvl(allocation.HistoricalUacAmount__c);
      Decimal sp = nvl(allocation.HistoricalSpAmount__c);
      if (uac == 0 && sp == 0) {
        continue;
      }
      if (allocation.Amount__c != uac - sp) {
        throw new DiffException(
          '過去日Invoiceの明細別割当内訳が割当額と一致しません。'
        );
      }
      if (allocation.Amount__c > 0 && (uac < 0 || sp > 0)) {
        throw new DiffException(
          '正額の過去日Invoice割当の振替内訳の符号が不正です。'
        );
      }
      if (allocation.Amount__c < 0 && (uac > 0 || sp < 0)) {
        throw new DiffException(
          '負額の過去日Invoice割当の振替内訳の符号が不正です。'
        );
      }
      toWrite.add(allocation);
    }
    if (!toWrite.isEmpty()) {
      Boolean previous = InvoicePaymentAllocationService.allowHistoricalAmountWrite;
      InvoicePaymentAllocationService.allowHistoricalAmountWrite = true;
      try {
        update toWrite;
      } finally {
        InvoicePaymentAllocationService.allowHistoricalAmountWrite = previous;
      }
    }
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  private static Boolean sameContent(GlJournal__c current, GlJournal__c goal) {
    return current.Amount__c == goal.Amount__c &&
      current.PostingDate__c == goal.PostingDate__c &&
      current.DebitSlotKey__c == goal.DebitSlotKey__c &&
      current.CreditSlotKey__c == goal.CreditSlotKey__c &&
      current.DebitAccountAssignment__c == goal.DebitAccountAssignment__c &&
      current.CreditAccountAssignment__c == goal.CreditAccountAssignment__c &&
      current.DebitAccount__c == goal.DebitAccount__c &&
      current.CreditAccount__c == goal.CreditAccount__c &&
      current.InvoiceLine__c == goal.InvoiceLine__c &&
      current.InvoicePayment__c == goal.InvoicePayment__c &&
      current.InvoicePaymentAllocation__c == goal.InvoicePaymentAllocation__c &&
      current.GlManualJournalHeader__c == goal.GlManualJournalHeader__c &&
      sameCopyFields(current, goal);
  }

  private static Boolean sameCopyFields(
    GlJournal__c current,
    GlJournal__c goal
  ) {
    Set<String> screenFields = InvoiceOpsFieldService.journalScreenFieldApiNames();
    for (
      String fieldName : FieldCopyDefinitionService.targetFieldApiNames(
        'GlJournal__c'
      )
    ) {
      // 仕様: Accounting 第8.7節、Core 第11.4.4節。画面定義の仕訳追加項目は内容比較しない。
      if (screenFields.contains(fieldName)) {
        continue;
      }
      if (current.get(fieldName) != goal.get(fieldName)) {
        return false;
      }
    }
    return true;
  }

  /** 仕様: Core 第11.4.4節、Accounting 第8.7節。差替えinsertへ人が直した画面定義項目を載せる。 */
  private static void carryScreenJournalExtraFields(
    GlJournal__c current,
    GlJournal__c goal
  ) {
    if (current == null || goal == null) {
      return;
    }
    Map<String, Object> currentFields = current.getPopulatedFieldsAsMap();
    for (String fieldName : InvoiceOpsFieldService.journalScreenFieldApiNames()) {
      if (!currentFields.containsKey(fieldName)) {
        continue;
      }
      goal.put(fieldName, current.get(fieldName));
    }
  }

  private static String idempotencyKey(
    AccountingGoalService.GoalJournal goal,
    String operationKey,
    String journalLineKey
  ) {
    if (
      goal != null &&
      goal.isManual &&
      goal.record.GlManualJournalHeader__c != null
    ) {
      return hashKey(
        new List<String>{
          'MAN',
          String.valueOf(goal.record.GlManualJournalHeader__c),
          'ORIGINAL'
        }
      );
    }
    return hashKey(
      new List<String>{ operationKey, journalLineKey, 'ORIGINAL' }
    );
  }

  private class CopySourceBundle {
    Invoice__c invoice;
    Map<Id, InvoiceLine__c> lines = new Map<Id, InvoiceLine__c>();
    Map<Id, InvoicePayment__c> payments = new Map<Id, InvoicePayment__c>();
    Map<Id, InvoicePaymentAllocation__c> allocations = new Map<Id, InvoicePaymentAllocation__c>();
    Map<Id, ContractProduct__c> contractProducts = new Map<Id, ContractProduct__c>();
    Map<Id, Product2> products = new Map<Id, Product2>();
    Map<Id, BillingAccount__c> billingAccounts = new Map<Id, BillingAccount__c>();
    Map<Id, ContractHistory__c> histories = new Map<Id, ContractHistory__c>();
    Map<Id, Opportunity> opportunities = new Map<Id, Opportunity>();
    Map<Id, Account> accounts = new Map<Id, Account>();
  }

  /** 仕様: Core 第11.4.2節。仕訳コピーの From を定義どおり SOQL する。行ロック照会は使わない。 */
  private static CopySourceBundle loadCopySources(
    Invoice__c lockedInvoice,
    List<AccountingGoalService.GoalJournal> goals
  ) {
    CopySourceBundle bundle = new CopySourceBundle();
    Set<Id> lineIds = new Set<Id>();
    Set<Id> paymentIds = new Set<Id>();
    Set<Id> allocationIds = new Set<Id>();
    for (AccountingGoalService.GoalJournal goal : goals) {
      if (goal == null || goal.record == null) {
        continue;
      }
      if (goal.record.InvoiceLine__c != null) {
        lineIds.add(goal.record.InvoiceLine__c);
      }
      if (goal.record.InvoicePayment__c != null) {
        paymentIds.add(goal.record.InvoicePayment__c);
      }
      if (goal.record.InvoicePaymentAllocation__c != null) {
        allocationIds.add(goal.record.InvoicePaymentAllocation__c);
      }
    }
    if (lockedInvoice != null && lockedInvoice.Id != null) {
      Set<String> invoiceCopyFields = new Set<String>{
        'BillingAccountSnapShot__c',
        'ContractHistory__c',
        'ContractService__c'
      };
      invoiceCopyFields.addAll(
        FieldCopyDefinitionService.sourceFieldApiNames('Invoice__c')
      );
      invoiceCopyFields.addAll(
        InvoiceProductFieldCopyService.getSourceFieldApiNames('Invoice__c')
      );
      if (hasAllQueriedFields(lockedInvoice, invoiceCopyFields)) {
        bundle.invoice = lockedInvoice;
      } else {
        List<Invoice__c> invoices = (List<Invoice__c>) queryCopySources(
          'Invoice__c',
          new Set<Id>{ lockedInvoice.Id },
          new Set<String>{
            'BillingAccountSnapShot__c',
            'ContractHistory__c',
            'ContractService__c'
          }
        );
        if (!invoices.isEmpty()) {
          bundle.invoice = invoices[0];
        }
      }
    }
    bundle.lines = toLineMap(
      reuseOrQueryCopy(
        'InvoiceLine__c',
        copyToSObject(
          AccountingGoalService.collectedLines(
              lockedInvoice == null ? null : lockedInvoice.Id
            )
            .values()
        ),
        lineIds,
        new Set<String>{
          'Invoice__c',
          'ContractProduct__c',
          'Product__c',
          'Amount__c'
        }
      )
    );
    bundle.payments = toPaymentMap(
      reuseOrQueryCopy(
        'InvoicePayment__c',
        copyToSObject(
          AccountingGoalService.collectedPayments(
              lockedInvoice == null ? null : lockedInvoice.Id
            )
            .values()
        ),
        paymentIds,
        new Set<String>{
          'Invoice__c',
          'Amount__c',
          'PaymentPurpose__c',
          'PaymentDate__c',
          'Memo__c'
        }
      )
    );
    bundle.allocations = toAllocationMap(
      reuseOrQueryCopy(
        'InvoicePaymentAllocation__c',
        copyToSObject(
          AccountingGoalService.collectedAllocations(
              lockedInvoice == null ? null : lockedInvoice.Id
            )
            .values()
        ),
        allocationIds,
        new Set<String>{ 'InvoiceLine__c', 'InvoicePayment__c', 'Amount__c' }
      )
    );
    Set<Id> contractProductIds = new Set<Id>();
    Set<Id> productIds = new Set<Id>();
    for (InvoiceLine__c line : bundle.lines.values()) {
      if (line.ContractProduct__c != null) {
        contractProductIds.add(line.ContractProduct__c);
      }
      if (line.Product__c != null) {
        productIds.add(line.Product__c);
      }
    }
    Id collectedId = lockedInvoice == null ? null : lockedInvoice.Id;
    bundle.contractProducts = toContractProductMap(
      reuseOrQueryCopy(
        'ContractProduct__c',
        copyToSObject(
          AccountingGoalService.collectedContractProducts(collectedId).values()
        ),
        contractProductIds,
        new Set<String>{ 'Product__c', 'ContractHistory__c' }
      )
    );
    for (
      ContractProduct__c contractProduct : bundle.contractProducts.values()
    ) {
      if (contractProduct.Product__c != null) {
        productIds.add(contractProduct.Product__c);
      }
    }
    bundle.products = toProductMap(
      reuseOrQueryCopy(
        'Product2',
        copyToSObject(
          AccountingGoalService.collectedProducts(collectedId).values()
        ),
        productIds,
        new Set<String>{ 'ProductCode' }
      )
    );
    Set<Id> billingIds = new Set<Id>();
    Set<Id> historyIds = new Set<Id>();
    if (bundle.invoice != null) {
      if (bundle.invoice.BillingAccountSnapShot__c != null) {
        billingIds.add(bundle.invoice.BillingAccountSnapShot__c);
      }
      if (bundle.invoice.ContractHistory__c != null) {
        historyIds.add(bundle.invoice.ContractHistory__c);
      }
    }
    bundle.histories = toHistoryMap(
      reuseOrQueryCopy(
        'ContractHistory__c',
        copyToSObject(
          AccountingGoalService.collectedHistories(collectedId).values()
        ),
        historyIds,
        new Set<String>{ 'Opportunity__c', 'ContractService__c' }
      )
    );
    Set<Id> opportunityIds = new Set<Id>();
    Set<Id> accountIds = new Set<Id>();
    for (ContractHistory__c history : bundle.histories.values()) {
      if (history.Opportunity__c != null) {
        opportunityIds.add(history.Opportunity__c);
      }
    }
    bundle.opportunities = toOpportunityMap(
      reuseOrQueryCopy(
        'Opportunity',
        copyToSObject(
          AccountingGoalService.collectedOpportunities(collectedId).values()
        ),
        opportunityIds,
        new Set<String>{ 'AccountId' }
      )
    );
    for (Opportunity opportunity : bundle.opportunities.values()) {
      if (opportunity.AccountId != null) {
        accountIds.add(opportunity.AccountId);
      }
    }
    bundle.billingAccounts = toBillingAccountMap(
      reuseOrQueryCopy(
        'BillingAccount__c',
        copyToSObject(
          AccountingGoalService.collectedBillingAccounts(collectedId).values()
        ),
        billingIds,
        new Set<String>{ 'Account__c' }
      )
    );
    for (BillingAccount__c billingAccount : bundle.billingAccounts.values()) {
      if (billingAccount.Account__c != null) {
        accountIds.add(billingAccount.Account__c);
      }
    }
    bundle.accounts = toAccountMap(
      reuseOrQueryCopy(
        'Account',
        copyToSObject(
          AccountingGoalService.collectedAccounts(collectedId).values()
        ),
        accountIds,
        new Set<String>()
      )
    );
    return bundle;
  }

  /** 仕様: Accounting 第8.2節。Goalが収集した原因にコピー項目があれば取り直さない。 */
  private static List<SObject> reuseOrQueryCopy(
    String objectApiName,
    Map<Id, SObject> collected,
    Set<Id> recordIds,
    Set<String> extraFields
  ) {
    Set<String> needed = extraFields == null
      ? new Set<String>()
      : new Set<String>(extraFields);
    needed.addAll(
      FieldCopyDefinitionService.sourceFieldApiNames(objectApiName)
    );
    if (recordIds == null || recordIds.isEmpty()) {
      return new List<SObject>();
    }
    Boolean reusable = collected != null;
    if (reusable) {
      for (Id recordId : recordIds) {
        if (!hasAllQueriedFields(collected.get(recordId), needed)) {
          reusable = false;
          break;
        }
      }
    }
    if (reusable) {
      List<SObject> rows = new List<SObject>();
      for (Id recordId : recordIds) {
        rows.add(collected.get(recordId));
      }
      return rows;
    }
    return queryCopySources(objectApiName, recordIds, extraFields);
  }

  private static Map<Id, SObject> copyToSObject(SObject[] rows) {
    Map<Id, SObject> mapped = new Map<Id, SObject>();
    if (rows == null) {
      return mapped;
    }
    for (SObject row : rows) {
      if (row != null && row.Id != null) {
        mapped.put(row.Id, row);
      }
    }
    return mapped;
  }

  private static Map<Id, InvoiceLine__c> toLineMap(List<SObject> rows) {
    Map<Id, InvoiceLine__c> mapped = new Map<Id, InvoiceLine__c>();
    if (rows == null) {
      return mapped;
    }
    for (SObject row : rows) {
      mapped.put(row.Id, (InvoiceLine__c) row);
    }
    return mapped;
  }

  private static Map<Id, InvoicePayment__c> toPaymentMap(List<SObject> rows) {
    Map<Id, InvoicePayment__c> mapped = new Map<Id, InvoicePayment__c>();
    if (rows == null) {
      return mapped;
    }
    for (SObject row : rows) {
      mapped.put(row.Id, (InvoicePayment__c) row);
    }
    return mapped;
  }

  private static Map<Id, InvoicePaymentAllocation__c> toAllocationMap(
    List<SObject> rows
  ) {
    Map<Id, InvoicePaymentAllocation__c> mapped = new Map<Id, InvoicePaymentAllocation__c>();
    if (rows == null) {
      return mapped;
    }
    for (SObject row : rows) {
      mapped.put(row.Id, (InvoicePaymentAllocation__c) row);
    }
    return mapped;
  }

  private static Map<Id, ContractProduct__c> toContractProductMap(
    List<SObject> rows
  ) {
    Map<Id, ContractProduct__c> mapped = new Map<Id, ContractProduct__c>();
    if (rows == null) {
      return mapped;
    }
    for (SObject row : rows) {
      mapped.put(row.Id, (ContractProduct__c) row);
    }
    return mapped;
  }

  private static Map<Id, Product2> toProductMap(List<SObject> rows) {
    Map<Id, Product2> mapped = new Map<Id, Product2>();
    if (rows == null) {
      return mapped;
    }
    for (SObject row : rows) {
      mapped.put(row.Id, (Product2) row);
    }
    return mapped;
  }

  private static Map<Id, ContractHistory__c> toHistoryMap(List<SObject> rows) {
    Map<Id, ContractHistory__c> mapped = new Map<Id, ContractHistory__c>();
    if (rows == null) {
      return mapped;
    }
    for (SObject row : rows) {
      mapped.put(row.Id, (ContractHistory__c) row);
    }
    return mapped;
  }

  private static Map<Id, Opportunity> toOpportunityMap(List<SObject> rows) {
    Map<Id, Opportunity> mapped = new Map<Id, Opportunity>();
    if (rows == null) {
      return mapped;
    }
    for (SObject row : rows) {
      mapped.put(row.Id, (Opportunity) row);
    }
    return mapped;
  }

  private static Map<Id, BillingAccount__c> toBillingAccountMap(
    List<SObject> rows
  ) {
    Map<Id, BillingAccount__c> mapped = new Map<Id, BillingAccount__c>();
    if (rows == null) {
      return mapped;
    }
    for (SObject row : rows) {
      mapped.put(row.Id, (BillingAccount__c) row);
    }
    return mapped;
  }

  private static Map<Id, Account> toAccountMap(List<SObject> rows) {
    Map<Id, Account> mapped = new Map<Id, Account>();
    if (rows == null) {
      return mapped;
    }
    for (SObject row : rows) {
      mapped.put(row.Id, (Account) row);
    }
    return mapped;
  }

  private static Boolean hasAllQueriedFields(
    SObject record,
    Set<String> fieldNames
  ) {
    if (record == null || fieldNames == null) {
      return false;
    }
    for (String fieldName : fieldNames) {
      if (String.isBlank(fieldName) || fieldName.contains('.')) {
        return false;
      }
      try {
        record.get(fieldName);
      } catch (SObjectException ex) {
        return false;
      }
    }
    return true;
  }

  /**
   * 仕様: Accounting 第8.2節。
   * Diff保存後のCurrentは保存結果で置き、仕訳を取り直さない。
   */
  private static void rememberCurrentAfterPersist(
    Id invoiceId,
    List<GlJournal__c> current,
    PersistPlan plan
  ) {
    Map<Id, GlJournal__c> byId = new Map<Id, GlJournal__c>();
    if (current != null) {
      for (GlJournal__c row : current) {
        if (row != null && row.Id != null) {
          byId.put(row.Id, row);
        }
      }
    }
    if (plan != null) {
      if (plan.logicalDeletes != null) {
        for (GlJournal__c row : plan.logicalDeletes) {
          if (row != null && row.Id != null) {
            byId.put(row.Id, row);
          }
        }
      }
      if (plan.reversals != null) {
        for (GlJournal__c row : plan.reversals) {
          if (row != null && row.Id != null) {
            byId.put(row.Id, row);
          }
        }
      }
      if (plan.inserts != null) {
        for (GlJournal__c row : plan.inserts) {
          if (row != null && row.Id != null) {
            byId.put(row.Id, row);
          }
        }
      }
    }
    AccountingCurrentService.replace(invoiceId, byId.values());
  }

  private static List<SObject> queryCopySources(
    String objectApiName,
    Set<Id> recordIds,
    Set<String> extraFields
  ) {
    if (
      recordIds == null ||
      recordIds.isEmpty() ||
      String.isBlank(objectApiName)
    ) {
      return new List<SObject>();
    }
    Schema.SObjectType sobjectType = Schema.getGlobalDescribe()
      .get(objectApiName);
    if (sobjectType == null) {
      return new List<SObject>();
    }
    Map<String, Schema.SObjectField> fieldMap = sobjectType.getDescribe()
      .fields.getMap();
    Set<String> names = new Set<String>{ 'Id' };
    if (extraFields != null) {
      names.addAll(extraFields);
    }
    names.addAll(FieldCopyDefinitionService.sourceFieldApiNames(objectApiName));
    List<String> selectFields = new List<String>();
    Set<String> used = new Set<String>();
    for (String fieldApiName : names) {
      if (String.isBlank(fieldApiName)) {
        continue;
      }
      String key = fieldApiName.toLowerCase();
      if (used.contains(key)) {
        continue;
      }
      if (!fieldMap.containsKey(fieldApiName) && !fieldApiName.contains('.')) {
        continue;
      }
      used.add(key);
      selectFields.add(fieldApiName);
    }
    if (selectFields.isEmpty()) {
      selectFields.add('Id');
    }
    selectFields.sort();
    copySourceSelectCount++;
    if (objectApiName == 'Invoice__c') {
      invoiceCopySourceSelectCount++;
    }
    return Database.query(
      'SELECT ' +
        String.join(selectFields, ',') +
        ' FROM ' +
        String.escapeSingleQuotes(objectApiName) +
        ' WHERE Id IN :recordIds WITH SYSTEM_MODE'
    );
  }

  /** 仕様: Core 第11.4.2節。明細仕訳の From は明細・見積商品・商品・入出金・割当・請求書・請求アカウント・契約履歴・商談・取引先。 */
  private static void applyJournalCopy(
    GlJournal__c journal,
    CopySourceBundle bundle
  ) {
    Map<String, SObject> sources = new Map<String, SObject>();
    if (bundle != null && bundle.invoice != null) {
      sources.put('Invoice__c', bundle.invoice);
      Id billingId = bundle.invoice.BillingAccountSnapShot__c;
      if (billingId != null && bundle.billingAccounts.containsKey(billingId)) {
        sources.put('BillingAccount__c', bundle.billingAccounts.get(billingId));
      }
      Id historyId = bundle.invoice.ContractHistory__c;
      if (historyId != null && bundle.histories.containsKey(historyId)) {
        ContractHistory__c history = bundle.histories.get(historyId);
        sources.put('ContractHistory__c', history);
        if (
          history.Opportunity__c != null &&
          bundle.opportunities.containsKey(history.Opportunity__c)
        ) {
          Opportunity opportunity = bundle.opportunities.get(
            history.Opportunity__c
          );
          sources.put('Opportunity', opportunity);
          if (
            opportunity.AccountId != null &&
            bundle.accounts.containsKey(opportunity.AccountId)
          ) {
            sources.put('Account', bundle.accounts.get(opportunity.AccountId));
          }
        }
      }
      if (
        !sources.containsKey('Account') &&
        billingId != null &&
        bundle.billingAccounts.containsKey(billingId)
      ) {
        BillingAccount__c billingAccount = bundle.billingAccounts.get(
          billingId
        );
        if (
          billingAccount.Account__c != null &&
          bundle.accounts.containsKey(billingAccount.Account__c)
        ) {
          sources.put(
            'Account',
            bundle.accounts.get(billingAccount.Account__c)
          );
        }
      }
    }
    if (
      journal.InvoiceLine__c != null &&
      bundle != null &&
      bundle.lines.containsKey(journal.InvoiceLine__c)
    ) {
      InvoiceLine__c line = bundle.lines.get(journal.InvoiceLine__c);
      sources.put('InvoiceLine__c', line);
      if (
        line.ContractProduct__c != null &&
        bundle.contractProducts.containsKey(line.ContractProduct__c)
      ) {
        ContractProduct__c contractProduct = bundle.contractProducts.get(
          line.ContractProduct__c
        );
        sources.put('ContractProduct__c', contractProduct);
        if (
          line.Product__c == null &&
          contractProduct.Product__c != null &&
          bundle.products.containsKey(contractProduct.Product__c)
        ) {
          sources.put(
            'Product2',
            bundle.products.get(contractProduct.Product__c)
          );
        }
      }
      if (
        line.Product__c != null && bundle.products.containsKey(line.Product__c)
      ) {
        sources.put('Product2', bundle.products.get(line.Product__c));
      }
    }
    if (
      journal.InvoicePayment__c != null &&
      bundle != null &&
      bundle.payments.containsKey(journal.InvoicePayment__c)
    ) {
      sources.put(
        'InvoicePayment__c',
        bundle.payments.get(journal.InvoicePayment__c)
      );
    }
    if (
      journal.InvoicePaymentAllocation__c != null &&
      bundle != null &&
      bundle.allocations.containsKey(journal.InvoicePaymentAllocation__c)
    ) {
      sources.put(
        'InvoicePaymentAllocation__c',
        bundle.allocations.get(journal.InvoicePaymentAllocation__c)
      );
    }
    FieldCopyDefinitionService.apply(
      journal,
      'GlJournal__c',
      journalCopyContext(journal),
      sources
    );
  }

  /** 仕様: Core 第11.4.2節。明細または割当がある仕訳は明細仕訳。 */
  @TestVisible
  static String journalCopyContext(GlJournal__c journal) {
    if (
      journal != null &&
      (journal.InvoiceLine__c != null ||
      journal.InvoicePaymentAllocation__c != null)
    ) {
      return FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL;
    }
    return FieldCopyDefinitionService.CONTEXT_NON_LINE_JOURNAL;
  }

  private static Map<String, String> hashedKeysByJoined;

  /** 仕様: Accounting 第8.7節、第9.1節。ダイジェスト結果は変えない。同一処理の同じ結合文字列は取り直さない。 */
  public static String hashKey(List<String> parts) {
    String joined = 'V1';
    if (parts != null) {
      for (String part : parts) {
        joined += String.isBlank(part) ? '-' : part;
      }
    }
    if (hashedKeysByJoined != null && hashedKeysByJoined.containsKey(joined)) {
      return hashedKeysByJoined.get(joined);
    }
    String digest = EncodingUtil.convertToHex(
        Crypto.generateDigest('SHA-256', Blob.valueOf(joined))
      )
      .toLowerCase();
    if (hashedKeysByJoined == null) {
      hashedKeysByJoined = new Map<String, String>();
    }
    hashedKeysByJoined.put(joined, digest);
    return digest;
  }
}
