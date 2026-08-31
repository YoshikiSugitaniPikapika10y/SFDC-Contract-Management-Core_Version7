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
      System.assert(
        ex.getMessage().contains('Unlockには理由が必要です'),
        'Accounting 第9.5節: Unlockは理由必須'
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
      System.assert(
        ex.getMessage().contains('Unlock理由は255文字以内'),
        'Accounting 第9.1節: Unlock理由はテキスト255。実際: ' + ex.getMessage()
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
        System.assert(
          ex.getMessage().contains('AccountingがOFFのときはLock/Unlockできません'),
          'Accounting 第9.5節: OFFではLockしない'
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
        System.assert(
          ex.getMessage().contains('AccountingがOFFのときはLock/Unlockできません'),
          'Accounting 第9.5節: OFFではUnlockしない'
        );
      }
      System.assertEquals(true, thrown);
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
        System.assert(
          ex.getMessage().contains('Lockする仕訳を選んでください'),
          'Accounting 第9.5節: 未選択ではLockできない'
        );
      }
      System.assertEquals(true, thrown);
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
        IdempotencyKey__c = AccountingDiffService.hashKey(new List<String>{ 'JL1' }),
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

      System.assertEquals(1, locked, 'Accounting 第9.5節: 選んだ行だけLockする');
      Map<Id, GlJournal__c> loaded = new Map<Id, GlJournal__c>(
        [
          SELECT IsLocked__c
          FROM GlJournal__c
          WHERE Id IN :new List<Id>{ first.Id, second.Id }
        ]
      );
      System.assertEquals(true, loaded.get(first.Id).IsLocked__c);
      System.assertEquals(false, loaded.get(second.Id).IsLocked__c);
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
          '有効な仕訳だけをLock/Unlockできます。',
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
      GlJournal__c reversal = new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'JL-REV' }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 2),
        TransactionStatus__c = 'Reversal'
      );
      insert new List<GlJournal__c>{ logicallyDeleted, reversal };

      for (GlJournal__c auditJournal : new List<GlJournal__c>{
        logicallyDeleted,
        reversal
      }) {
        Boolean thrown = false;
        try {
          JournalLockService.lockForInvoice(
            invoice.Id,
            new List<Id>{ auditJournal.Id },
            AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id),
            null
          );
        } catch (JournalLockService.LockException ex) {
          thrown = true;
          System.assertEquals(
            '有効な仕訳だけをLock/Unlockできます。',
            ex.getMessage(),
            'Accounting 第2.3節・第9.5節: 監査仕訳は請求以外扱いの拒否文にしない'
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
          'Accounting 第2.3節・第9.5節: 論理削除・取消仕訳はLockできない'
        );
      }
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
      token = AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id);
      Integer reUnlocked = JournalLockService.unlockForInvoice(
        invoice.Id,
        new List<Id>{ journal.Id },
        '再Unlock',
        token,
        null
      );
      token = AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id);
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
        System.assert(
          ex.getMessage().contains('この請求以外の仕訳はLock/Unlockできません'),
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
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
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
    JournalLockService.testLockExemptFieldApiNames = 'Memo__c';
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
        'Core 第11.6節: 仕訳の金額は一覧に書いても不可'
      );
    }
    System.assertEquals(true, thrown);
    JournalLockService.testLockExemptFieldApiNames = null;
  }

  @IsTest
  static void assertExemptUpdate_unlockedRejectsNonScreenField() {
    GlJournal__c prior = new GlJournal__c(
      Amount__c = 100,
      Memo__c = 'a',
      IsLocked__c = false
    );
    GlJournal__c changed = new GlJournal__c(
      Amount__c = 100,
      Memo__c = 'b',
      IsLocked__c = false
    );
    InvoiceOpsFieldService.setCachedRowsForTest(new List<InvoiceOpsField__mdt>());
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
