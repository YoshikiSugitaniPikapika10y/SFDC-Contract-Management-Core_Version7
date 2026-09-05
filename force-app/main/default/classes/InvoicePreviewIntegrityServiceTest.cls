@IsTest
private class InvoicePreviewIntegrityServiceTest {
  @TestSetup
  static void setup() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  @IsTest
  static void assertSameHistory_productOnOtherHistory_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createMismatchFixture();
      Boolean thrown = false;
      try {
        InvoicePreviewIntegrityService.assertSameHistory(
          null,
          new List<Invoice__c>{ fixture.invoice }
        );
      } catch (InvoicePreviewIntegrityService.IntegrityException ex) {
        thrown = true;
        System.assertEquals(
          InvoicePreviewIntegrityService.MISMATCH_MESSAGE,
          ex.getMessage(),
          'Core 第7.7.0節: 請求書と配下明細の契約履歴不一致は表示も編集も確定もできない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void assertSameHistory_emptyOrMatching_doesNotThrow() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoicePreviewIntegrityService.assertSameHistory(null, null);
      InvoicePreviewIntegrityService.assertSameHistory(
        null,
        new List<Invoice__c>()
      );
      Fixture fixture = createMatchingFixture();
      Test.startTest();
      InvoicePreviewIntegrityService.assertSameHistory(
        fixture.historyId,
        new List<Invoice__c>{ fixture.invoice }
      );
      Test.stopTest();
      Invoice__c loaded = [
        SELECT ContractHistory__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      System.assertEquals(
        fixture.historyId,
        loaded.ContractHistory__c,
        '仕様: Core 第7.7.0節 請求書の契約履歴は必須で配下と一致する'
      );
    }
  }

  @IsTest
  static void assertSameHistory_invoiceOutsideScopeHistory_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createMatchingFixture();
      Account otherAccount = ContractTestDataFactory.insertAccount(
        'Integrity Scope Other'
      );
      ContractService__c otherService = ContractTestDataFactory.insertContractService(
        otherAccount.Id,
        'Integrity Scope Other Service'
      );
      ContractHistory__c otherHistory = new ContractHistory__c(
        Name = 'Integrity Scope Other',
        ContractService__c = otherService.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 6, 30)
      );
      ContractTestDataFactory.applyRequiredFields(otherHistory);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        otherHistory,
        otherAccount.Id
      );
      insert otherHistory;
      Boolean thrown = false;
      try {
        InvoicePreviewIntegrityService.assertSameHistory(
          otherHistory.Id,
          new List<Invoice__c>{ fixture.invoice }
        );
      } catch (InvoicePreviewIntegrityService.IntegrityException ex) {
        thrown = true;
        System.assertEquals(
          InvoicePreviewIntegrityService.MISMATCH_MESSAGE,
          ex.getMessage(),
          '仕様: Core 第7.7.0節 請求書と配下明細の契約履歴不一致は表示も編集も確定もできない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void assertSameHistory_periodLineOnOtherHistory_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createMatchingFixture();
      Account otherAccount = ContractTestDataFactory.insertAccount(
        'Integrity Period Other Acc'
      );
      ContractService__c otherService = ContractTestDataFactory.insertContractService(
        otherAccount.Id,
        'Integrity Period Other Service'
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2026, 6, 30);
      ContractHistory__c otherHistory = new ContractHistory__c(
        Name = 'Integrity Period Other',
        ContractService__c = otherService.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyRequiredFields(otherHistory);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        otherHistory,
        otherAccount.Id
      );
      insert otherHistory;
      Product2 otherProduct = ContractTestDataFactory.buildProduct(
        'Integrity Period Other Prod'
      );
      otherProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(otherProduct);
      ContractProduct__c otherContractProduct = new ContractProduct__c(
        ContractHistory__c = otherHistory.Id,
        Account__c = otherAccount.Id,
        Product__c = otherProduct.Id,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        Type__c = 'New',
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
      );
      ContractTestDataFactory.applyRequiredFields(otherContractProduct);
      otherContractProduct.Amount__c = 1000;
      insert otherContractProduct;
      InvoiceProduct__c otherPeriod = new InvoiceProduct__c(
        ContractHistory__c = otherHistory.Id,
        ContractProduct__c = otherContractProduct.Id,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceBucketKey__c = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
          null,
          otherHistory.Id,
          termStart,
          null
        ),
        Amount__c = 1000
      );
      insert otherPeriod;
      InvoiceLine__c line = [
        SELECT Id, SourcePeriodLineIds__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :fixture.invoice.Id
        LIMIT 1
      ];
      line.SourcePeriodLineIds__c = 'junk,' + otherPeriod.Id + ',xx';
      update line;
      Boolean thrown = false;
      try {
        InvoicePreviewIntegrityService.assertSameHistory(
          fixture.historyId,
          new List<Invoice__c>{ fixture.invoice }
        );
      } catch (InvoicePreviewIntegrityService.IntegrityException ex) {
        thrown = true;
        System.assertEquals(
          InvoicePreviewIntegrityService.MISMATCH_MESSAGE,
          ex.getMessage(),
          '仕様: Core 第7.7.0節 生成元期間明細も同じ契約履歴に属さなければならない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void assertSameHistory_embeddedLinesAndMatchingPeriod_doesNotThrow() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createMatchingFixture();
      InvoiceLine__c line = [
        SELECT Id, ContractProduct__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :fixture.invoice.Id
        LIMIT 1
      ];
      InvoiceProduct__c period = new InvoiceProduct__c(
        ContractHistory__c = fixture.historyId,
        ContractProduct__c = line.ContractProduct__c,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30),
        InvoiceBucketKey__c = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
          null,
          fixture.historyId,
          Date.newInstance(2026, 6, 1),
          null
        ),
        Amount__c = 1000
      );
      insert period;
      line.SourcePeriodLineIds__c = period.Id;
      update line;
      Invoice__c withLines = [
        SELECT
          Id,
          ContractHistory__c,
          (
            SELECT
              Id,
              ContractProduct__r.ContractHistory__c,
              SourcePeriodLineIds__c
            FROM InvoiceLines__r
          )
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      Test.startTest();
      InvoicePreviewIntegrityService.assertSameHistory(
        fixture.historyId,
        new List<Invoice__c>{ null, withLines }
      );
      Test.stopTest();
      System.assertEquals(
        fixture.historyId,
        withLines.ContractHistory__c,
        '仕様: Core 第7.7.0節 請求書の契約履歴は必須で配下と一致する'
      );
    }
  }

  @IsTest
  static void assertSameHistory_skipsRecordsWithoutId_andKeepsMatchingHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createMatchingFixture();
      InvoicePreviewIntegrityService.assertSameHistory(
        fixture.historyId,
        new List<Invoice__c>{ new Invoice__c(), fixture.invoice }
      );
      Invoice__c loaded = [
        SELECT ContractHistory__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      System.assertEquals(
        fixture.historyId,
        loaded.ContractHistory__c,
        '仕様: Core 第7.7.0節 請求書の契約履歴は必須で配下と一致する'
      );
    }
  }

  @IsTest
  static void getInvoicePreview_wrapsIntegrityAsAuraHandled() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createMismatchFixture();
      Boolean thrown = false;
      Test.startTest();
      try {
        OrderCreateController.getInvoicePreview(fixture.historyId);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          InvoicePreviewIntegrityService.MISMATCH_MESSAGE,
          ex.getMessage(),
          'Core 第7.7.0節: ボード取得時の不一致は表示・編集を止める'
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
    }
  }

  private class Fixture {
    Id historyId;
    Invoice__c invoice;
  }

  private static Fixture createMismatchFixture() {
    Account account = ContractTestDataFactory.insertAccount('Integrity Account');
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      'Integrity Service'
    );
    Date termStart = Date.newInstance(2026, 6, 1);
    Date termEnd = Date.newInstance(2026, 6, 30);
    ContractHistory__c historyA = new ContractHistory__c(
      Name = 'Integrity Ordered',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd
    );
    ContractTestDataFactory.applyRequiredFields(historyA);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(historyA, account.Id);
    insert historyA;
    Product2 productA = ContractTestDataFactory.buildProduct('Integrity Prod A');
    productA.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(productA);
    ContractProduct__c productOnA = new ContractProduct__c(
      ContractHistory__c = historyA.Id,
      Account__c = account.Id,
      Product__c = productA.Id,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      StartDate__c = termStart,
      Enddate__c = termEnd,
      Type__c = 'New',
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
    );
    ContractTestDataFactory.applyRequiredFields(productOnA);
    productOnA.Amount__c = 1000;
    insert productOnA;
    historyA.historystatus__c = 'Ordered';
    update historyA;

    ContractHistory__c historyB = new ContractHistory__c(
      Name = 'Integrity Other Estimate',
      ContractService__c = service.Id,
      Type__c = 'Change',
      historystatus__c = 'Estimate',
      Version__c = 2,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd
    );
    ContractTestDataFactory.applyRequiredFields(historyB);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(historyB, account.Id);
    insert historyB;
    Product2 productB = ContractTestDataFactory.buildProduct('Integrity Prod B');
    productB.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(productB);
    ContractProduct__c productOnB = new ContractProduct__c(
      ContractHistory__c = historyB.Id,
      Account__c = account.Id,
      Product__c = productB.Id,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      StartDate__c = termStart,
      Enddate__c = termEnd,
      Type__c = 'New',
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
    );
    ContractTestDataFactory.applyRequiredFields(productOnB);
    productOnB.Amount__c = 1000;
    insert productOnB;

    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = historyA.Id,
      InvoiceDate__c = termStart,
      Amount__c = 1000,
      TaxAmount__c = 100,
      BillingAccountSnapShot__c = service.BiilingAcccount__c
    );
    ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
    ContractTestDataFactory.applyRequiredFields(invoice);
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    InvoiceLine__c line = new InvoiceLine__c(
      Invoice__c = invoice.Id,
      ContractProduct__c = productOnB.Id,
      ProductName__c = 'Integrity Line',
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME,
      AcceptanceEndDate__c = termEnd,
      ServicePeriodStartDate__c = termStart,
      ServicePeriodEndDate__c = termEnd
    );
    ContractTestDataFactory.applyRequiredFields(line);
    insert line;
    Fixture fixture = new Fixture();
    fixture.historyId = historyA.Id;
    fixture.invoice = invoice;
    return fixture;
  }

  private static Fixture createMatchingFixture() {
    Account account = ContractTestDataFactory.insertAccount('Integrity Match Acc');
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      'Integrity Match Service'
    );
    Date termStart = Date.newInstance(2026, 6, 1);
    Date termEnd = Date.newInstance(2026, 6, 30);
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Integrity Match Ordered',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd
    );
    ContractTestDataFactory.applyRequiredFields(history);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
    insert history;
    Product2 product = ContractTestDataFactory.buildProduct('Integrity Match Prod');
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Account__c = account.Id,
      Product__c = product.Id,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      StartDate__c = termStart,
      Enddate__c = termEnd,
      Type__c = 'New',
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
    );
    ContractTestDataFactory.applyRequiredFields(contractProduct);
    contractProduct.Amount__c = 1000;
    insert contractProduct;
    history.historystatus__c = 'Ordered';
    update history;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = termStart,
      Amount__c = 1000,
      TaxAmount__c = 100,
      BillingAccountSnapShot__c = service.BiilingAcccount__c
    );
    ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
    ContractTestDataFactory.applyRequiredFields(invoice);
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    InvoiceLine__c line = new InvoiceLine__c(
      Invoice__c = invoice.Id,
      ContractProduct__c = contractProduct.Id,
      ProductName__c = 'Integrity Match Line',
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME,
      AcceptanceEndDate__c = termEnd,
      ServicePeriodStartDate__c = termStart,
      ServicePeriodEndDate__c = termEnd
    );
    ContractTestDataFactory.applyRequiredFields(line);
    insert line;
    Fixture fixture = new Fixture();
    fixture.historyId = history.Id;
    fixture.invoice = invoice;
    return fixture;
  }
}
