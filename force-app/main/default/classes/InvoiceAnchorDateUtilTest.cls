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
}
