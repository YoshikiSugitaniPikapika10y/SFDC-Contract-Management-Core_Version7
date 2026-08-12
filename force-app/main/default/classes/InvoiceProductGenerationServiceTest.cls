@IsTest
private class InvoiceProductGenerationServiceTest {
  private static ContractService__c insertServiceWithBillingAccount(
    String name,
    Account account
  ) {
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_NEXT_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_1,
      BillingAddressee__c = 'テスト宛名',
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
      insert history;
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
        history.historystatus__c = 'Ordered';
        update history;
      } catch (Exception ex) {
        thrown = true;
        String message = dmlMessage(ex);
        System.assert(
          message.startsWith(
            '契約サービスの取引先と商談の取引先が一致しません'
          ),
          message
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown, '取引先不一致でエラーになること');
      System.assertEquals(
        'Estimate',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ]
        .historystatus__c,
        '拒否時は Estimate のまま'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :history.Id
        ],
        'エラー時は請求商品が作成されないこと'
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
      insert history;
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
      history.historystatus__c = 'Ordered';
      update history;
      Test.stopTest();

      System.assert(
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :history.Id
        ] > 0,
        '取引先一致時は請求商品が作成されること'
      );
    }
  }

  @IsTest
  static void estimateToOrdered_createsMonthlyInvoiceProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      Test.startTest();
      data.history.historystatus__c = 'Ordered';
      update data.history;
      Test.stopTest();
      List<InvoiceProduct__c> invoiceProducts = [
        SELECT StartDate__c, Enddate__c, Amount__c, TaxPercent__c, TaxAmount__c
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
      System.assertEquals(
        10,
        TaxCalculationUtil.resolveTaxPercent(
          TaxCalculationUtil.fromPercentFieldStorage(
            invoiceProducts[0].TaxPercent__c
          )
        )
      );
      System.assertEquals(
        null,
        invoiceProducts[0].TaxAmount__c,
        '請求商品行に税額は持たない'
      );
      List<Invoice__c> invoices = [
        SELECT InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :data.history.Id
        ORDER BY InvoiceDate__c ASC
      ];
      System.assert(!invoices.isEmpty(), '請求ヘッダが作成されること');
      for (Invoice__c invoice : invoices) {
        System.assertEquals(
          Date.newInstance(2026, 6, 1),
          invoice.InvoiceDate__c,
          '前請求は月次分割しても請求日は期間開始日で統一'
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
        '請求正本の税抜合計も期間明細合計と一致'
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
      data.history.historystatus__c = 'Ordered';
      update data.history;
      Test.stopTest();
      InvoiceProduct__c invoiceProduct = [
        SELECT Amount__c, TaxPercent__c, TaxAmount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id
        ORDER BY StartDate__c ASC
        LIMIT 1
      ];
      System.assertEquals(8000, invoiceProduct.Amount__c);
      System.assertEquals(
        8,
        TaxCalculationUtil.resolveTaxPercent(
          TaxCalculationUtil.fromPercentFieldStorage(
            invoiceProduct.TaxPercent__c
          )
        )
      );
      System.assertEquals(
        null,
        invoiceProduct.TaxAmount__c,
        '請求商品行に税額は持たない'
      );
    }
  }
  @IsTest
  static void estimateToOrdered_createsPositiveInvoiceProductsOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(true);
      Test.startTest();
      data.history.historystatus__c = 'Ordered';
      update data.history;
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
      data.recurringProduct.Unit__c = 'ID/月';
      update data.recurringProduct;
      Test.startTest();
      data.history.historystatus__c = 'Ordered';
      update data.history;
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
      System.assertEquals('ID/月', invoiceProduct.Unit__c);
      System.assertEquals(8000, invoiceProduct.Amount__c);
    }
  }
  @IsTest
  static void estimateToOrdered_createsSeparateLinesForDifferentUnit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      data.recurringProduct.Unit__c = 'ID/月';
      update data.recurringProduct;
      insert new ContractProduct__c(
        ContractHistory__c = data.history.Id,
        Product__c = data.recurringProduct.Product__c,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        Unit__c = '式/月',
        StartDate__c = data.recurringProduct.StartDate__c,
        Enddate__c = data.recurringProduct.Enddate__c,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Renew'
      );
      Test.startTest();
      data.history.historystatus__c = 'Ordered';
      update data.history;
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
      System.assertEquals('ID/月', juneLines[0].Unit__c);
      System.assertEquals(8000, juneLines[0].Amount__c);
      System.assertEquals('式/月', juneLines[1].Unit__c);
      System.assertEquals(8000, juneLines[1].Amount__c);
    }
  }
  @IsTest
  static void estimateToOrdered_copiesQuantityAndUnitPrice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TestData data = createHistoryWithProducts(false);
      Test.startTest();
      data.history.historystatus__c = 'Ordered';
      update data.history;
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
      data.history.historystatus__c = 'Ordered';
      update data.history;
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
      data.history.historystatus__c = 'Ordered';
      update data.history;
      Test.stopTest();
      List<InvoiceProduct__c> monthlyPeriodLines = [
        SELECT StartDate__c, Enddate__c, Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id AND Amount__c = 3000
        ORDER BY StartDate__c ASC
      ];
      System.assertEquals(12, monthlyPeriodLines.size());
      System.assertEquals(3000, monthlyPeriodLines[0].Amount__c);
      // 一括前払行と請求日が重なる月は同一 Invoice に集約されうるため、
      // 月次商品の InvoiceLine 件数で請求回数を検証する
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
        '月次請求は各月の開始日が請求日'
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
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_NEXT_MONTH_END,
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_5,
        BillingAddressee__c = 'テスト宛名',
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
      insert history;
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
      history.historystatus__c = 'Ordered';
      update history;
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
      data.recurringProduct.InvoiceSetting__c = '一括後払';
      update data.recurringProduct;
      Test.startTest();
      data.history.historystatus__c = 'Ordered';
      update data.history;
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
      data.history.historystatus__c = 'Ordered';
      update data.history;
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
      data.history.historystatus__c = 'Ordered';
      update data.history;
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
      data.history.historystatus__c = 'Ordered';
      update data.history;
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
      data.history.historystatus__c = 'Ordered';
      update data.history;
      Integer firstCount = [
        SELECT COUNT()
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :data.history.Id
      ];
      System.assertEquals(12, firstCount);
      data.recurringProduct.UnitPrice__c = 9000;
      update data.recurringProduct;
      Test.startTest();
      data.history.historystatus__c = 'Estimate';
      update data.history;
      data.history.historystatus__c = 'Ordered';
      update data.history;
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
      data.history.historystatus__c = 'Ordered';
      update data.history;
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
        '再生成拒否テスト用の請求があること'
      );
      for (Invoice__c invoice : lockedInvoices) {
        invoice.PaymentClearingCompletedDate__c = Date.today();
      }
      update lockedInvoices;
      data.recurringProduct.UnitPrice__c = 9000;
      update data.recurringProduct;
      Boolean thrown = false;
      Test.startTest();
      try {
        InvoiceProductGenerationService.generateForHistories(
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
        'ロック済み請求がある場合は再生成を拒否する'
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
        PaymentTerm__c = '翌月15日',
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
        BillingAddressee__c = 'テスト宛名',
        BillingEmailTo__c = 'to@example.com'
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      service.BiilingAcccount__c = billingAccount.Id;
      update service;
      Test.startTest();
      data.history.historystatus__c = 'Ordered';
      update data.history;
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
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_NEXT_MONTH_END,
        BillingAddressee__c = 'テスト宛名',
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
      insert history;
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
      history.historystatus__c = 'Ordered';
      update history;
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
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_5,
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_NEXT_MONTH_END,
        BillingAddressee__c = 'テスト宛名',
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
      insert history;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Prepaid Billing Day Product'
      );
      product.UnitName__c = 'ID';
      product.UnitPrice__c = 8000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
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
      history.historystatus__c = 'Ordered';
      update history;
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
      System.assert(!invoices.isEmpty(), '請求ヘッダが作成されること');
      for (Invoice__c invoice : invoices) {
        System.assertEquals(
          Date.newInstance(2026, 6, 5),
          invoice.InvoiceDate__c,
          '一括前払も請求アカウントの請求日ルールを請求日に反映する'
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
        PaymentTerm__c = '翌月15日',
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
        BillingAddressee__c = '株式会社スナップショット 御中',
        BillingEmailTo__c = 'billing-to@example.com',
        BillingEmailCc__c = 'billing-cc@example.com',
        BillingEmailBcc__c = 'billing-bcc@example.com'
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
      Product2 product = ContractTestDataFactory.buildProduct(
        'Snapshot Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Snapshot History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;
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
      history.historystatus__c = 'Ordered';
      update history;
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
          PaymentTermSnapShot__c,
          BillingDayOfMonthSnapShot__c,
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c,
          BillingEmailCcSnapShot__c,
          BillingEmailBccSnapShot__c
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
        ORDER BY InvoiceDate__c ASC
        LIMIT 1
      ];
      // BillingAccount__c → Invoice__c（ハードコード SnapShot）
      System.assertEquals(billingAccount.Id, invoice.BillingAccountSnapShot__c);
      System.assertEquals('翌月15日', invoice.PaymentTermSnapShot__c);
      System.assertEquals('25', invoice.BillingDayOfMonthSnapShot__c);
      System.assertEquals(
        '株式会社スナップショット 御中',
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
      // ContractProduct__c → 期間明細コア
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
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_SAME_DAY,
        BillingAddressee__c = 'テスト宛名',
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
      insert history;
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
      history.historystatus__c = 'Ordered';
      update history;
      Test.stopTest();
      Invoice__c invoice = [
        SELECT BillingDayOfMonthSnapShot__c
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
        ORDER BY InvoiceDate__c ASC
        LIMIT 1
      ];
      System.assertEquals(
        ContractTestDataFactory.TENANT_BILLING_DAY_SAME_DAY,
        invoice.BillingDayOfMonthSnapShot__c
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
    insert data.history;
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
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert priorHistory;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Invoice Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
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
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
      // 期間明細ロック廃止。Change 生成は V2 側のため prior ロック不要。
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
      insert changeHistory;
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
      Test.startTest();
      changeHistory.historystatus__c = 'Ordered';
      update changeHistory;
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
      System.assertEquals(16, changeInvoices.size(), '±2行×8ヶ月');
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
        'Change初回請求期間は有効日を請求日にする'
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
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert priorHistory;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Prior Locked Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
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
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
      List<Invoice__c> priorInvoices = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :priorHistory.Id
      ];
      System.assert(!priorInvoices.isEmpty(), 'prior 請求があること');
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
      insert changeHistory;
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

      Test.startTest();
      changeHistory.historystatus__c = 'Ordered';
      update changeHistory;
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
        'prior 請求ロックでも Change 側の期間明細は生成される'
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
        'prior ロック請求は残る'
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
      insert priorHistory;
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
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
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
      insert changeHistory;
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = recurringProduct.Id,
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
        Product__c = recurringProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );
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
      Test.startTest();
      changeHistory.historystatus__c = 'Ordered';
      update changeHistory;
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
        'Changeの一回課金追加商品に請求商品が1件生成される'
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
        '継続課金に変更がない Change では継続課金の差分合計は0'
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
      // 一回課金 New 追加のみ → 期中有効日可。継続課金 Remake は内容同一の据え置き。
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
      insert priorHistory;
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
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
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
      insert changeHistory;
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = recurringProduct.Id,
        Quantity__c = 900,
        UnitPrice__c = 500,
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
        Product__c = recurringProduct.Id,
        Quantity__c = 900,
        UnitPrice__c = 500,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );
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

      Test.startTest();
      changeHistory.historystatus__c = 'Ordered';
      update changeHistory;
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
        '据え置き継続課金は期中有効日でも period key 偽差分を出さない'
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
        'Change 受注の請求商品合計は一回課金追加分のみ'
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
      '境界上はその日'
    );
    System.assertEquals(
      Date.newInstance(2025, 9, 1),
      InvoiceProductGenerationService.resolveFirstMonthlyPeriodStartOnOrAfter(
        anchor,
        Date.newInstance(2025, 8, 29)
      ),
      '期中は次の明細開始日起点境界'
    );
    System.assertEquals(
      anchor,
      InvoiceProductGenerationService.resolveFirstMonthlyPeriodStartOnOrAfter(
        anchor,
        Date.newInstance(2025, 6, 15)
      ),
      'アンカー前はアンカーへ'
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
      insert priorHistory;
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
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
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
      insert changeHistory;
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
      Boolean thrown = false;
      Test.startTest();
      try {
        changeHistory.historystatus__c = 'Ordered';
        update changeHistory;
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          '前回Versionの期間終了日と一致する継続課金商品がないためChangeできません。',
          dmlMessage(ex)
        );
      }
      Test.stopTest();
      System.assertEquals(
        true,
        thrown,
        '継続課金のない Change は請求生成前に拒否される'
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
      // 単価変更が期首からなので有効日も期首（受注前検証を通す）
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
      insert priorHistory;
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
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
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
      insert changeHistory;
      // Data Loader 改変相当: Original 単価を past と不一致にして紐付け不能にする
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
      Test.startTest();
      try {
        changeHistory.historystatus__c = 'Ordered';
        update changeHistory;
      } catch (Exception ex) {
        thrown = true;
        message = dmlMessage(ex);
      }
      Test.stopTest();
      System.assertEquals(
        true,
        thrown,
        '打消し紐付け失敗時は受注を Fail closed で止める（黙殺してプラスだけ残さない）'
      );
      System.assert(
        message != null &&
          message.startsWith(
            'Change の打消し行を Original に紐づけられませんでした。'
          ),
        'Fail closed メッセージ: ' + message
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
        'Fail closed 時は請求期間明細を残さない'
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
      insert priorHistory;
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
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
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
      insert changeHistory;
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
      Test.startTest();
      try {
        changeHistory.historystatus__c = 'Ordered';
        update changeHistory;
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          '前回Versionの継続課金商品すべてにOriginal行が必要です。',
          dmlMessage(ex)
        );
      }
      Test.stopTest();
      System.assertEquals(
        true,
        thrown,
        'Original なしの Change は請求生成前に拒否される'
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
      renewData.history.historystatus__c = 'Ordered';
      update renewData.history;
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
      insert newHistory;
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
      newHistory.historystatus__c = 'Ordered';
      update newHistory;
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
      '正金額は打消しより優先'
    );
    System.assertEquals(
      true,
      InvoiceProductGenerationService.isPreferredPastSample(positive, zero),
      '正金額は0より優先'
    );
    System.assertEquals(
      false,
      InvoiceProductGenerationService.isPreferredPastSample(negative, positive),
      '打消しは正金額を上書きしない'
    );
    System.assertEquals(
      false,
      InvoiceProductGenerationService.isPreferredPastSample(positive, positive),
      '同符号は先勝ち（既存維持）'
    );
  }

  /**
   * Change→Change の単価改定2回。V2 打消しが CreatedDate 上で先でも、
   * 正金額サンプル優先により V3 受注が fail-closed しないこと。
   * V1/V2 は Ordered 直 insert（空 generate）＋期間明細手積みで SOQL を抑える。
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
      insert v1;
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
        Amount__c = 8000,
        invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
      );

      // past シード専用。Type=New の空 generate を使い、Change 受注経路の二重実行を避ける
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
      insert v2;
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
        Amount__c = -8000,
        invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
      );
      InvoiceProduct__c v2Charge = new InvoiceProduct__c(
        ContractHistory__c = v2.Id,
        ContractProduct__c = v2Remake.Id,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceBucketKey__c = v2Bucket,
        Quantity__c = 1,
        UnitPrice__c = 9000,
        Amount__c = 9000,
        invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
      );
      insert new List<InvoiceProduct__c>{ v2Reversal, v2Charge };
      Test.setCreatedDate(
        v2Charge.Id,
        Datetime.newInstance(2026, 1, 1, 0, 0, 0)
      );
      Test.setCreatedDate(
        v2Reversal.Id,
        Datetime.newInstance(2026, 1, 2, 0, 0, 0)
      );

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
      insert v3;
      insert new ContractProduct__c(
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
      );
      insert new ContractProduct__c(
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
      );

      Test.startTest();
      v3.historystatus__c = 'Ordered';
      update v3;
      Test.stopTest();

      System.assertEquals(
        'Ordered',
        [SELECT historystatus__c FROM ContractHistory__c WHERE Id = :v3.Id]
        .historystatus__c,
        'V3 受注がサンプル揺れで失敗しないこと'
      );
      assertReversalInvoiceProductsUseOriginalContractProduct(v3.Id);
      Decimal v3Net = (Decimal) [
          SELECT SUM(Amount__c) totalAmount
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :v3.Id
        ][0]
        .get('totalAmount');
      // 1ヶ月 × (10000 - 9000) = 1000
      System.assertEquals(1000, v3Net, 'V3 ネットは差分のみ');
      for (InvoiceProduct__c reversal : [
        SELECT Amount__c, UnitPrice__c, ContractProduct__r.UnitPrice__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :v3.Id AND Amount__c < 0
      ]) {
        System.assertEquals(
          9000,
          reversal.ContractProduct__r.UnitPrice__c,
          '打消しは V2 条件（9000）の Original に紐づく'
        );
      }
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
      '反転行は生成されない'
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
        '反転行は Original 契約商品に紐づく'
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
      insert priorHistory;
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
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
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
      insert renewHistory;
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
      Test.startTest();
      renewHistory.historystatus__c = 'Ordered';
      update renewHistory;
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
        'Renew は更新期間の継続課金12行のみ生成'
      );
      for (InvoiceProduct__c invoiceProduct : renewInvoices) {
        System.assert(invoiceProduct.Amount__c > 0, 'Renew に反転行なし');
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
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_15,
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_NEXT_MONTH_END,
        BillingAddressee__c = 'テスト宛名',
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
      Date effectiveDate = Date.newInstance(2026, 10, 10);
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
      insert priorHistory;
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
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
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
      insert changeHistory;
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
      Test.startTest();
      changeHistory.historystatus__c = 'Ordered';
      update changeHistory;
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
        'Change初回も請求アカウントの毎月指定日'
      );
      System.assertEquals(
        Date.newInstance(2026, 11, 15),
        changeInvoices[1].InvoiceDate__c,
        '2ヶ月目以降も請求アカウントの毎月指定日'
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
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_5,
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_NEXT_MONTH_END,
        BillingAddressee__c = 'テスト宛名',
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
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert priorHistory;
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
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
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
      insert changeHistory;
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = priorQuantity,
        UnitPrice__c = priorUnitPrice,
        Amount__c = -1,
        StartDate__c = Date.newInstance(2027, 2, 1),
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = product.Id,
        Quantity__c = priorQuantity,
        UnitPrice__c = priorUnitPrice,
        Amount__c = 1,
        StartDate__c = Date.newInstance(2027, 2, 1),
        Enddate__c = effectiveDate.addDays(-1),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );
      insert new ContractProduct__c(
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
      );
      insert new ContractProduct__c(
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
      );
      Test.startTest();
      changeHistory.historystatus__c = 'Ordered';
      update changeHistory;
      Test.stopTest();
      List<InvoiceProduct__c> changeInvoices = [
        SELECT Amount__c, StartDate__c, ContractProduct__r.Type__c
        FROM InvoiceProduct__c
        WHERE
          ContractHistory__c = :changeHistory.Id
          AND StartDate__c >= :effectiveDate
        ORDER BY StartDate__c ASC, Amount__c ASC
      ];
      System.assertEquals(6, changeInvoices.size(), '4〜6月は ±2 行 × 3 ヶ月');
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
        'Change × 一括前払は有効日基準の請求日'
      );
      System.assertEquals(
        expectedPaymentScheduledDate,
        changeInvoiceHeader.PaymentScheduledDate__c,
        'Change × 一括前払は有効日基準の入金予定日'
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
      System.assertNotEquals(null, juneCharge, '6月の請求行');
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
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_5,
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_NEXT_MONTH_END,
        BillingAddressee__c = 'テスト宛名',
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
      // 継続課金に内容差分がない場合、課金イベントは一回課金開始日のみ。
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
      insert priorHistory;
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
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
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
      insert changeHistory;
      insert new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = recurringProduct.Id,
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
        Product__c = recurringProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 1,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorContractProduct.Id
      );
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
      Test.startTest();
      changeHistory.historystatus__c = 'Ordered';
      update changeHistory;
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
        'Change × 一回 × 一括前払×Newは商品開始日基準'
      );
      System.assertEquals(
        expectedPaymentScheduledDate,
        addonHeader.PaymentScheduledDate__c,
        'Change × 一回 × 一括前払の入金予定日'
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
        '据え置き継続課金（一括前払）も期中有効日で偽差分を出さない'
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
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_SAME_DAY,
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        BillingAddressee__c = 'テスト宛名',
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
      insert priorHistory;
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
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
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
      insert changeHistory;
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
      Test.startTest();
      changeHistory.historystatus__c = 'Ordered';
      update changeHistory;
      Test.stopTest();
      List<InvoiceProduct__c> changePeriodLines = [
        SELECT StartDate__c, Enddate__c, Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :changeHistory.Id
      ];
      System.assert(
        !changePeriodLines.isEmpty(),
        '期中停止（単価0フルカバー Remake）でも請求商品が作られる'
      );
      List<Invoice__c> changeInvoices = [
        SELECT InvoiceDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :changeHistory.Id
      ];
      System.assert(!changeInvoices.isEmpty(), '請求ヘッダが作成されること');
      for (Invoice__c changeInvoice : changeInvoices) {
        System.assertEquals(
          effectiveDate,
          changeInvoice.InvoiceDate__c,
          'Starter相当: Change × 一括前払は商品開始日ではなく有効日が請求基準日'
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
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_SAME_DAY,
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        BillingAddressee__c = 'テスト宛名',
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
      insert priorHistory;
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
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
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
      insert changeHistory;
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
        // Estimate 直呼びは Ordered 不変条件で拒否されるため、受注経路でカバー検証する
        changeHistory.historystatus__c = 'Ordered';
        update changeHistory;
      } catch (Exception ex) {
        thrown = true;
        message = dmlMessage(ex);
      }
      System.assertEquals(true, thrown, '隙間 Remake の Change は受注できない');
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
        '拒否時は請求商品が作られない'
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
      insert priorHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Dual Lineage Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
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

      // ARR 再計算＋請求生成の SOQL を startTest 枠内へ寄せる
      Test.startTest();
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
      // 期間明細ロック廃止。Change 生成は V2 側のため prior ロック不要。

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
      insert changeHistory;

      // 系統1: 4-9月。有効日7/1以降だけ数量2へ。系統2: 10-3月。変更なし。
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

      changeHistory.historystatus__c = 'Ordered';
      update changeHistory;

      List<InvoiceProduct__c> changeInvoices = [
        SELECT Amount__c, Quantity__c, StartDate__c, Enddate__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :changeHistory.Id
        ORDER BY StartDate__c ASC, Amount__c ASC
      ];
      Test.stopTest();

      // 系統単位なら 7-9月のみ差分（取消+新規）×3ヶ月 = 6行。
      // Product2 単位で潰すと有効日前の穴や誤差分が出る。
      System.assertEquals(
        6,
        changeInvoices.size(),
        '同一商品でも系統別なら有効日以降3ヶ月の±のみ'
      );
      for (InvoiceProduct__c changeInvoice : changeInvoices) {
        System.assert(
          changeInvoice.StartDate__c >= effectiveDate,
          '差分請求は有効日以降のみ'
        );
        System.assert(
          changeInvoice.Enddate__c <= firstEnd,
          '系統1の期間内に収まる'
        );
      }
      Decimal totalAmount = 0;
      for (InvoiceProduct__c changeInvoice : changeInvoices) {
        totalAmount += changeInvoice.Amount__c;
      }
      System.assertEquals(30000, totalAmount, '数量1→2の差分 10000×3ヶ月');
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
      // Remake②の途中。As-Is では 6月が欠落して過剰 reversal になり得た。
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
      insert priorHistory;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Change Multi Remake Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
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

      Test.startTest();
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ priorHistory.Id }
      );
      // 期間明細ロック廃止。Change 生成は V2 側のため prior ロック不要。

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
      insert changeHistory;

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

      changeHistory.historystatus__c = 'Ordered';
      update changeHistory;

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
          '有効日前は Original=過去と一致するため差分行は出ない: ' +
          String.valueOf(changeInvoice.StartDate__c)
        );
        System.assertNotEquals(
          null,
          changeInvoice.ContractProduct__c,
          '請求明細は契約商品に紐づく必要がある'
        );
        if (changeInvoice.Amount__c != null && changeInvoice.Amount__c > 0) {
          System.assertEquals(
            'Remake',
            changeInvoice.ContractProduct__r.Type__c,
            'プラス請求は Remake 契約商品へ帰属すること'
          );
          System.assertEquals(
            2,
            changeInvoice.ContractProduct__r.Quantity__c,
            'プラス請求の数量は該当 Remake と一致すること（最後のRemake勝ち禁止）'
          );
        }
      }

      // 7月〜翌3月 = 9ヶ月 × 数量差分10000
      Decimal totalAmount = 0;
      for (InvoiceProduct__c changeInvoice : changeInvoices) {
        totalAmount += changeInvoice.Amount__c == null
          ? 0
          : changeInvoice.Amount__c;
      }
      System.assertEquals(
        90000,
        totalAmount,
        '6月欠落による過剰 reversal がなく、7月以降9ヶ月分のみ'
      );
      System.assertEquals(18, changeInvoices.size(), '±2行×9ヶ月');
    }
  }

  /** Trigger / Exception ラッパを剥がして業務メッセージ本体を返す */
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
