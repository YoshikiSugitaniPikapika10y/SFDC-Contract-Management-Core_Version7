public without sharing class AccountingDiffService {
  public class DiffException extends Exception {
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
    if (invoiceId == null) {
      throw new DiffException('請求が指定されていません。');
    }
    // 仕様: Core 第11.4.2節
    FieldCopyDefinitionService.validateAllDefinitions();
    AccountingEventFixedCatalog.require(eventKey);
    if (String.isBlank(operationKey)) {
      throw new DiffException('業務操作キーがありません。');
    }
    Invoice__c invoice = AccountingCauseLockService.lockInvoice(invoiceId);
    GlAccountingPolicy__c policy = eventKey == AccountingEventFixedCatalog.BILLING_CONFIRMED.key
      ? GlAccountingPolicyService.freezeOnFirstConfirm()
      : GlAccountingPolicyService.requireOrgPolicy();
    List<GlJournal__c> current = AccountingCurrentService.load(invoiceId);
    assertCurrentIntegrity(current);
    if (policy.AccountingEnabled__c != true) {
      if (isCancelEvent(eventKey)) {
        cancelCurrent(invoiceId, current, eventKey, operationKey, cancellationDate);
      }
      return;
    }
    if (
      !InvoiceTransactionStatusService.isConfirmed(invoice) &&
      !InvoiceTransactionStatusService.isCancelled(invoice)
    ) {
      return;
    }
    List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
      invoice,
      policy,
      current
    );
    persistDiff(invoice, goals, current, eventKey, operationKey, cancellationDate);
    persistHistoricalBreakdown(goals);
    AccountingTagEvaluationService.evaluateForInvoice(invoiceId);
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
    Map<String, GlJournal__c> activeByLine = new Map<String, GlJournal__c>();
    for (GlJournal__c journal : current) {
      if (journal.TransactionStatus__c == 'Active') {
        if (activeByLine.containsKey(journal.JournalLineKey__c)) {
          throw new DiffException('同じ仕訳行キーがCurrent内で重複しています。');
        }
        activeByLine.put(journal.JournalLineKey__c, journal);
      }
    }
    Map<Id, InvoiceLine__c> lineById = loadCopyLines(goals);
    Map<Id, InvoicePayment__c> paymentById = loadCopyPayments(goals);
    Set<String> goalKeys = new Set<String>();
    PersistPlan plan = new PersistPlan();
    plan.inserts = new List<GlJournal__c>();
    plan.logicalDeletes = new List<GlJournal__c>();
    plan.reversals = new List<GlJournal__c>();
    for (AccountingGoalService.GoalJournal goal : goals) {
      GlJournal__c next = goal.record;
      next.AccountingEventKey__c = eventKey;
      next.BusinessOperationKey__c = operationKey;
      applyJournalCopy(next, invoice, lineById, paymentById);
      goalKeys.add(next.JournalLineKey__c);
      GlJournal__c existing = activeByLine.get(next.JournalLineKey__c);
      if (existing == null) {
        next.IdempotencyKey__c = idempotencyKey(goal, operationKey, next.JournalLineKey__c);
        plan.inserts.add(next);
        continue;
      }
      if (sameContent(existing, next)) {
        continue;
      }
      if (existing.IsLocked__c == true) {
        plan.reversals.add(existing);
        next.IdempotencyKey__c = idempotencyKey(goal, operationKey, next.JournalLineKey__c);
        plan.inserts.add(next);
      } else {
        existing.TransactionStatus__c = 'LogicallyDeleted';
        plan.logicalDeletes.add(existing);
        next.IdempotencyKey__c = idempotencyKey(goal, operationKey, next.JournalLineKey__c);
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
    PersistPlan plan = collectPersistDiff(
      invoice,
      goals,
      current,
      eventKey,
      operationKey
    );
    Boolean previous = GlJournalTriggerHandler.allowEngineWrite;
    GlJournalTriggerHandler.allowEngineWrite = true;
    try {
      if (isCancelEvent(eventKey)) {
        applyCancelAuditToJournals(plan.logicalDeletes, invoice.Id, eventKey, operationKey);
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
          applyCancelAuditToJournal(original, invoice.Id, eventKey, operationKey);
        }
      }
      if (!plan.reversals.isEmpty()) {
        update plan.reversals;
      }
      if (!plan.inserts.isEmpty()) {
        insert plan.inserts;
      }
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
    if (invoiceId == null) {
      throw new DiffException('請求が指定されていません。');
    }
    AccountingEventFixedCatalog.require(eventKey);
    Invoice__c invoice = AccountingCauseLockService.lockInvoice(invoiceId);
    GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
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
    List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
      invoice,
      policy,
      current
    );
    PersistPlan plan = collectPersistDiff(
      invoice,
      goals,
      current,
      eventKey,
      'PREVIEW'
    );
    return previewFromPlan(plan.logicalDeletes, plan.reversals, cancellationDate);
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
    Set<Id> activePayments = activePaymentIds(current);
    Set<Id> activeHeaders = activeHeaderIds(current);
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
    if (!locked.isEmpty() && cancellationDate == null) {
      throw new DiffException('ロック済み仕訳がある取消では取消基準日が必要です。');
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

  private static CancelPreview emptyPreview() {
    return previewFromPlan(new List<GlJournal__c>(), new List<GlJournal__c>(), null);
  }

  private static CancelPreview previewFromPlan(
    List<GlJournal__c> logicalDeletes,
    List<GlJournal__c> reversals,
    Date cancellationDate
  ) {
    if (!reversals.isEmpty() && cancellationDate == null) {
      throw new DiffException('ロック済み仕訳がある取消では取消基準日が必要です。');
    }
    CancelPreview preview = new CancelPreview();
    preview.logicalDeleteCount = logicalDeletes == null ? 0 : logicalDeletes.size();
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
    if (preview.reverseDateCounts == null || preview.reverseDateCounts.isEmpty()) {
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
    lines.add('将来日付: ' + (preview.hasFutureReverseDate == true ? 'あり' : 'なし'));
    return String.join(lines, '\n');
  }

  private static Boolean isCancelEvent(String eventKey) {
    return eventKey == AccountingEventFixedCatalog.BILLING_CANCELLED.key ||
      eventKey == AccountingEventFixedCatalog.PAYMENT_CANCELLED.key ||
      eventKey == AccountingEventFixedCatalog.MANUAL_JOURNAL.key;
  }

  /** 仕様: Accounting 第2.4節、第8.2節、第8.5節、第8.8節、Core 第7.9.3節・第7.9.5節 */
  private static void cancelCurrent(
    Id invoiceId,
    List<GlJournal__c> current,
    String eventKey,
    String operationKey,
    Date cancellationDate
  ) {
    Set<Id> activePayments = activePaymentIds(current);
    Set<Id> activeHeaders = activeHeaderIds(current);
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
    if (!locked.isEmpty() && cancellationDate == null) {
      throw new DiffException('ロック済み仕訳がある取消では取消基準日が必要です。');
    }
    applyCancelAuditToJournals(unlocked, invoiceId, eventKey, operationKey);
    Boolean previous = GlJournalTriggerHandler.allowEngineWrite;
    GlJournalTriggerHandler.allowEngineWrite = true;
    try {
      if (!unlocked.isEmpty()) {
        update unlocked;
      }
      List<GlJournal__c> inserts = new List<GlJournal__c>();
      for (GlJournal__c original : locked) {
        CancelReasonSnapshot reason = cancelReasonOf(original, invoiceId, eventKey);
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
      List<Invoice__c> invoices = Database.query(
        'SELECT CancellationReason__c, CancellationReasonText__c ' +
          'FROM Invoice__c WHERE Id = :invoiceId WITH SYSTEM_MODE LIMIT 1'
      );
      if (!invoices.isEmpty()) {
        snapshot.reason = (String) invoices[0].get('CancellationReason__c');
        snapshot.reasonText = (String) invoices[0].get('CancellationReasonText__c');
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
    for (GlJournal__c journal : journals) {
      applyCancelAuditToJournal(journal, invoiceId, eventKey, operationKey);
    }
  }

  private static void applyCancelAuditToJournal(
    GlJournal__c journal,
    Id invoiceId,
    String eventKey,
    String operationKey
  ) {
    if (journal == null) {
      return;
    }
    journal.BusinessOperationKey__c = operationKey;
    CancelReasonSnapshot reason = cancelReasonOf(journal, invoiceId, eventKey);
    if (!String.isBlank(reason.reason)) {
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
      return journal.InvoicePayment__c != null && !activePayments.contains(journal.InvoicePayment__c);
    }
    if (eventKey == AccountingEventFixedCatalog.MANUAL_JOURNAL.key) {
      return journal.GlManualJournalHeader__c != null &&
        !activeHeaders.contains(journal.GlManualJournalHeader__c);
    }
    return false;
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
        reversalsByOriginal.put(journal.OriginalJournal__c, new List<GlJournal__c>());
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
      throw new DiffException('ロック済み仕訳の逆仕訳には取消基準日が必要です。');
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
    reversal.IsLocked__c = false;
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
  private static Date reversalDateOf(GlJournal__c original, Date cancellationDate) {
    return cancellationDate >= original.PostingDate__c
      ? cancellationDate
      : original.PostingDate__c;
  }

  /** 仕様: Accounting 第4.4節、第5.2.15節、第5.2.16節、第8.2節、第8.4節、Core 第8.6節 */
  private static void persistHistoricalBreakdown(List<AccountingGoalService.GoalJournal> goals) {
    if (goals == null || goals.isEmpty()) {
      return;
    }
    Id invoiceId = goals[0].record == null ? null : goals[0].record.Invoice__c;
    if (invoiceId == null) {
      return;
    }
    Map<Id, InvoicePaymentAllocation__c> updates = new Map<Id, InvoicePaymentAllocation__c>();
    for (InvoicePaymentAllocation__c allocation : [
      SELECT Id, Amount__c, HistoricalUacAmount__c, HistoricalSpAmount__c
      FROM InvoicePaymentAllocation__c
      WHERE
        InvoicePayment__r.Invoice__c = :invoiceId
        AND InvoicePayment__r.PaymentTransactionStatus__c = 'Active'
        AND InvoicePayment__r.PaymentPurpose__c = 'Invoice'
      WITH SYSTEM_MODE
    ]) {
      allocation.HistoricalUacAmount__c = 0;
      allocation.HistoricalSpAmount__c = 0;
      updates.put(allocation.Id, allocation);
    }
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
      InvoicePaymentAllocation__c allocation = updates.get(journal.InvoicePaymentAllocation__c);
      if (allocation == null) {
        allocation = new InvoicePaymentAllocation__c(
          Id = journal.InvoicePaymentAllocation__c,
          HistoricalUacAmount__c = 0,
          HistoricalSpAmount__c = 0
        );
        updates.put(allocation.Id, allocation);
      }
      Decimal magnitude = nvl(journal.Amount__c);
      String counterpart = journal.DebitSlotKey__c == AccountingSlotFixedCatalog.Cash.key
        ? journal.CreditSlotKey__c
        : journal.DebitSlotKey__c;
      if (counterpart == AccountingSlotFixedCatalog.UnappliedCash.key) {
        Decimal signed = negativeCash ? -magnitude : magnitude;
        allocation.HistoricalUacAmount__c = nvl(allocation.HistoricalUacAmount__c) + signed;
      }
      if (counterpart == AccountingSlotFixedCatalog.SuspensePayment.key) {
        Decimal signed = negativeCash ? magnitude : -magnitude;
        allocation.HistoricalSpAmount__c = nvl(allocation.HistoricalSpAmount__c) + signed;
      }
    }
    for (InvoicePaymentAllocation__c allocation : updates.values()) {
      Decimal uac = nvl(allocation.HistoricalUacAmount__c);
      Decimal sp = nvl(allocation.HistoricalSpAmount__c);
      if (uac == 0 && sp == 0) {
        continue;
      }
      if (allocation.Amount__c != uac - sp) {
        throw new DiffException('過去日Invoiceの明細別割当内訳が割当額と一致しません。');
      }
      if (allocation.Amount__c > 0 && (uac < 0 || sp > 0)) {
        throw new DiffException('正額の過去日Invoice割当の振替内訳の符号が不正です。');
      }
      if (allocation.Amount__c < 0 && (uac > 0 || sp < 0)) {
        throw new DiffException('負額の過去日Invoice割当の振替内訳の符号が不正です。');
      }
    }
    if (!updates.isEmpty()) {
      Boolean previous = InvoicePaymentAllocationService.allowHistoricalAmountWrite;
      InvoicePaymentAllocationService.allowHistoricalAmountWrite = true;
      try {
        update updates.values();
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

  private static Boolean sameCopyFields(GlJournal__c current, GlJournal__c goal) {
    Set<String> screenFields = InvoiceOpsFieldService.journalScreenFieldApiNames();
    for (String fieldName : FieldCopyDefinitionService.targetFieldApiNames('GlJournal__c')) {
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

  private static String idempotencyKey(
    AccountingGoalService.GoalJournal goal,
    String operationKey,
    String journalLineKey
  ) {
    if (goal != null && goal.isManual && goal.record.GlManualJournalHeader__c != null) {
      return hashKey(
        new List<String>{
          'MAN',
          String.valueOf(goal.record.GlManualJournalHeader__c),
          'ORIGINAL'
        }
      );
    }
    return hashKey(new List<String>{ operationKey, journalLineKey, 'ORIGINAL' });
  }

  private static Map<Id, InvoiceLine__c> loadCopyLines(
    List<AccountingGoalService.GoalJournal> goals
  ) {
    Set<Id> ids = new Set<Id>();
    for (AccountingGoalService.GoalJournal goal : goals) {
      if (goal.record.InvoiceLine__c != null) {
        ids.add(goal.record.InvoiceLine__c);
      }
    }
    if (ids.isEmpty()) {
      return new Map<Id, InvoiceLine__c>();
    }
    return new Map<Id, InvoiceLine__c>(
      [
        SELECT Id, Invoice__c, ContractProduct__c, Product__c, Amount__c
        FROM InvoiceLine__c
        WHERE Id IN :ids
        WITH SYSTEM_MODE
      ]
    );
  }

  private static Map<Id, InvoicePayment__c> loadCopyPayments(
    List<AccountingGoalService.GoalJournal> goals
  ) {
    Set<Id> ids = new Set<Id>();
    for (AccountingGoalService.GoalJournal goal : goals) {
      if (goal.record.InvoicePayment__c != null) {
        ids.add(goal.record.InvoicePayment__c);
      }
    }
    if (ids.isEmpty()) {
      return new Map<Id, InvoicePayment__c>();
    }
    return new Map<Id, InvoicePayment__c>(
      [
        SELECT Id, Invoice__c, Amount__c, PaymentPurpose__c, PaymentDate__c
        FROM InvoicePayment__c
        WHERE Id IN :ids
        WITH SYSTEM_MODE
      ]
    );
  }

  private static void applyJournalCopy(
    GlJournal__c journal,
    Invoice__c invoice,
    Map<Id, InvoiceLine__c> lineById,
    Map<Id, InvoicePayment__c> paymentById
  ) {
    Map<String, SObject> sources = new Map<String, SObject>{ 'Invoice__c' => invoice };
    if (journal.InvoiceLine__c != null && lineById.containsKey(journal.InvoiceLine__c)) {
      sources.put('InvoiceLine__c', lineById.get(journal.InvoiceLine__c));
    }
    if (journal.InvoicePayment__c != null && paymentById.containsKey(journal.InvoicePayment__c)) {
      sources.put('InvoicePayment__c', paymentById.get(journal.InvoicePayment__c));
    }
    String context = journal.InvoiceLine__c == null
      ? FieldCopyDefinitionService.CONTEXT_NON_LINE_JOURNAL
      : FieldCopyDefinitionService.CONTEXT_LINE_JOURNAL;
    FieldCopyDefinitionService.apply(journal, 'GlJournal__c', context, sources);
  }

  /** 仕様: Accounting 第8.7節、第9.1節 */
  public static String hashKey(List<String> parts) {
    String joined = 'V1';
    if (parts != null) {
      for (String part : parts) {
        joined += String.isBlank(part) ? '-' : part;
      }
    }
    return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(joined)))
      .toLowerCase();
  }
}
