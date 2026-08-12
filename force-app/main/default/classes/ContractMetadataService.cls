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

  public class InvoiceDateContext {
    public Integer billingDayOfMonth;
    public Boolean immediateBillingDay;
    public Boolean adjustToBusinessDay;
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

  private class PaymentTermRuleDefinition {
    public String label;
    public String paymentDateRule;
    public Integer daysToAdd;
  }

  private static final String PAYMENT_DATE_RULE_CURRENT_MONTH_END = 'CurrentMonthEnd';
  private static final String PAYMENT_DATE_RULE_NEXT_MONTH_DAY15 = 'NextMonthDay15';
  private static final String PAYMENT_DATE_RULE_NEXT_MONTH_END = 'NextMonthEnd';

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
  private static final Map<String, PaymentTermRuleDefinition> PAYMENT_TERM_RULES_BY_LABEL = buildPaymentTermRuleMap();

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

  private static Map<String, PaymentTermRuleDefinition> buildPaymentTermRuleMap() {
    PaymentTermRuleDefinition currentMonthEnd = new PaymentTermRuleDefinition();
    currentMonthEnd.label = '当月末';
    currentMonthEnd.paymentDateRule = PAYMENT_DATE_RULE_CURRENT_MONTH_END;
    currentMonthEnd.daysToAdd = 0;

    PaymentTermRuleDefinition nextMonth15 = new PaymentTermRuleDefinition();
    nextMonth15.label = '翌月15日';
    nextMonth15.paymentDateRule = PAYMENT_DATE_RULE_NEXT_MONTH_DAY15;
    nextMonth15.daysToAdd = 0;

    PaymentTermRuleDefinition nextMonthEnd = new PaymentTermRuleDefinition();
    nextMonthEnd.label = '翌月末';
    nextMonthEnd.paymentDateRule = PAYMENT_DATE_RULE_NEXT_MONTH_END;
    nextMonthEnd.daysToAdd = 0;

    return new Map<String, PaymentTermRuleDefinition>{
      currentMonthEnd.label => currentMonthEnd,
      nextMonth15.label => nextMonth15,
      nextMonthEnd.label => nextMonthEnd
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

  /**
   * 既存明細の継続／一回の正。BillingType__c があればそれ、空なら Product2。
   */
  public static String resolveLineBillingType(ContractProduct__c product) {
    if (product == null) {
      return null;
    }
    if (String.isNotBlank(product.BillingType__c)) {
      return product.BillingType__c;
    }
    if (product.Product__r == null) {
      return null;
    }
    return product.Product__r.BillingType__c;
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

  public static final String BILLING_DAY_IMMEDIATE_VALUE = '即日';
  private static final String LEGACY_BILLING_DAY_IMMEDIATE_VALUE = 'IMMEDIATE';
  public static final Integer BILLING_DAY_END_OF_MONTH = 31;

  public static Boolean isImmediateBillingDay(String picklistValue) {
    return picklistValue == BILLING_DAY_IMMEDIATE_VALUE ||
      picklistValue == LEGACY_BILLING_DAY_IMMEDIATE_VALUE;
  }

  public static InvoiceDateContext buildInvoiceDateContext(
    String billingDayPicklistValue,
    Boolean adjustToBusinessDay
  ) {
    InvoiceDateContext context = new InvoiceDateContext();
    context.immediateBillingDay = isImmediateBillingDay(
      billingDayPicklistValue
    );
    context.billingDayOfMonth = context.immediateBillingDay
      ? null
      : parseBillingDayOfMonth(billingDayPicklistValue);
    context.adjustToBusinessDay = adjustToBusinessDay == true;
    return context;
  }

  public static Integer parseBillingDayOfMonth(String picklistValue) {
    if (String.isBlank(picklistValue) || isImmediateBillingDay(picklistValue)) {
      return null;
    }
    Integer day = Integer.valueOf(picklistValue.trim());
    if (day >= 1 && day <= BILLING_DAY_END_OF_MONTH) {
      return day;
    }
    return null;
  }

  public static String formatBillingDayPicklistLabel(String picklistValue) {
    if (isImmediateBillingDay(picklistValue)) {
      return '即日';
    }
    return formatBillingDayOfMonthLabel(parseBillingDayOfMonth(picklistValue));
  }

  public static String formatBillingDayOfMonthLabel(Integer day) {
    if (day == null) {
      return null;
    }
    if (day == 1) {
      return '月初';
    }
    if (day == BILLING_DAY_END_OF_MONTH) {
      return '月末日';
    }
    return String.valueOf(day) + '日';
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
      periodEnd,
      null
    );
  }

  public static Date resolveInvoiceDate(
    String invoiceSettingLabel,
    Date periodStart,
    Date periodEnd,
    Date contractProductStart,
    Date contractProductEnd,
    InvoiceDateContext context
  ) {
    InvoiceDateRouteType route = resolveInvoiceDateRoute(invoiceSettingLabel);
    Date anchorDate = resolveAnchorDate(
      route,
      periodStart,
      periodEnd,
      contractProductStart,
      contractProductEnd
    );
    Date baseDate = resolveBaseInvoiceDate(route, anchorDate, context);
    return applyWeekendSkip(baseDate, context);
  }

  /**
   * 契約商品に保存済みの請求基準日を、請求先の請求日ルール・営業日調整のみ反映して請求日にする。
   */
  public static Date resolveInvoiceDateFromStoredAnchor(
    Date anchorDate,
    InvoiceDateContext context
  ) {
    if (anchorDate == null) {
      return null;
    }
    Date baseDate = resolveBaseInvoiceDate(
      InvoiceDateRouteType.MONTHLY_PERIOD_START,
      anchorDate,
      context
    );
    return applyWeekendSkip(baseDate, context);
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

  @TestVisible
  private static Date resolveBaseInvoiceDate(
    InvoiceDateRouteType route,
    Date anchorDate,
    InvoiceDateContext context
  ) {
    if (anchorDate == null) {
      return null;
    }
    if (usesBillingDaySnap(route, context)) {
      return snapToBillingDayOnOrAfter(anchorDate, context.billingDayOfMonth);
    }
    return anchorDate;
  }

  @TestVisible
  private static Boolean usesBillingDaySnap(
    InvoiceDateRouteType route,
    InvoiceDateContext context
  ) {
    if (context == null || context.immediateBillingDay == true) {
      return false;
    }
    return context.billingDayOfMonth != null;
  }

  @TestVisible
  private static Date snapToBillingDayOnOrAfter(
    Date anchorDate,
    Integer billingDayOfMonth
  ) {
    if (anchorDate == null || billingDayOfMonth == null) {
      return anchorDate;
    }

    Date sameMonthCandidate = dateWithDayOfMonth(
      anchorDate.year(),
      anchorDate.month(),
      billingDayOfMonth
    );
    if (sameMonthCandidate >= anchorDate) {
      return sameMonthCandidate;
    }

    Date nextMonthStart = Date.newInstance(
        anchorDate.year(),
        anchorDate.month(),
        1
      )
      .addMonths(1);
    return dateWithDayOfMonth(
      nextMonthStart.year(),
      nextMonthStart.month(),
      billingDayOfMonth
    );
  }

  @TestVisible
  private static Date dateWithDayOfMonth(
    Integer year,
    Integer month,
    Integer dayOfMonth
  ) {
    Integer lastDay = Date.daysInMonth(year, month);
    Integer day = Math.min(dayOfMonth, lastDay);
    return Date.newInstance(year, month, day);
  }

  @TestVisible
  private static Date applyWeekendSkip(
    Date baseDate,
    InvoiceDateContext context
  ) {
    if (baseDate == null) {
      return null;
    }
    if (context == null || context.adjustToBusinessDay != true) {
      return baseDate;
    }
    return adjustToNextBusinessDay(baseDate);
  }

  @TestVisible
  private static Date adjustToNextBusinessDay(Date dateValue) {
    if (dateValue == null) {
      return null;
    }
    Date cursor = dateValue;
    while (isWeekend(cursor)) {
      cursor = cursor.addDays(1);
    }
    return cursor;
  }

  @TestVisible
  private static Boolean isWeekend(Date dateValue) {
    Integer isoDay = isoDayOfWeek(dateValue);
    return isoDay == 6 || isoDay == 7;
  }

  @TestVisible
  private static Integer isoDayOfWeek(Date dateValue) {
    Date referenceMonday = Date.newInstance(2024, 1, 1);
    Integer daysBetween = referenceMonday.daysBetween(dateValue);
    Integer mod = Math.mod(daysBetween, 7);
    return mod + 1;
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

    List<String> allowedLabels = getAllowedInvoiceSettingLabels(
      billingTypeLabel
    );
    return allowedLabels.isEmpty() ? normalized : allowedLabels[0];
  }

  public static Date resolvePaymentScheduledDate(
    String paymentTermLabel,
    Date invoiceDate
  ) {
    if (invoiceDate == null || String.isBlank(paymentTermLabel)) {
      return null;
    }

    PaymentTermRuleDefinition rule = PAYMENT_TERM_RULES_BY_LABEL.get(
      paymentTermLabel
    );
    if (rule == null) {
      return null;
    }

    Date monthStart = Date.newInstance(
      invoiceDate.year(),
      invoiceDate.month(),
      1
    );

    Date scheduledDate;
    if (rule.paymentDateRule == PAYMENT_DATE_RULE_CURRENT_MONTH_END) {
      scheduledDate = monthStart.addMonths(1).addDays(-1);
    } else if (rule.paymentDateRule == PAYMENT_DATE_RULE_NEXT_MONTH_DAY15) {
      scheduledDate = monthStart.addMonths(1).addDays(14);
    } else if (rule.paymentDateRule == PAYMENT_DATE_RULE_NEXT_MONTH_END) {
      scheduledDate = monthStart.addMonths(2).addDays(-1);
    } else {
      scheduledDate = invoiceDate;
    }

    return rule.daysToAdd == 0
      ? scheduledDate
      : scheduledDate.addDays(rule.daysToAdd);
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
