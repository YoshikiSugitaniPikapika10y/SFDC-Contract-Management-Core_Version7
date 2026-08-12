/**
 * 請求書／請求明細マージキーの CMDT 設定読み込みと組み立て。
 * 組織で1セット。受注時生成でのみ利用する。
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
  public static final String PART_UNIT = 'Unit';
  public static final String PART_PRODUCT = 'Product';

  private static final Set<String> INVOICE_PARTS = new Set<String>{
    PART_BILLING_ACCOUNT,
    PART_CONTRACT_HISTORY,
    PART_INVOICE_DATE,
    PART_PAYMENT_SCHEDULED_DATE
  };
  private static final Set<String> LINE_PARTS = new Set<String>{
    PART_CONTRACT_PRODUCT,
    PART_UNIT_PRICE,
    PART_QUANTITY,
    PART_UNIT,
    PART_PRODUCT
  };
  /** 別契約履歴の請求が同一キーに衝突しないよう ContractHistory も必須 */
  private static final Set<String> REQUIRED_INVOICE_PARTS = new Set<String>{
    PART_BILLING_ACCOUNT,
    PART_CONTRACT_HISTORY,
    PART_INVOICE_DATE
  };
  private static final Set<String> REQUIRED_LINE_PARTS = new Set<String>{
    PART_CONTRACT_PRODUCT
  };

  private static final Map<String, String> PART_PREFIX = new Map<String, String>{
    PART_BILLING_ACCOUNT => 'BA',
    PART_CONTRACT_HISTORY => 'CH',
    PART_INVOICE_DATE => 'DT',
    PART_PAYMENT_SCHEDULED_DATE => 'PD',
    PART_CONTRACT_PRODUCT => 'CP',
    PART_UNIT_PRICE => 'UP',
    PART_QUANTITY => 'Q',
    PART_UNIT => 'U',
    PART_PRODUCT => 'P'
  };

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

  @TestVisible
  static List<InvoiceMergeKeyPart__mdt> cachedDefinitions;

  @TestVisible
  static void resetCache() {
    cachedDefinitions = null;
  }

  public static void validateActiveDefinitions() {
    List<InvoiceMergeKeyPart__mdt> invoiceParts = getActiveParts(SCOPE_INVOICE);
    List<InvoiceMergeKeyPart__mdt> lineParts = getActiveParts(SCOPE_INVOICE_LINE);
    validateScopeParts(SCOPE_INVOICE, invoiceParts, INVOICE_PARTS, REQUIRED_INVOICE_PARTS);
    validateScopeParts(SCOPE_INVOICE_LINE, lineParts, LINE_PARTS, REQUIRED_LINE_PARTS);
  }

  public static String buildInvoiceBucketKey(InvoiceKeyInput input) {
    validateActiveDefinitions();
    if (input == null) {
      input = new InvoiceKeyInput();
    }
    List<String> segments = new List<String>();
    for (InvoiceMergeKeyPart__mdt definition : getActiveParts(SCOPE_INVOICE)) {
      String value = resolveInvoicePartValue(definition.Part__c, input);
      segments.add(PART_PREFIX.get(definition.Part__c) + '=' + value);
    }
    return 'INV|' + String.join(segments, '|');
  }

  public static String buildLineBucketKey(LineKeyInput input) {
    validateActiveDefinitions();
    if (input == null) {
      input = new LineKeyInput();
    }
    List<String> segments = new List<String>();
    for (InvoiceMergeKeyPart__mdt definition : getActiveParts(SCOPE_INVOICE_LINE)) {
      String value = resolveLinePartValue(definition.Part__c, input);
      segments.add(PART_PREFIX.get(definition.Part__c) + '=' + value);
    }
    return 'LINE|' + String.join(segments, '|');
  }

  public static String buildLineBucketKeyFromProduct(InvoiceProduct__c product) {
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

  @TestVisible
  static List<InvoiceMergeKeyPart__mdt> getActiveParts(String scope) {
    List<InvoiceMergeKeyPart__mdt> matched = new List<InvoiceMergeKeyPart__mdt>();
    for (InvoiceMergeKeyPart__mdt definition : getAllDefinitions()) {
      if (definition == null || definition.Active__c != true) {
        continue;
      }
      if (definition.Scope__c != scope) {
        continue;
      }
      matched.add(definition);
    }
    matched.sort(new PartSortComparator());
    return matched;
  }

  private static List<InvoiceMergeKeyPart__mdt> getAllDefinitions() {
    if (cachedDefinitions != null) {
      return cachedDefinitions;
    }
    cachedDefinitions = [
      SELECT DeveloperName, MasterLabel, Active__c, Scope__c, Part__c, SortOrder__c
      FROM InvoiceMergeKeyPart__mdt
    ];
    return cachedDefinitions;
  }

  private static void validateScopeParts(
    String scope,
    List<InvoiceMergeKeyPart__mdt> parts,
    Set<String> allowedParts,
    Set<String> requiredParts
  ) {
    if (parts == null || parts.isEmpty()) {
      throw new MergeKeyConfigException(
        '請求マージキー部品（' + scopeLabel(scope) + '）が1件も有効ではありません。'
      );
    }
    Set<String> seen = new Set<String>();
    Set<String> activeParts = new Set<String>();
    for (InvoiceMergeKeyPart__mdt definition : parts) {
      String part = definition.Part__c;
      if (String.isBlank(part) || !allowedParts.contains(part)) {
        throw new MergeKeyConfigException(
          '請求マージキー部品「' +
            definitionLabel(definition) +
            '」の部品「' +
            part +
            '」は ' +
            scopeLabel(scope) +
            ' では使えません。'
        );
      }
      if (seen.contains(part)) {
        throw new MergeKeyConfigException(
          '請求マージキー部品（' +
            scopeLabel(scope) +
            '）の部品「' +
            part +
            '」が重複しています。'
        );
      }
      seen.add(part);
      activeParts.add(part);
    }
    for (String required : requiredParts) {
      if (!activeParts.contains(required)) {
        throw new MergeKeyConfigException(
          '請求マージキー部品（' +
            scopeLabel(scope) +
            '）に必須部品「' +
            required +
            '」がありません。'
        );
      }
    }
  }

  private static String resolveInvoicePartValue(String part, InvoiceKeyInput input) {
    if (part == PART_BILLING_ACCOUNT) {
      return formatId(input.billingAccountId);
    }
    if (part == PART_CONTRACT_HISTORY) {
      return formatId(input.contractHistoryId);
    }
    if (part == PART_INVOICE_DATE) {
      return formatDate(input.invoiceDate);
    }
    if (part == PART_PAYMENT_SCHEDULED_DATE) {
      return formatDate(input.paymentScheduledDate);
    }
    return '';
  }

  private static String resolveLinePartValue(String part, LineKeyInput input) {
    if (part == PART_CONTRACT_PRODUCT) {
      return formatId(input.contractProductId);
    }
    if (part == PART_UNIT_PRICE) {
      return formatDecimal(input.unitPrice);
    }
    if (part == PART_QUANTITY) {
      return formatDecimal(input.quantity);
    }
    if (part == PART_UNIT) {
      return formatText(input.unit);
    }
    if (part == PART_PRODUCT) {
      return formatId(input.productId);
    }
    return '';
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

  private static String formatText(String value) {
    return String.isBlank(value) ? '' : value;
  }

  private static String scopeLabel(String scope) {
    if (scope == SCOPE_INVOICE) {
      return '請求書';
    }
    if (scope == SCOPE_INVOICE_LINE) {
      return '請求明細';
    }
    return scope;
  }

  private static String definitionLabel(InvoiceMergeKeyPart__mdt definition) {
    if (definition == null) {
      return '';
    }
    if (String.isNotBlank(definition.MasterLabel)) {
      return definition.MasterLabel;
    }
    return definition.DeveloperName;
  }

  private class PartSortComparator implements Comparator<InvoiceMergeKeyPart__mdt> {
    public Integer compare(
      InvoiceMergeKeyPart__mdt left,
      InvoiceMergeKeyPart__mdt right
    ) {
      Decimal leftOrder = left == null || left.SortOrder__c == null
        ? 0
        : left.SortOrder__c;
      Decimal rightOrder = right == null || right.SortOrder__c == null
        ? 0
        : right.SortOrder__c;
      if (leftOrder < rightOrder) {
        return -1;
      }
      if (leftOrder > rightOrder) {
        return 1;
      }
      String leftName = left == null ? '' : String.valueOf(left.DeveloperName);
      String rightName = right == null ? '' : String.valueOf(right.DeveloperName);
      return leftName.compareTo(rightName);
    }
  }
}
