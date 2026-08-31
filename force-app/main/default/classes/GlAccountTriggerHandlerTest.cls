@IsTest
private class GlAccountTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void beforeDelete_allowsUnreferencedAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c account = insertAccount('Unref Asset', 'Asset');
      delete account;
      System.assertEquals(
        0,
        [SELECT COUNT() FROM GlAccount__c WHERE Id = :account.Id],
        'Accounting 第4.1節: 未参照の勘定科目は削除できる'
      );
    }
  }

  @IsTest
  static void beforeDelete_rejectsWhenJournalReferences() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c debit = insertAccount('Ref Debit', 'Asset');
      GlAccount__c credit = insertAccount('Ref Credit', 'Liability');
      Invoice__c invoice = insertDraftInvoice();
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'GA-REF', String.valueOf(debit.Id) }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      Boolean thrown = false;
      try {
        delete debit;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('参照されている勘定科目は削除できません'),
          'Accounting 第4.1節: 仕訳から参照済みの科目は削除せず無効化する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeDelete_rejectsWhenAccountMapReferences() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c account = insertAccount('Map Asset', 'Asset');
      insert new GlAccountMap__c(
        Name = 'Map Ref',
        Account__c = account.Id,
        SlotKey__c = 'AccountsReceivable',
        EvaluationContext__c = 'InvoiceLine',
        ConditionSourceType__c = 'None',
        Priority__c = 1,
        IsActive__c = true
      );
      Boolean thrown = false;
      try {
        delete account;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('参照されている勘定科目は削除できません'),
          'Accounting 第4.1節: 割当から参照済みの科目は削除せず無効化する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeDelete_rejectsWhenManualSettingReferences() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c debit = insertAccount('MJ Debit', 'Expense');
      GlAccount__c credit = insertAccount('MJ Credit', 'Asset');
      insert new GlManualJournalSetting__c(
        Name = '検証用設定',
        SettingKey__c = 'GA-MJ-' + String.valueOf(Crypto.getRandomInteger()),
        DebitSlotKey__c = 'FxLoss',
        DebitAccount__c = debit.Id,
        CreditSlotKey__c = 'AccountsReceivable',
        CreditAccount__c = credit.Id,
        Description__c = '検証',
        IsActive__c = true
      );
      Boolean thrown = false;
      try {
        delete debit;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('参照されている勘定科目は削除できません'),
          'Accounting 第4.1節: 手動仕訳設定から参照済みの科目は削除せず無効化する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  private static GlAccount__c insertAccount(String name, String accountType) {
    GlAccount__c account = new GlAccount__c(
      Name = name,
      AccountType__c = accountType,
      IsActive__c = true
    );
    insert account;
    return account;
  }

  private static Invoice__c insertDraftInvoice() {
    Account account = ContractTestDataFactory.insertAccount(
      'GA ' + String.valueOf(Crypto.getRandomInteger())
    );
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      'GA Service'
    );
    ContractServiceWriteGuard.allowPackageWrite(true);
    try {
      service.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
      update service;
    } finally {
      ContractServiceWriteGuard.allowPackageWrite(false);
    }
    ContractHistory__c history = new ContractHistory__c(
      Name = 'GA History',
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
