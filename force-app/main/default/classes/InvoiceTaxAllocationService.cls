/**
 * 確定時にヘッダ税を請求明細へ符号付き最大剰余で配分する。
 */
public without sharing class InvoiceTaxAllocationService {
  public static final String MISSING_INVOICE_MESSAGE = '確定する請求がありません。';
  public static final String MISSING_TAX_MESSAGE = '請求の税額がありません。';
  public static final String MISSING_LINE_AMOUNT_MESSAGE = '請求明細の税抜金額がありません。';
  public static final String EMPTY_LINES_TAX_MESSAGE = '請求明細が無いため税額を配分できません。';
  public static final String ZERO_WEIGHT_TAX_MESSAGE = '請求明細の税抜合計が0のため税額を配分できません。';

  /** 仕様: Core 第11.9節、第1.1.10節、Accounting 第3.2節 */
  public static void allocateOnConfirm(Invoice__c invoice) {
    if (invoice == null || invoice.Id == null) {
      throw new TaxAllocationException(MISSING_INVOICE_MESSAGE);
    }
    GlAccountingSetting__mdt setting = AmountCalculationSettingService.requireOrgDefault();
    invoice.AppliedTaxRoundingMode__c = setting.TaxRoundingMode__c;
    Decimal headerTax = resolveHeaderTax(invoice);
    List<InvoiceLine__c> lines = [
      SELECT Id, Amount__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :invoice.Id
      WITH SYSTEM_MODE
      ORDER BY Id
    ];
    if (lines.isEmpty()) {
      if (headerTax != 0) {
        throw new TaxAllocationException(EMPTY_LINES_TAX_MESSAGE);
      }
      return;
    }
    Decimal weightTotal = 0;
    for (InvoiceLine__c line : lines) {
      if (line.Amount__c == null) {
        throw new TaxAllocationException(MISSING_LINE_AMOUNT_MESSAGE);
      }
      weightTotal += line.Amount__c;
    }
    if (weightTotal == 0 && headerTax != 0) {
      throw new TaxAllocationException(ZERO_WEIGHT_TAX_MESSAGE);
    }
    List<Decimal> theoretical = new List<Decimal>();
    List<Integer> truncated = new List<Integer>();
    Decimal assigned = 0;
    for (InvoiceLine__c line : lines) {
      Decimal theory = weightTotal == 0
        ? 0
        : headerTax * line.Amount__c / weightTotal;
      theoretical.add(theory);
      Integer cut = theory >= 0
        ? theory.intValue()
        : -((-theory).intValue());
      truncated.add(cut);
      assigned += cut;
    }
    Decimal remainder = headerTax - assigned;
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
    List<InvoiceLine__c> updates = new List<InvoiceLine__c>();
    for (Integer i = 0; i < lines.size(); i++) {
      updates.add(
        new InvoiceLine__c(
          Id = lines[i].Id,
          AllocatedTaxAmount__c = truncated[i]
        )
      );
    }
    SystemContextAccess.updateRecords(updates);
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

  private static Decimal resolveHeaderTax(Invoice__c invoice) {
    Decimal headerTax;
    if (invoice.isSet(Invoice__c.TaxAmount__c)) {
      headerTax = invoice.TaxAmount__c;
    } else {
      Invoice__c loaded = [
        SELECT TaxAmount__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
        WITH SYSTEM_MODE
      ];
      headerTax = loaded.TaxAmount__c;
    }
    if (headerTax == null) {
      throw new TaxAllocationException(MISSING_TAX_MESSAGE);
    }
    return headerTax;
  }

  public class TaxAllocationException extends Exception {
  }
}
