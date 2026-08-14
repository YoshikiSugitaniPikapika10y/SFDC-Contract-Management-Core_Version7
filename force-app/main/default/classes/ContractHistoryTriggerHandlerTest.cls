@IsTest
private class ContractHistoryTriggerHandlerTest {
  /** Ordered 挿入／遷移テスト用。請求先必須検証を通す。 */
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

      insert new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 96000,
        TaxAmount__c = 9600,
        SystemIntegrationDate__c = Date.today()
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

      insert new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 96000,
        TaxAmount__c = 9600,
        SystemIntegrationDate__c = null,
        PaymentClearingCompletedDate__c = Date.newInstance(2026, 6, 1)
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
        Amount__c = 96000,
        invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
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
      // 最新判定は Ordered の MAX(Version) のみ。confirmOrder は不要（SOQL 節約）
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

      // Type は New のまま（Change の after insert 請求生成バリデーションを避ける）
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
  static void beforeUpdate_blocksRevertToEstimateWhenNewerEstimateExists() {
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

      Boolean thrown = false;
      try {
        orderedHistory.historystatus__c = 'Estimate';
        update orderedHistory;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          EstimateRevertInvoiceService.NEWER_ESTIMATE_REVERT_MESSAGE,
          dmlMessage(ex)
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeDelete_cascadesUninvoicedInvoiceProductsOnEstimateDelete() {
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
        Amount__c = 8000,
        invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY
      );

      delete history;

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :history.Id
        ]
      );
    }
  }

  @IsTest
  static void beforeDelete_partialBulk_cleansUnlockedWhileBlockingLocked() {
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
      // 請求は手挿入するため、受注生成を避けるよう Estimate で作り後から Ordered 相当の請求だけ付ける
      lockedHistory.historystatus__c = 'Estimate';
      openHistory.historystatus__c = 'Estimate';
      insert new List<ContractHistory__c>{ lockedHistory, openHistory };

      insert new List<Invoice__c>{
        new Invoice__c(
          ContractService__c = service.Id,
          ContractHistory__c = lockedHistory.Id,
          InvoiceDate__c = Date.newInstance(2026, 6, 1),
          Amount__c = 10000,
          TaxAmount__c = 1000,
          SystemIntegrationDate__c = Date.today()
        ),
        new Invoice__c(
          ContractService__c = service.Id,
          ContractHistory__c = openHistory.Id,
          InvoiceDate__c = Date.newInstance(2026, 7, 1),
          Amount__c = 20000,
          TaxAmount__c = 2000
        )
      };

      Database.DeleteResult[] results = Database.delete(
        new List<ContractHistory__c>{ lockedHistory, openHistory },
        false
      );

      Boolean lockedFailed = false;
      Boolean openSucceeded = false;
      String lockedMessage = null;
      for (Database.DeleteResult result : results) {
        if (result.getId() == lockedHistory.Id) {
          lockedFailed = !result.isSuccess();
          if (!result.isSuccess() && !result.getErrors().isEmpty()) {
            lockedMessage = result.getErrors()[0].getMessage();
          }
        }
        if (result.getId() == openHistory.Id) {
          openSucceeded = result.isSuccess();
        }
      }
      System.assertEquals(true, lockedFailed, 'ロック履歴は削除不可');
      System.assertEquals(
        InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
        lockedMessage
      );
      System.assertEquals(true, openSucceeded, '未ロック履歴は削除可');

      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Id = :lockedHistory.Id
        ],
        'ロック履歴は残る'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Id = :openHistory.Id
        ],
        '未ロック履歴は消える'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :lockedHistory.Id
        ],
        'ロック側請求は残る'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE
            ContractHistory__c = :openHistory.Id
            OR (ContractHistory__c = NULL
            AND ContractService__c = :service.Id
            AND Amount__c = 20000)
        ],
        '未ロック側請求は孤児にせず削除する'
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
      insert new List<Invoice__c>{
        new Invoice__c(
          ContractService__c = service.Id,
          ContractHistory__c = h1.Id,
          InvoiceDate__c = Date.newInstance(2026, 6, 1),
          Amount__c = 1000,
          TaxAmount__c = 100,
          SystemIntegrationDate__c = Date.today()
        ),
        new Invoice__c(
          ContractService__c = service.Id,
          ContractHistory__c = h2.Id,
          InvoiceDate__c = Date.newInstance(2026, 7, 1),
          Amount__c = 2000,
          TaxAmount__c = 200,
          PaymentClearingCompletedDate__c = Date.today()
        )
      };

      Database.DeleteResult[] results = Database.delete(
        new List<ContractHistory__c>{ h1, h2 },
        false
      );
      for (Database.DeleteResult result : results) {
        System.assertEquals(false, result.isSuccess());
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          result.getErrors()[0].getMessage()
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
        '全件ロック時は請求の掃除もしない'
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
        ContractPermissionUtil.BYPASS_INTEGRITY => true
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
        ContractPermissionUtil.BYPASS_INTEGRITY => true,
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
        'Archive 後に期間明細は残らない'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :history.Id
        ],
        'Archive 後に請求は残らない'
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
        ContractPermissionUtil.BYPASS_INTEGRITY => true
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
}
