/**
 * 請求書／請求明細マージキーの静的組み立て。
 * キー構成はパッケージ固定（CMDT なし）。
 * 請求: BA + CH + DT + PD / 明細: CP + UP + Q
 */
public without sharing class InvoiceMergeKeyConfigService {
  public static final String SCOPE_INVOICE = 'Invoice';
  public static final String SCOPE_INVOICE_LINE = 'InvoiceLine';

  public static final String PART_BILLING_ACCOUNT = 'BillingAccount';
  public static final String PART_CONTRACT_HISTORY = 'ContractHistory';
  public static final String PART_INVOICE_DATE = 'InvoiceDate';
  public static final String PART_PAYMENT_SCHEDULED_DATE = 'PaymentScheduledDate';
  public static final String PART_CONTRACT_PRODUCT = 'ContractProduct';
  public static final String PART_UNIT_PRICE = 'UnitPrice';
  public static final String PART_QUANTITY = 'Quantity';

  public class MergeKeyConfigException extends Exception {
  }

  public class InvoiceKeyInput {
    public Id billingAccountId;
    public Id contractHistoryId;
    public Date invoiceDate;
    public Date paymentScheduledDate;
  }

  public class LineKeyInput {
    public Id contractProductId;
    public Id productId;
    public Decimal unitPrice;
    public Decimal quantity;
    public String unit;
  }

  /** 互換用 no-op。キーは静的固定のため検証不要。 */
  public static void validateActiveDefinitions() {
  }

  public static String buildInvoiceBucketKey(InvoiceKeyInput input) {
    if (input == null) {
      input = new InvoiceKeyInput();
    }
    return 'INV|BA=' +
      formatId(input.billingAccountId) +
      '|CH=' +
      formatId(input.contractHistoryId) +
      '|DT=' +
      formatDate(input.invoiceDate) +
      '|PD=' +
      formatDate(input.paymentScheduledDate);
  }

  public static String buildLineBucketKey(LineKeyInput input) {
    if (input == null) {
      input = new LineKeyInput();
    }
    return 'LINE|CP=' +
      formatId(input.contractProductId) +
      '|UP=' +
      formatDecimal(input.unitPrice) +
      '|Q=' +
      formatDecimal(input.quantity);
  }

  public static String buildLineBucketKeyFromProduct(
    InvoiceProduct__c product
  ) {
    LineKeyInput input = new LineKeyInput();
    if (product != null) {
      Map<String, Object> fields = product.getPopulatedFieldsAsMap();
      if (fields.containsKey('ContractProduct__c')) {
        input.contractProductId = (Id) fields.get('ContractProduct__c');
      }
      if (fields.containsKey('UnitPrice__c')) {
        input.unitPrice = (Decimal) fields.get('UnitPrice__c');
      }
      if (fields.containsKey('Quantity__c')) {
        input.quantity = (Decimal) fields.get('Quantity__c');
      }
      if (fields.containsKey('Unit__c')) {
        input.unit = (String) fields.get('Unit__c');
      }
      if (
        fields.containsKey('ContractProduct__r') &&
        product.ContractProduct__r != null
      ) {
        Map<String, Object> cpFields = product.ContractProduct__r.getPopulatedFieldsAsMap();
        if (cpFields.containsKey('Product__c')) {
          input.productId = (Id) cpFields.get('Product__c');
        }
      }
    }
    return buildLineBucketKey(input);
  }

  public static String buildInvoiceBucketKey(
    Id billingAccountId,
    Id contractHistoryId,
    Date invoiceDate,
    Date paymentScheduledDate
  ) {
    InvoiceKeyInput input = new InvoiceKeyInput();
    input.billingAccountId = billingAccountId;
    input.contractHistoryId = contractHistoryId;
    input.invoiceDate = invoiceDate;
    input.paymentScheduledDate = paymentScheduledDate;
    return buildInvoiceBucketKey(input);
  }

  public static String buildLineBucketKey(
    Id contractProductId,
    Decimal unitPrice,
    Decimal quantity,
    String unit,
    Id productId
  ) {
    LineKeyInput input = new LineKeyInput();
    input.contractProductId = contractProductId;
    input.unitPrice = unitPrice;
    input.quantity = quantity;
    input.unit = unit;
    input.productId = productId;
    return buildLineBucketKey(input);
  }

  private static String formatId(Id value) {
    return value == null ? '' : String.valueOf(value);
  }

  private static String formatDate(Date value) {
    return value == null ? '' : String.valueOf(value);
  }

  private static String formatDecimal(Decimal value) {
    if (value == null) {
      return '0';
    }
    return value.stripTrailingZeros().toPlainString();
  }
}
