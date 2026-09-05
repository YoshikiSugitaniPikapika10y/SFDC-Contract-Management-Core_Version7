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
          CurrentTermEndDate__c
        FROM ContractHistory__c
        WHERE Opportunity__c = :renewal.Id
        LIMIT 1
      ];
      System.assertEquals(data.service.Id, created.ContractService__c);
      System.assertEquals(data.sourceHistory.Id, created.PreviousHistory__c);
      System.assertEquals('Renew', created.Type__c);
      System.assertEquals('Estimate', created.historystatus__c);
      System.assertEquals(true, created.RenewEstimateAutoCreated__c);
      System.assertEquals(
        data.sourceHistory.CurrentTermEndDate__c.addDays(1),
        created.CurrentTermStartDate__c
      );

      ContractProduct__c createdProduct = [
        SELECT
          PreviousContractProduct__c,
          Quantity__c,
          UnitPrice__c,
          Amount__c,
          Type__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :created.Id
        LIMIT 1
      ];
      System.assertEquals(
        data.sourceProduct.Id,
        createdProduct.PreviousContractProduct__c
      );
      System.assertEquals(1, createdProduct.Quantity__c);
      System.assertEquals(8000, createdProduct.UnitPrice__c);
      System.assertEquals(96000, createdProduct.Amount__c);
      System.assertEquals('Renew', createdProduct.Type__c);
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
        SELECT Id, Quantity__c, UnitPrice__c
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
