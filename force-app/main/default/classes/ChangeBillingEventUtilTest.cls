@IsTest
private class ChangeBillingEventUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void filterProductsForEstimateDocument_nonChange_returnsAll() {
    List<ContractProduct__c> products = new List<ContractProduct__c>{
      new ContractProduct__c(Id = fakeId(ContractProduct__c.SObjectType, 1)),
      new ContractProduct__c(Id = fakeId(ContractProduct__c.SObjectType, 2))
    };

    List<ContractProduct__c> filtered = ChangeBillingEventUtil.filterProductsForEstimateDocument(
      'New',
      products
    );

    System.assertEquals(2, filtered.size());
    System.assertEquals(products[0].Id, filtered[0].Id);
    System.assertEquals(products[1].Id, filtered[1].Id);
  }

  @IsTest
  static void filterProductsForEstimateDocument_excludesUnchangedLineage() {
    Id lineageId = fakeId(ContractProduct__c.SObjectType, 10);
    Id productId = fakeId(Product2.SObjectType, 1);
    ContractProduct__c original = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 1),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      Type__c = 'Original',
      PreviousContractProduct__c = lineageId
    );
    ContractProduct__c remake = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 2),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      Type__c = 'Remake',
      PreviousContractProduct__c = lineageId
    );
    ContractProduct__c newLine = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 3),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 500,
      Type__c = 'New'
    );

    List<ContractProduct__c> filtered = ChangeBillingEventUtil.filterProductsForEstimateDocument(
      'Change',
      new List<ContractProduct__c>{ original, remake, newLine }
    );

    System.assertEquals(1, filtered.size());
    System.assertEquals(newLine.Id, filtered[0].Id);
  }

  @IsTest
  static void filterProductsForEstimateDocument_keepsEndDateExtensionLineage() {
    Id lineageId = fakeId(ContractProduct__c.SObjectType, 10);
    Id productId = fakeId(Product2.SObjectType, 1);
    ContractProduct__c original = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 1),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      Type__c = 'Original',
      PreviousContractProduct__c = lineageId
    );
    ContractProduct__c remake = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 2),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 5, 31),
      Type__c = 'Remake',
      PreviousContractProduct__c = lineageId
    );

    List<ContractProduct__c> filtered = ChangeBillingEventUtil.filterProductsForEstimateDocument(
      'Change',
      new List<ContractProduct__c>{ original, remake }
    );

    System.assertEquals(
      2,
      filtered.size(),
      'Core 第4.4.1節: 期間終了日の延長は課金イベントとして見積書明細に残す'
    );
    System.assertEquals(original.Id, filtered[0].Id);
    System.assertEquals(remake.Id, filtered[1].Id);
  }

  @IsTest
  static void lineageHasBillingEvent_endDateExtension_returnsTrue() {
    Id productId = fakeId(Product2.SObjectType, 1);
    ContractProduct__c original = new ContractProduct__c(
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31)
    );
    ContractProduct__c remake = new ContractProduct__c(
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 5, 31)
    );

    System.assertEquals(
      true,
      ChangeBillingEventUtil.lineageHasBillingEvent(
        original,
        new List<ContractProduct__c>{ remake }
      )
    );
  }

  @IsTest
  static void filterProductsForEstimateDocument_keepsChangedLineage() {
    Id lineageId = fakeId(ContractProduct__c.SObjectType, 10);
    Id productId = fakeId(Product2.SObjectType, 1);
    ContractProduct__c original = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 1),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Type__c = 'Original',
      PreviousContractProduct__c = lineageId
    );
    ContractProduct__c remake = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 2),
      Product__c = productId,
      Quantity__c = 2,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Type__c = 'Remake',
      PreviousContractProduct__c = lineageId
    );

    List<ContractProduct__c> filtered = ChangeBillingEventUtil.filterProductsForEstimateDocument(
      'Change',
      new List<ContractProduct__c>{ original, remake }
    );

    System.assertEquals(2, filtered.size());
    System.assertEquals(original.Id, filtered[0].Id);
    System.assertEquals(remake.Id, filtered[1].Id);
  }

  @IsTest
  static void lineageHasBillingEvent_detectsExactStartDateBoundary() {
    Id productId = fakeId(Product2.SObjectType, 1);
    ContractProduct__c original = new ContractProduct__c(
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1)
    );
    ContractProduct__c sameStart = new ContractProduct__c(
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1)
    );
    ContractProduct__c midTermStart = new ContractProduct__c(
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 10, 1)
    );

    System.assertEquals(
      false,
      ChangeBillingEventUtil.lineageHasBillingEvent(
        original,
        new List<ContractProduct__c>{ sameStart }
      ),
      'Core 第4.4.1節: 元明細と同じ2026/4/1開始は途中開始ではない'
    );
    System.assertEquals(
      true,
      ChangeBillingEventUtil.lineageHasBillingEvent(
        original,
        new List<ContractProduct__c>{ midTermStart }
      ),
      'Core 第4.4.1節: 2026/10/1のRemake途中開始は課金イベント'
    );
  }

  @IsTest
  static void doesBillingContentDiffer_unitPriceZero_returnsTrue() {
    Id productId = fakeId(Product2.SObjectType, 1);
    ContractProduct__c original = new ContractProduct__c(
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
    );
    ContractProduct__c remake = new ContractProduct__c(
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 0,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
    );

    System.assertEquals(
      true,
      ChangeBillingEventUtil.doesBillingContentDiffer(remake, original)
    );
  }

  @IsTest
  static void filterProductsForEstimateDocument_nullOrEmpty_returnsEmpty() {
    System.assertEquals(
      0,
      ChangeBillingEventUtil.filterProductsForEstimateDocument('Change', null)
        .size()
    );
    System.assertEquals(
      0,
      ChangeBillingEventUtil.filterProductsForEstimateDocument(
          'Change',
          new List<ContractProduct__c>()
        )
        .size()
    );
  }

  @IsTest
  static void filterProductsForEstimateDocument_remakeWithoutOriginal_keepsRemake() {
    Id lineageId = fakeId(ContractProduct__c.SObjectType, 10);
    Id productId = fakeId(Product2.SObjectType, 1);
    ContractProduct__c remake = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 2),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Type__c = 'Remake',
      PreviousContractProduct__c = lineageId
    );

    List<ContractProduct__c> filtered = ChangeBillingEventUtil.filterProductsForEstimateDocument(
      'Change',
      new List<ContractProduct__c>{ remake }
    );

    System.assertEquals(1, filtered.size());
    System.assertEquals(remake.Id, filtered[0].Id);
  }

  @IsTest
  static void lineageHasBillingEvent_nullInputs_returnsFalse() {
    System.assertEquals(
      false,
      ChangeBillingEventUtil.lineageHasBillingEvent(null, null)
    );
    System.assertEquals(
      false,
      ChangeBillingEventUtil.lineageHasBillingEvent(
        new ContractProduct__c(StartDate__c = Date.today()),
        new List<ContractProduct__c>()
      )
    );
    System.assertEquals(
      false,
      ChangeBillingEventUtil.lineageHasBillingEvent(
        new ContractProduct__c(StartDate__c = Date.today()),
        new List<ContractProduct__c>{
          new ContractProduct__c(StartDate__c = null)
        }
      )
    );
  }

  @IsTest
  static void doesBillingContentDiffer_nullInputs_returnsFalse() {
    System.assertEquals(
      false,
      ChangeBillingEventUtil.doesBillingContentDiffer(null, null)
    );
    System.assertEquals(
      false,
      ChangeBillingEventUtil.doesBillingContentDiffer(
        new ContractProduct__c(),
        null
      )
    );
  }

  @IsTest
  static void isInvoiceSettingOnlyChange_detectsSettingOnlyAndRejectsMixed() {
    Id lineageId = fakeId(ContractProduct__c.SObjectType, 30);
    Id productId = fakeId(Product2.SObjectType, 1);
    ContractProduct__c original = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 31),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2027, 5, 31),
      Type__c = 'Original',
      PreviousContractProduct__c = lineageId
    );
    ContractProduct__c remakeSettingOnly = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 32),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2027, 5, 31),
      Type__c = 'Remake',
      PreviousContractProduct__c = lineageId
    );
    System.assertEquals(
      true,
      ChangeBillingEventUtil.isInvoiceSettingOnlyChange(
        new List<ContractProduct__c>{ original, remakeSettingOnly }
      )
    );

    ContractProduct__c remakeQty = remakeSettingOnly.clone(
      true,
      true,
      false,
      false
    );
    remakeQty.Quantity__c = 2;
    System.assertEquals(
      false,
      ChangeBillingEventUtil.isInvoiceSettingOnlyChange(
        new List<ContractProduct__c>{ original, remakeQty }
      ),
      '数量変更があれば設定だけではない'
    );

    ContractProduct__c addedNew = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 33),
      Product__c = productId,
      Quantity__c = 1,
      Type__c = 'New',
      StartDate__c = Date.newInstance(2026, 8, 1),
      Enddate__c = Date.newInstance(2026, 8, 31)
    );
    System.assertEquals(
      false,
      ChangeBillingEventUtil.isInvoiceSettingOnlyChange(
        new List<ContractProduct__c>{ original, remakeSettingOnly, addedNew }
      ),
      'New 追加があれば設定だけではない'
    );
  }

  @IsTest
  static void doesBillingContentDiffer_detectsQuantityAndUnitPrice_notInvoiceSetting() {
    // Core 第4.4.1節: 数量・単価はイベント。請求設定の差はイベントではない。
    Id productA = fakeId(Product2.SObjectType, 1);
    ContractProduct__c original = new ContractProduct__c(
      Product__c = productA,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
    );

    System.assertEquals(
      true,
      ChangeBillingEventUtil.doesBillingContentDiffer(
        new ContractProduct__c(
          Product__c = productA,
          Quantity__c = 2,
          UnitPrice__c = 1000,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
        ),
        original
      ),
      'Core 第4.4.1節: 数量1から2への変更は課金イベント'
    );
    System.assertEquals(
      true,
      ChangeBillingEventUtil.doesBillingContentDiffer(
        new ContractProduct__c(
          Product__c = productA,
          Quantity__c = 1,
          UnitPrice__c = 1200,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
        ),
        original
      ),
      'Core 第4.4.1節: 単価1000から1200への変更は課金イベント'
    );
    System.assertEquals(
      false,
      ChangeBillingEventUtil.doesBillingContentDiffer(
        new ContractProduct__c(
          Product__c = productA,
          Quantity__c = 1,
          UnitPrice__c = 1000,
          InvoiceSetting__c = '月次後払'
        ),
        original
      ),
      '請求設定だけの差は課金イベントの内容差にしない'
    );
  }

  @IsTest
  static void filterProductsForEstimateDocument_keepsDerivativeLineageWithBillingEvent() {
    Id lineageId = fakeId(ContractProduct__c.SObjectType, 20);
    Id productId = fakeId(Product2.SObjectType, 1);
    ContractProduct__c original = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 21),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      Type__c = 'Original',
      PreviousContractProduct__c = lineageId
    );
    ContractProduct__c derivative = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 22),
      Product__c = productId,
      Quantity__c = 2,
      UnitPrice__c = 1000,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      Type__c = 'Derivative',
      PreviousContractProduct__c = lineageId
    );

    List<ContractProduct__c> filtered = ChangeBillingEventUtil.filterProductsForEstimateDocument(
      'Change',
      new List<ContractProduct__c>{ original, derivative }
    );

    System.assertEquals(2, filtered.size());
  }

  @IsTest
  static void filterProductsForEstimateDocument_excludesInvoiceSettingOnlyLineage() {
    Id lineageId = fakeId(ContractProduct__c.SObjectType, 40);
    Id productId = fakeId(Product2.SObjectType, 1);
    ContractProduct__c original = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 41),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      Type__c = 'Original',
      PreviousContractProduct__c = lineageId
    );
    ContractProduct__c remake = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 42),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      Type__c = 'Remake',
      PreviousContractProduct__c = lineageId
    );
    List<ContractProduct__c> filtered = ChangeBillingEventUtil.filterProductsForEstimateDocument(
      'Change',
      new List<ContractProduct__c>{ original, remake }
    );
    System.assertEquals(
      0,
      filtered.size(),
      'Core 第4.4.1節: 請求設定の差は継続課金イベントではない'
    );
  }

  @IsTest
  static void isInvoiceSettingOnlyChange_emptyOrMidTermStart_isNotSettingOnly() {
    System.assertEquals(
      false,
      ChangeBillingEventUtil.isInvoiceSettingOnlyChange(null)
    );
    System.assertEquals(
      false,
      ChangeBillingEventUtil.isInvoiceSettingOnlyChange(
        new List<ContractProduct__c>()
      )
    );
    Id lineageId = fakeId(ContractProduct__c.SObjectType, 50);
    Id productId = fakeId(Product2.SObjectType, 1);
    ContractProduct__c original = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 51),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      Type__c = 'Original',
      PreviousContractProduct__c = lineageId
    );
    ContractProduct__c remake = new ContractProduct__c(
      Id = fakeId(ContractProduct__c.SObjectType, 52),
      Product__c = productId,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
      StartDate__c = Date.newInstance(2026, 10, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      Type__c = 'Remake',
      PreviousContractProduct__c = lineageId
    );
    System.assertEquals(
      false,
      ChangeBillingEventUtil.isInvoiceSettingOnlyChange(
        new List<ContractProduct__c>{ original, remake }
      ),
      'Core 第4.4.1節: Remakeの途中開始は課金イベント'
    );
  }

  private static Id fakeId(Schema.SObjectType sobjectType, Integer n) {
    String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
    String suffix = String.valueOf(n).leftPad(12, '0');
    return Id.valueOf(keyPrefix + suffix);
  }
}
