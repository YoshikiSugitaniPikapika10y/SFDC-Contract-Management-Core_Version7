@IsTest
private class InvoiceProductGenerationServiceTest {
  @TestSetup
  static void setupAccountingPolicy() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  /** 仕様: Core 第4.1節。Estimate・Ordered の契約履歴は商談必須。 */
  private static void insertHistory(ContractHistory__c history) {
    if (history.Opportunity__c == null && history.ContractService__c != null) {
      ContractService__c service = [
        SELECT Account__c
        FROM ContractService__c
        WHERE Id = :history.ContractService__c
      ];
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        service.Account__c,
        history.Name + ' Opp'
      );
      history.Opportunity__c = opportunity.Id;
    }
    insert history;
  }

  /** 仕様: Core 第1.1.10節・第4.5.2節。見積商品の売上計上基準は空にしない。 */
  private static void stampRevenueRecognitionBasis(Set<Id> historyIds) {
    if (historyIds == null || historyIds.isEmpty()) {
      return;
    }
    List<ContractProduct__c> rows = [
      SELECT Id, Product__r.RevenueRecognitionBasis__c, RevenueRecognitionBasis__c
      FROM ContractProduct__c
      WHERE ContractHistory__c IN :historyIds AND RevenueRecognitionBasis__c = NULL
    ];
    for (ContractProduct__c row : rows) {
      row.RevenueRecognitionBasis__c = row.Product__r.RevenueRecognitionBasis__c;
    }
    if (!rows.isEmpty()) {
      update rows;
    }
  }

  private static void generateInvoiceProducts(Set<Id> historyIds) {
    stampRevenueRecognitionBasis(historyIds);
    InvoiceProductGenerationService.generateForHistories(historyIds);
  }

  private static void prepareHistoryForOrder(ContractHistory__c history) {
    stampRevenueRecognitionBasis(new Set<Id>{ history.Id });
    if (history != null && history.Type__c == 'Change') {
      syncChangeOriginalsToPrevious(history.Id);
      syncChangeRemakeLockedFieldsToPrevious(history.Id);
    }
  }

  private static void commitOrder(ContractHistory__c history) {
    if (history.historystatus__c == 'Ordered') {
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ history.Id }
      );
      return;
    }
    history.historystatus__c = 'Ordered';
    update history;
  }

  private static void orderHistory(ContractHistory__c history) {
    prepareHistoryForOrder(history);
    commitOrder(history);
  }

  /** 仕様: Core 第4.4節。Original は前回見積商品と一致し、税抜だけ符号反転する。 */
  private static void syncChangeOriginalsToPrevious(Id changeHistoryId) {
    List<ContractProduct__c> originals = [
      SELECT Id, PreviousContractProduct__c, UnitPrice__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :changeHistoryId AND Type__c = 'Original'
    ];
    Set<Id> previousIds = new Set<Id>();
    for (ContractProduct__c original : originals) {
      if (original.PreviousContractProduct__c != null) {
        previousIds.add(original.PreviousContractProduct__c);
      }
    }
    if (previousIds.isEmpty()) {
      return;
    }
    Map<Id, ContractProduct__c> previousById = new Map<Id, ContractProduct__c>(
      [
        SELECT
          Product__c,
          Quantity__c,
          UnitPrice__c,
          Amount__c,
          StartDate__c,
          Enddate__c,
          InvoiceSetting__c,
          BillingType__c,
          RevenueRecognitionBasis__c,
          Unit__c
        FROM ContractProduct__c
        WHERE Id IN :previousIds
      ]
    );
    List<ContractProduct__c> updates = new List<ContractProduct__c>();
    for (ContractProduct__c original : originals) {
      ContractProduct__c source = previousById.get(
        original.PreviousContractProduct__c
      );
      if (source == null) {
        continue;
      }
      Boolean keepUnmatchedOriginal =
        original.UnitPrice__c != null &&
        source.UnitPrice__c != null &&
        original.UnitPrice__c != source.UnitPrice__c;
      if (!keepUnmatchedOriginal) {
        original.Product__c = source.Product__c;
        original.Quantity__c = source.Quantity__c;
        original.UnitPrice__c = source.UnitPrice__c;
        original.StartDate__c = source.StartDate__c;
        original.Enddate__c = source.Enddate__c;
        original.Unit__c = source.Unit__c;
      }
      original.InvoiceSetting__c = source.InvoiceSetting__c;
      original.BillingType__c = source.BillingType__c;
      original.RevenueRecognitionBasis__c = source.RevenueRecognitionBasis__c;
      updates.add(original);
    }
    if (!updates.isEmpty()) {
      update updates;
    }
  }

  /** 仕様: Core 第4.4.3節。Remake の請求設定と売上計上基準は前回値のまま。 */
  private static void syncChangeRemakeLockedFieldsToPrevious(Id changeHistoryId) {
    List<ContractProduct__c> remakes = [
      SELECT Id, PreviousContractProduct__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :changeHistoryId AND Type__c = 'Remake'
    ];
    Set<Id> previousIds = new Set<Id>();
    for (ContractProduct__c remake : remakes) {
      if (remake.PreviousContractProduct__c != null) {
        previousIds.add(remake.PreviousContractProduct__c);
      }
    }
    if (previousIds.isEmpty()) {
      return;
    }
    Map<Id, ContractProduct__c> previousById = new Map<Id, ContractProduct__c>(
      [
        SELECT InvoiceSetting__c, RevenueRecognitionBasis__c
        FROM ContractProduct__c
        WHERE Id IN :previousIds
      ]
    );
    List<ContractProduct__c> updates = new List<ContractProduct__c>();
    for (ContractProduct__c remake : remakes) {
      ContractProduct__c source = previousById.get(
        remake.PreviousContractProduct__c
      );
      if (source == null) {
        continue;
      }
      remake.InvoiceSetting__c = source.InvoiceSetting__c;
      remake.RevenueRecognitionBasis__c = source.RevenueRecognitionBasis__c;
      updates.add(remake);
    }
    if (!updates.isEmpty()) {
      update updates;
    }
  }

  /** 仕様: Core 第1.3節・第4.4節。Term の一回課金追加でも前回継続課金の Original/Remake を持つ。同条件なら請求差分は作らない。 */
  private static void insertUnchangedOriginalAndRemake(
    Id changeHistoryId,
    ContractProduct__c prior
  ) {
    insert new List<ContractProduct__c>{
      new ContractProduct__c(
        ContractHistory__c = changeHistoryId,
        Product__c = prior.Product__c,
        Quantity__c = prior.Quantity__c,
        UnitPrice__c = prior.UnitPrice__c,
        Amount__c = -1,
        StartDate__c = prior.StartDate__c,
        Enddate__c = prior.Enddate__c,
        InvoiceSetting__c = prior.InvoiceSetting__c,
        BillingType__c = prior.BillingType__c,
        Type__c = 'Original',
        PreviousContractProduct__c = prior.Id
      ),
      new ContractProduct__c(
        ContractHistory__c = changeHistoryId,
        Product__c = prior.Product__c,
        Quantity__c = prior.Quantity__c,
        UnitPrice__c = prior.UnitPrice__c,
        Amount__c = 1,
        StartDate__c = prior.StartDate__c,
        Enddate__c = prior.Enddate__c,
        InvoiceSetting__c = prior.InvoiceSetting__c,
        BillingType__c = prior.BillingType__c,
        Type__c = 'Remake',
        PreviousContractProduct__c = prior.Id
      )
    };
  }

  private static void updateInvoicesAllowingStatus(List<Invoice__c> invoices) {
    Boolean previous = InvoiceTransactionStatusService.allowStatusWrite;
    InvoiceTransactionStatusService.allowStatusWrite = true;
    try {
      update invoices;
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = previous;
    }
  }

  private static ContractService__c insertServiceWithBillingAccount(
    String name,
    Account account
  ) {
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END, PaymentTermMonthOffset__c = 1, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER, InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY, InvoiceDateDayOfMonth__c = 1, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com'
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    ContractService__c service = new ContractService__c(
      Name = name,
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    insert service;
    return service;
  }

  @IsTest
  static void estimateToOrdered_throwsWhenCsAccountAndOpportunityAccountMismatch() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account serviceAccount = ContractTestDataFactory.insertAccount(
        'CS Account Mismatch'
      );
      Account opportunityAccount = ContractTestDataFactory.insertAccount(
        'Opp Account Mismatch'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'Account Mismatch Service',
        serviceAccount
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        opportunityAccount.Id,
        'Account Mismatch Opp'
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Account Mismatch History',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(history);
      Product2 product = ContractTestDataFactory.buildProduct(
        'Account Mismatch Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      Boolean thrown = false;
      Test.startTest();
      try {
        orderHistory(history);
      } catch (Exception ex) {
        thrown = true;
        String message = dmlMessage(ex);
        System.assert(
          message.startsWith(
            '契約サービスの取引先と商談の取引先が一致しません'
          ),
          'Core 第4.1節: ' + message
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown, 'Core 第4.1節: 取引先不一致は受注しない');
      System.assertEquals(
        'Estimate',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ]
        .historystatus__c,
        '????E Estimate ???'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :history.Id
        ],
        '?????E???????E????E???'
      );
    }
  }

  @IsTest
  static void estimateToOrdered_succeedsWhenCsAccountMatchesOpportunityAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'CS Opp Account Match'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'Account Match Service',
        account
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Account Match Opp'
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Account Match History',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(history);
      Product2 product = ContractTestDataFactory.buildProduct(
        'Account Match Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      Test.startTest();
      orderHistory(history);
      Test.stopTest();

      System.assert(
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :history.Id
        ] > 0,
        '???E????E???????E?????'
      );
    }
  }

  @IsTest
  static void estimateToOrdered_createsMonthlyInvoiceProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      Test.startTest();
      orderHistory(data.history);
      Test.stopTest();
      List<InvoiceProduct__c> invoiceProducts = [
        SELECT StartDate__c, Enddate__c, Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id
        ORDER BY StartDate__c ASC
      ];
      System.assertEquals(12, invoiceProducts.size());
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        invoiceProducts[0].StartDate__c
      );
      System.assertEquals(
        Date.newInstance(2026, 6, 30),
        invoiceProducts[0].Enddate__c
      );
      System.assertEquals(8000, invoiceProducts[0].Amount__c);
      List<Invoice__c> invoices = [
        SELECT InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :data.history.Id
        ORDER BY InvoiceDate__c ASC
      ];
      System.assert(!invoices.isEmpty(), '???E?E?????E?????');
      for (Invoice__c invoice : invoices) {
        System.assertEquals(
          Date.newInstance(2026, 6, 1),
          invoice.InvoiceDate__c,
          '????E???E?????????????????'
        );
      }
      System.assertEquals(
        96000,
        [
            SELECT SUM(Amount__c) totalAmount
            FROM InvoiceProduct__c
            WHERE ContractHistory__c = :data.history.Id
          ][0]
          .get('totalAmount')
      );
      System.assertEquals(
        96000,
        [
            SELECT SUM(Amount__c) totalAmount
            FROM Invoice__c
            WHERE ContractHistory__c = :data.history.Id
          ][0]
          .get('totalAmount'),
        '???????????????????'
      );
    }
  }
  @IsTest
  static void estimateToOrdered_usesContractServiceTaxPercent() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      update new ContractService__c(
        Id = data.history.ContractService__c,
        TaxPercent__c = 0.08
      );
      Test.startTest();
      orderHistory(data.history);
      Test.stopTest();
      InvoiceProduct__c invoiceProduct = [
        SELECT Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id
        ORDER BY StartDate__c ASC
        LIMIT 1
      ];
      System.assertEquals(8000, invoiceProduct.Amount__c);
      Invoice__c invoice = [
        SELECT TaxPercent__c
        FROM Invoice__c
        WHERE ContractHistory__c = :data.history.Id
        LIMIT 1
      ];
      System.assertEquals(
        8,
        TaxCalculationUtil.resolveTaxPercent(
          TaxCalculationUtil.fromPercentFieldStorage(invoice.TaxPercent__c)
        )
      );
    }
  }
  @IsTest
  static void estimateToOrdered_createsPositiveInvoiceProductsOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(true);
      Test.startTest();
      orderHistory(data.history);
      Test.stopTest();
      List<InvoiceProduct__c> invoiceProducts = [
        SELECT Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id
        ORDER BY Amount__c ASC
      ];
      System.assertEquals(12, invoiceProducts.size());
      System.assertEquals(8000, invoiceProducts[0].Amount__c);
      for (InvoiceProduct__c invoiceProduct : invoiceProducts) {
        System.assert(invoiceProduct.Amount__c > 0);
      }
    }
  }
  @IsTest
  static void estimateToOrdered_copiesQuantityUnitPriceAndUnit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      data.recurringProduct.Unit__c = 'ID';
      update data.recurringProduct;
      Test.startTest();
      orderHistory(data.history);
      Test.stopTest();
      InvoiceProduct__c invoiceProduct = [
        SELECT
          Unit__c,
          Amount__c,
          ContractProduct__r.Quantity__c,
          ContractProduct__r.UnitPrice__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id
        ORDER BY StartDate__c ASC
        LIMIT 1
      ];
      System.assertEquals(1, invoiceProduct.ContractProduct__r.Quantity__c);
      System.assertEquals(8000, invoiceProduct.ContractProduct__r.UnitPrice__c);
      System.assertEquals('ID', invoiceProduct.Unit__c);
      System.assertEquals(8000, invoiceProduct.Amount__c);
    }
  }
  @IsTest
  static void estimateToOrdered_createsSeparateLinesForDifferentUnit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      data.recurringProduct.Unit__c = 'ID';
      update data.recurringProduct;
      insert new ContractProduct__c(
        ContractHistory__c = data.history.Id,
        Product__c = data.recurringProduct.Product__c,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        Unit__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
        StartDate__c = data.recurringProduct.StartDate__c,
        Enddate__c = data.recurringProduct.Enddate__c,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Renew'
      );
      Test.startTest();
      orderHistory(data.history);
      Test.stopTest();
      List<InvoiceProduct__c> juneLines = [
        SELECT Unit__c, Amount__c
        FROM InvoiceProduct__c
        WHERE
          ContractHistory__c = :data.history.Id
          AND StartDate__c = :Date.newInstance(2026, 6, 1)
        ORDER BY Unit__c ASC
      ];
      System.assertEquals(2, juneLines.size());
      System.assertEquals('ID', juneLines[0].Unit__c);
      System.assertEquals(8000, juneLines[0].Amount__c);
      System.assertEquals(
        ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
        juneLines[1].Unit__c
      );
      System.assertEquals(8000, juneLines[1].Amount__c);
    }
  }
  @IsTest
  static void estimateToOrdered_copiesQuantityAndUnitPrice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      Test.startTest();
      orderHistory(data.history);
      Test.stopTest();
      InvoiceProduct__c invoiceProduct = [
        SELECT
          Amount__c,
          ContractProduct__r.Quantity__c,
          ContractProduct__r.UnitPrice__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id
        ORDER BY StartDate__c ASC
        LIMIT 1
      ];
      System.assertEquals(1, invoiceProduct.ContractProduct__r.Quantity__c);
      System.assertEquals(8000, invoiceProduct.ContractProduct__r.UnitPrice__c);
      System.assertEquals(8000, invoiceProduct.Amount__c);
    }
  }
  @IsTest
  static void estimateToOrdered_createsSeparateLinesForDifferentQuantityUnitPrice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      insert new ContractProduct__c(
        ContractHistory__c = data.history.Id,
        Product__c = data.recurringProduct.Product__c,
        Quantity__c = 2,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = data.recurringProduct.StartDate__c,
        Enddate__c = data.recurringProduct.Enddate__c,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Renew'
      );
      Test.startTest();
      orderHistory(data.history);
      Test.stopTest();
      List<InvoiceProduct__c> juneLines = [
        SELECT
          Amount__c,
          ContractProduct__r.Quantity__c,
          ContractProduct__r.UnitPrice__c
        FROM InvoiceProduct__c
        WHERE
          ContractHistory__c = :data.history.Id
          AND StartDate__c = :Date.newInstance(2026, 6, 1)
        ORDER BY ContractProduct__r.Quantity__c ASC
      ];
      System.assertEquals(2, juneLines.size());
      System.assertEquals(1, juneLines[0].ContractProduct__r.Quantity__c);
      System.assertEquals(8000, juneLines[0].ContractProduct__r.UnitPrice__c);
      System.assertEquals(8000, juneLines[0].Amount__c);
      System.assertEquals(2, juneLines[1].ContractProduct__r.Quantity__c);
      System.assertEquals(8000, juneLines[1].ContractProduct__r.UnitPrice__c);
      System.assertEquals(16000, juneLines[1].Amount__c);
    }
  }
  @IsTest
  static void estimateToOrdered_createsMonthlyInvoiceSettingProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      Product2 monthlyInvoiceProduct = ContractTestDataFactory.buildProduct(
        'Monthly Invoice Product'
      );
      monthlyInvoiceProduct.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      monthlyInvoiceProduct.UnitPrice__c = 3000;
      monthlyInvoiceProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
      monthlyInvoiceProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(monthlyInvoiceProduct);
      insert new ContractProduct__c(
        ContractHistory__c = data.history.Id,
        Product__c = monthlyInvoiceProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 3000,
        Amount__c = 1,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      Test.startTest();
      orderHistory(data.history);
      Test.stopTest();
      List<InvoiceProduct__c> monthlyPeriodLines = [
        SELECT StartDate__c, Enddate__c, Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id AND Amount__c = 3000
        ORDER BY StartDate__c ASC
      ];
      System.assertEquals(12, monthlyPeriodLines.size());
      System.assertEquals(3000, monthlyPeriodLines[0].Amount__c);
      // ????????????????? Invoice ??E??E????????E
      // ???E??? InvoiceLine ????????????
      List<InvoiceLine__c> monthlyLines = [
        SELECT Invoice__r.InvoiceDate__c, Amount__c
        FROM InvoiceLine__c
        WHERE
          Invoice__r.ContractHistory__c = :data.history.Id
          AND Amount__c = 3000
        ORDER BY Invoice__r.InvoiceDate__c ASC
      ];
      System.assertEquals(12, monthlyLines.size());
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        monthlyLines[0].Invoice__r.InvoiceDate__c
      );
      System.assertEquals(
        Date.newInstance(2026, 7, 1),
        monthlyLines[1].Invoice__r.InvoiceDate__c,
        '?????E?E??????????'
      );
      System.assertEquals(
        24,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :data.history.Id
        ]
      );
    }
  }
  @IsTest
  static void estimateToOrdered_usesMonthlyBillingDayAsInvoiceDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Calendar Month Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END, PaymentTermMonthOffset__c = 1, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER, InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY, InvoiceDateDayOfMonth__c = 5, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com'
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'Calendar Month Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Calendar Month History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 5),
        CurrentTermEndDate__c = Date.newInstance(2027, 6, 4)
      );
      insertHistory(history);
      Product2 monthlyProduct = ContractTestDataFactory.buildProduct(
        'Calendar Monthly Product'
      );
      monthlyProduct.UnitName__c = 'ID';
      monthlyProduct.UnitPrice__c = 5000;
      monthlyProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
      monthlyProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(monthlyProduct);
      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = monthlyProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 5000,
        Amount__c = 1,
        StartDate__c = Date.newInstance(2026, 6, 5),
        Enddate__c = Date.newInstance(2027, 6, 4),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      Test.startTest();
      orderHistory(history);
      Test.stopTest();
      InvoiceProduct__c firstPeriodLine = [
        SELECT StartDate__c, Enddate__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :history.Id
        ORDER BY StartDate__c ASC
        LIMIT 1
      ];
      System.assertEquals(
        Date.newInstance(2026, 6, 5),
        firstPeriodLine.StartDate__c
      );
      System.assertEquals(
        Date.newInstance(2026, 7, 4),
        firstPeriodLine.Enddate__c
      );
      Invoice__c firstInvoice = [
        SELECT InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
        ORDER BY InvoiceDate__c ASC
        LIMIT 1
      ];
      System.assertEquals(
        Date.newInstance(2026, 6, 5),
        firstInvoice.InvoiceDate__c
      );
    }
  }
  @IsTest
  static void estimateToOrdered_usesAfterBillingInvoiceDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      data.recurringProduct.InvoiceSetting__c = ContractMetadataService.INVOICE_SETTING_POSTPAID_NEXT_DAY;
      update data.recurringProduct;
      Test.startTest();
      orderHistory(data.history);
      Test.stopTest();
      InvoiceProduct__c firstPeriodLine = [
        SELECT Enddate__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id
        ORDER BY StartDate__c ASC
        LIMIT 1
      ];
      System.assertEquals(
        Date.newInstance(2026, 6, 30),
        firstPeriodLine.Enddate__c
      );
      Invoice__c firstInvoice = [
        SELECT InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :data.history.Id
        ORDER BY InvoiceDate__c ASC
        LIMIT 1
      ];
      System.assertEquals(
        Date.newInstance(2027, 6, 1),
        firstInvoice.InvoiceDate__c
      );
    }
  }
  @IsTest
  static void estimateToOrdered_createsOneTimeInvoiceProduct() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      Product2 oneTimeProduct = ContractTestDataFactory.buildProduct(
        'One Time Product'
      );
      oneTimeProduct.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      oneTimeProduct.UnitPrice__c = 100000;
      oneTimeProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(oneTimeProduct);
      Date startDate = Date.newInstance(2026, 6, 1);
      Date endDate = Date.newInstance(2026, 6, 30);
      insert new ContractProduct__c(
        ContractHistory__c = data.history.Id,
        Product__c = oneTimeProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 100000,
        Amount__c = 1,
        StartDate__c = startDate,
        Enddate__c = endDate,
        InvoiceSetting__c = ContractMetadataService.INVOICE_SETTING_POSTPAID_NEXT_DAY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = 'New'
      );
      Test.startTest();
      orderHistory(data.history);
      Test.stopTest();
      InvoiceProduct__c oneTimeInvoice = [
        SELECT StartDate__c, Enddate__c, Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id AND Amount__c = 100000
        LIMIT 1
      ];
      System.assertEquals(startDate, oneTimeInvoice.StartDate__c);
      System.assertEquals(endDate, oneTimeInvoice.Enddate__c);
      System.assertEquals(100000, oneTimeInvoice.Amount__c);
      Date expectedOneTimeInvoiceDate = endDate.addDays(1);
      Invoice__c oneTimeHeader = [
        SELECT InvoiceDate__c
        FROM Invoice__c
        WHERE
          ContractHistory__c = :data.history.Id
          AND InvoiceDate__c = :expectedOneTimeInvoiceDate
        LIMIT 1
      ];
      System.assertEquals(
        expectedOneTimeInvoiceDate,
        oneTimeHeader.InvoiceDate__c
      );
    }
  }
  @IsTest
  static void estimateToOrdered_mergesSameProductSamePeriodAmounts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      insert new ContractProduct__c(
        ContractHistory__c = data.history.Id,
        Product__c = data.recurringProduct.Product__c,
        Quantity__c = 1,
        UnitPrice__c = 2000,
        Amount__c = -1,
        StartDate__c = data.recurringProduct.StartDate__c,
        Enddate__c = data.recurringProduct.Enddate__c,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original'
      );
      Test.startTest();
      orderHistory(data.history);
      Test.stopTest();
      List<InvoiceProduct__c> invoiceProducts = [
        SELECT StartDate__c, Enddate__c, Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id
        ORDER BY StartDate__c ASC
      ];
      System.assertEquals(12, invoiceProducts.size());
      System.assertEquals(8000, invoiceProducts[0].Amount__c);
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        invoiceProducts[0].StartDate__c
      );
      System.assertEquals(
        Date.newInstance(2026, 6, 30),
        invoiceProducts[0].Enddate__c
      );
      System.assertEquals(
        96000,
        [
            SELECT SUM(Amount__c) totalAmount
            FROM InvoiceProduct__c
            WHERE ContractHistory__c = :data.history.Id
          ][0]
          .get('totalAmount')
      );
    }
  }
  @IsTest
  static void estimateToOrdered_excludesZeroAmountAfterMerge() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      insert new ContractProduct__c(
        ContractHistory__c = data.history.Id,
        Product__c = data.recurringProduct.Product__c,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = -1,
        StartDate__c = data.recurringProduct.StartDate__c,
        Enddate__c = data.recurringProduct.Enddate__c,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original'
      );
      Test.startTest();
      orderHistory(data.history);
      Test.stopTest();
      System.assertEquals(
        12,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :data.history.Id
        ]
      );
    }
  }
  @IsTest
  static void estimateToOrdered_regeneratesInvoiceProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      orderHistory(data.history);
      Integer firstCount = [
        SELECT COUNT()
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id
      ];
      System.assertEquals(12, firstCount);
      Test.startTest();
      data.history.historystatus__c = 'Estimate';
      update data.history;
      Product2 pricedProduct = new Product2(
        Id = data.recurringProduct.Product__c,
        UnitPrice__c = 9000
      );
      update pricedProduct;
      data.recurringProduct.UnitPrice__c = 9000;
      update data.recurringProduct;
      orderHistory(data.history);
      Test.stopTest();
      List<InvoiceProduct__c> regeneratedProducts = [
        SELECT Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id
      ];
      System.assertEquals(12, regeneratedProducts.size());
      System.assertEquals(9000, regeneratedProducts[0].Amount__c);
      System.assertEquals(
        108000,
        [
            SELECT SUM(Amount__c) totalAmount
            FROM InvoiceProduct__c
            WHERE ContractHistory__c = :data.history.Id
          ][0]
          .get('totalAmount')
      );
    }
  }
  @IsTest
  static void generateForHistories_preservesExportedInvoiceProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      orderHistory(data.history);
      InvoiceProduct__c firstPeriodLine = [
        SELECT Id, Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id
        ORDER BY StartDate__c ASC
        LIMIT 1
      ];
      List<Invoice__c> lockedInvoices = [
        SELECT Id, PaymentClearingCompletedDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :data.history.Id
      ];
      System.assert(
        !lockedInvoices.isEmpty(),
        '??????E????????????'
      );
      for (Invoice__c invoice : lockedInvoices) {
        invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
        invoice.CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_COMPLETED;
        invoice.PaymentClearingCompletedDate__c = Date.today();
      }
      updateInvoicesAllowingStatus(lockedInvoices);
      data.recurringProduct.UnitPrice__c = 9000;
      update data.recurringProduct;
      Boolean thrown = false;
      Test.startTest();
      try {
        generateInvoiceProducts(
          new Set<Id>{ data.history.Id }
        );
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      Test.stopTest();
      System.assertEquals(
        true,
        thrown,
        '??E????????????E????????'
      );
      InvoiceProduct__c preservedProduct = [
        SELECT Amount__c
        FROM InvoiceProduct__c
        WHERE Id = :firstPeriodLine.Id
      ];
      System.assertEquals(8000, preservedProduct.Amount__c);
      System.assertNotEquals(
        null,
        [
          SELECT PaymentClearingCompletedDate__c
          FROM Invoice__c
          WHERE Id = :lockedInvoices[0].Id
        ]
        .PaymentClearingCompletedDate__c
      );
    }
  }
  @IsTest
  static void estimateToOrdered_setsPaymentScheduledDateFromPaymentTerm() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      ContractService__c service = [
        SELECT Id, Account__c
        FROM ContractService__c
        WHERE Id = :data.history.ContractService__c
      ];
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = service.Account__c,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_DAY, PaymentTermDayOfMonth__c = 15, PaymentTermMonthOffset__c = 1, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER, InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY, InvoiceDateDayOfMonth__c = 25, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com'
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      service.BiilingAcccount__c = billingAccount.Id;
      update service;
      Test.startTest();
      orderHistory(data.history);
      Test.stopTest();
      Invoice__c firstInvoice = [
        SELECT InvoiceDate__c, PaymentScheduledDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :data.history.Id
        ORDER BY InvoiceDate__c ASC
        LIMIT 1
      ];
      System.assertEquals(
        Date.newInstance(2026, 6, 25),
        firstInvoice.InvoiceDate__c
      );
      System.assertEquals(
        Date.newInstance(2026, 7, 15),
        firstInvoice.PaymentScheduledDate__c
      );
    }
  }
  @IsTest
  static void estimateToOrdered_usesBillingAccountDayForMonthlyInvoiceDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Billing Day Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER, InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY, InvoiceDateDayOfMonth__c = 25, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END, PaymentTermMonthOffset__c = 1, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com'
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'Billing Day Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Billing Day History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 5),
        CurrentTermEndDate__c = Date.newInstance(2027, 6, 4)
      );
      insertHistory(history);
      Product2 monthlyProduct = ContractTestDataFactory.buildProduct(
        'Billing Day Product'
      );
      monthlyProduct.UnitName__c = 'ID';
      monthlyProduct.UnitPrice__c = 5000;
      monthlyProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
      monthlyProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(monthlyProduct);
      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = monthlyProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 5000,
        Amount__c = 1,
        StartDate__c = Date.newInstance(2026, 6, 5),
        Enddate__c = Date.newInstance(2027, 6, 4),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      Test.startTest();
      orderHistory(history);
      Test.stopTest();
      Invoice__c firstInvoice = [
        SELECT InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
        ORDER BY InvoiceDate__c ASC
        LIMIT 1
      ];
      System.assertEquals(
        Date.newInstance(2026, 6, 25),
        firstInvoice.InvoiceDate__c
      );
    }
  }
  @IsTest
  static void estimateToOrdered_prepaidUsesBillingAccountDayForBulkInvoiceDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Prepaid Billing Day Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER, InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY, InvoiceDateDayOfMonth__c = 5, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END, PaymentTermMonthOffset__c = 1, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com'
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'Prepaid Billing Day Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Prepaid Billing Day History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insertHistory(history);
      Product2 product = ContractTestDataFactory.buildProduct(
        'Prepaid Billing Day Product'
      );
      product.UnitName__c = 'ID';
      product.UnitPrice__c = 8000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      Test.startTest();
      orderHistory(history);
      Test.stopTest();
      System.assertEquals(
        12,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :history.Id
        ]
      );
      List<Invoice__c> invoices = [
        SELECT InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
        ORDER BY InvoiceDate__c ASC
      ];
      System.assert(!invoices.isEmpty(), '???E?E?????E?????');
      for (Invoice__c invoice : invoices) {
        System.assertEquals(
          Date.newInstance(2026, 6, 5),
          invoice.InvoiceDate__c,
          '?????????????E???????????????'
        );
      }
    }
  }
  @IsTest
  static void estimateToOrdered_copiesBillingAccountSnapShots() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceProductFieldCopyService.resetCache();
      Account account = ContractTestDataFactory.insertAccount(
        'Snapshot Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_DAY, PaymentTermDayOfMonth__c = 15, PaymentTermMonthOffset__c = 1, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER, InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY, InvoiceDateDayOfMonth__c = 25, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        BillingAddressee__c = '???????????E?? ??',
        BillingEmailTo__c = 'billing-to@example.com',
        BillingEmailCc__c = 'billing-cc@example.com',
        BillingEmailBcc__c = 'billing-bcc@example.com',
        InvoiceDeliveryMethod__c = InvoiceDeliveryMethodService.EMAIL
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'Snapshot Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Snapshot Opportunity'
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Snapshot Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Snapshot History',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insertHistory(history);
      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New',
        Unit__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT
      );
      Test.startTest();
      orderHistory(history);
      Test.stopTest();
      InvoiceProduct__c invoiceProduct = [
        SELECT
          Quantity__c,
          UnitPrice__c,
          Unit__c,
          ContractProduct__c,
          ContractHistory__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :history.Id
        ORDER BY StartDate__c ASC
        LIMIT 1
      ];
      Invoice__c invoice = [
        SELECT
          BillingAccountSnapShot__c,
          BillingAccountKeySnapShot__c,
          PaymentTermMethodSnapShot__c,
          InvoiceDateDayOfMonthSnapShot__c,
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c,
          BillingEmailCcSnapShot__c,
          BillingEmailBccSnapShot__c,
          InvoiceDeliveryMethodSnapShot__c
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
        ORDER BY InvoiceDate__c ASC
        LIMIT 1
      ];
      BillingAccount__c keyedAccount = [
        SELECT BillingAccountKey__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      // BillingAccount__c ?EInvoice__c?E???????ESnapShot?E?E
      System.assertEquals(billingAccount.Id, invoice.BillingAccountSnapShot__c);
      System.assertEquals(
        keyedAccount.BillingAccountKey__c,
        invoice.BillingAccountKeySnapShot__c
      );
      System.assertEquals(
        BillingScheduleService.METHOD_MONTH_OFFSET,
        invoice.PaymentTermMethodSnapShot__c,
        'Core 第7.5節: 生成時に支払条件の計算方式をスナップショットする'
      );
      System.assertEquals(
        25,
        invoice.InvoiceDateDayOfMonthSnapShot__c,
        'Core 第7.2節: 生成時に請求日ルールの指定日をスナップショットする'
      );
      System.assertEquals(
        '???????????E?? ??',
        invoice.BillingAddresseeSnapShot__c
      );
      System.assertEquals(
        'billing-to@example.com',
        invoice.BillingEmailToSnapShot__c
      );
      System.assertEquals(
        'billing-cc@example.com',
        invoice.BillingEmailCcSnapShot__c
      );
      System.assertEquals(
        'billing-bcc@example.com',
        invoice.BillingEmailBccSnapShot__c
      );
      System.assertEquals(
        InvoiceDeliveryMethodService.EMAIL,
        invoice.InvoiceDeliveryMethodSnapShot__c,
        'Core 第3.3.7節: 受注生成で届け方をスナップショットする'
      );
      // ContractProduct__c ?E??????
      System.assertEquals(1, invoiceProduct.Quantity__c);
      System.assertEquals(8000, invoiceProduct.UnitPrice__c);
      System.assertEquals(
        ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
        invoiceProduct.Unit__c
      );
      System.assertNotEquals(null, invoiceProduct.ContractProduct__c);
      System.assertEquals(history.Id, invoiceProduct.ContractHistory__c);
    }
  }
  @IsTest
  static void estimateToOrdered_copiesImmediateBillingDaySnapShotAsIs() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Immediate Snapshot Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END, PaymentTermMonthOffset__c = 0, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
        InvoiceDateMethod__c = BillingScheduleService.METHOD_SAME_DAY, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com'
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'Immediate Snapshot Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Immediate Snapshot Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Immediate Snapshot History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insertHistory(history);
      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2027, 5, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      Test.startTest();
      orderHistory(history);
      Test.stopTest();
      Invoice__c invoice = [
        SELECT InvoiceDateDayOfMonthSnapShot__c
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
        ORDER BY InvoiceDate__c ASC
        LIMIT 1
      ];
      System.assertEquals(
        null,
        invoice.InvoiceDateDayOfMonthSnapShot__c,
        'Core 第7.2節: SameDayでは指定日を空にする'
      );
    }
  }
  private class TestData {
    public ContractHistory__c history;
    public ContractProduct__c recurringProduct;
  }
  private static TestData createHistoryWithProducts(Boolean includeOriginal) {
    Account account = ContractTestDataFactory.insertAccount('Test Account');
    ContractService__c service = insertServiceWithBillingAccount(
      'Invoice Test Service',
      account
    );
    TestData data = new TestData();
    data.history = new ContractHistory__c(
      Name = 'Invoice Test History',
      ContractService__c = service.Id,
      Type__c = 'Renew',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
    );
    insertHistory(data.history);
    Product2 recurringProduct = ContractTestDataFactory.buildProduct(
      'Recurring Product'
    );
    recurringProduct.UnitName__c = 'ID';
    recurringProduct.UnitPrice__c = 8000;
    recurringProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    ContractTestDataFactory.insertProduct(recurringProduct);
    Date termStart = Date.newInstance(2026, 6, 1);
    Date termEnd = Date.newInstance(2027, 5, 31);
    data.recurringProduct = new ContractProduct__c(
      ContractHistory__c = data.history.Id,
      Product__c = recurringProduct.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Amount__c = 1,
      StartDate__c = termStart,
      Enddate__c = termEnd,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = 'Renew'
    );
    insert data.recurringProduct;
    if (includeOriginal) {
      Product2 originalProduct = ContractTestDataFactory.buildProduct(
        'Original Product'
      );
      originalProduct.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      originalProduct.UnitPrice__c = 5000;
      originalProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      originalProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(originalProduct);
      insert new ContractProduct__c(
        ContractHistory__c = data.history.Id,
        Product__c = originalProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 5000,
        Amount__c = -1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original'
      );
    }
    return data;
  }
  @IsTest
  static void changeToOrdered_skipsOriginalInvoiceProductsAndUsesEffectiveDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Invoice Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'Change Invoice Service',
        account
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      Date effectiveDate = Date.newInstance(2026, 10, 1);
      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change Invoice Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);
      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Invoice Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c priorContractProduct = new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert priorContractProduct;
      orderHistory(priorHistory);
      Test.startTest();
      // ??????E???E???Ehange ??E? V2 ???? prior ??E?????E
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change Invoice History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = -1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = effectiveDate.addDays(-1),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = effectiveDate,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      orderHistory(changeHistory);
      Test.stopTest();
      System.assertEquals(
        12,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :priorHistory.Id
        ]
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :priorHistory.Id AND Amount__c < 0
        ]
      );
      List<InvoiceProduct__c> changeInvoices = [
        SELECT Amount__c, Quantity__c, UnitPrice__c, StartDate__c, Enddate__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :changeHistory.Id
        ORDER BY StartDate__c ASC, Amount__c ASC
      ];
      System.assertEquals(16, changeInvoices.size(), '?2??E??E');
      System.assertEquals(-8000, changeInvoices[0].Amount__c);
      System.assertEquals(1, changeInvoices[0].Quantity__c);
      System.assertEquals(8000, changeInvoices[0].UnitPrice__c);
      System.assertEquals(16000, changeInvoices[1].Amount__c);
      System.assertEquals(2, changeInvoices[1].Quantity__c);
      System.assertEquals(8000, changeInvoices[1].UnitPrice__c);
      System.assertEquals(effectiveDate, changeInvoices[0].StartDate__c);
      System.assertEquals(
        Date.newInstance(2026, 10, 31),
        changeInvoices[0].Enddate__c
      );
      Invoice__c changeInvoiceHeader = [
        SELECT InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :changeHistory.Id
        ORDER BY InvoiceDate__c ASC
        LIMIT 1
      ];
      System.assertEquals(
        effectiveDate,
        changeInvoiceHeader.InvoiceDate__c,
        'Change???????E??????????'
      );
      System.assertEquals(
        64000,
        [
            SELECT SUM(Amount__c) totalAmount
            FROM InvoiceProduct__c
            WHERE ContractHistory__c = :changeHistory.Id
          ][0]
          .get('totalAmount')
      );
    }
  }

  @IsTest
  static void changeGenerate_allowsWhenPriorHistoryInvoiceLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Prior Locked Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'Change Prior Locked Service',
        account
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      Date effectiveDate = Date.newInstance(2026, 10, 1);
      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change Prior Locked Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);
      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Prior Locked Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c priorContractProduct = new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert priorContractProduct;
      orderHistory(priorHistory);
      Test.startTest();
      List<Invoice__c> priorInvoices = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :priorHistory.Id
      ];
      System.assert(!priorInvoices.isEmpty(), 'prior ???????');
      for (Invoice__c invoice : priorInvoices) {
        invoice.SystemIntegrationDate__c = Date.today();
      }
      update priorInvoices;

      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change Prior Locked Change',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = -1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = effectiveDate.addDays(-1),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = effectiveDate,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );

      orderHistory(changeHistory);
      Test.stopTest();

      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :changeHistory.Id
        ]
        .historystatus__c
      );
      System.assert(
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :changeHistory.Id
        ] > 0,
        'prior ????E????EChange ?????????E???E'
      );
      System.assertEquals(
        priorInvoices.size(),
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE
            ContractHistory__c = :priorHistory.Id
            AND SystemIntegrationDate__c != NULL
        ],
        'prior ??E?????E??'
      );
    }
  }

  @IsTest
  static void changeToOrdered_createsOneTimeAddonInvoiceProduct() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change One Time Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'Change One Time Service',
        account
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      Date effectiveDate = Date.newInstance(2026, 10, 1);
      Date addonStart = effectiveDate;
      Date addonEnd = Date.newInstance(2026, 10, 31);
      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change One Time Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);
      Product2 recurringProduct = ContractTestDataFactory.buildProduct(
        'Change One Time Recurring'
      );
      recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(recurringProduct);
      ContractProduct__c priorContractProduct = new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = recurringProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert priorContractProduct;
      orderHistory(priorHistory);
      Test.startTest();
      Product2 oneTimeProduct = ContractTestDataFactory.buildProduct(
        'Change One Time Addon'
      );
      oneTimeProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(oneTimeProduct);
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change One Time History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);
      insertUnchangedOriginalAndRemake(changeHistory.Id, priorContractProduct);
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = oneTimeProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 50000,
        Amount__c = 1,
        StartDate__c = addonStart,
        Enddate__c = addonEnd,
        InvoiceSetting__c = ContractMetadataService.INVOICE_SETTING_POSTPAID_NEXT_DAY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = 'New'
      );
      orderHistory(changeHistory);
      Test.stopTest();
      List<InvoiceProduct__c> addonInvoices = [
        SELECT Amount__c, StartDate__c, Enddate__c
        FROM InvoiceProduct__c
        WHERE
          ContractHistory__c = :changeHistory.Id
          AND ContractProduct__r.Product__c = :oneTimeProduct.Id
      ];
      System.assertEquals(
        1,
        addonInvoices.size(),
        'Change????????E????????1???E???E'
      );
      System.assertEquals(50000, addonInvoices[0].Amount__c);
      System.assertEquals(addonStart, addonInvoices[0].StartDate__c);
      System.assertEquals(addonEnd, addonInvoices[0].Enddate__c);
      Decimal recurringNet = 0;
      for (InvoiceProduct__c invoiceProduct : [
        SELECT Amount__c
        FROM InvoiceProduct__c
        WHERE
          ContractHistory__c = :changeHistory.Id
          AND ContractProduct__r.Product__c = :recurringProduct.Id
      ]) {
        recurringNet += invoiceProduct.Amount__c == null
          ? 0
          : invoiceProduct.Amount__c;
      }
      System.assertEquals(
        0,
        recurringNet,
        '??????????EChange ???????E??E????E0'
      );
    }
  }

  @IsTest
  static void changeOneTimeAddonMidMonth_doesNotShiftRecurringMonthlyGrid() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change MidMonth OneTime Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'Change MidMonth OneTime Service',
        account
      );
      Date termStart = Date.newInstance(2025, 7, 1);
      Date termEnd = Date.newInstance(2026, 6, 30);
      // ????ENew ???? ?E???????????ERemake ??E??????????E
      Date addonStart = Date.newInstance(2025, 8, 29);
      Date addonEnd = Date.newInstance(2025, 9, 29);
      Date effectiveDate = addonStart;
      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change MidMonth OneTime Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);
      Product2 recurringProduct = ContractTestDataFactory.buildProduct(
        'Change MidMonth OneTime Recurring'
      );
      recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(recurringProduct);
      ContractProduct__c priorContractProduct = new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = recurringProduct.Id,
        Quantity__c = 900,
        UnitPrice__c = 500,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert priorContractProduct;
      orderHistory(priorHistory);
      Test.startTest();
      Product2 oneTimeProduct = ContractTestDataFactory.buildProduct(
        'Change MidMonth OneTime Addon'
      );
      oneTimeProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(oneTimeProduct);
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change MidMonth OneTime History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);
      insertUnchangedOriginalAndRemake(changeHistory.Id, priorContractProduct);
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = oneTimeProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 1200000,
        Amount__c = 1,
        StartDate__c = addonStart,
        Enddate__c = addonEnd,
        InvoiceSetting__c = ContractMetadataService.INVOICE_SETTING_POSTPAID_NEXT_DAY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = 'New'
      );

      orderHistory(changeHistory);
      Test.stopTest();

      List<InvoiceProduct__c> changeRecurring = [
        SELECT Amount__c, StartDate__c, Enddate__c, ContractProduct__r.Type__c
        FROM InvoiceProduct__c
        WHERE
          ContractHistory__c = :changeHistory.Id
          AND ContractProduct__r.Product__c = :recurringProduct.Id
      ];
      System.assertEquals(
        0,
        changeRecurring.size(),
        '?????????E???????Eperiod key ???E??????E'
      );

      List<InvoiceProduct__c> addonInvoices = [
        SELECT Amount__c
        FROM InvoiceProduct__c
        WHERE
          ContractHistory__c = :changeHistory.Id
          AND ContractProduct__r.Product__c = :oneTimeProduct.Id
      ];
      System.assertEquals(1, addonInvoices.size());
      System.assertEquals(1200000, addonInvoices[0].Amount__c);

      AggregateResult changeTotal = [
        SELECT SUM(Amount__c) total
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :changeHistory.Id
      ];
      System.assertEquals(
        1200000,
        (Decimal) changeTotal.get('total'),
        'Change ??????????E???????E?E?'
      );
    }
  }

  @IsTest
  static void resolveFirstMonthlyPeriodStartOnOrAfter_keepsAnchorGrid() {
    Date anchor = Date.newInstance(2025, 7, 1);
    System.assertEquals(
      Date.newInstance(2025, 9, 1),
      InvoiceProductGenerationService.resolveFirstMonthlyPeriodStartOnOrAfter(
        anchor,
        Date.newInstance(2025, 9, 1)
      ),
      '?E????E??E?'
    );
    System.assertEquals(
      Date.newInstance(2025, 9, 1),
      InvoiceProductGenerationService.resolveFirstMonthlyPeriodStartOnOrAfter(
        anchor,
        Date.newInstance(2025, 8, 29)
      ),
      '?????????????E??'
    );
    System.assertEquals(
      anchor,
      InvoiceProductGenerationService.resolveFirstMonthlyPeriodStartOnOrAfter(
        anchor,
        Date.newInstance(2025, 6, 15)
      ),
      '??????E?????'
    );
  }

  @IsTest
  static void changeOneTimeOnlyWithoutOriginalRemake_neverCreatesReversal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change One Time Only Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'Change One Time Only Service',
        account
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      Date effectiveDate = Date.newInstance(2026, 10, 1);
      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change One Time Only Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);
      Product2 oneTimeProduct = ContractTestDataFactory.buildProduct(
        'Change One Time Only Product'
      );
      oneTimeProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(oneTimeProduct);
      insert new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = oneTimeProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 80000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = Date.newInstance(2026, 6, 30),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = 'New'
      );
      orderHistory(priorHistory);
      Test.startTest();
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change One Time Only History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = oneTimeProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 30000,
        Amount__c = 1,
        StartDate__c = Date.newInstance(2026, 10, 15),
        Enddate__c = Date.newInstance(2026, 10, 31),
        InvoiceSetting__c = ContractMetadataService.INVOICE_SETTING_POSTPAID_NEXT_DAY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = 'New'
      );
      orderHistory(changeHistory);
      Test.stopTest();
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :changeHistory.Id
        ]
        .historystatus__c,
        'Core 第6.1節: 一回課金追加だけの Change は受注できる'
      );
      assertNoReversalInvoiceProducts(changeHistory.Id);
    }
  }
  @IsTest
  static void changeReversalUnmatchedOriginal_failsClosedOnOrder() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Reversal FailClosed Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'Change Reversal FailClosed Service',
        account
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      // ????????????????????????????E?E
      Date effectiveDate = termStart;
      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change Reversal FailClosed Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);
      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Reversal FailClosed Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c priorContractProduct = new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert priorContractProduct;
      orderHistory(priorHistory);
      Test.startTest();
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change Reversal FailClosed History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);
      // Data Loader ????E Original ???Epast ????????????E???
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 9999,
        Amount__c = -1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 9000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );

      Boolean thrown = false;
      String message = null;
      try {
        orderHistory(changeHistory);
      } catch (Exception ex) {
        thrown = true;
        message = dmlMessage(ex);
      }
      Test.stopTest();
      System.assertEquals(
        true,
        thrown,
        '?????????????EFail closed ?????E??????????????E??E'
      );
      System.assert(
        message != null &&
          message.contains('変更前の行は前回の版の見積商品と一致している必要があります'),
        'Core 第6.1節: Original 不一致は fail-closed。実際: ' + message
      );
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
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :changeHistory.Id
        ],
        'Fail closed ??E?????E??????E'
      );
    }
  }

  @IsTest
  static void changeRemakeOnlyWithoutOriginal_neverCreatesReversal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Remake Only Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'Change Remake Only Service',
        account
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      Date effectiveDate = Date.newInstance(2026, 10, 1);
      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change Remake Only Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);
      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Remake Only Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c priorContractProduct = new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert priorContractProduct;
      orderHistory(priorHistory);
      Test.startTest();
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change Remake Only History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = effectiveDate,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      Boolean thrown = false;
      try {
        orderHistory(changeHistory);
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          '前回の版の継続課金商品すべてに変更前の行が必要です。',
          dmlMessage(ex),
          'Core 第6.1節: Remake だけの Change は変更前行が無いと拒否する'
        );
      }
      Test.stopTest();
      System.assertEquals(
        true,
        thrown,
        'Original ???E Change ????????????E'
      );
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
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :changeHistory.Id
        ]
      );
    }
  }
  @IsTest
  static void newAndRenewHistories_neverCreateReversalInvoiceProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData renewData = createHistoryWithProducts(false);
      Test.startTest();
      orderHistory(renewData.history);
      Test.stopTest();
      assertNoReversalInvoiceProducts(renewData.history.Id);
      Account account = ContractTestDataFactory.insertAccount(
        'New No Reversal Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'New No Reversal Service',
        account
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      ContractHistory__c newHistory = new ContractHistory__c(
        Name = 'New No Reversal History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(newHistory);
      Product2 product = ContractTestDataFactory.buildProduct(
        'New No Reversal Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = newHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      orderHistory(newHistory);
      assertNoReversalInvoiceProducts(newHistory.Id);
    }
  }
  @IsTest
  static void isPreferredPastSample_prefersPositiveOverNonPositive() {
    InvoiceProduct__c positive = new InvoiceProduct__c(Amount__c = 9000);
    InvoiceProduct__c negative = new InvoiceProduct__c(Amount__c = -8000);
    InvoiceProduct__c zero = new InvoiceProduct__c(Amount__c = 0);
    System.assertEquals(
      true,
      InvoiceProductGenerationService.isPreferredPastSample(positive, negative),
      '????E???????E'
    );
    System.assertEquals(
      true,
      InvoiceProductGenerationService.isPreferredPastSample(positive, zero),
      '????E0????E'
    );
    System.assertEquals(
      false,
      InvoiceProductGenerationService.isPreferredPastSample(negative, positive),
      '??????????????E'
    );
    System.assertEquals(
      false,
      InvoiceProductGenerationService.isPreferredPastSample(positive, positive),
      '????????E?????E??E'
    );
  }

  /**
   * Change?Change ?????E??V2 ????ECreatedDate ??????E
   * ???????????? V3 ???Efail-closed ???E????E
   * V1/V2 ? Ordered ? insert?E?? generate?E?????E????? SOQL ?????E
   */
  @IsTest
  static void changeChange_priceRevisionTwice_ordersSuccessfully() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Change Price Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'Change Change Price Service',
        account
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2026, 6, 30);

      ContractHistory__c v1 = new ContractHistory__c(
        Name = 'Change Change Price V1',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(v1);
      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Change Price Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c v1Cp = new ContractProduct__c(
        ContractHistory__c = v1.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert v1Cp;
      String v1Bucket = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
        null,
        v1.Id,
        termStart,
        null
      );
      insert new InvoiceProduct__c(
        ContractHistory__c = v1.Id,
        ContractProduct__c = v1Cp.Id,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceBucketKey__c = v1Bucket,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 8000
      );

      // past ??????Type=New ?? generate ???E??Change ?????????????
      ContractHistory__c v2 = new ContractHistory__c(
        Name = 'Change Change Price V2',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart,
        PreviousHistory__c = v1.Id
      );
      insertHistory(v2);
      ContractProduct__c v2Original = new ContractProduct__c(
        ContractHistory__c = v2.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = -1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original',
        PreviousContractProduct__c = v1Cp.Id
      );
      ContractProduct__c v2Remake = new ContractProduct__c(
        ContractHistory__c = v2.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 9000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = v1Cp.Id
      );
      insert new List<ContractProduct__c>{ v2Original, v2Remake };
      String v2Bucket = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
        null,
        v2.Id,
        termStart,
        null
      );
      InvoiceProduct__c v2Reversal = new InvoiceProduct__c(
        ContractHistory__c = v2.Id,
        ContractProduct__c = v2Original.Id,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceBucketKey__c = v2Bucket,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = -8000
      );
      InvoiceProduct__c v2Charge = new InvoiceProduct__c(
        ContractHistory__c = v2.Id,
        ContractProduct__c = v2Remake.Id,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceBucketKey__c = v2Bucket,
        Quantity__c = 1,
        UnitPrice__c = 9000,
        Amount__c = 9000
      );
      insert new List<InvoiceProduct__c>{ v2Charge, v2Reversal };

      Test.startTest();

      ContractHistory__c v3 = new ContractHistory__c(
        Name = 'Change Change Price V3',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 3,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart,
        PreviousHistory__c = v2.Id
      );
      insertHistory(v3);
      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = v3.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 9000,
          Amount__c = -1,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Original',
          PreviousContractProduct__c = v2Remake.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = v3.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 1,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = v2Remake.Id
        )
      };

      prepareHistoryForOrder(v3);
      commitOrder(v3);

      System.assertEquals(
        'Ordered',
        [SELECT historystatus__c FROM ContractHistory__c WHERE Id = :v3.Id]
        .historystatus__c,
        'V3 は Ordered になる'
      );
      assertReversalInvoiceProductsUseOriginalContractProduct(v3.Id);
      Decimal v3Net = (Decimal) [
          SELECT SUM(Amount__c) totalAmount
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :v3.Id
        ][0]
        .get('totalAmount');
      // 1??E?E(10000 - 9000) = 1000
      System.assertEquals(1000, v3Net, 'Core 第6.1節: V3 の期間明細 Net は 1000');
      for (InvoiceProduct__c reversal : [
        SELECT Amount__c, UnitPrice__c, ContractProduct__r.UnitPrice__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :v3.Id AND Amount__c < 0
      ]) {
        System.assertEquals(
          9000,
          reversal.ContractProduct__r.UnitPrice__c,
          'Core 第6.1節: V3 Original の単価は V2 Remake の 9000'
        );
      }
      Test.stopTest();
    }
  }

  private static void assertNoReversalInvoiceProducts(Id contractHistoryId) {
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :contractHistoryId AND Amount__c < 0
      ],
      '????E??E????E'
    );
  }
  private static void assertReversalInvoiceProductsUseOriginalContractProduct(
    Id contractHistoryId
  ) {
    for (InvoiceProduct__c invoiceProduct : [
      SELECT ContractProduct__r.Type__c
      FROM InvoiceProduct__c
      WHERE ContractHistory__c = :contractHistoryId AND Amount__c < 0
    ]) {
      System.assertEquals(
        'Original',
        invoiceProduct.ContractProduct__r.Type__c,
        '????E Original ??E???????E'
      );
    }
  }
  @IsTest
  static void renewToOrdered_usesPastInvoiceProductSampleForDiffReversal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Renew Diff Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'Renew Diff Service',
        account
      );
      Date priorStart = Date.newInstance(2025, 6, 1);
      Date priorEnd = Date.newInstance(2026, 5, 31);
      Date renewStart = Date.newInstance(2026, 6, 1);
      Date renewEnd = Date.newInstance(2027, 5, 31);
      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Renew Diff Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = priorStart,
        CurrentTermEndDate__c = priorEnd,
        EffectiveDate__c = priorStart
      );
      insertHistory(priorHistory);
      Product2 product = ContractTestDataFactory.buildProduct(
        'Renew Diff Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c priorContractProduct = new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = priorStart,
        Enddate__c = priorEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert priorContractProduct;
      orderHistory(priorHistory);
      Test.startTest();
      ContractHistory__c renewHistory = new ContractHistory__c(
        Name = 'Renew Diff History',
        ContractService__c = service.Id,
        Type__c = 'Renew',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = renewStart,
        CurrentTermEndDate__c = renewEnd,
        EffectiveDate__c = renewStart,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(renewHistory);
      insert new ContractProduct__c(
        ContractHistory__c = renewHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = renewStart,
        Enddate__c = renewEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Renew',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      orderHistory(renewHistory);
      Test.stopTest();
      List<InvoiceProduct__c> renewInvoices = [
        SELECT Quantity__c, UnitPrice__c, Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :renewHistory.Id
        ORDER BY StartDate__c ASC
      ];
      System.assertEquals(
        12,
        renewInvoices.size(),
        'Renew ??????????E2??E???E'
      );
      for (InvoiceProduct__c invoiceProduct : renewInvoices) {
        System.assert(invoiceProduct.Amount__c > 0, 'Renew ??????E');
        System.assertNotEquals(null, invoiceProduct.Quantity__c);
        System.assertNotEquals(null, invoiceProduct.UnitPrice__c);
        System.assertEquals(8000, invoiceProduct.Amount__c);
      }
    }
  }
  @IsTest
  static void changeToOrdered_usesBillingDayAfterFirstPeriod() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Billing Day Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER, InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY, InvoiceDateDayOfMonth__c = 15, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END, PaymentTermMonthOffset__c = 1, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com'
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'Change Billing Day Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      Date effectiveDate = Date.newInstance(2026, 10, 1);
      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change Billing Day Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);
      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Billing Day Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c priorContractProduct = new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert priorContractProduct;
      orderHistory(priorHistory);
      Test.startTest();
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change Billing Day History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = -1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = effectiveDate.addDays(-1),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 2,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = effectiveDate,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      orderHistory(changeHistory);
      Test.stopTest();
      List<Invoice__c> changeInvoices = [
        SELECT InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :changeHistory.Id
        ORDER BY InvoiceDate__c ASC
      ];
      System.assert(changeInvoices.size() >= 2);
      System.assertEquals(
        Date.newInstance(2026, 10, 15),
        changeInvoices[0].InvoiceDate__c,
        'Change???????????E???E???'
      );
      System.assertEquals(
        Date.newInstance(2026, 11, 15),
        changeInvoices[1].InvoiceDate__c,
        '2??????????????E???E???'
      );
    }
  }
  @IsTest
  static void changePrepaidMultiRemakeUsesEffectiveDateAsInvoiceAnchor() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Prepaid Effective Anchor Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER, InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY, InvoiceDateDayOfMonth__c = 5, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END, PaymentTermMonthOffset__c = 1, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com'
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'Change Prepaid Effective Anchor Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;
      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2027, 6, 30);
      Date effectiveDate = Date.newInstance(2027, 4, 1);
      Date laterRemakeStart = Date.newInstance(2027, 6, 1);
      Date expectedInvoiceDate = Date.newInstance(2027, 4, 5);
      Date expectedPaymentScheduledDate = Date.newInstance(2027, 5, 31);
      Decimal priorUnitPrice = 50000;
      Decimal priorQuantity = 2;
      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change Prepaid Effective Anchor Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);
      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Prepaid Effective Anchor Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = product.Id,
        Quantity__c = priorQuantity,
        UnitPrice__c = priorUnitPrice,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      ContractProduct__c priorContractProduct = [
        SELECT Id
        FROM ContractProduct__c
        WHERE ContractHistory__c = :priorHistory.Id
        LIMIT 1
      ];
      orderHistory(priorHistory);
      Test.startTest();
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change Prepaid Effective Anchor History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);
      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = priorQuantity,
          UnitPrice__c = priorUnitPrice,
          Amount__c = -1,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Original',
          PreviousContractProduct__c = priorContractProduct.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = priorQuantity,
          UnitPrice__c = priorUnitPrice,
          Amount__c = 1,
          StartDate__c = termStart,
          Enddate__c = effectiveDate.addDays(-1),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorContractProduct.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = priorQuantity,
          UnitPrice__c = 52000,
          Amount__c = 1,
          StartDate__c = effectiveDate,
          Enddate__c = Date.newInstance(2027, 5, 31),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorContractProduct.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 3,
          UnitPrice__c = 55000,
          Amount__c = 1,
          StartDate__c = laterRemakeStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorContractProduct.Id
        )
      };
      orderHistory(changeHistory);
      Test.stopTest();
      List<InvoiceProduct__c> changeInvoices = [
        SELECT Amount__c, StartDate__c, ContractProduct__r.Type__c
        FROM InvoiceProduct__c
        WHERE
          ContractHistory__c = :changeHistory.Id
          AND StartDate__c >= :effectiveDate
        ORDER BY StartDate__c ASC, Amount__c ASC
      ];
      System.assertEquals(6, changeInvoices.size(), '4?E??E ?2 ?E?E3 ??E');
      Invoice__c changeInvoiceHeader = [
        SELECT InvoiceDate__c, PaymentScheduledDate__c
        FROM Invoice__c
        WHERE
          ContractHistory__c = :changeHistory.Id
          AND InvoiceDate__c = :expectedInvoiceDate
        LIMIT 1
      ];
      System.assertEquals(
        expectedInvoiceDate,
        changeInvoiceHeader.InvoiceDate__c,
        'Change ?E???????????E???'
      );
      System.assertEquals(
        expectedPaymentScheduledDate,
        changeInvoiceHeader.PaymentScheduledDate__c,
        'Change ?E???????????E?????'
      );
      InvoiceProduct__c juneCharge = null;
      for (InvoiceProduct__c changeInvoice : changeInvoices) {
        if (
          changeInvoice.StartDate__c == laterRemakeStart &&
          changeInvoice.Amount__c > 0
        ) {
          juneCharge = changeInvoice;
          break;
        }
      }
      System.assertNotEquals(null, juneCharge, '6??E???E');
    }
  }
  @IsTest
  static void changePrepaidOneTimeAddonUsesEffectiveDateAsInvoiceAnchor() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Prepaid One Time Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER, InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY, InvoiceDateDayOfMonth__c = 5, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END, PaymentTermMonthOffset__c = 1, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com'
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'Change Prepaid One Time Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      Date addonStart = Date.newInstance(2026, 10, 15);
      Date addonEnd = Date.newInstance(2026, 10, 31);
      // ??????E????E????E???????????E??????????E
      Date effectiveDate = addonStart;
      Date expectedInvoiceDate = Date.newInstance(2026, 11, 5);
      Date expectedPaymentScheduledDate = Date.newInstance(2026, 12, 31);
      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change Prepaid One Time Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);
      Product2 recurringProduct = ContractTestDataFactory.buildProduct(
        'Change Prepaid One Time Recurring'
      );
      recurringProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(recurringProduct);
      ContractProduct__c priorContractProduct = new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = recurringProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert priorContractProduct;
      orderHistory(priorHistory);
      Test.startTest();
      Product2 oneTimeProduct = ContractTestDataFactory.buildProduct(
        'Change Prepaid One Time Addon'
      );
      oneTimeProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(oneTimeProduct);
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change Prepaid One Time History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);
      insertUnchangedOriginalAndRemake(changeHistory.Id, priorContractProduct);
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = oneTimeProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 50000,
        Amount__c = 1,
        StartDate__c = addonStart,
        Enddate__c = addonEnd,
        InvoiceSetting__c = ContractMetadataService.INVOICE_SETTING_PREPAID_START,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = 'New'
      );
      orderHistory(changeHistory);
      Test.stopTest();
      InvoiceProduct__c addonInvoice = [
        SELECT Amount__c, StartDate__c, Enddate__c
        FROM InvoiceProduct__c
        WHERE
          ContractHistory__c = :changeHistory.Id
          AND ContractProduct__r.Product__c = :oneTimeProduct.Id
        LIMIT 1
      ];
      System.assertEquals(50000, addonInvoice.Amount__c);
      System.assertEquals(addonStart, addonInvoice.StartDate__c);
      System.assertEquals(addonEnd, addonInvoice.Enddate__c);
      Invoice__c addonHeader = [
        SELECT InvoiceDate__c, PaymentScheduledDate__c
        FROM Invoice__c
        WHERE
          ContractHistory__c = :changeHistory.Id
          AND InvoiceDate__c = :expectedInvoiceDate
        LIMIT 1
      ];
      System.assertEquals(
        expectedInvoiceDate,
        addonHeader.InvoiceDate__c,
        'Change ?E??E?E?????New??E???????E'
      );
      System.assertEquals(
        expectedPaymentScheduledDate,
        addonHeader.PaymentScheduledDate__c,
        'Change ?E??E?E??????????'
      );
      Integer recurringChangeCount = [
        SELECT COUNT()
        FROM InvoiceProduct__c
        WHERE
          ContractHistory__c = :changeHistory.Id
          AND ContractProduct__r.Product__c = :recurringProduct.Id
      ];
      System.assertEquals(
        0,
        recurringChangeCount,
        '??????????????E???????????E??????E'
      );
    }
  }
  @IsTest
  static void changePrepaidDiscontinuedRemakeUsesEffectiveDateAsInvoiceAnchor() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Prepaid Discontinued Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        InvoiceDateMethod__c = BillingScheduleService.METHOD_SAME_DAY, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END, PaymentTermMonthOffset__c = 0, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com'
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'Change Prepaid Discontinued Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;
      Date termStart = Date.newInstance(2024, 4, 1);
      Date termEnd = Date.newInstance(2025, 3, 31);
      Date effectiveDate = Date.newInstance(2025, 1, 1);
      Date remakeContinueEnd = Date.newInstance(2024, 12, 31);
      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change Prepaid Discontinued Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);
      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Prepaid Discontinued Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 20000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      ContractProduct__c priorContractProduct = [
        SELECT Id
        FROM ContractProduct__c
        WHERE ContractHistory__c = :priorHistory.Id
        LIMIT 1
      ];
      orderHistory(priorHistory);
      Test.startTest();
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change Prepaid Discontinued History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 20000,
        Amount__c = -1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 20000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = remakeContinueEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 0,
        Amount__c = 1,
        StartDate__c = effectiveDate,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      orderHistory(changeHistory);
      Test.stopTest();
      List<InvoiceProduct__c> changePeriodLines = [
        SELECT StartDate__c, Enddate__c, Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :changeHistory.Id
      ];
      System.assert(
        !changePeriodLines.isEmpty(),
        '?????E???0?????E Remake?E????????????'
      );
      List<Invoice__c> changeInvoices = [
        SELECT InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :changeHistory.Id
      ];
      System.assert(!changeInvoices.isEmpty(), '???E?E?????E?????');
      for (Invoice__c changeInvoice : changeInvoices) {
        System.assertEquals(
          effectiveDate,
          changeInvoice.InvoiceDate__c,
          'Starter??E Change ?E??????E??????????????????'
        );
      }
    }
  }

  @IsTest
  static void generateForHistories_blocksChangeWithReconstitutionGap() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Gap Block Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        InvoiceDateMethod__c = BillingScheduleService.METHOD_SAME_DAY, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END, PaymentTermMonthOffset__c = 0, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com'
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      ContractService__c service = new ContractService__c(
        Name = 'Change Gap Block Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;
      Date termStart = Date.newInstance(2024, 4, 1);
      Date termEnd = Date.newInstance(2025, 3, 31);
      Date effectiveDate = Date.newInstance(2025, 1, 1);
      Date shortRemakeEnd = Date.newInstance(2024, 12, 31);
      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change Gap Block Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);
      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Gap Block Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 20000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      ContractProduct__c priorContractProduct = [
        SELECT Id
        FROM ContractProduct__c
        WHERE ContractHistory__c = :priorHistory.Id
        LIMIT 1
      ];
      orderHistory(priorHistory);
      Test.startTest();
      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change Gap Block History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 20000,
        Amount__c = -1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 20000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = shortRemakeEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );

      Boolean thrown = false;
      String message = null;
      try {
        orderHistory(changeHistory);
      } catch (Exception ex) {
        thrown = true;
        message = dmlMessage(ex);
      }
      Test.stopTest();
      System.assertEquals(true, thrown, '?? Remake ? Change ???????E');
      System.assertEquals(
        EstimateValidationService.CHANGE_REMAKE_COVERAGE_MESSAGE,
        message
      );
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
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :changeHistory.Id
        ],
        '????E??????????E'
      );
    }
  }

  @IsTest
  static void changeToOrdered_keepsSeparateLineagesForSameProduct() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Dual Lineage Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'Change Dual Lineage Service',
        account
      );

      Date termStart = Date.newInstance(2026, 4, 1);
      Date firstEnd = Date.newInstance(2026, 9, 30);
      Date secondStart = Date.newInstance(2026, 10, 1);
      Date termEnd = Date.newInstance(2027, 3, 31);
      Date effectiveDate = Date.newInstance(2026, 7, 1);

      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change Dual Lineage Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Dual Lineage Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c priorFirst = new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = firstEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      ContractProduct__c priorSecond = new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Amount__c = 1,
        StartDate__c = secondStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert new List<ContractProduct__c>{ priorFirst, priorSecond };

      orderHistory(priorHistory);
      Test.startTest();

      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change Dual Lineage History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);

      // ??1: 4-9?????7/1??????E????2: 10-3???????E
      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = -1,
          StartDate__c = termStart,
          Enddate__c = firstEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Original',
          PreviousContractProduct__c = priorFirst.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 1,
          StartDate__c = termStart,
          Enddate__c = effectiveDate.addDays(-1),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorFirst.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 2,
          UnitPrice__c = 10000,
          Amount__c = 1,
          StartDate__c = effectiveDate,
          Enddate__c = firstEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorFirst.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = -1,
          StartDate__c = secondStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Original',
          PreviousContractProduct__c = priorSecond.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 1,
          StartDate__c = secondStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorSecond.Id
        )
      };

      orderHistory(changeHistory);

      List<InvoiceProduct__c> changeInvoices = [
        SELECT Amount__c, Quantity__c, StartDate__c, Enddate__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :changeHistory.Id
        ORDER BY StartDate__c ASC, Amount__c ASC
      ];
      Test.stopTest();

      // ??????E7-9??E???E????E????E??E= 6??E
      // Product2 ???????????E??E????E?????E
      System.assertEquals(
        6,
        changeInvoices.size(),
        '???E??????????????E???E???'
      );
      for (InvoiceProduct__c changeInvoice : changeInvoices) {
        System.assert(
          changeInvoice.StartDate__c >= effectiveDate,
          '??E????E??????E?'
        );
        System.assert(
          changeInvoice.Enddate__c <= firstEnd,
          '??1????E?????E'
        );
      }
      Decimal totalAmount = 0;
      for (InvoiceProduct__c changeInvoice : changeInvoices) {
        totalAmount += changeInvoice.Amount__c;
      }
      System.assertEquals(30000, totalAmount, '??E?E???E10000?E??E');
    }
  }

  @IsTest
  static void changeToOrdered_multiRemake_fillsPreEffectiveWithOriginal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Change Multi Remake Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        'Change Multi Remake Service',
        account
      );

      Date termStart = Date.newInstance(2026, 4, 1);
      Date remake1End = Date.newInstance(2026, 5, 31);
      Date remake2Start = Date.newInstance(2026, 6, 1);
      Date remake2End = Date.newInstance(2026, 8, 31);
      Date remake3Start = Date.newInstance(2026, 9, 1);
      Date termEnd = Date.newInstance(2027, 3, 31);
      // Remake?????Es-Is ?? 6???????? reversal ??????E
      Date effectiveDate = Date.newInstance(2026, 7, 1);

      ContractHistory__c priorHistory = new ContractHistory__c(
        Name = 'Change Multi Remake Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insertHistory(priorHistory);

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Multi Remake Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      ContractProduct__c priorProduct = new ContractProduct__c(
        ContractHistory__c = priorHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert priorProduct;

      orderHistory(priorHistory);
      Test.startTest();

      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Change Multi Remake History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = priorHistory.Id
      );
      insertHistory(changeHistory);

      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = -1,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Original',
          PreviousContractProduct__c = priorProduct.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 1,
          StartDate__c = termStart,
          Enddate__c = remake1End,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorProduct.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 1,
          StartDate__c = remake2Start,
          Enddate__c = effectiveDate.addDays(-1),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorProduct.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 2,
          UnitPrice__c = 10000,
          Amount__c = 1,
          StartDate__c = effectiveDate,
          Enddate__c = remake2End,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorProduct.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 2,
          UnitPrice__c = 10000,
          Amount__c = 1,
          StartDate__c = remake3Start,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorProduct.Id
        )
      };

      orderHistory(changeHistory);

      List<InvoiceProduct__c> changeInvoices = [
        SELECT
          Amount__c,
          Quantity__c,
          StartDate__c,
          Enddate__c,
          ContractProduct__c,
          ContractProduct__r.Quantity__c,
          ContractProduct__r.Type__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :changeHistory.Id
        ORDER BY StartDate__c ASC, Amount__c ASC
      ];
      Test.stopTest();

      for (InvoiceProduct__c changeInvoice : changeInvoices) {
        System.assert(
          changeInvoice.StartDate__c >= effectiveDate,
          '?????E Original=???????????E???E???E ' +
          String.valueOf(changeInvoice.StartDate__c)
        );
        System.assertNotEquals(
          null,
          changeInvoice.ContractProduct__c,
          '???E????E????????E?????'
        );
        if (changeInvoice.Amount__c != null && changeInvoice.Amount__c > 0) {
          System.assertEquals(
            'Remake',
            changeInvoice.ContractProduct__r.Type__c,
            '??????E Remake ??E??????????'
          );
          System.assertEquals(
            2,
            changeInvoice.ContractProduct__r.Quantity__c,
            '??????E???E??ERemake ????????E????ERemake?????E?E'
          );
        }
      }

      // 7???E?E= 9??E?E????E0000
      Decimal totalAmount = 0;
      for (InvoiceProduct__c changeInvoice : changeInvoices) {
        totalAmount += changeInvoice.Amount__c == null
          ? 0
          : changeInvoice.Amount__c;
      }
      System.assertEquals(
        90000,
        totalAmount,
        '6???????? reversal ????E???E???E??'
      );
      System.assertEquals(18, changeInvoices.size(), '?2??E??E');
    }
  }

  /** Trigger / Exception ??E???????????E????????? */
  private static String dmlMessage(Exception ex) {
    if (ex == null) {
      return null;
    }
    String raw;
    if (ex instanceof DmlException) {
      DmlException dml = (DmlException) ex;
      raw = dml.getNumDml() > 0 ? dml.getDmlMessage(0) : ex.getMessage();
    } else {
      raw = ex.getMessage();
    }
    if (String.isBlank(raw)) {
      return raw;
    }
    Integer causedBy = raw.indexOf('caused by: ');
    if (causedBy >= 0) {
      raw = raw.substring(causedBy + 'caused by: '.length());
    }
    List<String> markers = new List<String>{
      'ChangeConsistencyException: ',
      'InvoiceProductGenerationException: ',
      'FieldCopyException: ',
      'InvoiceLockException: '
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
