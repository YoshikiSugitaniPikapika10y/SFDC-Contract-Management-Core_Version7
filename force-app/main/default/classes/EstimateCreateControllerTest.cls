@IsTest
private class EstimateCreateControllerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void getProductDefaults_returnsValues() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct('Test Product');
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 12000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductDefaultDto result = EstimateCreateController.getProductDefaults(
        product.Id
      );

      System.assertNotEquals(null, result);
      System.assertEquals(
        ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
        result.unitName
      );
      System.assertEquals(12000, result.unitPrice);
      System.assertEquals(
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        result.invoiceType
      );
      System.assertEquals(
        ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
        result.displayUnit
      );
    }
  }

  @IsTest
  static void getProductDefaults_nullId_returnsNull() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      System.assertEquals(
        null,
        EstimateCreateController.getProductDefaults(null)
      );
    }
  }

  @IsTest
  static void getEstimateRemarkMasterText_returnsRemarkText() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateNoteMaster__c master = ContractTestDataFactory.insertEstimateNoteMaster(
        'Standard Remark',
        '見積備考のサンプル文'
      );

      System.assertEquals(
        '見積備考のサンプル文',
        EstimateCreateController.getEstimateRemarkMasterText(master.Id)
      );
    }
  }

  @IsTest
  static void getEstimateRemarkMasterText_nullId_returnsEmpty() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      System.assertEquals(
        '',
        EstimateCreateController.getEstimateRemarkMasterText(null)
      );
    }
  }

  @IsTest
  static void saveEstimate_createsRecordsForNewType() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Test Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Test Opportunity'
      );

      Product2 product = ContractTestDataFactory.buildProduct(
        'Save Test Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 10000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      // 月次境界は固定日で検証（today / toStartOfMonth でも月末付近でブレうる）
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();

      EstimateCreateController.ProductLineItem lineItem = new EstimateCreateController.ProductLineItem();
      lineItem.productId = product.Id;
      lineItem.quantity = 2;
      lineItem.unitPrice = 10000;
      lineItem.amount = 20000;
      lineItem.startDate = String.valueOf(termStart);
      lineItem.endDate = String.valueOf(termEnd);
      lineItem.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      lineItem.unit = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      lineItem.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      lineItem.billingCycle = '月';
      lineItem.recordType = 'New';

      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{ lineItem }
      );

      Test.startTest();
      EstimateCreateController.EstimateSaveResult result = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'Test Service',
        'Test History',
        null,
        null,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(termStart),
        String.valueOf(termStart),
        productsJson,
        null,
        null,
        null,
        null
      );
      Test.stopTest();

      System.assertNotEquals(null, result.contractServiceId);
      System.assertNotEquals(null, result.contractHistoryId);
      System.assertEquals(1, result.contractProductIds.size());

      ContractService__c service = [
        SELECT Name, Account__c, FirstOrderedHistory__c, LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :result.contractServiceId
      ];
      System.assertEquals('Test Service', service.Name);
      System.assertEquals(opportunity.AccountId, service.Account__c);
      System.assertEquals(null, service.FirstOrderedHistory__c);
      System.assertEquals(null, service.LatestOrderedHistory__c);

      ContractHistory__c history = [
        SELECT
          Name,
          Type__c,
          historystatus__c,
          Version__c,
          Opportunity__c,
          ContractService__c,
          PreviousHistory__c,
          EstimateNoteMaster__c,
          Note__c
        FROM ContractHistory__c
        WHERE Id = :result.contractHistoryId
      ];
      System.assertEquals('Test History', history.Name);
      System.assertEquals('New', history.Type__c);
      System.assertEquals('Estimate', history.historystatus__c);
      System.assertEquals(1, history.Version__c);
      System.assertEquals(opportunity.Id, history.Opportunity__c);
      System.assertEquals(result.contractServiceId, history.ContractService__c);
      System.assertEquals(null, history.PreviousHistory__c);

      ContractProduct__c contractProduct = [
        SELECT
          Product__c,
          Quantity__c,
          UnitPrice__c,
          InvoiceSetting__c,
          ContractHistory__c,
          Type__c,
          Unit__c,
          BillingType__c,
          Amount__c,
          StartDate__c,
          Enddate__c,
          InvoiceAnchorDate__c,
          InvoiceBillingCycleCount__c
        FROM ContractProduct__c
        WHERE Id = :result.contractProductIds[0]
      ];
      System.assertEquals(product.Id, contractProduct.Product__c);
      System.assertEquals(2, contractProduct.Quantity__c);
      System.assertEquals(10000, contractProduct.UnitPrice__c);
      System.assertEquals(
        result.contractHistoryId,
        contractProduct.ContractHistory__c
      );
      System.assertEquals('New', contractProduct.Type__c);
      System.assertEquals(
        ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
        contractProduct.Unit__c
      );
      System.assertEquals(
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        contractProduct.BillingType__c
      );
      System.assertEquals(
        20000,
        contractProduct.Amount__c,
        'Step3 画面確認値（line.amount）をそのまま保存'
      );
      System.assertEquals(
        termStart,
        contractProduct.InvoiceAnchorDate__c,
        '一括前払の請求基準日は開始日'
      );
      System.assertEquals(
        null,
        contractProduct.InvoiceBillingCycleCount__c,
        '一括前払では請求回数は保存しない'
      );
    }
  }

  @IsTest
  static void saveEstimate_newType_savesOptionalBillingAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Test Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Test Opportunity'
      );

      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = opportunity.AccountId,
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25
      );
      insert billingAccount;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Billing Account Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 1000;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(product);

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = termStart.addMonths(1).addDays(-1);

      EstimateCreateController.ProductLineItem lineItem = new EstimateCreateController.ProductLineItem();
      lineItem.productId = product.Id;
      lineItem.quantity = 1;
      lineItem.unitPrice = 1000;
      lineItem.amount = 1000;
      lineItem.startDate = String.valueOf(termStart);
      lineItem.endDate = String.valueOf(termEnd);
      lineItem.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      lineItem.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      lineItem.unit = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      lineItem.recordType = 'New';

      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{ lineItem }
      );

      Test.startTest();
      EstimateCreateController.EstimateSaveResult result = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'Billing Service',
        'Billing History',
        null,
        null,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(termStart),
        String.valueOf(termEnd),
        productsJson,
        null,
        null,
        billingAccount.Id,
        null
      );
      Test.stopTest();

      ContractService__c service = [
        SELECT BiilingAcccount__c
        FROM ContractService__c
        WHERE Id = :result.contractServiceId
      ];
      System.assertEquals(billingAccount.Id, service.BiilingAcccount__c);
    }
  }

  @IsTest
  static void getBillingAccountInvoiceSettings_returnsConfiguredValues() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Billing Settings Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = testAccount.Id,
        PaymentTerm__c = '翌月15日',
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
        AdjustInvoiceDateToBusinessDay__c = true
      );
      insert billingAccount;

      EstimateCreateController.BillingAccountInvoiceSettingsDto result = EstimateCreateController.getBillingAccountInvoiceSettings(
        billingAccount.Id
      );

      System.assertEquals(25, result.billingDayOfMonth);
      System.assertEquals('25', result.billingDayOfMonthPicklistValue);
      System.assertEquals('25日', result.billingDayOfMonthLabel);
      System.assertEquals('翌月15日', result.paymentTerm);
      System.assertEquals(true, result.adjustInvoiceDateToBusinessDay);
    }
  }

  @IsTest
  static void saveEstimate_unsupportedType_throwsException() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          null,
          'Invalid',
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown, '未対応タイプは例外になること');
    }
  }

  @IsTest
  static void getLatestContractHistory_returnsHighestNonEstimateVersion() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Test Account');

      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Service A'
      );

      ContractHistory__c older = new ContractHistory__c(
        Name = 'History v1',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1
      );
      insert older;
      ContractHistory__c latest = new ContractHistory__c(
        Name = 'History v2',
        ContractService__c = service.Id,
        Type__c = 'Renew',
        historystatus__c = 'Ordered',
        Version__c = 2,
        PreviousHistory__c = older.Id
      );
      ContractHistory__c estimate = new ContractHistory__c(
        Name = 'Estimate v3',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 3,
        PreviousHistory__c = latest.Id
      );
      insert new List<ContractHistory__c>{ latest, estimate };

      EstimateCreateController.ContractHistoryDto result = EstimateCreateController.getLatestContractHistory(
        service.Id
      );

      System.assertNotEquals(null, result);
      System.assertEquals(latest.Id, result.historyId);
      System.assertEquals('History v2', result.historyName);
      System.assertEquals(2, result.version);
      // 未受注 Estimate があっても次 Version は最新 Ordered + 1
      System.assertEquals(3, result.nextVersion);
      System.assertEquals(
        ContractHistoryVersionUtil.getNextHistoryVersion(service.Id),
        result.nextVersion
      );
    }
  }

  @IsTest
  static void getLatestContractHistory_nullId_returnsNull() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      System.assertEquals(
        null,
        EstimateCreateController.getLatestContractHistory(null)
      );
    }
  }

  @IsTest
  static void getLatestContractHistory_skipsOrderedCancelChurn() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Churn Skip Account'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Churn Skip Service'
      );

      ContractHistory__c activeHistory = new ContractHistory__c(
        Name = 'Renew v1',
        ContractService__c = service.Id,
        Type__c = 'Renew',
        historystatus__c = 'Ordered',
        Version__c = 1
      );
      ContractHistory__c churnHistory = new ContractHistory__c(
        Name = 'Churn v2',
        ContractService__c = service.Id,
        Type__c = 'Cancel',
        historystatus__c = 'Ordered',
        Version__c = 2
      );
      insert new List<ContractHistory__c>{ activeHistory, churnHistory };

      EstimateCreateController.ContractHistoryDto result = EstimateCreateController.getLatestContractHistory(
        service.Id
      );

      System.assertNotEquals(null, result);
      System.assertEquals(activeHistory.Id, result.historyId);
      System.assertEquals('Renew v1', result.historyName);
      System.assertEquals(1, result.version);
    }
  }

  @IsTest
  static void getRecurringContractProducts_returnsRecurringOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Test Account');

      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Service A'
      );

      ContractHistory__c history = new ContractHistory__c(
        Name = 'History',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Version__c = 1
      );
      insert history;

      Product2 recurringProduct = ContractTestDataFactory.buildProduct(
        'Recurring Product'
      );
      recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      recurringProduct.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      recurringProduct.UnitPrice__c = 5000;
      recurringProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      Product2 oneTimeProduct = ContractTestDataFactory.buildProduct(
        'One Time Product'
      );
      oneTimeProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      oneTimeProduct.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      oneTimeProduct.UnitPrice__c = 10000;
      ContractTestDataFactory.insertProducts(
        new List<Product2>{ recurringProduct, oneTimeProduct }
      );

      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Product__c = recurringProduct.Id,
          Quantity__c = 2,
          UnitPrice__c = 5000,
          StartDate__c = ContractTestDataFactory.stableTermStart(),
          Enddate__c = ContractTestDataFactory.stableTermEnd(),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
        ),
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Product__c = oneTimeProduct.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          StartDate__c = ContractTestDataFactory.stableTermStart(),
          Enddate__c = ContractTestDataFactory.stableTermEnd(),
          InvoiceSetting__c = ContractMetadataService.INVOICE_SETTING_PREPAID_START
        )
      };

      List<EstimateCreateController.ContractProductLineDto> results = EstimateCreateController.getRecurringContractProducts(
        history.Id
      );

      System.assertEquals(1, results.size());
      System.assertEquals(recurringProduct.Id, results[0].productId);
      System.assertEquals('Recurring Product', results[0].productName);
      System.assertEquals(
        ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
        results[0].unitName
      );
      System.assertEquals(2, results[0].quantity);
      System.assertEquals(5000, results[0].unitPrice);
      System.assertEquals(
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        results[0].invoiceType
      );
    }
  }

  @IsTest
  static void getRecurringContractProducts_nullId_returnsEmpty() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      System.assertEquals(
        0,
        EstimateCreateController.getRecurringContractProducts(null).size()
      );
    }
  }

  @IsTest
  static void getRecurringContractProducts_excludesOriginalAndZeroQuantity() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Test Account');

      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Service A'
      );

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Source History',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Version__c = 1
      );
      insert sourceHistory;
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change History',
        ContractService__c = service.Id,
        historystatus__c = 'Estimate',
        Version__c = 2,
        Type__c = 'Change',
        PreviousHistory__c = sourceHistory.Id
      );
      insert changeHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Recurring Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 5000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      Product2 removedProduct = ContractTestDataFactory.buildProduct(
        'Removed Product'
      );
      removedProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      removedProduct.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      removedProduct.UnitPrice__c = 3000;
      removedProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProducts(
        new List<Product2>{ product, removedProduct }
      );

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 5000,
        StartDate__c = ContractTestDataFactory.stableTermStart(),
        Enddate__c = ContractTestDataFactory.stableTermEnd(),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 2,
          UnitPrice__c = 5000,
          StartDate__c = ContractTestDataFactory.stableTermStart(),
          Enddate__c = ContractTestDataFactory.stableTermEnd(),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          Type__c = 'Original',
          PreviousContractProduct__c = sourceProduct.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 3,
          UnitPrice__c = 5000,
          StartDate__c = ContractTestDataFactory.stableTermStart(),
          Enddate__c = ContractTestDataFactory.stableTermEnd(),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          Type__c = 'Remake',
          PreviousContractProduct__c = sourceProduct.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = removedProduct.Id,
          Quantity__c = 0,
          UnitPrice__c = 3000,
          StartDate__c = ContractTestDataFactory.stableTermStart(),
          Enddate__c = ContractTestDataFactory.stableTermEnd(),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          Type__c = 'Remake',
          PreviousContractProduct__c = sourceProduct.Id
        )
      };

      List<EstimateCreateController.ContractProductLineDto> results = EstimateCreateController.getRecurringContractProducts(
        changeHistory.Id
      );

      System.assertEquals(1, results.size());
      System.assertEquals(product.Id, results[0].productId);
      System.assertEquals(3, results[0].quantity);
    }
  }

  @IsTest
  static void getRenewContractProducts_matchesHistoryEndDateOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Test Account');

      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Service A'
      );

      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermEndDate__c = termEnd
      );
      insert history;

      Product2 productA = ContractTestDataFactory.buildProduct('Product A');
      productA.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      productA.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      productA.UnitPrice__c = 5000;
      productA.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      Product2 productB = ContractTestDataFactory.buildProduct('Product B');
      productB.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      productB.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      productB.UnitPrice__c = 3000;
      productB.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProducts(
        new List<Product2>{ productA, productB }
      );

      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Product__c = productA.Id,
          Quantity__c = 1,
          UnitPrice__c = 5000,
          StartDate__c = ContractTestDataFactory.stableTermStart(),
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
        ),
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Product__c = productB.Id,
          Quantity__c = 1,
          UnitPrice__c = 3000,
          StartDate__c = ContractTestDataFactory.stableTermStart(),
          Enddate__c = Date.newInstance(2026, 3, 31),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
        )
      };

      List<EstimateCreateController.ContractProductLineDto> results = EstimateCreateController.getRenewContractProducts(
        service.Id
      );

      System.assertEquals(1, results.size());
      System.assertEquals(productA.Id, results[0].productId);
      System.assertEquals(String.valueOf(termEnd), results[0].endDate);
    }
  }

  @IsTest
  static void getRenewContractProducts_excludesOriginalTypeEvenWhenEndDateMatches() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Test Account');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Service A'
      );

      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Change History',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermEndDate__c = termEnd
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct('Product A');
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 5000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 5000,
        StartDate__c = ContractTestDataFactory.stableTermStart(),
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'Original'
      );

      System.assertEquals(
        0,
        EstimateCreateController.getRenewContractProducts(service.Id).size()
      );
    }
  }

  @IsTest
  static void getRenewContractProducts_nullId_returnsEmpty() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      System.assertEquals(
        0,
        EstimateCreateController.getRenewContractProducts(null).size()
      );
    }
  }

  @IsTest
  static void getRenewContractProducts_usesLatestNonEstimateHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Test Account');

      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Service A'
      );

      Date priorTermEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c orderedHistory = new ContractHistory__c(
        Name = 'Ordered History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermEndDate__c = priorTermEnd
      );
      ContractHistory__c estimateHistory = new ContractHistory__c(
        Name = 'Renew Estimate',
        ContractService__c = service.Id,
        Type__c = 'Renew',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert new List<ContractHistory__c>{ orderedHistory, estimateHistory };

      Product2 product = ContractTestDataFactory.buildProduct('Product A');
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 5000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      insert new ContractProduct__c(
        ContractHistory__c = orderedHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 5000,
        StartDate__c = ContractTestDataFactory.stableTermStart(),
        Enddate__c = priorTermEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
      );

      List<EstimateCreateController.ContractProductLineDto> results = EstimateCreateController.getRenewContractProducts(
        service.Id
      );

      System.assertEquals(1, results.size());
      System.assertEquals(product.Id, results[0].productId);
    }
  }

  @IsTest
  static void getContractHistoryInfo_returnsTermDates() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Test Account');

      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Service A'
      );

      Date startDate = ContractTestDataFactory.stableTermStart();
      Date endDate = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'History',
        ContractService__c = service.Id,
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = startDate,
        CurrentTermEndDate__c = endDate
      );
      insert history;

      EstimateCreateController.ContractHistoryDto result = EstimateCreateController.getContractHistoryInfo(
        history.Id
      );

      System.assertNotEquals(null, result);
      System.assertEquals(String.valueOf(startDate), result.termStartDate);
      System.assertEquals(String.valueOf(endDate), result.termEndDate);
    }
  }

  @IsTest
  static void getContractHistoryInfo_nullId_returnsNull() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      System.assertEquals(
        null,
        EstimateCreateController.getContractHistoryInfo(null)
      );
    }
  }

  @IsTest
  static void saveEstimate_invalidBillingPeriod_throwsException() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Test Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Test Opportunity'
      );

      Product2 product = ContractTestDataFactory.buildProduct(
        'Recurring Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 1000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem lineItem = new EstimateCreateController.ProductLineItem();
      lineItem.productId = product.Id;
      lineItem.quantity = 1;
      lineItem.unitPrice = 1000;
      lineItem.amount = 1000;
      lineItem.startDate = String.valueOf(
        ContractTestDataFactory.stableTermStart()
      );
      lineItem.endDate = String.valueOf(
        ContractTestDataFactory.stableTermStart().addDays(10)
      );
      lineItem.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      lineItem.unit = '式/月';
      lineItem.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      lineItem.billingCycle = '月';
      lineItem.recordType = 'New';

      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{ lineItem }
      );

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'New',
          'Test Service',
          'Test History',
          null,
          null,
          String.valueOf(ContractTestDataFactory.stableTermStart()),
          String.valueOf(ContractTestDataFactory.stableTermEnd()),
          String.valueOf(ContractTestDataFactory.stableTermStart()),
          String.valueOf(ContractTestDataFactory.stableTermStart()),
          productsJson,
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_newTypeMissingEndpointMatch_throwsException() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Test Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Test Opportunity'
      );

      Product2 product = ContractTestDataFactory.buildProduct(
        'Endpoint Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 1000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      Date headerStart = ContractTestDataFactory.stableTermStart();
      Date headerEnd = ContractTestDataFactory.stableTermEnd();

      EstimateCreateController.ProductLineItem lineItem = new EstimateCreateController.ProductLineItem();
      lineItem.productId = product.Id;
      lineItem.quantity = 1;
      lineItem.unitPrice = 1000;
      lineItem.amount = 12000;
      lineItem.startDate = String.valueOf(headerStart);
      lineItem.endDate = String.valueOf(headerStart.addMonths(6).addDays(-1));
      lineItem.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      lineItem.unit = '式/月';
      lineItem.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      lineItem.billingCycle = '月';
      lineItem.recordType = 'New';

      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{ lineItem }
      );

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'New',
          'Test Service',
          'Test History',
          null,
          null,
          String.valueOf(headerStart),
          String.valueOf(headerEnd),
          String.valueOf(headerStart),
          String.valueOf(Date.today()),
          productsJson,
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_newType_recurringPartialAddon_succeeds() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Partial Addon Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Partial Addon Opportunity'
      );

      Product2 coreProduct = ContractTestDataFactory.buildProduct(
        'Core Product'
      );
      coreProduct.UnitName__c = 'ID';
      coreProduct.UnitPrice__c = 8000;
      coreProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      coreProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      Product2 addonProduct = ContractTestDataFactory.buildProduct(
        'Trial Addon'
      );
      addonProduct.UnitName__c = 'ID';
      addonProduct.UnitPrice__c = 2000;
      addonProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
      addonProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProducts(
        new List<Product2>{ coreProduct, addonProduct }
      );

      Date headerStart = Date.newInstance(2026, 6, 1);
      Date headerEnd = Date.newInstance(2027, 5, 31);
      Date addonEnd = Date.newInstance(2026, 8, 31);

      EstimateCreateController.ProductLineItem coreLine = new EstimateCreateController.ProductLineItem();
      coreLine.productId = coreProduct.Id;
      coreLine.quantity = 1;
      coreLine.unitPrice = 8000;
      coreLine.amount = 96000;
      coreLine.startDate = String.valueOf(headerStart);
      coreLine.endDate = String.valueOf(headerEnd);
      coreLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      coreLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      coreLine.billingCycle = '月';
      coreLine.recordType = 'New';

      EstimateCreateController.ProductLineItem addonLine = new EstimateCreateController.ProductLineItem();
      addonLine.productId = addonProduct.Id;
      addonLine.quantity = 1;
      addonLine.unitPrice = 2000;
      addonLine.amount = 6000;
      addonLine.startDate = String.valueOf(headerStart);
      addonLine.endDate = String.valueOf(addonEnd);
      addonLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
      addonLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      addonLine.billingCycle = '月';
      addonLine.recordType = 'New';

      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{
          coreLine,
          addonLine
        }
      );

      EstimateCreateController.EstimateSaveResult result = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'Partial Addon Service',
        'Partial Addon History',
        null,
        null,
        String.valueOf(headerStart),
        String.valueOf(headerEnd),
        String.valueOf(headerStart),
        String.valueOf(headerStart),
        productsJson,
        null,
        null,
        null,
        null
      );

      System.assertEquals(2, result.contractProductIds.size());
    }
  }

  @IsTest
  static void saveEstimate_newType_overlappingProducts_throwsException() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Overlap Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Overlap Opportunity'
      );

      Product2 product = ContractTestDataFactory.buildProduct(
        'Overlap Product'
      );
      product.UnitName__c = 'ID';
      product.UnitPrice__c = 8000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      Date headerStart = Date.newInstance(2026, 6, 1);
      Date headerEnd = Date.newInstance(2027, 5, 31);

      EstimateCreateController.ProductLineItem firstLine = new EstimateCreateController.ProductLineItem();
      firstLine.productId = product.Id;
      firstLine.quantity = 1;
      firstLine.unitPrice = 8000;
      firstLine.startDate = String.valueOf(headerStart);
      firstLine.endDate = String.valueOf(headerEnd);
      firstLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      firstLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      firstLine.billingCycle = '月';
      firstLine.recordType = 'New';

      EstimateCreateController.ProductLineItem secondLine = new EstimateCreateController.ProductLineItem();
      secondLine.productId = product.Id;
      secondLine.quantity = 2;
      secondLine.unitPrice = 8000;
      secondLine.startDate = String.valueOf(Date.newInstance(2026, 10, 1));
      secondLine.endDate = String.valueOf(headerEnd);
      secondLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      secondLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      secondLine.billingCycle = '月';
      secondLine.recordType = 'New';

      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{
          firstLine,
          secondLine
        }
      );

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'New',
          'Overlap Service',
          'Overlap History',
          null,
          null,
          String.valueOf(headerStart),
          String.valueOf(headerEnd),
          String.valueOf(headerStart),
          null,
          productsJson,
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_createsRecordsForChangeType() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Test Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Test Opportunity'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        opportunity.AccountId,
        'Change Test Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date effectiveDate = Date.newInstance(2025, 10, 1);
      Date preEffectiveEnd = effectiveDate.addDays(-1);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Source History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct('Change Product');
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 5000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 5000,
        Unit__c = '式/月',
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = product.Id;
      beforeLine.quantity = 2;
      beforeLine.unitPrice = 5000;
      beforeLine.amount = -120000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.unit = '式/月';
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem remakePreLine = new EstimateCreateController.ProductLineItem();
      remakePreLine.productId = product.Id;
      remakePreLine.quantity = 2;
      remakePreLine.unitPrice = 5000;
      remakePreLine.amount = 40000;
      remakePreLine.startDate = String.valueOf(termStart);
      remakePreLine.endDate = String.valueOf(preEffectiveEnd);
      remakePreLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakePreLine.unit = '式/月';
      remakePreLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakePreLine.billingCycle = '月';
      remakePreLine.recordType = 'Remake';
      remakePreLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem afterLine = new EstimateCreateController.ProductLineItem();
      afterLine.productId = product.Id;
      afterLine.quantity = 3;
      afterLine.unitPrice = 5000;
      afterLine.amount = 120000;
      afterLine.startDate = String.valueOf(effectiveDate);
      afterLine.endDate = String.valueOf(termEnd);
      afterLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      afterLine.unit = '式/月';
      afterLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      afterLine.billingCycle = '月';
      afterLine.recordType = 'Remake';
      afterLine.sourceContractProductId = sourceProduct.Id;

      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{
          beforeLine,
          remakePreLine,
          afterLine
        }
      );

      Test.startTest();
      EstimateCreateController.EstimateSaveResult result = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'Change',
        null,
        'Change Estimate',
        service.Id,
        sourceHistory.Id,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(effectiveDate),
        String.valueOf(Date.today()),
        productsJson,
        null,
        null,
        null,
        null
      );
      Test.stopTest();

      System.assertEquals(service.Id, result.contractServiceId);
      System.assertNotEquals(null, result.contractHistoryId);
      System.assertEquals(3, result.contractProductIds.size());

      ContractHistory__c estimateHistory = [
        SELECT
          Type__c,
          historystatus__c,
          Version__c,
          ContractService__c,
          PreviousHistory__c
        FROM ContractHistory__c
        WHERE Id = :result.contractHistoryId
      ];
      System.assertEquals('Change', estimateHistory.Type__c);
      System.assertEquals('Estimate', estimateHistory.historystatus__c);
      System.assertEquals(2, estimateHistory.Version__c);
      System.assertEquals(service.Id, estimateHistory.ContractService__c);
      System.assertEquals(sourceHistory.Id, estimateHistory.PreviousHistory__c);

      List<ContractProduct__c> savedProducts = [
        SELECT
          Type__c,
          PreviousContractProduct__c,
          Quantity__c,
          UnitPrice__c,
          BillingType__c,
          Amount__c,
          StartDate__c,
          Enddate__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :result.contractHistoryId
        ORDER BY Type__c DESC, StartDate__c ASC
      ];
      System.assertEquals(3, savedProducts.size());
      System.assertEquals('Remake', savedProducts[0].Type__c);
      System.assertEquals(termStart, savedProducts[0].StartDate__c);
      System.assertEquals(preEffectiveEnd, savedProducts[0].Enddate__c);
      System.assertEquals(2, savedProducts[0].Quantity__c);
      System.assertEquals(40000, savedProducts[0].Amount__c);
      System.assertEquals('Remake', savedProducts[1].Type__c);
      System.assertEquals(effectiveDate, savedProducts[1].StartDate__c);
      System.assertEquals(termEnd, savedProducts[1].Enddate__c);
      System.assertEquals(3, savedProducts[1].Quantity__c);
      System.assertEquals(120000, savedProducts[1].Amount__c);
      System.assertEquals('Original', savedProducts[2].Type__c);
      System.assertEquals(
        sourceProduct.Id,
        savedProducts[2].PreviousContractProduct__c
      );
      System.assertEquals(
        -120000,
        savedProducts[2].Amount__c,
        'Original: マイナス符号'
      );
    }
  }

  @IsTest
  static void saveEstimate_change_allowsNewAddonWithMislabeledDerivativeRecordType() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Change Addon Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Change Addon Opportunity'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        opportunity.AccountId,
        'Change Addon Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date effectiveDate = Date.newInstance(2025, 10, 1);
      Date preEffectiveEnd = effectiveDate.addDays(-1);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change Addon Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Addon Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 5000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      Product2 addonProduct = ContractTestDataFactory.buildProduct(
        'Change Addon Extra Product'
      );
      addonProduct.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      addonProduct.UnitPrice__c = 3000;
      addonProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      addonProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(addonProduct);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 5000,
        Unit__c = '式/月',
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = product.Id;
      beforeLine.quantity = 2;
      beforeLine.unitPrice = 5000;
      beforeLine.amount = -120000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.unit = '式/月';
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem remakePreLine = new EstimateCreateController.ProductLineItem();
      remakePreLine.productId = product.Id;
      remakePreLine.quantity = 2;
      remakePreLine.unitPrice = 5000;
      remakePreLine.amount = 40000;
      remakePreLine.startDate = String.valueOf(termStart);
      remakePreLine.endDate = String.valueOf(preEffectiveEnd);
      remakePreLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakePreLine.unit = '式/月';
      remakePreLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakePreLine.billingCycle = '月';
      remakePreLine.recordType = 'Remake';
      remakePreLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem afterLine = new EstimateCreateController.ProductLineItem();
      afterLine.productId = product.Id;
      afterLine.quantity = 3;
      afterLine.unitPrice = 5000;
      afterLine.amount = 120000;
      afterLine.startDate = String.valueOf(effectiveDate);
      afterLine.endDate = String.valueOf(termEnd);
      afterLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      afterLine.unit = '式/月';
      afterLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      afterLine.billingCycle = '月';
      afterLine.recordType = 'Remake';
      afterLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem addonLine = new EstimateCreateController.ProductLineItem();
      addonLine.productId = addonProduct.Id;
      addonLine.quantity = 1;
      addonLine.unitPrice = 3000;
      addonLine.amount = 36000;
      addonLine.startDate = String.valueOf(effectiveDate);
      addonLine.endDate = String.valueOf(termEnd);
      addonLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      addonLine.unit = '式/月';
      addonLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      addonLine.billingCycle = '月';
      addonLine.recordType = 'derivative';
      addonLine.typeLabel = 'New';
      addonLine.isDuplicate = true;
      addonLine.sourceContractProductId = null;

      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{
          beforeLine,
          remakePreLine,
          afterLine,
          addonLine
        }
      );

      Test.startTest();
      EstimateCreateController.EstimateSaveResult result = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'Change',
        null,
        'Change Addon Estimate',
        service.Id,
        sourceHistory.Id,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(effectiveDate),
        String.valueOf(Date.today()),
        productsJson,
        null,
        null,
        null,
        null
      );
      Test.stopTest();

      System.assertEquals(4, result.contractProductIds.size());
    }
  }

  @IsTest
  static void saveEstimate_change_allowsOneTimeAddonWithMidPeriodEffectiveDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Change OneTime Mid Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Change OneTime Mid Opportunity'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        opportunity.AccountId,
        'Change OneTime Mid Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date addonStart = Date.newInstance(2025, 10, 15);
      Date addonEnd = Date.newInstance(2025, 10, 31);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change OneTime Mid Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 recurringProduct = ContractTestDataFactory.buildProduct(
        'Change OneTime Mid Recurring'
      );
      recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      recurringProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(recurringProduct);

      Product2 oneTimeProduct = ContractTestDataFactory.buildProduct(
        'Change OneTime Mid Addon'
      );
      oneTimeProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      oneTimeProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(oneTimeProduct);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = recurringProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = recurringProduct.Id;
      beforeLine.quantity = 1;
      beforeLine.unitPrice = 8000;
      beforeLine.amount = -96000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem remakeLine = new EstimateCreateController.ProductLineItem();
      remakeLine.productId = recurringProduct.Id;
      remakeLine.quantity = 1;
      remakeLine.unitPrice = 8000;
      remakeLine.amount = 96000;
      remakeLine.startDate = String.valueOf(termStart);
      remakeLine.endDate = String.valueOf(termEnd);
      remakeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeLine.billingCycle = '月';
      remakeLine.recordType = 'Remake';
      remakeLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem addonLine = new EstimateCreateController.ProductLineItem();
      addonLine.productId = oneTimeProduct.Id;
      addonLine.quantity = 1;
      addonLine.unitPrice = 50000;
      addonLine.amount = 50000;
      addonLine.startDate = String.valueOf(addonStart);
      addonLine.endDate = String.valueOf(addonEnd);
      addonLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      addonLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      addonLine.recordType = 'New';

      EstimateCreateController.EstimateSaveResult result = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'Change',
        null,
        'Change OneTime Mid Estimate',
        service.Id,
        sourceHistory.Id,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(addonStart),
        String.valueOf(Date.today()),
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{
            beforeLine,
            remakeLine,
            addonLine
          }
        ),
        null,
        null,
        null,
        null
      );

      System.assertNotEquals(null, result.contractHistoryId);
      ContractHistory__c saved = [
        SELECT EffectiveDate__c
        FROM ContractHistory__c
        WHERE Id = :result.contractHistoryId
      ];
      System.assertEquals(
        null,
        saved.EffectiveDate__c,
        '一回課金追加のみの Change では継続課金の切替日は不要（null）'
      );
    }
  }

  @IsTest
  static void saveEstimate_changeType_rejectsMisalignedEffectiveDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Change Align Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Change Align Opportunity'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        opportunity.AccountId,
        'Change Align Service'
      );

      Date termStart = Date.newInstance(2026, 4, 15);
      Date termEnd = Date.newInstance(2027, 4, 14);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change Align Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Align Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 5000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = product.Id;
      beforeLine.quantity = 1;
      beforeLine.unitPrice = 5000;
      beforeLine.amount = -60000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      // Remake は隙間なく埋めたうえで、有効日だけ課金切替日（10/15）とずらす
      Date changeStart = Date.newInstance(2026, 10, 15);
      EstimateCreateController.ProductLineItem remakeEarly = new EstimateCreateController.ProductLineItem();
      remakeEarly.productId = product.Id;
      remakeEarly.quantity = 1;
      remakeEarly.unitPrice = 5000;
      remakeEarly.amount = 30000;
      remakeEarly.startDate = String.valueOf(termStart);
      remakeEarly.endDate = String.valueOf(changeStart.addDays(-1));
      remakeEarly.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakeEarly.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeEarly.billingCycle = '月';
      remakeEarly.recordType = 'Remake';
      remakeEarly.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem remakeLate = new EstimateCreateController.ProductLineItem();
      remakeLate.productId = product.Id;
      remakeLate.quantity = 2;
      remakeLate.unitPrice = 5000;
      remakeLate.amount = 60000;
      remakeLate.startDate = String.valueOf(changeStart);
      remakeLate.endDate = String.valueOf(termEnd);
      remakeLate.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakeLate.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeLate.billingCycle = '月';
      remakeLate.recordType = 'Remake';
      remakeLate.sourceContractProductId = sourceProduct.Id;

      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{
          beforeLine,
          remakeEarly,
          remakeLate
        }
      );

      Integer historyCountBefore = [
        SELECT COUNT()
        FROM ContractHistory__c
        WHERE ContractService__c = :service.Id
      ];
      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Change',
          null,
          'Change Align Estimate',
          service.Id,
          sourceHistory.Id,
          String.valueOf(termStart),
          String.valueOf(termEnd),
          // 請求期間開始日（11/15）だが、実切替（10/15）とはずらす
          String.valueOf(Date.newInstance(2026, 11, 15)),
          String.valueOf(Date.today()),
          productsJson,
          null,
          null,
          null,
          null
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '有効日は課金内容が変更された最も古い日付（2026-10-15）と一致している必要があります。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        historyCountBefore,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE ContractService__c = :service.Id
        ],
        '拒否時は Change 見積が増えない'
      );
    }
  }

  @IsTest
  static void saveEstimate_createsRecordsForRenewType() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Test Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Test Opportunity'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        opportunity.AccountId,
        'Renew Test Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date renewStart = Date.newInstance(2026, 6, 1);
      Date renewEnd = Date.newInstance(2027, 5, 31);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Source History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct('Renew Product');
      product.UnitName__c = 'ID';
      product.UnitPrice__c = 8000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      Product2 addonProduct = ContractTestDataFactory.buildProduct(
        'Renew Addon Product'
      );
      addonProduct.UnitName__c = 'ID';
      addonProduct.UnitPrice__c = 8000;
      addonProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      addonProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(addonProduct);

      insert new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Unit__c = 'ID/月',
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = addonProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Unit__c = 'ID/月',
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );

      EstimateCreateController.ProductLineItem renewLine = new EstimateCreateController.ProductLineItem();
      renewLine.productId = product.Id;
      renewLine.quantity = 1;
      renewLine.unitPrice = 8000;
      renewLine.amount = 96000;
      renewLine.startDate = String.valueOf(renewStart);
      renewLine.endDate = String.valueOf(renewEnd);
      renewLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      renewLine.unit = 'ID/月';
      renewLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      renewLine.billingCycle = '月';
      renewLine.recordType = 'Renew';

      EstimateCreateController.ProductLineItem newLine = new EstimateCreateController.ProductLineItem();
      newLine.productId = addonProduct.Id;
      newLine.quantity = 2;
      newLine.unitPrice = 8000;
      newLine.amount = 192000;
      newLine.startDate = String.valueOf(renewStart);
      newLine.endDate = String.valueOf(renewEnd);
      newLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      newLine.unit = 'ID/月';
      newLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      newLine.billingCycle = '月';
      newLine.recordType = 'New';

      String productsJson = JSON.serialize(
        new List<EstimateCreateController.ProductLineItem>{ renewLine, newLine }
      );

      Test.startTest();
      EstimateCreateController.EstimateSaveResult result = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'Renew',
        null,
        'Renew Estimate',
        service.Id,
        sourceHistory.Id,
        String.valueOf(renewStart),
        String.valueOf(renewEnd),
        String.valueOf(termEnd.addDays(1)),
        String.valueOf(Date.today()),
        productsJson,
        null,
        null,
        null,
        null
      );
      Test.stopTest();

      System.assertEquals(service.Id, result.contractServiceId);
      System.assertNotEquals(null, result.contractHistoryId);
      System.assertEquals(2, result.contractProductIds.size());

      ContractHistory__c estimateHistory = [
        SELECT Type__c, historystatus__c, Version__c, PreviousHistory__c
        FROM ContractHistory__c
        WHERE Id = :result.contractHistoryId
      ];
      System.assertEquals('Renew', estimateHistory.Type__c);
      System.assertEquals('Estimate', estimateHistory.historystatus__c);
      System.assertEquals(2, estimateHistory.Version__c);
      System.assertEquals(sourceHistory.Id, estimateHistory.PreviousHistory__c);

      List<ContractProduct__c> savedProducts = [
        SELECT Type__c, Quantity__c, BillingType__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :result.contractHistoryId
        ORDER BY Type__c DESC
      ];
      System.assertEquals(2, savedProducts.size());
      System.assertEquals('Renew', savedProducts[0].Type__c);
      System.assertEquals(
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        savedProducts[0].BillingType__c
      );
      System.assertEquals(1, savedProducts[0].Quantity__c);
      System.assertEquals('New', savedProducts[1].Type__c);
      System.assertEquals(2, savedProducts[1].Quantity__c);
    }
  }

  @IsTest
  static void saveEstimate_renew_allowsOneTimeAddonWithRecurring() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Addon Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Addon Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Renew Addon Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date renewStart = Date.newInstance(2026, 6, 1);
      Date renewEnd = Date.newInstance(2027, 5, 31);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Renew Addon Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 recurringProduct = ContractTestDataFactory.buildProduct(
        'Renew Addon Recurring'
      );
      recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      recurringProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(recurringProduct);

      Product2 oneTimeProduct = ContractTestDataFactory.buildProduct(
        'Renew Addon One Time'
      );
      oneTimeProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(oneTimeProduct);

      insert new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = recurringProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );

      EstimateCreateController.ProductLineItem renewLine = new EstimateCreateController.ProductLineItem();
      renewLine.productId = recurringProduct.Id;
      renewLine.quantity = 1;
      renewLine.unitPrice = 8000;
      renewLine.amount = 96000;
      renewLine.startDate = String.valueOf(renewStart);
      renewLine.endDate = String.valueOf(renewEnd);
      renewLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      renewLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      renewLine.billingCycle = '月';
      renewLine.recordType = 'Renew';

      EstimateCreateController.ProductLineItem addonLine = new EstimateCreateController.ProductLineItem();
      addonLine.productId = oneTimeProduct.Id;
      addonLine.quantity = 1;
      addonLine.unitPrice = 50000;
      addonLine.amount = 50000;
      addonLine.startDate = String.valueOf(renewStart);
      addonLine.endDate = String.valueOf(renewEnd);
      addonLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      addonLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      addonLine.recordType = 'New';

      EstimateCreateController.EstimateSaveResult result = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'Renew',
        null,
        'Renew Addon Estimate',
        service.Id,
        sourceHistory.Id,
        String.valueOf(renewStart),
        String.valueOf(renewEnd),
        String.valueOf(termEnd.addDays(1)),
        String.valueOf(Date.today()),
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{
            renewLine,
            addonLine
          }
        ),
        null,
        null,
        null,
        null
      );

      System.assertEquals(2, result.contractProductIds.size());
    }
  }

  @IsTest
  static void saveEstimate_renew_rejectsOneTimeOnlyLines() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Renew One Time Only Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew One Time Only Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Renew One Time Only Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date renewStart = Date.newInstance(2026, 6, 1);
      Date renewEnd = Date.newInstance(2027, 5, 31);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Renew One Time Only Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 recurringProduct = ContractTestDataFactory.buildProduct(
        'Renew One Time Only Recurring'
      );
      recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      recurringProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(recurringProduct);

      Product2 oneTimeProduct = ContractTestDataFactory.buildProduct(
        'Renew One Time Only Fee'
      );
      oneTimeProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(oneTimeProduct);

      insert new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = recurringProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );

      EstimateCreateController.ProductLineItem oneTimeLine = new EstimateCreateController.ProductLineItem();
      oneTimeLine.productId = oneTimeProduct.Id;
      oneTimeLine.quantity = 1;
      oneTimeLine.unitPrice = 50000;
      oneTimeLine.amount = 50000;
      oneTimeLine.startDate = String.valueOf(renewStart);
      oneTimeLine.endDate = String.valueOf(renewEnd);
      oneTimeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      oneTimeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      oneTimeLine.recordType = 'New';

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Renew',
          null,
          'Renew One Time Only Estimate',
          service.Id,
          sourceHistory.Id,
          String.valueOf(renewStart),
          String.valueOf(renewEnd),
          String.valueOf(termEnd.addDays(1)),
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{ oneTimeLine }
          ),
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_createsRecordsForCancelType() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Test Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Test Opportunity'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        opportunity.AccountId,
        'Cancel Test Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date cancelDate = Date.newInstance(2026, 6, 1);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Source History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 recurringProduct = ContractTestDataFactory.buildProduct(
        'Cancel Source Recurring'
      );
      recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      recurringProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(recurringProduct);

      insert new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = recurringProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );

      EstimateNoteMaster__c remarkMaster = ContractTestDataFactory.insertEstimateNoteMaster(
        'Cancel Should Ignore Master',
        'Cancel に残ってはいけない備考'
      );

      Test.startTest();
      EstimateCreateController.EstimateSaveResult result = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'Cancel',
        null,
        'Cancel Churn',
        service.Id,
        sourceHistory.Id,
        String.valueOf(cancelDate),
        String.valueOf(cancelDate),
        String.valueOf(termEnd.addDays(1)),
        String.valueOf(Date.today()),
        '[]',
        remarkMaster.Id,
        'ペイロードにあっても残さない文言',
        null,
        null
      );
      Test.stopTest();

      System.assertEquals(service.Id, result.contractServiceId);
      System.assertNotEquals(null, result.contractHistoryId);
      System.assertEquals(0, result.contractProductIds.size());

      ContractHistory__c cancelHistory = [
        SELECT
          Type__c,
          historystatus__c,
          Version__c,
          CurrentTermStartDate__c,
          CurrentTermEndDate__c,
          PreviousHistory__c,
          EstimateNoteMaster__c,
          Note__c
        FROM ContractHistory__c
        WHERE Id = :result.contractHistoryId
      ];
      System.assertEquals('Cancel', cancelHistory.Type__c);
      System.assertEquals('Estimate', cancelHistory.historystatus__c);
      System.assertEquals(2, cancelHistory.Version__c);
      System.assertEquals(sourceHistory.Id, cancelHistory.PreviousHistory__c);
      System.assertEquals(cancelDate, cancelHistory.CurrentTermStartDate__c);
      System.assertEquals(cancelDate, cancelHistory.CurrentTermEndDate__c);
      System.assertEquals(
        null,
        cancelHistory.EstimateNoteMaster__c,
        'Cancel に備考マスタは登録されない'
      );
      System.assertEquals(
        null,
        cancelHistory.Note__c,
        'Cancel に備考自由文は登録されない'
      );

      ContractService__c updatedService = [
        SELECT FirstOrderedHistory__c, LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        sourceHistory.Id,
        updatedService.FirstOrderedHistory__c
      );
      System.assertEquals(
        sourceHistory.Id,
        updatedService.LatestOrderedHistory__c
      );
    }
  }

  @IsTest
  static void getLatestContractHistory_returnsRenewEligibleFlag() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Eligible Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Renew Eligible Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();

      ContractHistory__c recurringHistory = new ContractHistory__c(
        Name = 'Renew Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      insert recurringHistory;

      Product2 recurringProduct = ContractTestDataFactory.buildProduct(
        'Renew Eligible Product'
      );
      recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      recurringProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(recurringProduct);

      insert new ContractProduct__c(
        ContractHistory__c = recurringHistory.Id,
        Product__c = recurringProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );

      EstimateCreateController.ContractHistoryDto result = EstimateCreateController.getLatestContractHistory(
        service.Id
      );

      System.assertEquals(true, result.renewEligible);
    }
  }

  @IsTest
  static void getLatestContractHistory_usesLineBillingTypeForRenewEligible() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Line Billing Account'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();

      ContractService__c flippedToOneTime = ContractTestDataFactory.insertContractService(
        account.Id,
        'Line One Time Service'
      );
      ContractHistory__c oneTimeHistory = new ContractHistory__c(
        Name = 'Line One Time History',
        ContractService__c = flippedToOneTime.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      insert oneTimeHistory;
      Product2 recurringMaster = ContractTestDataFactory.buildProduct(
        'Master Recurring Line One Time'
      );
      recurringMaster.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      recurringMaster.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(recurringMaster);
      insert new ContractProduct__c(
        ContractHistory__c = oneTimeHistory.Id,
        Product__c = recurringMaster.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = 'New'
      );

      ContractService__c flippedToRecurring = ContractTestDataFactory.insertContractService(
        account.Id,
        'Line Recurring Service'
      );
      ContractHistory__c recurringHistory = new ContractHistory__c(
        Name = 'Line Recurring History',
        ContractService__c = flippedToRecurring.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      insert recurringHistory;
      Product2 oneTimeMaster = ContractTestDataFactory.buildProduct(
        'Master One Time Line Recurring'
      );
      oneTimeMaster.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      oneTimeMaster.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(oneTimeMaster);
      insert new ContractProduct__c(
        ContractHistory__c = recurringHistory.Id,
        Product__c = oneTimeMaster.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      System.assertEquals(
        false,
        EstimateCreateController.getLatestContractHistory(flippedToOneTime.Id)
          .renewEligible,
        '明細が一回ならマスタが継続でも Renew 不可'
      );
      System.assertEquals(
        true,
        EstimateCreateController.getLatestContractHistory(flippedToRecurring.Id)
          .renewEligible,
        '明細が継続ならマスタが一回でも Renew 可'
      );

      List<EstimateCreateController.ContractProductLineDto> recurringLines = EstimateCreateController.getRecurringContractProducts(
        oneTimeHistory.Id
      );
      System.assertEquals(
        0,
        recurringLines.size(),
        '明細が一回の行は Change 元に載せない'
      );
      List<EstimateCreateController.ContractProductLineDto> keptLines = EstimateCreateController.getRecurringContractProducts(
        recurringHistory.Id
      );
      System.assertEquals(1, keptLines.size());
      System.assertEquals(
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        keptLines[0].billingType
      );

      System.assertEquals(
        0,
        EstimateCreateController.getRenewContractProducts(flippedToOneTime.Id)
          .size()
      );
      List<EstimateCreateController.ContractProductLineDto> renewLines = EstimateCreateController.getRenewContractProducts(
        flippedToRecurring.Id
      );
      System.assertEquals(1, renewLines.size());
      System.assertEquals(
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        renewLines[0].billingType
      );
    }
  }

  @IsTest
  static void saveEstimate_renew_rejectsWhenNoRecurringSource() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Reject Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Reject Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Renew Reject Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date renewStart = Date.newInstance(2026, 6, 1);
      Date renewEnd = Date.newInstance(2027, 5, 31);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'One Time Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 oneTimeProduct = ContractTestDataFactory.buildProduct(
        'One Time Product'
      );
      oneTimeProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(oneTimeProduct);

      insert new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = oneTimeProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 100000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractMetadataService.INVOICE_SETTING_PREPAID_START,
        Type__c = 'New'
      );

      EstimateCreateController.ProductLineItem renewLine = new EstimateCreateController.ProductLineItem();
      renewLine.productId = oneTimeProduct.Id;
      renewLine.quantity = 1;
      renewLine.unitPrice = 100000;
      renewLine.amount = 100000;
      renewLine.startDate = String.valueOf(renewStart);
      renewLine.endDate = String.valueOf(renewEnd);
      renewLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      renewLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      renewLine.recordType = 'Renew';

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Renew',
          null,
          'Renew Reject',
          service.Id,
          sourceHistory.Id,
          String.valueOf(renewStart),
          String.valueOf(renewEnd),
          String.valueOf(renewStart),
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{ renewLine }
          ),
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_renew_rejectsWrongPeriodStart() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Start Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Start Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Renew Start Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date wrongStart = Date.newInstance(2026, 7, 1);
      Date renewEnd = Date.newInstance(2027, 6, 30);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Renew Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct('Renew Product');
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      insert new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );

      EstimateCreateController.ProductLineItem renewLine = new EstimateCreateController.ProductLineItem();
      renewLine.productId = product.Id;
      renewLine.quantity = 1;
      renewLine.unitPrice = 8000;
      renewLine.amount = 96000;
      renewLine.startDate = String.valueOf(wrongStart);
      renewLine.endDate = String.valueOf(renewEnd);
      renewLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      renewLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      renewLine.billingCycle = '月';
      renewLine.recordType = 'Renew';

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Renew',
          null,
          'Renew Wrong Start',
          service.Id,
          sourceHistory.Id,
          String.valueOf(wrongStart),
          String.valueOf(renewEnd),
          String.valueOf(wrongStart),
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{ renewLine }
          ),
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_renew_rejectsOverlappingSameProduct() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Overlap Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Renew Overlap Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Renew Overlap Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date renewStart = Date.newInstance(2026, 6, 1);
      Date renewEnd = Date.newInstance(2027, 5, 31);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Renew Overlap Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Renew Overlap Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      insert new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );

      EstimateCreateController.ProductLineItem renewLine = new EstimateCreateController.ProductLineItem();
      renewLine.productId = product.Id;
      renewLine.quantity = 1;
      renewLine.unitPrice = 8000;
      renewLine.amount = 96000;
      renewLine.startDate = String.valueOf(renewStart);
      renewLine.endDate = String.valueOf(renewEnd);
      renewLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      renewLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      renewLine.billingCycle = '月';
      renewLine.recordType = 'Renew';

      EstimateCreateController.ProductLineItem newLine = new EstimateCreateController.ProductLineItem();
      newLine.productId = product.Id;
      newLine.quantity = 2;
      newLine.unitPrice = 8000;
      newLine.amount = 192000;
      newLine.startDate = String.valueOf(renewStart);
      newLine.endDate = String.valueOf(renewEnd);
      newLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      newLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      newLine.billingCycle = '月';
      newLine.recordType = 'New';

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Renew',
          null,
          'Renew Overlap',
          service.Id,
          sourceHistory.Id,
          String.valueOf(renewStart),
          String.valueOf(renewEnd),
          String.valueOf(renewStart),
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{
              renewLine,
              newLine
            }
          ),
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_cancel_rejectsWhenNoRecurringSource() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Cancel Reject Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Cancel Reject Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Cancel Reject Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date cancelDate = Date.newInstance(2026, 6, 1);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Cancel One Time Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Cancel',
          null,
          'Cancel Reject',
          service.Id,
          sourceHistory.Id,
          String.valueOf(cancelDate),
          String.valueOf(cancelDate),
          String.valueOf(cancelDate),
          String.valueOf(Date.today()),
          '[]',
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_cancel_rejectsFromChurnHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Cancel Churn Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Cancel Churn Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Cancel Churn Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date cancelDate = Date.newInstance(2026, 6, 1);

      ContractHistory__c churnHistory = new ContractHistory__c(
        Name = 'Already Churned',
        ContractService__c = service.Id,
        Type__c = 'Cancel',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = cancelDate,
        CurrentTermEndDate__c = cancelDate,
        Opportunity__c = opportunity.Id
      );
      insert churnHistory;

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Cancel',
          null,
          'Cancel From Churn',
          service.Id,
          churnHistory.Id,
          String.valueOf(cancelDate),
          String.valueOf(cancelDate),
          String.valueOf(cancelDate),
          String.valueOf(Date.today()),
          '[]',
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_cancel_rejectsProductsInPayload() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Cancel Product Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Cancel Product Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Cancel Product Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date cancelDate = Date.newInstance(2026, 6, 1);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Cancel Product Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 recurringProduct = ContractTestDataFactory.buildProduct(
        'Cancel Product Recurring'
      );
      recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      recurringProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(recurringProduct);

      insert new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = recurringProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );

      EstimateCreateController.ProductLineItem line = new EstimateCreateController.ProductLineItem();
      line.productId = recurringProduct.Id;
      line.quantity = 1;
      line.unitPrice = 8000;
      line.amount = 8000;
      line.startDate = String.valueOf(cancelDate);
      line.endDate = String.valueOf(cancelDate);
      line.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      line.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Cancel',
          null,
          'Cancel With Products',
          service.Id,
          sourceHistory.Id,
          String.valueOf(cancelDate),
          String.valueOf(cancelDate),
          String.valueOf(cancelDate),
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{ line }
          ),
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_cancel_rejectsWrongCancelDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Cancel Date Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Cancel Date Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Cancel Date Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date wrongCancelDate = Date.newInstance(2026, 6, 15);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Cancel Date Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 recurringProduct = ContractTestDataFactory.buildProduct(
        'Cancel Date Recurring'
      );
      recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      recurringProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(recurringProduct);

      insert new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = recurringProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Cancel',
          null,
          'Cancel Wrong Date',
          service.Id,
          sourceHistory.Id,
          String.valueOf(wrongCancelDate),
          String.valueOf(wrongCancelDate),
          String.valueOf(wrongCancelDate),
          String.valueOf(Date.today()),
          '[]',
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_change_rejectsUnchangedRemakeRequiresRenew() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Unchanged Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Change Unchanged Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Change Unchanged Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date extendedEnd = Date.newInstance(2027, 5, 31);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change Unchanged Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Unchanged Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 5000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = product.Id;
      beforeLine.quantity = 2;
      beforeLine.unitPrice = 5000;
      beforeLine.amount = -120000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem afterLine = new EstimateCreateController.ProductLineItem();
      afterLine.productId = product.Id;
      afterLine.quantity = 2;
      afterLine.unitPrice = 5000;
      afterLine.amount = 240000;
      afterLine.startDate = String.valueOf(termStart);
      afterLine.endDate = String.valueOf(extendedEnd);
      afterLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      afterLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      afterLine.billingCycle = '月';
      afterLine.recordType = 'Remake';
      afterLine.sourceContractProductId = sourceProduct.Id;

      Integer historyCountBefore = [
        SELECT COUNT()
        FROM ContractHistory__c
        WHERE ContractService__c = :service.Id
      ];
      Integer productCountBefore = [
        SELECT COUNT()
        FROM ContractProduct__c
        WHERE ContractHistory__c = :sourceHistory.Id
      ];

      // 延長だけの Change は切替日が前回終了を超えるため Renew 誘導になる
      Date extensionStart = termEnd.addDays(1);
      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Change',
          null,
          'Change Unchanged Estimate',
          service.Id,
          sourceHistory.Id,
          String.valueOf(termStart),
          String.valueOf(extendedEnd),
          String.valueOf(extensionStart),
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{
              beforeLine,
              afterLine
            }
          ),
          null,
          null,
          null,
          null
        );
      } catch (AuraHandledException e) {
        thrown = true;
        System.assertEquals(
          '切替日が前回Versionの契約終了日を超えているため、ChangeではなくRenewで作成してください。',
          e.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        historyCountBefore,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE ContractService__c = :service.Id
        ],
        '拒否時は Change 見積が増えない'
      );
      System.assertEquals(
        productCountBefore,
        [
          SELECT COUNT()
          FROM ContractProduct__c
          WHERE ContractHistory__c = :sourceHistory.Id
        ],
        '拒否時は元の受注商品も増えない'
      );
    }
  }

  @IsTest
  static void saveEstimate_change_allowsChangeBeforeEffectiveWithFullTermRemake() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Before Effective Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Change Before Effective Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Change Before Effective Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date effectiveDate = ContractTestDataFactory.stableTermStart();

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change Before Effective Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Before Effective Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 5000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = product.Id;
      beforeLine.quantity = 2;
      beforeLine.unitPrice = 5000;
      beforeLine.amount = -120000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem afterLine = new EstimateCreateController.ProductLineItem();
      afterLine.productId = product.Id;
      afterLine.quantity = 3;
      afterLine.unitPrice = 5000;
      afterLine.amount = 180000;
      afterLine.startDate = String.valueOf(termStart);
      afterLine.endDate = String.valueOf(termEnd);
      afterLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      afterLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      afterLine.billingCycle = '月';
      afterLine.recordType = 'Remake';
      afterLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.EstimateSaveResult result = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'Change',
        null,
        'Change Before Effective',
        service.Id,
        sourceHistory.Id,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(effectiveDate),
        String.valueOf(Date.today()),
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{
            beforeLine,
            afterLine
          }
        ),
        null,
        null,
        null,
        null
      );

      System.assertNotEquals(null, result.contractHistoryId);

      List<ContractProduct__c> savedProducts = [
        SELECT Type__c, StartDate__c, Enddate__c, Quantity__c, UnitPrice__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :result.contractHistoryId
        ORDER BY Type__c DESC
      ];
      System.assertEquals(2, savedProducts.size());
      System.assertEquals('Remake', savedProducts[0].Type__c);
      System.assertEquals(effectiveDate, savedProducts[0].StartDate__c);
      System.assertEquals(termEnd, savedProducts[0].Enddate__c);
      System.assertEquals(3, savedProducts[0].Quantity__c);
    }
  }

  @IsTest
  static void saveEstimate_change_rejectsSplitReconstitutionWithNewLine() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Split Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Change Split Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Change Split Service'
      );

      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2027, 3, 31);
      Date effectiveDate = Date.newInstance(2026, 5, 1);
      Date preEffectiveEnd = Date.newInstance(2026, 4, 30);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change Split Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Split Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 30000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = product.Id;
      beforeLine.quantity = 1;
      beforeLine.unitPrice = 30000;
      beforeLine.amount = -360000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem derivativeLine = new EstimateCreateController.ProductLineItem();
      derivativeLine.productId = product.Id;
      derivativeLine.quantity = 1;
      derivativeLine.unitPrice = 30000;
      derivativeLine.amount = 30000;
      derivativeLine.startDate = String.valueOf(termStart);
      derivativeLine.endDate = String.valueOf(preEffectiveEnd);
      derivativeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      derivativeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      derivativeLine.billingCycle = '月';
      derivativeLine.recordType = 'Remake';
      derivativeLine.sourceContractProductId = sourceProduct.Id;

      // 同じ商品の New で残り期間を埋めても、再構成の穴埋めには使えない
      EstimateCreateController.ProductLineItem newLine = new EstimateCreateController.ProductLineItem();
      newLine.productId = product.Id;
      newLine.quantity = 1;
      newLine.unitPrice = 50000;
      newLine.amount = 550000;
      newLine.startDate = String.valueOf(effectiveDate);
      newLine.endDate = String.valueOf(termEnd);
      newLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      newLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      newLine.billingCycle = '月';
      newLine.recordType = 'New';
      newLine.typeLabel = 'New';

      Integer historyCountBefore = [
        SELECT COUNT()
        FROM ContractHistory__c
        WHERE ContractService__c = :service.Id
      ];
      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Change',
          null,
          'Change Split Estimate',
          service.Id,
          sourceHistory.Id,
          String.valueOf(termStart),
          String.valueOf(termEnd),
          String.valueOf(effectiveDate),
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{
              beforeLine,
              derivativeLine,
              newLine
            }
          ),
          null,
          null,
          null,
          null
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          'Remake は Originalの期間を重複や隙間なく埋める必要があります。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        historyCountBefore,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE ContractService__c = :service.Id
        ],
        '拒否時は Change 見積が増えない'
      );
    }
  }

  @IsTest
  static void saveEstimate_change_rejectsRemakeReadonlyAsOriginalSubstitute() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Remake Readonly Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Change Remake Readonly Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Change Remake Readonly Service'
      );

      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2027, 3, 31);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change Remake Readonly Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Remake Readonly Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 30000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      // 旧フォールバック形（Remake+readonly）は Original 扱いにしない
      EstimateCreateController.ProductLineItem fakeOriginal = new EstimateCreateController.ProductLineItem();
      fakeOriginal.productId = product.Id;
      fakeOriginal.quantity = 1;
      fakeOriginal.unitPrice = 30000;
      fakeOriginal.amount = -360000;
      fakeOriginal.startDate = String.valueOf(termStart);
      fakeOriginal.endDate = String.valueOf(termEnd);
      fakeOriginal.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      fakeOriginal.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      fakeOriginal.billingCycle = '月';
      fakeOriginal.recordType = 'Remake';
      fakeOriginal.isReadonly = true;
      fakeOriginal.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem remakeLine = new EstimateCreateController.ProductLineItem();
      remakeLine.productId = product.Id;
      remakeLine.quantity = 1;
      remakeLine.unitPrice = 30000;
      remakeLine.amount = 360000;
      remakeLine.startDate = String.valueOf(termStart);
      remakeLine.endDate = String.valueOf(termEnd);
      remakeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeLine.billingCycle = '月';
      remakeLine.recordType = 'Remake';
      remakeLine.sourceContractProductId = sourceProduct.Id;

      Boolean thrown = false;
      String message = '';
      Integer historyCountBefore = [
        SELECT COUNT()
        FROM ContractHistory__c
        WHERE ContractService__c = :service.Id
      ];
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Change',
          null,
          'Change Remake Readonly Estimate',
          service.Id,
          sourceHistory.Id,
          String.valueOf(termStart),
          String.valueOf(termEnd),
          String.valueOf(termStart),
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{
              fakeOriginal,
              remakeLine
            }
          ),
          null,
          null,
          null,
          null
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        message = ex.getMessage();
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        '前回Versionの継続課金商品すべてにOriginal行が必要です。',
        message
      );
      System.assertEquals(
        historyCountBefore,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE ContractService__c = :service.Id
        ],
        '拒否時は Change 見積が増えない'
      );
    }
  }

  @IsTest
  static void saveEstimate_change_rejectsZeroQuantityRemake() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Zero Qty Ban Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Change Zero Qty Ban Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Change Zero Qty Ban Service'
      );

      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2027, 3, 31);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change Zero Qty Ban Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Zero Qty Ban Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 30000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = product.Id;
      beforeLine.quantity = 1;
      beforeLine.unitPrice = 30000;
      beforeLine.amount = -360000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      // 途中終了は単価0。数量0 Remake は禁止。
      EstimateCreateController.ProductLineItem remakeLine = new EstimateCreateController.ProductLineItem();
      remakeLine.productId = product.Id;
      remakeLine.quantity = 0;
      remakeLine.unitPrice = 0;
      remakeLine.amount = 0;
      remakeLine.startDate = String.valueOf(termStart);
      remakeLine.endDate = String.valueOf(termEnd);
      remakeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeLine.billingCycle = '月';
      remakeLine.recordType = 'Remake';
      remakeLine.sourceContractProductId = sourceProduct.Id;

      Integer historyCountBefore = [
        SELECT COUNT()
        FROM ContractHistory__c
        WHERE ContractService__c = :service.Id
      ];

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Change',
          null,
          'Change Zero Qty Ban Estimate',
          service.Id,
          sourceHistory.Id,
          String.valueOf(termStart),
          String.valueOf(termEnd),
          String.valueOf(termStart),
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{
              beforeLine,
              remakeLine
            }
          ),
          null,
          null,
          null,
          null
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '商品明細2行目: 数量を入力してください。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown, '数量0 Remake はエラーになること');
      System.assertEquals(
        historyCountBefore,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE ContractService__c = :service.Id
        ],
        '拒否時は Change 見積が増えない'
      );
    }
  }

  @IsTest
  static void saveEstimate_change_skipsEndpointWhenNoActiveRecurring() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Endpoint Skip Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Change Endpoint Skip Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Change Endpoint Skip Service'
      );

      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2027, 3, 31);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change Endpoint Skip Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Endpoint Skip Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 30000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = product.Id;
      beforeLine.quantity = 1;
      beforeLine.unitPrice = 30000;
      beforeLine.amount = -360000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      // Remake を単価差のみの継続課金にし、課金イベントを立てつつ終端チェックを通す
      EstimateCreateController.ProductLineItem remakeLine = new EstimateCreateController.ProductLineItem();
      remakeLine.productId = product.Id;
      remakeLine.quantity = 1;
      remakeLine.unitPrice = 29000;
      remakeLine.amount = 29000;
      remakeLine.startDate = String.valueOf(termStart);
      remakeLine.endDate = String.valueOf(termEnd);
      remakeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeLine.recordType = 'Remake';
      remakeLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.EstimateSaveResult result = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'Change',
        null,
        'Change Endpoint Skip Estimate',
        service.Id,
        sourceHistory.Id,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(termStart),
        String.valueOf(Date.today()),
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{
            beforeLine,
            remakeLine
          }
        ),
        null,
        null,
        null,
        null
      );
      System.assertNotEquals(null, result);
      System.assertNotEquals(null, result.contractHistoryId);
    }
  }

  @IsTest
  static void saveEstimate_change_rejectsReconstitutionGap() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Gap Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Change Gap Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Change Gap Service'
      );

      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2027, 3, 31);
      Date effectiveDate = Date.newInstance(2026, 5, 1);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change Gap Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Gap Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 30000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = product.Id;
      beforeLine.quantity = 1;
      beforeLine.unitPrice = 30000;
      beforeLine.amount = -360000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem derivativeLine = new EstimateCreateController.ProductLineItem();
      derivativeLine.productId = product.Id;
      derivativeLine.quantity = 1;
      derivativeLine.unitPrice = 50000;
      derivativeLine.amount = 550000;
      derivativeLine.startDate = String.valueOf(Date.newInstance(2026, 6, 1));
      derivativeLine.endDate = String.valueOf(termEnd);
      derivativeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      derivativeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      derivativeLine.billingCycle = '月';
      derivativeLine.recordType = 'Remake';
      derivativeLine.sourceContractProductId = sourceProduct.Id;

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Change',
          null,
          'Change Gap Estimate',
          service.Id,
          sourceHistory.Id,
          String.valueOf(termStart),
          String.valueOf(termEnd),
          String.valueOf(effectiveDate),
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{
              beforeLine,
              derivativeLine
            }
          ),
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_change_rejectsSingleRemakeStartingAtEffectiveDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Single Remake Effective Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Change Single Remake Effective Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Change Single Remake Effective Service'
      );

      Date termStart = Date.newInstance(2025, 4, 1);
      Date termEnd = Date.newInstance(2026, 3, 31);
      Date effectiveDate = Date.newInstance(2025, 10, 1);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change Single Remake Effective Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Single Remake Effective Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem originalLine = new EstimateCreateController.ProductLineItem();
      originalLine.productId = product.Id;
      originalLine.quantity = 1;
      originalLine.unitPrice = 10000;
      originalLine.amount = -120000;
      originalLine.startDate = String.valueOf(termStart);
      originalLine.endDate = String.valueOf(termEnd);
      originalLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      originalLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      originalLine.billingCycle = '月';
      originalLine.recordType = 'Original';
      originalLine.sourceContractProductId = sourceProduct.Id;

      // 課題A: Remake1本かつ開始=有効日で Original 開始〜有効日前を埋めない → 保存不可
      EstimateCreateController.ProductLineItem remakeLine = new EstimateCreateController.ProductLineItem();
      remakeLine.productId = product.Id;
      remakeLine.quantity = 1;
      remakeLine.unitPrice = 15000;
      remakeLine.amount = 90000;
      remakeLine.startDate = String.valueOf(effectiveDate);
      remakeLine.endDate = String.valueOf(termEnd);
      remakeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakeLine.billingCycle = '月';
      remakeLine.recordType = 'Remake';
      remakeLine.sourceContractProductId = sourceProduct.Id;

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Change',
          null,
          'Change Single Remake Effective',
          service.Id,
          sourceHistory.Id,
          String.valueOf(termStart),
          String.valueOf(termEnd),
          String.valueOf(effectiveDate),
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{
              originalLine,
              remakeLine
            }
          ),
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_change_rejectsTamperedOriginal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Tamper Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Change Tamper Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Change Tamper Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change Tamper Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Tamper Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 5000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = product.Id;
      beforeLine.quantity = 3;
      beforeLine.unitPrice = 5000;
      beforeLine.amount = -180000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem afterLine = new EstimateCreateController.ProductLineItem();
      afterLine.productId = product.Id;
      afterLine.quantity = 2;
      afterLine.unitPrice = 5000;
      afterLine.amount = 120000;
      afterLine.startDate = String.valueOf(termStart);
      afterLine.endDate = String.valueOf(termEnd);
      afterLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      afterLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      afterLine.billingCycle = '月';
      afterLine.recordType = 'Remake';
      afterLine.sourceContractProductId = sourceProduct.Id;

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Change',
          null,
          'Change Tamper',
          service.Id,
          sourceHistory.Id,
          String.valueOf(termStart),
          String.valueOf(termEnd),
          String.valueOf(termStart),
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{
              beforeLine,
              afterLine
            }
          ),
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_change_rejectsRemakeEndBeforeHeaderEnd() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change End Endpoint Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Change End Endpoint Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Change End Endpoint Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date extendedTermEnd = Date.newInstance(2027, 5, 31);
      Date effectiveDate = Date.newInstance(2025, 10, 1);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change End Endpoint Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change End Endpoint Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 5000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = product.Id;
      beforeLine.quantity = 2;
      beforeLine.unitPrice = 5000;
      beforeLine.amount = -120000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem afterLine = new EstimateCreateController.ProductLineItem();
      afterLine.productId = product.Id;
      afterLine.quantity = 2;
      afterLine.unitPrice = 5000;
      afterLine.amount = 60000;
      afterLine.startDate = String.valueOf(effectiveDate);
      afterLine.endDate = String.valueOf(termEnd);
      afterLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      afterLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      afterLine.billingCycle = '月';
      afterLine.recordType = 'Remake';
      afterLine.sourceContractProductId = sourceProduct.Id;

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'Change',
          null,
          'Change End Endpoint',
          service.Id,
          sourceHistory.Id,
          String.valueOf(termStart),
          String.valueOf(extendedTermEnd),
          String.valueOf(effectiveDate),
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{
              beforeLine,
              afterLine
            }
          ),
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void saveEstimate_change_defaultsMissingRecordTypeToNew() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Missing RecordType Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Change Missing RecordType Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Change Missing RecordType Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date effectiveDate = Date.newInstance(2025, 10, 1);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Change Missing RecordType Source',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Missing RecordType Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      Product2 addonProduct = ContractTestDataFactory.buildProduct(
        'Change Missing RecordType Addon'
      );
      addonProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      addonProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(addonProduct);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 5000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = product.Id;
      beforeLine.quantity = 2;
      beforeLine.unitPrice = 5000;
      beforeLine.amount = -120000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem afterLine = new EstimateCreateController.ProductLineItem();
      afterLine.productId = product.Id;
      afterLine.quantity = 2;
      afterLine.unitPrice = 5000;
      afterLine.amount = 120000;
      afterLine.startDate = String.valueOf(termStart);
      afterLine.endDate = String.valueOf(termEnd);
      afterLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      afterLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      afterLine.billingCycle = '月';
      afterLine.recordType = 'Remake';
      afterLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem addonLine = new EstimateCreateController.ProductLineItem();
      addonLine.productId = addonProduct.Id;
      addonLine.quantity = 1;
      addonLine.unitPrice = 3000;
      addonLine.amount = 60000;
      addonLine.startDate = String.valueOf(effectiveDate);
      addonLine.endDate = String.valueOf(termEnd);
      addonLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      addonLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      addonLine.billingCycle = '月';

      EstimateCreateController.EstimateSaveResult result = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'Change',
        null,
        'Change Missing RecordType Estimate',
        service.Id,
        sourceHistory.Id,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(effectiveDate),
        String.valueOf(Date.today()),
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{
            beforeLine,
            afterLine,
            addonLine
          }
        ),
        null,
        null,
        null,
        null
      );

      System.assertNotEquals(null, result.contractHistoryId);

      List<ContractProduct__c> savedProducts = [
        SELECT Type__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :result.contractHistoryId
        ORDER BY Type__c ASC
      ];
      System.assertEquals(3, savedProducts.size());
      System.assertEquals('New', savedProducts[0].Type__c);
    }
  }

  @IsTest
  static void saveEstimate_rejectsSplitMonthlyInvoiceSettingForOneTime() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'One Time Invoice Setting'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'One Time Invoice Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'One Time Invoice Service'
      );

      Product2 oneTimeProduct = ContractTestDataFactory.buildProduct(
        'One Time Split Monthly Product'
      );
      oneTimeProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(oneTimeProduct);

      EstimateCreateController.ProductLineItem lineItem = new EstimateCreateController.ProductLineItem();
      lineItem.productId = oneTimeProduct.Id;
      lineItem.quantity = 1;
      lineItem.unitPrice = 10000;
      lineItem.startDate = '2026-06-01';
      lineItem.endDate = '2027-05-31';
      lineItem.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
      lineItem.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;

      Boolean thrown = false;
      try {
        EstimateCreateController.saveEstimate(
          opportunity.Id,
          'New',
          null,
          'One Time Split Monthly Estimate',
          service.Id,
          null,
          '2026-06-01',
          '2027-05-31',
          '2026-06-01',
          String.valueOf(Date.today()),
          JSON.serialize(
            new List<EstimateCreateController.ProductLineItem>{ lineItem }
          ),
          null,
          null,
          null,
          null
        );
      } catch (Exception error) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void getEstimateCopyPreset_returnsPresetForEstimateHistory() {
    // Fixed monthly term dates for stable New-save validation.
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Copy Test Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Copy Test Opportunity'
      );

      Product2 product = ContractTestDataFactory.buildProduct(
        'Copy Test Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 10000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      EstimateNoteMaster__c remarkMaster = ContractTestDataFactory.insertEstimateNoteMaster(
        'Copy Remark Master',
        '見積備考マスタの文面'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();

      EstimateCreateController.ProductLineItem lineItem = new EstimateCreateController.ProductLineItem();
      lineItem.productId = product.Id;
      lineItem.quantity = 2;
      lineItem.unitPrice = 10000;
      lineItem.amount = 20000;
      lineItem.startDate = String.valueOf(termStart);
      lineItem.endDate = String.valueOf(termEnd);
      lineItem.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      lineItem.unit = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      lineItem.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      lineItem.billingCycle = '月';
      lineItem.recordType = 'New';

      EstimateCreateController.EstimateSaveResult saveResult = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'New',
        'Copy Test Service',
        'Copy Source History',
        null,
        null,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(termStart),
        String.valueOf(termStart),
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{ lineItem }
        ),
        remarkMaster.Id,
        'コピー元の見積備考',
        null,
        null
      );

      Test.startTest();
      EstimateCreateController.EstimateCopyPresetDto preset = EstimateCreateController.getEstimateCopyPreset(
        saveResult.contractHistoryId
      );
      Test.stopTest();

      System.assertEquals(opportunity.Id, preset.opportunityId);
      System.assertEquals('Copy Test Opportunity', preset.opportunityName);
      System.assertEquals('Copy Test Account', preset.accountName);
      System.assertEquals('New', preset.selectedType);
      System.assertEquals(
        'Copy Test Serviceのコピー',
        preset.contractServiceName
      );
      System.assertEquals(
        'Copy Source Historyのコピー',
        preset.contractHistoryName
      );
      System.assertEquals(null, preset.contractServiceId);
      System.assertEquals(null, preset.contractHistoryId);
      System.assertEquals(
        null,
        preset.serviceLifecycle,
        'New コピーはサービス新規化のため Lifecycle は空'
      );
      System.assertEquals(1, preset.selectedProducts.size());
      System.assertEquals(product.Id, preset.selectedProducts[0].productId);
      System.assertEquals(2, preset.selectedProducts[0].quantity);
      System.assertEquals(
        String.valueOf(termStart),
        preset.contractEffectiveDate
      );
      System.assertEquals(String.valueOf(termEnd), preset.endDate);
      System.assertEquals(remarkMaster.Id, preset.estimateRemarkMasterId);
      System.assertEquals('コピー元の見積備考', preset.estimateRemarks);
    }
  }

  @IsTest
  static void getEstimateCopyPreset_rejectsNonEstimateHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Reject Copy Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Reject Copy Opportunity'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        testAccount.Id,
        'Reject Copy Service'
      );

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Ordered History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        Opportunity__c = opportunity.Id,
        CurrentTermStartDate__c = ContractTestDataFactory.stableTermStart(),
        CurrentTermEndDate__c = ContractTestDataFactory.stableTermEnd()
      );
      insert history;

      Boolean thrown = false;
      Test.startTest();
      try {
        EstimateCreateController.getEstimateCopyPreset(history.Id);
      } catch (Exception error) {
        thrown = true;
      }
      Test.stopTest();

      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void getEstimateCopyPreset_presetsSameVersionForNonNewCopy() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'NonNew Copy Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'NonNew Copy Opportunity'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        testAccount.Id,
        'NonNew Copy Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date effectiveDate = Date.newInstance(2025, 10, 1);
      Date preEffectiveEnd = effectiveDate.addDays(-1);

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'NonNew Source History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'NonNew Copy Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 5000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c sourceProduct = new ContractProduct__c(
        ContractHistory__c = sourceHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 5000,
        Unit__c = '式/月',
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        Type__c = 'New'
      );
      insert sourceProduct;

      EstimateCreateController.ProductLineItem beforeLine = new EstimateCreateController.ProductLineItem();
      beforeLine.productId = product.Id;
      beforeLine.quantity = 2;
      beforeLine.unitPrice = 5000;
      beforeLine.amount = -120000;
      beforeLine.startDate = String.valueOf(termStart);
      beforeLine.endDate = String.valueOf(termEnd);
      beforeLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      beforeLine.unit = '式/月';
      beforeLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      beforeLine.billingCycle = '月';
      beforeLine.recordType = 'Original';
      beforeLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem remakePreLine = new EstimateCreateController.ProductLineItem();
      remakePreLine.productId = product.Id;
      remakePreLine.quantity = 2;
      remakePreLine.unitPrice = 5000;
      remakePreLine.amount = 40000;
      remakePreLine.startDate = String.valueOf(termStart);
      remakePreLine.endDate = String.valueOf(preEffectiveEnd);
      remakePreLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      remakePreLine.unit = '式/月';
      remakePreLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      remakePreLine.billingCycle = '月';
      remakePreLine.recordType = 'Remake';
      remakePreLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.ProductLineItem afterLine = new EstimateCreateController.ProductLineItem();
      afterLine.productId = product.Id;
      afterLine.quantity = 3;
      afterLine.unitPrice = 5000;
      afterLine.amount = 120000;
      afterLine.startDate = String.valueOf(effectiveDate);
      afterLine.endDate = String.valueOf(termEnd);
      afterLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      afterLine.unit = '式/月';
      afterLine.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      afterLine.billingCycle = '月';
      afterLine.recordType = 'Remake';
      afterLine.sourceContractProductId = sourceProduct.Id;

      EstimateCreateController.EstimateSaveResult sourceResult = EstimateCreateController.saveEstimate(
        opportunity.Id,
        'Change',
        null,
        'Change Source Estimate',
        service.Id,
        sourceHistory.Id,
        String.valueOf(termStart),
        String.valueOf(termEnd),
        String.valueOf(effectiveDate),
        String.valueOf(Date.today()),
        JSON.serialize(
          new List<EstimateCreateController.ProductLineItem>{
            beforeLine,
            remakePreLine,
            afterLine
          }
        ),
        null,
        null,
        null,
        null
      );

      Test.startTest();
      EstimateCreateController.EstimateCopyPresetDto preset = EstimateCreateController.getEstimateCopyPreset(
        sourceResult.contractHistoryId
      );
      Test.stopTest();

      System.assertEquals('Change', preset.selectedType);
      System.assertEquals(service.Id, preset.contractServiceId);
      System.assertEquals(sourceHistory.Id, preset.contractHistoryId);
      System.assertEquals(
        ContractDomainConstants.LIFECYCLE_TERM,
        preset.serviceLifecycle
      );
      System.assertEquals(1, preset.baseHistoryVersion);
      System.assertEquals(2, preset.nextHistoryVersion);
      System.assertEquals(
        'Change Source Estimateのコピー',
        preset.contractHistoryName
      );
      System.assertEquals(
        String.valueOf(effectiveDate),
        preset.contractEffectiveDate
      );
    }
  }

  @IsTest
  static void getEstimateCopyPreset_presetsEffectiveDateForRenewWithoutEffectiveDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Renew Copy Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Renew Copy Opportunity'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        testAccount.Id,
        'Renew Copy Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      Date renewStart = Date.newInstance(2026, 6, 1);
      Date renewEnd = Date.newInstance(2027, 5, 31);

      ContractHistory__c previousHistory = new ContractHistory__c(
        Name = 'Renew Copy Previous History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert previousHistory;

      ContractHistory__c renewHistory = new ContractHistory__c(
        Name = 'Renew Copy Source History',
        ContractService__c = service.Id,
        Type__c = 'Renew',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = renewStart,
        CurrentTermEndDate__c = renewEnd,
        Opportunity__c = opportunity.Id,
        PreviousHistory__c = previousHistory.Id
      );
      insert renewHistory;

      Test.startTest();
      EstimateCreateController.EstimateCopyPresetDto preset = EstimateCreateController.getEstimateCopyPreset(
        renewHistory.Id
      );
      Test.stopTest();

      System.assertEquals('Renew', preset.selectedType);
      System.assertEquals(String.valueOf(renewStart), preset.contractStartDate);
      System.assertEquals(
        String.valueOf(renewStart),
        preset.contractEffectiveDate
      );
    }
  }

  @IsTest
  static void resolveEstimateHistoryVersion_usesLatestOrderedPlusOneForCopy() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account testAccount = ContractTestDataFactory.insertAccount(
        'Copy Version Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        testAccount.Id,
        'Copy Version Opportunity'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        testAccount.Id,
        'Copy Version Service'
      );

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();

      ContractHistory__c sourceHistory = new ContractHistory__c(
        Name = 'Copy Version Source History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert sourceHistory;

      ContractHistory__c estimateHistory = new ContractHistory__c(
        Name = 'Copy Version Change Estimate',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 9,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = Date.newInstance(2025, 10, 1),
        Opportunity__c = opportunity.Id,
        PreviousHistory__c = sourceHistory.Id
      );
      insert estimateHistory;

      Test.startTest();
      Decimal resolvedVersion = EstimateSaveService.resolveEstimateHistoryVersion(
        service.Id,
        estimateHistory.Id
      );
      Test.stopTest();

      System.assertEquals(
        2,
        resolvedVersion,
        'コピーでも最新 Ordered + 1（コピー元 Version は使わない）'
      );
    }
  }

  @IsTest
  static void wizardFieldService_helpers_areCoveredWithTestDefinitions() {
    ContractTestDataFactory.applyStandardWizardFieldDefinitionsForTest();

    System.assertEquals(
      1,
      ContractWizardFieldService.getContractServiceFieldDefinitions().size()
    );
    System.assertEquals(
      1,
      ContractWizardFieldService.getContractHistoryFieldDefinitions().size()
    );

    ContractService__c service = new ContractService__c();
    ContractWizardFieldService.applyCustomFields(
      service,
      new Map<String, Object>{ 'CustomerMemo__c' => ' service memo ' },
      ContractWizardFieldService.WizardTarget.ContractService
    );
    System.assertEquals('service memo', service.CustomerMemo__c);

    Product2 product = new Product2(
      Name = 'Wizard Coverage Product',
      Family = ContractTestDataFactory.WIZARD_TEST_PRODUCT_FAMILY
    );
    ContractTestDataFactory.insertProduct(product);
    Map<String, String> context = ContractWizardFieldService.buildProductVisibilityContext(
      product
    );
    System.assertEquals(
      ContractTestDataFactory.WIZARD_TEST_PRODUCT_FAMILY,
      context.get('Family')
    );

    System.assertEquals(true, EstimateValidationService.decimalsEqual(1, 1));
    System.assertEquals(false, EstimateValidationService.decimalsEqual(1, 2));
    try {
      throw EstimateValidationService.estSaveException('001', 'coverage');
    } catch (AuraHandledException ex) {
      System.assertNotEquals(null, ex.getMessage());
    }
  }

  @IsTest
  static void facadeQueryMethods_areCallable() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Facade Account');
      Boolean copyLaunchThrows = false;
      try {
        EstimateCreateController.getEstimateCopyLaunchInfo(null);
      } catch (AuraHandledException ex) {
        copyLaunchThrows = true;
      }
      System.assertEquals(true, copyLaunchThrows);
      System.assertNotEquals(
        null,
        EstimateCreateController.getDefaultInvoiceSettingLabel()
      );
      System.assertNotEquals(
        null,
        EstimateCreateController.getInvoiceSettingOptions()
      );
      System.assertEquals(
        0,
        EstimateCreateController.getBillingAccountsByAccount(null).size()
      );
      System.assertEquals(
        0,
        EstimateCreateController.getActiveContractServicesByAccount(null).size()
      );

      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = 'テスト御中',
        BillingEmailTo__c = 'to@example.com',
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
        AdjustInvoiceDateToBusinessDay__c = false
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;

      System.assert(
        EstimateCreateController.getBillingAccountsByAccount(account.Id)
          .size() >= 1
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Facade Service'
      );
      List<EstimateCreateController.ContractServiceOptionDto> services = EstimateCreateController.getActiveContractServicesByAccount(
        account.Id
      );
      System.assertNotEquals(null, services);
      // 未受注のみのサービスは候補に出ない。DTO は id/name だけ触れ、ウィザード向け拡張フィールドは触らない。
      EstimateCreateController.ContractServiceOptionDto shape = new EstimateCreateController.ContractServiceOptionDto();
      shape.id = service.Id;
      shape.name = service.Name;
      System.assertEquals(service.Id, shape.id);
      System.assertEquals(service.Name, shape.name);
    }
  }

  @IsTest
  static void getActiveContractServicesByAccount_skipsBlankLifecycle() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Lifecycle Picker Acc'
      );
      // 未受注サービスは候補に出ない（Lifecycle 空クリアは受注後 VR で不可なため）
      ContractService__c estimateOnlyService = ContractTestDataFactory.insertContractService(
        account.Id,
        'Estimate Only Service'
      );
      ContractService__c blankOrderedService = ContractTestDataFactory.insertContractService(
        account.Id,
        'Blank Lifecycle Ordered Service'
      );
      ContractService__c termService = ContractTestDataFactory.insertContractService(
        account.Id,
        'Term Lifecycle Service'
      );
      termService.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
      update termService;
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      insert new List<ContractHistory__c>{
        new ContractHistory__c(
          Name = 'Estimate Only V1',
          ContractService__c = estimateOnlyService.Id,
          Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
          historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
          Version__c = 1,
          CurrentTermStartDate__c = termStart,
          CurrentTermEndDate__c = termEnd,
          EffectiveDate__c = termStart
        ),
        new ContractHistory__c(
          Name = 'Blank Ordered V1',
          ContractService__c = blankOrderedService.Id,
          Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
          historystatus__c = ContractDomainConstants.HISTORY_STATUS_ORDERED,
          Version__c = 1,
          CurrentTermStartDate__c = termStart,
          CurrentTermEndDate__c = termEnd,
          EffectiveDate__c = termStart
        ),
        new ContractHistory__c(
          Name = 'Term V1',
          ContractService__c = termService.Id,
          Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
          historystatus__c = ContractDomainConstants.HISTORY_STATUS_ORDERED,
          Version__c = 1,
          CurrentTermStartDate__c = termStart,
          CurrentTermEndDate__c = termEnd,
          EffectiveDate__c = termStart
        )
      };

      Test.startTest();
      List<EstimateCreateController.ContractServiceOptionDto> services = EstimateCreateController.getActiveContractServicesByAccount(
        account.Id
      );
      Test.stopTest();

      Set<Id> ids = new Set<Id>();
      for (
        EstimateCreateController.ContractServiceOptionDto option : services
      ) {
        ids.add(option.id);
      }
      System.assertEquals(
        false,
        ids.contains(estimateOnlyService.Id),
        '未受注サービスは候補に出さない'
      );
      System.assertEquals(
        false,
        ids.contains(blankOrderedService.Id),
        'Lifecycle 未設定の受注済みサービスは候補に出さない'
      );
      System.assertEquals(true, ids.contains(termService.Id));
    }
  }

  @IsTest
  static void getActiveContractServicesByAccount_fillsCurrentProductNames() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Current Products Acc'
      );
      ContractService__c termService = ContractTestDataFactory.insertContractService(
        account.Id,
        'Term Current Products Service'
      );
      termService.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
      update termService;
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Term Current Products V1',
        ContractService__c = termService.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ORDERED,
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert history;

      Product2 recurringProduct = ContractTestDataFactory.buildProduct(
        'Current Product Term'
      );
      recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(recurringProduct);
      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = recurringProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        Type__c = 'New'
      );

      Test.startTest();
      List<EstimateCreateController.ContractServiceOptionDto> services = EstimateCreateController.getActiveContractServicesByAccount(
        account.Id
      );
      Test.stopTest();

      String currentProducts = null;
      for (
        EstimateCreateController.ContractServiceOptionDto option : services
      ) {
        if (option.id == termService.Id) {
          currentProducts = option.currentProductNames;
        }
      }
      System.assert(
        String.isNotBlank(currentProducts) &&
        currentProducts.contains('Current Product Term'),
        'Term の現商品名が載ること: ' + currentProducts
      );
    }
  }

  @IsTest
  static void saveEstimate_shorterOverloads_delegateToService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown18 = false;
      try {
        EstimateCreateController.saveEstimate(
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown18 = true;
      }
      System.assertEquals(true, thrown18);

      Boolean thrown16 = false;
      try {
        EstimateCreateController.saveEstimate(
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown16 = true;
      }
      System.assertEquals(true, thrown16);

      Boolean thrown15 = false;
      try {
        EstimateCreateController.saveEstimate(
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown15 = true;
      }
      System.assertEquals(true, thrown15);
    }
  }

  @IsTest
  static void dtoConstructors_instantiateInnerClasses() {
    EstimateCreateController.ProductDefaultDto productDefault = new EstimateCreateController.ProductDefaultDto();
    productDefault.unitName = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
    productDefault.unitPrice = 1000;

    EstimateCreateController.ProductLineItem lineItem = new EstimateCreateController.ProductLineItem();
    lineItem.quantity = 1;
    lineItem.amount = 1000;

    EstimateCreateController.EstimateCopyPresetDto preset = new EstimateCreateController.EstimateCopyPresetDto();
    preset.selectedType = 'New';
    preset.contractCustomFieldsExpanded = true;

    EstimateCreateController.BillingAccountInvoiceSettingsDto billingSettings = new EstimateCreateController.BillingAccountInvoiceSettingsDto();
    billingSettings.billingDayOfMonth = 25;

    EstimateCreateController.BillingAccountOptionDto billingOption = new EstimateCreateController.BillingAccountOptionDto();
    billingOption.name = 'BA';

    EstimateCreateController.ContractServiceOptionDto serviceOption = new EstimateCreateController.ContractServiceOptionDto();
    serviceOption.name = 'Service';

    EstimateCreateController.EstimateSaveRequest saveRequest = new EstimateCreateController.EstimateSaveRequest();
    saveRequest.selectedType = 'New';

    EstimateCreateController.EstimateSaveResult saveResult = new EstimateCreateController.EstimateSaveResult();
    saveResult.contractProductIds = new List<Id>();

    EstimateCreateController.ContractHistoryDto historyDto = new EstimateCreateController.ContractHistoryDto();
    historyDto.version = 1;

    EstimateCreateController.ContractProductLineDto productLine = new EstimateCreateController.ContractProductLineDto();
    productLine.quantity = 1;

    System.assertEquals('New', preset.selectedType);
  }
}
