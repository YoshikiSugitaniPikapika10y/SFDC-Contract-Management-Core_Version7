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
  static void load_isInvoiceScopedAndReusesCacheUntilInvalidated() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c firstInvoice = insertDraftInvoice();
      Invoice__c otherInvoice = insertDraftInvoice();
      AccountPair accounts = insertAccounts('Scope');
      GlJournal__c firstJournal = insertJournal(
        firstInvoice.Id,
        accounts,
        1000,
        'Active',
        false,
        'scope-first'
      );
      insertJournal(
        otherInvoice.Id,
        accounts,
        2000,
        'Active',
        false,
        'scope-other'
      );
      AccountingCurrentService.currentLoadSelectCount = 0;

      List<GlJournal__c> first = AccountingCurrentService.load(firstInvoice.Id);
      System.assertEquals(
        1,
        first.size(),
        'Accounting 第1.2節・第8.2節: 対象請求書の仕訳だけを収集する'
      );
      System.assertEquals(firstJournal.Id, first[0].Id);
      System.assertEquals(1000, first[0].Amount__c);
      System.assertEquals(1, AccountingCurrentService.currentLoadSelectCount);

      List<GlJournal__c> cached = AccountingCurrentService.load(
        firstInvoice.Id
      );
      System.assertEquals(firstJournal.Id, cached[0].Id);
      System.assertEquals(
        1,
        AccountingCurrentService.currentLoadSelectCount,
        'Accounting 第8.2節: 同一請求の収集済み仕訳を再照会しない'
      );

      AccountingCurrentService.invalidate(firstInvoice.Id);
      System.assertEquals(
        false,
        AccountingCurrentService.hasLoaded(firstInvoice.Id)
      );
      List<GlJournal__c> reloaded = AccountingCurrentService.load(
        firstInvoice.Id
      );
      System.assertEquals(firstJournal.Id, reloaded[0].Id);
      System.assertEquals(
        2,
        AccountingCurrentService.currentLoadSelectCount,
        'Accounting 第8.2節: 無効化後は対象請求の仕訳を取り直す'
      );
    }
  }

  @IsTest
  static void invalidateForJournals_invalidatesOnlyReferencedInvoices() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c firstInvoice = insertDraftInvoice();
      Invoice__c otherInvoice = insertDraftInvoice();
      AccountPair accounts = insertAccounts('Invalidate');
      insertJournal(
        firstInvoice.Id,
        accounts,
        1100,
        'Active',
        false,
        'invalidate-first'
      );
      insertJournal(
        otherInvoice.Id,
        accounts,
        2200,
        'Active',
        false,
        'invalidate-other'
      );
      List<GlJournal__c> firstRows = AccountingCurrentService.load(
        firstInvoice.Id
      );
      AccountingCurrentService.load(otherInvoice.Id);

      AccountingCurrentService.invalidateForJournals(
        new List<GlJournal__c>{ firstRows[0], null }
      );

      System.assertEquals(
        false,
        AccountingCurrentService.hasLoaded(firstInvoice.Id)
      );
      System.assertEquals(
        true,
        AccountingCurrentService.hasLoaded(otherInvoice.Id),
        'Accounting 第8.2節: 変更された仕訳の請求だけを無効化する'
      );
    }
  }

  @IsTest
  static void replace_andLoadKeepIndependentCopies() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertDraftInvoice();
      AccountPair accounts = insertAccounts('Replace');
      GlJournal__c inserted = insertJournal(
        invoice.Id,
        accounts,
        1300,
        'Active',
        false,
        'replace'
      );
      GlJournal__c source = [
        SELECT Id, Invoice__c, Amount__c, TransactionStatus__c, LastModifiedDate
        FROM GlJournal__c
        WHERE Id = :inserted.Id
      ];
      AccountingCurrentService.currentLoadSelectCount = 0;

      AccountingCurrentService.replace(
        invoice.Id,
        new List<GlJournal__c>{ source }
      );
      source.Amount__c = 9999;
      List<GlJournal__c> first = AccountingCurrentService.load(invoice.Id);
      System.assertEquals(1300, first[0].Amount__c);
      first[0].TransactionStatus__c = 'Cancelled';

      List<GlJournal__c> second = AccountingCurrentService.load(invoice.Id);
      System.assertEquals(
        'Active',
        second[0].TransactionStatus__c,
        'Accounting 第8.2節: 呼出側の変更で収集済み仕訳を書き換えない'
      );
      System.assertEquals(0, AccountingCurrentService.currentLoadSelectCount);
      System.assertEquals(true, AccountingCurrentService.hasLoaded(invoice.Id));
      System.assertEquals(
        source.LastModifiedDate,
        AccountingCurrentService.maxLastModified(invoice.Id)
      );
    }
  }

  @IsTest
  static void load_mergesKnownRowsAndExcludesThemFromSelect() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertDraftInvoice();
      AccountPair accounts = insertAccounts('Known');
      GlJournal__c knownInserted = insertJournal(
        invoice.Id,
        accounts,
        1400,
        'Active',
        true,
        'known'
      );
      GlJournal__c loadedInserted = insertJournal(
        invoice.Id,
        accounts,
        1500,
        'Active',
        false,
        'loaded'
      );
      GlJournal__c known = [
        SELECT
          Id,
          Invoice__c,
          Amount__c,
          TransactionStatus__c,
          IsLocked__c,
          LastModifiedDate
        FROM GlJournal__c
        WHERE Id = :knownInserted.Id
      ];
      known.Amount__c = 1410;
      AccountingCurrentService.currentLoadSelectCount = 0;

      List<GlJournal__c> merged = AccountingCurrentService.load(
        invoice.Id,
        new List<GlJournal__c>{ known }
      );
      Map<Id, GlJournal__c> mergedById = new Map<Id, GlJournal__c>(merged);

      System.assertEquals(2, merged.size());
      System.assertEquals(1410, mergedById.get(knownInserted.Id).Amount__c);
      System.assertEquals(1500, mergedById.get(loadedInserted.Id).Amount__c);
      System.assertEquals(
        new Set<Id>{ knownInserted.Id },
        AccountingCurrentService.lastLoadExcludedIds,
        'Core 第12.4節・第7.9.7節: 更新日時付き既知行は再照会しない'
      );
      System.assertEquals(1, AccountingCurrentService.currentLoadSelectCount);
    }
  }

  @IsTest
  static void hasActiveLocked_requiresBothActiveAndLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c activeLockedInvoice = insertDraftInvoice();
      Invoice__c inactiveLockedInvoice = insertDraftInvoice();
      Invoice__c activeUnlockedInvoice = insertDraftInvoice();
      AccountPair accounts = insertAccounts('Lock');
      insertJournal(
        activeLockedInvoice.Id,
        accounts,
        1600,
        'Active',
        true,
        'active-locked'
      );
      insertJournal(
        inactiveLockedInvoice.Id,
        accounts,
        1700,
        'Cancelled',
        true,
        'cancelled-locked'
      );
      insertJournal(
        activeUnlockedInvoice.Id,
        accounts,
        1800,
        'Active',
        false,
        'active-unlocked'
      );

      System.assertEquals(
        true,
        AccountingCurrentService.hasActiveLocked(activeLockedInvoice.Id)
      );
      System.assertEquals(
        false,
        AccountingCurrentService.hasActiveLocked(inactiveLockedInvoice.Id),
        'Accounting 第1.8.1節・第8.5節: 取消済み元仕訳のLockはActive Lockに数えない'
      );
      System.assertEquals(
        false,
        AccountingCurrentService.hasActiveLocked(activeUnlockedInvoice.Id)
      );
      System.assertEquals(
        false,
        AccountingCurrentService.hasActiveLocked(null)
      );
    }
  }

  @IsTest
  static void hasLoadedAll_andMaxLastModifiedUseLoadedCache() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c firstInvoice = insertDraftInvoice();
      Invoice__c otherInvoice = insertDraftInvoice();
      AccountPair accounts = insertAccounts('Loaded');
      insertJournal(
        firstInvoice.Id,
        accounts,
        1900,
        'Active',
        false,
        'loaded-first'
      );
      insertJournal(
        firstInvoice.Id,
        accounts,
        2000,
        'Active',
        false,
        'loaded-second'
      );
      insertJournal(
        otherInvoice.Id,
        accounts,
        2100,
        'Active',
        false,
        'loaded-other'
      );
      System.assertEquals(
        null,
        AccountingCurrentService.maxLastModified(firstInvoice.Id)
      );
      System.assertEquals(
        false,
        AccountingCurrentService.hasLoadedAll(
          new Set<Id>{ firstInvoice.Id, otherInvoice.Id }
        )
      );

      List<GlJournal__c> firstRows = AccountingCurrentService.load(
        firstInvoice.Id
      );
      Datetime expectedLatest;
      for (GlJournal__c row : firstRows) {
        if (
          expectedLatest == null ||
          row.LastModifiedDate.getTime() > expectedLatest.getTime()
        ) {
          expectedLatest = row.LastModifiedDate;
        }
      }
      System.assertEquals(
        expectedLatest,
        AccountingCurrentService.maxLastModified(firstInvoice.Id),
        'Accounting 第8.2節: 版比較は収集済み仕訳の最新更新日時を使う'
      );
      System.assertEquals(
        false,
        AccountingCurrentService.hasLoadedAll(
          new Set<Id>{ firstInvoice.Id, otherInvoice.Id }
        )
      );

      AccountingCurrentService.load(otherInvoice.Id);
      System.assertEquals(
        true,
        AccountingCurrentService.hasLoadedAll(
          new Set<Id>{ firstInvoice.Id, otherInvoice.Id }
        )
      );
      System.assertEquals(
        false,
        AccountingCurrentService.hasLoadedAll(new Set<Id>())
      );
    }
  }

  private class AccountPair {
    Id debitId;
    Id creditId;
  }

  private static AccountPair insertAccounts(String suffix) {
    GlAccount__c debit = new GlAccount__c(
      Name = 'Current Debit ' + suffix,
      AccountType__c = 'Asset',
      IsActive__c = true
    );
    GlAccount__c credit = new GlAccount__c(
      Name = 'Current Credit ' + suffix,
      AccountType__c = 'Liability',
      IsActive__c = true
    );
    insert new List<GlAccount__c>{ debit, credit };
    AccountPair result = new AccountPair();
    result.debitId = debit.Id;
    result.creditId = credit.Id;
    return result;
  }

  private static GlJournal__c insertJournal(
    Id invoiceId,
    AccountPair accounts,
    Decimal amount,
    String status,
    Boolean locked,
    String keySuffix
  ) {
    GlJournal__c journal = new GlJournal__c(
      Invoice__c = invoiceId,
      Amount__c = amount,
      IdempotencyKey__c = AccountingDiffService.hashKey(
        new List<String>{ 'CurrentLoad', String.valueOf(invoiceId), keySuffix }
      ),
      DebitSlotKey__c = 'Cash',
      CreditSlotKey__c = 'UnappliedCash',
      DebitAccount__c = accounts.debitId,
      CreditAccount__c = accounts.creditId,
      PostingDate__c = Date.newInstance(2026, 6, 1),
      TransactionStatus__c = status,
      IsLocked__c = locked
    );
    insert journal;
    return journal;
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
