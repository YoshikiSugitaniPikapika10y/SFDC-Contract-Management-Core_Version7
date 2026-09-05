@IsTest
private class EstimateRevertInvoiceServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
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
      insertDraftInvoice(context);

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
        'Core 第4.9節: 差し戻しは自履歴の未確定請求を消す'
      );
    }
  }

  @IsTest
  static void revertToEstimate_allowsLogicallyDeletedDraftJournal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createSingleOrderedContext();
      Invoice__c invoice = insertDraftInvoice(context);
      insertJournal(invoice.Id, 'revert-deleted', 'LogicallyDeleted');

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
        'Core 第5.3節: 消す未確定を参照する仕訳があっても差し戻せる'
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM GlJournal__c WHERE Invoice__c = :invoice.Id],
        'Core 第5.3節: 未確定を参照する仕訳は請求削除の前に物理削除する'
      );
    }
  }

  @IsTest
  static void revertToEstimate_deletesActiveDraftJournalsThenPurges() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createSingleOrderedContext();
      Invoice__c invoice = insertDraftInvoice(context);
      insertJournal(invoice.Id, 'revert-active', 'Active');

      context.history.historystatus__c = 'Estimate';
      Test.startTest();
      update context.history;
      Test.stopTest();

      System.assertEquals(
        'Estimate',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :context.history.Id
        ]
        .historystatus__c,
        'Core 第5.3節: 仕訳の有無では差し戻しを拒否しない'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :context.history.Id
        ]
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM GlJournal__c WHERE Invoice__c = :invoice.Id],
        'Core 第5.3節: 未確定を参照する仕訳は状態を問わず物理削除する'
      );
    }
  }

  @IsTest
  static void revertToEstimate_keepsCancelledInvoiceJournals() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestContext context = createSingleOrderedContext();
      Invoice__c cancelled = insertDraftInvoice(context);
      Boolean previous = InvoiceTransactionStatusService.allowStatusWrite;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      try {
        cancelled.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CANCELLED;
        update cancelled;
      } finally {
        InvoiceTransactionStatusService.allowStatusWrite = previous;
      }
      insertJournal(cancelled.Id, 'revert-cancelled', 'LogicallyDeleted');

      context.history.historystatus__c = 'Estimate';
      Test.startTest();
      update context.history;
      Test.stopTest();

      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE
            Id = :cancelled.Id
            AND InvoiceTransactionStatus__c = :InvoiceTransactionStatusService.TX_CANCELLED
        ],
        'Core 第5.3節: 取消済み請求は元契約履歴に残す'
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM GlJournal__c WHERE Invoice__c = :cancelled.Id],
        'Core 第5.3節: 取消済み請求を参照する仕訳は削除しない'
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
      Invoice__c invoice = new Invoice__c(
        ContractService__c = context.history.ContractService__c,
        ContractHistory__c = context.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 8000,
        TaxAmount__c = 800,
        BillingAccountSnapShot__c = context.billingAccountId
      );
      ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = Date.today();
      ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);

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
        '確定済み請求がある差し戻しは Ordered のまま'
      );
      System.assertEquals(
        invoiceCountBefore,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :context.history.Id
        ],
        '拒否時は確定済み請求を残す'
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
        '受注済みから不採用には変更できない'
      );
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

      Boolean previous = ContractServiceWriteGuard.isPackageWriteAllowed();
      ContractServiceWriteGuard.allowPackageWrite(true);
      try {
        update new ContractService__c(
          Id = context.priorHistory.ContractService__c,
          LatestOrderedHistory__c = context.priorHistory.Id
        );
      } finally {
        ContractServiceWriteGuard.allowPackageWrite(previous);
      }

      System.assertEquals(
        false,
        EstimateRevertInvoiceService.isLatestOrderedHistory(
          context.priorHistory.Id
        ),
        'Latest Ordered ポインタではなく Version で最新を判定する'
      );
      System.assertEquals(
        true,
        EstimateRevertInvoiceService.isLatestOrderedHistory(
          context.changeHistory.Id
        ),
        'Version が大きい V2 が最新の受注である'
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
      System.assertEquals(true, priorBlocked, 'Version が古い受注は差し戻せない');
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

      ContractHistory__c newer = new ContractHistory__c(
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
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        newer,
        context.accountId
      );
      insert newer;

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
        .historystatus__c,
        'Core 第4.9節: 差し戻しはより新しい Estimate を先に Archive にする'
      );
    }
  }

  @IsTest
  static void revertHelpers_emptyAndNull_doNotChangeHistories() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateRevertInvoiceService.archiveNewerEstimates(null);
      EstimateRevertInvoiceService.archiveNewerEstimates(
        new List<ContractHistory__c>()
      );
      EstimateRevertInvoiceService.archiveNewerEstimates(
        new List<ContractHistory__c>{ null, new ContractHistory__c() }
      );
      EstimateRevertInvoiceService.adjustForRevertedToEstimateHistories(null);
      EstimateRevertInvoiceService.adjustForRevertedToEstimateHistories(
        new List<ContractHistory__c>()
      );
      EstimateRevertInvoiceService.adjustForRevertedToEstimateHistories(
        new List<ContractHistory__c>{ new ContractHistory__c() }
      );
      System.assertEquals(
        false,
        EstimateRevertInvoiceService.isLatestOrderedHistory(null),
        'Core 第4.9節: Latest Ordered だけ差し戻せる。空の履歴は最新と証明できない'
      );
      System.assertEquals(
        false,
        EstimateRevertInvoiceService.hasNewerEstimateVersion(null),
        'Core 第4.9節: より新しい Estimate の判定も空の履歴ではしない'
      );
      EstimateRevertInvoiceService.RevertBlockSets emptyBlocks =
        EstimateRevertInvoiceService.queryRevertBlockSets(null);
      System.assertEquals(
        0,
        emptyBlocks.nonLatestOrderedHistoryIds.size(),
        'Core 第4.9節: 対象が空なら差し戻し拒否の集合も空'
      );
      System.assertEquals(0, emptyBlocks.newerEstimateHistoryIds.size());
    }
  }

  private class TestContext {
    public Id accountId;
    public Id billingAccountId;
    public ContractHistory__c history;
    public ContractProduct__c contractProduct;
    public ContractHistory__c priorHistory;
    public ContractHistory__c changeHistory;
    public ContractProduct__c priorContractProduct;
  }

  private static Invoice__c insertDraftInvoice(TestContext context) {
    Invoice__c invoice = new Invoice__c(
      ContractService__c = context.history.ContractService__c,
      ContractHistory__c = context.history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 8000,
      TaxAmount__c = 800,
      BillingAccountSnapShot__c = context.billingAccountId
    );
    ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
    insert invoice;
    return invoice;
  }

  private static void insertJournal(
    Id invoiceId,
    String lineKey,
    String transactionStatus
  ) {
    GlAccount__c debit = new GlAccount__c(
      Name = 'Revert J Debit ' + String.valueOf(Crypto.getRandomInteger()),
      AccountType__c = 'Asset',
      IsActive__c = true
    );
    GlAccount__c credit = new GlAccount__c(
      Name = 'Revert J Credit ' + String.valueOf(Crypto.getRandomInteger()),
      AccountType__c = 'Revenue',
      IsActive__c = true
    );
    insert new List<GlAccount__c>{ debit, credit };
    insert new GlJournal__c(
      Invoice__c = invoiceId,
      Amount__c = 1,
      IdempotencyKey__c = AccountingDiffService.hashKey(
        new List<String>{ lineKey, String.valueOf(invoiceId) }
      ),
      JournalLineKey__c = lineKey,
      DebitSlotKey__c = AccountingSlotFixedCatalog.AccountsReceivable.key,
      CreditSlotKey__c = AccountingSlotFixedCatalog.Revenue.key,
      DebitAccount__c = debit.Id,
      CreditAccount__c = credit.Id,
      PostingDate__c = Date.newInstance(2026, 6, 1),
      TransactionStatus__c = transactionStatus
    );
  }

  private static ContractProduct__c insertLine(
    Id historyId,
    Id accountId,
    Product2 product,
    String productType,
    Date startDate,
    Date endDate
  ) {
    return insertLine(
      historyId,
      accountId,
      product,
      productType,
      startDate,
      endDate,
      null
    );
  }

  private static ContractProduct__c insertLine(
    Id historyId,
    Id accountId,
    Product2 product,
    String productType,
    Date startDate,
    Date endDate,
    Id previousContractProductId
  ) {
    ContractProduct__c line = new ContractProduct__c(
      ContractHistory__c = historyId,
      Account__c = accountId,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Amount__c = 8000,
      StartDate__c = startDate,
      Enddate__c = endDate,
      InvoiceSetting__c = INVOICE_SETTING_MONTHLY,
      BillingType__c = BILLING_TYPE_RECURRING,
      Type__c = productType,
      PreviousContractProduct__c = previousContractProductId,
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
    );
    ContractTestDataFactory.applyRequiredFields(line);
    line.Amount__c = 8000;
    insert line;
    return line;
  }

  private static TestContext createSingleOrderedContext() {
    Account account = ContractTestDataFactory.insertAccount(
      'Revert Own Account'
    );
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
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
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2026, 6, 30),
      EffectiveDate__c = Date.newInstance(2026, 6, 1)
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
    insert history;

    ContractProduct__c contractProduct = insertLine(
      history.Id,
      account.Id,
      product,
      'New',
      Date.newInstance(2026, 6, 1),
      Date.newInstance(2026, 6, 30)
    );
    history.historystatus__c = 'Ordered';
    update history;
    history = [
      SELECT Id, ContractService__c, historystatus__c, Version__c
      FROM ContractHistory__c
      WHERE Id = :history.Id
    ];

    TestContext context = new TestContext();
    context.accountId = account.Id;
    context.billingAccountId = service.BiilingAcccount__c;
    context.history = history;
    context.contractProduct = contractProduct;
    return context;
  }

  private static TestContext createTwoVersionContext(Date effectiveDate) {
    Account account = ContractTestDataFactory.insertAccount(
      'Revert Prior Account'
    );
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
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
    ContractTestDataFactory.applyEstimateOrderedOpportunity(
      priorHistory,
      account.Id
    );
    insert priorHistory;

    ContractProduct__c priorContractProduct = insertLine(
      priorHistory.Id,
      account.Id,
      product,
      'New',
      Date.newInstance(2026, 6, 1),
      Date.newInstance(2026, 6, 30)
    );
    priorHistory.historystatus__c = 'Ordered';
    update priorHistory;
    priorHistory = [
      SELECT Id, ContractService__c, historystatus__c, Version__c
      FROM ContractHistory__c
      WHERE Id = :priorHistory.Id
    ];

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
    ContractTestDataFactory.applyEstimateOrderedOpportunity(
      changeHistory,
      account.Id
    );
    insert changeHistory;
    insertLine(
      changeHistory.Id,
      account.Id,
      product,
      'New',
      Date.newInstance(2026, 6, 1),
      Date.newInstance(2026, 6, 30)
    );

    TestContext context = new TestContext();
    context.accountId = account.Id;
    context.billingAccountId = service.BiilingAcccount__c;
    context.priorHistory = priorHistory;
    context.changeHistory = changeHistory;
    context.priorContractProduct = priorContractProduct;
    return context;
  }
}
