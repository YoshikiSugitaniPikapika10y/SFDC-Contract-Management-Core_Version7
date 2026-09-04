@IsTest
private class ManualJournalServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void register_requiresCancellationDateWhenInvoiceHasLockedJournal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice(true);
      GlAccount__c debit = new GlAccount__c(
        Name = 'MJ Reg Lock Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'MJ Reg Lock Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 500,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'MJREGLOCK', String.valueOf(invoice.Id) }
        ),
        JournalLineKey__c = 'mj-reg-locked',
        DebitSlotKey__c = 'ContractLiability',
        CreditSlotKey__c = 'AccountsReceivable',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.today(),
        TransactionStatus__c = 'Active',
        IsLocked__c = true
      );
      ManualJournalService.RegisterRequest request = new ManualJournalService.RegisterRequest();
      request.invoiceId = invoice.Id;
      request.settingId = insertActiveSetting().Id;
      request.postingDate = Date.today();
      request.amount = 100;
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Boolean thrown = false;
      try {
        ManualJournalService.register(request);
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          'ロック済み仕訳がある取消では取消基準日が必要です。',
          ex.getMessage(),
          'Accounting 第8.5節・第8.8節: Lockがある手動登録は取消基準日必須'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void previewRegister_doesNotPersistHeader() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice(true);
      ManualJournalService.RegisterRequest request = new ManualJournalService.RegisterRequest();
      request.invoiceId = invoice.Id;
      request.settingId = insertActiveSetting().Id;
      request.postingDate = Date.today();
      request.amount = 100;
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Test.startTest();
      AccountingDiffService.CancelPreview preview = ManualJournalService.previewRegister(
        request
      );
      Test.stopTest();
      System.assertNotEquals(null, preview);
      System.assertNotEquals(null, preview.displayText);
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM GlManualJournalHeader__c
          WHERE Invoice__c = :invoice.Id
        ],
        'Accounting 第8.8節: 実行前プレビューは登録しない'
      );
    }
  }

  @IsTest
  static void register_thenCancel_keepsCauseLifecycle() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice(true);
      ManualJournalService.RegisterRequest request = new ManualJournalService.RegisterRequest();
      request.invoiceId = invoice.Id;
      request.settingId = insertActiveSetting().Id;
      request.postingDate = Date.today();
      request.amount = 100;
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Test.startTest();
      Id headerId = ManualJournalService.register(request);
      Test.stopTest();
      System.assertNotEquals(null, headerId, 'Accounting 第10.3節: 登録できる');
      GlManualJournalHeader__c header = [
        SELECT TransactionStatus__c
        FROM GlManualJournalHeader__c
        WHERE Id = :headerId
      ];
      System.assertEquals('Active', header.TransactionStatus__c);
      ManualJournalService.CancelRequest cancelRequest = new ManualJournalService.CancelRequest();
      cancelRequest.headerId = headerId;
      cancelRequest.cancellationReason = 'Duplicate';
      cancelRequest.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      ManualJournalService.cancel(cancelRequest);
      System.assertEquals(
        'Cancelled',
        [
          SELECT TransactionStatus__c
          FROM GlManualJournalHeader__c
          WHERE Id = :headerId
        ]
        .TransactionStatus__c,
        'Accounting 第10.4節: 取消できる'
      );
    }
  }

  @IsTest
  static void previewRegister_requiresCancellationDateWhenInvoiceHasLockedJournal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice(true);
      GlAccount__c debit = new GlAccount__c(
        Name = 'MJ Prev Lock Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'MJ Prev Lock Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 500,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'MJPREVLOCK', String.valueOf(invoice.Id) }
        ),
        JournalLineKey__c = 'mj-prev-locked',
        DebitSlotKey__c = 'ContractLiability',
        CreditSlotKey__c = 'AccountsReceivable',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.today(),
        TransactionStatus__c = 'Active',
        IsLocked__c = true
      );
      ManualJournalService.RegisterRequest request = new ManualJournalService.RegisterRequest();
      request.invoiceId = invoice.Id;
      request.settingId = insertActiveSetting().Id;
      request.postingDate = Date.today();
      request.amount = 100;
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Boolean thrown = false;
      try {
        ManualJournalService.previewRegister(request);
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          'ロック済み仕訳がある取消では取消基準日が必要です。',
          ex.getMessage(),
          'Accounting 第8.5節・第8.8節: Lockがある手動登録プレビューも取消基準日必須'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void register_rejectsNegativeAmount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ManualJournalService.RegisterRequest request = new ManualJournalService.RegisterRequest();
      request.invoiceId = UserInfo.getUserId();
      request.settingId = UserInfo.getUserId();
      request.postingDate = Date.today();
      request.amount = -1;
      Boolean thrown = false;
      try {
        ManualJournalService.register(request);
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          '金額は0より大きい整数にしてください。',
          ex.getMessage(),
          'Accounting 第10.3節: 負数は自動反転せず拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void register_rejectsWhenAccountingOff() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      ManualJournalService.RegisterRequest request = new ManualJournalService.RegisterRequest();
      request.invoiceId = insertInvoice(true).Id;
      request.settingId = insertActiveSetting().Id;
      request.postingDate = Date.today();
      request.amount = 100;
      Boolean thrown = false;
      try {
        ManualJournalService.register(request);
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          'AccountingがOFFのときは手動仕訳を登録できません。',
          ex.getMessage(),
          'Accounting 第10.3節: OFFなら登録しない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void cancel_requiresReason() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ManualJournalService.CancelRequest request = new ManualJournalService.CancelRequest();
      request.headerId = UserInfo.getUserId();
      Boolean thrown = false;
      try {
        ManualJournalService.cancel(request);
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          '取消理由を入力してください。',
          ex.getMessage(),
          'Accounting 第10.4節: 取消理由は必須'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void register_withoutManageInvoiceOps_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ManualJournalService.RegisterRequest request = new ManualJournalService.RegisterRequest();
      request.invoiceId = UserInfo.getUserId();
      request.settingId = UserInfo.getUserId();
      request.postingDate = Date.today();
      request.amount = 100;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MANUAL_JOURNAL => false
      };
      Boolean thrown = false;
      try {
        ManualJournalService.register(request);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '手動仕訳を実行する権限がありません。',
          ex.getMessage(),
          'Core 第7.7.3節: 手動仕訳登録は請求ボード操作権限を見る'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void cancel_withoutManageInvoiceOps_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ManualJournalService.CancelRequest request = new ManualJournalService.CancelRequest();
      request.headerId = UserInfo.getUserId();
      request.cancellationReason = 'Duplicate';
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MANUAL_JOURNAL => false
      };
      Boolean thrown = false;
      try {
        ManualJournalService.cancel(request);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '手動仕訳を実行する権限がありません。',
          ex.getMessage(),
          'Core 第7.7.3節: 手動仕訳取消は請求ボード操作権限を見る'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void cancel_requiresDateWhenLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertInvoice(true);
      GlManualJournalHeader__c header = new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = insertActiveSetting().Id,
        PostingDate__c = Date.today(),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      insert header;
      GlAccount__c debit = new GlAccount__c(
        Name = 'MJ Lock Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'MJ Lock Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        GlManualJournalHeader__c = header.Id,
        Amount__c = 100,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'MJLOCK', String.valueOf(header.Id) }
        ),
        DebitSlotKey__c = 'FxLoss',
        CreditSlotKey__c = 'AccountsReceivable',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.today(),
        TransactionStatus__c = 'Active',
        IsLocked__c = true
      );
      ManualJournalService.CancelRequest request = new ManualJournalService.CancelRequest();
      request.headerId = header.Id;
      request.cancellationReason = 'Duplicate';
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Boolean thrown = false;
      try {
        ManualJournalService.cancel(request);
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          'ロック済み仕訳がある取消では取消基準日が必要です。',
          ex.getMessage(),
          'Accounting 第10.3節、第10.4節、日付仕様 第7.3節: ロック済みなら未入力はエラー'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void cancel_requiresDateWhenInvoiceHasLockedNonHeaderJournal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertInvoice(true);
      GlManualJournalHeader__c header = new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = insertActiveSetting().Id,
        PostingDate__c = Date.today(),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      insert header;
      GlAccount__c debit = new GlAccount__c(
        Name = 'MJ InvLock Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'MJ InvLock Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      // ヘッダー配下は未ロック。請求書上の別仕訳だけ Lock（BUG-088）。
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        GlManualJournalHeader__c = header.Id,
        Amount__c = 100,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'MJHDR', String.valueOf(header.Id) }
        ),
        JournalLineKey__c = 'mj-header-unlocked',
        DebitSlotKey__c = 'FxLoss',
        CreditSlotKey__c = 'AccountsReceivable',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.today(),
        TransactionStatus__c = 'Active',
        IsLocked__c = false
      );
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 500,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'MJAUTO', String.valueOf(invoice.Id) }
        ),
        JournalLineKey__c = 'mj-auto-locked',
        DebitSlotKey__c = 'ContractLiability',
        CreditSlotKey__c = 'AccountsReceivable',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.today(),
        TransactionStatus__c = 'Active',
        IsLocked__c = true
      );
      ManualJournalService.CancelRequest request = new ManualJournalService.CancelRequest();
      request.headerId = header.Id;
      request.cancellationReason = 'Duplicate';
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Boolean thrown = false;
      try {
        ManualJournalService.cancel(request);
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          'ロック済み仕訳がある取消では取消基準日が必要です。',
          ex.getMessage(),
          'Accounting 第8.5節: 請求書単位の Active Lock で取消基準日必須'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void previewCancel_offCountsHeaderJournals() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertInvoice(true);
      GlManualJournalHeader__c header = new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = insertActiveSetting().Id,
        PostingDate__c = Date.today(),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      insert header;
      GlAccount__c debit = new GlAccount__c(
        Name = 'MJ Preview Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'MJ Preview Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        GlManualJournalHeader__c = header.Id,
        Amount__c = 100,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'MJPREV', String.valueOf(header.Id) }
        ),
        DebitSlotKey__c = 'FxLoss',
        CreditSlotKey__c = 'AccountsReceivable',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.today(),
        TransactionStatus__c = 'Active',
        IsLocked__c = false
      );

      AccountingDiffService.CancelPreview preview = ManualJournalService.previewCancel(
        header.Id,
        null
      );
      System.assertEquals(
        1,
        preview.logicalDeleteCount,
        'OFF は cancelCurrent と同じくヘッダー仕訳を数える'
      );
      System.assertEquals(0, preview.reverseCount);
      System.assertEquals(
        false,
        preview.hasFutureReverseDate,
        'Core 第7.9.6節: 逆仕訳が無ければ将来日付はなし'
      );
    }
  }

  @IsTest
  static void previewCancel_onCountsGoalDiffNotHeaderOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice(true);
      GlManualJournalHeader__c header = new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = insertActiveSetting().Id,
        PostingDate__c = Date.today(),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      insert header;
      GlAccount__c debit = new GlAccount__c(
        Name = 'MJ Diff Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'MJ Diff Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        GlManualJournalHeader__c = header.Id,
        Amount__c = 100,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'MJDIFF-H', String.valueOf(header.Id) }
        ),
        JournalLineKey__c = 'mj-diff-header',
        GenerationUnitKey__c = 'mj-diff-header-gu',
        DebitSlotKey__c = 'FxLoss',
        CreditSlotKey__c = 'AccountsReceivable',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.today(),
        TransactionStatus__c = 'Active',
        IsLocked__c = false
      );
      // Goal に載らない Current のみの自動仕訳。ヘッダー除外後 Diff で論理削除される（BUG-089）。
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 40,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'MJDIFF-A', String.valueOf(invoice.Id) }
        ),
        JournalLineKey__c = 'mj-diff-auto',
        GenerationUnitKey__c = 'mj-diff-auto-gu',
        DebitSlotKey__c = 'ContractLiability',
        CreditSlotKey__c = 'AccountsReceivable',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.today(),
        TransactionStatus__c = 'Active',
        IsLocked__c = false
      );

      AccountingDiffService.CancelPreview preview = ManualJournalService.previewCancel(
        header.Id,
        null
      );
      System.assertEquals(
        2,
        preview.logicalDeleteCount,
        'Accounting 第8.8節・Core 第7.9.6節: ON は Goal Diff 全体（ヘッダー以外も）を数える'
      );
      System.assertEquals(0, preview.reverseCount);
    }
  }

  private static Invoice__c insertInvoice(Boolean confirmed) {
    Account account = ContractTestDataFactory.insertAccount(
      'MJSvc ' + String.valueOf(Crypto.getRandomInteger())
    );
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      'MJSvc Service'
    );
    BillingAccount__c billingAccount = [
      SELECT Id
      FROM BillingAccount__c
      WHERE Id = :service.BiilingAcccount__c
    ];
    ContractHistory__c history = new ContractHistory__c(
      Name = 'MJSvc History',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1
    );
    ContractTestDataFactory.applyRequiredFields(history);
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
      BillingAccountSnapShot__c = billingAccount.Id,
      InvoiceTransactionStatus__c = confirmed
        ? InvoiceTransactionStatusService.TX_CONFIRMED
        : InvoiceTransactionStatusService.TX_DRAFT,
      SystemIntegrationDate__c = confirmed ? Date.today() : null
    );
    ContractTestDataFactory.applyRequiredFields(invoice);
    ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
    if (confirmed) {
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = Date.today();
    } else {
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT;
      invoice.SystemIntegrationDate__c = null;
    }
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    return invoice;
  }

  @IsTest
  static void register_rejectsInactiveSetting() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice(true);
      GlManualJournalSetting__c setting = insertActiveSetting();
      setting.IsActive__c = false;
      update setting;
      ManualJournalService.RegisterRequest request = new ManualJournalService.RegisterRequest();
      request.invoiceId = invoice.Id;
      request.settingId = setting.Id;
      request.postingDate = Date.today();
      request.amount = 100;
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Boolean thrown = false;
      try {
        ManualJournalService.register(request);
      } catch (Exception ex) {
        thrown = true;
        System.assertEquals(
          '有効な手動仕訳設定だけ選べます。',
          ex.getMessage(),
          'Accounting 第10.3節: 利用者は有効なメニューだけを指定する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_rejectsSameSlotSameAccountCashInactiveEquityAndCategory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c expense = insertAccount('MJ Exp', 'Expense', true);
      GlAccount__c asset = insertAccount('MJ Ast', 'Asset', true);
      GlAccount__c asset2 = insertAccount('MJ Ast2', 'Asset', true);
      GlAccount__c expense2 = insertAccount('MJ Exp2', 'Expense', true);
      GlAccount__c inactive = insertAccount('MJ Inact', 'Expense', false);

      assertSettingRejected(
        'FxLoss',
        expense.Id,
        'FxLoss',
        expense2.Id,
        '借方と貸方に同じスロットは指定できません。',
        'Accounting 第10.2節: 同一スロットを拒否する'
      );
      assertSettingRejected(
        'FxLoss',
        expense.Id,
        'OtherExpense',
        expense.Id,
        '借方と貸方に同じ科目は指定できません。',
        'Accounting 第10.2節: 同一科目を拒否する'
      );
      assertSettingRejected(
        'Cash',
        asset.Id,
        'AccountsReceivable',
        asset2.Id,
        '現金・預金は指定できません',
        'Accounting 第10.2節: CASHを拒否する'
      );
      assertSettingRejected(
        'FxLoss',
        inactive.Id,
        'AccountsReceivable',
        asset.Id,
        '無効な勘定科目は手動仕訳設定に指定できません。',
        'Accounting 第10.2節: 無効科目を拒否する'
      );
      Boolean equityInsertRejected = false;
      try {
        insert new GlAccount__c(
          Name = 'MJ Eq',
          AccountType__c = 'Equity',
          IsActive__c = true
        );
      } catch (DmlException ex) {
        equityInsertRejected = true;
        System.assert(
          ex.getMessage().contains('Equity') ||
            ex.getMessage().contains('選択リスト'),
          'Accounting 第4.1節: 新規作成で純資産を選ばせない。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, equityInsertRejected);
      assertSettingRejected(
        'FxLoss',
        asset.Id,
        'AccountsReceivable',
        asset2.Id,
        'スロットと科目の勘定区分が一致していません。',
        'Accounting 第10.2節: スロットと科目の勘定区分を一致させる'
      );
    }
  }

  @IsTest
  static void save_rejectsDuplicateAndChangedSettingKey() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccount__c expense = insertAccount('MJ Key Exp', 'Expense', true);
      GlAccount__c asset = insertAccount('MJ Key Ast', 'Asset', true);
      GlManualJournalSetting__c first = validSetting(
        expense.Id,
        asset.Id,
        'DUP_KEY'
      );
      insert first;

      Boolean duplicateThrown = false;
      try {
        insert validSetting(expense.Id, asset.Id, 'DUP_KEY');
      } catch (DmlException ex) {
        duplicateThrown = true;
        System.assert(
          ex.getMessage().contains('重複') ||
            ex.getMessage().toLowerCase().contains('duplicate') ||
            ex.getMessage().contains('DUP_KEY'),
          'Accounting 第10.2節: シードキーは組織内一意。実際: ' + ex.getMessage()
        );
      }
      System.assertEquals(true, duplicateThrown);

      first.SettingKey__c = 'OTHER_KEY';
      Boolean changedThrown = false;
      try {
        update first;
      } catch (DmlException ex) {
        changedThrown = true;
        System.assert(
          ex.getMessage().contains('シードキーは作成後に変更できません。'),
          'Accounting 第10.2節: シードキーは作成後変更不可。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, changedThrown);
    }
  }

  @IsTest
  static void delete_rejectsReferencedSetting() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertInvoice(true);
      GlManualJournalSetting__c setting = insertActiveSetting();
      insert new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = setting.Id,
        PostingDate__c = Date.today(),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      Boolean thrown = false;
      try {
        delete setting;
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          '参照されている手動仕訳設定は削除できません。無効化してください。',
          ex.getDmlMessage(0),
          'Accounting 第10.2節: 参照済みなら削除せず無効化する'
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        1,
        [SELECT COUNT() FROM GlManualJournalSetting__c WHERE Id = :setting.Id]
      );
    }
  }

  @IsTest
  static void irregularCreate_on104DirectInsert() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertInvoice(true);
      GlManualJournalHeader__c header = new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = insertActiveSetting().Id,
        PostingDate__c = Date.today(),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        insert header;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'IrregularCreate'
            AND TargetObject__c = 'GlManualJournalHeader__c'
            AND TargetRecordId__c = :String.valueOf(header.Id)
        ],
        '共通基盤第12章・第3.6節: 104の手動仕訳ヘッダー新規作成はIrregularCreateを1件書く'
      );
    }
  }

  @IsTest
  static void irregularUpdate_on104DirectUpdate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertInvoice(true);
      GlManualJournalHeader__c header = new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = insertActiveSetting().Id,
        PostingDate__c = Date.today(),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      insert header;
      header.Amount__c = 200;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        update header;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'IrregularUpdate'
            AND TargetObject__c = 'GlManualJournalHeader__c'
            AND TargetRecordId__c = :String.valueOf(header.Id)
        ],
        '共通基盤第12章・第3.6節: 104の手動仕訳ヘッダー項目更新はIrregularUpdateを1件書く'
      );
    }
  }

  @IsTest
  static void irregularDelete_on104DirectDelete() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertInvoice(true);
      GlManualJournalHeader__c header = new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = insertActiveSetting().Id,
        PostingDate__c = Date.today(),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      insert header;
      Id headerId = header.Id;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        delete header;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'IrregularDelete'
            AND TargetObject__c = 'GlManualJournalHeader__c'
            AND TargetRecordId__c = :String.valueOf(headerId)
        ],
        '共通基盤第12章・第3.6節: 104の手動仕訳ヘッダー削除はIrregularDeleteを1件書く'
      );
    }
  }

  @IsTest
  static void regularRegisterPath_doesNotWriteIrregularCreate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertInvoice(true);
      GlManualJournalHeader__c header = new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = insertActiveSetting().Id,
        PostingDate__c = Date.today(),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      Boolean previousWrite = ManualJournalService.allowLifecycleWrite;
      ManualJournalService.allowLifecycleWrite = true;
      try {
        ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
          ContractPermissionUtil.MIGRATE_ALL => true
        };
        try {
          insert header;
        } finally {
          ContractPermissionUtil.testOverrides = null;
        }
      } finally {
        ManualJournalService.allowLifecycleWrite = previousWrite;
      }
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'IrregularCreate'
            AND TargetObject__c = 'GlManualJournalHeader__c'
        ],
        '共通基盤第12章: 正規の手動仕訳登録はIrregularCreateを書かない'
      );
    }
  }

  @IsTest
  static void delete_allowsUnreferencedSetting() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlManualJournalSetting__c setting = insertActiveSetting();
      delete setting;
      System.assertEquals(
        0,
        [SELECT COUNT() FROM GlManualJournalSetting__c WHERE Id = :setting.Id],
        'Accounting 第10.2節: 未参照なら削除できる'
      );
    }
  }

  private static GlAccount__c insertAccount(
    String name,
    String accountType,
    Boolean active
  ) {
    GlAccount__c account = new GlAccount__c(
      Name = name,
      AccountType__c = accountType,
      IsActive__c = active
    );
    insert account;
    return account;
  }

  private static GlManualJournalSetting__c validSetting(
    Id debitAccountId,
    Id creditAccountId,
    String settingKey
  ) {
    return new GlManualJournalSetting__c(
      Name = '検証用設定',
      SettingKey__c = settingKey,
      DebitSlotKey__c = 'FxLoss',
      DebitAccount__c = debitAccountId,
      CreditSlotKey__c = 'AccountsReceivable',
      CreditAccount__c = creditAccountId,
      Description__c = '検証',
      IsActive__c = true
    );
  }

  private static void assertSettingRejected(
    String debitSlot,
    Id debitAccountId,
    String creditSlot,
    Id creditAccountId,
    String expectedMessage,
    String specNote
  ) {
    GlManualJournalSetting__c setting = new GlManualJournalSetting__c(
      Name = '検証用設定',
      DebitSlotKey__c = debitSlot,
      DebitAccount__c = debitAccountId,
      CreditSlotKey__c = creditSlot,
      CreditAccount__c = creditAccountId,
      Description__c = '検証',
      IsActive__c = true
    );
    Boolean thrown = false;
    try {
      insert setting;
    } catch (DmlException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains(expectedMessage),
        specNote + ' 実際: ' + ex.getMessage()
      );
    }
    System.assertEquals(true, thrown, specNote);
  }

  private static GlManualJournalSetting__c insertActiveSetting() {
    GlAccount__c debit = new GlAccount__c(
      Name = 'MJSvc Debit',
      AccountType__c = 'Expense',
      IsActive__c = true
    );
    GlAccount__c credit = new GlAccount__c(
      Name = 'MJSvc Credit',
      AccountType__c = 'Asset',
      IsActive__c = true
    );
    insert new List<GlAccount__c>{ debit, credit };
    GlManualJournalSetting__c setting = new GlManualJournalSetting__c(
      Name = '為替差損の計上',
      DebitSlotKey__c = 'FxLoss',
      DebitAccount__c = debit.Id,
      CreditSlotKey__c = 'AccountsReceivable',
      CreditAccount__c = credit.Id,
      Description__c = '入金不足が為替変動による場合',
      IsActive__c = true
    );
    insert setting;
    return setting;
  }
}
