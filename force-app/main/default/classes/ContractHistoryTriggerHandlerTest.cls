@IsTest
private class ContractHistoryTriggerHandlerTest {
  /** Ordered ???E??E??E????????E?E????????E*/
  private static ContractService__c insertServiceWithBillingAccount(
    Account account,
    String serviceName
  ) {
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      BillingEmailCc__c = 'cc@example.com',
      BillingEmailBcc__c = 'bcc@example.com',
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

  @IsTest
  static void beforeUpdate_blocksRevertToEstimateWhenInvoicedProductsExist() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Revert Block Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Revert Block Service'
      );

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Revert Block History',
        ContractService__c = service.Id,
        Type__c = 'Renew',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Revert Block Product'
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
        Type__c = 'Renew'
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
        history.historystatus__c = 'Estimate';
        update history;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          dmlMessage(ex)
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ]
        .historystatus__c
      );
    }
  }

  @IsTest
  static void beforeUpdate_blocksRevertToEstimateWhenExportedProductsExist() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Revert Export Block Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Revert Export Block Service'
      );

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Revert Export Block History',
        ContractService__c = service.Id,
        Type__c = 'Renew',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Revert Export Block Product'
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
        Type__c = 'Renew'
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
        CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_COMPLETED,
        SystemIntegrationDate__c = null,
        PaymentClearingCompletedDate__c = Date.newInstance(2026, 6, 1)
      )
      );

      Boolean thrown = false;
      try {
        history.historystatus__c = 'Estimate';
        update history;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          dmlMessage(ex)
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ]
        .historystatus__c
      );
    }
  }

  @IsTest
  static void beforeUpdate_allowsRevertToEstimateWhenNoInvoicedProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Revert Allow Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Revert Allow Service'
      );

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Revert Allow History',
        ContractService__c = service.Id,
        Type__c = 'Renew',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Revert Allow Product'
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
        Type__c = 'Renew'
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

      history.historystatus__c = 'Estimate';
      update history;

      ContractHistory__c updated = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Estimate', updated.historystatus__c);
    }
  }

  @IsTest
  static void beforeUpdate_blocksRevertToEstimateWhenNewerOrderedExists() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Revert NonLatest Account'
      );
      // ?????E Ordered ? MAX(Version) ???confirmOrder ???E??EOQL ??E??E
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Revert NonLatest Service'
      );

      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Revert NonLatest History v1',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insert priorHistory;

      // Type ? New ????E?Ehange ? after insert ???????E?E????????E?E
      insert new ContractHistory__c(
        Name = 'Revert NonLatest History v2',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 2,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1),
        PreviousHistory__c = priorHistory.Id
      );

      Test.startTest();
      Boolean thrown = false;
      try {
        priorHistory.historystatus__c = 'Estimate';
        update priorHistory;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          EstimateRevertInvoiceService.NON_LATEST_ORDERED_REVERT_MESSAGE,
          dmlMessage(ex)
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeUpdate_archivesNewerEstimateWhenReverting() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Revert Newer Estimate Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Revert Newer Estimate Service'
      );

      ContractHistory__c orderedHistory = new ContractHistory__c(
        Name = 'Revert Newer Estimate History v1',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insert orderedHistory;

      insert new ContractHistory__c(
        Name = 'Revert Newer Estimate History v2',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 10, 1),
        PreviousHistory__c = orderedHistory.Id
      );

      ContractHistory__c newer = [
        SELECT Id
        FROM ContractHistory__c
        WHERE Name = 'Revert Newer Estimate History v2'
        LIMIT 1
      ];
      orderedHistory.historystatus__c = 'Estimate';
      update orderedHistory;
      System.assertEquals(
        'Estimate',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :orderedHistory.Id
        ]
        .historystatus__c
      );
      System.assertEquals(
        'Archive',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :newer.Id
        ]
        .historystatus__c,
        '?? Estimate ??????????? Archive ??'
      );
    }
  }

  @IsTest
  static void beforeDelete_rejectsPhysicalDelete() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Estimate Delete Account'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Estimate Delete Service',
        Account__c = account.Id
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Estimate Delete History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Estimate Delete Product'
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
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert contractProduct;

      insert new InvoiceProduct__c(
        ContractHistory__c = history.Id,
        ContractProduct__c = contractProduct.Id,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30),
        InvoiceBucketKey__c = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
          null,
          history.Id,
          Date.newInstance(2026, 6, 1),
          null
        ),
        Amount__c = 8000
      );

      Boolean thrown = false;
      try {
        delete history;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('契約履歴は物理削除できません'),
          'Core 第4.11節: 契約履歴の物理削除を拒否する'
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ],
        'Core 第4.11節: 削除されない'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :history.Id
        ],
        'Core 第4.11節: 前処理で期間明細を消さない'
      );
    }
  }

  @IsTest
  static void beforeDelete_rejectsEvenWithBypassPermission() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Bypass Delete Account'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Bypass Delete Service',
        Account__c = account.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Bypass Delete History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1
      );
      insert history;

      Boolean thrown = false;
      try {
        delete history;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('契約履歴は物理削除できません'),
          'Core 第4.11節: 緊急権限でも物理削除を通さない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeDelete_allowsWith103() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Delete 103 Account'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Delete 103 Service',
        Account__c = account.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Delete 103 History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1
      );
      insert history;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.DELETE_RECORDS => true
      };
      try {
        delete history;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        0,
        [SELECT COUNT() FROM ContractHistory__c WHERE Id = :history.Id],
        'Core 第4.11節・共通基盤 第3.6節: 103 は契約履歴の物理削除を通す'
      );
    }
  }

  @IsTest
  static void beforeDelete_allowsWith104() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Delete 104 Account'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Delete 104 Service',
        Account__c = account.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Delete 104 History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1
      );
      insert history;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        delete history;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        0,
        [SELECT COUNT() FROM ContractHistory__c WHERE Id = :history.Id],
        'Core 第4.11節・共通基盤 第3.6節: 104 は契約履歴の物理削除を通す'
      );
    }
  }

  @IsTest
  static void beforeDelete_partialBulk_rejectsAll() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Bulk Delete Mixed Lock Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Bulk Delete Mixed Lock Service'
      );

      ContractHistory__c lockedHistory = new ContractHistory__c(
        Name = 'Bulk Delete Locked History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      ContractHistory__c openHistory = new ContractHistory__c(
        Name = 'Bulk Delete Open History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 2,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      // ???E????????????E?????? Estimate ??????EOrdered ???E???????E
      lockedHistory.historystatus__c = 'Estimate';
      openHistory.historystatus__c = 'Estimate';
      insert new List<ContractHistory__c>{ lockedHistory, openHistory };

      ContractTestDataFactory.insertAllowingInvoiceStatus(
        new List<Invoice__c>{
        new Invoice__c(
          ContractService__c = service.Id,
          ContractHistory__c = lockedHistory.Id,
          InvoiceDate__c = Date.newInstance(2026, 6, 1),
          Amount__c = 10000,
          TaxAmount__c = 1000,
          InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
          SystemIntegrationDate__c = Date.today()
        ),
        new Invoice__c(
          ContractService__c = service.Id,
          ContractHistory__c = openHistory.Id,
          InvoiceDate__c = Date.newInstance(2026, 7, 1),
          Amount__c = 20000,
          TaxAmount__c = 2000
        )
        }
      );

      Database.DeleteResult[] results = Database.delete(
        new List<ContractHistory__c>{ lockedHistory, openHistory },
        false
      );

      for (Database.DeleteResult result : results) {
        System.assertEquals(
          false,
          result.isSuccess(),
          'Core 第4.11節: 一括でも契約履歴は全件拒否'
        );
        System.assert(
          result.getErrors()[0].getMessage().contains('契約履歴は物理削除できません'),
          'Core 第4.11節: 物理削除拒否メッセージ'
        );
      }

      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Id IN :new List<Id>{ lockedHistory.Id, openHistory.Id }
        ],
        'Core 第4.11節: どちらも残る'
      );
      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c IN :new List<Id>{ lockedHistory.Id, openHistory.Id }
        ],
        'Core 第4.11節: 前処理で請求を消さない'
      );
    }
  }

  @IsTest
  static void beforeDelete_allLocked_noCleanupSideEffects() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Bulk Delete All Locked Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Bulk Delete All Locked Service'
      );
      ContractHistory__c h1 = new ContractHistory__c(
        Name = 'All Locked H1',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1
      );
      ContractHistory__c h2 = new ContractHistory__c(
        Name = 'All Locked H2',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 2
      );
      insert new List<ContractHistory__c>{ h1, h2 };
      ContractTestDataFactory.insertAllowingInvoiceStatus(
        new List<Invoice__c>{
        new Invoice__c(
          ContractService__c = service.Id,
          ContractHistory__c = h1.Id,
          InvoiceDate__c = Date.newInstance(2026, 6, 1),
          Amount__c = 1000,
          TaxAmount__c = 100,
          InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
          SystemIntegrationDate__c = Date.today()
        ),
        new Invoice__c(
          ContractService__c = service.Id,
          ContractHistory__c = h2.Id,
          InvoiceDate__c = Date.newInstance(2026, 7, 1),
          Amount__c = 2000,
          TaxAmount__c = 200,
          InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
        CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_COMPLETED,
          PaymentClearingCompletedDate__c = Date.today()
        )
        }
      );

      Database.DeleteResult[] results = Database.delete(
        new List<ContractHistory__c>{ h1, h2 },
        false
      );
      for (Database.DeleteResult result : results) {
        System.assertEquals(false, result.isSuccess());
        System.assert(
          result.getErrors()[0].getMessage().contains('契約履歴は物理削除できません'),
          'Core 第4.11節: 物理削除を拒否する'
        );
      }
      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Id IN :new List<Id>{ h1.Id, h2.Id }
        ]
      );
      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c IN :new List<Id>{ h1.Id, h2.Id }
        ],
        '????E????E???E?E??????E'
      );
    }
  }

  @IsTest
  static void beforeUpdate_clearsPreviousHistoryOnArchive() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Clear Previous Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Archive Clear Previous Service'
      );

      ContractHistory__c orderedHistory = new ContractHistory__c(
        Name = 'Archive Clear Previous Ordered',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insert orderedHistory;

      ContractHistory__c estimateHistory = new ContractHistory__c(
        Name = 'Archive Clear Previous Estimate',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 10, 1),
        PreviousHistory__c = orderedHistory.Id
      );
      insert estimateHistory;

      Test.startTest();
      estimateHistory.historystatus__c = 'Archive';
      update estimateHistory;
      Test.stopTest();

      ContractHistory__c archived = [
        SELECT historystatus__c, PreviousHistory__c
        FROM ContractHistory__c
        WHERE Id = :estimateHistory.Id
      ];
      System.assertEquals('Archive', archived.historystatus__c);
      System.assertEquals(
        null,
        archived.PreviousHistory__c,
        'Archive ??E????E?????E?E'
      );
    }
  }

  @IsTest
  static void beforeUpdate_blocksOrderedToArchive() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Ordered To Archive Block'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Ordered To Archive Service'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Ordered To Archive History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      Boolean thrown = false;
      try {
        history.historystatus__c = 'Archive';
        update history;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          ContractHistoryTriggerHandler.ORDERED_TO_ARCHIVE_BLOCK_MESSAGE,
          dmlMessage(ex)
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeUpdate_blocksOrderedToArchiveEvenWithIntegrityBypass() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Ordered Archive Bypass Still Blocked'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Ordered Archive Bypass Still Blocked Service'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Ordered Archive Bypass Still Blocked History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      Boolean thrown = false;
      try {
        history.historystatus__c = 'Archive';
        update history;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          ContractHistoryTriggerHandler.ORDERED_TO_ARCHIVE_BLOCK_MESSAGE,
          dmlMessage(ex)
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeUpdate_blocksArchiveToOrderedEvenWithIntegrityBypass() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive To Ordered Bypass Still Blocked'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Archive To Ordered Bypass Still Blocked Service'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Archive To Ordered Bypass Still Blocked History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Archive',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true,
        ContractPermissionUtil.ORDER => true
      };
      Boolean thrown = false;
      try {
        history.historystatus__c = 'Ordered';
        update history;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          ContractHistoryTriggerHandler.ARCHIVE_LEAVE_BLOCK_MESSAGE,
          dmlMessage(ex)
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void afterUpdate_archivePurgesStrayBilling() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Purge Billing'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Archive Purge Service',
        Account__c = account.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Archive Purge History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Archive Purge Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c cp = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert cp;
      insert new InvoiceProduct__c(
        ContractHistory__c = history.Id,
        ContractProduct__c = cp.Id,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30),
        Amount__c = 1000
      );
      insert new Invoice__c(
        ContractHistory__c = history.Id,
        ContractService__c = service.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100
      );

      Test.startTest();
      history.historystatus__c = 'Archive';
      update history;
      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :history.Id
        ],
        'Archive ???????????E'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :history.Id
        ],
        'Archive ?????E????E'
      );
    }
  }

  @IsTest
  static void beforeUpdate_blocksOrderWithoutCustomPermission() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Order Perm Block Account'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Order Perm Block Service',
        Account__c = account.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Order Perm Block History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.ORDER => false
      };
      Boolean thrown = false;
      try {
        history.historystatus__c = 'Ordered';
        update history;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          ContractHistoryTriggerHandler.ORDER_PERMISSION_BLOCK_MESSAGE,
          dmlMessage(ex)
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);

      ContractHistory__c unchanged = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Estimate', unchanged.historystatus__c);
    }
  }

  @IsTest
  static void beforeInsert_blocksOrderedInsertWithoutCustomPermission() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Order Insert Perm Block'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Order Insert Perm Block Service',
        Account__c = account.Id
      );
      insert service;

      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.ORDER => false
      };
      Boolean thrown = false;
      try {
        insert new ContractHistory__c(
          Name = 'Order Insert Perm Block History',
          ContractService__c = service.Id,
          Type__c = 'New',
          historystatus__c = 'Ordered',
          Version__c = 1,
          CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
          CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
        );
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          ContractHistoryTriggerHandler.ORDER_PERMISSION_BLOCK_MESSAGE,
          dmlMessage(ex)
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeUpdate_blocksRevertWithoutCustomPermission() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Revert Perm Block Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Revert Perm Block Service'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Revert Perm Block History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.REVERT => false
      };
      Boolean thrown = false;
      try {
        history.historystatus__c = 'Estimate';
        update history;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          ContractHistoryTriggerHandler.REVERT_PERMISSION_BLOCK_MESSAGE,
          dmlMessage(ex)
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);

      ContractHistory__c unchanged = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Ordered', unchanged.historystatus__c);
    }
  }

  @IsTest
  static void beforeUpdate_orderPermissionNotBypassedByIntegrityGuard() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Order Bypass Still Needs 09'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Order Bypass Still Needs 09 Service',
        Account__c = account.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Order Bypass Still Needs 09 History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.ORDER => false,
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      Boolean thrown = false;
      try {
        history.historystatus__c = 'Ordered';
        update history;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          ContractHistoryTriggerHandler.ORDER_PERMISSION_BLOCK_MESSAGE,
          dmlMessage(ex)
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void cancelOrdered_blocksLaterVersionInsertAndOrder() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Terminal Cancel Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Terminal Cancel Service'
      );

      // Cancel ???????????????Cancel ??E??????E??E
      ContractHistory__c existingFutureEstimate = new ContractHistory__c(
        Name = 'Existing Future Estimate',
        ContractService__c = service.Id,
        Type__c = 'Renew',
        historystatus__c = 'Estimate',
        Version__c = 3
      );
      insert existingFutureEstimate;

      insert new ContractHistory__c(
        Name = 'Terminal Cancel',
        ContractService__c = service.Id,
        Type__c = 'Cancel',
        historystatus__c = 'Ordered',
        Version__c = 2
      );

      ContractHistory__c laterEstimate = new ContractHistory__c(
        Name = 'Later Estimate',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 4
      );
      Database.SaveResult insertResult = Database.insert(laterEstimate, false);
      System.assertEquals(false, insertResult.isSuccess());
      System.assert(
        insertResult
          .getErrors()[0]
          .getMessage()
          .contains(
            ContractHistoryTerminalService.VERSION_AFTER_CANCEL_BLOCK_MESSAGE
          ),
        insertResult.getErrors()[0].getMessage()
      );

      existingFutureEstimate.historystatus__c = 'Ordered';
      Database.SaveResult orderResult = Database.update(
        existingFutureEstimate,
        false
      );
      System.assertEquals(false, orderResult.isSuccess());
      System.assert(
        orderResult
          .getErrors()[0]
          .getMessage()
          .contains(
            ContractHistoryTerminalService.VERSION_AFTER_CANCEL_BLOCK_MESSAGE
          ),
        orderResult.getErrors()[0].getMessage()
      );
    }
  }

  private static String dmlMessage(DmlException ex) {
    if (ex == null) {
      return null;
    }
    String raw = ex.getNumDml() > 0 ? ex.getDmlMessage(0) : ex.getMessage();
    if (String.isBlank(raw)) {
      return raw;
    }
    Integer causedBy = raw.indexOf('caused by: ');
    if (causedBy >= 0) {
      raw = raw.substring(causedBy + 'caused by: '.length());
    }
    List<String> markers = new List<String>{
      'InvoiceLockException: ',
      'DmlException: '
    };
    for (String marker : markers) {
      Integer idx = raw.indexOf(marker);
      if (idx >= 0) {
        raw = raw.substring(idx + marker.length());
        break;
      }
    }
    Integer newline = raw.indexOf('\n');
    if (newline >= 0) {
      raw = raw.substring(0, newline);
    }
    return raw.trim();
  }

  @IsTest
  static void insert_rejectsManualAutoCreatedFlag() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('AutoFlag Acct');
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'AutoFlag Service'
      );
      Boolean thrown = false;
      try {
        insert new ContractHistory__c(
          Name = 'Manual Auto Flag',
          ContractService__c = service.Id,
          Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
          historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
          Version__c = 1,
          RenewEstimateAutoCreated__c = true
        );
      } catch (DmlException ex) {
        thrown = true;
        System.assert(ex.getMessage().contains('??????????????????'));
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void update_rejectsAutoCreatedFlagToggle() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('AutoFlag Upd Acct');
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'AutoFlag Upd Service'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Manual Auto Flag Upd',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1
      );
      insert history;
      history.RenewEstimateAutoCreated__c = true;
      Boolean thrown = false;
      try {
        update history;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(ex.getMessage().contains('??????????????????'));
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void insert_rejectsCreateRenewWhenSwitchOff() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.RenewOpportunityEnabled__c = false;
      update setting;
      ContractDocumentSettingService.clearCache();

      Account account = ContractTestDataFactory.insertAccount(
        'Renew Req Off Acct'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Renew Req Off Service'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Req Off Opp'
      );
      Boolean thrown = false;
      try {
        insert new ContractHistory__c(
          Name = 'Renew Req Off',
          ContractService__c = service.Id,
          Opportunity__c = opportunity.Id,
          Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
          historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
          Version__c = 1,
          CreateRenewOpportunity__c = true
        );
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          ContractHistoryTriggerHandler.RENEW_REQUEST_NOT_ALLOWED_MESSAGE,
          dmlMessage(ex),
          'Core 第11.5節: OFFではCreateRenewOpportunity=trueの保存を拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void update_rejectsCreateRenewWhenSwitchOff() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.RenewOpportunityEnabled__c = false;
      update setting;
      ContractDocumentSettingService.clearCache();

      Account account = ContractTestDataFactory.insertAccount(
        'Renew Req Off Upd Acct'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Renew Req Off Upd Service'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Req Off Upd Opp'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Renew Req Off Upd',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1
      );
      insert history;
      history.CreateRenewOpportunity__c = true;
      Boolean thrown = false;
      try {
        update history;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          ContractHistoryTriggerHandler.RENEW_REQUEST_NOT_ALLOWED_MESSAGE,
          dmlMessage(ex),
          'Core 第11.5節: OFFではCreateRenewOpportunity=trueの更新を拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void insert_rejectsCreateRenewForCancel() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Req Cancel Acct'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Renew Req Cancel Service'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Req Cancel Opp'
      );
      Boolean thrown = false;
      try {
        insert new ContractHistory__c(
          Name = 'Renew Req Cancel',
          ContractService__c = service.Id,
          Opportunity__c = opportunity.Id,
          Type__c = ContractDomainConstants.HISTORY_TYPE_CANCEL,
          historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
          Version__c = 2,
          CreateRenewOpportunity__c = true
        );
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          ContractHistoryTriggerHandler.RENEW_REQUEST_NOT_ALLOWED_MESSAGE,
          dmlMessage(ex),
          'Core 第5.2節: CancelではCreateRenewOpportunity=trueの保存を拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void termDates_helpUsesIkkaiKakinNotDigitOne() {
    List<Schema.DescribeFieldResult> fields = new List<Schema.DescribeFieldResult>{
      ContractHistory__c.CurrentTermStartDate__c.getDescribe(),
      ContractHistory__c.CurrentTermEndDate__c.getDescribe(),
      ContractHistory__c.EffectiveDate__c.getDescribe()
    };
    for (Schema.DescribeFieldResult fieldDescribe : fields) {
      String helpText = fieldDescribe.getInlineHelpText();
      System.assertNotEquals(null, helpText);
      System.assert(
        helpText.contains('一回課金'),
        'Core 第0章: 課金形態の用語は一回課金。項目=' + fieldDescribe.getName()
      );
      System.assert(
        !helpText.contains('1回課金'),
        'Core 第0章: ヘルプに 1回課金 と出さない。項目=' +
        fieldDescribe.getName()
      );
    }
  }

  @IsTest
  static void orderDate_helpIsNotJournalPostingBasis() {
    String helpText = ContractHistory__c.OrderDate__c.getDescribe()
      .getInlineHelpText();
    System.assertNotEquals(null, helpText);
    System.assert(
      helpText.contains('受注済み'),
      'Core 第11.7節・第0.1節: 受注日は社内で受注済みにした日'
    );
    System.assert(
      helpText.contains('仕訳計上日には使いません'),
      'Core 第11.7節: 受注日は仕訳計上日に使わない'
    );
    System.assert(
      !helpText.contains('仕訳を受注日で計上'),
      'Core 第11.7節: ヘルプに仕訳計上の基準と出さない'
    );
  }
}
