@IsTest
private class ContractOrderValidationServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void assertReadyForOrder_newWithBillingAndProducts_canOrder() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Order Ready New Happy Account'
      );
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
        Name = 'Order Ready New Happy Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Order Ready New Happy History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart,
        ApplicationDate__c = termStart
      );
      insert history;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Order Ready New Happy Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Amount__c = 120000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      Test.startTest();
      ContractOrderValidationService.assertReadyForOrder(history);
      history.historystatus__c = 'Ordered';
      update history;
      Test.stopTest();

      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ]
        .historystatus__c,
        '請求先・商品・金額が揃った新規見積は受注できる'
      );
    }
  }

  @IsTest
  static void assertReadyForOrder_blocksWithoutBillingAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Order Ready No BA Account'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Order Ready No BA Service',
        Account__c = account.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Order Ready No BA History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      Boolean thrown = false;
      try {
        ContractOrderValidationService.assertReadyForOrder(history);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOrderValidationService.BILLING_ACCOUNT_MISSING_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void assertReadyForOrder_blocksWithoutProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Order Ready No Product Account'
      );
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
        Name = 'Order Ready No Product Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Order Ready No Product History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      Boolean thrown = false;
      try {
        ContractOrderValidationService.assertReadyForOrder(history);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOrderValidationService.PRODUCTS_MISSING_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void assertReadyForOrder_blocksWhenAmountMissing() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Order Ready No Amount Account'
      );
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
        Name = 'Order Ready No Amount Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Order Ready No Amount History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Order Ready No Amount Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = null,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      Boolean thrown = false;
      try {
        ContractOrderValidationService.assertReadyForOrder(history);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOrderValidationService.AMOUNT_MISSING_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeUpdate_directOrderWithoutBillingAccount_isBlocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Direct Order No BA Account'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Direct Order No BA Service',
        Account__c = account.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Direct Order No BA History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Direct Order No BA Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      Boolean thrown = false;
      try {
        history.historystatus__c = 'Ordered';
        update history;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(
              ContractOrderValidationService.BILLING_ACCOUNT_MISSING_MESSAGE
            ),
          ex.getMessage()
        );
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
  static void assertReadyForOrder_blocksInvoiceSettingOnlyChange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Order Ready Setting Only Account'
      );
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
        Name = 'Order Ready Setting Only Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      ContractHistory__c previous = new ContractHistory__c(
        Name = 'Order Ready Setting Only Previous',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert previous;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Order Ready Setting Only Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c previousProduct = new ContractProduct__c(
        ContractHistory__c = previous.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert previousProduct;

      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Order Ready Setting Only Change',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        PreviousHistory__c = previous.Id,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insert changeHistory;
      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 1000,
          Amount__c = 12000,
          StartDate__c = Date.newInstance(2026, 6, 1),
          Enddate__c = Date.newInstance(2027, 5, 31),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Original',
          PreviousContractProduct__c = previousProduct.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 1000,
          Amount__c = 12000,
          StartDate__c = Date.newInstance(2026, 6, 1),
          Enddate__c = Date.newInstance(2027, 5, 31),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = previousProduct.Id
        )
      };

      Boolean thrown = false;
      try {
        ContractOrderValidationService.assertReadyForOrder(changeHistory);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOrderValidationService.INVOICE_SETTING_ONLY_CHANGE_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);

      // 実 DML でも受注できず、見積のまま・請求は作られない
      changeHistory.historystatus__c = 'Ordered';
      Boolean dmlBlocked = false;
      try {
        update changeHistory;
      } catch (DmlException ex) {
        dmlBlocked = true;
        System.assert(
          ex.getDmlMessage(0)
            .contains(
              ContractOrderValidationService.INVOICE_SETTING_ONLY_CHANGE_MESSAGE
            ),
          ex.getDmlMessage(0)
        );
      }
      System.assertEquals(true, dmlBlocked);
      System.assertEquals(
        'Estimate',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :changeHistory.Id
        ]
        .historystatus__c
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :changeHistory.Id
        ]
      );
    }
  }

  @IsTest
  static void assertReadyForOrder_blocksWhenSameVersionAlreadyOrdered() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Order Ready Dup Version Account'
      );
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
        Name = 'Order Ready Dup Version Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      ContractHistory__c ordered = new ContractHistory__c(
        Name = 'Order Ready Dup Version Winner',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert ordered;
      ContractHistory__c rival = new ContractHistory__c(
        Name = 'Order Ready Dup Version Rival',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert rival;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Order Ready Dup Version Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = rival.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      Boolean thrown = false;
      try {
        ContractOrderValidationService.assertReadyForOrder(rival);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOrderValidationService.DUPLICATE_ORDERED_VERSION_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeUpdate_bulkOrderSameVersion_bothBlocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Bulk Order Dup Version Account'
      );
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
        Name = 'Bulk Order Dup Version Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      ContractHistory__c estA = new ContractHistory__c(
        Name = 'Bulk Order Dup Version A',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      ContractHistory__c estB = new ContractHistory__c(
        Name = 'Bulk Order Dup Version B',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert new List<ContractHistory__c>{ estA, estB };
      Product2 product = ContractTestDataFactory.buildProduct(
        'Bulk Order Dup Version Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = estA.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 1000,
          Amount__c = 12000,
          StartDate__c = Date.newInstance(2026, 6, 1),
          Enddate__c = Date.newInstance(2027, 5, 31),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'New'
        ),
        new ContractProduct__c(
          ContractHistory__c = estB.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 1000,
          Amount__c = 12000,
          StartDate__c = Date.newInstance(2026, 6, 1),
          Enddate__c = Date.newInstance(2027, 5, 31),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'New'
        )
      };

      estA.historystatus__c = 'Ordered';
      estB.historystatus__c = 'Ordered';
      Boolean thrown = false;
      String message = null;
      try {
        update new List<ContractHistory__c>{ estA, estB };
      } catch (DmlException ex) {
        thrown = true;
        message = ex.getNumDml() > 0 ? ex.getDmlMessage(0) : ex.getMessage();
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        ContractOrderValidationService.DUPLICATE_ORDERED_VERSION_MESSAGE,
        message
      );

      Integer orderedCount = [
        SELECT COUNT()
        FROM ContractHistory__c
        WHERE ContractService__c = :service.Id AND historystatus__c = 'Ordered'
      ];
      System.assertEquals(0, orderedCount);
    }
  }

  @IsTest
  static void assertReadyForOrder_allowsDifferentVersionSameService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Order Ready Diff Version Account'
      );
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
        Name = 'Order Ready Diff Version Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      insert new ContractHistory__c(
        Name = 'Order Ready Diff Version Winner',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      ContractHistory__c next = new ContractHistory__c(
        Name = 'Order Ready Diff Version Next',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert next;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Order Ready Diff Version Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = next.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      Test.startTest();
      ContractOrderValidationService.assertReadyForOrder(next);
      next.historystatus__c = 'Ordered';
      update next;
      Test.stopTest();

      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE
            ContractService__c = :service.Id
            AND historystatus__c = 'Ordered'
        ],
        'Version が違えば同一サービスでも複数 Ordered 可'
      );
    }
  }

  @IsTest
  static void cancelAllowsOrderWithoutProductsWhenBillingReady() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Cancel Order Ready Account'
      );
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
        Name = 'Cancel Order Ready Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Cancel Order Ready History',
        ContractService__c = service.Id,
        Type__c = 'Cancel',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insert history;

      Test.startTest();
      ContractOrderValidationService.assertReadyForOrder(history);
      history.historystatus__c = 'Ordered';
      update history;
      Test.stopTest();

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
}
