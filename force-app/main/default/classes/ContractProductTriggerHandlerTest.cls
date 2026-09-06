@IsTest
private class ContractProductTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  private static ContractService__c insertService(Id accountId, String name) {
    return ContractTestDataFactory.insertContractService(accountId, name);
  }

  private static ContractHistory__c insertEstimateHistory(
    Id serviceId,
    Id accountId,
    String name,
    String historyType,
    Decimal version,
    Date termStart,
    Date termEnd,
    Id previousHistoryId
  ) {
    ContractHistory__c history = new ContractHistory__c(
      Name = name,
      ContractService__c = serviceId,
      Type__c = historyType,
      historystatus__c = 'Estimate',
      Version__c = version,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = termStart,
      PreviousHistory__c = previousHistoryId
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, accountId);
    insert history;
    return history;
  }

  private static ContractProduct__c insertLine(
    Id historyId,
    Id accountId,
    Product2 product,
    Decimal quantity,
    Decimal unitPrice,
    Decimal amount,
    Date startDate,
    Date endDate,
    String invoiceSetting,
    String billingType,
    String productType
  ) {
    ContractProduct__c line = new ContractProduct__c(
      ContractHistory__c = historyId,
      Account__c = accountId,
      Product__c = product.Id,
      Quantity__c = quantity,
      UnitPrice__c = unitPrice,
      Amount__c = amount,
      StartDate__c = startDate,
      Enddate__c = endDate,
      InvoiceSetting__c = invoiceSetting,
      BillingType__c = billingType,
      Type__c = productType,
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
    );
    if (amount == null) {
      line.Amount__c = null;
    }
    ContractTestDataFactory.applyRequiredFields(line);
    if (amount != null) {
      line.Amount__c = amount;
    }
    insert line;
    return line;
  }

  @IsTest
  static void populateAccountFromContractHistory_setsAccountFromService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Trigger Test Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'Trigger Test Service'
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Trigger Test History',
        'New',
        1,
        termStart,
        termEnd,
        null
      );
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
        Amount__c = 12000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New',
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
      );
      ContractTestDataFactory.applyRequiredFields(contractProduct);
      contractProduct.Account__c = null;
      insert contractProduct;

      contractProduct = [
        SELECT
          Account__c,
          ContractHistory__c,
          InvoiceAnchorDate__c,
          InvoiceBillingCycleCount__c,
          StartDate__c,
          Enddate__c,
          InvoiceSetting__c,
          BillingType__c,
          Type__c
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

      ContractProduct__c accountProbe = new ContractProduct__c(
        Id = contractProduct.Id,
        ContractHistory__c = history.Id,
        Account__c = null
      );
      ContractProductTriggerHandler.populateAccountFromContractHistory(
        new List<ContractProduct__c>{ accountProbe }
      );
      System.assertEquals(
        account.Id,
        accountProbe.Account__c,
        'Core 第4.6節: 空の取引先は契約サービスから埋める'
      );
      ContractProductTriggerHandler.populateInvoiceAnchorFields(
        new List<ContractProduct__c>{ contractProduct }
      );
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        contractProduct.InvoiceAnchorDate__c,
        '請求基準は InvoiceAnchorDateUtil'
      );
      Account otherAccount = ContractTestDataFactory.insertAccount(
        'Trigger Keep Account'
      );
      ContractProduct__c keepAccount = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Account__c = otherAccount.Id
      );
      ContractProductTriggerHandler.populateAccountFromContractHistory(
        new List<ContractProduct__c>{ keepAccount }
      );
      System.assertEquals(
        otherAccount.Id,
        keepAccount.Account__c,
        'Core 第4.6節: 空の取引先だけ契約サービスから埋める。既にあれば上書きしない'
      );
    }
  }

  @IsTest
  static void handleBeforeInsert_skipsHistoryQueryWhenAccountAndAnchorSet() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Skip History Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'Skip History Service'
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Skip History',
        'New',
        1,
        termStart,
        termEnd,
        null
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Skip History Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      EstimateCreateController.ProductLineItem line = new EstimateCreateController.ProductLineItem();
      line.productId = product.Id;
      line.quantity = 1;
      line.unitPrice = 1000;
      line.amount = 12000;
      line.startDate = String.valueOf(termStart);
      line.endDate = String.valueOf(termEnd);
      line.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      line.billingType = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      line.revenueRecognitionBasis = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      ContractProduct__c built = EstimateSaveService.buildContractProduct(
        history.Id,
        account.Id,
        line,
        product,
        'New',
        termStart
      );
      System.assertEquals(account.Id, built.Account__c);
      System.assertNotEquals(null, built.InvoiceAnchorDate__c);
      Integer queriesBefore = Limits.getQueries();
      ContractProductTriggerHandler.handleBeforeInsertOrUpdate(
        new List<ContractProduct__c>{ built }
      );
      System.assertEquals(
        queriesBefore,
        Limits.getQueries(),
        'Core 第12.4節: insert で本体が書いた Account と請求アンカーがある行は履歴を取り直さない'
      );
      System.assertEquals(account.Id, built.Account__c);
      System.assertEquals(termStart, built.InvoiceAnchorDate__c);
    }
  }

  @IsTest
  static void amount_isNotRecalculatedByTrigger() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Amount Trigger Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'Amount Trigger Service'
      );
      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2027, 3, 31);
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Amount Trigger History',
        'New',
        1,
        termStart,
        termEnd,
        null
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Amount Trigger Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      Decimal screenConfirmedAmount = 99999;
      ContractProduct__c contractProduct = insertLine(
        history.Id,
        account.Id,
        product,
        1,
        12000,
        screenConfirmedAmount,
        termStart,
        termEnd,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        'New'
      );

      contractProduct = [
        SELECT Amount__c
        FROM ContractProduct__c
        WHERE Id = :contractProduct.Id
      ];
      System.assertEquals(
        screenConfirmedAmount,
        contractProduct.Amount__c,
        'Core 第4.6節: 見積商品金額はウィザードで確認・保存した税抜であり、Triggerは再計算上書きしない'
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
      ContractService__c service = insertService(
        account.Id,
        'Original Amount Service'
      );
      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2027, 3, 31);
      ContractHistory__c prior = insertEstimateHistory(
        service.Id,
        account.Id,
        'Original Amount Prior',
        'New',
        1,
        termStart,
        termEnd,
        null
      );
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Original Amount History',
        'Change',
        2,
        termStart,
        termEnd,
        prior.Id
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Original Amount Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      Decimal screenConfirmedAmount = -55555;
      insertLine(
        history.Id,
        account.Id,
        product,
        1,
        12000,
        screenConfirmedAmount,
        termStart,
        termEnd,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        'Original'
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
      Account account = ContractTestDataFactory.insertAccount(
        'Anchor Monthly Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'Anchor Monthly Service'
      );
      Date startDate = Date.newInstance(2025, 8, 1);
      Date endDate = Date.newInstance(2026, 7, 31);
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Anchor Monthly History',
        'New',
        1,
        startDate,
        endDate,
        null
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Anchor Monthly Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c contractProduct = insertLine(
        history.Id,
        account.Id,
        product,
        1,
        1000,
        12000,
        startDate,
        endDate,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        'New'
      );

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
    ContractProductTriggerHandler.handleBeforeInsertOrUpdate(null);
    ContractProductTriggerHandler.handleBeforeInsertOrUpdate(
      new List<ContractProduct__c>()
    );
    ContractProductTriggerHandler.populateAccountFromContractHistory(null);
    ContractProductTriggerHandler.populateAccountFromContractHistory(
      new List<ContractProduct__c>()
    );
    ContractProductTriggerHandler.populateInvoiceAnchorFields(null);
    ContractProductTriggerHandler.populateInvoiceAnchorFields(
      new List<ContractProduct__c>()
    );
    ContractProductTriggerHandler.handleAfterChange(
      new List<ContractProduct__c>(),
      null
    );
    ContractProductTriggerHandler.handleAfterDelete(
      new List<ContractProduct__c>()
    );
    ContractProduct__c untouched = new ContractProduct__c(
      Amount__c = 12345
    );
    ContractProductTriggerHandler.handleBeforeInsertOrUpdate(
      new List<ContractProduct__c>{ untouched }
    );
    System.assertEquals(
      12345,
      untouched.Amount__c,
      'Core 第4.6節: 見積商品金額はウィザードで確認・保存した税抜であり、Triggerは再計算上書きしない'
    );
  }

  @IsTest
  static void handleAfterChangeAndDelete_recalculatesArrWithoutChangingAmount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'After Change Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'After Change Service'
      );
      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2027, 3, 31);
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'After Change History',
        'New',
        1,
        termStart,
        termEnd,
        null
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'After Change Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.IncludeInARR__c = true;
      ContractTestDataFactory.insertProduct(product);
      Decimal screenConfirmedAmount = 77777;
      ContractProduct__c contractProduct = insertLine(
        history.Id,
        account.Id,
        product,
        1,
        12000,
        screenConfirmedAmount,
        termStart,
        termEnd,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        'New'
      );

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

  @IsTest
  static void handleAfterChange_skipsLifecycleQueryForEstimateProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Skip Lifecycle Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'Skip Lifecycle Service'
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Skip Lifecycle History',
        'New',
        1,
        termStart,
        termEnd,
        null
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Skip Lifecycle Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c line = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Account__c = account.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New',
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
      );
      Integer queriesBeforeArr = Limits.getQueries();
      ContractArrCalculationService.recalculateForHistories(
        new Set<Id>{ history.Id }
      );
      Integer arrQueries = Limits.getQueries() - queriesBeforeArr;
      Integer queriesBeforeHandler = Limits.getQueries();
      ContractProductTriggerHandler.handleAfterChange(
        new List<ContractProduct__c>{ line },
        null
      );
      System.assertEquals(
        arrQueries,
        Limits.getQueries() - queriesBeforeHandler,
        'Core 第5.4節: 未受注 Estimate の見積商品 after は Lifecycle 判定で履歴を照会しない'
      );
    }
  }
}
