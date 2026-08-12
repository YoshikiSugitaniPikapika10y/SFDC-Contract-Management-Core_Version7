/**
 * generateForHistories API の境界専用（厚い Generation/Amount スイートとは役割分担）。
 * - Cancel Ordered を直接 generateForHistories しても期間明細 0
 * - 短い月次 New（6–8月）で件数・行金額・合計を厳密断言
 * GenerationServiceTest / AmountAccuracyAuditTest に吸収しない（直接 API 境界を残す）。
 */
@IsTest
private class InvoiceProductGenerationHardeningTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void generateForHistories_cancelOnly_skipsLineGeneration() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'IPG Cancel Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'IPG Cancel Service'
      );

      ContractHistory__c cancelHistory = new ContractHistory__c(
        Name = 'IPG Cancel History',
        ContractService__c = service.Id,
        Type__c = 'Cancel',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 6, 1),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insert cancelHistory;

      Test.startTest();
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ cancelHistory.Id }
      );
      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :cancelHistory.Id
        ],
        'Cancel は期間明細を作らない'
      );
    }
  }

  @IsTest
  static void generateForHistories_newOrdered_buildsMonthlyLines() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'IPG New Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'IPG New Service'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'IPG New History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 8, 31)
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'IPG New Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
      product.UnitPrice__c = 1000;
      product.UnitName__c = 'ID';
      ContractTestDataFactory.insertProduct(product);

      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 3000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 8, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      history.historystatus__c = 'Ordered';
      Test.startTest();
      update history;
      Test.stopTest();

      List<InvoiceProduct__c> lines = [
        SELECT Amount__c, StartDate__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :history.Id
        ORDER BY StartDate__c ASC
      ];
      System.assertEquals(3, lines.size(), '6–8月の月次3行');
      System.assertEquals(1000, lines[0].Amount__c);
      System.assertEquals(1000, lines[1].Amount__c);
      System.assertEquals(1000, lines[2].Amount__c);
      System.assertEquals(
        3000,
        lines[0].Amount__c + lines[1].Amount__c + lines[2].Amount__c,
        '期間明細合計 3000'
      );
    }
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
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    ContractService__c service = new ContractService__c(
      Name = serviceName,
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    insert service;
    return service;
  }
}
