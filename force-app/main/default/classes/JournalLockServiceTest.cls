@IsTest
private class JournalLockServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void unlockForInvoice_requiresReason() {
    Boolean thrown = false;
    try {
      JournalLockService.unlockForInvoice(UserInfo.getUserId(), null, null);
    } catch (Exception ex) {
      thrown = true;
      System.assertEquals(
        'Unlockには理由が必要です。',
        ex.getMessage(),
        'Accounting 第9.5節: Unlockは理由を必須とする'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void unlockForInvoice_rejectsReasonLongerThan255() {
    String tooLong = 'a'.repeat(256);
    Boolean thrown = false;
    try {
      JournalLockService.unlockForInvoice(UserInfo.getUserId(), null, tooLong);
    } catch (Exception ex) {
      thrown = true;
      System.assertEquals(
        'Unlock理由は255文字以内で指定してください。',
        ex.getMessage(),
        'Accounting 第9.1節: Unlock理由はテキスト(255)'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void lockForInvoice_rejectsWhenAccountingOff() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertInvoice();
      Boolean thrown = false;
      try {
        JournalLockService.lockForInvoice(invoice.Id, new List<Id>());
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          'AccountingがOFFのときはLock/Unlockできません。',
          ex.getMessage(),
          'Accounting 第9.5節・第1.1節: OFFではLock／Unlockの入口を持たない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void unlockForInvoice_rejectsWhenAccountingOff() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertInvoice();
      Boolean thrown = false;
      try {
        JournalLockService.unlockForInvoice(invoice.Id, new List<Id>(), '確認');
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          'AccountingがOFFのときはLock/Unlockできません。',
          ex.getMessage(),
          'Accounting 第9.5節・第1.1節: OFFではLock／Unlockの入口を持たない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void unlockForInvoice_rejectsEmptySelection() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      Boolean thrown = false;
      try {
        JournalLockService.unlockForInvoice(invoice.Id, new List<Id>(), '確認');
      } catch (JournalLockService.LockException ex) {
        thrown = true;
        System.assertEquals(
          'Unlockする仕訳を選んでください。',
          ex.getMessage(),
          'Accounting 第9.5節: 未選択では実行できない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void lockForInvoice_allowsCancelledInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      GlAccount__c debit = new GlAccount__c(
        Name = 'JLock CancelledInv Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'JLock CancelledInv Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlJournal__c journal = new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'JL-CANCELLED-INV' }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      insert journal;
      Boolean previousStatus = InvoiceTransactionStatusService.allowStatusWrite;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      try {
        invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CANCELLED;
        update invoice;
      } finally {
        InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
      }
      Test.startTest();
      Integer lockedCount = JournalLockService.lockForInvoice(
        invoice.Id,
        new List<Id>{ journal.Id },
        AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id),
        null
      );
      Test.stopTest();
      System.assertEquals(
        1,
        lockedCount,
        'Core 第7.7.3節・Accounting 第9.5節: 取消済み請求でも有効仕訳をLockできる'
      );
      System.assertEquals(
        true,
        [
          SELECT IsLocked__c
          FROM GlJournal__c
          WHERE Id = :journal.Id
        ]
          .IsLocked__c,
        'Core 第7.7.3節・Accounting 第9.5節: 取消済み請求でも対象は有効と取消'
      );
      System.assertEquals(
        InvoiceTransactionStatusService.TX_CANCELLED,
        [
          SELECT InvoiceTransactionStatus__c
          FROM Invoice__c
          WHERE Id = :invoice.Id
        ]
          .InvoiceTransactionStatus__c,
        'Accounting 第9.5節: 請求書の取引状態は変えない'
      );
    }
  }

  @IsTest
  static void unlockForInvoice_allowsCancelledInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      GlAccount__c debit = new GlAccount__c(
        Name = 'JLock CancelledInv Unlock Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'JLock CancelledInv Unlock Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlJournal__c journal = new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'JL-CANCELLED-INV-UNLOCK' }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Reversal',
        IsLocked__c = true
      );
      insert journal;
      Boolean previousStatus = InvoiceTransactionStatusService.allowStatusWrite;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      try {
        invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CANCELLED;
        update invoice;
      } finally {
        InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
      }
      Test.startTest();
      Integer unlockedCount = JournalLockService.unlockForInvoice(
        invoice.Id,
        new List<Id>{ journal.Id },
        '確認',
        AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id),
        null
      );
      Test.stopTest();
      System.assertEquals(
        1,
        unlockedCount,
        'Core 第7.7.3節・Accounting 第9.5節: 取消済み請求でも取消仕訳をUnlockできる'
      );
      GlJournal__c loaded = [
        SELECT IsLocked__c, UnlockReason__c
        FROM GlJournal__c
        WHERE Id = :journal.Id
      ];
      System.assertEquals(
        false,
        loaded.IsLocked__c,
        'Core 第7.7.3節・Accounting 第9.5節: 取消済み請求でも対象は有効と取消'
      );
      System.assertEquals(
        '確認',
        loaded.UnlockReason__c,
        'Accounting 第9.5節: Unlock理由は残す'
      );
    }
  }

  @IsTest
  static void lockForInvoice_rejectsEmptySelection() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      Boolean thrown = false;
      try {
        JournalLockService.lockForInvoice(invoice.Id, new List<Id>());
      } catch (JournalLockService.LockException ex) {
        thrown = true;
        System.assertEquals(
          'Lockする仕訳を選んでください。',
          ex.getMessage(),
          'Accounting 第9.5節: 未選択では実行できない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void unlockForInvoice_rejectsMixedLockSelection() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      GlAccount__c debit = new GlAccount__c(
        Name = 'JLock Mix Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'JLock Mix Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlJournal__c locked = new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'JL-MIX-L' }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active',
        IsLocked__c = true
      );
      GlJournal__c unlocked = locked.clone(false, false, false, false);
      unlocked.IdempotencyKey__c = AccountingDiffService.hashKey(
        new List<String>{ 'JL-MIX-U' }
      );
      unlocked.IsLocked__c = false;
      insert new List<GlJournal__c>{ locked, unlocked };

      Boolean thrown = false;
      try {
        JournalLockService.unlockForInvoice(
          invoice.Id,
          new List<Id>{ locked.Id, unlocked.Id },
          '確認',
          AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id),
          null
        );
      } catch (JournalLockService.LockException ex) {
        thrown = true;
        System.assertEquals(
          'LockとUnlockが混在しています',
          ex.getMessage(),
          'Accounting 第9.5節・Core 第7.7.3節: UnlockはLock済みと未Lockの混在を拒否する'
        );
      }
      System.assertEquals(true, thrown);
      Map<Id, GlJournal__c> loaded = new Map<Id, GlJournal__c>(
        [
          SELECT IsLocked__c
          FROM GlJournal__c
          WHERE Id IN :new List<Id>{ locked.Id, unlocked.Id }
        ]
      );
      System.assertEquals(
        true,
        loaded.get(locked.Id).IsLocked__c,
        'Accounting 第9.5節: 混在拒否ではLock済みを外さない'
      );
      System.assertEquals(
        false,
        loaded.get(unlocked.Id).IsLocked__c,
        'Accounting 第9.5節: 混在拒否では未Lockを変えない'
      );
    }
  }

  @IsTest
  static void lockForInvoice_locksOnlySelectedJournals() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      GlAccount__c debit = new GlAccount__c(
        Name = 'JLock Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'JLock Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlJournal__c first = new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'JL1' }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      GlJournal__c second = first.clone(false, false, false, false);
      second.IdempotencyKey__c = AccountingDiffService.hashKey(
        new List<String>{ 'JL2' }
      );
      insert new List<GlJournal__c>{ first, second };

      Test.startTest();
      Integer locked = JournalLockService.lockForInvoice(
        invoice.Id,
        new List<Id>{ first.Id },
        AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id),
        null
      );
      Test.stopTest();

      System.assertEquals(
        1,
        locked,
        'Accounting 第9.5節: 選んだ行だけLockする'
      );
      Map<Id, GlJournal__c> loaded = new Map<Id, GlJournal__c>(
        [
          SELECT
            IsLocked__c,
            Amount__c,
            PostingDate__c,
            DebitAccount__c,
            CreditAccount__c
          FROM GlJournal__c
          WHERE Id IN :new List<Id>{ first.Id, second.Id }
        ]
      );
      System.assertEquals(true, loaded.get(first.Id).IsLocked__c);
      System.assertEquals(false, loaded.get(second.Id).IsLocked__c);
      System.assertEquals(
        1,
        loaded.get(first.Id).Amount__c,
        'Accounting 第9.5節・Core 第7.7.3節: Lockは金額を変えない'
      );
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        loaded.get(first.Id).PostingDate__c,
        'Accounting 第9.5節: Lockは日付を変えない'
      );
      System.assertEquals(
        debit.Id,
        loaded.get(first.Id).DebitAccount__c,
        'Accounting 第9.5節: Lockは科目を変えない'
      );
      System.assertEquals(
        credit.Id,
        loaded.get(first.Id).CreditAccount__c,
        'Accounting 第9.5節: Lockは借貸を変えない'
      );
    }
  }

  @IsTest
  static void lockForInvoice_allowsFuturePostingDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      GlAccount__c debit = new GlAccount__c(
        Name = 'JLock Future Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'JLock Future Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      Date futureDate = Date.today().addYears(1);
      GlJournal__c futureJournal = new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'JL-FUTURE' }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = futureDate,
        TransactionStatus__c = 'Active'
      );
      insert futureJournal;

      Test.startTest();
      Integer locked = JournalLockService.lockForInvoice(
        invoice.Id,
        new List<Id>{ futureJournal.Id },
        AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id),
        null
      );
      Test.stopTest();

      System.assertEquals(
        1,
        locked,
        'Accounting 第9.5節・Core 第7.7.3節: 未来日付の行も選べる'
      );
      GlJournal__c loaded = [
        SELECT IsLocked__c, PostingDate__c
        FROM GlJournal__c
        WHERE Id = :futureJournal.Id
      ];
      System.assertEquals(true, loaded.IsLocked__c);
      System.assertEquals(
        futureDate,
        loaded.PostingDate__c,
        'Accounting 第9.5節: Lockは日付を変えない'
      );
    }
  }

  @IsTest
  static void lockForInvoice_rejectsCancelledJournalStatus() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = Date.today();
      InvoiceTransactionStatusService.allowStatusWrite = true;
      update invoice;
      InvoiceTransactionStatusService.allowStatusWrite = false;
      GlAccount__c debit = new GlAccount__c(
        Name = 'JLock Cancelled Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'JLock Cancelled Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlJournal__c cancelled = new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'JL-CANCELLED' }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Cancelled'
      );
      insert cancelled;

      Boolean thrown = false;
      try {
        Test.startTest();
        JournalLockService.lockForInvoice(
          invoice.Id,
          new List<Id>{ cancelled.Id },
          AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id),
          null
        );
        Test.stopTest();
      } catch (JournalLockService.LockException ex) {
        thrown = true;
        System.assertEquals(
          '有効と取消の仕訳だけをLock/Unlockできます。',
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        thrown,
        'Accounting 第2.3節・第9.5節: 取消済仕訳はLockできない'
      );
    }
  }

  @IsTest
  static void lockForInvoice_rejectsAuditJournalStatuses_withActiveOnlyMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = Date.today();
      InvoiceTransactionStatusService.allowStatusWrite = true;
      update invoice;
      InvoiceTransactionStatusService.allowStatusWrite = false;
      GlAccount__c debit = new GlAccount__c(
        Name = 'JLock Audit Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'JLock Audit Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlJournal__c logicallyDeleted = new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'JL-LD' }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'LogicallyDeleted'
      );
      insert logicallyDeleted;

      Boolean thrown = false;
      try {
        JournalLockService.lockForInvoice(
          invoice.Id,
          new List<Id>{ logicallyDeleted.Id },
          AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id),
          null
        );
      } catch (JournalLockService.LockException ex) {
        thrown = true;
        System.assertEquals(
          '有効と取消の仕訳だけをLock/Unlockできます。',
          ex.getMessage(),
          'Accounting 第9.5節: 論理削除は請求以外扱いの拒否文にしない'
        );
        System.assertEquals(
          false,
          ex.getMessage().contains('この請求以外'),
          '件数不一致の誤メッセージにしない'
        );
      }
      System.assertEquals(
        true,
        thrown,
        'Accounting 第9.5節: 論理削除仕訳はLockできない'
      );
    }
  }

  @IsTest
  static void lockForInvoice_locksReversalJournal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = Date.today();
      InvoiceTransactionStatusService.allowStatusWrite = true;
      update invoice;
      InvoiceTransactionStatusService.allowStatusWrite = false;
      GlAccount__c debit = new GlAccount__c(
        Name = 'JLock Reversal Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'JLock Reversal Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlJournal__c reversal = new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'JL-REV-LOCK' }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 2),
        TransactionStatus__c = 'Reversal',
        IsLocked__c = false
      );
      insert reversal;

      Test.startTest();
      Integer locked = JournalLockService.lockForInvoice(
        invoice.Id,
        new List<Id>{ reversal.Id },
        AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id),
        null
      );
      Test.stopTest();

      System.assertEquals(
        1,
        locked,
        'Accounting 第9.5節: 取消仕訳も手動Lockできる'
      );
      reversal = [
        SELECT IsLocked__c
        FROM GlJournal__c
        WHERE Id = :reversal.Id
      ];
      System.assertEquals(
        true,
        reversal.IsLocked__c,
        'Accounting 第9.5節: 取消行のIsLocked__cをTrueにする'
      );
    }
  }

  @IsTest
  static void unlockForInvoice_writesUnlockReason_andLockDoesNotClear() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      GlAccount__c debit = new GlAccount__c(
        Name = 'JLock Reason Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'JLock Reason Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlJournal__c journal = new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'JL-REASON' }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active',
        IsLocked__c = true
      );
      insert journal;

      String token = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Test.startTest();
      Integer unlocked = JournalLockService.unlockForInvoice(
        invoice.Id,
        new List<Id>{ journal.Id },
        '確認のため',
        token,
        null
      );
      token = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Integer reUnlocked = JournalLockService.unlockForInvoice(
        invoice.Id,
        new List<Id>{ journal.Id },
        '再Unlock',
        token,
        null
      );
      token = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Integer locked = JournalLockService.lockForInvoice(
        invoice.Id,
        new List<Id>{ journal.Id },
        token,
        null
      );
      Test.stopTest();

      System.assertEquals(1, unlocked, 'Accounting 第9.5節: Unlockできる');
      System.assertEquals(1, reUnlocked, 'Accounting 第9.5節: 再Unlockできる');
      System.assertEquals(1, locked, 'Accounting 第9.5節: Lockできる');
      GlJournal__c loaded = [
        SELECT IsLocked__c, UnlockReason__c
        FROM GlJournal__c
        WHERE Id = :journal.Id
      ];
      System.assertEquals(true, loaded.IsLocked__c);
      System.assertEquals(
        '再Unlock',
        loaded.UnlockReason__c,
        'Accounting 第9.5節: 再Unlockは理由を上書きし、LockではUnlockReasonを消さない'
      );
    }
  }

  @IsTest
  static void lockForInvoice_rejectsOtherInvoiceJournals() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      Invoice__c other = insertInvoice();
      GlAccount__c debit = new GlAccount__c(
        Name = 'JLock Other Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'JLock Other Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlJournal__c otherJournal = new GlJournal__c(
        Invoice__c = other.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'JL-OTHER' }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      insert otherJournal;

      Boolean thrown = false;
      try {
        JournalLockService.lockForInvoice(
          invoice.Id,
          new List<Id>{ otherJournal.Id }
        );
      } catch (JournalLockService.LockException ex) {
        thrown = true;
        System.assertEquals(
          'この請求以外の仕訳はLock/Unlockできません。',
          ex.getMessage(),
          'Accounting 第9.5節: この請求以外の仕訳は選べない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  private static Invoice__c insertInvoice() {
    Account account = ContractTestDataFactory.insertAccount(
      'JLock ' + String.valueOf(Crypto.getRandomInteger())
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'jlock@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 1,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      'JLock Opp'
    );
    ContractService__c service = new ContractService__c(
      Name = 'JLock Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'JLock History',
      ContractService__c = service.Id,
      Opportunity__c = opportunity.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1
    );
    insert history;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = 100,
      BillingAccountSnapShot__c = billingAccount.Id,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT
    );
    insert invoice;
    return invoice;
  }

  @IsTest
  static void assertExemptUpdate_lockedMemoAllowed_amountDenied() {
    GlJournal__c prior = new GlJournal__c(
      Amount__c = 100,
      Memo__c = 'old',
      IsLocked__c = true
    );
    GlJournal__c memoOnly = new GlJournal__c(
      Amount__c = 100,
      Memo__c = 'new',
      IsLocked__c = true
    );
    JournalLockService.testLockExemptFieldApiNames = '';
    JournalLockService.assertExemptUpdate(prior, memoOnly);

    GlJournal__c amountChange = new GlJournal__c(
      Amount__c = 200,
      Memo__c = 'old',
      IsLocked__c = true
    );
    Boolean thrown = false;
    try {
      JournalLockService.testLockExemptFieldApiNames = 'Memo__c,Amount__c';
      JournalLockService.assertExemptUpdate(prior, amountChange);
    } catch (JournalLockService.LockException ex) {
      thrown = true;
      System.assertEquals(
        JournalLockService.NEVER_EXEMPT_MESSAGE,
        ex.getMessage(),
        'Core 第11.6節・Accounting 第9.5節: 金額・科目・日付はリストに書いても不可'
      );
    }
    System.assertEquals(true, thrown);
    JournalLockService.testLockExemptFieldApiNames = null;
  }

  @IsTest
  static void assertExemptUpdate_unlockedMemoAllowed() {
    GlJournal__c prior = new GlJournal__c(
      Amount__c = 100,
      Memo__c = 'a',
      IsLocked__c = false
    );
    GlJournal__c memoOnly = new GlJournal__c(
      Amount__c = 100,
      Memo__c = 'b',
      IsLocked__c = false
    );
    InvoiceOpsFieldService.setCachedRowsForTest(
      new List<InvoiceOpsField__mdt>()
    );
    Boolean thrown = false;
    try {
      JournalLockService.assertExemptUpdate(prior, memoOnly);
    } catch (JournalLockService.LockException ex) {
      thrown = true;
    }
    System.assertEquals(
      false,
      thrown,
      'Accounting 第9.5節・Core 第11.6節: 標準メモは製品固定でLock後も直せる。未Lockも直せる'
    );
    InvoiceOpsFieldService.resetCache();
  }

  @IsTest
  static void assertExemptUpdate_unlockedRejectsNonScreenField() {
    GlJournal__c prior = new GlJournal__c(
      Amount__c = 100,
      Memo__c = 'a',
      IdempotencyKey__c = 'k1',
      IsLocked__c = false
    );
    GlJournal__c changed = new GlJournal__c(
      Amount__c = 100,
      Memo__c = 'a',
      IdempotencyKey__c = 'k2',
      IsLocked__c = false
    );
    InvoiceOpsFieldService.setCachedRowsForTest(
      new List<InvoiceOpsField__mdt>()
    );
    Boolean thrown = false;
    try {
      JournalLockService.assertExemptUpdate(prior, changed);
    } catch (JournalLockService.LockException ex) {
      thrown = true;
      System.assertEquals(
        JournalLockService.UNLOCKED_NOT_SCREEN_MESSAGE,
        ex.getMessage(),
        'Accounting 第9.5節: 未Lockは画面定義の追加項目以外を更新できない'
      );
    }
    System.assertEquals(true, thrown);
    InvoiceOpsFieldService.resetCache();
  }
}
