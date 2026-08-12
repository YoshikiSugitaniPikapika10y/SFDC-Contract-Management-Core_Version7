@IsTest
private class EstimateRevertInvoiceServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  private static final String BILLING_TYPE_RECURRING = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
  private static final String INVOICE_SETTING_MONTHLY = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
  private static final String CREDIT_NOTE_INVOICE_TYPE =
    INVOICE_SETTING_MONTHLY + '（赤伝）';

  @IsTest
  static void revertToEstimate_deletesUninvoicedProductsOnOwnHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createSingleOrderedContext();

      insert new InvoiceProduct__c(
        ContractHistory__c = context.history.Id,
        ContractProduct__c = context.contractProduct.Id,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30),
        InvoiceBucketKey__c = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
          null,
          context.history.Id,
          Date.newInstance(2026, 6, 1),
          null
        ),
        Amount__c = 8000,
        invoicetype__c = INVOICE_SETTING_MONTHLY
      );

      context.history.historystatus__c = 'Estimate';
      Test.startTest();
      update context.history;
      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :context.history.Id
        ]
      );
    }
  }

  @IsTest
  static void revertToEstimate_doesNotModifyPriorHistoryInvoiceProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createTwoVersionContext(
        Date.newInstance(2026, 10, 1)
      );

      context.changeHistory.historystatus__c = 'Ordered';
      update context.changeHistory;

      insert new InvoiceProduct__c(
        ContractHistory__c = context.priorHistory.Id,
        ContractProduct__c = context.priorContractProduct.Id,
        StartDate__c = Date.newInstance(2026, 10, 1),
        Enddate__c = Date.newInstance(2026, 10, 31),
        InvoiceBucketKey__c = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
          null,
          context.priorHistory.Id,
          Date.newInstance(2026, 10, 1),
          null
        ),
        Amount__c = -8000,
        invoicetype__c = CREDIT_NOTE_INVOICE_TYPE
      );

      Integer priorCountBefore = [
        SELECT COUNT()
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :context.priorHistory.Id
      ];

      context.changeHistory.historystatus__c = 'Estimate';
      Test.startTest();
      update context.changeHistory;
      Test.stopTest();

      System.assertEquals(
        priorCountBefore,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :context.priorHistory.Id
        ]
      );
    }
  }

  @IsTest
  static void revertToEstimate_blocksWhenInvoicedProductsExistOnOwnHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createSingleOrderedContext();

      insert new Invoice__c(
        ContractService__c = context.history.ContractService__c,
        ContractHistory__c = context.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 8000,
        TaxAmount__c = 800,
        SystemIntegrationDate__c = Date.today()
      );

      Integer invoiceCountBefore = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
      ];

      Boolean thrown = false;
      try {
        context.history.historystatus__c = 'Estimate';
        update context.history;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          ex.getDmlMessage(0)
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ]
        .historystatus__c,
        'ロック拒否時は Ordered のまま'
      );
      System.assertEquals(
        invoiceCountBefore,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :context.history.Id
        ],
        '拒否時は請求件数が変わらない'
      );
    }
  }

  @IsTest
  static void revertToEstimate_blocksWhenNewerOrderedVersionExists() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createTwoVersionContext(
        Date.newInstance(2026, 10, 1)
      );
      context.changeHistory.historystatus__c = 'Ordered';
      update context.changeHistory;

      Boolean thrown = false;
      try {
        context.priorHistory.historystatus__c = 'Estimate';
        update context.priorHistory;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          EstimateRevertInvoiceService.NON_LATEST_ORDERED_REVERT_MESSAGE,
          ex.getDmlMessage(0)
        );
      }
      System.assertEquals(true, thrown);

      ContractHistory__c prior = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.priorHistory.Id
      ];
      System.assertEquals('Ordered', prior.historystatus__c);
    }
  }

  @IsTest
  static void revertToArchive_blocksOrderedToArchive() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createTwoVersionContext(
        Date.newInstance(2026, 10, 1)
      );
      context.changeHistory.historystatus__c = 'Ordered';
      update context.changeHistory;

      Boolean thrown = false;
      try {
        context.priorHistory.historystatus__c = 'Archive';
        update context.priorHistory;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          ContractHistoryTriggerHandler.ORDERED_TO_ARCHIVE_BLOCK_MESSAGE,
          ex.getDmlMessage(0)
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.priorHistory.Id
        ]
        .historystatus__c,
        'Archive 拒否時は Ordered のまま'
      );
    }
  }

  @IsTest
  static void isLatestOrderedHistory_returnsFalseForPriorOrdered() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createTwoVersionContext(
        Date.newInstance(2026, 10, 1)
      );
      context.changeHistory.historystatus__c = 'Ordered';
      update context.changeHistory;

      System.assertEquals(
        false,
        EstimateRevertInvoiceService.isLatestOrderedHistory(
          context.priorHistory.Id
        )
      );
      System.assertEquals(
        true,
        EstimateRevertInvoiceService.isLatestOrderedHistory(
          context.changeHistory.Id
        )
      );
    }
  }

  @IsTest
  static void isLatestOrderedHistory_usesVersionNotLatestPointer() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createTwoVersionContext(
        Date.newInstance(2026, 10, 1)
      );
      context.changeHistory.historystatus__c = 'Ordered';
      update context.changeHistory;

      // ポインタを意図的に古い V1 へずらす（同期キャッシュ破損相当）
      update new ContractService__c(
        Id = context.priorHistory.ContractService__c,
        LatestOrderedHistory__c = context.priorHistory.Id
      );

      System.assertEquals(
        false,
        EstimateRevertInvoiceService.isLatestOrderedHistory(
          context.priorHistory.Id
        ),
        'Version が小さい V1 はポインタが自分を指しても最新ではない'
      );
      System.assertEquals(
        true,
        EstimateRevertInvoiceService.isLatestOrderedHistory(
          context.changeHistory.Id
        ),
        'Version 最大の V2 はポインタがずれていても最新'
      );

      Boolean priorBlocked = false;
      try {
        context.priorHistory.historystatus__c = 'Estimate';
        update context.priorHistory;
      } catch (DmlException ex) {
        priorBlocked = true;
        System.assertEquals(
          EstimateRevertInvoiceService.NON_LATEST_ORDERED_REVERT_MESSAGE,
          ex.getDmlMessage(0)
        );
      }
      System.assertEquals(true, priorBlocked, '古い Version の差し戻しは拒否');
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.priorHistory.Id
        ]
        .historystatus__c
      );
    }
  }

  @IsTest
  static void revertToEstimate_blocksWhenNewerEstimateVersionExists() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createTwoVersionContext(
        Date.newInstance(2026, 10, 1)
      );
      context.changeHistory.historystatus__c = 'Ordered';
      update context.changeHistory;

      insert new ContractHistory__c(
        Name = 'Newer Estimate v3',
        ContractService__c = context.changeHistory.ContractService__c,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 3,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 12, 1),
        PreviousHistory__c = context.changeHistory.Id
      );

      Boolean thrown = false;
      try {
        context.changeHistory.historystatus__c = 'Estimate';
        update context.changeHistory;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          EstimateRevertInvoiceService.NEWER_ESTIMATE_REVERT_MESSAGE,
          ex.getDmlMessage(0)
        );
      }
      System.assertEquals(true, thrown);

      ContractHistory__c stillOrdered = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.changeHistory.Id
      ];
      System.assertEquals('Ordered', stillOrdered.historystatus__c);
    }
  }

  private class TestContext {
    public ContractHistory__c history;
    public ContractProduct__c contractProduct;
    public ContractHistory__c priorHistory;
    public ContractHistory__c changeHistory;
    public ContractProduct__c priorContractProduct;
  }

  private static ContractService__c insertServiceWithBillingAccount(
    Account account,
    String serviceName
  ) {
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
      AdjustInvoiceDateToBusinessDay__c = false
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

  private static TestContext createSingleOrderedContext() {
    Account account = ContractTestDataFactory.insertAccount(
      'Revert Own Account'
    );
    ContractService__c service = insertServiceWithBillingAccount(
      account,
      'Revert Own Service'
    );

    Product2 product = ContractTestDataFactory.buildProduct(
      'Revert Own Product'
    );
    product.BillingType__c = BILLING_TYPE_RECURRING;
    ContractTestDataFactory.insertProduct(product);

    ContractHistory__c history = new ContractHistory__c(
      Name = 'Revert Own History',
      ContractService__c = service.Id,
      Type__c = 'Renew',
      historystatus__c = 'Ordered',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
    );
    insert history;

    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Amount__c = 8000,
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2027, 5, 31),
      InvoiceSetting__c = INVOICE_SETTING_MONTHLY,
      BillingType__c = BILLING_TYPE_RECURRING,
      Type__c = 'Renew'
    );
    insert contractProduct;

    TestContext context = new TestContext();
    context.history = history;
    context.contractProduct = contractProduct;
    return context;
  }

  private static TestContext createTwoVersionContext(Date effectiveDate) {
    Account account = ContractTestDataFactory.insertAccount(
      'Revert Prior Account'
    );
    ContractService__c service = insertServiceWithBillingAccount(
      account,
      'Revert Prior Service'
    );

    Product2 product = ContractTestDataFactory.buildProduct(
      'Revert Prior Product'
    );
    product.BillingType__c = BILLING_TYPE_RECURRING;
    ContractTestDataFactory.insertProduct(product);

    ContractHistory__c priorHistory = new ContractHistory__c(
      Name = 'Revert Prior History v1',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
      EffectiveDate__c = Date.newInstance(2026, 6, 1)
    );
    insert priorHistory;

    ContractProduct__c priorContractProduct = new ContractProduct__c(
      ContractHistory__c = priorHistory.Id,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Amount__c = 8000,
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2027, 5, 31),
      InvoiceSetting__c = INVOICE_SETTING_MONTHLY,
      BillingType__c = BILLING_TYPE_RECURRING,
      Type__c = 'New'
    );
    insert priorContractProduct;

    // Version 並びの検証用。請求生成の Change 検証を避けるため Type=New
    ContractHistory__c changeHistory = new ContractHistory__c(
      Name = 'Revert Change History v2',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 2,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
      EffectiveDate__c = effectiveDate,
      PreviousHistory__c = priorHistory.Id
    );
    insert changeHistory;
    insert new ContractProduct__c(
      ContractHistory__c = changeHistory.Id,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Amount__c = 8000,
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2027, 5, 31),
      InvoiceSetting__c = INVOICE_SETTING_MONTHLY,
      BillingType__c = BILLING_TYPE_RECURRING,
      Type__c = 'New'
    );

    TestContext context = new TestContext();
    context.priorHistory = priorHistory;
    context.changeHistory = changeHistory;
    context.priorContractProduct = priorContractProduct;
    return context;
  }
}
