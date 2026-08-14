/**
 * 請求明細のマージキー組み立て（契約サービス・商品・期間など）。
 */
public without sharing class InvoiceProductMergeKeyUtil {
  public static String buildMergeKey(
    Id contractServiceId,
    Id productId,
    Date startDate,
    Date endDate,
    Decimal quantity,
    Decimal unitPrice,
    String unit
  ) {
    return String.valueOf(contractServiceId) +
      '_' +
      String.valueOf(productId) +
      '_' +
      String.valueOf(startDate) +
      '_' +
      String.valueOf(endDate) +
      '_' +
      formatDecimal(quantity) +
      '_' +
      formatDecimal(unitPrice) +
      '_' +
      formatText(unit);
  }

  public static String buildPeriodKey(
    Id contractServiceId,
    Id productId,
    Date startDate,
    Date endDate
  ) {
    return String.valueOf(contractServiceId) +
      '_' +
      String.valueOf(productId) +
      '_' +
      String.valueOf(startDate) +
      '_' +
      String.valueOf(endDate);
  }

  public static String extractPeriodKey(String mergeKey) {
    if (String.isBlank(mergeKey)) {
      return null;
    }
    List<String> parts = mergeKey.split('_');
    if (parts.size() < 4) {
      return null;
    }
    return parts[0] + '_' + parts[1] + '_' + parts[2] + '_' + parts[3];
  }

  public static String buildMergeKey(InvoiceProduct__c invoiceProduct) {
    if (invoiceProduct == null) {
      return null;
    }
    if (String.isNotBlank(invoiceProduct.InvoiceBucketKey__c)) {
      return invoiceProduct.InvoiceBucketKey__c;
    }
    return buildMergeKeyFromContractProductReference(invoiceProduct);
  }

  public static String buildMergeKeyFromContractProductReference(
    InvoiceProduct__c invoiceProduct
  ) {
    if (invoiceProduct == null) {
      return null;
    }
    ContractProduct__c contractProduct = invoiceProduct.ContractProduct__r;
    return buildMergeKey(
      invoiceProduct.ContractHistory__r == null
        ? null
        : invoiceProduct.ContractHistory__r.ContractService__c,
      contractProduct == null ? null : contractProduct.Product__c,
      invoiceProduct.StartDate__c,
      invoiceProduct.Enddate__c,
      contractProduct == null ? null : contractProduct.Quantity__c,
      contractProduct == null ? null : contractProduct.UnitPrice__c,
      contractProduct == null ? null : contractProduct.Unit__c
    );
  }

  private static String formatDecimal(Decimal value) {
    if (value == null) {
      return '0';
    }
    return value.stripTrailingZeros().toPlainString();
  }

  private static String formatText(String value) {
    if (String.isBlank(value)) {
      return '';
    }
    return value.replace('_', '~');
  }

  public static String buildExportInvoiceMergeKey(
    Id billingAccountId,
    Id contractHistoryId,
    Date invoiceDate,
    Date paymentScheduledDate
  ) {
    return InvoiceMergeKeyConfigService.buildInvoiceBucketKey(
      billingAccountId,
      contractHistoryId,
      invoiceDate,
      paymentScheduledDate
    );
  }

  public static Date parseInvoiceDateFromExportMergeKey(String key) {
    return parseExportMergeKeyDate(key, 'DT=');
  }

  public static Date parsePaymentScheduledDateFromExportMergeKey(String key) {
    return parseExportMergeKeyDate(key, 'PD=');
  }

  public static Id parseBillingAccountIdFromExportMergeKey(String key) {
    return parseExportMergeKeyId(key, 'BA=');
  }

  private static String formatExportMergeKeyDate(Date value) {
    return value == null ? '' : String.valueOf(value);
  }

  private static Date parseExportMergeKeyDate(String key, String prefix) {
    String raw = extractExportMergeKeySegment(key, prefix);
    if (String.isBlank(raw)) {
      return null;
    }
    try {
      return Date.valueOf(raw);
    } catch (Exception ex) {
      return null;
    }
  }

  private static Id parseExportMergeKeyId(String key, String prefix) {
    String raw = extractExportMergeKeySegment(key, prefix);
    if (String.isBlank(raw)) {
      return null;
    }
    try {
      return (Id) raw;
    } catch (Exception ex) {
      return null;
    }
  }

  private static String extractExportMergeKeySegment(
    String key,
    String prefix
  ) {
    if (String.isBlank(key) || String.isBlank(prefix)) {
      return null;
    }
    Integer startIndex = key.indexOf(prefix);
    if (startIndex < 0) {
      return null;
    }
    startIndex += prefix.length();
    Integer endIndex = key.indexOf('|', startIndex);
    if (endIndex < 0) {
      return key.substring(startIndex);
    }
    return key.substring(startIndex, endIndex);
  }
}
