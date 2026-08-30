@IsTest
private class ContractServiceTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  private static ContractService__c insertServiceWithBillingAccount(
    Account account,
    String serviceName
  ) {
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END, PaymentTermMonthOffset__c = 0, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER, InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY, InvoiceDateDayOfMonth__c = 25, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    ContractService__c service = new ContractService__c(
      Name = serviceName,
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id
    );
    insert service;
    return service;
  }

  @IsTest
  static void beforeDelete_allowsDeleteWhenNotOrderedAndNoLockedInvoices() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'CS Delete Allow Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'CS Delete Allow Service'
      );

      ContractHistory__c history = new ContractHistory__c(
        Name = 'CS Delete Allow History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'CS Delete Allow Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c contractProduct = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert contractProduct;

      insert new InvoiceProduct__c(
        ContractHistory__c = history.Id,
        ContractProduct__c = contractProduct.Id,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceBucketKey__c = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
          null,
          history.Id,
          Date.newInstance(2026, 6, 1),
          null
        ),
        Amount__c = 96000
      );

      Test.startTest();
      delete service;
      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractService__c
          WHERE Id = :service.Id
        ]
      );
    }
  }

  @IsTest
  static void beforeDelete_blocksDeleteWhenLatestOrderedHistoryExists() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'CS Delete Ordered Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'CS Delete Ordered Service'
      );

      // Cancel Ordered ??E????? BA ???????E???????? Ordered ??????E?E
      insert new ContractHistory__c(
        Name = 'CS Delete Ordered History',
        ContractService__c = service.Id,
        Type__c = 'Cancel',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 6, 1),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );

      ContractService__c synced = [
        SELECT LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertNotEquals(null, synced.LatestOrderedHistory__c);

      Boolean thrown = false;
      try {
        Test.startTest();
        delete service;
        Test.stopTest();
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(
              ContractServiceTriggerHandler.ORDERED_DELETE_BLOCK_MESSAGE
            ),
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);

      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractService__c
          WHERE Id = :service.Id
        ]
      );
    }
  }

  @IsTest
  static void beforeDelete_blocksDeleteWhenOrderedExistsEvenIfLatestPointerCleared() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'CS Delete Pointer Gap Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'CS Delete Pointer Gap Service'
      );

      insert new ContractHistory__c(
        Name = 'CS Delete Pointer Gap History',
        ContractService__c = service.Id,
        Type__c = 'Cancel',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 6, 1),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );

      // ??????????EOrdered ????E????
      update new ContractService__c(
        Id = service.Id,
        LatestOrderedHistory__c = null,
        FirstOrderedHistory__c = null
      );

      Boolean thrown = false;
      try {
        Test.startTest();
        delete service;
        Test.stopTest();
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(
              ContractServiceTriggerHandler.ORDERED_DELETE_BLOCK_MESSAGE
            ),
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeDelete_blocksDeleteWhenLockedInvoiceProductsExist() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'CS Delete Locked IP Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'CS Delete Locked IP Service'
      );

      ContractHistory__c history = new ContractHistory__c(
        Name = 'CS Delete Locked IP History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'CS Delete Locked IP Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c contractProduct = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert contractProduct;

      ContractTestDataFactory.insertAllowingInvoiceStatus(
        new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 96000,
        TaxAmount__c = 9600,
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
        SystemIntegrationDate__c = Date.today()
      )
      );

      Boolean thrown = false;
      try {
        Test.startTest();
        delete service;
        Test.stopTest();
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(
              ContractServiceTriggerHandler.LOCKED_INVOICE_DELETE_BLOCK_MESSAGE
            ),
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);

      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractService__c
          WHERE Id = :service.Id
        ]
      );
    }
  }

  @IsTest
  static void serviceEndDate_helpUsesJapaneseOrderedCancelNames() {
    String helpText = ContractService__c.ServiceEndDate__c.getDescribe()
      .getInlineHelpText();
    System.assertNotEquals(null, helpText);
    System.assert(
      helpText.contains('受注済み'),
      'Core 第0.1節: Ordered の画面表示は受注済み'
    );
    System.assert(
      helpText.contains('解約'),
      'Core 第0.1節: Cancel の画面表示は解約'
    );
    System.assert(
      !helpText.contains('Ordered'),
      'Core 第0.1節: ヘルプに Ordered と出さない'
    );
    System.assert(
      !helpText.contains('Cancel'),
      'Core 第0.1節: ヘルプに Cancel と出さない'
    );
  }

  @IsTest
  static void lifecycle_helpUsesJapaneseTermSpotDisplayNames() {
    String helpText = ContractService__c.Lifecycle__c.getDescribe()
      .getInlineHelpText();
    System.assertNotEquals(null, helpText);
    System.assert(
      helpText.contains('期間契約'),
      'Core 第0.1節: Lifecycle の画面表示は期間契約'
    );
    System.assert(
      helpText.contains('都度契約'),
      'Core 第0.1節: Lifecycle の画面表示は都度契約'
    );
    System.assert(
      !helpText.contains('Term'),
      'Core 第0.1節: ヘルプに Term と出さない'
    );
    System.assert(
      !helpText.contains('Spot'),
      'Core 第0.1節: ヘルプに Spot と出さない'
    );
  }
}
