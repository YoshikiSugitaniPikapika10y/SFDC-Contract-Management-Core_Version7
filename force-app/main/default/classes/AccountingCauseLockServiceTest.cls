@IsTest
private class AccountingCauseLockServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void lockInvoice_rejectsNull() {
    Boolean thrown = false;
    try {
      AccountingCauseLockService.lockInvoice(null);
    } catch (AccountingCauseLockService.LockException ex) {
      thrown = true;
      System.assertEquals(
        '請求が指定されていません。',
        ex.getMessage(),
        'Accounting 第8.2節: 対象請求書が無ければパイプラインを始めない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void lockInvoice_returnsTargetInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertDraftInvoice();
      Invoice__c locked = AccountingCauseLockService.lockInvoice(invoice.Id);
      System.assertEquals(
        invoice.Id,
        locked.Id,
        'Accounting 第8.2節: 対象請求書を行ロックする'
      );
    }
  }

  @IsTest
  static void lockHistory_rejectsNullAndMissing() {
    Boolean nullThrown = false;
    try {
      AccountingCauseLockService.lockHistory(null);
    } catch (AccountingCauseLockService.LockException ex) {
      nullThrown = true;
      System.assertEquals(
        '契約履歴が指定されていません。',
        ex.getMessage(),
        'Core 第4.3.12節: 対象契約履歴が無ければ行ロックしない'
      );
    }
    System.assertEquals(true, nullThrown);
    Boolean missingThrown = false;
    try {
      AccountingCauseLockService.lockHistory(fakeId(ContractHistory__c.SObjectType));
    } catch (AccountingCauseLockService.LockException ex) {
      missingThrown = true;
      System.assertEquals(
        '契約履歴をロックできませんでした。',
        ex.getMessage(),
        'Core 第4.3.12節: 取れなければ操作全体を失敗させる'
      );
    }
    System.assertEquals(true, missingThrown);
  }

  @IsTest
  static void lockHistoryAndService_returnTargets() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertDraftInvoice();
      Invoice__c scoped = [
        SELECT ContractHistory__c, ContractService__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      ContractHistory__c lockedHistory = AccountingCauseLockService.lockHistory(
        scoped.ContractHistory__c
      );
      System.assertEquals(
        scoped.ContractHistory__c,
        lockedHistory.Id,
        'Core 第4.3.12節: 見積編集・受注・差し戻し・手動Archiveは契約履歴を行ロックする'
      );
      Boolean serviceNullThrown = false;
      try {
        AccountingCauseLockService.lockService(null);
      } catch (AccountingCauseLockService.LockException ex) {
        serviceNullThrown = true;
        System.assertEquals(
          '契約サービスが指定されていません。',
          ex.getMessage(),
          'Core 第3.4.1節: 対象の契約サービスを行ロックする'
        );
      }
      System.assertEquals(true, serviceNullThrown);
      ContractService__c lockedService = AccountingCauseLockService.lockService(
        scoped.ContractService__c
      );
      System.assertEquals(
        scoped.ContractService__c,
        lockedService.Id,
        'Core 第3.4.1節: 契約サービスを編集は対象の契約サービスを行ロックする'
      );
      Boolean serviceMissingThrown = false;
      try {
        AccountingCauseLockService.lockService(fakeId(ContractService__c.SObjectType));
      } catch (AccountingCauseLockService.LockException ex) {
        serviceMissingThrown = true;
        System.assertEquals(
          '契約サービスをロックできませんでした。',
          ex.getMessage(),
          'Core 第4.3.12節: 短時間待っても取れなければ操作全体を失敗させる'
        );
      }
      System.assertEquals(true, serviceMissingThrown);
    }
  }

  @IsTest
  static void resolveOrIssueOperationKey_blankIssuesAndKeepsProvided() {
    String issued = AccountingCauseLockService.resolveOrIssueOperationKey('  ');
    System.assertEquals(
      true,
      String.isNotBlank(issued),
      'Core 第7.9.7節: サーバが業務操作キーを発行する'
    );
    System.assertEquals(
      'given-key',
      AccountingCauseLockService.resolveOrIssueOperationKey(' given-key '),
      'Core 第7.9.7節: 画面は応答で受け取ったキーだけを再試行に使う'
    );
  }

  @IsTest
  static void lockInvoice_rejectsMissing() {
    Boolean thrown = false;
    try {
      AccountingCauseLockService.lockInvoice(fakeId(Invoice__c.SObjectType));
    } catch (AccountingCauseLockService.LockException ex) {
      thrown = true;
      System.assertEquals(
        '請求をロックできませんでした。',
        ex.getMessage(),
        'Accounting 第8.2節: 対象請求書を行ロックする'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void resolveInvoiceOperationDatetime_nullAndEmptyStayEmpty() {
    System.assertEquals(
      null,
      AccountingCauseLockService.resolveInvoiceOperationDatetime(null),
      'Core 第7.9.7節: 対象が無ければ版を取らない'
    );
    System.assertEquals(
      true,
      AccountingCauseLockService.resolveInvoiceOperationDatetimes(new Set<Id>())
        .isEmpty(),
      'Core 第7.9.7節: 空の対象は版マップを空のまま返す'
    );
  }

  @IsTest
  static void issueOperationKey_returnsDistinctKeys() {
    String first = AccountingCauseLockService.issueOperationKey();
    String second = AccountingCauseLockService.issueOperationKey();
    System.assertEquals(
      true,
      String.isNotBlank(first),
      'Core 第7.9.7節: サーバが業務操作キーを発行する'
    );
    System.assertEquals(
      false,
      first == second,
      'Core 第7.9.7節: 応答前の連打は別キーである'
    );
  }

  @IsTest
  static void resolveInvoiceOperationDatetime_includesJournal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertDraftInvoice();
      Datetime before = AccountingCauseLockService.resolveInvoiceOperationDatetime(
        invoice.Id
      );
      GlAccount__c debit = new GlAccount__c(
        Name = 'Lock Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'Lock Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'LockJournal', String.valueOf(invoice.Id) }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      Datetime afterJournal = AccountingCauseLockService.resolveInvoiceOperationDatetime(
        invoice.Id
      );
      System.assertEquals(
        true,
        afterJournal.getTime() >= before.getTime(),
        'Core 第7.9.7節: 版は対象請求と配下の仕訳を含む'
      );
    }
  }

  private static Id fakeId(Schema.SObjectType objectType) {
    return Id.valueOf(objectType.getDescribe().getKeyPrefix() + '000000000001');
  }

  private static Invoice__c insertDraftInvoice() {
    Account account = ContractTestDataFactory.insertAccount(
      'Lock ' + String.valueOf(Crypto.getRandomInteger())
    );
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      'Lock Service'
    );
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Lock History',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1
    );
    ContractTestDataFactory.applyRequiredFields(history);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
    insert history;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = 100,
      BillingAccountSnapShot__c = service.BiilingAcccount__c
    );
    ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    return invoice;
  }
}
