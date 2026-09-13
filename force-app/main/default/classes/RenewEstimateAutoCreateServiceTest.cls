@IsTest
private class RenewEstimateAutoCreateServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  @IsTest
  static void renewalOpportunityInsert_createsLinkedRenewEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableRenewOpportunity();
      TestData data = createSourceData(true);

      Test.startTest();
      Opportunity renewal = insertRenewalOpportunity(data);
      Test.stopTest();

      ContractHistory__c created = [
        SELECT
          Opportunity__c,
          ContractService__c,
          PreviousHistory__c,
          Type__c,
          historystatus__c,
          RenewEstimateAutoCreated__c,
          CurrentTermStartDate__c,
          CurrentTermEndDate__c,
          EffectiveDate__c,
          ApplicationDate__c,
          EstimateDate__c,
          EstimateValidDate__c
        FROM ContractHistory__c
        WHERE Opportunity__c = :renewal.Id
        LIMIT 1
      ];
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Opportunity__c = :renewal.Id
        ],
        'Core 第4.9節: 更新商談の作成と自動Renew見積の作成はセットであり、作成Renewは1件'
      );
      System.assertEquals(
        renewal.Id,
        created.Opportunity__c,
        'Core 第4.9節: 作成Renewの商談は起点の更新商談'
      );
      System.assertEquals(
        data.service.Id,
        created.ContractService__c,
        'Core 第4.9節: 作成Renewは更新商談と同じ契約サービス'
      );
      System.assertEquals(
        data.sourceHistory.Id,
        created.PreviousHistory__c,
        'Core 第4.9節: 作成Renewの前回履歴は元Ordered'
      );
      System.assertEquals(
        'Renew',
        created.Type__c,
        'Core 第4.9節: 自動作成する見積種別はRenew'
      );
      System.assertEquals(
        'Estimate',
        created.historystatus__c,
        'Core 第4.9節: 自動作成後は編集できるEstimate'
      );
      System.assertEquals(
        true,
        created.RenewEstimateAutoCreated__c,
        'Core 第4.9節: パッケージの自動作成だけが自動Renew見積をTrueにする'
      );
      System.assertEquals(
        data.sourceHistory.CurrentTermEndDate__c.addDays(1),
        created.CurrentTermStartDate__c,
        '日付仕様 第2.4節: Renew開始日は元Orderedの期間終了日の翌日'
      );
      System.assertEquals(
        Date.newInstance(2027, 5, 31),
        created.CurrentTermEndDate__c,
        '日付仕様 第1.1節・第2.4〜2.5節: Renew開始日から既定12サイクルを積み上げる'
      );
      System.assertEquals(
        created.CurrentTermStartDate__c,
        created.EffectiveDate__c,
        '日付仕様 第2.2節: Renewの切替日は期間開始日'
      );
      System.assertEquals(
        null,
        created.ApplicationDate__c,
        'Core 第4.9節: 申込日は前Orderedからコピーせず空のまま作る'
      );
      System.assertEquals(
        null,
        created.EstimateDate__c,
        'Core 第4.9節・第11.4.2節: 見積日はApexで書かない'
      );
      System.assertEquals(
        null,
        created.EstimateValidDate__c,
        'Core 第4.9節・第11.4.2節: 有効期限はApexで書かない'
      );

      ContractProduct__c createdProduct = [
        SELECT
          PreviousContractProduct__c,
          Account__c,
          Product__c,
          Quantity__c,
          UnitPrice__c,
          Amount__c,
          Unit__c,
          StartDate__c,
          Enddate__c,
          InvoiceSetting__c,
          BillingType__c,
          RevenueRecognitionBasis__c,
          Type__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :created.Id
        LIMIT 1
      ];
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractProduct__c
          WHERE ContractHistory__c = :created.Id
        ],
        'Core 第4.9節: 期末へ届く対象継続課金明細を重複なく継承する'
      );
      System.assertEquals(
        data.sourceProduct.Id,
        createdProduct.PreviousContractProduct__c,
        'Core 第4.9節: 自動Renew商品は継承元の見積商品を保持する'
      );
      System.assertEquals(
        data.sourceProduct.Account__c,
        createdProduct.Account__c,
        'Core 第4.9節: 手動Renewと同じ対象商品を継承する'
      );
      System.assertEquals(
        data.sourceProduct.Product__c,
        createdProduct.Product__c,
        'Core 第4.9節: 手動Renewと同じ対象商品を継承する'
      );
      System.assertEquals(
        1,
        createdProduct.Quantity__c,
        'Core 第4.9節: 対象継続課金明細の数量を継承する'
      );
      System.assertEquals(
        8000,
        createdProduct.UnitPrice__c,
        'Core 第4.9節: 対象継続課金明細の単価を継承する'
      );
      System.assertEquals(
        96000,
        createdProduct.Amount__c,
        'Core 第4.6節・第4.9節: 継続課金は数量×単価×12サイクルの整数円を保存する'
      );
      System.assertEquals(
        'ID/月',
        createdProduct.Unit__c,
        'Core 第4.9節: 手動Renewと同じ対象商品を継承する'
      );
      System.assertEquals(
        created.CurrentTermStartDate__c,
        createdProduct.StartDate__c,
        '日付仕様 第2.2節: Renewヘッダー開始日は継承商品の開始日'
      );
      System.assertEquals(
        created.CurrentTermEndDate__c,
        createdProduct.Enddate__c,
        '日付仕様 第2.2節: Renewヘッダー終了日は継承商品の終了日'
      );
      System.assertEquals(
        data.sourceProduct.InvoiceSetting__c,
        createdProduct.InvoiceSetting__c,
        'Core 第4.9節: 手動Renewと同じ対象商品の請求設定を継承する'
      );
      System.assertEquals(
        data.sourceProduct.BillingType__c,
        createdProduct.BillingType__c,
        'Core 第4.9節: 対象は継続課金として継承する'
      );
      System.assertEquals(
        data.sourceProduct.RevenueRecognitionBasis__c,
        createdProduct.RevenueRecognitionBasis__c,
        'Core 第4.9節: 手動Renewと同じ対象商品を継承する'
      );
      System.assertEquals(
        'Renew',
        createdProduct.Type__c,
        'Core 第4.9節: 自動Renew商品の種別はRenew'
      );
    }
  }

  @IsTest
  static void autoRenew_quantityUnitPriceUsesOrgDefaultRounding() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableRenewOpportunity();
      TestData data = createSourceData(true);
      data.sourceProduct.Quantity__c = 1.234;
      data.sourceProduct.UnitPrice__c = 10.345;
      update data.sourceProduct;

      Test.startTest();
      Opportunity renewal = insertRenewalOpportunity(data);
      Test.stopTest();

      ContractHistory__c created = [
        SELECT Id
        FROM ContractHistory__c
        WHERE Opportunity__c = :renewal.Id
        LIMIT 1
      ];
      ContractProduct__c createdProduct = [
        SELECT Quantity__c, UnitPrice__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :created.Id
        LIMIT 1
      ];
      System.assertEquals(
        AmountCalculationSettingService.roundQuantityUnitPrice(1.234),
        createdProduct.Quantity__c,
        'Core 第11.9節・第4.6節・第4.9節: 自動Renewの数量は OrgDefault。HALF_UP 直書きしない'
      );
      System.assertEquals(
        AmountCalculationSettingService.roundQuantityUnitPrice(10.345),
        createdProduct.UnitPrice__c,
        'Core 第11.9節・第4.6節・第4.9節: 自動Renewの単価は OrgDefault。HALF_UP 直書きしない'
      );
    }
  }

  @IsTest
  static void autoRenew_appliesAutoRenewCopyOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableRenewOpportunity();
      insert new FieldCopyDefinition__c(
        Name = 'Test_Renew_AccountName',
        TargetObject__c = 'ContractHistory__c',
        Context__c = FieldCopyDefinitionService.CONTEXT_AUTO_RENEW,
        SourceObject__c = 'Account',
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Note__c'
      );
      TestData data = createSourceData(true);

      Test.startTest();
      Opportunity renewal = insertRenewalOpportunity(data);
      Test.stopTest();

      ContractHistory__c created = [
        SELECT Note__c
        FROM ContractHistory__c
        WHERE Opportunity__c = :renewal.Id
        LIMIT 1
      ];
      Account account = [
        SELECT Name
        FROM Account
        WHERE Id = :data.account.Id
      ];
      System.assertEquals(
        account.Name,
        created.Note__c,
        'Core 第4.9節・第11.4.2節: 契約履歴かつ自動Renewを含むコピー定義を空欄へ適用する'
      );
    }
  }

  @IsTest
  static void switchOff_doesNotCreateRenewEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting =
        ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.RenewOpportunityEnabled__c = false;
      update setting;
      ContractDocumentSettingService.clearCache();
      TestData data = createSourceData(true);

      Test.startTest();
      Opportunity renewal = insertRenewalOpportunity(data);
      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Opportunity__c = :renewal.Id
        ],
        'Core 第4.9節・第11.5節: 更新商談スイッチOFFでは自動Renew見積を作らない'
      );
    }
  }

  @IsTest
  static void regularOpportunity_doesNotCreateRenewEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableRenewOpportunity();
      TestData data = createSourceData(true);

      Test.startTest();
      ContractTestDataFactory.insertOpportunity(
        data.account.Id,
        'Regular Opportunity'
      );
      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE
            ContractService__c = :data.service.Id
            AND RenewEstimateAutoCreated__c = TRUE
        ]
      );
    }
  }

  @IsTest
  static void renewalOpportunity_requiresMatchingContractService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableRenewOpportunity();
      TestData data = createSourceData(true);
      ContractService__c otherService = ContractTestDataFactory.insertContractService(
        data.account.Id,
        'Other Service'
      );
      Opportunity renewal = buildRenewalOpportunity(data);
      renewal.ContractService__c = otherService.Id;

      Database.SaveResult result = Database.insert(renewal, false);

      System.assertEquals(
        false,
        result.isSuccess()
      );
      System.assertEquals(
        RenewEstimateAutoCreateService.CONTRACT_SERVICE_MISMATCH_MESSAGE,
        result.getErrors()[0].getMessage(),
        'Core 第11.5節: 更新商談の契約サービスは元契約履歴と一致させる'
      );
    }
  }

  @IsTest
  static void renewalOpportunity_requiresMatchingAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableRenewOpportunity();
      TestData data = createSourceData(true);
      Account otherAccount = ContractTestDataFactory.insertAccount(
        'Other Renewal Account'
      );
      Opportunity renewal = buildRenewalOpportunity(data);
      renewal.AccountId = otherAccount.Id;

      Database.SaveResult result = Database.insert(renewal, false);

      System.assertEquals(
        false,
        result.isSuccess(),
        'Core 第4.9節・第11.5節: 更新商談の取引先不一致は商談作成ごと拒否する'
      );
      System.assertEquals(
        RenewEstimateAutoCreateService.ACCOUNT_MISMATCH_MESSAGE,
        result.getErrors()[0].getMessage(),
        'Core 第4.9節・第11.5節: 更新商談の取引先は契約サービスの取引先と一致させる'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE
            ContractService__c = :data.service.Id
            AND RenewEstimateAutoCreated__c = TRUE
        ],
        'Core 第4.9節・第11.5節: 不一致時は自動Renew見積も残さない'
      );
    }
  }

  @IsTest
  static void renewalOpportunity_requiresRecurringSourceProduct() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableRenewOpportunity();
      TestData data = createSourceData(false);

      Database.SaveResult result = Database.insert(
        buildRenewalOpportunity(data),
        false
      );

      System.assertEquals(false, result.isSuccess());
      System.assertEquals(
        RenewEstimateAutoCreateService.RENEW_SOURCE_REQUIRED_MESSAGE,
        result.getErrors()[0].getMessage(),
        'Core 第11.5節: 更新見積自動作成には前回期間終了日に届く継続課金明細が要る'
      );
    }
  }

  private class TestData {
    public Account account;
    public Opportunity previousOpportunity;
    public ContractService__c service;
    public ContractHistory__c sourceHistory;
    public ContractProduct__c sourceProduct;
  }

  private static void enableRenewOpportunity() {
    ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
    setting.RenewOpportunityEnabled__c = true;
    update setting;
    ContractDocumentSettingService.clearCache();
  }

  private static TestData createSourceData(Boolean withRecurringProduct) {
    TestData data = new TestData();
    data.account = ContractTestDataFactory.insertAccount('Auto Renew Account');
    data.previousOpportunity = ContractTestDataFactory.insertOpportunity(
      data.account.Id,
      'Previous Opportunity'
    );
    data.service = ContractTestDataFactory.insertContractService(
      data.account.Id,
      'Auto Renew Service'
    );

    Date termStart = Date.newInstance(2025, 6, 1);
    Date termEnd = Date.newInstance(2026, 5, 31);
    data.sourceHistory = new ContractHistory__c(
      Name = 'Source Ordered History',
      ContractService__c = data.service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      Opportunity__c = data.previousOpportunity.Id
    );
    ContractTestDataFactory.applyRequiredFields(data.sourceHistory);
    insert data.sourceHistory;

    Product2 product = ContractTestDataFactory.buildProduct(
      'Auto Renew Product'
    );
    product.UnitName__c = 'ID';
    product.UnitPrice__c = 8000;
    product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    ContractTestDataFactory.insertProduct(product);

    data.sourceProduct = new ContractProduct__c(
      ContractHistory__c = data.sourceHistory.Id,
      Product__c = product.Id,
      Account__c = data.account.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Amount__c = 96000,
      Unit__c = 'ID/月',
      StartDate__c = termStart,
      Enddate__c = withRecurringProduct ? termEnd : termStart,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = product.BillingType__c,
      Type__c = 'New',
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
    );
    ContractTestDataFactory.applyRequiredFields(data.sourceProduct);
    insert data.sourceProduct;

    data.sourceHistory.historystatus__c = 'Ordered';
    update data.sourceHistory;
    data.sourceHistory = [
      SELECT Id, CurrentTermStartDate__c, CurrentTermEndDate__c
      FROM ContractHistory__c
      WHERE Id = :data.sourceHistory.Id
    ];
    if (withRecurringProduct) {
      data.sourceProduct = [
        SELECT
          Id,
          Account__c,
          Product__c,
          Quantity__c,
          UnitPrice__c,
          InvoiceSetting__c,
          BillingType__c,
          RevenueRecognitionBasis__c
        FROM ContractProduct__c
        WHERE Id = :data.sourceProduct.Id
      ];
    } else {
      data.sourceProduct = null;
    }
    return data;
  }

  private static Opportunity buildRenewalOpportunity(TestData data) {
    Opportunity renewal = ContractTestDataFactory.buildOpportunity(
      data.account.Id,
      'Renewal Opportunity',
      data.previousOpportunity.Id,
      false,
      data.service.Id
    );
    renewal.SourceContractHistory__c = data.sourceHistory.Id;
    ContractTestDataFactory.applyOpportunityDefaults(renewal);
    return renewal;
  }

  private static Opportunity insertRenewalOpportunity(TestData data) {
    Opportunity renewal = buildRenewalOpportunity(data);
    insert renewal;
    return renewal;
  }
}
