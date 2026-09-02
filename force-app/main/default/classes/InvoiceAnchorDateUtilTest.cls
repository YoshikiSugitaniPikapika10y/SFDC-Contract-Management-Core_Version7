@IsTest
private class InvoiceAnchorDateUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void resolve_prepaidUsesStartDate() {
    ContractProduct__c product = new ContractProduct__c(
      Type__c = 'New',
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
    );

    InvoiceAnchorDateUtil.ResolvedAnchor resolved = InvoiceAnchorDateUtil.resolve(
      'New',
      Date.newInstance(2026, 4, 1),
      product
    );

    System.assertEquals(Date.newInstance(2026, 4, 1), resolved.anchorDate);
    System.assertEquals(null, resolved.billingCycleCount);
  }

  @IsTest
  static void resolve_changePrepaidRemakeUsesEffectiveDate() {
    ContractProduct__c product = new ContractProduct__c(
      Type__c = 'Remake',
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
    );
    Date effectiveDate = Date.newInstance(2026, 4, 1);

    InvoiceAnchorDateUtil.ResolvedAnchor resolved = InvoiceAnchorDateUtil.resolve(
      'Change',
      effectiveDate,
      product
    );

    System.assertEquals(effectiveDate, resolved.anchorDate);
  }

  @IsTest
  static void resolve_changePrepaidNewUsesStartDate() {
    ContractProduct__c product = new ContractProduct__c(
      Type__c = 'New',
      StartDate__c = Date.newInstance(2026, 10, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
    );
    Date effectiveDate = Date.newInstance(2026, 4, 1);

    InvoiceAnchorDateUtil.ResolvedAnchor resolved = InvoiceAnchorDateUtil.resolve(
      'Change',
      effectiveDate,
      product
    );

    System.assertEquals(Date.newInstance(2026, 10, 1), resolved.anchorDate);
  }

  @IsTest
  static void resolve_monthlySplitStoresCycleCount() {
    ContractProduct__c product = new ContractProduct__c(
      Type__c = 'New',
      StartDate__c = Date.newInstance(2025, 8, 1),
      Enddate__c = Date.newInstance(2026, 7, 31),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY
    );

    InvoiceAnchorDateUtil.ResolvedAnchor resolved = InvoiceAnchorDateUtil.resolve(
      'New',
      Date.newInstance(2025, 8, 1),
      product
    );

    System.assertEquals(Date.newInstance(2025, 8, 1), resolved.anchorDate);
    System.assertEquals(12, resolved.billingCycleCount);
  }

  @IsTest
  static void resolve_postpaidUsesEndPlusOne() {
    ContractProduct__c product = new ContractProduct__c(
      Type__c = 'New',
      StartDate__c = Date.newInstance(2025, 8, 1),
      Enddate__c = Date.newInstance(2026, 7, 31),
      InvoiceSetting__c = '一括後払'
    );

    InvoiceAnchorDateUtil.ResolvedAnchor resolved = InvoiceAnchorDateUtil.resolve(
      'New',
      Date.newInstance(2025, 8, 1),
      product
    );

    System.assertEquals(Date.newInstance(2026, 8, 1), resolved.anchorDate);
    System.assertEquals(null, resolved.billingCycleCount);
  }

  @IsTest
  static void resolve_blankSettingOrMissingEndDoesNotInventAnchor() {
    System.assertEquals(
      null,
      InvoiceAnchorDateUtil.resolve('New', Date.newInstance(2026, 4, 1), null)
        .anchorDate
    );
    ContractProduct__c noSetting = new ContractProduct__c(
      Type__c = 'New',
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31)
    );
    System.assertEquals(
      null,
      InvoiceAnchorDateUtil.resolve('New', Date.newInstance(2026, 4, 1), noSetting)
        .anchorDate,
      'Core 第7.2節: 請求設定が空なら基準日を決めない'
    );
    ContractProduct__c postpaidNoEnd = new ContractProduct__c(
      Type__c = 'New',
      StartDate__c = Date.newInstance(2026, 4, 1),
      InvoiceSetting__c = ContractMetadataService.INVOICE_SETTING_POSTPAID_NEXT_DAY
    );
    System.assertEquals(
      null,
      InvoiceAnchorDateUtil.resolve('New', Date.newInstance(2026, 4, 1), postpaidNoEnd)
        .anchorDate,
      'Core 第7.2節: 一括後払は終了日の翌日。終了日が無ければ決めない'
    );
  }

  @IsTest
  static void applyToContractProduct_keepsStoredWhenUnresolved_andWritesWhenResolved() {
    ContractProduct__c unresolved = new ContractProduct__c(
      Type__c = 'New',
      InvoiceAnchorDate__c = Date.newInstance(2026, 1, 1),
      InvoiceBillingCycleCount__c = 3
    );
    InvoiceAnchorDateUtil.applyToContractProduct(unresolved, 'New', null);
    System.assertEquals(
      Date.newInstance(2026, 1, 1),
      unresolved.InvoiceAnchorDate__c,
      'Core 第7.2節: 基準日が決まらないときは保存済みを消さない'
    );
    System.assertEquals(3, unresolved.InvoiceBillingCycleCount__c);

    ContractProduct__c monthly = new ContractProduct__c(
      Type__c = 'New',
      StartDate__c = Date.newInstance(2025, 8, 1),
      Enddate__c = Date.newInstance(2026, 7, 31),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
      InvoiceBillingCycleCount__c = 99
    );
    InvoiceAnchorDateUtil.applyToContractProduct(monthly, 'New', null);
    System.assertEquals(Date.newInstance(2025, 8, 1), monthly.InvoiceAnchorDate__c);
    System.assertEquals(
      12,
      monthly.InvoiceBillingCycleCount__c,
      'Core 第7.2節: 月次分割は各サイクル開始日。回数は期間のサイクル数'
    );
  }
}
