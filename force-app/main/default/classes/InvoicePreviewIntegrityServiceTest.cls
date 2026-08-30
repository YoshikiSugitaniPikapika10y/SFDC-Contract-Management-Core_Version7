@IsTest
private class InvoicePreviewIntegrityServiceTest {
  @TestSetup
  static void setup() {
    ContractTestDataFactory.initTestContext();
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
          ex.getMessage()
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
          ex.getMessage()
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
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'integrity@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 1,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    ContractService__c service = new ContractService__c(
      Name = 'Integrity Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c historyA = new ContractHistory__c(
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1
    );
    ContractTestDataFactory.applyRequiredFields(historyA);
    insert historyA;
    ContractHistory__c historyB = new ContractHistory__c(
      ContractService__c = service.Id,
      Type__c = 'Change',
      historystatus__c = 'Ordered',
      Version__c = 2
    );
    ContractTestDataFactory.applyRequiredFields(historyB);
    insert historyB;
    Product2 product = ContractTestDataFactory.buildProduct('Integrity Prod');
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = historyB.Id,
      Account__c = account.Id,
      Product__c = product.Id,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      StartDate__c = Date.today(),
      Enddate__c = Date.today()
    );
    ContractTestDataFactory.applyRequiredFields(contractProduct);
    insert contractProduct;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = historyA.Id,
      InvoiceDate__c = Date.today(),
      Amount__c = 1000,
      TaxAmount__c = 100
    );
    ContractTestDataFactory.applyRequiredFields(invoice);
    insert invoice;
    InvoiceLine__c line = new InvoiceLine__c(
      Invoice__c = invoice.Id,
      ContractProduct__c = contractProduct.Id,
      ProductName__c = 'Integrity Line',
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000
    );
    ContractTestDataFactory.applyRequiredFields(line);
    insert line;
    Fixture fixture = new Fixture();
    fixture.historyId = historyA.Id;
    fixture.invoice = invoice;
    return fixture;
  }
}
