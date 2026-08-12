@IsTest
private class InvoiceProductMergeKeyUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void buildMergeKey_formatsServiceProductPeriodQuantityUnitPriceAndUnit() {
    // DMLなしで検証する（Account insert は Sansan 等の組織依存トリガで落ちうるため）。
    Id serviceId = (Id) (ContractService__c.SObjectType.getDescribe()
      .getKeyPrefix() + '000000000001');
    Id productId = (Id) (Product2.SObjectType.getDescribe().getKeyPrefix() +
    '000000000001');

    Date startDate = Date.newInstance(2026, 6, 1);
    Date endDate = Date.newInstance(2026, 6, 30);
    String mergeKey = InvoiceProductMergeKeyUtil.buildMergeKey(
      serviceId,
      productId,
      startDate,
      endDate,
      2,
      8000,
      'ID/月'
    );

    System.assertEquals(
      String.valueOf(serviceId) +
        '_' +
        String.valueOf(productId) +
        '_' +
        String.valueOf(startDate) +
        '_' +
        String.valueOf(endDate) +
        '_2_8000_ID/月',
      mergeKey
    );
  }

  @IsTest
  static void buildPeriodKey_andExtractPeriodKey_roundTrip() {
    Id serviceId = (Id) (ContractService__c.SObjectType.getDescribe()
      .getKeyPrefix() + '000000000002');
    Id productId = (Id) (Product2.SObjectType.getDescribe().getKeyPrefix() +
    '000000000002');
    Date startDate = Date.newInstance(2026, 6, 1);
    Date endDate = Date.newInstance(2026, 6, 30);

    String periodKey = InvoiceProductMergeKeyUtil.buildPeriodKey(
      serviceId,
      productId,
      startDate,
      endDate
    );
    String mergeKey =
      periodKey +
      '_2_8000_ID/月';
    System.assertEquals(periodKey, InvoiceProductMergeKeyUtil.extractPeriodKey(mergeKey));
    System.assertEquals(null, InvoiceProductMergeKeyUtil.extractPeriodKey(null));
    System.assertEquals(null, InvoiceProductMergeKeyUtil.extractPeriodKey('short'));
  }

  @IsTest
  static void buildMergeKey_fromInvoiceProduct_usesContractProductReference() {
    System.assertEquals(null, InvoiceProductMergeKeyUtil.buildMergeKey((InvoiceProduct__c) null));

    Id serviceId = (Id) (ContractService__c.SObjectType.getDescribe()
      .getKeyPrefix() + '000000000003');
    Id productId = (Id) (Product2.SObjectType.getDescribe().getKeyPrefix() +
    '000000000003');
    Date startDate = Date.newInstance(2026, 7, 1);
    Date endDate = Date.newInstance(2026, 7, 31);

    InvoiceProduct__c referenced = new InvoiceProduct__c(
      StartDate__c = startDate,
      Enddate__c = endDate,
      ContractHistory__r = new ContractHistory__c(
        ContractService__c = serviceId
      ),
      ContractProduct__r = new ContractProduct__c(
        Product__c = productId,
        Quantity__c = 1,
        UnitPrice__c = 5000,
        Unit__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT
      )
    );
    System.assertEquals(
      InvoiceProductMergeKeyUtil.buildMergeKey(
        serviceId,
        productId,
        startDate,
        endDate,
        1,
        5000,
        ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT
      ),
      InvoiceProductMergeKeyUtil.buildMergeKey(referenced)
    );
  }

  @IsTest
  static void buildMergeKey_formatsNullDecimalsAndBlankUnit() {
    Id serviceId = (Id) (ContractService__c.SObjectType.getDescribe()
      .getKeyPrefix() + '000000000004');
    Id productId = (Id) (Product2.SObjectType.getDescribe().getKeyPrefix() +
    '000000000004');
    Date startDate = Date.newInstance(2026, 8, 1);
    Date endDate = Date.newInstance(2026, 8, 31);

    System.assertEquals(
      String.valueOf(serviceId) +
        '_' +
        String.valueOf(productId) +
        '_' +
        String.valueOf(startDate) +
        '_' +
        String.valueOf(endDate) +
        '_0_0_',
      InvoiceProductMergeKeyUtil.buildMergeKey(
        serviceId,
        productId,
        startDate,
        endDate,
        null,
        null,
        null
      )
    );
    System.assertEquals(
      String.valueOf(serviceId) +
        '_' +
        String.valueOf(productId) +
        '_' +
        String.valueOf(startDate) +
        '_' +
        String.valueOf(endDate) +
        '_1.5_1000_ID~月',
      InvoiceProductMergeKeyUtil.buildMergeKey(
        serviceId,
        productId,
        startDate,
        endDate,
        1.5,
        1000,
        'ID_月'
      )
    );
  }

  @IsTest
  static void buildExportInvoiceMergeKey_roundTripsDatesAndBillingAccount() {
    Id billingAccountId = (Id) (BillingAccount__c.SObjectType.getDescribe()
      .getKeyPrefix() + '000000000001');
    Id contractHistoryId = (Id) (ContractHistory__c.SObjectType.getDescribe()
      .getKeyPrefix() + '000000000002');
    Date invoiceDate = Date.newInstance(2026, 6, 5);
    Date paymentDate = Date.newInstance(2026, 7, 31);

    String mergeKey = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
      billingAccountId,
      contractHistoryId,
      invoiceDate,
      paymentDate
    );

    System.assertEquals(
      'INV|BA=' +
        String.valueOf(billingAccountId) +
        '|CH=' +
        String.valueOf(contractHistoryId) +
        '|DT=2026-06-05|PD=2026-07-31',
      mergeKey
    );
    System.assertEquals(
      invoiceDate,
      InvoiceProductMergeKeyUtil.parseInvoiceDateFromExportMergeKey(mergeKey)
    );
    System.assertEquals(
      paymentDate,
      InvoiceProductMergeKeyUtil.parsePaymentScheduledDateFromExportMergeKey(
        mergeKey
      )
    );
    System.assertEquals(
      billingAccountId,
      InvoiceProductMergeKeyUtil.parseBillingAccountIdFromExportMergeKey(mergeKey)
    );
    System.assertEquals(null, InvoiceProductMergeKeyUtil.parseInvoiceDateFromExportMergeKey(null));
    System.assertEquals(null, InvoiceProductMergeKeyUtil.parseBillingAccountIdFromExportMergeKey('short'));
  }

  @IsTest
  static void buildMergeKey_fromInvoiceProduct_prefersExportMergeKey() {
    InvoiceProduct__c withExportKey = new InvoiceProduct__c(
      InvoiceBucketKey__c = 'INV|BA=001|CH=002|DT=2026-06-01|PD=2026-06-30'
    );
    System.assertEquals(
      withExportKey.InvoiceBucketKey__c,
      InvoiceProductMergeKeyUtil.buildMergeKey(withExportKey)
    );
  }
}
