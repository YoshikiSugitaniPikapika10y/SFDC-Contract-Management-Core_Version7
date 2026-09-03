public without sharing class AccountingGoalService {
  public class GoalException extends Exception {
  }

  public class GoalJournal {
    public GlJournal__c record;
    public String candidateKey;
    public String allocatedSlotKey;
    public Boolean isManual;
  }

  private class Candidate {
    Invoice__c invoice;
    InvoiceLine__c line;
    InvoicePayment__c payment;
    InvoicePaymentAllocation__c allocation;
    GlManualJournalHeader__c header;
    GlManualJournalSetting__c setting;
    JournalPatternFixedCatalog.Definition pattern;
    AccountingCatalogTypes.JournalCandidateRole role;
    Integer recognitionSequence;
    Date postingDate;
    Decimal amount;
    Integer sameDayOrder;
    String candidateKey;
    Datetime causeCreatedDate;
    Id causeRecordId;
    String debitSlotKey;
    String creditSlotKey;
    Id debitAssignmentId;
    Id creditAssignmentId;
    Id debitAccountId;
    Id creditAccountId;
    Boolean isManual;
  }

  private class LineBook {
    Decimal billedBody = 0;
    Decimal billedTax = 0;
    Decimal recognizedBody = 0;
    Decimal recognizedTax = 0;
    Decimal paid = 0;
    Map<String, Decimal> slots = new Map<String, Decimal>();
    Map<String, Map<String, AccountStamp>> accountStamps = new Map<String, Map<String, AccountStamp>>();
  }

  private class AccountStamp {
    Id accountId;
    Id assignmentId;
    String originKind;
    Decimal signedAmount;
  }

  /** 仕様: Accounting 第8.2節、第8.3節、第8.4節、第4.4節、第4.6節、第5.6節、第5.7節、第8.7節 */
  public static List<GoalJournal> build(
    Invoice__c invoice,
    GlAccountingPolicy__c policy,
    List<GlJournal__c> currentJournals
  ) {
    if (invoice == null || policy == null) {
      throw new GoalException('Goalの対象請求または会計方針がありません。');
    }
    if (InvoiceTransactionStatusService.isCancelled(invoice)) {
      return new List<GoalJournal>();
    }
    Set<String> allowed = GlAccountingPolicyService.deriveAllowedPatternKeys(policy);
    Map<String, String> reusedPatterns = reusedPatternsByCandidate(currentJournals);
    Map<Id, InvoiceLine__c> lines = loadLines(invoice.Id);
    Map<Id, InvoicePayment__c> payments = loadPayments(invoice.Id);
    List<InvoicePaymentAllocation__c> allocations = loadAllocations(payments.keySet());
    List<GlManualJournalHeader__c> headers = loadManualHeaders(invoice.Id);
    Map<Id, GlManualJournalSetting__c> settings = loadSettings(headers);
    List<Candidate> candidates = new List<Candidate>();
    for (InvoiceLine__c line : lines.values()) {
      candidates.addAll(
        lineCandidates(invoice, line, policy, allowed, reusedPatterns)
      );
    }
    for (InvoicePayment__c payment : payments.values()) {
      if (payment.PaymentPurpose__c == InvoicePaymentService.PURPOSE_NON_INVOICE) {
        addPaymentCandidate(
          candidates,
          invoice,
          null,
          payment,
          null,
          allowed,
          reusedPatterns
        );
      }
    }
    for (InvoicePaymentAllocation__c allocation : allocations) {
      addPaymentCandidate(
        candidates,
        invoice,
        lines.get(allocation.InvoiceLine__c),
        payments.get(allocation.InvoicePayment__c),
        allocation,
        allowed,
        reusedPatterns
      );
    }
    for (GlManualJournalHeader__c header : headers) {
      candidates.add(manualCandidate(invoice, header, settings.get(header.GlManualJournalSetting__c)));
    }
    sortCandidates(candidates);
    Map<Id, LineBook> books = new Map<Id, LineBook>();
    LineBook invoiceBook = new LineBook();
    Map<Id, Decimal> uacByAllocation = new Map<Id, Decimal>();
    Map<Id, Decimal> spByAllocation = new Map<Id, Decimal>();
    List<GoalJournal> goals = new List<GoalJournal>();
    Set<String> lineKeys = new Set<String>();
    for (Candidate candidate : candidates) {
      if (candidate.isManual) {
        // 仕様: Accounting 第4.6節・第8.2節手順6～7。手動も実行残高へ載せ、B／C／Pは増やさない。
        applySlotBalance(candidate, books, invoiceBook);
        addGoal(goals, lineKeys, toGoal(candidate, invoice, false));
        continue;
      }
      fillHistoricalTransferAmount(candidate, uacByAllocation, spByAllocation);
      List<Candidate> splits = resolveSplits(
        candidate,
        policy,
        books,
        invoiceBook,
        uacByAllocation,
        spByAllocation
      );
      applyFacts(candidate, books, policy);
      Boolean finalSettlement = isLineFinalSettlement(candidate, books);
      for (Candidate split : splits) {
        if (split.amount == null || split.amount == 0) {
          continue;
        }
        List<Candidate> accountSplits = splitByRealAccounts(
          split,
          books,
          invoiceBook,
          finalSettlement
        );
        for (Candidate accountSplit : accountSplits) {
          if (accountSplit.amount == null || accountSplit.amount == 0) {
            continue;
          }
          resolveAccounts(accountSplit, currentJournals);
          // 仕様: Accounting 第1.3節、第4.6節、第8.2節。分割後に負の候補だけ借貸反転した正額で実行残高へ載せる。
          applySlotBalance(accountSplit, books, invoiceBook);
          addGoal(goals, lineKeys, toGoal(accountSplit, invoice, true));
        }
      }
    }
    return goals;
  }

  private static void addGoal(
    List<GoalJournal> goals,
    Set<String> lineKeys,
    GoalJournal goal
  ) {
    if (lineKeys.contains(goal.record.JournalLineKey__c)) {
      throw new GoalException('同じ仕訳行キーがGoal内で重複しています。');
    }
    lineKeys.add(goal.record.JournalLineKey__c);
    goals.add(goal);
  }

  private static List<Candidate> lineCandidates(
    Invoice__c invoice,
    InvoiceLine__c line,
    GlAccountingPolicy__c policy,
    Set<String> allowed,
    Map<String, String> reusedPatterns
  ) {
    List<Candidate> rows = new List<Candidate>();
    addExclusiveCandidate(
      rows,
      invoice,
      line,
      null,
      null,
      0,
      invoice.InvoiceDate__c,
      line.Amount__c,
      AccountingCatalogTypes.ExclusiveGroup.BodyInvoice,
      AccountingCatalogTypes.JournalCandidateRole.InvoiceBody,
      allowed,
      reusedPatterns
    );
    addExclusiveCandidate(
      rows,
      invoice,
      line,
      null,
      null,
      0,
      invoice.InvoiceDate__c,
      nvl(line.AllocatedTaxAmount__c),
      AccountingCatalogTypes.ExclusiveGroup.TaxInvoice,
      AccountingCatalogTypes.JournalCandidateRole.InvoiceTax,
      allowed,
      reusedPatterns
    );
    List<Recognition> recognitions = recognitions(line, policy);
    for (Recognition recognition : recognitions) {
      addExclusiveCandidate(
        rows,
        invoice,
        line,
        null,
        null,
        recognition.sequence,
        recognition.postingDate,
        recognition.bodyAmount,
        AccountingCatalogTypes.ExclusiveGroup.BodyRevenue,
        AccountingCatalogTypes.JournalCandidateRole.RevenueBody,
        allowed,
        reusedPatterns
      );
      addExclusiveCandidate(
        rows,
        invoice,
        line,
        null,
        null,
        recognition.sequence,
        recognition.postingDate,
        recognition.taxAmount,
        AccountingCatalogTypes.ExclusiveGroup.TaxRevenue,
        AccountingCatalogTypes.JournalCandidateRole.RevenueTax,
        allowed,
        reusedPatterns
      );
    }
    return rows;
  }

  private static void addExclusiveCandidate(
    List<Candidate> rows,
    Invoice__c invoice,
    InvoiceLine__c line,
    InvoicePayment__c payment,
    InvoicePaymentAllocation__c allocation,
    Integer recognitionSequence,
    Date postingDate,
    Decimal sourceAmount,
    AccountingCatalogTypes.ExclusiveGroup exclusiveGroup,
    AccountingCatalogTypes.JournalCandidateRole role,
    Set<String> allowed,
    Map<String, String> reusedPatterns
  ) {
    if (sourceAmount == null || sourceAmount == 0) {
      return;
    }
    if (postingDate == null) {
      throw new GoalException('計上日が空のため仕訳を生成できません。');
    }
    String candidateKey = causeKey(
      invoice.Id,
      line == null ? null : line.Id,
      recognitionSequence,
      payment == null ? null : payment.Id,
      allocation == null ? null : allocation.Id,
      String.valueOf(role),
      null,
      null
    );
    JournalPatternFixedCatalog.Definition pattern = selectPattern(
      exclusiveGroup,
      role,
      candidateKey,
      invoice,
      line,
      payment,
      allocation,
      allowed,
      reusedPatterns
    );
    if (pattern == null) {
      return;
    }
    Decimal amount = resolveAmount(pattern, line, payment, allocation, sourceAmount, invoice);
    if (amount == null || amount == 0) {
      return;
    }
    Candidate candidate = new Candidate();
    candidate.invoice = invoice;
    candidate.line = line;
    candidate.payment = payment;
    candidate.allocation = allocation;
    candidate.pattern = pattern;
    candidate.role = role;
    candidate.recognitionSequence = recognitionSequence;
    candidate.postingDate = postingDate;
    candidate.amount = amount;
    candidate.sameDayOrder = pattern.sameDayOrder;
    candidate.candidateKey = candidateKey;
    assignCause(candidate, line, payment, allocation, null);
    candidate.debitSlotKey = pattern.debitSlot == null ? null : pattern.debitSlot.key;
    candidate.creditSlotKey = pattern.creditSlot == null ? null : pattern.creditSlot.key;
    candidate.isManual = false;
    rows.add(candidate);
  }

  private static void addPaymentCandidate(
    List<Candidate> rows,
    Invoice__c invoice,
    InvoiceLine__c line,
    InvoicePayment__c payment,
    InvoicePaymentAllocation__c allocation,
    Set<String> allowed,
    Map<String, String> reusedPatterns
  ) {
    if (payment == null) {
      return;
    }
    for (JournalPatternFixedCatalog.Definition pattern : JournalPatternFixedCatalog.values()) {
      if (!allowed.contains(pattern.key) || pattern.exclusiveGroup != null) {
        continue;
      }
      String candidateKey = causeKey(
        invoice.Id,
        line == null ? null : line.Id,
        0,
        payment.Id,
        allocation == null ? null : allocation.Id,
        String.valueOf(pattern.candidateRole),
        null,
        null
      );
      // 仕様: Accounting 第8.2節手順3・第8.7節。同じ原因候補キーの既存パターンを強制再利用する。
      String reused = reusedPatterns.get(candidateKey);
      if (reused != null && reused != pattern.key) {
        continue;
      }
      ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
      context.invoice = invoice;
      context.invoiceLine = line;
      context.invoicePayment = payment;
      context.allocation = allocation;
      if (reused == null && !ConditionEvaluationService.evaluate(pattern.conditionSet, context)) {
        continue;
      }
      Decimal amount = resolveAmount(pattern, line, payment, allocation, null, invoice);
      // 仕様: Accounting 第8.2節手順3〜6・第5.2.15節・第5.2.16節。
      // No.15／16は製品固定条件（Purpose＋入出金日＜請求日）通過後に候補化し、
      // 金額は現預金段階のあと同じ Goal のメモリ内訳で埋める。登録時0でも候補から落とさない。
      Boolean pendingHistorical =
        (pattern.amountItem == JournalAmountItemFixedCatalog.HistoricalUacAmount ||
          pattern.amountItem == JournalAmountItemFixedCatalog.HistoricalSpAmount) &&
        (amount == null || amount == 0);
      if ((amount == null || amount == 0) && !pendingHistorical) {
        continue;
      }
      if (pattern.postingDateItem == JournalPostingDateFixedCatalog.PaymentDate && payment.PaymentDate__c == null) {
        throw new GoalException('入出金日が空のため仕訳を生成できません。');
      }
      if (pattern.postingDateItem == JournalPostingDateFixedCatalog.BillingDate && invoice.InvoiceDate__c == null) {
        throw new GoalException('請求日が空のため仕訳を生成できません。');
      }
      Candidate candidate = new Candidate();
      candidate.invoice = invoice;
      candidate.line = line;
      candidate.payment = payment;
      candidate.allocation = allocation;
      candidate.pattern = pattern;
      candidate.role = pattern.candidateRole;
      candidate.recognitionSequence = 0;
      candidate.postingDate = pattern.postingDateItem == JournalPostingDateFixedCatalog.BillingDate
        ? invoice.InvoiceDate__c
        : payment.PaymentDate__c;
      candidate.amount = amount;
      candidate.sameDayOrder = pattern.sameDayOrder;
      assignCause(candidate, line, payment, allocation, null);
      candidate.candidateKey = candidateKey;
      candidate.debitSlotKey = pattern.debitSlot == null ? null : pattern.debitSlot.key;
      candidate.creditSlotKey = pattern.creditSlot == null ? null : pattern.creditSlot.key;
      candidate.isManual = false;
      rows.add(candidate);
    }
  }

  private static Candidate manualCandidate(
    Invoice__c invoice,
    GlManualJournalHeader__c header,
    GlManualJournalSetting__c setting
  ) {
    if (setting == null) {
      throw new GoalException('手動仕訳設定がありません。');
    }
    if (header.PostingDate__c == null) {
      throw new GoalException('手動仕訳の計上日が空です。');
    }
    if (header.Amount__c == null || header.Amount__c <= 0) {
      throw new GoalException('手動仕訳の金額は0より大きい整数です。');
    }
    Candidate candidate = new Candidate();
    candidate.invoice = invoice;
    candidate.header = header;
    candidate.setting = setting;
    candidate.role = null;
    candidate.recognitionSequence = 0;
    candidate.postingDate = header.PostingDate__c;
    candidate.amount = header.Amount__c;
    candidate.sameDayOrder = 80;
    assignCause(candidate, null, null, null, header);
    candidate.candidateKey = causeKey(
      invoice.Id,
      null,
      0,
      null,
      null,
      null,
      setting.Id,
      header.Id
    );
    candidate.debitSlotKey = setting.DebitSlotKey__c;
    candidate.creditSlotKey = setting.CreditSlotKey__c;
    candidate.debitAccountId = setting.DebitAccount__c;
    candidate.creditAccountId = setting.CreditAccount__c;
    candidate.isManual = true;
    return candidate;
  }

  /** 仕様: Accounting 第8.3節 */
  private static JournalPatternFixedCatalog.Definition selectPattern(
    AccountingCatalogTypes.ExclusiveGroup exclusiveGroup,
    AccountingCatalogTypes.JournalCandidateRole role,
    String candidateKey,
    Invoice__c invoice,
    InvoiceLine__c line,
    InvoicePayment__c payment,
    InvoicePaymentAllocation__c allocation,
    Set<String> allowed,
    Map<String, String> reusedPatterns
  ) {
    if (reusedPatterns.containsKey(candidateKey)) {
      return JournalPatternFixedCatalog.require(reusedPatterns.get(candidateKey));
    }
    JournalPatternFixedCatalog.Definition chosen = null;
    for (JournalPatternFixedCatalog.Definition pattern : JournalPatternFixedCatalog.values()) {
      if (!allowed.contains(pattern.key) || pattern.exclusiveGroup != exclusiveGroup) {
        continue;
      }
      if (pattern.candidateRole != role) {
        continue;
      }
      ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
      context.invoice = invoice;
      context.invoiceLine = line;
      context.invoicePayment = payment;
      context.allocation = allocation;
      if (!ConditionEvaluationService.evaluate(pattern.conditionSet, context)) {
        continue;
      }
      if (chosen == null || pattern.sortOrder < chosen.sortOrder) {
        chosen = pattern;
      }
    }
    return chosen;
  }

  /** 仕様: Accounting 第8.4節 */
  private static Decimal resolveAmount(
    JournalPatternFixedCatalog.Definition pattern,
    InvoiceLine__c line,
    InvoicePayment__c payment,
    InvoicePaymentAllocation__c allocation,
    Decimal sourceAmount,
    Invoice__c invoice
  ) {
    if (pattern.amountItem == JournalAmountItemFixedCatalog.InvoiceSubtotal) {
      return nvl(line == null ? null : line.Amount__c);
    }
    if (pattern.amountItem == JournalAmountItemFixedCatalog.AllocatedInvoiceTax) {
      return nvl(line == null ? null : line.AllocatedTaxAmount__c);
    }
    if (pattern.amountItem == JournalAmountItemFixedCatalog.RecognizedRevenue) {
      return sourceAmount;
    }
    if (pattern.amountItem == JournalAmountItemFixedCatalog.RecognizedTax) {
      return sourceAmount;
    }
    if (pattern.amountItem == JournalAmountItemFixedCatalog.PaymentAmount) {
      return payment == null ? 0 : payment.Amount__c;
    }
    if (pattern.amountItem == JournalAmountItemFixedCatalog.PaymentAllocationAmount) {
      return allocation == null ? 0 : allocation.Amount__c;
    }
    // 仕様: Accounting 第4.4節・第5.2.15節・第5.2.16節・第8.2節。
    // 登録時スナップショット（割当の保存値）は使わない。常に null。
    // 同じ Goal の現預金段階で決めた内訳は fillHistoricalTransferAmount（メモリ地図）で載せる。
    if (pattern.amountItem == JournalAmountItemFixedCatalog.HistoricalUacAmount) {
      return null;
    }
    if (pattern.amountItem == JournalAmountItemFixedCatalog.HistoricalSpAmount) {
      return null;
    }
    if (pattern.amountItem == JournalAmountItemFixedCatalog.InvoiceBodyCtaTransfer) {
      return sourceAmount;
    }
    if (pattern.amountItem == JournalAmountItemFixedCatalog.InvoiceTaxCtaTransfer) {
      return sourceAmount;
    }
    return sourceAmount;
  }

  /** 仕様: Accounting 第4.4節、第5.2.15節、第5.2.16節、第8.2節、第8.4節 */
  private static void fillHistoricalTransferAmount(
    Candidate candidate,
    Map<Id, Decimal> uacByAllocation,
    Map<Id, Decimal> spByAllocation
  ) {
    if (candidate.allocation == null || candidate.pattern == null) {
      return;
    }
    if (candidate.pattern.amountItem == JournalAmountItemFixedCatalog.HistoricalUacAmount) {
      candidate.amount = nvl(uacByAllocation.get(candidate.allocation.Id));
    }
    if (candidate.pattern.amountItem == JournalAmountItemFixedCatalog.HistoricalSpAmount) {
      candidate.amount = nvl(spByAllocation.get(candidate.allocation.Id));
    }
  }

  /** 仕様: Accounting 第4.4節、第4.6節、第6.2節 */
  private static List<Candidate> resolveSplits(
    Candidate candidate,
    GlAccountingPolicy__c policy,
    Map<Id, LineBook> books,
    LineBook invoiceBook,
    Map<Id, Decimal> uacByAllocation,
    Map<Id, Decimal> spByAllocation
  ) {
    if (candidate.pattern != null && candidate.pattern.amountItem == JournalAmountItemFixedCatalog.InvoiceBodyCtaTransfer) {
      candidate.amount = signedCtaTransfer(
        bookOf(books, candidate.line).recognizedBody,
        bookOf(books, candidate.line).billedBody,
        candidate.line
      );
      // 仕様: 第4.4節・第6.2節。本体由来CTA実行残高（作成元科目）を超えず、0なら候補なし。科目別分割は splitByRealAccounts。
      candidate.amount = capCtaTransferByStamps(
        candidate.amount,
        bookOf(books, candidate.line),
        'Body'
      );
    }
    if (candidate.pattern != null && candidate.pattern.amountItem == JournalAmountItemFixedCatalog.InvoiceTaxCtaTransfer) {
      candidate.amount = signedCtaTransfer(
        bookOf(books, candidate.line).recognizedTax,
        bookOf(books, candidate.line).billedTax,
        candidate.line
      );
      candidate.amount = capCtaTransferByStamps(
        candidate.amount,
        bookOf(books, candidate.line),
        'Tax'
      );
    }
    if (candidate.amount == null || candidate.amount == 0) {
      return new List<Candidate>();
    }
    if (candidate.pattern == null || candidate.pattern.slotPriorityType == null) {
      return new List<Candidate>{ candidate };
    }
    Boolean debitEmpty = candidate.debitSlotKey == null;
    String sourceKey = debitEmpty ? candidate.creditSlotKey : candidate.debitSlotKey;
    LineBook before = snapshot(bookOf(books, candidate.line));
    applyFacts(candidate, books, policy);
    LineBook after = snapshot(bookOf(books, candidate.line));
    revertFacts(candidate, books, policy);
    Decimal remaining = candidate.amount.abs();
    Integer sign = candidate.amount < 0 ? -1 : 1;
    List<Candidate> splits = new List<Candidate>();
    for (SlotPriorityRuleFixedCatalog.Definition rule : rulesOf(candidate.pattern.slotPriorityType)) {
      if (rule.sourceSlot.key != sourceKey || remaining <= 0) {
        continue;
      }
      Decimal capacity = capacityOf(
        policy,
        candidate,
        rule.targetSlot.key,
        before,
        after,
        invoiceBook
      );
      if (capacity <= 0) {
        continue;
      }
      Decimal take = remaining < capacity ? remaining : capacity;
      Candidate split = copyCandidate(candidate);
      split.amount = take * sign;
      if (debitEmpty) {
        split.debitSlotKey = rule.targetSlot.key;
      } else {
        split.creditSlotKey = rule.targetSlot.key;
      }
      rememberTemporary(split, uacByAllocation, spByAllocation);
      splits.add(split);
      remaining -= take;
    }
    if (remaining > 0) {
      throw new GoalException('スロット優先ルールで金額を説明できませんでした。');
    }
    return splits;
  }

  private static Candidate copyCandidate(Candidate source) {
    Candidate copy = new Candidate();
    copy.invoice = source.invoice;
    copy.line = source.line;
    copy.payment = source.payment;
    copy.allocation = source.allocation;
    copy.header = source.header;
    copy.setting = source.setting;
    copy.pattern = source.pattern;
    copy.role = source.role;
    copy.recognitionSequence = source.recognitionSequence;
    copy.postingDate = source.postingDate;
    copy.amount = source.amount;
    copy.sameDayOrder = source.sameDayOrder;
    copy.candidateKey = source.candidateKey;
    copy.causeCreatedDate = source.causeCreatedDate;
    copy.causeRecordId = source.causeRecordId;
    copy.debitSlotKey = source.debitSlotKey;
    copy.creditSlotKey = source.creditSlotKey;
    copy.debitAssignmentId = source.debitAssignmentId;
    copy.creditAssignmentId = source.creditAssignmentId;
    copy.debitAccountId = source.debitAccountId;
    copy.creditAccountId = source.creditAccountId;
    copy.isManual = source.isManual;
    return copy;
  }

  /** 仕様: Accounting 第4.4節、第5.2.13節、第5.2.14節、第8.2節、第8.4節 */
  private static void rememberTemporary(
    Candidate split,
    Map<Id, Decimal> uacByAllocation,
    Map<Id, Decimal> spByAllocation
  ) {
    if (split.allocation == null) {
      return;
    }
    // 仕様: Accounting 第4.4節・第5.2.14節。借貸反転前でも persistHistoricalBreakdown と同じ符号。
    Boolean negativeCash =
      split.pattern != null &&
      split.pattern.key ==
        JournalPatternFixedCatalog.PAYMENT_INVOICE_HISTORICAL_NEGATIVE_CASH.key;
    Boolean cashDebit = split.debitSlotKey == AccountingSlotFixedCatalog.Cash.key;
    String counterpart = cashDebit ? split.creditSlotKey : split.debitSlotKey;
    Decimal magnitude = split.amount == null ? 0 : split.amount.abs();
    if (counterpart == AccountingSlotFixedCatalog.UnappliedCash.key) {
      Decimal signed = negativeCash ? -magnitude : magnitude;
      uacByAllocation.put(
        split.allocation.Id,
        nvl(uacByAllocation.get(split.allocation.Id)) + signed
      );
    }
    if (counterpart == AccountingSlotFixedCatalog.SuspensePayment.key) {
      Decimal signed = negativeCash ? magnitude : -magnitude;
      spByAllocation.put(
        split.allocation.Id,
        nvl(spByAllocation.get(split.allocation.Id)) + signed
      );
    }
  }

  private static Decimal capacityOf(
    GlAccountingPolicy__c policy,
    Candidate candidate,
    String targetSlot,
    LineBook before,
    LineBook after,
    LineBook invoiceBook
  ) {
    AccountingCatalogTypes.SlotPriorityType type = candidate.pattern.slotPriorityType;
    if (
      type == AccountingCatalogTypes.SlotPriorityType.PositiveCashTemporaryAllocation ||
      type == AccountingCatalogTypes.SlotPriorityType.NegativeCashTemporaryAllocation
    ) {
      Decimal existing = nvl(invoiceBook.slots.get(targetSlot));
      if (targetSlot == AccountingSlotFixedCatalog.SuspensePayment.key) {
        return type == AccountingCatalogTypes.SlotPriorityType.PositiveCashTemporaryAllocation
          ? max(existing, 0)
          : Decimal.valueOf(999999999);
      }
      if (targetSlot == AccountingSlotFixedCatalog.UnappliedCash.key) {
        return type == AccountingCatalogTypes.SlotPriorityType.NegativeCashTemporaryAllocation
          ? max(existing, 0)
          : Decimal.valueOf(999999999);
      }
      return 0;
    }
    Decimal beforeTarget = targetOf(policy, before, targetSlot, candidate);
    Decimal afterTarget = targetOf(policy, after, targetSlot, candidate);
    Decimal delta = afterTarget - beforeTarget;
    // 仕様: Accounting 第4.6節・第6.2節。取り崩し容量は対象明細・符号方向・対象スロットに帰属する実行残高と目標差の小さい方。
    Decimal running = attributedSlotBalance(before, targetSlot, candidate);
    if (delta > 0) {
      return delta;
    }
    if (delta < 0) {
      Decimal draw = -delta;
      // 仕様: Accounting 第4.6節。正額と負額は同じ算法を符号方向へ正規化する。取り崩し上限は帰属残高の絶対値。
      Decimal available = nvl(running).abs();
      return available < draw ? available : draw;
    }
    return 0;
  }

  /**
   * 仕様: Accounting 第4.6節・第5.2.1節・第5.2.4節。
   * CTA目標は本体／税のB・Cを分ける。請求基準のDEFも本体／税に分ける。
   * 入金連動前受のDEF／ARは税込プールの合算B/Cのまま。
   */
  private static Decimal targetOf(
    GlAccountingPolicy__c policy,
    LineBook book,
    String slotKey,
    Candidate candidate
  ) {
    Decimal billed = book.billedBody + book.billedTax;
    Decimal recognized = book.recognizedBody + book.recognizedTax;
    Boolean billing = policy.RevenueRecognitionBasis__c == 'BillingBasis';
    if (
      slotKey == AccountingSlotFixedCatalog.ContractAsset.key ||
      (billing && slotKey == AccountingSlotFixedCatalog.DeferredRevenue.key)
    ) {
      if (isBodyFactRole(candidate)) {
        billed = book.billedBody;
        recognized = book.recognizedBody;
      } else if (isTaxFactRole(candidate)) {
        billed = book.billedTax;
        recognized = book.recognizedTax;
      }
    }
    Decimal paid = book.paid;
    if (slotKey == AccountingSlotFixedCatalog.ContractAsset.key) {
      return max(recognized - billed, 0);
    }
    if (slotKey == AccountingSlotFixedCatalog.AccountsReceivable.key) {
      return billing ? billed - paid : max(min(recognized, billed) - paid, 0);
    }
    if (slotKey == AccountingSlotFixedCatalog.DeferredRevenue.key) {
      return billing ? max(billed - recognized, 0) : max(paid - recognized, 0);
    }
    return 0;
  }

  /**
   * 仕様: Accounting 第4.6節・第6.2節。
   * 本体／税で濾るスロットは作成元スタンプ合計。それ以外はスロット実行残高。
   */
  private static Decimal attributedSlotBalance(
    LineBook book,
    String slotKey,
    Candidate candidate
  ) {
    String originKind = stampOriginKind(candidate, slotKey);
    if (originKind == null) {
      return nvl(book.slots.get(slotKey));
    }
    Decimal total = 0;
    for (AccountStamp stamp : drawdownBalances(book, slotKey, originKind)) {
      total += nvl(stamp.signedAmount);
    }
    return total;
  }

  private static Boolean isBodyFactRole(Candidate candidate) {
    return candidate != null &&
      (candidate.role == AccountingCatalogTypes.JournalCandidateRole.InvoiceBody ||
        candidate.role == AccountingCatalogTypes.JournalCandidateRole.RevenueBody);
  }

  private static Boolean isTaxFactRole(Candidate candidate) {
    return candidate != null &&
      (candidate.role == AccountingCatalogTypes.JournalCandidateRole.InvoiceTax ||
        candidate.role == AccountingCatalogTypes.JournalCandidateRole.RevenueTax);
  }

  /** 仕様: Accounting 第4.6節、第4.4節 */
  private static void applyFacts(
    Candidate candidate,
    Map<Id, LineBook> books,
    GlAccountingPolicy__c policy
  ) {
    LineBook book = bookOf(books, candidate.line);
    Integer dir = factSign(candidate.line);
    if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.InvoiceBody) {
      book.billedBody += nvl(candidate.line.Amount__c) * dir;
    } else if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.InvoiceTax) {
      Decimal tax = nvl(candidate.line.AllocatedTaxAmount__c) * dir;
      book.billedTax += tax;
      if (policy != null && policy.TaxRecognitionTiming__c == 'AtInvoice') {
        book.recognizedTax += tax;
      }
    } else if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.RevenueBody) {
      book.recognizedBody += nvl(candidate.amount) * dir;
    } else if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.RevenueTax) {
      book.recognizedTax += nvl(candidate.amount) * dir;
    } else if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.CurrentInvoicePayment) {
      // 仕様: Accounting 第4.6節。Pは明細方向へ正規化した非負。
      book.paid += nvl(candidate.amount) * dir;
    } else if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.HistoricalUacTransfer) {
      // 仕様: Accounting 第5.2.16節。正規化 HistoricalUacAmount__c を P へ加える。
      book.paid += nvl(candidate.amount) * dir;
    } else if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.HistoricalSpTransfer) {
      // 仕様: Accounting 第5.2.16節。正規化 -HistoricalSpAmount__c を P へ加える。
      book.paid += -nvl(candidate.amount) * dir;
    }
  }

  /** 仕様: Accounting 第4.6節、第4.4節 */
  private static void revertFacts(
    Candidate candidate,
    Map<Id, LineBook> books,
    GlAccountingPolicy__c policy
  ) {
    LineBook book = bookOf(books, candidate.line);
    Integer dir = factSign(candidate.line);
    if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.InvoiceBody) {
      book.billedBody -= nvl(candidate.line.Amount__c) * dir;
    } else if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.InvoiceTax) {
      Decimal tax = nvl(candidate.line.AllocatedTaxAmount__c) * dir;
      book.billedTax -= tax;
      if (policy != null && policy.TaxRecognitionTiming__c == 'AtInvoice') {
        book.recognizedTax -= tax;
      }
    } else if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.RevenueBody) {
      book.recognizedBody -= nvl(candidate.amount) * dir;
    } else if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.RevenueTax) {
      book.recognizedTax -= nvl(candidate.amount) * dir;
    } else if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.CurrentInvoicePayment) {
      book.paid -= nvl(candidate.amount) * dir;
    } else if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.HistoricalUacTransfer) {
      book.paid -= nvl(candidate.amount) * dir;
    } else if (candidate.role == AccountingCatalogTypes.JournalCandidateRole.HistoricalSpTransfer) {
      book.paid -= -nvl(candidate.amount) * dir;
    }
  }

  private static void applySlotBalance(
    Candidate candidate,
    Map<Id, LineBook> books,
    LineBook invoiceBook
  ) {
    // 仕様: Accounting 第1.3節、第4.6節、第8.2節。負の候補は借貸反転後の正額でスロット実行残高と科目スタンプを更新する。
    String debitSlot = candidate.debitSlotKey;
    String creditSlot = candidate.creditSlotKey;
    Id debitAccount = candidate.debitAccountId;
    Id creditAccount = candidate.creditAccountId;
    Id debitAssign = candidate.debitAssignmentId;
    Id creditAssign = candidate.creditAssignmentId;
    Decimal amount = candidate.amount;
    if (amount != null && amount < 0) {
      String swapSlot = debitSlot;
      debitSlot = creditSlot;
      creditSlot = swapSlot;
      Id swapAccount = debitAccount;
      debitAccount = creditAccount;
      creditAccount = swapAccount;
      Id swapAssign = debitAssign;
      debitAssign = creditAssign;
      creditAssign = swapAssign;
      amount = -amount;
    }
    LineBook lineBook = bookOf(books, candidate.line);
    addSlot(lineBook, debitSlot, amount, true);
    addSlot(lineBook, creditSlot, amount, false);
    addAccountStamp(
      lineBook,
      debitSlot,
      debitAccount,
      debitAssign,
      amount,
      true,
      stampOriginKind(candidate, debitSlot)
    );
    addAccountStamp(
      lineBook,
      creditSlot,
      creditAccount,
      creditAssign,
      amount,
      false,
      stampOriginKind(candidate, creditSlot)
    );
    addSlot(invoiceBook, debitSlot, amount, true);
    addSlot(invoiceBook, creditSlot, amount, false);
    // 仕様: Accounting 第5.2.11節・第5.2.12節・第6.2節。UAC／SP等の実勘定スタンプは請求書単位帳簿にも載せる。
    addAccountStamp(
      invoiceBook,
      debitSlot,
      debitAccount,
      debitAssign,
      amount,
      true,
      stampOriginKind(candidate, debitSlot)
    );
    addAccountStamp(
      invoiceBook,
      creditSlot,
      creditAccount,
      creditAssign,
      amount,
      false,
      stampOriginKind(candidate, creditSlot)
    );
  }

  /** 仕様: Accounting 第4.4節、第6.2節、第8.4節。AR・DEF・CTAの作成元割当・実勘定を残す。CTAは候補役割（本体／税）も分ける。 */
  private static void addAccountStamp(
    LineBook book,
    String slotKey,
    Id accountId,
    Id assignmentId,
    Decimal amount,
    Boolean debitSide,
    String originKind
  ) {
    if (String.isBlank(slotKey) || accountId == null || amount == null) {
      return;
    }
    if (!isAccountStampSlot(slotKey)) {
      return;
    }
    AccountingSlotFixedCatalog.Definition slot = AccountingSlotFixedCatalog.require(slotKey);
    Decimal signed = debitSide
      ? (slot.normalBalance == AccountingCatalogTypes.NormalBalance.Debit ? amount : -amount)
      : (slot.normalBalance == AccountingCatalogTypes.NormalBalance.Credit ? amount : -amount);
    if (!book.accountStamps.containsKey(slotKey)) {
      book.accountStamps.put(slotKey, new Map<String, AccountStamp>());
    }
    Map<String, AccountStamp> byAccount = book.accountStamps.get(slotKey);
    String stampKey =
      String.valueOf(accountId) +
      ':' +
      String.valueOf(assignmentId) +
      ':' +
      (originKind == null ? '' : originKind);
    AccountStamp stamp = byAccount.get(stampKey);
    if (stamp == null) {
      stamp = new AccountStamp();
      stamp.accountId = accountId;
      stamp.assignmentId = assignmentId;
      stamp.originKind = originKind;
      stamp.signedAmount = 0;
      byAccount.put(stampKey, stamp);
    }
    stamp.signedAmount = nvl(stamp.signedAmount) + signed;
  }

  /** 仕様: Accounting 第4.4節、第4.6節。CTA・請求基準DEFは本体／税の候補役割を持つ。 */
  private static String stampOriginKind(Candidate candidate, String slotKey) {
    if (
      candidate == null ||
      candidate.role == null ||
      (slotKey != AccountingSlotFixedCatalog.ContractAsset.key &&
        slotKey != AccountingSlotFixedCatalog.DeferredRevenue.key)
    ) {
      return null;
    }
    if (
      candidate.role == AccountingCatalogTypes.JournalCandidateRole.InvoiceBody ||
      candidate.role == AccountingCatalogTypes.JournalCandidateRole.RevenueBody
    ) {
      return 'Body';
    }
    if (
      candidate.role == AccountingCatalogTypes.JournalCandidateRole.InvoiceTax ||
      candidate.role == AccountingCatalogTypes.JournalCandidateRole.RevenueTax
    ) {
      return 'Tax';
    }
    return null;
  }

  private static Boolean isLineFinalSettlement(Candidate candidate, Map<Id, LineBook> books) {
    if (candidate.allocation == null || candidate.line == null) {
      return false;
    }
    Decimal inclusive =
      nvl(candidate.line.Amount__c) + nvl(candidate.line.AllocatedTaxAmount__c);
    return inclusive - bookOf(books, candidate.line).paid == 0;
  }

  /** 仕様: Accounting 第4.4節、第4.6節、第6.2節、第8.4節、Core 第11.9節。No.2・5のCTA、請求基準No.6・8のDEF取り崩し、UAC／SP充当を含む。 */
  private static List<Candidate> splitByRealAccounts(
    Candidate split,
    Map<Id, LineBook> books,
    LineBook invoiceBook,
    Boolean finalSettlement
  ) {
    String targetSlot = accountSplitSlot(split);
    if (targetSlot == null) {
      return new List<Candidate>{ split };
    }
    // 仕様: Accounting 第6.2節。line==null（No.11／12）は請求書単位のUAC／SPスタンプで充当する。
    if (increasesSlot(split, targetSlot)) {
      return new List<Candidate>{ split };
    }
    String originKind = bodyTaxDrawdownOrigin(split, targetSlot);
    LineBook stampBook = split.line == null
      ? invoiceBook
      : bookOf(books, split.line);
    List<AccountStamp> balances = drawdownBalances(
      stampBook,
      targetSlot,
      originKind
    );
    if (balances.isEmpty()) {
      // 仕様: Accounting 第4.4節・第4.6節・第6.2節。
      // 本体／税スタンプで濾したあと0件なら候補破棄（現行割当へ落とさない）。No.2・5およびNo.1・4のCTA取り崩し、請求基準DEF取り崩し。
      if (originKind != null) {
        return new List<Candidate>();
      }
      return new List<Candidate>{ split };
    }
    AmountCalculationSettingService.requireOrgDefault();
    List<Integer> amounts = finalSettlement
      ? directRemainings(balances, split.amount)
      : sameRateAmounts(balances, split.amount);
    List<Candidate> rows = new List<Candidate>();
    for (Integer i = 0; i < balances.size(); i++) {
      if (amounts[i] == 0) {
        continue;
      }
      Candidate row = copyCandidate(split);
      row.amount = amounts[i];
      stampTargetAccount(row, targetSlot, balances[i]);
      rows.add(row);
    }
    return rows;
  }

  /**
   * 仕様: Accounting 第4.6節。
   * CTAは常に本体／税。請求基準のDEF取り崩し（No.6・8）も本体／税。
   * 入金連動前受のDEF・AR税込プールは役割で分けない。
   */
  private static String bodyTaxDrawdownOrigin(Candidate split, String targetSlot) {
    if (targetSlot == AccountingSlotFixedCatalog.ContractAsset.key) {
      return stampOriginKind(split, targetSlot);
    }
    if (
      targetSlot == AccountingSlotFixedCatalog.DeferredRevenue.key &&
      split.pattern != null &&
      split.pattern.slotPriorityType ==
        AccountingCatalogTypes.SlotPriorityType.BillingBasisRecognitionAllocation
    ) {
      return stampOriginKind(split, targetSlot);
    }
    return null;
  }

  private static String ctaTransferOrigin(Candidate candidate) {
    if (candidate == null || candidate.pattern == null || candidate.pattern.amountItem == null) {
      return null;
    }
    if (candidate.pattern.amountItem == JournalAmountItemFixedCatalog.InvoiceBodyCtaTransfer) {
      return 'Body';
    }
    if (candidate.pattern.amountItem == JournalAmountItemFixedCatalog.InvoiceTaxCtaTransfer) {
      return 'Tax';
    }
    return null;
  }

  /**
   * 仕様: Accounting 第6.2節。
   * 片側だけスタンプ対象ならそのスロット。両側とも対象なら取り崩し側（既存残高への充当）。
   */
  private static String accountSplitSlot(Candidate split) {
    Boolean debitStamp = isAccountStampSlot(split.debitSlotKey);
    Boolean creditStamp = isAccountStampSlot(split.creditSlotKey);
    if (debitStamp && !creditStamp) {
      return split.debitSlotKey;
    }
    if (creditStamp && !debitStamp) {
      return split.creditSlotKey;
    }
    if (debitStamp && creditStamp) {
      Boolean debitIncreases = increasesSlot(split, split.debitSlotKey);
      Boolean creditIncreases = increasesSlot(split, split.creditSlotKey);
      if (!debitIncreases && creditIncreases) {
        return split.debitSlotKey;
      }
      if (!creditIncreases && debitIncreases) {
        return split.creditSlotKey;
      }
    }
    return null;
  }

  private static Boolean isAccountStampSlot(String slotKey) {
    // 仕様: Accounting 第6.2節・第8.4節・第8.6節。既存残高充当はAR・DEF・CTA・UAC・SPの元スタンプを使う。
    return slotKey == AccountingSlotFixedCatalog.AccountsReceivable.key ||
      slotKey == AccountingSlotFixedCatalog.DeferredRevenue.key ||
      slotKey == AccountingSlotFixedCatalog.ContractAsset.key ||
      slotKey == AccountingSlotFixedCatalog.UnappliedCash.key ||
      slotKey == AccountingSlotFixedCatalog.SuspensePayment.key;
  }

  /** 仕様: Accounting 第4.4節・第6.2節。業務容量を候補役割ごとのCTA作成元スタンプ合計で打ち切る。 */
  private static Decimal capCtaTransferByStamps(
    Decimal businessAmount,
    LineBook book,
    String originKind
  ) {
    if (businessAmount == null || businessAmount == 0) {
      return businessAmount;
    }
    Decimal stampTotal = 0;
    for (
      AccountStamp stamp : drawdownBalances(
        book,
        AccountingSlotFixedCatalog.ContractAsset.key,
        originKind
      )
    ) {
      stampTotal += nvl(stamp.signedAmount);
    }
    Integer sign = businessAmount < 0 ? -1 : 1;
    Decimal available = max(stampTotal * sign, 0);
    if (available <= 0) {
      return 0;
    }
    Decimal take = businessAmount.abs() < available ? businessAmount.abs() : available;
    return take * sign;
  }

  private static Boolean increasesSlot(Candidate split, String targetSlot) {
    Boolean debitSide = split.debitSlotKey == targetSlot;
    AccountingSlotFixedCatalog.Definition slot = AccountingSlotFixedCatalog.require(
      targetSlot
    );
    return (debitSide &&
      slot.normalBalance == AccountingCatalogTypes.NormalBalance.Debit) ||
      (!debitSide &&
        slot.normalBalance == AccountingCatalogTypes.NormalBalance.Credit);
  }

  private static List<AccountStamp> drawdownBalances(
    LineBook book,
    String slotKey,
    String originKind
  ) {
    List<AccountStamp> rows = new List<AccountStamp>();
    Map<String, AccountStamp> byAccount = book.accountStamps.get(slotKey);
    if (byAccount == null) {
      return rows;
    }
    for (AccountStamp stamp : byAccount.values()) {
      if (stamp == null || nvl(stamp.signedAmount) == 0) {
        continue;
      }
      if (originKind != null && stamp.originKind != originKind) {
        continue;
      }
      rows.add(stamp);
    }
    for (Integer i = 0; i < rows.size(); i++) {
      for (Integer j = i + 1; j < rows.size(); j++) {
        if (String.valueOf(rows[j].accountId) < String.valueOf(rows[i].accountId)) {
          AccountStamp swap = rows[i];
          rows[i] = rows[j];
          rows[j] = swap;
        }
      }
    }
    return rows;
  }

  private static void stampTargetAccount(
    Candidate split,
    String targetSlot,
    AccountStamp stamp
  ) {
    if (split.debitSlotKey == targetSlot) {
      split.debitAccountId = stamp.accountId;
      split.debitAssignmentId = stamp.assignmentId;
    } else {
      split.creditAccountId = stamp.accountId;
      split.creditAssignmentId = stamp.assignmentId;
    }
  }

  private static List<Integer> directRemainings(
    List<AccountStamp> balances,
    Decimal parentAmount
  ) {
    Integer sign = parentAmount < 0 ? -1 : 1;
    Integer parentAbs = parentAmount.abs().intValue();
    List<Integer> amounts = new List<Integer>();
    Integer assigned = 0;
    for (AccountStamp stamp : balances) {
      Integer remaining = nvl(stamp.signedAmount).abs().intValue();
      amounts.add(remaining * sign);
      assigned += remaining;
    }
    if (assigned != parentAbs) {
      throw new GoalException('最終決済の科目別残額合計が親割当額と一致しません。');
    }
    return amounts;
  }

  private static List<Integer> sameRateAmounts(
    List<AccountStamp> balances,
    Decimal parentAmount
  ) {
    Decimal weightTotal = 0;
    for (AccountStamp stamp : balances) {
      weightTotal += nvl(stamp.signedAmount);
    }
    List<Decimal> theoretical = new List<Decimal>();
    List<Integer> truncated = new List<Integer>();
    Decimal assigned = 0;
    for (AccountStamp stamp : balances) {
      Decimal theory = weightTotal == 0
        ? 0
        : parentAmount * nvl(stamp.signedAmount) / weightTotal;
      theoretical.add(theory);
      Integer cut = truncateTowardZero(theory);
      truncated.add(cut);
      assigned += cut;
    }
    Decimal remainder = parentAmount - assigned;
    List<Integer> order = sortByRemainder(theoretical, truncated);
    Integer step = remainder >= 0 ? 1 : -1;
    Integer left = remainder.abs().intValue();
    Integer index = 0;
    while (left > 0 && !order.isEmpty()) {
      Integer rowIndex = order[Math.mod(index, order.size())];
      truncated[rowIndex] = truncated[rowIndex] + step;
      left--;
      index++;
    }
    return truncated;
  }

  private static Integer truncateTowardZero(Decimal value) {
    if (value == null) {
      return 0;
    }
    return value >= 0 ? value.intValue() : -((-value).intValue());
  }

  /** 仕様: Core 第11.9節 */
  private static List<Integer> sortByRemainder(
    List<Decimal> theoretical,
    List<Integer> truncated
  ) {
    List<Integer> indexes = new List<Integer>();
    for (Integer i = 0; i < theoretical.size(); i++) {
      indexes.add(i);
    }
    for (Integer i = 0; i < indexes.size(); i++) {
      for (Integer j = i + 1; j < indexes.size(); j++) {
        Decimal leftFrac = theoretical[indexes[i]] - truncated[indexes[i]];
        Decimal rightFrac = theoretical[indexes[j]] - truncated[indexes[j]];
        if (
          rightFrac > leftFrac ||
          (rightFrac == leftFrac && indexes[j] < indexes[i])
        ) {
          Integer swap = indexes[i];
          indexes[i] = indexes[j];
          indexes[j] = swap;
        }
      }
    }
    return indexes;
  }

  private static void addSlot(LineBook book, String slotKey, Decimal amount, Boolean debitSide) {
    if (String.isBlank(slotKey) || amount == null) {
      return;
    }
    AccountingSlotFixedCatalog.Definition slot = AccountingSlotFixedCatalog.require(slotKey);
    Decimal signed = debitSide
      ? (slot.normalBalance == AccountingCatalogTypes.NormalBalance.Debit ? amount : -amount)
      : (slot.normalBalance == AccountingCatalogTypes.NormalBalance.Credit ? amount : -amount);
    book.slots.put(slotKey, nvl(book.slots.get(slotKey)) + signed);
  }

  private static void resolveAccounts(
    Candidate candidate,
    List<GlJournal__c> currentJournals
  ) {
    if (candidate.isManual) {
      return;
    }
    // 仕様: Accounting 第8.2節手順6・第8.8節。片側がスタンプ済みでも同一生成単位の元仕訳があれば実勘定を維持する。
    if (reuseOriginalAccounts(candidate, currentJournals)) {
      return;
    }
    if (candidate.debitAccountId != null && candidate.creditAccountId != null) {
      return;
    }
    String contextName = evaluationContext(candidate);
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoice = candidate.invoice;
    context.invoiceLine = candidate.line;
    context.invoicePayment = candidate.payment;
    context.allocation = candidate.allocation;
    if (candidate.debitAccountId == null && !String.isBlank(candidate.debitSlotKey)) {
      GlAccountMapResolveService.ResolvedAccount debit = GlAccountMapResolveService.resolve(
        candidate.debitSlotKey,
        contextName,
        context
      );
      candidate.debitAssignmentId = debit.assignmentId;
      candidate.debitAccountId = debit.accountId;
    }
    if (candidate.creditAccountId == null && !String.isBlank(candidate.creditSlotKey)) {
      GlAccountMapResolveService.ResolvedAccount credit = GlAccountMapResolveService.resolve(
        candidate.creditSlotKey,
        contextName,
        context
      );
      candidate.creditAssignmentId = credit.assignmentId;
      candidate.creditAccountId = credit.accountId;
    }
  }

  private static String evaluationContext(Candidate candidate) {
    if (candidate.allocation != null) {
      return 'InvoicePaymentAllocation';
    }
    if (candidate.payment != null) {
      return 'InvoicePayment';
    }
    return 'InvoiceLine';
  }

  /** 仕様: Accounting 第1.8.1節・第6.2節・第8.2節手順6・第8.6節・第8.8節。Current上の有効元仕訳（Active）だけから割当・実勘定を再利用する。 */
  private static Boolean reuseOriginalAccounts(
    Candidate candidate,
    List<GlJournal__c> currentJournals
  ) {
    if (currentJournals == null || currentJournals.isEmpty()) {
      return false;
    }
    String generation = generationUnitKey(candidate, candidate.invoice, allocatedSlot(candidate));
    for (GlJournal__c journal : currentJournals) {
      // 仕様: 第1.8.1節。論理削除・取消済・取消仕訳はCurrentの有効元仕訳ではない。
      if (
        journal.GenerationUnitKey__c != generation ||
        journal.TransactionStatus__c != 'Active'
      ) {
        continue;
      }
      Map<String, Id> accounts = new Map<String, Id>();
      Map<String, Id> assignments = new Map<String, Id>();
      accounts.put(journal.DebitSlotKey__c, journal.DebitAccount__c);
      accounts.put(journal.CreditSlotKey__c, journal.CreditAccount__c);
      assignments.put(journal.DebitSlotKey__c, journal.DebitAccountAssignment__c);
      assignments.put(journal.CreditSlotKey__c, journal.CreditAccountAssignment__c);
      if (
        !accounts.containsKey(candidate.debitSlotKey) ||
        !accounts.containsKey(candidate.creditSlotKey)
      ) {
        continue;
      }
      candidate.debitAccountId = accounts.get(candidate.debitSlotKey);
      candidate.creditAccountId = accounts.get(candidate.creditSlotKey);
      candidate.debitAssignmentId = assignments.get(candidate.debitSlotKey);
      candidate.creditAssignmentId = assignments.get(candidate.creditSlotKey);
      return true;
    }
    return false;
  }

  private static String allocatedSlot(Candidate candidate) {
    if (candidate.pattern == null || candidate.pattern.slotPriorityType == null) {
      return null;
    }
    if (candidate.pattern.debitSlot == null) {
      return candidate.debitSlotKey;
    }
    if (candidate.pattern.creditSlot == null) {
      return candidate.creditSlotKey;
    }
    return null;
  }

  private static String generationUnitKey(
    Candidate candidate,
    Invoice__c invoice,
    String allocated
  ) {
    return AccountingDiffService.hashKey(
      new List<String>{
        String.valueOf(invoice.Id),
        candidate.line == null ? '' : String.valueOf(candidate.line.Id),
        candidate.recognitionSequence == null || candidate.recognitionSequence == 0
          ? ''
          : String.valueOf(candidate.recognitionSequence),
        candidate.payment == null ||
          candidate.role == AccountingCatalogTypes.JournalCandidateRole.RevenueBody ||
          candidate.role == AccountingCatalogTypes.JournalCandidateRole.RevenueTax
          ? ''
          : String.valueOf(candidate.payment.Id),
        candidate.allocation == null ||
          candidate.role == AccountingCatalogTypes.JournalCandidateRole.RevenueBody ||
          candidate.role == AccountingCatalogTypes.JournalCandidateRole.RevenueTax
          ? ''
          : String.valueOf(candidate.allocation.Id),
        candidate.isManual || candidate.pattern == null ? '' : candidate.pattern.key,
        candidate.setting == null ? '' : String.valueOf(candidate.setting.Id),
        candidate.header == null ? '' : String.valueOf(candidate.header.Id),
        allocated == null ? '' : allocated
      }
    );
  }

  private static GoalJournal toGoal(Candidate candidate, Invoice__c invoice, Boolean flip) {
    String debit = candidate.debitSlotKey;
    String credit = candidate.creditSlotKey;
    Id debitAccount = candidate.debitAccountId;
    Id creditAccount = candidate.creditAccountId;
    Id debitAssign = candidate.debitAssignmentId;
    Id creditAssign = candidate.creditAssignmentId;
    Decimal amount = candidate.amount;
    String allocated = allocatedSlot(candidate);
    if (flip && amount != null && amount < 0) {
      String swapSlot = debit;
      debit = credit;
      credit = swapSlot;
      Id swapAccount = debitAccount;
      debitAccount = creditAccount;
      creditAccount = swapAccount;
      Id swapAssign = debitAssign;
      debitAssign = creditAssign;
      creditAssign = swapAssign;
      amount = -amount;
    }
    if (amount == null || amount <= 0) {
      throw new GoalException('仕訳金額は0より大きい整数です。');
    }
    String generation = generationUnitKey(candidate, invoice, allocated);
    String lineKey = AccountingDiffService.hashKey(
      new List<String>{
        generation,
        String.valueOf(candidate.postingDate),
        debit,
        candidate.isManual ? '' : String.valueOf(debitAssign),
        String.valueOf(debitAccount),
        credit,
        candidate.isManual ? '' : String.valueOf(creditAssign),
        String.valueOf(creditAccount)
      }
    );
    GlJournal__c record = new GlJournal__c(
      Invoice__c = invoice.Id,
      BillingAccount__c = invoice.BillingAccountSnapShot__c,
      BillingAccountKeySnapShot__c = invoice.BillingAccountKeySnapShot__c,
      InvoiceLine__c = candidate.line == null ? null : candidate.line.Id,
      InvoicePayment__c = candidate.payment == null ? null : candidate.payment.Id,
      InvoicePaymentAllocation__c = candidate.allocation == null ? null : candidate.allocation.Id,
      GlManualJournalHeader__c = candidate.header == null ? null : candidate.header.Id,
      GlManualJournalSetting__c = candidate.setting == null ? null : candidate.setting.Id,
      JournalPatternKey__c = candidate.pattern == null ? null : candidate.pattern.key,
      DebitSlotKey__c = debit,
      CreditSlotKey__c = credit,
      DebitAccountAssignment__c = debitAssign,
      CreditAccountAssignment__c = creditAssign,
      DebitAccount__c = debitAccount,
      CreditAccount__c = creditAccount,
      Amount__c = amount.intValue(),
      PostingDate__c = candidate.postingDate,
      TransactionStatus__c = 'Active',
      IsLocked__c = false,
      RecognitionSequence__c = candidate.recognitionSequence,
      GenerationUnitKey__c = generation,
      JournalLineKey__c = lineKey
    );
    GoalJournal goal = new GoalJournal();
    goal.record = record;
    goal.candidateKey = candidate.candidateKey;
    goal.allocatedSlotKey = allocated;
    goal.isManual = candidate.isManual;
    return goal;
  }

  private class Recognition {
    Integer sequence;
    Date postingDate;
    Decimal bodyAmount;
    Decimal taxAmount;
  }

  /** 仕様: Accounting 第3.2節、第8.5節、Core 第11.9節 */
  private static List<Recognition> recognitions(InvoiceLine__c line, GlAccountingPolicy__c policy) {
    String basis = ContractMetadataService.normalizeRevenueRecognitionBasis(
      line.RevenueRecognitionBasis__c
    );
    List<Recognition> rows = new List<Recognition>();
    if (basis == ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME) {
      if (line.AcceptanceEndDate__c == null) {
        throw new GoalException('一括計上の検収終了日が空です。');
      }
      Recognition row = new Recognition();
      row.sequence = 1;
      row.postingDate = line.AcceptanceEndDate__c;
      row.bodyAmount = nvl(line.Amount__c);
      row.taxAmount = nvl(line.AllocatedTaxAmount__c);
      rows.add(row);
      return rows;
    }
    if (basis != ContractMetadataService.REVENUE_BASIS_OVER_TIME) {
      throw new GoalException('売上計上基準が不正です。');
    }
    if (line.AcceptanceEndDate__c != null) {
      throw new GoalException('月次計上に検収終了日は設定できません。');
    }
    if (line.ServicePeriodStartDate__c == null || line.ServicePeriodEndDate__c == null) {
      throw new GoalException('月次計上のサービス期間が空です。');
    }
    List<MonthlyBillingPeriodUtil.BillingPeriod> periods = monthlyPeriods(line, policy);
    if (periods.isEmpty()) {
      throw new GoalException('月次計上のバケットを作れませんでした。');
    }
    List<Decimal> bodies = splitAmount(nvl(line.Amount__c), periods.size(), policy.RoundingTargetBucket__c);
    List<Decimal> taxes = allocateTaxBySignedRevenue(
      nvl(line.AllocatedTaxAmount__c),
      bodies,
      policy.RoundingTargetBucket__c
    );
    for (Integer i = 0; i < periods.size(); i++) {
      Recognition row = new Recognition();
      row.sequence = i + 1;
      row.postingDate = recognitionDate(periods[i], i == periods.size() - 1, line, policy);
      row.bodyAmount = bodies[i];
      row.taxAmount = taxes[i];
      rows.add(row);
    }
    return rows;
  }

  /** 仕様: Accounting 第3.2節、第3.3節、日付仕様 第2章。刻む算法は組織にひとつ。 */
  private static List<MonthlyBillingPeriodUtil.BillingPeriod> monthlyPeriods(
    InvoiceLine__c line,
    GlAccountingPolicy__c policy
  ) {
    Date startDate = line.ServicePeriodStartDate__c;
    Date endDate = line.ServicePeriodEndDate__c;
    String method = policy.MonthlyBucketMethod__c;
    if (method == 'CalendarMonth') {
      return MonthlyBillingPeriodUtil.buildCalendarMonthPeriods(startDate, endDate);
    }
    if (method == 'Auto' && MonthlyBillingPeriodUtil.countMonthlyCycles(startDate, endDate) < 0) {
      return MonthlyBillingPeriodUtil.buildCalendarMonthPeriods(startDate, endDate);
    }
    return MonthlyBillingPeriodUtil.buildMonthlyPeriodsCoveringEnd(startDate, endDate);
  }

  private static Date recognitionDate(
    MonthlyBillingPeriodUtil.BillingPeriod period,
    Boolean lastBucket,
    InvoiceLine__c line,
    GlAccountingPolicy__c policy
  ) {
    if (lastBucket) {
      return line.ServicePeriodEndDate__c;
    }
    if (policy.MonthlyRecognitionDatePosition__c == 'BucketStart') {
      return period.startDate;
    }
    if (policy.MonthlyRecognitionDatePosition__c == 'MonthEnd') {
      Date monthEnd = Date.newInstance(
        period.endDate.year(),
        period.endDate.month(),
        Date.daysInMonth(period.endDate.year(), period.endDate.month())
      );
      return monthEnd > line.ServicePeriodEndDate__c ? line.ServicePeriodEndDate__c : monthEnd;
    }
    return period.endDate;
  }

  private static List<Decimal> splitAmount(Decimal total, Integer parts, String roundingTarget) {
    List<Decimal> values = new List<Decimal>();
    if (parts <= 0) {
      return values;
    }
    Integer absTotal = total == null ? 0 : total.abs().intValue();
    Integer base = parts == 0 ? 0 : absTotal / parts;
    Integer remainder = absTotal - (base * parts);
    Integer remainderIndex = roundingTarget == 'First' ? 0 : parts - 1;
    Integer sign = total == null || total >= 0 ? 1 : -1;
    for (Integer i = 0; i < parts; i++) {
      Integer value = base + (i == remainderIndex ? remainder : 0);
      values.add(value * sign);
    }
    return values;
  }

  /** 仕様: Core 第11.9節、Accounting 第3.2節 */
  private static List<Decimal> allocateTaxBySignedRevenue(
    Decimal taxTotal,
    List<Decimal> bodies,
    String roundingTarget
  ) {
    List<Decimal> values = new List<Decimal>();
    Integer parts = bodies == null ? 0 : bodies.size();
    if (parts <= 0) {
      return values;
    }
    Decimal bodyTotal = 0;
    for (Decimal body : bodies) {
      bodyTotal += nvl(body);
    }
    Decimal tax = nvl(taxTotal);
    if (bodyTotal == 0) {
      if (tax == 0) {
        for (Integer i = 0; i < parts; i++) {
          values.add(0);
        }
        return values;
      }
      throw new GoalException('税抜売上が0のため税額をスケジュールへ配分できません。');
    }
    List<Integer> truncated = new List<Integer>();
    Integer assigned = 0;
    for (Decimal body : bodies) {
      Decimal theory = tax * nvl(body) / bodyTotal;
      Integer cut = truncateTowardZero(theory);
      truncated.add(cut);
      assigned += cut;
    }
    Integer remainder = tax.intValue() - assigned;
    Integer remainderIndex = roundingTarget == 'First' ? 0 : parts - 1;
    truncated[remainderIndex] = truncated[remainderIndex] + remainder;
    for (Integer value : truncated) {
      values.add(value);
    }
    return values;
  }

  /** 仕様: Accounting 第4.4節、第4.6節 */
  private static Decimal signedCtaTransfer(
    Decimal recognized,
    Decimal billed,
    InvoiceLine__c line
  ) {
    return max(nvl(recognized) - nvl(billed), 0) * factSign(line);
  }

  /** 仕様: Accounting 第4.6節 */
  private static Integer factSign(InvoiceLine__c line) {
    if (line == null) {
      return 1;
    }
    Decimal body = nvl(line.Amount__c);
    if (body < 0) {
      return -1;
    }
    if (body > 0) {
      return 1;
    }
    return nvl(line.AllocatedTaxAmount__c) < 0 ? -1 : 1;
  }

  /** 仕様: Accounting 第8.2節、第8.7節 */
  private static void sortCandidates(List<Candidate> candidates) {
    for (Integer i = 0; i < candidates.size(); i++) {
      for (Integer j = i + 1; j < candidates.size(); j++) {
        if (comesBefore(candidates[j], candidates[i])) {
          Candidate swap = candidates[i];
          candidates[i] = candidates[j];
          candidates[j] = swap;
        }
      }
    }
  }

  private static Boolean comesBefore(Candidate left, Candidate right) {
    if (left.postingDate != right.postingDate) {
      if (left.postingDate == null) {
        return false;
      }
      if (right.postingDate == null) {
        return true;
      }
      return left.postingDate < right.postingDate;
    }
    Integer leftOrder = left.sameDayOrder == null ? 0 : left.sameDayOrder;
    Integer rightOrder = right.sameDayOrder == null ? 0 : right.sameDayOrder;
    if (leftOrder != rightOrder) {
      return leftOrder < rightOrder;
    }
    if (left.causeCreatedDate != right.causeCreatedDate) {
      if (left.causeCreatedDate == null) {
        return false;
      }
      if (right.causeCreatedDate == null) {
        return true;
      }
      return left.causeCreatedDate < right.causeCreatedDate;
    }
    if (sameLineSameDayRevenue(left, right)) {
      Integer leftSequence = left.recognitionSequence == null ? 0 : left.recognitionSequence;
      Integer rightSequence = right.recognitionSequence == null ? 0 : right.recognitionSequence;
      if (leftSequence != rightSequence) {
        return leftSequence < rightSequence;
      }
    }
    return causeIdKey(left) < causeIdKey(right);
  }

  private static Boolean sameLineSameDayRevenue(Candidate left, Candidate right) {
    return left.line != null &&
      right.line != null &&
      left.line.Id == right.line.Id &&
      left.postingDate == right.postingDate &&
      isRevenueRole(left.role) &&
      isRevenueRole(right.role);
  }

  private static Boolean isRevenueRole(AccountingCatalogTypes.JournalCandidateRole role) {
    return role == AccountingCatalogTypes.JournalCandidateRole.RevenueBody ||
      role == AccountingCatalogTypes.JournalCandidateRole.RevenueTax;
  }

  private static String causeIdKey(Candidate candidate) {
    return candidate.causeRecordId == null ? '' : String.valueOf(candidate.causeRecordId);
  }

  private static void assignCause(
    Candidate candidate,
    InvoiceLine__c line,
    InvoicePayment__c payment,
    InvoicePaymentAllocation__c allocation,
    GlManualJournalHeader__c header
  ) {
    if (header != null) {
      candidate.causeCreatedDate = header.CreatedDate;
      candidate.causeRecordId = header.Id;
      return;
    }
    if (allocation != null) {
      candidate.causeCreatedDate = allocation.CreatedDate;
      candidate.causeRecordId = allocation.Id;
      return;
    }
    if (payment != null) {
      candidate.causeCreatedDate = payment.CreatedDate;
      candidate.causeRecordId = payment.Id;
      return;
    }
    if (line != null) {
      candidate.causeCreatedDate = line.CreatedDate;
      candidate.causeRecordId = line.Id;
    }
  }

  /** 仕様: Accounting 第1.8.1節・第8.2節手順3・第8.7節。Current上の有効な元仕訳（Active）だけをパターン再利用に使う。 */
  private static Map<String, String> reusedPatternsByCandidate(List<GlJournal__c> currentJournals) {
    Map<String, Set<String>> allKeys = new Map<String, Set<String>>();
    Map<String, Set<String>> activeKeys = new Map<String, Set<String>>();
    if (currentJournals == null) {
      return new Map<String, String>();
    }
    for (GlJournal__c journal : currentJournals) {
      if (String.isBlank(journal.JournalPatternKey__c)) {
        continue;
      }
      // 仕様: 第1.8.1節。取消仕訳は独立行にしない。元仕訳だけを見る。
      if (journal.TransactionStatus__c == 'Reversal') {
        continue;
      }
      String candidateKey = causeKey(
        journal.Invoice__c,
        journal.InvoiceLine__c,
        journal.RecognitionSequence__c == null ? 0 : Integer.valueOf(journal.RecognitionSequence__c),
        journal.InvoicePayment__c,
        journal.InvoicePaymentAllocation__c,
        patternRole(journal.JournalPatternKey__c),
        journal.GlManualJournalSetting__c,
        journal.GlManualJournalHeader__c
      );
      if (!allKeys.containsKey(candidateKey)) {
        allKeys.put(candidateKey, new Set<String>());
      }
      allKeys.get(candidateKey).add(journal.JournalPatternKey__c);
      // 仕様: 第8.7節。論理削除・取消済も含めてパターン一致を検証する。再利用値はActiveだけ。
      if (journal.TransactionStatus__c == 'Active') {
        if (!activeKeys.containsKey(candidateKey)) {
          activeKeys.put(candidateKey, new Set<String>());
        }
        activeKeys.get(candidateKey).add(journal.JournalPatternKey__c);
      }
    }
    Map<String, String> reused = new Map<String, String>();
    for (String candidateKey : allKeys.keySet()) {
      Set<String> patterns = allKeys.get(candidateKey);
      if (patterns.size() > 1) {
        throw new GoalException('同じ原因候補に複数の仕訳パターンが残っています。');
      }
      // 仕様: 第1.8.1節・第8.2節。Currentに有効元仕訳が無い（論理削除だけ等）ときは初回生成。
      if (!activeKeys.containsKey(candidateKey)) {
        continue;
      }
      reused.put(candidateKey, new List<String>(activeKeys.get(candidateKey))[0]);
    }
    return reused;
  }

  private static String patternRole(String patternKey) {
    return String.valueOf(JournalPatternFixedCatalog.require(patternKey).candidateRole);
  }

  private static String causeKey(
    Id invoiceId,
    Id lineId,
    Integer sequence,
    Id paymentId,
    Id allocationId,
    String role,
    Id settingId,
    Id headerId
  ) {
    return String.join(
      new List<String>{
        String.valueOf(invoiceId),
        lineId == null ? '-' : String.valueOf(lineId),
        sequence == null || sequence == 0 ? '-' : String.valueOf(sequence),
        paymentId == null ? '-' : String.valueOf(paymentId),
        allocationId == null ? '-' : String.valueOf(allocationId),
        String.isBlank(role) ? '-' : role,
        settingId == null ? '-' : String.valueOf(settingId),
        headerId == null ? '-' : String.valueOf(headerId)
      },
      '|'
    );
  }

  private static Map<Id, InvoiceLine__c> loadLines(Id invoiceId) {
    Map<Id, InvoiceLine__c> rows = new Map<Id, InvoiceLine__c>();
    for (InvoiceLine__c line : [
      SELECT
        Id,
        CreatedDate,
        Invoice__c,
        Amount__c,
        AllocatedTaxAmount__c,
        AcceptanceEndDate__c,
        ServicePeriodStartDate__c,
        ServicePeriodEndDate__c,
        RevenueRecognitionBasis__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :invoiceId
      WITH SYSTEM_MODE
    ]) {
      rows.put(line.Id, line);
    }
    return rows;
  }

  private static Map<Id, InvoicePayment__c> loadPayments(Id invoiceId) {
    Map<Id, InvoicePayment__c> rows = new Map<Id, InvoicePayment__c>();
    for (InvoicePayment__c payment : [
      SELECT
        Id,
        CreatedDate,
        Invoice__c,
        Amount__c,
        PaymentPurpose__c,
        PaymentDate__c,
        PaymentTransactionStatus__c
      FROM InvoicePayment__c
      WHERE Invoice__c = :invoiceId AND PaymentTransactionStatus__c = 'Active'
      WITH SYSTEM_MODE
    ]) {
      rows.put(payment.Id, payment);
    }
    return rows;
  }

  private static List<InvoicePaymentAllocation__c> loadAllocations(Set<Id> paymentIds) {
    if (paymentIds == null || paymentIds.isEmpty()) {
      return new List<InvoicePaymentAllocation__c>();
    }
    return [
      SELECT
        Id,
        CreatedDate,
        InvoicePayment__c,
        InvoiceLine__c,
        Amount__c,
        HistoricalUacAmount__c,
        HistoricalSpAmount__c
      FROM InvoicePaymentAllocation__c
      WHERE InvoicePayment__c IN :paymentIds
      WITH SYSTEM_MODE
    ];
  }

  private static List<GlManualJournalHeader__c> loadManualHeaders(Id invoiceId) {
    return [
      SELECT
        Id,
        CreatedDate,
        Invoice__c,
        GlManualJournalSetting__c,
        PostingDate__c,
        Amount__c,
        TransactionStatus__c
      FROM GlManualJournalHeader__c
      WHERE Invoice__c = :invoiceId AND TransactionStatus__c = 'Active'
      WITH SYSTEM_MODE
    ];
  }

  private static Map<Id, GlManualJournalSetting__c> loadSettings(List<GlManualJournalHeader__c> headers) {
    Set<Id> ids = new Set<Id>();
    for (GlManualJournalHeader__c header : headers) {
      ids.add(header.GlManualJournalSetting__c);
    }
    if (ids.isEmpty()) {
      return new Map<Id, GlManualJournalSetting__c>();
    }
    return new Map<Id, GlManualJournalSetting__c>(
      [
        SELECT Id, DebitSlotKey__c, CreditSlotKey__c, DebitAccount__c, CreditAccount__c, IsActive__c
        FROM GlManualJournalSetting__c
        WHERE Id IN :ids
        WITH SYSTEM_MODE
      ]
    );
  }

  private static LineBook bookOf(Map<Id, LineBook> books, InvoiceLine__c line) {
    Id key = line == null ? null : line.Id;
    if (!books.containsKey(key)) {
      books.put(key, new LineBook());
    }
    return books.get(key);
  }

  /** 仕様: Accounting 第4.6節。取り崩し容量は帰属する実行残高（スタンプ）を見る。複写から落とさない。 */
  private static LineBook snapshot(LineBook source) {
    LineBook copy = new LineBook();
    copy.billedBody = source.billedBody;
    copy.billedTax = source.billedTax;
    copy.recognizedBody = source.recognizedBody;
    copy.recognizedTax = source.recognizedTax;
    copy.paid = source.paid;
    copy.slots = source.slots.clone();
    for (String slotKey : source.accountStamps.keySet()) {
      copy.accountStamps.put(slotKey, source.accountStamps.get(slotKey).clone());
    }
    return copy;
  }

  private static List<SlotPriorityRuleFixedCatalog.Definition> rulesOf(
    AccountingCatalogTypes.SlotPriorityType priorityType
  ) {
    List<SlotPriorityRuleFixedCatalog.Definition> rules = new List<SlotPriorityRuleFixedCatalog.Definition>();
    for (SlotPriorityRuleFixedCatalog.Definition rule : SlotPriorityRuleFixedCatalog.values()) {
      if (rule.priorityType == priorityType) {
        rules.add(rule);
      }
    }
    for (Integer i = 0; i < rules.size(); i++) {
      for (Integer j = i + 1; j < rules.size(); j++) {
        if (rules[j].priority < rules[i].priority) {
          SlotPriorityRuleFixedCatalog.Definition swap = rules[i];
          rules[i] = rules[j];
          rules[j] = swap;
        }
      }
    }
    return rules;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  private static Decimal max(Decimal left, Decimal right) {
    return left > right ? left : right;
  }

  private static Decimal min(Decimal left, Decimal right) {
    return left < right ? left : right;
  }
}
