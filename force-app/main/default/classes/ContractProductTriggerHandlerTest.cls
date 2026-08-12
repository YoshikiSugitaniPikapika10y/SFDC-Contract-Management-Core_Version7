@IsTest
private class ContractProductTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void populateAccountFromContractHistory_setsAccountFromService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Trigger Test Account'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Trigger Test Service',
        Account__c = account.Id
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Trigger Test History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Trigger Test Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c contractProduct = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert contractProduct;

      contractProduct = [
        SELECT Account__c, InvoiceAnchorDate__c, InvoiceBillingCycleCount__c
        FROM ContractProduct__c
        WHERE Id = :contractProduct.Id
      ];
      System.assertEquals(account.Id, contractProduct.Account__c);
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        contractProduct.InvoiceAnchorDate__c,
        '一括前払の請求基準日は開始日'
      );
      System.assertEquals(null, contractProduct.InvoiceBillingCycleCount__c);
    }
  }

  @IsTest
  static void amount_isNotRecalculatedByTrigger() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Amount Trigger Account'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Amount Trigger Service',
        Account__c = account.Id
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Amount Trigger History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 4, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 3, 31)
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Amount Trigger Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      // 画面確認値として、数量×単価×月数(144000)とは異なる値を明示保存する
      Decimal screenConfirmedAmount = 99999;
      ContractProduct__c contractProduct = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 12000,
        Amount__c = screenConfirmedAmount,
        StartDate__c = Date.newInstance(2026, 4, 1),
        Enddate__c = Date.newInstance(2027, 3, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert contractProduct;

      contractProduct = [
        SELECT Amount__c
        FROM ContractProduct__c
        WHERE Id = :contractProduct.Id
      ];
      System.assertEquals(
        screenConfirmedAmount,
        contractProduct.Amount__c,
        'Trigger は Amount を再計算上書きしない'
      );

      history = [
        SELECT DeltaAmountSum__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(screenConfirmedAmount, history.DeltaAmountSum__c);
    }
  }

  @IsTest
  static void amount_originalKeepsProvidedValue() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Original Amount Account'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Original Amount Service',
        Account__c = account.Id
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Original Amount History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = Date.newInstance(2026, 4, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 3, 31)
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Original Amount Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      Decimal screenConfirmedAmount = -55555;
      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 12000,
        Amount__c = screenConfirmedAmount,
        StartDate__c = Date.newInstance(2026, 4, 1),
        Enddate__c = Date.newInstance(2027, 3, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original'
      );

      ContractProduct__c originalProduct = [
        SELECT Amount__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :history.Id
        LIMIT 1
      ];
      System.assertEquals(
        screenConfirmedAmount,
        originalProduct.Amount__c,
        'Original でも Trigger は符号再計算しない'
      );
    }
  }

  @IsTest
  static void populateInvoiceAnchorFields_monthlySplitStoresCycleCount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Anchor Monthly Account');
      ContractService__c service = new ContractService__c(
        Name = 'Anchor Monthly Service',
        Account__c = account.Id
      );
      insert service;

      Date startDate = Date.newInstance(2025, 8, 1);
      Date endDate = Date.newInstance(2026, 7, 31);
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Anchor Monthly History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = startDate,
        CurrentTermEndDate__c = endDate,
        EffectiveDate__c = startDate
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct('Anchor Monthly Product');
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c contractProduct = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        StartDate__c = startDate,
        Enddate__c = endDate,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert contractProduct;

      contractProduct = [
        SELECT InvoiceAnchorDate__c, InvoiceBillingCycleCount__c
        FROM ContractProduct__c
        WHERE Id = :contractProduct.Id
      ];
      System.assertEquals(startDate, contractProduct.InvoiceAnchorDate__c);
      System.assertEquals(12, contractProduct.InvoiceBillingCycleCount__c);
    }
  }

  @IsTest
  static void populateAccount_ignoresNullAndEmpty() {
    ContractProductTriggerHandler.populateAccountFromContractHistory(null);
    ContractProductTriggerHandler.populateAccountFromContractHistory(
      new List<ContractProduct__c>()
    );
    ContractProductTriggerHandler.handleAfterChange(
      new List<ContractProduct__c>(),
      null
    );
    ContractProductTriggerHandler.handleAfterDelete(
      new List<ContractProduct__c>()
    );
    // ここに到達できれば null／空入力でも例外なし
    System.assertEquals(
      0,
      new List<ContractProduct__c>().size(),
      'null／空入力でも例外にならないこと'
    );
  }

  @IsTest
  static void handleAfterChangeAndDelete_recalculatesArrWithoutChangingAmount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'After Change Account'
      );
      ContractService__c service = new ContractService__c(
        Name = 'After Change Service',
        Account__c = account.Id
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'After Change History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 4, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 3, 31)
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'After Change Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.IncludeInARR__c = true;
      ContractTestDataFactory.insertProduct(product);

      Decimal screenConfirmedAmount = 77777;
      ContractProduct__c contractProduct = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 12000,
        Amount__c = screenConfirmedAmount,
        StartDate__c = Date.newInstance(2026, 4, 1),
        Enddate__c = Date.newInstance(2027, 3, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert contractProduct;

      contractProduct.Quantity__c = 2;
      update contractProduct;

      contractProduct = [
        SELECT Amount__c
        FROM ContractProduct__c
        WHERE Id = :contractProduct.Id
      ];
      System.assertEquals(
        screenConfirmedAmount,
        contractProduct.Amount__c,
        'update 後も Amount は上書きされない'
      );

      delete contractProduct;
      history = [
        SELECT DeltaAmountSum__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(
        0,
        history.DeltaAmountSum__c == null ? 0 : history.DeltaAmountSum__c,
        'delete 後は発生金額が再集計される'
      );
    }
  }
}
