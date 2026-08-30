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
  static void resolveInvoiceDate_monthlySplitUsesPeriodStart() {
    Date periodStart = Date.newInstance(2026, 6, 5);
    Date periodEnd = Date.newInstance(2026, 7, 4);

    System.assertEquals(
      periodStart,
      ContractMetadataService.resolveInvoiceDate(
        ContractMetadataService.INVOICE_SETTING_SPLIT_MONTHLY,
        periodStart,
        periodEnd,
        periodStart,
        periodEnd
      ),
      'Core 第7.2節: 月次分割の請求基準日は各請求サイクルの開始日。請求日ルールは BillingScheduleService'
    );
  }

  @IsTest
  static void resolveInvoiceDate_monthlySplitKeepsAnchorWithoutBillingDaySnap() {
    Date periodStart = Date.newInstance(2026, 6, 10);

    System.assertEquals(
      periodStart,
      ContractMetadataService.resolveInvoiceDate(
        ContractMetadataService.INVOICE_SETTING_SPLIT_MONTHLY,
        periodStart,
        periodStart,
        periodStart,
        periodStart
      )
    );
  }

  @IsTest
  static void resolveInvoiceDate_bulkPrepaidUsesContractStart() {
    Date termStart = Date.newInstance(2026, 6, 1);
    Date termEnd = Date.newInstance(2027, 5, 31);
    Date julyPeriodStart = Date.newInstance(2026, 7, 1);

    System.assertEquals(
      termStart,
      ContractMetadataService.resolveInvoiceDate(
        ContractMetadataService.INVOICE_SETTING_PREPAID_START,
        julyPeriodStart,
        julyPeriodStart,
        termStart,
        termEnd
      ),
      'Core 第7.2節: 一括前払の請求基準日は見積商品の開始日'
    );
  }

  @IsTest
  static void resolveInvoiceDate_bulkPostpaidUsesContractEndPlusOne() {
    Date termStart = Date.newInstance(2026, 6, 1);
    Date termEnd = Date.newInstance(2027, 5, 31);

    System.assertEquals(
      Date.newInstance(2027, 6, 1),
      ContractMetadataService.resolveInvoiceDate(
        ContractMetadataService.INVOICE_SETTING_POSTPAID_NEXT_DAY,
        termStart,
        termEnd,
        termStart,
        termEnd
      ),
      'Core 第7.2節: 一括後払の請求基準日は見積商品の終了日の翌日'
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
        endDate
      )
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
    try {
      ContractMetadataService.resolveLineBillingType(blankLine);
      System.assert(false, '課金形態空は商品マスタへ戻さずエラー');
    } catch (ContractMetadataService.BillingTypeException ex) {
      System.assert(ex.getMessage().contains('課金形態が空です。'));
    }
  }

  @IsTest
  static void resolveRevenueRecognitionBasis_rejectsBlankAndInvalid() {
    System.assertEquals(
      ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME,
      ContractMetadataService.resolveRevenueRecognitionBasis(
        ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
      )
    );
    System.assertEquals(
      ContractMetadataService.REVENUE_BASIS_OVER_TIME,
      ContractMetadataService.resolveRevenueRecognitionBasis(
        ContractMetadataService.REVENUE_BASIS_OVER_TIME
      )
    );
    try {
      ContractMetadataService.resolveRevenueRecognitionBasis(null);
      System.assert(false, '空は商品マスタへ落とさずエラー');
    } catch (ContractMetadataService.RevenueRecognitionBasisException ex) {
      System.assert(ex.getMessage().contains('売上計上基準が空です。'));
    }
    try {
      ContractMetadataService.resolveRevenueRecognitionBasis('不正');
      System.assert(false, '不正値は課金形態へ落とさずエラー');
    } catch (ContractMetadataService.RevenueRecognitionBasisException ex) {
      System.assert(
        ex.getMessage().contains('売上計上基準は月次計上または一括計上です。')
      );
    }

    ContractProduct__c line = new ContractProduct__c(
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME,
      BillingType__c = ContractMetadataService.RECURRING_BILLING_TYPE_LABEL
    );
    line.Product__r = new Product2(
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
    );
    System.assertEquals(
      ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME,
      ContractMetadataService.resolveLineRevenueRecognitionBasis(line)
    );
    ContractProduct__c blankLine = new ContractProduct__c();
    System.assertEquals(
      null,
      ContractMetadataService.resolveLineRevenueRecognitionBasis(blankLine)
    );
  }
}
