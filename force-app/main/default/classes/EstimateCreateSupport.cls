/**
 * Shared helpers for EstimateCreate* services (parse/normalize/date/boolean).
 */
public without sharing class EstimateCreateSupport {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ARCHIVE = ContractDomainConstants.HISTORY_STATUS_ARCHIVE;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;
  private static final String HISTORY_TYPE_NEW = ContractDomainConstants.HISTORY_TYPE_NEW;
  private static final String HISTORY_TYPE_CHANGE = ContractDomainConstants.HISTORY_TYPE_CHANGE;
  private static final String HISTORY_TYPE_RENEW = ContractDomainConstants.HISTORY_TYPE_RENEW;
  private static final String HISTORY_TYPE_CANCEL = ContractDomainConstants.HISTORY_TYPE_CANCEL;
  private static final String BILLING_TYPE_RECURRING = ContractDomainConstants.BILLING_TYPE_RECURRING;
  private static final String BILLING_TYPE_ONE_TIME = ContractDomainConstants.BILLING_TYPE_ONE_TIME;
  private static final String MONTHLY_BILLING_CYCLE = ContractDomainConstants.MONTHLY_BILLING_CYCLE;
  private static final String PRODUCT_TYPE_ORIGINAL = ContractDomainConstants.PRODUCT_TYPE_ORIGINAL;
  private static final String PRODUCT_TYPE_REMAKE = ContractDomainConstants.PRODUCT_TYPE_REMAKE;
  private static final String LEGACY_PRODUCT_TYPE_DERIVATIVE = ContractDomainConstants.LEGACY_PRODUCT_TYPE_DERIVATIVE;
  private static final String PRODUCT_TYPE_NEW = ContractDomainConstants.PRODUCT_TYPE_NEW;
  private static final String PRODUCT_TYPE_RENEW = ContractDomainConstants.PRODUCT_TYPE_RENEW;
  private static final Integer NOTE_MAX_LENGTH = ContractDomainConstants.NOTE_MAX_LENGTH;

  public static Date tryParseDate(String dateValue) {
    if (String.isBlank(dateValue)) {
      return null;
    }
    try {
      return Date.valueOf(dateValue);
    } catch (Exception e) {
      return null;
    }
  }

  // マスタ単位をそのまま表示する（継続課金でも「・月」は付与しない）。
  public static String buildDisplayUnit(String unitName, String billingType) {
    return unitName;
  }

  public static String resolveRecurringBillingCycleLabel(String billingType) {
    return billingType == BILLING_TYPE_RECURRING ? MONTHLY_BILLING_CYCLE : null;
  }

  public static List<EstimateCreateController.ProductLineItem> parseProducts(
    String productsJson
  ) {
    List<EstimateCreateController.ProductLineItem> lines = new List<EstimateCreateController.ProductLineItem>();
    if (String.isBlank(productsJson)) {
      return lines;
    }

    for (Object row : (List<Object>) JSON.deserializeUntyped(productsJson)) {
      Map<String, Object> item = (Map<String, Object>) row;
      EstimateCreateController.ProductLineItem line = new EstimateCreateController.ProductLineItem();
      line.productId = (Id) item.get('productId');
      line.quantity = toDecimal(item.get('quantity'));
      line.unitPrice = toDecimal(item.get('unitPrice'));
      line.amount = toDecimal(item.get('amount'));
      line.startDate = (String) item.get('startDate');
      line.endDate = (String) item.get('endDate');
      line.invoiceType = (String) item.get('invoiceType');
      line.unit = (String) item.get('unit');
      line.unitName = (String) item.get('unitName');
      line.productName = (String) item.get('productName');
      line.billingType = (String) item.get('billingType');
      line.billingCycle = (String) item.get('billingCycle');
      // 仕様: Core 第4.3.4節、第4.5.2節、第1.1.10節。画面の売上計上基準を保存へ載せる。
      line.revenueRecognitionBasis = (String) item.get(
        'revenueRecognitionBasis'
      );
      line.recordType = normalizeProductRecordType(
        (String) item.get('recordType')
      );
      line.typeLabel = (String) item.get('typeLabel');
      line.isDuplicate = toBoolean(item.get('isDuplicate'));
      line.sourceContractProductId = (Id) item.get('sourceContractProductId');
      line.contractProductId = (Id) item.get('contractProductId');
      line.isReadonly = toBoolean(item.get('isReadonly'));
      line.pairId = (String) item.get('pairId');
      line.customFields = parseProductCustomFields(item.get('customFields'));
      line.productVisibilityContext = parseProductVisibilityContext(
        item.get('productVisibilityContext')
      );
      lines.add(line);
    }
    return lines;
  }

  public static Map<String, Object> parseProductCustomFields(
    Object rawCustomFields
  ) {
    if (!(rawCustomFields instanceof Map<String, Object>)) {
      return new Map<String, Object>();
    }
    return (Map<String, Object>) rawCustomFields;
  }

  public static Map<String, String> parseProductVisibilityContext(
    Object rawContext
  ) {
    Map<String, String> context = new Map<String, String>();
    if (!(rawContext instanceof Map<String, Object>)) {
      return context;
    }
    Map<String, Object> rawMap = (Map<String, Object>) rawContext;
    for (String key : rawMap.keySet()) {
      Object value = rawMap.get(key);
      if (value == null) {
        context.put(key, null);
      } else {
        context.put(key, String.valueOf(value));
      }
    }
    return context;
  }

  public static String normalizeProductRecordType(String recordType) {
    if (String.isBlank(recordType)) {
      return PRODUCT_TYPE_NEW;
    }
    String value = recordType.trim();
    if (value.equalsIgnoreCase(LEGACY_PRODUCT_TYPE_DERIVATIVE)) {
      return PRODUCT_TYPE_REMAKE;
    }
    if (value == PRODUCT_TYPE_ORIGINAL) {
      return PRODUCT_TYPE_ORIGINAL;
    }
    if (value == PRODUCT_TYPE_REMAKE) {
      return PRODUCT_TYPE_REMAKE;
    }
    if (value == PRODUCT_TYPE_RENEW) {
      return PRODUCT_TYPE_RENEW;
    }
    if (value == PRODUCT_TYPE_NEW) {
      return PRODUCT_TYPE_NEW;
    }
    return value;
  }

  public static Boolean isChangeOriginalLine(
    EstimateCreateController.ProductLineItem line
  ) {
    if (line == null) {
      return false;
    }
    // Original は recordType のみで判定する（Remake+isReadonly のフォールバックは廃止）。
    return normalizeProductRecordType(line.recordType) == PRODUCT_TYPE_ORIGINAL;
  }

  public static Boolean isChangeRemakeLine(
    EstimateCreateController.ProductLineItem line
  ) {
    if (line == null || line.sourceContractProductId == null) {
      return false;
    }
    if (isChangeOriginalLine(line)) {
      return false;
    }
    return normalizeProductRecordType(line.recordType) == PRODUCT_TYPE_REMAKE;
  }

  public static Boolean toBoolean(Object value) {
    if (value == null) {
      return false;
    }
    if (value instanceof Boolean) {
      return (Boolean) value;
    }
    return Boolean.valueOf(String.valueOf(value));
  }

  public static Decimal toDecimal(Object value) {
    if (value == null || String.isBlank(String.valueOf(value))) {
      return null;
    }
    return Decimal.valueOf(String.valueOf(value));
  }

  public static Date parseDate(String dateValue) {
    if (String.isBlank(dateValue)) {
      return null;
    }
    return Date.valueOf(dateValue);
  }

  public static String formatDate(Date dateValue) {
    return dateValue == null ? null : String.valueOf(dateValue);
  }
}
