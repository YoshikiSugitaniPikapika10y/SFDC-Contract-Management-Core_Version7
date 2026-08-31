/**
 * 請求金額目的の明細別割当。合計は親金額と一致させる。
 */
public without sharing class InvoicePaymentAllocationService {
  public class AllocationLine {
    public Id invoiceLineId;
    public Decimal amount;
    public Decimal historicalUacAmount;
    public Decimal historicalSpAmount;
  }

  public static Boolean allowHistoricalAmountWrite;

  public static final String HISTORICAL_AMOUNT_EDIT_MESSAGE =
    '過去日UAC／SP振替額は利用者が直接編集できません。';

  /** 仕様: Core 第8.6節、Accounting 第4.4節 */
  public static void guardHistoricalAmounts(
    List<InvoicePaymentAllocation__c> rows,
    Map<Id, InvoicePaymentAllocation__c> oldMap
  ) {
    if (allowHistoricalAmountWrite == true || rows == null) {
      return;
    }
    for (InvoicePaymentAllocation__c row : rows) {
      if (row == null) {
        continue;
      }
      InvoicePaymentAllocation__c prior =
        oldMap == null ? null : oldMap.get(row.Id);
      if (prior == null) {
        if (
          nvl(row.HistoricalUacAmount__c) != 0 ||
          nvl(row.HistoricalSpAmount__c) != 0
        ) {
          row.addError(HISTORICAL_AMOUNT_EDIT_MESSAGE);
        }
        continue;
      }
      if (
        nvl(row.HistoricalUacAmount__c) != nvl(prior.HistoricalUacAmount__c) ||
        nvl(row.HistoricalSpAmount__c) != nvl(prior.HistoricalSpAmount__c)
      ) {
        row.addError(HISTORICAL_AMOUNT_EDIT_MESSAGE);
      }
    }
  }

  /** 仕様: Core 第8.6節、第11.9節。未処理税込の比例と符号付き最大剰余。最終決済は残額をそのまま載せる。 */
  public static List<AllocationLine> proposeLines(Id invoiceId, Decimal parentAmount) {
    if (invoiceId == null || parentAmount == null || parentAmount == 0) {
      throw new AllocationException('明細別割当の初期値を作れません。');
    }
    AmountCalculationSettingService.requireOrgDefault();
    List<LineRemaining> remainings = loadLineRemainings(invoiceId);
    if (remainings.isEmpty()) {
      throw new AllocationException('請求金額の入出金は明細別割当が1件以上必要です。');
    }
    Decimal openTotal = 0;
    for (LineRemaining row : remainings) {
      openTotal += row.remainingInclusive;
    }
    if (parentAmount == openTotal) {
      List<AllocationLine> proposed = new List<AllocationLine>();
      for (LineRemaining row : remainings) {
        if (row.remainingInclusive == 0) {
          continue;
        }
        AllocationLine line = new AllocationLine();
        line.invoiceLineId = row.lineId;
        line.amount = row.remainingInclusive;
        proposed.add(line);
      }
      if (proposed.isEmpty()) {
        throw new AllocationException('明細別割当の初期値を作れません。');
      }
      return proposed;
    }
    List<LineRemaining> openLines = new List<LineRemaining>();
    for (LineRemaining row : remainings) {
      if (row.remainingInclusive != 0) {
        openLines.add(row);
      }
    }
    if (openLines.isEmpty() || openTotal == 0) {
      throw new AllocationException('明細別割当の初期値を作れません。');
    }
    List<Decimal> theoretical = new List<Decimal>();
    List<Integer> truncated = new List<Integer>();
    Decimal assigned = 0;
    for (LineRemaining row : openLines) {
      Decimal theory = parentAmount * row.remainingInclusive / openTotal;
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
      Integer lineIndex = order[Math.mod(index, order.size())];
      truncated[lineIndex] = truncated[lineIndex] + step;
      left--;
      index++;
    }
    List<AllocationLine> proposed = new List<AllocationLine>();
    for (Integer i = 0; i < openLines.size(); i++) {
      AllocationLine line = new AllocationLine();
      line.invoiceLineId = openLines[i].lineId;
      line.amount = truncated[i];
      proposed.add(line);
    }
    return proposed;
  }

  /** 仕様: Core 第8.6節、第11.9節。処理可能残額内。最終決済は全明細残額0。 */
  public static void assertLines(
    Id invoiceId,
    Decimal parentAmount,
    List<AllocationLine> lines
  ) {
    if (lines == null || lines.isEmpty()) {
      throw new AllocationException('請求金額の入出金は明細別割当が1件以上必要です。');
    }
    Decimal total = 0;
    Set<Id> lineIds = new Set<Id>();
    for (AllocationLine line : lines) {
      if (line == null || line.invoiceLineId == null || line.amount == null) {
        throw new AllocationException('明細別割当の請求明細と金額は必須です。');
      }
      if (line.amount != line.amount.intValue()) {
        throw new AllocationException('明細別割当の金額は整数にしてください。');
      }
      if (!lineIds.add(line.invoiceLineId)) {
        throw new AllocationException('同じ請求明細へ重複して割り当てられません。');
      }
      total += line.amount;
    }
    if (total != parentAmount) {
      throw new AllocationException('明細別割当の合計は親の金額と一致させてください。');
    }
    InvoiceSnapshot snapshot = loadInvoiceSnapshot(invoiceId);
    Map<Id, Decimal> remainingByLine = new Map<Id, Decimal>();
    for (LineRemaining row : snapshot.remainings) {
      remainingByLine.put(row.lineId, row.remainingInclusive);
    }
    Map<Id, Decimal> allocatedByLine = new Map<Id, Decimal>();
    for (AllocationLine line : lines) {
      if (!remainingByLine.containsKey(line.invoiceLineId)) {
        throw new AllocationException('明細別割当は親と同じ請求書の請求明細だけを指定できます。');
      }
      Decimal remaining = remainingByLine.get(line.invoiceLineId);
      if (exceedsRemaining(line.amount, remaining)) {
        throw new AllocationException('明細別割当は各明細の処理可能残額以内にしてください。');
      }
      allocatedByLine.put(line.invoiceLineId, line.amount);
    }
    Decimal headerRemaining =
      snapshot.taxInclusiveAmount - snapshot.invoicePaymentNet;
    if (parentAmount == headerRemaining) {
      for (Id lineId : remainingByLine.keySet()) {
        Decimal remaining = remainingByLine.get(lineId);
        Decimal allocated = allocatedByLine.containsKey(lineId)
          ? allocatedByLine.get(lineId)
          : 0;
        if (allocated != remaining) {
          throw new AllocationException('最終決済では全明細の未処理税込残額を0にしてください。');
        }
      }
    }
  }

  /** 仕様: Core 第8.1節、Accounting 第4.4節、第8.4節 */
  public static void allocate(Id paymentId, List<AllocationLine> lines) {
    if (paymentId == null) {
      throw new AllocationException('請求入出金が指定されていません。');
    }
    InvoicePayment__c payment = [
      SELECT Id, Invoice__c, Amount__c, PaymentPurpose__c
      FROM InvoicePayment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (payment.PaymentPurpose__c == 'NonInvoice') {
      if (lines != null && !lines.isEmpty()) {
        throw new AllocationException('請求金額以外の入出金に明細別割当は持てません。');
      }
      return;
    }
    assertLines(payment.Invoice__c, payment.Amount__c, lines);
    List<InvoicePaymentAllocation__c> rows = new List<InvoicePaymentAllocation__c>();
    for (AllocationLine line : lines) {
      rows.add(
        new InvoicePaymentAllocation__c(
          InvoicePayment__c = paymentId,
          InvoiceLine__c = line.invoiceLineId,
          Amount__c = line.amount,
          HistoricalUacAmount__c = 0,
          HistoricalSpAmount__c = 0
        )
      );
    }
    SystemContextAccess.insertRecords(rows);
  }

  /** 仕様: Core 第8.1節、Accounting 第4.4節、第8.4節。取消時は再按分せず、同じ明細へ反対符号を載せる。 */
  public static void reverseAllocations(Id originalPaymentId, Id reversalPaymentId) {
    List<InvoicePaymentAllocation__c> originals = [
      SELECT InvoiceLine__c, Amount__c, HistoricalUacAmount__c, HistoricalSpAmount__c
      FROM InvoicePaymentAllocation__c
      WHERE InvoicePayment__c = :originalPaymentId
      WITH SYSTEM_MODE
    ];
    if (originals.isEmpty()) {
      return;
    }
    List<InvoicePaymentAllocation__c> rows = new List<InvoicePaymentAllocation__c>();
    for (InvoicePaymentAllocation__c original : originals) {
      rows.add(
        new InvoicePaymentAllocation__c(
          InvoicePayment__c = reversalPaymentId,
          InvoiceLine__c = original.InvoiceLine__c,
          Amount__c = original.Amount__c == null ? 0 : -original.Amount__c,
          HistoricalUacAmount__c = original.HistoricalUacAmount__c == null
            ? 0
            : -original.HistoricalUacAmount__c,
          HistoricalSpAmount__c = original.HistoricalSpAmount__c == null
            ? 0
            : -original.HistoricalSpAmount__c
        )
      );
    }
    Boolean previous = allowHistoricalAmountWrite;
    allowHistoricalAmountWrite = true;
    try {
      SystemContextAccess.insertRecords(rows);
    } finally {
      allowHistoricalAmountWrite = previous;
    }
  }

  private static List<LineRemaining> loadLineRemainings(Id invoiceId) {
    return loadInvoiceSnapshot(invoiceId).remainings;
  }

  private static InvoiceSnapshot loadInvoiceSnapshot(Id invoiceId) {
    Invoice__c invoice = [
      SELECT Id, TaxInclusiveAmount__c, InvoicePaymentNet__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    Map<Id, Decimal> allocatedByLine = new Map<Id, Decimal>();
    for (InvoicePaymentAllocation__c allocation : [
      SELECT InvoiceLine__c, Amount__c
      FROM InvoicePaymentAllocation__c
      WHERE
        InvoicePayment__r.Invoice__c = :invoiceId
        AND InvoicePayment__r.PaymentPurpose__c = :InvoicePaymentService.PURPOSE_INVOICE
        AND InvoicePayment__r.PaymentTransactionStatus__c = :InvoicePaymentService.STATUS_ACTIVE
      WITH SYSTEM_MODE
    ]) {
      Decimal current = allocatedByLine.containsKey(allocation.InvoiceLine__c)
        ? allocatedByLine.get(allocation.InvoiceLine__c)
        : 0;
      allocatedByLine.put(
        allocation.InvoiceLine__c,
        current + nvl(allocation.Amount__c)
      );
    }
    InvoiceSnapshot snapshot = new InvoiceSnapshot();
    snapshot.taxInclusiveAmount = nvl(invoice.TaxInclusiveAmount__c);
    snapshot.invoicePaymentNet = nvl(invoice.InvoicePaymentNet__c);
    snapshot.remainings = new List<LineRemaining>();
    for (InvoiceLine__c line : [
      SELECT Id, TaxInclusiveAmount__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :invoiceId
      WITH SYSTEM_MODE
      ORDER BY Id
    ]) {
      LineRemaining row = new LineRemaining();
      row.lineId = line.Id;
      // 仕様: Core 第8.6節。明細の決済対象額は明細税込。
      Decimal inclusive = nvl(line.TaxInclusiveAmount__c);
      Decimal allocated = allocatedByLine.containsKey(line.Id)
        ? allocatedByLine.get(line.Id)
        : 0;
      row.remainingInclusive = inclusive - allocated;
      snapshot.remainings.add(row);
    }
    return snapshot;
  }

  private static Boolean exceedsRemaining(Decimal amount, Decimal remaining) {
    // 仕様: Core 第8.6節・第8.9節。同符号かつ|割当|≦|処理可能残額|。異符号は超過。
    if (amount == 0) {
      return false;
    }
    if (remaining == 0) {
      return true;
    }
    if ((amount > 0 && remaining < 0) || (amount < 0 && remaining > 0)) {
      return true;
    }
    return amount.abs() > remaining.abs();
  }

  private static Integer truncateTowardZero(Decimal value) {
    if (value == null || value == 0) {
      return 0;
    }
    return value >= 0 ? value.intValue() : -((-value).intValue());
  }

  /** 仕様: Core 第11.9節。小数剰余の大きい順。差が負なら負方向へ配る。 */
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

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  private class LineRemaining {
    Id lineId;
    Decimal remainingInclusive;
  }

  private class InvoiceSnapshot {
    Decimal taxInclusiveAmount;
    Decimal invoicePaymentNet;
    List<LineRemaining> remainings;
  }

  public class AllocationException extends Exception {
  }
}
