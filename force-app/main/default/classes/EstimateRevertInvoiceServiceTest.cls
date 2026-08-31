@IsTest
private class EstimateRevertInvoiceServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  private static final String BILLING_TYPE_RECURRING = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
  private static final String INVOICE_SETTING_MONTHLY = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;

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
        Amount__c = 8000
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
  static void revertToEstimate_deletesInvoices() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createSingleOrderedContext();

      Invoice__c invoice = new Invoice__c(
        ContractService__c = context.history.ContractService__c,
        ContractHistory__c = context.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 8000,
        TaxAmount__c = 800
      );
      insert invoice;

      context.history.historystatus__c = 'Estimate';
      Test.startTest();
      update context.history;
      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :context.history.Id
        ],
        '???????????????'
      );
    }
  }

  @IsTest
  static void revertToEstimate_allowsLogicallyDeletedDraftJournal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createSingleOrderedContext();
      Invoice__c invoice = new Invoice__c(
        ContractService__c = context.history.ContractService__c,
        ContractHistory__c = context.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 8000,
        TaxAmount__c = 800
      );
      insert invoice;
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'REVERT_DELETED', String.valueOf(invoice.Id) }
        ),
        JournalLineKey__c = 'revert-deleted',
        DebitSlotKey__c = AccountingSlotFixedCatalog.Cash.key,
        CreditSlotKey__c = AccountingSlotFixedCatalog.UnappliedCash.key,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'LogicallyDeleted'
      );

      context.history.historystatus__c = 'Estimate';
      Test.startTest();
      update context.history;
      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :context.history.Id
        ],
        'Accounting 第1.8.1節: 論理削除だけ残る未確定は差し戻せる'
      );
    }
  }

  @IsTest
  static void revertToEstimate_blocksWhenDraftHasActiveJournal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createSingleOrderedContext();
      Invoice__c invoice = new Invoice__c(
        ContractService__c = context.history.ContractService__c,
        ContractHistory__c = context.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 8000,
        TaxAmount__c = 800
      );
      insert invoice;
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'REVERT_ACTIVE', String.valueOf(invoice.Id) }
        ),
        JournalLineKey__c = 'revert-active',
        DebitSlotKey__c = AccountingSlotFixedCatalog.Cash.key,
        CreditSlotKey__c = AccountingSlotFixedCatalog.UnappliedCash.key,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );

      Boolean thrown = false;
      Test.startTest();
      try {
        context.history.historystatus__c = 'Estimate';
        update context.history;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getDmlMessage(0)
            .contains(EstimateRevertInvoiceService.DRAFT_JOURNAL_REVERT_MESSAGE),
          'Core 第5.3節: 未確定に有効な仕訳がある差し戻しは全体拒否'
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ]
        .historystatus__c
      );
    }
  }

  @IsTest
  static void revertToEstimate_doesNotModifyPriorHistoryInvoiceProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createTwoVersionContext(
        Date.newInstance(2026, 10, 1)
      );

      Test.startTest();
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
        Amount__c = -8000
      );

      Integer priorCountBefore = [
        SELECT COUNT()
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :context.priorHistory.Id
      ];

      context.changeHistory.historystatus__c = 'Estimate';
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

      ContractTestDataFactory.insertAllowingInvoiceStatus(
        new Invoice__c(
        ContractService__c = context.history.ContractService__c,
        ContractHistory__c = context.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 8000,
        TaxAmount__c = 800,
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
        SystemIntegrationDate__c = Date.today()
      )
      );

      Integer invoiceCountBefore = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE ContractHistory__c = :context.history.Id
      ];

      Boolean thrown = false;
      Test.startTest();
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
      Test.stopTest();
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ]
        .historystatus__c,
        '??E??????E Ordered ???'
      );
      System.assertEquals(
        invoiceCountBefore,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :context.history.Id
        ],
        '????E??????????E'
      );
    }
  }

  @IsTest
  static void revertToEstimate_blocksWhenNewerOrderedVersionExists() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createTwoVersionContext(
        Date.newInstance(2026, 10, 1)
      );
      Test.startTest();
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
      Test.stopTest();
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
      Test.startTest();
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
      Test.stopTest();
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.priorHistory.Id
        ]
        .historystatus__c,
        'Archive ????E Ordered ???'
      );
    }
  }

  @IsTest
  static void isLatestOrderedHistory_returnsFalseForPriorOrdered() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createTwoVersionContext(
        Date.newInstance(2026, 10, 1)
      );
      Test.startTest();
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
      Test.stopTest();
    }
  }

  @IsTest
  static void isLatestOrderedHistory_usesVersionNotLatestPointer() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createTwoVersionContext(
        Date.newInstance(2026, 10, 1)
      );
      Test.startTest();
      context.changeHistory.historystatus__c = 'Ordered';
      update context.changeHistory;

      // ????????E????EV1 ??????????E????????E
      update new ContractService__c(
        Id = context.priorHistory.ContractService__c,
        LatestOrderedHistory__c = context.priorHistory.Id
      );

      System.assertEquals(
        false,
        EstimateRevertInvoiceService.isLatestOrderedHistory(
          context.priorHistory.Id
        ),
        'Version ????EV1 ???????E?E???E??????????E'
      );
      System.assertEquals(
        true,
        EstimateRevertInvoiceService.isLatestOrderedHistory(
          context.changeHistory.Id
        ),
        'Version ??? V2 ??????????E?????'
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
      Test.stopTest();
      System.assertEquals(true, priorBlocked, '??EVersion ??????E??');
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
      Test.startTest();
      context.changeHistory.historystatus__c = 'Ordered';
      update context.changeHistory;

      insert new ContractHistory__c(
        Name = 'Newer Estimate v3',
        ContractService__c = context.changeHistory.ContractService__c,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 3,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 6, 30),
        EffectiveDate__c = Date.newInstance(2026, 12, 1),
        PreviousHistory__c = context.changeHistory.Id
      );

      context.changeHistory.historystatus__c = 'Estimate';
      update context.changeHistory;
      Test.stopTest();

      ContractHistory__c reverted = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :context.changeHistory.Id
      ];
      System.assertEquals('Estimate', reverted.historystatus__c);
      System.assertEquals(
        'Archive',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Name = 'Newer Estimate v3'
          LIMIT 1
        ]
        .historystatus__c
      );
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
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 25,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
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
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2026, 6, 30)
    );
    insert history;

    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Amount__c = 8000,
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2026, 6, 30),
      InvoiceSetting__c = INVOICE_SETTING_MONTHLY,
      BillingType__c = BILLING_TYPE_RECURRING,
      Type__c = 'Renew'
    );
    insert contractProduct;
    history.historystatus__c = 'Ordered';
    update history;
    history = [
      SELECT Id, ContractService__c, historystatus__c, Version__c
      FROM ContractHistory__c
      WHERE Id = :history.Id
    ];

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
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2026, 6, 30),
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
      Enddate__c = Date.newInstance(2026, 6, 30),
      InvoiceSetting__c = INVOICE_SETTING_MONTHLY,
      BillingType__c = BILLING_TYPE_RECURRING,
      Type__c = 'New'
    );
    insert priorContractProduct;
    priorHistory.historystatus__c = 'Ordered';
    update priorHistory;
    priorHistory = [
      SELECT Id, ContractService__c, historystatus__c, Version__c
      FROM ContractHistory__c
      WHERE Id = :priorHistory.Id
    ];

    // Version ????????????E Change ???????? Type=New
    ContractHistory__c changeHistory = new ContractHistory__c(
      Name = 'Revert Change History v2',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 2,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2026, 6, 30),
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
      Enddate__c = Date.newInstance(2026, 6, 30),
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
