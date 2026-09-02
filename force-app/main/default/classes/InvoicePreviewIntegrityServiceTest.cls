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
  static void getInvoicePreview_wrapsIntegrityAsAuraHandled() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createMismatchFixture();
      Boolean thrown = false;
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
}
