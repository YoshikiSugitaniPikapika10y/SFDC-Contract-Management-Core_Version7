/**
 * 請求プレビュー用の回収ステータス金額（排他バケツ）。
 * 請求前 + 請求済（未消込）+ 入金消込 = 税抜合計。
 * 回収状態の正は CollectionRefundStatus__c、請求金額処理済みの正は InvoicePaymentNet__c。
 */
public without sharing class InvoicePaymentStatusUtil {
  public class StatusAmounts {
    public Decimal openAmount;
    public Decimal integratedAmount;
    public Decimal clearedAmount;

    public StatusAmounts(
      Decimal openAmount,
      Decimal integratedAmount,
      Decimal clearedAmount
    ) {
      this.openAmount = openAmount == null ? 0 : openAmount;
      this.integratedAmount = integratedAmount == null ? 0 : integratedAmount;
      this.clearedAmount = clearedAmount == null ? 0 : clearedAmount;
    }
  }

  /** 仕様: Core 第8.7節、第8.10節。請求金額Netを税抜表示額へ比例配分する。 */
  public static Decimal resolveClearedAmount(
    Invoice__c invoice,
    Decimal amountTotal
  ) {
    Decimal amount = amountTotal == null ? 0 : amountTotal;
    if (invoice == null || amount == 0) {
      return 0;
    }
    if (
      invoice.CollectionRefundStatus__c ==
      InvoiceTransactionStatusService.COLLECTION_COMPLETED
    ) {
      return amount;
    }
    if (
      !InvoiceTransactionStatusService.isConfirmed(invoice) ||
      invoice.InvoicePaymentNet__c == null ||
      invoice.InvoicePaymentNet__c == 0
    ) {
      return 0;
    }
    Decimal taxInclusive = invoice.TaxInclusiveAmount__c;
    if (taxInclusive == null) {
      taxInclusive =
        (invoice.Amount__c == null ? 0 : invoice.Amount__c) +
        (invoice.TaxAmount__c == null ? 0 : invoice.TaxAmount__c);
    }
    if (taxInclusive == 0) {
      return 0;
    }
    Decimal allocated = (
      amount *
      invoice.InvoicePaymentNet__c /
      taxInclusive
    ).setScale(0, RoundingMode.HALF_UP);
    return clampToAmount(allocated, amount);
  }

  public static StatusAmounts resolveStatusAmounts(
    Invoice__c invoice,
    Decimal amountTotal
  ) {
    Decimal amount = amountTotal == null ? 0 : amountTotal;
    Decimal cleared = resolveClearedAmount(invoice, amount);
    Boolean draft =
      invoice == null || InvoiceTransactionStatusService.isDraft(invoice);
    if (draft) {
      return new StatusAmounts(amount - cleared, 0, cleared);
    }
    return new StatusAmounts(0, amount - cleared, cleared);
  }

  public static StatusAmounts allocateLineStatusAmounts(
    Decimal lineAmount,
    Decimal invoiceAmountTotal,
    StatusAmounts invoiceStatus
  ) {
    Decimal line = lineAmount == null ? 0 : lineAmount;
    Decimal invoiceAmount = invoiceAmountTotal == null ? 0 : invoiceAmountTotal;
    if (invoiceStatus == null) {
      return new StatusAmounts(line, 0, 0);
    }
    if (invoiceAmount == 0) {
      return new StatusAmounts(0, 0, 0);
    }
    Decimal cleared = scaleAmount(
      line,
      invoiceAmount,
      invoiceStatus.clearedAmount
    );
    Decimal integrated = scaleAmount(
      line,
      invoiceAmount,
      invoiceStatus.integratedAmount
    );
    // 端数は請求前側に吸収して line = open + integrated + cleared を保つ
    Decimal open = line - cleared - integrated;
    return new StatusAmounts(open, integrated, cleared);
  }

  private static Decimal scaleAmount(
    Decimal lineAmount,
    Decimal invoiceAmount,
    Decimal bucketAmount
  ) {
    if (bucketAmount == null || bucketAmount == 0 || invoiceAmount == 0) {
      return 0;
    }
    return (lineAmount *
      bucketAmount /
      invoiceAmount)
      .setScale(0, RoundingMode.HALF_UP);
  }

  private static Decimal clampToAmount(Decimal cleared, Decimal amount) {
    if (amount >= 0) {
      if (cleared < 0) {
        return 0;
      }
      if (cleared > amount) {
        return amount;
      }
      return cleared;
    }
    if (cleared > 0) {
      return 0;
    }
    if (cleared < amount) {
      return amount;
    }
    return cleared;
  }
}
