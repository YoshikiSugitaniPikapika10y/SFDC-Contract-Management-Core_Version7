/**
 * 請求明細のマージ（同一キーの合算・消込残高など）を行う。
 */
public without sharing class InvoiceProductMergeService {
  public class MergeKeyException extends Exception {
  }

  public class MergedInvoice {
    public String mergeKey;
    public String contractServiceName;
    public String billingAccountName;
    public Date invoiceDate;
    public Date paymentScheduledDate;
    public Decimal amountTotal;
    public Decimal taxTotal;
    public Decimal taxPercent;
    public Decimal integratedAmount;
    public Decimal clearedAmount;
    public Decimal openAmount;
    public List<MergedLine> lines;
    public List<InvoiceProduct__c> sourceProducts;
  }

  public class MergedLine {
    public String lineMergeKey;
    public String productName;
    public String historyVersionLabel;
    public List<Decimal> historyVersions;
    public Decimal unitPrice;
    public Decimal quantity;
    public String periodLabel;
    public Decimal amount;
    public Decimal taxAmount;
    public Decimal integratedAmount;
    public Decimal clearedAmount;
    public Decimal openAmount;
    public List<Id> sourceInvoiceProductIds;
    public List<InvoiceProduct__c> sourceProducts;
    public Boolean isRecurring;
  }

  public static List<MergedInvoice> buildMergedInvoices(
    List<InvoiceProduct__c> products
  ) {
    if (products == null || products.isEmpty()) {
      return new List<MergedInvoice>();
    }

    Map<String, List<InvoiceProduct__c>> productsByInvoiceKey = new Map<String, List<InvoiceProduct__c>>();
    for (InvoiceProduct__c product : products) {
      String invoiceKey = resolveInvoiceMergeKey(product);
      if (String.isBlank(invoiceKey)) {
        continue;
      }
      if (!productsByInvoiceKey.containsKey(invoiceKey)) {
        productsByInvoiceKey.put(invoiceKey, new List<InvoiceProduct__c>());
      }
      productsByInvoiceKey.get(invoiceKey).add(product);
    }

    List<MergedInvoice> invoices = new List<MergedInvoice>();
    for (String invoiceKey : productsByInvoiceKey.keySet()) {
      invoices.add(
        buildMergedInvoice(invoiceKey, productsByInvoiceKey.get(invoiceKey))
      );
    }
    invoices.sort(new MergedInvoiceComparator());
    return invoices;
  }

  public static String buildPeriodLabel(
    List<InvoiceProduct__c> products,
    Boolean mergeContinuousPeriods
  ) {
    if (products == null || products.isEmpty()) {
      return '';
    }

    List<DateRange> ranges = new List<DateRange>();
    for (InvoiceProduct__c product : products) {
      if (product.StartDate__c == null && product.Enddate__c == null) {
        continue;
      }
      ranges.add(new DateRange(product.StartDate__c, product.Enddate__c));
    }
    if (ranges.isEmpty()) {
      return '';
    }
    ranges.sort();

    List<DateRange> displayRanges;
    if (mergeContinuousPeriods == true) {
      displayRanges = mergeContinuousRanges(ranges);
    } else {
      displayRanges = ranges;
    }

    List<String> labels = new List<String>();
    for (DateRange range : displayRanges) {
      String label = formatPeriod(range.startDate, range.endDate);
      if (String.isNotBlank(label)) {
        labels.add(label);
      }
    }
    return String.join(labels, '、');
  }

  public static String formatPeriod(Date startDate, Date endDate) {
    String startLabel = formatDate(startDate);
    String endLabel = formatDate(endDate);
    if (String.isBlank(startLabel) && String.isBlank(endLabel)) {
      return '';
    }
    if (String.isBlank(endLabel)) {
      return startLabel;
    }
    if (String.isBlank(startLabel)) {
      return endLabel;
    }
    return startLabel + '～' + endLabel;
  }

  public static String formatDate(Date value) {
    return value == null ? '' : String.valueOf(value);
  }

  public static String formatHistoryVersionLabel(Decimal version) {
    if (version == null) {
      return '';
    }
    return 'V' + String.valueOf(version.intValue());
  }

  public static String resolveInvoiceMergeKey(InvoiceProduct__c product) {
    if (product == null) {
      return null;
    }
    if (String.isNotBlank(product.InvoiceBucketKey__c)) {
      return product.InvoiceBucketKey__c;
    }
    // 生成時に付与されるべきキー欠落はバグ。黙って FALLBACK 統合しない（Fail closed）
    throw new MergeKeyException(
      '請求マージキー（InvoiceBucketKey）がありません。請求生成をやり直してください。'
    );
  }

  public static String resolveLineMergeKey(InvoiceProduct__c product) {
    if (product == null) {
      return null;
    }
    if (String.isNotBlank(product.LineBucketKey__c)) {
      return product.LineBucketKey__c;
    }
    // 旧データ互換: 生成時キーが無い行は現行 CMDT で組み立てる
    if (product.ContractProduct__c == null && product.Id != null) {
      return 'LINE|FALLBACK=' + String.valueOf(product.Id);
    }
    return InvoiceMergeKeyConfigService.buildLineBucketKeyFromProduct(product);
  }

  private static MergedInvoice buildMergedInvoice(
    String invoiceKey,
    List<InvoiceProduct__c> products
  ) {
    MergedInvoice invoice = new MergedInvoice();
    invoice.mergeKey = invoiceKey;
    invoice.amountTotal = 0;
    invoice.taxTotal = 0;
    invoice.integratedAmount = 0;
    invoice.clearedAmount = 0;
    invoice.openAmount = 0;
    invoice.sourceProducts = products;
    invoice.lines = new List<MergedLine>();

    InvoiceProduct__c representative = products[0];
    for (InvoiceProduct__c product : products) {
      Date productInvoiceDate = InvoiceProductMergeKeyUtil.parseInvoiceDateFromExportMergeKey(
        product.InvoiceBucketKey__c
      );
      Date representativeInvoiceDate = InvoiceProductMergeKeyUtil.parseInvoiceDateFromExportMergeKey(
        representative.InvoiceBucketKey__c
      );
      if (
        representativeInvoiceDate == null ||
        (productInvoiceDate != null &&
        productInvoiceDate < representativeInvoiceDate)
      ) {
        representative = product;
      }
    }
    invoice.invoiceDate = InvoiceProductMergeKeyUtil.parseInvoiceDateFromExportMergeKey(
      representative.InvoiceBucketKey__c
    );
    invoice.paymentScheduledDate = InvoiceProductMergeKeyUtil.parsePaymentScheduledDateFromExportMergeKey(
      representative.InvoiceBucketKey__c
    );
    invoice.contractServiceName = resolveContractServiceName(representative);
    invoice.billingAccountName = resolveBillingAccountName(representative);

    Map<String, List<InvoiceProduct__c>> productsByLineKey = new Map<String, List<InvoiceProduct__c>>();
    for (InvoiceProduct__c product : products) {
      String lineKey = resolveLineMergeKey(product);
      if (String.isBlank(lineKey)) {
        continue;
      }
      if (!productsByLineKey.containsKey(lineKey)) {
        productsByLineKey.put(lineKey, new List<InvoiceProduct__c>());
      }
      productsByLineKey.get(lineKey).add(product);
    }

    for (String lineKey : productsByLineKey.keySet()) {
      MergedLine line = buildMergedLine(
        lineKey,
        productsByLineKey.get(lineKey)
      );
      invoice.lines.add(line);
      invoice.amountTotal += line.amount;
      invoice.integratedAmount += line.integratedAmount;
      invoice.clearedAmount += line.clearedAmount;
    }
    invoice.taxPercent = resolveTaxPercent(products);
    // 行税額の合算はしない。請求マージ単位の税抜合計に対して1回切り捨て。
    invoice.taxTotal = TaxCalculationUtil.calculateTaxAmount(
      invoice.amountTotal,
      invoice.taxPercent
    );
    invoice.openAmount = calculateOpenAmount(products);
    invoice.lines.sort(new MergedLineComparator());
    return invoice;
  }

  private static Decimal resolveTaxPercent(List<InvoiceProduct__c> products) {
    if (products == null) {
      return TaxCalculationUtil.DEFAULT_TAX_PERCENT;
    }
    for (InvoiceProduct__c product : products) {
      if (product != null && product.TaxPercent__c != null) {
        return TaxCalculationUtil.resolveTaxPercent(
          TaxCalculationUtil.fromPercentFieldStorage(product.TaxPercent__c)
        );
      }
    }
    return TaxCalculationUtil.DEFAULT_TAX_PERCENT;
  }

  private static MergedLine buildMergedLine(
    String lineKey,
    List<InvoiceProduct__c> products
  ) {
    products.sort(new InvoiceProductStartDateComparator());

    MergedLine line = new MergedLine();
    line.lineMergeKey = lineKey;
    line.sourceProducts = products;
    line.sourceInvoiceProductIds = new List<Id>();
    line.amount = 0;
    line.taxAmount = 0;
    line.integratedAmount = 0;
    line.clearedAmount = 0;
    line.isRecurring = false;

    Set<String> versionLabels = new Set<String>();
    Set<Decimal> versionNumbers = new Set<Decimal>();
    InvoiceProduct__c representative = products[0];

    for (InvoiceProduct__c product : products) {
      line.sourceInvoiceProductIds.add(product.Id);
      Decimal amount = product.Amount__c == null ? 0 : product.Amount__c;
      line.amount += amount;
      // 連携／消込金額の正は Invoice__c。期間明細からは集計しない。
      if (isRecurringProduct(product)) {
        line.isRecurring = true;
      }
      Decimal versionNumber = product.ContractHistory__r == null
        ? null
        : product.ContractHistory__r.Version__c;
      if (versionNumber != null) {
        versionNumbers.add(versionNumber);
      }
      String versionLabel = formatHistoryVersionLabel(versionNumber);
      if (String.isNotBlank(versionLabel)) {
        versionLabels.add(versionLabel);
      }
      if (line.unitPrice == null && product.UnitPrice__c != null) {
        line.unitPrice = product.UnitPrice__c;
      }
      if (line.quantity == null && product.Quantity__c != null) {
        line.quantity = product.Quantity__c;
      }
      if (String.isBlank(line.productName)) {
        line.productName = resolveProductName(product);
      }
    }

    line.historyVersions = new List<Decimal>(versionNumbers);
    line.historyVersions.sort();
    line.historyVersionLabel = String.join(
      new List<String>(versionLabels),
      ','
    );
    line.openAmount = calculateOpenAmount(products);
    line.periodLabel = buildPeriodLabel(products, line.isRecurring);
    if (line.unitPrice == null) {
      line.unitPrice = representative.UnitPrice__c;
    }
    if (line.quantity == null) {
      line.quantity = representative.Quantity__c;
    }
    if (String.isBlank(line.productName)) {
      line.productName = resolveProductName(representative);
    }
    return line;
  }

  private static Decimal calculateOpenAmount(List<InvoiceProduct__c> products) {
    Decimal openAmount = 0;
    for (InvoiceProduct__c product : products) {
      openAmount += product.Amount__c == null ? 0 : product.Amount__c;
    }
    return openAmount;
  }

  private static Boolean isRecurringProduct(InvoiceProduct__c product) {
    if (product == null || product.ContractProduct__r == null) {
      return false;
    }
    String billingType = product.ContractProduct__r.BillingType__c;
    if (
      String.isBlank(billingType) &&
      product.ContractProduct__r.Product__r != null
    ) {
      billingType = product.ContractProduct__r.Product__r.BillingType__c;
    }
    return ContractMetadataService.isRecurringBillingType(billingType);
  }

  private static String resolveProductName(InvoiceProduct__c product) {
    if (
      product.ContractProduct__r != null &&
      product.ContractProduct__r.Product__r != null &&
      String.isNotBlank(product.ContractProduct__r.Product__r.Name)
    ) {
      return product.ContractProduct__r.Product__r.Name;
    }
    return String.isBlank(product.Name) ? '' : product.Name;
  }

  private static String resolveContractServiceName(InvoiceProduct__c product) {
    if (
      product.ContractHistory__r != null &&
      product.ContractHistory__r.ContractService__r != null
    ) {
      return product.ContractHistory__r.ContractService__r.Name;
    }
    return '';
  }

  private static String resolveBillingAccountName(InvoiceProduct__c product) {
    if (
      product.ContractHistory__r != null &&
      product.ContractHistory__r.ContractService__r != null &&
      product.ContractHistory__r.ContractService__r.BiilingAcccount__r != null
    ) {
      return product.ContractHistory__r.ContractService__r.BiilingAcccount__r.Name;
    }
    return '';
  }

  private static List<DateRange> mergeContinuousRanges(List<DateRange> ranges) {
    List<DateRange> merged = new List<DateRange>();
    for (DateRange range : ranges) {
      if (merged.isEmpty()) {
        merged.add(new DateRange(range.startDate, range.endDate));
        continue;
      }
      DateRange last = merged[merged.size() - 1];
      if (isContinuousOrOverlapping(last, range)) {
        if (
          last.endDate == null ||
          (range.endDate != null &&
          range.endDate > last.endDate)
        ) {
          last.endDate = range.endDate;
        }
        if (
          last.startDate == null ||
          (range.startDate != null &&
          range.startDate < last.startDate)
        ) {
          last.startDate = range.startDate;
        }
      } else {
        merged.add(new DateRange(range.startDate, range.endDate));
      }
    }
    return merged;
  }

  private static Boolean isContinuousOrOverlapping(
    DateRange previousRange,
    DateRange nextRange
  ) {
    if (previousRange == null || nextRange == null) {
      return false;
    }
    if (previousRange.endDate == null || nextRange.startDate == null) {
      return false;
    }
    // Overlap or adjacent (previous end + 1 day == next start).
    return nextRange.startDate <= previousRange.endDate.addDays(1);
  }

  private class DateRange implements Comparable {
    public Date startDate;
    public Date endDate;

    public DateRange(Date startDate, Date endDate) {
      this.startDate = startDate;
      this.endDate = endDate;
    }

    public Integer compareTo(Object other) {
      DateRange otherRange = (DateRange) other;
      if (this.startDate == otherRange.startDate) {
        if (this.endDate == otherRange.endDate) {
          return 0;
        }
        if (this.endDate == null) {
          return 1;
        }
        if (otherRange.endDate == null) {
          return -1;
        }
        return this.endDate < otherRange.endDate
          ? -1
          : this.endDate > otherRange.endDate ? 1 : 0;
      }
      if (this.startDate == null) {
        return 1;
      }
      if (otherRange.startDate == null) {
        return -1;
      }
      return this.startDate < otherRange.startDate
        ? -1
        : this.startDate > otherRange.startDate ? 1 : 0;
    }
  }

  private class MergedInvoiceComparator implements Comparator<MergedInvoice> {
    public Integer compare(MergedInvoice left, MergedInvoice right) {
      Integer dateCompare = compareDates(left.invoiceDate, right.invoiceDate);
      if (dateCompare != 0) {
        return dateCompare;
      }
      Integer paymentCompare = compareDates(
        left.paymentScheduledDate,
        right.paymentScheduledDate
      );
      if (paymentCompare != 0) {
        return paymentCompare;
      }
      return compareText(left.mergeKey, right.mergeKey);
    }
  }

  private class MergedLineComparator implements Comparator<MergedLine> {
    public Integer compare(MergedLine left, MergedLine right) {
      Integer nameCompare = compareText(left.productName, right.productName);
      if (nameCompare != 0) {
        return nameCompare;
      }
      return compareText(left.lineMergeKey, right.lineMergeKey);
    }
  }

  private class InvoiceProductStartDateComparator implements Comparator<InvoiceProduct__c> {
    public Integer compare(InvoiceProduct__c left, InvoiceProduct__c right) {
      Integer dateCompare = compareDates(left.StartDate__c, right.StartDate__c);
      if (dateCompare != 0) {
        return dateCompare;
      }
      return compareText(left.Name, right.Name);
    }
  }

  private static Integer compareDates(Date left, Date right) {
    if (left == right) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return left < right ? -1 : 1;
  }

  private static Integer compareText(String left, String right) {
    String leftValue = left == null ? '' : left;
    String rightValue = right == null ? '' : right;
    if (leftValue == rightValue) {
      return 0;
    }
    return leftValue < rightValue ? -1 : 1;
  }
}
