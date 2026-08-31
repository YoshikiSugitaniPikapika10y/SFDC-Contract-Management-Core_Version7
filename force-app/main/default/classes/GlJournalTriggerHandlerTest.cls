@IsTest
private class GlJournalTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void beforeUpdate_engineWriteAllowsAmount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlJournal__c journal = insertJournal();
      GlJournalTriggerHandler.allowEngineWrite = true;
      try {
        journal.Amount__c = 3;
        update journal;
      } finally {
        GlJournalTriggerHandler.allowEngineWrite = false;
      }
      System.assertEquals(
        3,
        [SELECT Amount__c FROM GlJournal__c WHERE Id = :journal.Id].Amount__c,
        'Accounting 第9.5節: エンジン書き込みだけ金額更新を通す'
      );
    }
  }

  @IsTest
  static void beforeUpdate_rejectsDirectTransactionStatusChange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlJournal__c journal = insertJournal();
      Boolean thrown = false;
      try {
        journal.TransactionStatus__c = 'Cancelled';
        update journal;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('仕訳の取引状態は専用処理以外から変更できません'),
          'Accounting 第9.5節: 取引状態は専用処理以外から変えない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeUpdate_rejectsAmountChange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlJournal__c journal = insertJournal();
      Boolean thrown = false;
      try {
        journal.Amount__c = 2;
        update journal;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('仕訳の金額・科目・日付・借貸は変更できません'),
          'Accounting 第9.5節: 金額の更新は拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeUpdate_rejectsDirectLockFlagChange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlJournal__c journal = insertJournal();
      Boolean thrown = false;
      try {
        journal.IsLocked__c = true;
        update journal;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('ロック状態は専用処理以外から変更できません'),
          'Accounting 第9.5節: Lockは専用処理以外から変えない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeUpdate_lockWriteStillRejectsAmount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlJournal__c journal = insertJournal();
      JournalLockService.allowLockWrite = true;
      Boolean thrown = false;
      try {
        journal.Amount__c = 9;
        update journal;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('Lock/Unlockはロック状態以外を変更できません'),
          'Accounting 第9.5節: Lock/Unlockは金額を変えない'
        );
      } finally {
        JournalLockService.allowLockWrite = false;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeDelete_rejectsWithout103Or104() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlJournal__c journal = insertJournal();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.DELETE_RECORDS => false,
        ContractPermissionUtil.MIGRATE_ALL => false
      };
      Boolean thrown = false;
      try {
        delete journal;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('仕訳は物理削除できません'),
          'Accounting 第2.5節: 物理削除は 103／104 だけ'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void beforeDelete_allows103() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlJournal__c journal = insertJournal();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.DELETE_RECORDS => true,
        ContractPermissionUtil.MIGRATE_ALL => false
      };
      try {
        delete journal;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        0,
        [SELECT COUNT() FROM GlJournal__c WHERE Id = :journal.Id],
        'Accounting 第2.5節・共通基盤第3.6節: 103は仕訳の物理削除を通す'
      );
    }
  }

  @IsTest
  static void beforeDelete_allows104() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlJournal__c journal = insertJournal();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        delete journal;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        0,
        [SELECT COUNT() FROM GlJournal__c WHERE Id = :journal.Id],
        'Accounting 第2.5節・共通基盤第3.6節: 104は仕訳の物理削除を通す'
      );
    }
  }

  private static GlJournal__c insertJournal() {
    Invoice__c invoice = insertDraftInvoice();
    GlAccount__c debit = new GlAccount__c(
      Name = 'GJ Debit',
      AccountType__c = 'Asset',
      IsActive__c = true
    );
    GlAccount__c credit = new GlAccount__c(
      Name = 'GJ Credit',
      AccountType__c = 'Liability',
      IsActive__c = true
    );
    insert new List<GlAccount__c>{ debit, credit };
    GlJournal__c journal = new GlJournal__c(
      Invoice__c = invoice.Id,
      Amount__c = 1,
      IdempotencyKey__c = AccountingDiffService.hashKey(
        new List<String>{ 'GJ', String.valueOf(invoice.Id) }
      ),
      DebitSlotKey__c = 'Cash',
      CreditSlotKey__c = 'UnappliedCash',
      DebitAccount__c = debit.Id,
      CreditAccount__c = credit.Id,
      PostingDate__c = Date.newInstance(2026, 6, 1),
      TransactionStatus__c = 'Active'
    );
    insert journal;
    return journal;
  }

  private static Invoice__c insertDraftInvoice() {
    Account account = ContractTestDataFactory.insertAccount(
      'GJ ' + String.valueOf(Crypto.getRandomInteger())
    );
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      'GJ Service'
    );
    ContractServiceWriteGuard.allowPackageWrite(true);
    try {
      service.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
      update service;
    } finally {
      ContractServiceWriteGuard.allowPackageWrite(false);
    }
    ContractHistory__c history = new ContractHistory__c(
      Name = 'GJ History',
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
