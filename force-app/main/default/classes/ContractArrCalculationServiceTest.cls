@IsTest
private class ContractArrCalculationServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void calculateProductArr_usesSavedAmountCyclesAndEligibility() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'ARR Unit Account'
      );
      Date termEnd = ContractTestDataFactory.stableTermEnd();

      ContractService__c service = new ContractService__c(
        Name = 'ARR Unit Service',
        Account__c = account.Id
      );
      ContractTestDataFactory.applyRequiredFields(service);
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
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        account.Id
      );
      insert history;

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
        'Core 第10.1節: 保存Amount 60000÷12サイクル×12=60000'
      );

      line.Amount__c = 7000;
      line.StartDate__c = ContractTestDataFactory.stableTermStart();
      line.Enddate__c = ContractTestDataFactory.stableTermEnd(7);
      System.assertEquals(
        12000,
        ContractArrCalculationService.calculateProductArr(
          line,
          ContractTestDataFactory.stableTermEnd(7)
        ),
        'Core 第10.1節: 保存Amount 7000÷7サイクル×12=12000'
      );

      line.Amount__c = -7000;
      System.assertEquals(
        -12000,
        ContractArrCalculationService.calculateProductArr(
          line,
          ContractTestDataFactory.stableTermEnd(7)
        ),
        'Core 第10.1節: 負の保存Amountも符号付きで年換算する'
      );

      line.StartDate__c = Date.newInstance(2025, 1, 31);
      line.Enddate__c = Date.newInstance(2026, 1, 27);
      line.Amount__c = 60000;
      System.assertEquals(
        60000,
        ContractArrCalculationService.calculateProductArr(
          line,
          Date.newInstance(2026, 1, 27)
        ),
        'Core 第10.1節・共通基盤日付第1.1節: 1月31日起点の12積上げサイクルで年換算する'
      );

      System.assertEquals(
        0,
        ContractArrCalculationService.calculateProductArr(
          line,
          Date.newInstance(2026, 1, 28)
        ),
        'Core 第10.1節: 明細終了日が履歴終了日に届かない行は対象外'
      );
      System.assertEquals(
        0,
        ContractArrCalculationService.calculateProductArr(line, null),
        'Core 第10.1節: 履歴終了日が空なら期末到達を判定できず対象外'
      );

      line.Enddate__c = Date.newInstance(2026, 1, 27);
      line.Amount__c = 0;
      System.assertEquals(
        0,
        ContractArrCalculationService.calculateProductArr(
          line,
          Date.newInstance(2026, 1, 27)
        ),
        'Core 第10.1節: 金額0は対象外'
      );

      line.Amount__c = 60000;
      for (Decimal excludedQuantity : new List<Decimal>{ null, 0, -1 }) {
        line.Quantity__c = excludedQuantity;
        System.assertEquals(
          0,
          ContractArrCalculationService.calculateProductArr(
            line,
            Date.newInstance(2026, 1, 27)
          ),
          'Core 第10.1節: 数量は0・空・負を除き正数だけが対象'
        );
      }
      line.Quantity__c = 1;

      line.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      System.assertEquals(
        0,
        ContractArrCalculationService.calculateProductArr(
          line,
          Date.newInstance(2026, 1, 27)
        ),
        'Core 第10.1節: Spotで用いる一回課金はARR対象外'
      );
      line.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;

      line.Type__c = 'Original';
      System.assertEquals(
        0,
        ContractArrCalculationService.calculateProductArr(
          line,
          Date.newInstance(2026, 1, 27)
        ),
        'Core 第10.1節: OriginalはARR対象外'
      );
      line.Type__c = 'New';

      line.Product__r = new Product2(
        IncludeInARR__c = false,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      );
      System.assertEquals(
        0,
        ContractArrCalculationService.calculateProductArr(
          line,
          Date.newInstance(2026, 1, 27)
        ),
        'Core 第10.1節: ARR対象OFFの商品は対象外'
      );
    }
  }

  @IsTest
  static void recalculateForHistories_persistsTotalsAndExcludesOriginal() {
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
      ContractTestDataFactory.applyRequiredFields(service);
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
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        account.Id
      );
      insert history;

      ContractProduct__c included = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Account__c = account.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 5000,
        Amount__c = 60000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      ContractProduct__c original = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Account__c = account.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 5000,
        StartDate__c = termStart,
        Enddate__c = ContractTestDataFactory.stableTermEnd(6),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original'
      );
      ContractTestDataFactory.applyRequiredFields(included);
      ContractTestDataFactory.applyRequiredFields(original);
      insert new List<ContractProduct__c>{ included, original };

      history = [
        SELECT ARR__c, AveARR__c, DeltaARR__c, DeltaAveARR__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(
        60000,
        history.ARR__c,
        'Core 第10.1節: 対象明細の年換算額を履歴ARRへ保存する'
      );
      System.assertEquals(
        60000,
        history.AveARR__c,
        'Core 第10.2節: 60000÷履歴12サイクル×12=60000を保存する'
      );
      System.assertEquals(
        60000,
        history.DeltaARR__c,
        'Core 第10.1節: Version 1のDeltaARRは当該ARR'
      );
      System.assertEquals(
        60000,
        history.DeltaAveARR__c,
        'Core 第10.2節: Version 1のDeltaAveARRは当該AveARR'
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
      ContractTestDataFactory.applyRequiredFields(service);
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
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        account.Id
      );
      insert history;

      // 前半6か月 Amount=30000（月5,000）→ 期末に届かないので ARR 外
      // 後半6か月 Amount=60000（月10,000）→ ARR=120,000
      // AveARR = (30000+60000)/12*12 = 90,000
      insert new List<ContractProduct__c>{
        applyContractProduct(
          new ContractProduct__c(
            ContractHistory__c = history.Id,
            Account__c = account.Id,
            Product__c = product.Id,
            Quantity__c = 1,
            UnitPrice__c = 5000,
            Amount__c = 30000,
            StartDate__c = termStart,
            Enddate__c = midEnd,
            InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
            BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
            Type__c = 'New'
          )
        ),
        applyContractProduct(
          new ContractProduct__c(
            ContractHistory__c = history.Id,
            Account__c = account.Id,
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
        )
      };

      history = [
        SELECT ARR__c, AveARR__c, DeltaAveARR__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(
        120000,
        history.ARR__c,
        'Core 第10.1節: 期末到達明細60000÷6サイクル×12=120000だけをARRへ合計する'
      );
      System.assertEquals(
        90000,
        history.AveARR__c,
        'Core 第10.2節: (期中停止30000+期末到達60000)÷履歴12サイクル×12=90000'
      );
      System.assertEquals(
        90000,
        history.DeltaAveARR__c,
        'Core 第10.2節: Version 1のDeltaAveARRは当該AveARR'
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
      ContractTestDataFactory.applyRequiredFields(service);
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
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        account.Id
      );
      insert history;

      insert applyContractProduct(
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Account__c = account.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          StartDate__c = Date.today(),
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'New'
        )
      );

      history = [
        SELECT ARR__c, AveARR__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(
        0,
        history.ARR__c,
        'Core 第10.1節: ARR対象OFFの商品はARRに含めず0を保存する'
      );
      System.assertEquals(
        0,
        history.AveARR__c,
        'Core 第10.2節: ARR対象OFFの商品はAveARRにも含めず0を保存する'
      );
    }
  }

  @IsTest
  static void calculateProductMetrics_blankAmount_throwsWithoutFallback() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'ARR Blank Amount Account'
      );
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractService__c service = new ContractService__c(
        Name = 'ARR Blank Amount Service',
        Account__c = account.Id
      );
      ContractTestDataFactory.applyRequiredFields(service);
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'ARR Blank Amount History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = ContractTestDataFactory.stableTermStart(),
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        account.Id
      );
      insert history;
      ContractProduct__c line = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Quantity__c = 1,
        UnitPrice__c = 5000,
        Amount__c = null,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New',
        StartDate__c = ContractTestDataFactory.stableTermStart(),
        Enddate__c = termEnd
      );
      line.Product__r = new Product2(
        IncludeInARR__c = true,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      );
      Boolean arrThrown = false;
      try {
        ContractArrCalculationService.calculateProductArr(line, termEnd);
      } catch (ContractArrCalculationService.ArrException ex) {
        arrThrown = true;
        System.assert(
          ex.getMessage().contains('ARR対象明細の金額が空です。'),
          'Core 第10.1節: 金額が空の明細は数量×単価で埋めずエラー。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        arrThrown,
        'Core 第10.1節: 金額空は数量×単価で埋めずARRエラー'
      );

      Boolean aveArrThrown = false;
      try {
        ContractArrCalculationService.calculateProductAveArrPeriodAmount(line);
      } catch (ContractArrCalculationService.ArrException ex) {
        aveArrThrown = true;
        System.assert(
          ex.getMessage().contains('AveARR対象明細の金額が空です。'),
          'Core 第10.2節: 金額が空の明細は数量×単価で埋めずエラー。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        aveArrThrown,
        'Core 第10.2節: 金額空は数量×単価で埋めずAveARRエラー'
      );

      line.Amount__c = 0;
      System.assertEquals(
        0,
        ContractArrCalculationService.calculateProductAveArrPeriodAmount(line),
        'Core 第10.2節: 金額0はAveARR対象外'
      );
      line.Amount__c = -12345;
      System.assertEquals(
        -12345,
        ContractArrCalculationService.calculateProductAveArrPeriodAmount(line),
        'Core 第10.2節: 期中停止を含む対象明細の負の保存Amountも符号付きで分子へ含める'
      );
    }
  }

  @IsTest
  static void recalculateForHistories_deferCoalescesToOnePass() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('ARR Defer Account');
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractService__c service = new ContractService__c(
        Name = 'ARR Defer Service',
        Account__c = account.Id
      );
      ContractTestDataFactory.applyRequiredFields(service);
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'ARR Defer History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = ContractTestDataFactory.stableTermStart(),
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
      insert history;
      Product2 product = ContractTestDataFactory.buildProduct('ARR Defer Product');
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 5000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.IncludeInARR__c = true;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c line = applyContractProduct(
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Account__c = account.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 5000,
          Amount__c = 60000,
          StartDate__c = ContractTestDataFactory.stableTermStart(),
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'New'
        )
      );
      insert line;

      Test.startTest();
      ContractArrCalculationService.beginRecalcDefer();
      ContractArrCalculationService.recalculateForHistories(new Set<Id>{ history.Id });
      Integer queriesAfterQueue = Limits.getQueries();
      ContractArrCalculationService.recalculateForHistories(new Set<Id>{ history.Id });
      System.assertEquals(
        queriesAfterQueue,
        Limits.getQueries(),
        'Core 第4.3節: 見積保存1処理の ARR 再計算は保留して繰り返さない'
      );
      ContractArrCalculationService.endRecalcDefer();
      Test.stopTest();
      ContractHistory__c stored = [
        SELECT ARR__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(
        60000,
        stored.ARR__c,
        'Core 第10.1節: 保留解除後に60000÷12サイクル×12=60000を保存する'
      );
    }
  }

  @IsTest
  static void endRecalcDefer_reusesRememberedHistoryAndProducts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'ARR Remember Account'
      );
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractService__c service = new ContractService__c(
        Name = 'ARR Remember Service',
        Account__c = account.Id
      );
      ContractTestDataFactory.applyRequiredFields(service);
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'ARR Remember History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = ContractTestDataFactory.stableTermStart(),
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
      insert history;
      Product2 product = ContractTestDataFactory.buildProduct(
        'ARR Remember Product'
      );
      product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
      product.UnitPrice__c = 5000;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.IncludeInARR__c = true;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c line = applyContractProduct(
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Account__c = account.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 5000,
          Amount__c = 60000,
          StartDate__c = ContractTestDataFactory.stableTermStart(),
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'New'
        )
      );
      insert line;
      line = [
        SELECT
          ContractHistory__c,
          Amount__c,
          Quantity__c,
          UnitPrice__c,
          BillingType__c,
          Type__c,
          StartDate__c,
          Enddate__c,
          Product__r.BillingType__c,
          Product__r.IncludeInARR__c
        FROM ContractProduct__c
        WHERE Id = :line.Id
      ];

      Test.startTest();
      ContractArrCalculationService.beginRecalcDefer();
      ContractArrCalculationService.rememberHistoriesForRecalc(
        new List<ContractHistory__c>{ history }
      );
      ContractArrCalculationService.rememberProductsForRecalc(
        new List<ContractProduct__c>{ line }
      );
      ContractArrCalculationService.recalculateForHistories(
        new Set<Id>{ history.Id }
      );
      ContractArrCalculationService.endRecalcDefer();
      Test.stopTest();
      ContractHistory__c stored = [
        SELECT ARR__c, AveARR__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(
        60000,
        stored.ARR__c,
        'Core 第10.1節: Estimate段階でもARR 60000を保持する'
      );
      System.assertEquals(
        60000,
        stored.AveARR__c,
        'Core 第10.2節: Estimate段階でもAveARR 60000を保持する'
      );
    }
  }

  private static ContractProduct__c applyContractProduct(ContractProduct__c product) {
    if (String.isBlank(product.RevenueRecognitionBasis__c)) {
      product.RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
    }
    ContractTestDataFactory.applyRequiredFields(product);
    return product;
  }
}
