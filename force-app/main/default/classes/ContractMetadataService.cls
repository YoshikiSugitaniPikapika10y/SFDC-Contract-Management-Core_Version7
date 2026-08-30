/**
 * 契約管理 UI 向けのメタデータ／選択肢取得（請求形態・課金形態・ARR 計算など）。
 */
public without sharing class ContractMetadataService {
  public class InvoiceSettingOption {
    @AuraEnabled
    public String label;

    @AuraEnabled
    public String billingCategory;

    @AuraEnabled
    public Integer sortOrder;
  }

  public enum InvoiceDateRouteType {
    MONTHLY_PERIOD_START,
    BULK_CONTRACT_START,
    BULK_CONTRACT_END_PLUS_ONE
  }

  private class InvoiceSettingDefinition {
    public String label;
    public String billingCategory;
    public Boolean splitMonthlyInvoicePeriods;
    public Boolean useCalendarMonthSplit;
    public Integer sortOrder;
  }

  private static final String BILLING_CATEGORY_RECURRING = 'Recurring';
  private static final String BILLING_CATEGORY_ONE_TIME = 'OneTime';

  public static final String RECURRING_BILLING_TYPE_LABEL = '継続課金';
  public static final String ONE_TIME_BILLING_TYPE_LABEL = '一回課金';
  public static final String MONTHLY_BILLING_CYCLE_LABEL = '月';
  private static final Integer MONTHLY_ARR_ANNUAL_MULTIPLIER = 12;

  public static final String INVOICE_SETTING_PREPAID_START = '一括前払';
  public static final String INVOICE_SETTING_POSTPAID_NEXT_DAY = '一括後払';
  public static final String INVOICE_SETTING_SPLIT_MONTHLY = '月次分割';

  private static final Map<String, InvoiceSettingDefinition> INVOICE_SETTINGS_BY_LABEL = buildInvoiceSettingMap();

  private static List<InvoiceSettingDefinition> invoiceSettings() {
    return new List<InvoiceSettingDefinition>(
      INVOICE_SETTINGS_BY_LABEL.values()
    );
  }

  private static Map<String, InvoiceSettingDefinition> buildInvoiceSettingMap() {
    Map<String, InvoiceSettingDefinition> settingsByLabel = new Map<String, InvoiceSettingDefinition>();
    for (InvoiceSettingDefinition setting : buildInvoiceSettings()) {
      settingsByLabel.put(setting.label, setting);
    }
    return settingsByLabel;
  }

  private static List<InvoiceSettingDefinition> buildInvoiceSettings() {
    return new List<InvoiceSettingDefinition>{
      buildInvoiceSetting(
        INVOICE_SETTING_PREPAID_START,
        BILLING_CATEGORY_RECURRING,
        true,
        false,
        10
      ),
      buildInvoiceSetting(
        INVOICE_SETTING_POSTPAID_NEXT_DAY,
        BILLING_CATEGORY_RECURRING,
        true,
        false,
        20
      ),
      buildInvoiceSetting(
        INVOICE_SETTING_SPLIT_MONTHLY,
        BILLING_CATEGORY_RECURRING,
        true,
        false,
        30
      )
    };
  }

  public static List<InvoiceSettingOption> getActiveInvoiceSettingOptions() {
    List<InvoiceSettingDefinition> settings = invoiceSettings();
    settings.sort(new InvoiceSettingSortComparator());
    List<InvoiceSettingOption> options = new List<InvoiceSettingOption>();
    for (InvoiceSettingDefinition setting : settings) {
      InvoiceSettingOption option = new InvoiceSettingOption();
      option.label = setting.label;
      option.billingCategory = setting.billingCategory;
      option.sortOrder = setting.sortOrder;
      options.add(option);
    }
    return options;
  }

  private class InvoiceSettingSortComparator implements Comparator<InvoiceSettingDefinition> {
    public Integer compare(
      InvoiceSettingDefinition left,
      InvoiceSettingDefinition right
    ) {
      Integer leftOrder = left == null ||
        left.sortOrder == null
        ? 0
        : left.sortOrder;
      Integer rightOrder = right == null ||
        right.sortOrder == null
        ? 0
        : right.sortOrder;
      if (leftOrder == rightOrder) {
        String leftLabel = left == null ? '' : left.label;
        String rightLabel = right == null ? '' : right.label;
        return leftLabel.compareTo(rightLabel);
      }
      return leftOrder - rightOrder;
    }
  }

  public static String getDefaultInvoiceSettingLabel() {
    List<InvoiceSettingDefinition> settings = invoiceSettings();
    return settings.isEmpty() ? null : settings[0].label;
  }

  public static Boolean useCalendarMonthPeriodSplit(
    String invoiceSettingLabel
  ) {
    InvoiceSettingDefinition setting = getInvoiceSetting(invoiceSettingLabel);
    return setting != null && setting.useCalendarMonthSplit == true;
  }

  public static Boolean isRecurringBillingType(String billingTypeLabel) {
    return billingTypeLabel == RECURRING_BILLING_TYPE_LABEL;
  }

  public static final String REVENUE_BASIS_OVER_TIME = '月次計上';
  public static final String REVENUE_BASIS_POINT_IN_TIME = '一括計上';
  private static final String LEGACY_REVENUE_BASIS_OVER_TIME = 'OverTime';
  private static final String LEGACY_REVENUE_BASIS_POINT_IN_TIME = 'PointInTime';

  public static String normalizeRevenueRecognitionBasis(String basis) {
    if (basis == LEGACY_REVENUE_BASIS_OVER_TIME) {
      return REVENUE_BASIS_OVER_TIME;
    }
    if (basis == LEGACY_REVENUE_BASIS_POINT_IN_TIME) {
      return REVENUE_BASIS_POINT_IN_TIME;
    }
    return basis;
  }

  /**
   * 仕様: Core 第1.1.10節、Accounting 第1.16節。
   * 行の値だけを使い、商品マスタや課金形態へ落とさない。
   */
  public static String resolveRevenueRecognitionBasis(String lineBasis) {
    lineBasis = normalizeRevenueRecognitionBasis(lineBasis);
    if (
      lineBasis == REVENUE_BASIS_OVER_TIME ||
      lineBasis == REVENUE_BASIS_POINT_IN_TIME
    ) {
      return lineBasis;
    }
    if (String.isBlank(lineBasis)) {
      throw new RevenueRecognitionBasisException('売上計上基準が空です。');
    }
    throw new RevenueRecognitionBasisException(
      '売上計上基準は月次計上または一括計上です。'
    );
  }

  /**
   * 保存済み行の表示用。空でも商品マスタへ戻さない。
   * 仕様: Core 第1.1.10節
   */
  public static String resolveLineRevenueRecognitionBasis(
    ContractProduct__c product
  ) {
    if (product == null) {
      return null;
    }
    return normalizeRevenueRecognitionBasis(product.RevenueRecognitionBasis__c);
  }

  /** 仕様: Core 第1.1.10節。行の課金形態だけを使い、商品マスタへ戻さない。 */
  public static String resolveLineBillingType(ContractProduct__c product) {
    if (product == null || String.isBlank(product.BillingType__c)) {
      throw new BillingTypeException('課金形態が空です。');
    }
    if (
      product.BillingType__c != RECURRING_BILLING_TYPE_LABEL &&
      product.BillingType__c != ONE_TIME_BILLING_TYPE_LABEL
    ) {
      throw new BillingTypeException('課金形態は継続課金または一回課金です。');
    }
    return product.BillingType__c;
  }

  public static Boolean shouldSplitMonthlyInvoicePeriods(
    String invoiceSettingLabel
  ) {
    InvoiceSettingDefinition setting = getInvoiceSetting(invoiceSettingLabel);
    return setting != null && setting.splitMonthlyInvoicePeriods == true;
  }

  public static String normalizeInvoiceSettingLabel(
    String invoiceSettingLabel
  ) {
    return invoiceSettingLabel;
  }

  public static List<String> getAllowedInvoiceSettingLabels(
    String billingTypeLabel
  ) {
    if (billingTypeLabel == RECURRING_BILLING_TYPE_LABEL) {
      return new List<String>{
        INVOICE_SETTING_PREPAID_START,
        INVOICE_SETTING_POSTPAID_NEXT_DAY,
        INVOICE_SETTING_SPLIT_MONTHLY
      };
    }
    if (billingTypeLabel == ONE_TIME_BILLING_TYPE_LABEL) {
      return new List<String>{
        INVOICE_SETTING_PREPAID_START,
        INVOICE_SETTING_POSTPAID_NEXT_DAY
      };
    }
    return new List<String>();
  }

  public static Boolean isAllowedInvoiceSettingForBillingType(
    String billingTypeLabel,
    String invoiceSettingLabel
  ) {
    String normalized = normalizeInvoiceSettingLabel(invoiceSettingLabel);
    if (String.isBlank(normalized)) {
      return false;
    }
    return getAllowedInvoiceSettingLabels(billingTypeLabel)
      .contains(normalized);
  }

  public static Boolean isSplitMonthlyInvoiceSetting(
    String invoiceSettingLabel
  ) {
    return normalizeInvoiceSettingLabel(invoiceSettingLabel) ==
      INVOICE_SETTING_SPLIT_MONTHLY;
  }

  public static InvoiceDateRouteType resolveInvoiceDateRoute(
    String invoiceSettingLabel
  ) {
    String normalized = normalizeInvoiceSettingLabel(invoiceSettingLabel);
    if (normalized == INVOICE_SETTING_SPLIT_MONTHLY) {
      return InvoiceDateRouteType.MONTHLY_PERIOD_START;
    }
    if (normalized == INVOICE_SETTING_PREPAID_START) {
      return InvoiceDateRouteType.BULK_CONTRACT_START;
    }
    if (normalized == INVOICE_SETTING_POSTPAID_NEXT_DAY) {
      return InvoiceDateRouteType.BULK_CONTRACT_END_PLUS_ONE;
    }
    return InvoiceDateRouteType.BULK_CONTRACT_START;
  }

  public static Boolean usesBulkContractProductInvoiceDate(
    String invoiceSettingLabel
  ) {
    InvoiceDateRouteType route = resolveInvoiceDateRoute(invoiceSettingLabel);
    return route == InvoiceDateRouteType.BULK_CONTRACT_START ||
      route == InvoiceDateRouteType.BULK_CONTRACT_END_PLUS_ONE;
  }

  /** 仕様: Core 第7.2節。請求基準日だけ返す。請求日ルールは BillingScheduleService.computeInvoiceDate。 */
  public static Date resolveInvoiceDate(
    String invoiceSettingLabel,
    Date periodStart,
    Date periodEnd
  ) {
    return resolveInvoiceDate(
      invoiceSettingLabel,
      periodStart,
      periodEnd,
      periodStart,
      periodEnd
    );
  }

  public static Date resolveInvoiceDate(
    String invoiceSettingLabel,
    Date periodStart,
    Date periodEnd,
    Date contractProductStart,
    Date contractProductEnd
  ) {
    InvoiceDateRouteType route = resolveInvoiceDateRoute(invoiceSettingLabel);
    return resolveAnchorDate(
      route,
      periodStart,
      periodEnd,
      contractProductStart,
      contractProductEnd
    );
  }

  @TestVisible
  private static Date resolveAnchorDate(
    InvoiceDateRouteType route,
    Date periodStart,
    Date periodEnd,
    Date contractProductStart,
    Date contractProductEnd
  ) {
    if (route == InvoiceDateRouteType.MONTHLY_PERIOD_START) {
      return periodStart;
    }
    if (route == InvoiceDateRouteType.BULK_CONTRACT_START) {
      return contractProductStart;
    }
    if (route == InvoiceDateRouteType.BULK_CONTRACT_END_PLUS_ONE) {
      return contractProductEnd == null ? null : contractProductEnd.addDays(1);
    }
    return periodStart;
  }

  public static Boolean isRecurringInvoiceSetting(String invoiceSettingLabel) {
    InvoiceSettingDefinition setting = getInvoiceSetting(invoiceSettingLabel);
    return setting != null &&
      setting.billingCategory == BILLING_CATEGORY_RECURRING;
  }

  public static Boolean isOneTimeInvoiceSetting(String invoiceSettingLabel) {
    InvoiceSettingDefinition setting = getInvoiceSetting(invoiceSettingLabel);
    return setting != null &&
      setting.billingCategory == BILLING_CATEGORY_ONE_TIME;
  }

  public static String validateInvoiceSettingForBillingType(
    String billingTypeLabel,
    String invoiceSettingLabel
  ) {
    if (String.isBlank(invoiceSettingLabel)) {
      return null;
    }

    String normalized = normalizeInvoiceSettingLabel(invoiceSettingLabel);

    if (
      billingTypeLabel == ONE_TIME_BILLING_TYPE_LABEL &&
      isSplitMonthlyInvoiceSetting(normalized)
    ) {
      return '一回課金では月次分割は選択できません。';
    }

    if (isAllowedInvoiceSettingForBillingType(billingTypeLabel, normalized)) {
      return null;
    }

    if (billingTypeLabel == ONE_TIME_BILLING_TYPE_LABEL) {
      return '一回課金では月次分割は選択できません。';
    }
    if (billingTypeLabel == RECURRING_BILLING_TYPE_LABEL) {
      return '継続課金に対応した請求設定を選択してください。';
    }
    return '請求設定が不正です。';
  }

  /** 仕様: Core 第1.1.10節 */
  public static String resolveInvoiceSettingForBillingType(
    String billingTypeLabel,
    String invoiceSettingLabel
  ) {
    String normalized = normalizeInvoiceSettingLabel(invoiceSettingLabel);
    if (
      String.isNotBlank(billingTypeLabel) &&
      String.isNotBlank(normalized) &&
      validateInvoiceSettingForBillingType(billingTypeLabel, normalized) == null
    ) {
      return normalized;
    }

    String error = validateInvoiceSettingForBillingType(
      billingTypeLabel,
      normalized
    );
    throw new InvoiceSettingException(
      String.isBlank(error) ? '請求設定が不正です。' : error
    );
  }

  public class InvoiceSettingException extends Exception {
  }

  public class BillingTypeException extends Exception {
  }

  public class RevenueRecognitionBasisException extends Exception {
  }

  public static Integer countMonthlyBillingCycles(
    Date startDate,
    Date endDate
  ) {
    if (startDate == null || endDate == null || endDate < startDate) {
      return -1;
    }
    return MonthlyBillingPeriodUtil.countMonthlyCycles(startDate, endDate);
  }

  public static Decimal calculateMonthlyArrRunRate(
    Decimal quantity,
    Decimal unitPrice
  ) {
    if (quantity == null || unitPrice == null) {
      return 0;
    }
    return quantity * unitPrice * MONTHLY_ARR_ANNUAL_MULTIPLIER;
  }

  private static InvoiceSettingDefinition getInvoiceSetting(String label) {
    if (String.isBlank(label)) {
      return null;
    }
    InvoiceSettingDefinition setting = INVOICE_SETTINGS_BY_LABEL.get(label);
    if (setting != null) {
      return setting;
    }
    String normalizedLabel = normalizeInvoiceSettingLabel(label);
    return normalizedLabel == label
      ? null
      : INVOICE_SETTINGS_BY_LABEL.get(normalizedLabel);
  }

  private static InvoiceSettingDefinition buildInvoiceSetting(
    String label,
    String billingCategory,
    Boolean splitMonthlyInvoicePeriods,
    Boolean useCalendarMonthSplit,
    Integer sortOrder
  ) {
    InvoiceSettingDefinition setting = new InvoiceSettingDefinition();
    setting.label = label;
    setting.billingCategory = billingCategory;
    setting.splitMonthlyInvoicePeriods = splitMonthlyInvoicePeriods;
    setting.useCalendarMonthSplit = useCalendarMonthSplit;
    setting.sortOrder = sortOrder;
    return setting;
  }
}
