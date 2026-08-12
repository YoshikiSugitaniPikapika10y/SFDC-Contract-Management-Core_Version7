@IsTest
private class ContractArrCalculationServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void calculateProductArr_respectsIncludeInArrFlag() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'ARR Unit Account'
      );
      Date termEnd = ContractTestDataFactory.stableTermEnd();

      ContractService__c service = new ContractService__c(
        Name = 'ARR Unit Service',
        Account__c = account.Id
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'ARR Unit History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.today(),
        CurrentTermEndDate__c = termEnd
      );
      insert history;

      // 12ヶ月・Amount=60000 → ARR=60000（ウィザード金額ベース）
      ContractProduct__c line = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Quantity__c = 1,
        UnitPrice__c = 5000,
        Amount__c = 60000,
        StartDate__c = ContractTestDataFactory.stableTermStart(),
        Enddate__c = termEnd,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      line.Product__r = new Product2(
        IncludeInARR__c = true,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      );
      System.assertEquals(
        60000,
        ContractArrCalculationService.calculateProductArr(line, termEnd),
        'ARR計算対象ONなら契約商品Amountを年換算する'
      );

      // 端数月でも Currency scale=2 に収める
      line.Amount__c = 10001;
      line.StartDate__c = ContractTestDataFactory.stableTermStart();
      line.Enddate__c = ContractTestDataFactory.stableTermEnd(3);
      System.assertEquals(
        40004,
        ContractArrCalculationService.calculateProductArr(
          line,
          ContractTestDataFactory.stableTermEnd(3)
        ),
        'Amount÷月数×12 を scale=2 HALF_UP'
      );

      line.Product__r = new Product2(
        IncludeInARR__c = false,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      );
      System.assertEquals(
        0,
        ContractArrCalculationService.calculateProductArr(line, termEnd),
        'ARR計算対象OFFなら0'
      );
    }
  }

  @IsTest
  static void recalculateForHistories_excludesOriginalAndShortTermProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'ARR Filter Account'
      );

      Product2 product = ContractTestDataFactory.buildProduct(
        'ARR Filter Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 5000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();

      ContractService__c service = new ContractService__c(
        Name = 'ARR Filter Service',
        Account__c = account.Id
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'ARR Filter History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      insert history;

      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 5000,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'New'
        ),
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 5000,
          StartDate__c = termStart,
          Enddate__c = ContractTestDataFactory.stableTermEnd(6),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Original'
        )
      };

      history = [
        SELECT ARR__c, AveARR__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(60000, history.ARR__c);
      System.assertEquals(
        60000,
        history.AveARR__c,
        'フラット満了なら AveARR は ARR と同値'
      );
    }
  }

  @IsTest
  static void recalculateForHistories_aveArrIncludesMidTermLines() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'AveARR Mid Account'
      );

      Product2 product = ContractTestDataFactory.buildProduct(
        'AveARR Mid Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 10000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date midEnd = ContractTestDataFactory.stableTermEnd(6);
      Date termEnd = ContractTestDataFactory.stableTermEnd(12);
      Date secondStart = midEnd.addDays(1);

      ContractService__c service = new ContractService__c(
        Name = 'AveARR Mid Service',
        Account__c = account.Id
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'AveARR Mid History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      insert history;

      // 前半6か月 Amount=30000（月5,000）→ 期末に届かないので ARR 外
      // 後半6か月 Amount=60000（月10,000）→ ARR=120,000
      // AveARR = (30000+60000)/12*12 = 90,000
      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 5000,
          Amount__c = 30000,
          StartDate__c = termStart,
          Enddate__c = midEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'New'
        ),
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 60000,
          StartDate__c = secondStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake'
        )
      };

      history = [
        SELECT ARR__c, AveARR__c, DeltaAveARR__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(120000, history.ARR__c, '期末到達明細のみ ARR');
      System.assertEquals(
        90000,
        history.AveARR__c,
        '期中明細も分子に含めた期間平均'
      );
      System.assertEquals(
        90000,
        history.DeltaAveARR__c,
        'Version1 の △AveARR は AveARR と同値'
      );
    }
  }

  @IsTest
  static void recalculateForHistories_excludesProductsWithoutIncludeInArrFlag() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'ARR Flag Account'
      );

      Product2 product = ContractTestDataFactory.buildProduct(
        'ARR Flag Off Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 10000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product, false);

      Date termEnd = ContractTestDataFactory.stableTermEnd();

      ContractService__c service = new ContractService__c(
        Name = 'ARR Flag Service',
        Account__c = account.Id
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'ARR Flag History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.today(),
        CurrentTermEndDate__c = termEnd
      );
      insert history;

      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        StartDate__c = Date.today(),
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );

      history = [
        SELECT ARR__c, AveARR__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(
        0,
        history.ARR__c,
        'ARR計算対象OFFの商品はARRに含めない'
      );
      System.assertEquals(
        0,
        history.AveARR__c,
        'ARR計算対象OFFの商品はAveARRにも含めない'
      );
    }
  }
}
