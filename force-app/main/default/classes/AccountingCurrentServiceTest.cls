@IsTest
private class AccountingCurrentServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void load_returnsEmptyWhenInvoiceHasNoJournals() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertDraftInvoice();
      List<GlJournal__c> current = AccountingCurrentService.load(invoice.Id);
      System.assertEquals(
        0,
        current.size(),
        'Accounting 第8.2節: 仕訳が無い請求のCurrentは空'
      );
    }
  }

  @IsTest
  static void load_nullInvoiceId_returnsEmpty() {
    List<GlJournal__c> current = AccountingCurrentService.load(null);
    System.assertEquals(
      0,
      current.size(),
      'Accounting 第8.2節: 請求Idが無いCurrentは空'
    );
  }

  private static Invoice__c insertDraftInvoice() {
    Account account = ContractTestDataFactory.insertAccount(
      'Current ' + String.valueOf(Crypto.getRandomInteger())
    );
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      'Current Service'
    );
    ContractServiceWriteGuard.allowPackageWrite(true);
    try {
      service.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
      update service;
    } finally {
      ContractServiceWriteGuard.allowPackageWrite(false);
    }
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Current History',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(
      history,
      account.Id
    );
    insert history;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = 100,
      BillingAccountSnapShot__c = service.BiilingAcccount__c
    );
    InvoiceTransactionStatusService.allowStatusWrite = true;
    try {
      insert invoice;
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = false;
    }
    return invoice;
  }
}
