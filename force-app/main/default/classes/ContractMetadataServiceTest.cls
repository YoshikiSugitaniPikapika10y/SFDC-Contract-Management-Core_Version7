@IsTest
private class ContractMetadataServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void getActiveInvoiceSettingOptions_returnsConfiguredRecords() {
    List<ContractMetadataService.InvoiceSettingOption> options = ContractMetadataService.getActiveInvoiceSettingOptions();
    System.assertEquals(3, options.size());
  }

  @IsTest
  static void resolveInvoiceDateRoute_mapsSettingsToRoutes() {
    System.assertEquals(
      ContractMetadataService.InvoiceDateRouteType.MONTHLY_PERIOD_START,
      ContractMetadataService.resolveInvoiceDateRoute(
        ContractMetadataService.INVOICE_SETTING_SPLIT_MONTHLY
      )
    );
    System.assertEquals(
      ContractMetadataService.InvoiceDateRouteType.BULK_CONTRACT_START,
      ContractMetadataService.resolveInvoiceDateRoute(
        ContractMetadataService.INVOICE_SETTING_PREPAID_START
      )
    );
    System.assertEquals(
      ContractMetadataService.InvoiceDateRouteType.BULK_CONTRACT_END_PLUS_ONE,
      ContractMetadataService.resolveInvoiceDateRoute(
        ContractMetadataService.INVOICE_SETTING_POSTPAID_NEXT_DAY
      )
    );
  }

  @IsTest
  static void resolveInvoiceDate_monthlySplitSnapsToBillingDay() {
    Date periodStart = Date.newInstance(2026, 6, 5);
    Date periodEnd = Date.newInstance(2026, 7, 4);
    ContractMetadataService.InvoiceDateContext context = ContractMetadataService.buildInvoiceDateContext(
      '25',
      false
    );

    System.assertEquals(
      Date.newInstance(2026, 6, 25),
      ContractMetadataService.resolveInvoiceDate(
        ContractMetadataService.INVOICE_SETTING_SPLIT_MONTHLY,
        periodStart,
        periodEnd,
        periodStart,
        periodEnd,
        context
      )
    );
  }

  @IsTest
  static void resolveInvoiceDate_monthlySplitUsesImmediateBillingDay() {
    Date periodStart = Date.newInstance(2026, 6, 10);
    ContractMetadataService.InvoiceDateContext context = ContractMetadataService.buildInvoiceDateContext(
      'IMMEDIATE',
      false
    );

    System.assertEquals(
      Date.newInstance(2026, 6, 10),
      ContractMetadataService.resolveInvoiceDate(
        ContractMetadataService.INVOICE_SETTING_SPLIT_MONTHLY,
        periodStart,
        periodStart,
        periodStart,
        periodStart,
        context
      )
    );
  }

  @IsTest
  static void resolveInvoiceDate_bulkPrepaidSnapsContractStartToBillingDay() {
    Date termStart = Date.newInstance(2026, 6, 1);
    Date termEnd = Date.newInstance(2027, 5, 31);
    Date julyPeriodStart = Date.newInstance(2026, 7, 1);
    ContractMetadataService.InvoiceDateContext context = ContractMetadataService.buildInvoiceDateContext(
      '25',
      false
    );

    System.assertEquals(
      Date.newInstance(2026, 6, 25),
      ContractMetadataService.resolveInvoiceDate(
        ContractMetadataService.INVOICE_SETTING_PREPAID_START,
        julyPeriodStart,
        julyPeriodStart,
        termStart,
        termEnd,
        context
      )
    );
  }

  @IsTest
  static void resolveInvoiceDate_bulkPostpaidSnapsContractEndPlusOneToBillingDay() {
    Date termStart = Date.newInstance(2026, 6, 1);
    Date termEnd = Date.newInstance(2027, 5, 31);
    ContractMetadataService.InvoiceDateContext context = ContractMetadataService.buildInvoiceDateContext(
      '25',
      false
    );

    System.assertEquals(
      Date.newInstance(2027, 6, 25),
      ContractMetadataService.resolveInvoiceDate(
        ContractMetadataService.INVOICE_SETTING_POSTPAID_NEXT_DAY,
        termStart,
        termEnd,
        termStart,
        termEnd,
        context
      )
    );
  }

  @IsTest
  static void resolveInvoiceDate_postpaidUsesContractEndPlusOne() {
    Date startDate = Date.newInstance(2026, 6, 1);
    Date endDate = Date.newInstance(2026, 6, 30);

    System.assertEquals(
      endDate.addDays(1),
      ContractMetadataService.resolveInvoiceDate(
        ContractMetadataService.INVOICE_SETTING_POSTPAID_NEXT_DAY,
        startDate,
        endDate,
        startDate,
        endDate,
        null
      )
    );
  }

  @IsTest
  static void resolveInvoiceDate_endOfMonthBillingDayUsesLastDayOfMonth() {
    Date periodStart = Date.newInstance(2026, 2, 1);
    ContractMetadataService.InvoiceDateContext context = ContractMetadataService.buildInvoiceDateContext(
      '31',
      false
    );

    System.assertEquals(
      Date.newInstance(2026, 2, 28),
      ContractMetadataService.resolveInvoiceDate(
        ContractMetadataService.INVOICE_SETTING_SPLIT_MONTHLY,
        periodStart,
        periodStart,
        periodStart,
        periodStart,
        context
      )
    );
  }

  @IsTest
  static void resolveInvoiceDate_adjustsWeekendToBusinessDay() {
    Date saturday = Date.newInstance(2026, 6, 6);
    ContractMetadataService.InvoiceDateContext context = ContractMetadataService.buildInvoiceDateContext(
      'IMMEDIATE',
      true
    );

    System.assertEquals(
      Date.newInstance(2026, 6, 8),
      ContractMetadataService.resolveInvoiceDate(
        ContractMetadataService.INVOICE_SETTING_PREPAID_START,
        saturday,
        saturday,
        saturday,
        saturday,
        context
      )
    );
  }

  @IsTest
  static void parseBillingDayOfMonth_mapsPicklistValues() {
    System.assertEquals(1, ContractMetadataService.parseBillingDayOfMonth('1'));
    System.assertEquals(
      25,
      ContractMetadataService.parseBillingDayOfMonth('25')
    );
    System.assertEquals(
      ContractMetadataService.BILLING_DAY_END_OF_MONTH,
      ContractMetadataService.parseBillingDayOfMonth('31')
    );
    System.assertEquals(
      null,
      ContractMetadataService.parseBillingDayOfMonth(ContractTestDataFactory.TENANT_BILLING_DAY_SAME_DAY)
    );
    System.assertEquals(
      null,
      ContractMetadataService.parseBillingDayOfMonth('IMMEDIATE')
    );
    System.assertEquals(
      null,
      ContractMetadataService.parseBillingDayOfMonth(null)
    );
  }

  @IsTest
  static void formatBillingDayPicklistLabel_returnsDisplayLabels() {
    System.assertEquals(
      '月初',
      ContractMetadataService.formatBillingDayPicklistLabel('1')
    );
    System.assertEquals(
      ContractTestDataFactory.TENANT_BILLING_DAY_SAME_DAY,
      ContractMetadataService.formatBillingDayPicklistLabel(ContractTestDataFactory.TENANT_BILLING_DAY_SAME_DAY)
    );
    System.assertEquals(
      ContractTestDataFactory.TENANT_BILLING_DAY_SAME_DAY,
      ContractMetadataService.formatBillingDayPicklistLabel('IMMEDIATE')
    );
    System.assertEquals(
      '25日',
      ContractMetadataService.formatBillingDayPicklistLabel('25')
    );
    System.assertEquals(
      '月末日',
      ContractMetadataService.formatBillingDayPicklistLabel('31')
    );
  }

  @IsTest
  static void invoiceSettingFlags_resolveSplitAndBulkRoutes() {
    System.assertEquals(
      true,
      ContractMetadataService.shouldSplitMonthlyInvoicePeriods(
        ContractMetadataService.INVOICE_SETTING_SPLIT_MONTHLY
      )
    );
    System.assertEquals(
      true,
      ContractMetadataService.shouldSplitMonthlyInvoicePeriods(
        ContractMetadataService.INVOICE_SETTING_PREPAID_START
      )
    );
    System.assertEquals(
      true,
      ContractMetadataService.usesBulkContractProductInvoiceDate(
        ContractMetadataService.INVOICE_SETTING_PREPAID_START
      )
    );
    System.assertEquals(
      false,
      ContractMetadataService.usesBulkContractProductInvoiceDate(
        ContractMetadataService.INVOICE_SETTING_SPLIT_MONTHLY
      )
    );
  }

  @IsTest
  static void countMonthlyBillingCycles_usesMonthlyPeriods() {
    Date startDate = Date.newInstance(2025, 1, 1);
    Date endDate = Date.newInstance(2025, 12, 31);

    System.assertEquals(
      12,
      ContractMetadataService.countMonthlyBillingCycles(startDate, endDate)
    );
  }

  @IsTest
  static void resolvePaymentScheduledDate_usesConfiguredPaymentTermRules() {
    Date invoiceDate = Date.newInstance(2026, 6, 1);

    System.assertEquals(
      Date.newInstance(2026, 6, 30),
      ContractMetadataService.resolvePaymentScheduledDate(ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END, invoiceDate)
    );
    System.assertEquals(
      Date.newInstance(2026, 7, 15),
      ContractMetadataService.resolvePaymentScheduledDate(
        '翌月15日',
        invoiceDate
      )
    );
  }

  @IsTest
  static void validateInvoiceSettingForBillingType_rejectsSplitMonthlyForOneTime() {
    System.assertEquals(
      '一回課金では月次分割は選択できません。',
      ContractMetadataService.validateInvoiceSettingForBillingType(
        ContractMetadataService.ONE_TIME_BILLING_TYPE_LABEL,
        ContractMetadataService.INVOICE_SETTING_SPLIT_MONTHLY
      )
    );
  }

  @IsTest
  static void resolveInvoiceDateFromStoredAnchor_snapsToBillingDay() {
    Date anchorDate = Date.newInstance(2026, 6, 15);
    ContractMetadataService.InvoiceDateContext context = ContractMetadataService.buildInvoiceDateContext(
      '25',
      false
    );

    System.assertEquals(
      Date.newInstance(2026, 6, 25),
      ContractMetadataService.resolveInvoiceDateFromStoredAnchor(
        anchorDate,
        context
      )
    );
  }

  @IsTest
  static void resolveInvoiceDateFromStoredAnchor_returnsNullForNullAnchor() {
    System.assertEquals(
      null,
      ContractMetadataService.resolveInvoiceDateFromStoredAnchor(
        null,
        ContractMetadataService.buildInvoiceDateContext('1', false)
      )
    );
  }

  @IsTest
  static void resolveInvoiceDateFromStoredAnchor_adjustsWeekendToBusinessDay() {
    Date saturday = Date.newInstance(2026, 6, 6);
    ContractMetadataService.InvoiceDateContext context = ContractMetadataService.buildInvoiceDateContext(
      'IMMEDIATE',
      true
    );

    System.assertEquals(
      Date.newInstance(2026, 6, 8),
      ContractMetadataService.resolveInvoiceDateFromStoredAnchor(
        saturday,
        context
      )
    );
  }

  @IsTest
  static void validateInvoiceSettingForBillingType_allowsUnifiedLabelsForOneTime() {
    System.assertEquals(
      null,
      ContractMetadataService.validateInvoiceSettingForBillingType(
        ContractMetadataService.ONE_TIME_BILLING_TYPE_LABEL,
        ContractMetadataService.INVOICE_SETTING_PREPAID_START
      )
    );
    System.assertEquals(
      null,
      ContractMetadataService.validateInvoiceSettingForBillingType(
        ContractMetadataService.ONE_TIME_BILLING_TYPE_LABEL,
        ContractMetadataService.INVOICE_SETTING_POSTPAID_NEXT_DAY
      )
    );
  }

  @IsTest
  static void resolveLineBillingType_prefersLineOverProductMaster() {
    ContractProduct__c lineOneTime = new ContractProduct__c(
      BillingType__c = ContractMetadataService.ONE_TIME_BILLING_TYPE_LABEL
    );
    lineOneTime.Product__r = new Product2(
      BillingType__c = ContractMetadataService.RECURRING_BILLING_TYPE_LABEL
    );
    System.assertEquals(
      ContractMetadataService.ONE_TIME_BILLING_TYPE_LABEL,
      ContractMetadataService.resolveLineBillingType(lineOneTime)
    );

    ContractProduct__c blankLine = new ContractProduct__c();
    blankLine.Product__r = new Product2(
      BillingType__c = ContractMetadataService.RECURRING_BILLING_TYPE_LABEL
    );
    System.assertEquals(
      ContractMetadataService.RECURRING_BILLING_TYPE_LABEL,
      ContractMetadataService.resolveLineBillingType(blankLine)
    );
  }
}
