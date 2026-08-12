/**
 * 請求プレビュー用の入金ステータス金額（排他バケツ）。
 * 請求前 + 請求済（未消込）+ 入金消込 = 税抜合計。
 * 入金消込額／消込完了日は手動。日付変更で金額を自動セット／クリアしない。
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

  /**
   * 入金消込額は手入力値のみ。未設定は 0（消込完了日があっても自動で税抜合計とみなさない）。
   */
  public static Decimal resolveClearedAmount(
    Invoice__c invoice,
    Decimal amountTotal
  ) {
    Decimal amount = amountTotal == null ? 0 : amountTotal;
    if (invoice == null || invoice.PaymentClearedAmount__c == null) {
      return 0;
    }
    return clampToAmount(invoice.PaymentClearedAmount__c, amount);
  }

  public static StatusAmounts resolveStatusAmounts(
    Invoice__c invoice,
    Decimal amountTotal
  ) {
    Decimal amount = amountTotal == null ? 0 : amountTotal;
    Decimal cleared = resolveClearedAmount(invoice, amount);
    Boolean invoiced = InvoiceLockUtil.isInvoiced(invoice);
    if (!invoiced) {
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
    Decimal cleared = scaleAmount(line, invoiceAmount, invoiceStatus.clearedAmount);
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
    return (lineAmount * bucketAmount / invoiceAmount)
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
