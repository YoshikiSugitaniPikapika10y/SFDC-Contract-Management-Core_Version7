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

  @IsTest
  static void load_returnsJournalsAndCloneDoesNotMutateCache() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertDraftInvoice();
      GlAccount__c debit = new GlAccount__c(
        Name = 'Current Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'Current Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlJournal__c journal = new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1000,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'CurrentLoad', String.valueOf(invoice.Id) }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      insert journal;

      List<GlJournal__c> first = AccountingCurrentService.load(invoice.Id);
      System.assertEquals(
        1,
        first.size(),
        'Accounting 第8.2節: ロック後の請求書から仕訳を収集する'
      );
      System.assertEquals(journal.Id, first[0].Id);
      System.assertEquals(1000, first[0].Amount__c);
      first[0].TransactionStatus__c = 'Cancelled';

      List<GlJournal__c> second = AccountingCurrentService.load(invoice.Id);
      System.assertEquals(
        'Active',
        second[0].TransactionStatus__c,
        'Accounting 第8.2節: preview の Diff 計算がキャッシュ行の取引状態を書き換えない'
      );
    }
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
