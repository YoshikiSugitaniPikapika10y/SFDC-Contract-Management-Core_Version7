@IsTest
private class InvoicePreviewOpsControllerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void getOpsBundle_returnsSignedLineRemainingInclusive() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      fixture.line.AllocatedTaxAmount__c = 100;
      update fixture.line;

      Test.startTest();
      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id
      );
      Test.stopTest();

      System.assertEquals(
        1,
        bundle.paymentLines.size(),
        'Core 第8.6節: 請求明細の処理可能残額を返す'
      );
      System.assertEquals(1100, bundle.paymentLines[0].remainingInclusive);
      System.assertEquals(true, bundle.paymentAllowed);
    }
  }

  @IsTest
  static void getOpsBundle_hasLockedJournals_countsActiveLockedOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      insertJournal(
        fixture.invoice.Id,
        true,
        'Cancelled',
        'LOCKCAN'
      );

      Test.startTest();
      InvoicePreviewOpsController.OpsBundleDto cancelledOnly = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id
      );
      System.assertEquals(
        false,
        cancelledOnly.hasLockedJournals,
        'Core 第7.9.6節: 取消済のLock行では取消基準日を求めない'
      );

      insertJournal(fixture.invoice.Id, true, 'Active', 'LOCKACT');
      InvoicePreviewOpsController.OpsBundleDto withActive = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id
      );
      System.assertEquals(
        true,
        withActive.hasLockedJournals,
        'Core 第7.9.6節: 有効かつLock済みの仕訳があるとき取消基準日を求める'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void getOpsBundle_manualJournalLockUsesLoadedJournals() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      GlAccount__c debit = new GlAccount__c(
        Name = 'MJ Bundle Debit',
        AccountType__c = 'Expense',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'MJ Bundle Credit',
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
        IsActive__c = true
      );
      insert setting;
      GlManualJournalHeader__c header = new GlManualJournalHeader__c(
        Invoice__c = fixture.invoice.Id,
        GlManualJournalSetting__c = setting.Id,
        PostingDate__c = Date.today(),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      insert header;
      Boolean previous = GlJournalTriggerHandler.allowEngineWrite;
      GlJournalTriggerHandler.allowEngineWrite = true;
      try {
        insert new GlJournal__c(
          Invoice__c = fixture.invoice.Id,
          GlManualJournalHeader__c = header.Id,
          GlManualJournalSetting__c = setting.Id,
          Amount__c = 100,
          IdempotencyKey__c = AccountingDiffService.hashKey(
            new List<String>{ 'MJBUNDLE', String.valueOf(header.Id) }
          ),
          DebitSlotKey__c = 'FxLoss',
          CreditSlotKey__c = 'AccountsReceivable',
          DebitAccount__c = debit.Id,
          CreditAccount__c = credit.Id,
          PostingDate__c = Date.today(),
          TransactionStatus__c = 'Active',
          IsLocked__c = true
        );
      } finally {
        GlJournalTriggerHandler.allowEngineWrite = previous;
      }
      InvoicePreviewOpsController.manualJournalLockSelectCount = 0;
      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id
      );
      System.assertEquals(
        0,
        InvoicePreviewOpsController.manualJournalLockSelectCount,
        'Core 第12.4節: 読み済み仕訳のLockをCOUNTで取り直さない'
      );
      System.assertEquals(1, bundle.manualJournals.size());
      System.assertEquals(
        true,
        bundle.manualJournals[0].hasLockedJournals,
        'Accounting 第8.5節: このヘッダーのActive Lockで取消基準日要否を出す'
      );
    }
  }

  @IsTest
  static void getOpsBundle_slotNetsAndAbbreviationDisplay() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      insertJournal(fixture.invoice.Id, false, 'Active', 'SLOTNET');
      Test.startTest();
      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id
      );
      Test.stopTest();
      System.assertEquals(
        1,
        bundle.journals.size(),
        'Core 第7.7.3節: 仕訳タブは仕訳を返す'
      );
      System.assertEquals(
        'CASH SLOTNET Debit',
        bundle.journals[0].debitAccountName,
        'Accounting 第4.3節: 借方は略称と科目'
      );
      System.assertEquals(
        'UAC SLOTNET Credit',
        bundle.journals[0].creditAccountName,
        'Accounting 第4.3節: 貸方は略称と科目'
      );
      System.assertEquals(2, bundle.slotNets.size(), 'Core 第8.10節: 0円スロットは出さない');
      System.assertEquals('CASH', bundle.slotNets[0].abbreviation);
      System.assertEquals(1, bundle.slotNets[0].amount);
      System.assertEquals('UAC', bundle.slotNets[1].abbreviation);
      System.assertEquals(1, bundle.slotNets[1].amount);
    }
  }

  @IsTest
  static void getOpsBundle_journalListNameIsPatternAliasOrSettingName() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      GlAccount__c autoDebit = new GlAccount__c(
        Name = 'AUTO Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c autoCredit = new GlAccount__c(
        Name = 'AUTO Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      GlAccount__c debit = new GlAccount__c(
        Name = 'MANUAL Debit',
        AccountType__c = 'Expense',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'MANUAL Credit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ autoDebit, autoCredit, debit, credit };
      insert new GlJournal__c(
        Invoice__c = fixture.invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'PATTRN', String.valueOf(fixture.invoice.Id) }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = autoDebit.Id,
        CreditAccount__c = autoCredit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active',
        IsLocked__c = false,
        AccountingEventKey__c = AccountingEventFixedCatalog.BILLING_CONFIRMED.key,
        JournalPatternKey__c = JournalPatternFixedCatalog.BILLING_BASIS_INVOICE_BODY.key
      );
      GlManualJournalSetting__c setting = new GlManualJournalSetting__c(
        Name = '為替差損の計上',
        DebitSlotKey__c = 'FxLoss',
        DebitAccount__c = debit.Id,
        CreditSlotKey__c = 'AccountsReceivable',
        CreditAccount__c = credit.Id,
        IsActive__c = true
      );
      insert setting;
      insert new GlJournal__c(
        Invoice__c = fixture.invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'MANUALROW', String.valueOf(fixture.invoice.Id) }
        ),
        DebitSlotKey__c = 'FxLoss',
        CreditSlotKey__c = 'AccountsReceivable',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 2),
        TransactionStatus__c = 'Active',
        IsLocked__c = false,
        AccountingEventKey__c = AccountingEventFixedCatalog.MANUAL_JOURNAL.key,
        GlManualJournalSetting__c = setting.Id
      );
      Test.startTest();
      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id
      );
      Test.stopTest();
      System.assertEquals(2, bundle.journals.size());
      System.assertEquals(
        '請求本体',
        bundle.journals[0].eventName,
        'Accounting 第5.2節: 自動仕訳の列はパターン別名'
      );
      System.assertEquals(
        AccountingEventFixedCatalog.BILLING_CONFIRMED.key,
        bundle.journals[0].eventKey,
        'Accounting 第5.2節: 保存の起動点キーは変えない'
      );
      System.assertEquals(
        '為替差損の計上',
        bundle.journals[1].eventName,
        'Accounting 第5.2節: 手動は設定Name'
      );
    }
  }

  @IsTest
  static void getOpsBundle_manualSettings_useNameAsLabelAndKeepDescription() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      GlAccount__c debit = new GlAccount__c(
        Name = 'MS Name Debit',
        AccountType__c = 'Expense',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'MS Name Credit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      insert new GlManualJournalSetting__c(
        Name = '為替差損の計上',
        DebitSlotKey__c = 'FxLoss',
        DebitAccount__c = debit.Id,
        CreditSlotKey__c = 'AccountsReceivable',
        CreditAccount__c = credit.Id,
        Description__c = '入金不足が為替変動による場合',
        IsActive__c = true
      );

      Test.startTest();
      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id
      );
      System.assertEquals(1, bundle.manualSettings.size());
      System.assertEquals(
        '為替差損の計上',
        bundle.manualSettings[0].label,
        'Accounting 第10.2節: Name をメニュー表示名にする'
      );
      System.assertEquals(
        '入金不足が為替変動による場合',
        bundle.manualSettings[0].description,
        'Accounting 第10.2節: Description は選択すべき事象'
      );
      System.assertEquals(
        'FXL MS Name Debit',
        bundle.manualSettings[0].debitAccountName,
        'Accounting 第10.3節: 借方は略称＋科目名'
      );
      System.assertEquals(
        'AR MS Name Credit',
        bundle.manualSettings[0].creditAccountName,
        'Accounting 第10.3節: 貸方は略称＋科目名'
      );
      Test.stopTest();
    }
  }

  private static void insertJournal(
    Id invoiceId,
    Boolean locked,
    String transactionStatus,
    String keySuffix
  ) {
    GlAccount__c debit = new GlAccount__c(
      Name = keySuffix + ' Debit',
      AccountType__c = 'Asset',
      IsActive__c = true
    );
    GlAccount__c credit = new GlAccount__c(
      Name = keySuffix + ' Credit',
      AccountType__c = 'Liability',
      IsActive__c = true
    );
    insert new List<GlAccount__c>{ debit, credit };
    insert new GlJournal__c(
      Invoice__c = invoiceId,
      Amount__c = 1,
      IdempotencyKey__c = AccountingDiffService.hashKey(
        new List<String>{ keySuffix, String.valueOf(invoiceId) }
      ),
      DebitSlotKey__c = 'Cash',
      CreditSlotKey__c = 'UnappliedCash',
      DebitAccount__c = debit.Id,
      CreditAccount__c = credit.Id,
      PostingDate__c = Date.newInstance(2026, 6, 1),
      TransactionStatus__c = transactionStatus,
      IsLocked__c = locked
    );
  }

  @IsTest
  static void savePaymentFromPreview_keepsClientAllocations() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createTwoLineInvoice();
      InvoicePreviewOpsController.AllocationInputDto first = new InvoicePreviewOpsController.AllocationInputDto();
      first.invoiceLineId = fixture.line.Id;
      first.amount = 409;
      InvoicePreviewOpsController.AllocationInputDto second = new InvoicePreviewOpsController.AllocationInputDto();
      second.invoiceLineId = fixture.secondLine.Id;
      second.amount = 91;
      Invoice__c invoice = [
        SELECT LastModifiedDate
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];

      Test.startTest();
      Id paymentId = InvoicePreviewOpsController.savePaymentFromPreview(
        null,
        fixture.invoice.Id,
        500,
        InvoicePaymentService.PURPOSE_INVOICE,
        Date.today(),
        null,
        ContractOptimisticLockUtil.toToken(invoice.LastModifiedDate),
        new List<InvoicePreviewOpsController.AllocationInputDto>{ first, second },
        null
      );
      Test.stopTest();

      Map<Id, Decimal> byLine = new Map<Id, Decimal>();
      for (InvoicePaymentAllocation__c row : [
        SELECT InvoiceLine__c, Amount__c
        FROM InvoicePaymentAllocation__c
        WHERE InvoicePayment__c = :paymentId
      ]) {
        byLine.put(row.InvoiceLine__c, row.Amount__c);
      }
      System.assertEquals(
        409,
        byLine.get(fixture.line.Id),
        'Core 第8.9節: 画面の割当を保存し、proposeLinesで上書きしない'
      );
      System.assertEquals(91, byLine.get(fixture.secondLine.Id));
    }
  }

  @IsTest
  static void savePaymentFromPreview_nullAllocationsRejectedForInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      Invoice__c invoice = [
        SELECT LastModifiedDate
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      Boolean thrown = false;
      Test.startTest();
      try {
        InvoicePreviewOpsController.savePaymentFromPreview(
          null,
          fixture.invoice.Id,
          100,
          InvoicePaymentService.PURPOSE_INVOICE,
          Date.today(),
          null,
          ContractOptimisticLockUtil.toToken(invoice.LastModifiedDate),
          null,
          null
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '明細別割当の請求明細と金額は必須です。',
          ex.getMessage(),
          'Core 第8.6節・第8.9節: 画面の割当が空なら proposeLines で埋めない'
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void cancelPaymentFromPreview_allowsBlankCancelDateWithoutLockedJournals() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      fixture.line.AllocatedTaxAmount__c = 100;
      update fixture.line;
      InvoicePaymentService.RegisterRequest request = new InvoicePaymentService.RegisterRequest();
      request.invoiceId = fixture.invoice.Id;
      request.amount = 1100;
      request.purpose = InvoicePaymentService.PURPOSE_INVOICE;
      request.paymentDate = Date.today();
      InvoicePaymentAllocationService.AllocationLine allocation = new InvoicePaymentAllocationService.AllocationLine();
      allocation.invoiceLineId = fixture.line.Id;
      allocation.amount = 1100;
      request.allocations = new List<InvoicePaymentAllocationService.AllocationLine>{
        allocation
      };
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      Test.startTest();
      Id paymentId = InvoicePaymentService.register(request);
      Id reversalId = InvoicePreviewOpsController.cancelPaymentFromPreview(
        paymentId,
        fixture.invoice.Id,
        null,
        'Duplicate',
        null,
        AccountingCauseLockService.resolveInvoiceOperationToken(
          fixture.invoice.Id
        )
      );

      System.assertNotEquals(null, reversalId);
      InvoicePayment__c original = [
        SELECT PaymentTransactionStatus__c
        FROM InvoicePayment__c
        WHERE Id = :paymentId
      ];
      System.assertEquals(
        InvoicePaymentService.STATUS_CANCELLED,
        original.PaymentTransactionStatus__c,
        'Core 第8.5節: 未ロックなら取消基準日なしで取消できる'
      );

      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id
      );
      Map<String, Integer> statusCounts = new Map<String, Integer>();
      for (InvoicePreviewOpsController.PaymentRowDto row : bundle.payments) {
        String status = row.paymentTransactionStatus;
        Integer n = statusCounts.containsKey(status)
          ? statusCounts.get(status)
          : 0;
        statusCounts.put(status, n + 1);
      }
      System.assertEquals(
        1,
        statusCounts.get(InvoicePaymentService.STATUS_CANCELLED),
        'Core 第8.4節: 取消済みの元取引を返す。表示の既定非表示は画面'
      );
      System.assertEquals(
        1,
        statusCounts.get(InvoicePaymentService.STATUS_REVERSAL),
        'Core 第8.4節: 取消レコードを返す。表示の既定非表示は画面'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'CancelPayment'
            AND TargetRecordId__c = :String.valueOf(paymentId)
        ],
        '共通基盤第12章: CancelPaymentは成功した1回'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void getOpsBundle_doesNotReturnDedicatedDocumentList() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);

      Test.startTest();
      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id
      );
      Test.stopTest();

      System.assertNotEquals(null, bundle.journals, 'Core 第7.7.3節: 仕訳タブは仕訳を返す');
    }
  }

  @IsTest
  static void getOpsBundle_nullInvoice_throwsJapanese() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        InvoicePreviewOpsController.getOpsBundle(null);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '請求が指定されていません。',
          ex.getMessage(),
          'Core 第0章: 人が見る文字は日本語'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void getOpsBundle_scoped_reusesInvoiceWithoutCount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      Invoice__c loaded = [
        SELECT
          Id,
          ContractHistory__c,
          ContractService__c,
          InvoiceTransactionStatus__c,
          Amount__c,
          TaxAmount__c,
          TaxInclusiveAmount__c,
          PaymentInclusiveTotal__c,
          InvoicePaymentNet__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];

      Test.startTest();
      InvoicePreviewOpsController.getOpsBundle(loaded.Id);
      Integer beforeScoped = Limits.getQueries();
      InvoicePreviewOpsController.OpsBundleDto scoped = InvoicePreviewOpsController.getOpsBundle(
        loaded.Id,
        loaded.ContractHistory__c
      );
      Integer usedScoped = Limits.getQueries() - beforeScoped;
      Integer beforeIdOnly = Limits.getQueries();
      InvoicePreviewOpsController.OpsBundleDto idOnly = InvoicePreviewOpsController.getOpsBundle(
        loaded.Id
      );
      Integer usedIdOnly = Limits.getQueries() - beforeIdOnly;
      Test.stopTest();

      System.assertEquals(
        usedIdOnly + 1,
        usedScoped,
        'Core 第12.4節・第4.3.11節: 範囲は履歴1回だけで、請求COUNTを重ねない'
      );
      System.assertEquals(loaded.Id, scoped.invoiceId);
      System.assertEquals(
        idOnly.taxInclusiveAmount,
        scoped.taxInclusiveAmount,
        'Core 第7.7.3節: 範囲付き取得のバンドルは変えない'
      );
      System.assertEquals(idOnly.paymentAllowed, scoped.paymentAllowed);
      System.assertEquals(idOnly.invoicePaymentNet, scoped.invoicePaymentNet);
      System.assertEquals(
        InvoiceTransactionStatusService.resolveTaxInclusive(loaded),
        scoped.taxInclusiveAmount,
        '開発ルール第13節: 入口はSOQL行の税込を読む'
      );
    }
  }

  @IsTest
  static void getOpsBundle_reusesLoadedInvoiceLastModifiedForToken() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      Invoice__c loaded = [
        SELECT Id, LastModifiedDate
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      String expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        loaded.Id
      );

      AccountingCauseLockService.invoiceModifiedSelectCount = 0;
      Test.startTest();
      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        loaded.Id
      );
      Test.stopTest();

      System.assertEquals(
        0,
        AccountingCauseLockService.invoiceModifiedSelectCount,
        'Core 第12.4節・第4.3.11節: 本体で読んだ請求を版トークンで取り直さない'
      );
      System.assertEquals(
        expectedToken,
        bundle.invoiceToken,
        'Core 第7.9.7節: invoiceToken は変えない'
      );
      System.assertEquals(
        expectedToken,
        AccountingCauseLockService.resolveInvoiceOperationToken(
          loaded.Id,
          loaded.LastModifiedDate
        ),
        '開発ルール第13節: 入口はSOQL行の LastModified で版トークンを読む'
      );
    }
  }

  @IsTest
  static void getOpsBundle_reusesLoadedInvoiceForTagResults() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(false);
      fixture.invoice.IsManuallyAdjusted__c = true;
      fixture.invoice.IsAmountAdjusted__c = false;
      update fixture.invoice;
      insert new List<GlAccountingTagRule__c>{
        new GlAccountingTagRule__c(
          Name = 'BUG806 True',
          TagKey__c = 'bug806_t_' + String.valueOf(Crypto.getRandomInteger()),
          TagLabel__c = 'BUG806残あり',
          Expression__c = 'AR',
          ComparisonOperator__c = 'NE',
          ComparisonValue__c = 0,
          TargetFieldApiName__c = 'IsManuallyAdjusted__c',
          IsEnabled__c = true
        ),
        new GlAccountingTagRule__c(
          Name = 'BUG806 False',
          TagKey__c = 'bug806_f_' + String.valueOf(Crypto.getRandomInteger()),
          TagLabel__c = 'BUG806端数',
          Expression__c = 'AR',
          ComparisonOperator__c = 'EQ',
          ComparisonValue__c = 0,
          TargetFieldApiName__c = 'IsAmountAdjusted__c',
          IsEnabled__c = true
        )
      };
      Invoice__c loaded = [
        SELECT Id, IsManuallyAdjusted__c, IsAmountAdjusted__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];

      InvoicePreviewOpsController.tagInvoiceSelectCount = 0;
      Test.startTest();
      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        loaded.Id
      );
      Test.stopTest();

      System.assertEquals(
        0,
        InvoicePreviewOpsController.tagInvoiceSelectCount,
        'Core 第12.4節・第4.3.11節: 本体で読んだ請求をタグ結果で取り直さない'
      );
      Boolean foundTrue = false;
      if (bundle.tagResults != null) {
        for (InvoicePreviewOpsController.TagResultRowDto row : bundle.tagResults) {
          if (row.name == 'BUG806残あり') {
            foundTrue = true;
            System.assertEquals(true, row.value, 'Accounting 第7.6節: Trueのタグ行は変えない');
          }
          System.assertNotEquals(
            'BUG806端数',
            row.name,
            'Accounting 第7.6節: Falseは出さない'
          );
        }
      }
      System.assertEquals(
        true,
        foundTrue,
        'Accounting 第7.6節・Core 第7.7.3節: Trueのタグラベルを返す'
      );
      System.assertEquals(
        true,
        loaded.IsManuallyAdjusted__c,
        '開発ルール第13節: 入口はSOQL行のタグ保存先を読む'
      );
      System.assertEquals(
        loaded.IsManuallyAdjusted__c == true,
        foundTrue,
        '開発ルール第13節: タグ行は本体SOQL行の保存先と一致する'
      );
    }
  }

  @IsTest
  static void getOpsBundle_unconfirmed_blocksPaymentJapanese() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(false);
      Test.startTest();
      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id,
        fixture.invoice.ContractHistory__c
      );
      Test.stopTest();
      System.assertEquals(false, bundle.paymentAllowed);
      System.assertEquals(
        '請求を確定してから入金できます。',
        bundle.paymentBlockedReason,
        'Core 第7.7.3節: 未確定の請求に入出金は登録できない'
      );
      System.assertEquals(
        false,
        bundle.hasUnlockedJournals,
        'Core 第7.9.6節: 仕訳が無いときUnlock行は無い'
      );
    }
  }

  @IsTest
  static void getOpsBundle_cancelled_blocksPaymentJapanese() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      InvoiceTransactionStatusService.allowStatusWrite = true;
      InvoiceLockUtil.allowLockedStatusWrite = true;
      try {
        InvoiceTransactionStatusService.applyCancelled(
          new List<Invoice__c>{ fixture.invoice }
        );
        update fixture.invoice;
      } finally {
        InvoiceTransactionStatusService.allowStatusWrite = false;
        InvoiceLockUtil.allowLockedStatusWrite = false;
      }
      insertJournal(fixture.invoice.Id, false, 'Active', 'UNLCK1');
      Test.startTest();
      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id
      );
      Test.stopTest();
      System.assertEquals(false, bundle.paymentAllowed);
      System.assertEquals(
        '取消済みの請求に入出金は登録できません。',
        bundle.paymentBlockedReason,
        'Core 第7.7.3節: 取消済みは入出金できない'
      );
      System.assertEquals(
        true,
        bundle.hasUnlockedJournals,
        'Core 第7.9.6節: 未Lock仕訳がある'
      );
    }
  }

  @IsTest
  static void issueInvoiceOperationKey_returnsDistinctKeys() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Test.startTest();
      String first = InvoicePreviewOpsController.issueInvoiceOperationKey();
      String second = InvoicePreviewOpsController.issueInvoiceOperationKey();
      Test.stopTest();
      System.assertEquals(false, String.isBlank(first));
      System.assertEquals(false, String.isBlank(second));
      System.assertNotEquals(
        first,
        second,
        'Core 第4.3.12節・第7.9.7節: 実行のたびに別の操作キーを発行する'
      );
    }
  }

  @IsTest
  static void previewRegisterFromPreview_requiresAmountAndDateJapanese() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      Boolean thrown = false;
      Test.startTest();
      try {
        InvoicePreviewOpsController.previewRegisterFromPreview(
          fixture.invoice.Id,
          0,
          InvoicePaymentService.PURPOSE_INVOICE,
          null,
          null,
          'token',
          null,
          null
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '請求、0以外の金額、入出金日を入力してください。',
          ex.getMessage(),
          'Core 第8.9節: 請求・0以外の金額・入出金日が無ければ登録プレビューしない'
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void previewCancelPaymentFromPreview_requiresPaymentJapanese() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      Test.startTest();
      try {
        InvoicePreviewOpsController.previewCancelPaymentFromPreview(
          null,
          null,
          Date.today()
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '取消する入出金が指定されていません。',
          ex.getMessage(),
          'Core 第8.9節: 入出金未指定の取消プレビューは拒否する'
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void lockJournals_accountingOff_throwsJapanese() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      insertJournal(fixture.invoice.Id, false, 'Active', 'LOCKOFF');
      GlJournal__c journal = [
        SELECT Id
        FROM GlJournal__c
        WHERE Invoice__c = :fixture.invoice.Id
        LIMIT 1
      ];
      Boolean thrown = false;
      Test.startTest();
      try {
        InvoicePreviewOpsController.lockJournalsForInvoice(
          fixture.invoice.Id,
          new List<Id>{ journal.Id }
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          'AccountingがOFFのときはLock/Unlockできません。',
          ex.getMessage(),
          'Accounting 第9.5節: Accounting OFF では Lock しない'
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void lockJournalsForInvoice_reusesCancelCheckedInvoiceForRowLock() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      InvoiceFixture fixture = createInvoice(true);
      insertJournal(fixture.invoice.Id, false, 'Active', 'LOCKREUSE');
      Invoice__c invoice = [
        SELECT Id, InvoiceTransactionStatus__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      GlJournal__c journal = [
        SELECT Id
        FROM GlJournal__c
        WHERE Invoice__c = :invoice.Id
        LIMIT 1
      ];
      String token = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      Test.startTest();
      Integer lockedCount = InvoicePreviewOpsController.lockJournalsForInvoice(
        invoice.Id,
        new List<Id>{ journal.Id },
        token,
        InvoicePreviewOpsController.issueInvoiceOperationKey()
      );
      Test.stopTest();
      System.assertEquals(1, lockedCount, 'Accounting 第9.5節: 選んだ有効仕訳をLockする');
      System.assertEquals(
        1,
        AccountingCauseLockService.invoiceLockSelectCount,
        'Core 第12.4節・第7.9.7節: 取消確認のあと行ロックで同じ請求を取り直さない'
      );
      System.assertEquals(
        true,
        [
          SELECT IsLocked__c
          FROM GlJournal__c
          WHERE Id = :journal.Id
        ]
          .IsLocked__c,
        'Accounting 第9.5節: Lock状態は変えない'
      );
    }
  }

  @IsTest
  static void unlockJournalsForInvoice_reusesCancelCheckedInvoiceForRowLock() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      InvoiceFixture fixture = createInvoice(true);
      insertJournal(fixture.invoice.Id, true, 'Active', 'UNLOCKREUSE');
      Invoice__c invoice = [
        SELECT Id, InvoiceTransactionStatus__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      GlJournal__c journal = [
        SELECT Id
        FROM GlJournal__c
        WHERE Invoice__c = :invoice.Id
        LIMIT 1
      ];
      String token = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      Test.startTest();
      Integer unlockedCount = InvoicePreviewOpsController.unlockJournalsForInvoice(
        invoice.Id,
        new List<Id>{ journal.Id },
        '監査',
        token,
        InvoicePreviewOpsController.issueInvoiceOperationKey()
      );
      Test.stopTest();
      System.assertEquals(
        1,
        unlockedCount,
        'Accounting 第9.5節: 選んだ行をUnlockする'
      );
      System.assertEquals(
        1,
        AccountingCauseLockService.invoiceLockSelectCount,
        'Core 第12.4節・第7.9.7節: 取消確認のあと行ロックで同じ請求を取り直さない'
      );
      System.assertEquals(
        false,
        [
          SELECT IsLocked__c
          FROM GlJournal__c
          WHERE Id = :journal.Id
        ]
          .IsLocked__c,
        'Accounting 第9.5節: Unlock後は未Lock'
      );
    }
  }

  @IsTest
  static void lockJournalsForInvoice_reusesCopyDefinitionCatalog() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      InvoiceFixture fixture = createInvoice(true);
      insertJournal(fixture.invoice.Id, false, 'Active', 'LOCKCOPY');
      Invoice__c invoice = [
        SELECT Id, InvoiceTransactionStatus__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      GlJournal__c journal = [
        SELECT Id
        FROM GlJournal__c
        WHERE Invoice__c = :invoice.Id
        LIMIT 1
      ];
      String token = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Test.startTest();
      InvoiceProductFieldCopyService.resetCache();
      InvoiceProductFieldCopyService.catalogSelectCount = 0;
      FieldCopyDefinitionService.resetCache();
      Integer lockedCount = InvoicePreviewOpsController.lockJournalsForInvoice(
        invoice.Id,
        new List<Id>{ journal.Id },
        token,
        InvoicePreviewOpsController.issueInvoiceOperationKey()
      );
      Test.stopTest();
      System.assertEquals(1, lockedCount, 'Accounting 第9.5節: 選んだ有効仕訳をLockする');
      System.assertEquals(
        0,
        InvoiceProductFieldCopyService.catalogSelectCount,
        'Core 第12.4節・第11.4.2節: コピー定義を2カタログで取り直さない'
      );
      System.assertEquals(
        true,
        [
          SELECT IsLocked__c
          FROM GlJournal__c
          WHERE Id = :journal.Id
        ]
          .IsLocked__c,
        'Accounting 第9.5節: Lock状態は変えない'
      );
    }
  }

  @IsTest
  static void unlockJournalsForInvoice_reusesCopyDefinitionCatalog() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      InvoiceFixture fixture = createInvoice(true);
      insertJournal(fixture.invoice.Id, true, 'Active', 'UNLOCKCOPY');
      Invoice__c invoice = [
        SELECT Id, InvoiceTransactionStatus__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      GlJournal__c journal = [
        SELECT Id
        FROM GlJournal__c
        WHERE Invoice__c = :invoice.Id
        LIMIT 1
      ];
      String token = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Test.startTest();
      InvoiceProductFieldCopyService.resetCache();
      InvoiceProductFieldCopyService.catalogSelectCount = 0;
      FieldCopyDefinitionService.resetCache();
      Integer unlockedCount = InvoicePreviewOpsController.unlockJournalsForInvoice(
        invoice.Id,
        new List<Id>{ journal.Id },
        '監査',
        token,
        InvoicePreviewOpsController.issueInvoiceOperationKey()
      );
      Test.stopTest();
      System.assertEquals(
        1,
        unlockedCount,
        'Accounting 第9.5節: 選んだ行をUnlockする'
      );
      System.assertEquals(
        0,
        InvoiceProductFieldCopyService.catalogSelectCount,
        'Core 第12.4節・第11.4.2節: コピー定義を2カタログで取り直さない'
      );
      System.assertEquals(
        false,
        [
          SELECT IsLocked__c
          FROM GlJournal__c
          WHERE Id = :journal.Id
        ]
          .IsLocked__c,
        'Accounting 第9.5節: Unlock後は未Lock'
      );
    }
  }

  @IsTest
  static void lockJournalsForInvoice_cancelled_rejectsUsingLockedInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      InvoiceFixture fixture = createInvoice(true);
      InvoiceTransactionStatusService.allowStatusWrite = true;
      InvoiceLockUtil.allowLockedStatusWrite = true;
      try {
        InvoiceTransactionStatusService.applyCancelled(
          new List<Invoice__c>{ fixture.invoice }
        );
        update fixture.invoice;
      } finally {
        InvoiceTransactionStatusService.allowStatusWrite = false;
        InvoiceLockUtil.allowLockedStatusWrite = false;
      }
      insertJournal(fixture.invoice.Id, false, 'Active', 'LOCKCANCEL');
      Invoice__c invoice = [
        SELECT Id, InvoiceTransactionStatus__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      GlJournal__c journal = [
        SELECT Id
        FROM GlJournal__c
        WHERE Invoice__c = :invoice.Id
        LIMIT 1
      ];
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      Boolean thrown = false;
      Test.startTest();
      try {
        InvoicePreviewOpsController.lockJournalsForInvoice(
          invoice.Id,
          new List<Id>{ journal.Id },
          AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id),
          InvoicePreviewOpsController.issueInvoiceOperationKey()
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '取消済み請求の仕訳はLock/Unlockできません。',
          ex.getMessage(),
          'Core 第12.2節・第7.7.3節: 取消済み請求の仕訳はLockできない'
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
      System.assertEquals(
        1,
        AccountingCauseLockService.invoiceLockSelectCount,
        'Core 第12.4節・第7.9.7節: 取消確認は行ロックした請求で行い取り直さない'
      );
    }
  }

  @IsTest
  static void lockThenUnlockJournals_withToken_countsSelected() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      InvoiceFixture fixture = createInvoice(true);
      insertJournal(fixture.invoice.Id, false, 'Active', 'LOCKON');
      GlJournal__c journal = [
        SELECT Id
        FROM GlJournal__c
        WHERE Invoice__c = :fixture.invoice.Id
        LIMIT 1
      ];
      String token = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      String key = InvoicePreviewOpsController.issueInvoiceOperationKey();
      Test.startTest();
      Integer lockedCount = InvoicePreviewOpsController.lockJournalsForInvoice(
        fixture.invoice.Id,
        new List<Id>{ journal.Id },
        token,
        key
      );
      System.assertEquals(1, lockedCount, 'Accounting 第9.5節: 選んだ有効仕訳をLockする');
      System.assertEquals(
        true,
        [
          SELECT IsLocked__c
          FROM GlJournal__c
          WHERE Id = :journal.Id
        ]
          .IsLocked__c
      );
      String unlockToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      Integer unlockedCount = InvoicePreviewOpsController.unlockJournalsForInvoice(
        fixture.invoice.Id,
        new List<Id>{ journal.Id },
        '監査',
        unlockToken,
        InvoicePreviewOpsController.issueInvoiceOperationKey()
      );
      Test.stopTest();
      System.assertEquals(
        1,
        unlockedCount,
        'Accounting 第9.5節: Unlockには理由が必要で、選んだ行をUnlockする'
      );
      System.assertEquals(
        false,
        [
          SELECT IsLocked__c
          FROM GlJournal__c
          WHERE Id = :journal.Id
        ]
          .IsLocked__c
      );
    }
  }

  @IsTest
  static void updateJournalMemo_threeArgWritesMemo() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceOpsFieldService.setCachedRowsForTest(
        new List<InvoiceOpsField__mdt>{
          new InvoiceOpsField__mdt(
            DeveloperName = 'JnlMemo3',
            Active__c = true,
            TargetObject__c = 'GlJournal__c',
            FieldApiName__c = 'Memo__c'
          )
        }
      );
      InvoiceFixture fixture = createInvoice(true);
      insertJournal(fixture.invoice.Id, false, 'Active', 'MEMO3');
      GlJournal__c journal = [
        SELECT Id
        FROM GlJournal__c
        WHERE Invoice__c = :fixture.invoice.Id
        LIMIT 1
      ];
      Test.startTest();
      InvoicePreviewOpsController.updateJournalMemo(
        journal.Id,
        '3引数メモ',
        fixture.invoice.Id
      );
      Test.stopTest();
      System.assertEquals(
        '3引数メモ',
        [SELECT Memo__c FROM GlJournal__c WHERE Id = :journal.Id].Memo__c,
        'Accounting 第9.1節: 請求付きの仕訳メモ保存も後から保存した文が残る'
      );
      InvoiceOpsFieldService.resetCache();
    }
  }

  @IsTest
  static void unlockJournals_threeArgAccountingOff_throwsJapanese() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      insertJournal(fixture.invoice.Id, true, 'Active', 'UNLOFF');
      GlJournal__c journal = [
        SELECT Id
        FROM GlJournal__c
        WHERE Invoice__c = :fixture.invoice.Id
        LIMIT 1
      ];
      Boolean thrown = false;
      Test.startTest();
      try {
        InvoicePreviewOpsController.unlockJournalsForInvoice(
          fixture.invoice.Id,
          new List<Id>{ journal.Id },
          '監査'
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          'AccountingがOFFのときはLock/Unlockできません。',
          ex.getMessage(),
          'Accounting 第9.5節: Accounting OFF では Unlock しない'
        );
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void savePaymentFromPreview_rejectsDirectUpdateAndBadPurpose() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      Invoice__c invoice = [
        SELECT LastModifiedDate, ContractHistory__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      String token = ContractOptimisticLockUtil.toToken(invoice.LastModifiedDate);
      Boolean updateThrown = false;
      Test.startTest();
      try {
        InvoicePreviewOpsController.savePaymentFromPreview(
          fixture.line.Id,
          fixture.invoice.Id,
          100,
          InvoicePaymentService.PURPOSE_INVOICE,
          Date.today(),
          null,
          token,
          null,
          null
        );
      } catch (AuraHandledException ex) {
        updateThrown = true;
        System.assertEquals(
          '入金は直接更新できません。取消して再登録してください。',
          ex.getMessage(),
          'Core 第8.4節: 入金の金額変更は取消して再登録'
        );
      }
      Boolean purposeThrown = false;
      try {
        InvoicePreviewOpsController.savePaymentFromPreview(
          null,
          fixture.invoice.Id,
          100,
          'Other',
          Date.today(),
          null,
          token,
          null,
          null,
          'op-purpose'
        );
      } catch (AuraHandledException ex) {
        purposeThrown = true;
        System.assertEquals(
          '入出金目的は請求金額または請求金額以外です。',
          ex.getMessage(),
          'Core 第8.9節: 入出金目的は2択'
        );
      }
      Boolean missingThrown = false;
      try {
        InvoicePreviewOpsController.updatePaymentFromPreview(
          null,
          fixture.invoice.Id,
          'メモ',
          null,
          token,
          'op-edit',
          invoice.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        missingThrown = true;
        System.assertEquals(
          '入出金が指定されていません。',
          ex.getMessage(),
          'Core 第8.4節: 入出金未指定の編集は拒否する'
        );
      }
      Test.stopTest();
      System.assertEquals(true, updateThrown);
      System.assertEquals(true, purposeThrown);
      System.assertEquals(true, missingThrown);
    }
  }

  @IsTest
  static void previewRegisterFromPreview_inScopeReturnsPreview() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      Invoice__c invoice = [
        SELECT LastModifiedDate, ContractHistory__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      Test.startTest();
      AccountingDiffService.CancelPreview preview = InvoicePreviewOpsController.previewRegisterFromPreview(
        fixture.invoice.Id,
        100,
        InvoicePaymentService.PURPOSE_NON_INVOICE,
        Date.today(),
        null,
        ContractOptimisticLockUtil.toToken(invoice.LastModifiedDate),
        null,
        null,
        invoice.ContractHistory__c
      );
      Test.stopTest();
      System.assertNotEquals(
        null,
        preview,
        'Core 第7.9.6節・第8.9節: 範囲内の入金登録プレビューは結果を返す'
      );
      System.assertEquals(
        1,
        AccountingCauseLockService.invoiceLockSelectCount,
        'Core 第7.7.3節・第12.4節: 範囲確認と版比較のあと行ロックで請求を取り直さない'
      );
    }
  }

  @IsTest
  static void savePaymentFromPreview_inScope_locksInvoiceOnce() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      Invoice__c invoice = [
        SELECT LastModifiedDate, ContractHistory__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      Test.startTest();
      Id paymentId = InvoicePreviewOpsController.savePaymentFromPreview(
        null,
        fixture.invoice.Id,
        100,
        InvoicePaymentService.PURPOSE_NON_INVOICE,
        Date.today(),
        null,
        ContractOptimisticLockUtil.toToken(invoice.LastModifiedDate),
        null,
        null,
        null,
        invoice.ContractHistory__c,
        null
      );
      Test.stopTest();
      System.assertNotEquals(null, paymentId);
      System.assertEquals(
        1,
        AccountingCauseLockService.invoiceLockSelectCount,
        'Core 第7.7.3節・第12.4節: 入金登録は範囲確認後に同じ請求を取り直さない'
      );
    }
  }

  @IsTest
  static void cancelPaymentFromPreview_inScope_doesNotReselectPayment() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      Id paymentId = InvoicePaymentService.register(
        invoiceRequest(fixture, 1100)
      );
      Invoice__c invoice = [
        SELECT ContractHistory__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      AccountingCauseLockService.invoiceLockSelectCount = 0;
      InvoicePaymentService.paymentSelectCount = 0;
      Test.startTest();
      Id reversalId = InvoicePreviewOpsController.cancelPaymentFromPreview(
        paymentId,
        fixture.invoice.Id,
        Date.today(),
        'Duplicate',
        null,
        AccountingCauseLockService.resolveInvoiceOperationToken(fixture.invoice.Id),
        null,
        invoice.ContractHistory__c
      );
      Test.stopTest();
      System.assertNotEquals(null, reversalId);
      System.assertEquals(
        1,
        AccountingCauseLockService.invoiceLockSelectCount,
        'Core 第7.7.3節: 入出金取消は範囲確認後に同じ請求を取り直さない'
      );
      System.assertEquals(
        0,
        InvoicePaymentService.paymentSelectCount,
        'Accounting 第8.2節: 入口で読んだ入出金をcancelが取り直さない'
      );
    }
  }

  @IsTest
  static void previewRegisterFromPreview_usesInvoiceOperationTokenWhenJournalIsNewer() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      insertJournal(fixture.invoice.Id, false, 'Active', 'PREVIEWTOK');
      Invoice__c invoice = [
        SELECT LastModifiedDate, ContractHistory__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      String operationToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      Test.startTest();
      AccountingDiffService.CancelPreview preview = InvoicePreviewOpsController.previewRegisterFromPreview(
        fixture.invoice.Id,
        100,
        InvoicePaymentService.PURPOSE_NON_INVOICE,
        Date.today(),
        null,
        operationToken,
        null,
        null,
        invoice.ContractHistory__c
      );
      Test.stopTest();
      System.assertNotEquals(
        null,
        preview,
        'Core 第7.9.7節: 入出金登録プレビューは請求操作の版で通す'
      );
      String invoiceOnlyToken = ContractOptimisticLockUtil.toToken(
        invoice.LastModifiedDate
      );
      if (invoiceOnlyToken != operationToken) {
        Boolean conflicted = false;
        try {
          InvoicePreviewOpsController.previewRegisterFromPreview(
            fixture.invoice.Id,
            100,
            InvoicePaymentService.PURPOSE_NON_INVOICE,
            Date.today(),
            null,
            invoiceOnlyToken,
            null,
            null,
            invoice.ContractHistory__c
          );
        } catch (AuraHandledException ex) {
          conflicted = true;
        }
        System.assertEquals(
          true,
          conflicted,
          'Core 第7.9.7節: 請求書のLastModifiedDateだけは操作集合より古ければ競合'
        );
      }
    }
  }

  @IsTest
  static void previewOps_rejectInvoiceOutsideContractService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture own = createInvoice(true);
      Test.startTest();
      InvoiceFixture other = createInvoice(true);
      Boolean bundleRejected = false;
      try {
        InvoicePreviewOpsController.getOpsBundle(
          other.invoice.Id,
          own.invoice.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        bundleRejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        bundleRejected,
        'Core 第7.7.3節: 契約サービスをまたいで入金バンドルを取れない'
      );

      Boolean saveRejected = false;
      try {
        InvoicePreviewOpsController.savePaymentFromPreview(
          null,
          other.invoice.Id,
          500,
          InvoicePaymentService.PURPOSE_INVOICE,
          Date.today(),
          null,
          'token',
          null,
          null,
          null,
          own.invoice.ContractHistory__c,
          null
        );
      } catch (AuraHandledException ex) {
        saveRejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        saveRejected,
        'Core 第7.7.3節: 契約サービスをまたいで入金登録できない'
      );

      Boolean previewRejected = false;
      try {
        InvoicePreviewOpsController.previewRegisterFromPreview(
          other.invoice.Id,
          500,
          InvoicePaymentService.PURPOSE_INVOICE,
          Date.today(),
          null,
          'token',
          null,
          null,
          own.invoice.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        previewRejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        previewRejected,
        'Core 第7.7.3節: 契約サービスをまたいで入金登録プレビューできない'
      );

      Boolean cancelRejected = false;
      try {
        InvoicePreviewOpsController.cancelPaymentFromPreview(
          other.invoice.Id,
          other.invoice.Id,
          Date.today(),
          'Duplicate',
          null,
          'token',
          null,
          own.invoice.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        cancelRejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        cancelRejected,
        'Core 第7.7.3節: 契約サービスをまたいで入金取消できない'
      );

      Boolean cancelPreviewRejected = false;
      try {
        InvoicePreviewOpsController.previewCancelPaymentFromPreview(
          other.invoice.Id,
          other.invoice.Id,
          Date.today(),
          own.invoice.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        cancelPreviewRejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        cancelPreviewRejected,
        'Core 第7.7.3節: 契約サービスをまたいで入金取消プレビューできない'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void updateJournalMemo_rejectsJournalOutsideInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceOpsFieldService.setCachedRowsForTest(
        new List<InvoiceOpsField__mdt>{
          new InvoiceOpsField__mdt(
            DeveloperName = 'JnlMemo',
            Active__c = true,
            TargetObject__c = 'GlJournal__c',
            FieldApiName__c = 'Memo__c'
          )
        }
      );
      InvoiceFixture own = createInvoice(true);
      Test.startTest();
      InvoiceFixture other = createInvoice(true);
      insertJournal(other.invoice.Id, false, 'Active', 'MEMOOUT');

      GlJournal__c otherJournal = [
        SELECT Id, Memo__c
        FROM GlJournal__c
        WHERE Invoice__c = :other.invoice.Id
        LIMIT 1
      ];

      Boolean rejected = false;
      try {
        InvoicePreviewOpsController.updateJournalMemo(
          otherJournal.Id,
          '他請求の仕訳',
          own.invoice.Id
        );
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assertEquals(
          'この請求以外の仕訳のメモは保存できません。',
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        rejected,
        'Core 第7.7.3節: この請求以外の仕訳のメモは保存できない'
      );
      System.assertEquals(
        null,
        [SELECT Memo__c FROM GlJournal__c WHERE Id = :otherJournal.Id].Memo__c
      );

      insertJournal(own.invoice.Id, false, 'Active', 'MEMOOWN');
      GlJournal__c ownJournal = [
        SELECT Id
        FROM GlJournal__c
        WHERE Invoice__c = :own.invoice.Id
        LIMIT 1
      ];
      InvoicePreviewOpsController.updateJournalMemo(
        ownJournal.Id,
        '当該請求の仕訳',
        own.invoice.Id
      );
      System.assertEquals(
        '当該請求の仕訳',
        [SELECT Memo__c FROM GlJournal__c WHERE Id = :ownJournal.Id].Memo__c
      );
      Test.stopTest();
      InvoiceOpsFieldService.resetCache();
    }
  }

  @IsTest
  static void updateJournalMemo_rejectsCancelledInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      InvoiceTransactionStatusService.allowStatusWrite = true;
      InvoiceLockUtil.allowLockedStatusWrite = true;
      try {
        InvoiceTransactionStatusService.applyCancelled(
          new List<Invoice__c>{ fixture.invoice }
        );
        update fixture.invoice;
      } finally {
        InvoiceTransactionStatusService.allowStatusWrite = false;
        InvoiceLockUtil.allowLockedStatusWrite = false;
      }
      insertJournal(fixture.invoice.Id, false, 'Active', 'MEMOCAN');
      GlJournal__c journal = [
        SELECT Id, Memo__c
        FROM GlJournal__c
        WHERE Invoice__c = :fixture.invoice.Id
        LIMIT 1
      ];

      Test.startTest();
      Boolean rejected = false;
      try {
        InvoicePreviewOpsController.updateJournalMemo(
          journal.Id,
          '取消済みへ書込',
          fixture.invoice.Id
        );
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assertEquals(
          '取消済み請求の仕訳メモは編集できません。',
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        rejected,
        'Core 第12.2節・第7.7.3節: 取消済み請求の仕訳メモは編集できない'
      );
      System.assertEquals(
        null,
        [SELECT Memo__c FROM GlJournal__c WHERE Id = :journal.Id].Memo__c
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void updateJournalMemo_withoutEditPermission_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.EDIT_DRAFT_INVOICE => false
      };
      Boolean thrown = false;
      try {
        InvoicePreviewOpsController.updateJournalMemo(
          UserInfo.getUserId(),
          'x',
          UserInfo.getUserId()
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '未確定請求を直す権限がありません。',
          ex.getMessage(),
          '共通基盤 第3.2節・第10.4節: 仕訳メモ保存は 10'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void lockJournals_requiresLockJournal_notSubstitutedByViewEditConfirmOrUnlock() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractPermissionUtil.testAllowAll = false;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.VIEW_INVOICE => true,
        ContractPermissionUtil.EDIT_DRAFT_INVOICE => true,
        ContractPermissionUtil.CONFIRM_INVOICE => true,
        ContractPermissionUtil.UNLOCK_JOURNAL => true,
        ContractPermissionUtil.MIGRATE_ALL => true,
        ContractPermissionUtil.MIGRATE_ALL => true,
        ContractPermissionUtil.LOCK_JOURNAL => false
      };
      Boolean thrown = false;
      try {
        InvoicePreviewOpsController.lockJournalsForInvoice(
          UserInfo.getUserId(),
          new List<Id>{ UserInfo.getUserId() },
          'token',
          'key'
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '仕訳をLockする権限がありません。',
          ex.getMessage(),
          'Accounting 第9.5節: 閲覧・編集・確定・Unlock・101〜103 では Lock しない'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
        ContractPermissionUtil.testAllowAll = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void unlockJournals_requiresUnlockJournal_notSubstitutedByLock() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractPermissionUtil.testAllowAll = false;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.VIEW_INVOICE => true,
        ContractPermissionUtil.LOCK_JOURNAL => true,
        ContractPermissionUtil.UNLOCK_JOURNAL => false
      };
      Boolean thrown = false;
      try {
        InvoicePreviewOpsController.unlockJournalsForInvoice(
          UserInfo.getUserId(),
          new List<Id>{ UserInfo.getUserId() },
          '監査',
          'token',
          'key'
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '仕訳をUnlockする権限がありません。',
          ex.getMessage(),
          'Accounting 第9.5節: Lock 権限では Unlock を代替しない'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
        ContractPermissionUtil.testAllowAll = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  private class InvoiceFixture {
    Invoice__c invoice;
    InvoiceLine__c line;
    InvoiceLine__c secondLine;
  }

  private static InvoicePaymentService.RegisterRequest invoiceRequest(
    InvoiceFixture fixture,
    Decimal amount
  ) {
    InvoicePaymentAllocationService.AllocationLine allocation = new InvoicePaymentAllocationService.AllocationLine();
    allocation.invoiceLineId = fixture.line.Id;
    allocation.amount = amount;
    InvoicePaymentService.RegisterRequest request = new InvoicePaymentService.RegisterRequest();
    request.invoiceId = fixture.invoice.Id;
    request.amount = amount;
    request.purpose = InvoicePaymentService.PURPOSE_INVOICE;
    request.paymentDate = Date.today();
    request.allocations = new List<InvoicePaymentAllocationService.AllocationLine>{
      allocation
    };
    request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
      fixture.invoice.Id
    );
    return request;
  }

  private static InvoiceFixture createTwoLineInvoice() {
    InvoiceFixture fixture = createInvoice(true);
    fixture.line.Amount__c = 900;
    fixture.line.AllocatedTaxAmount__c = 0;
    update fixture.line;
    InvoiceLine__c second = new InvoiceLine__c(
      Invoice__c = fixture.invoice.Id,
      ProductName__c = 'PaySvc Line B',
      Amount__c = 100,
      AllocatedTaxAmount__c = 100,
      Quantity__c = 1,
      UnitPrice__c = 100
    );
    ContractTestDataFactory.applyRequiredFields(second);
    insert second;
    fixture.secondLine = second;
    return fixture;
  }

  private static InvoiceFixture createInvoice(Boolean confirmed) {
    Account account = ContractTestDataFactory.insertAccount(
      'PayPrev ' + String.valueOf(Crypto.getRandomInteger())
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'payprev@example.com',
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
    ContractService__c service = new ContractService__c(
      Name = 'PayPrev Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    ContractTestDataFactory.applyRequiredFields(service);
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'PayPrev History',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2026, 6, 30),
      EffectiveDate__c = Date.newInstance(2026, 6, 1)
    );
    ContractTestDataFactory.applyRequiredFields(history);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
    insert history;
    Product2 product = ContractTestDataFactory.buildProduct(
      'PayPrev Product ' + String.valueOf(Crypto.getRandomInteger())
    );
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Account__c = account.Id,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2026, 6, 30),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Type__c = 'New',
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
    );
    ContractTestDataFactory.applyRequiredFields(contractProduct);
    contractProduct.Amount__c = 1000;
    insert contractProduct;
    history.historystatus__c = 'Ordered';
    update history;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = 100,
      BillingAccountSnapShot__c = billingAccount.Id
    );
    ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
    if (confirmed) {
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = Date.today();
    }
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    InvoiceLine__c line = new InvoiceLine__c(
      Invoice__c = invoice.Id,
      ProductName__c = 'PayPrev Line',
      Amount__c = 1000,
      AllocatedTaxAmount__c = 100,
      Quantity__c = 1,
      UnitPrice__c = 1000
    );
    ContractTestDataFactory.applyRequiredFields(line);
    insert line;
    InvoiceFixture fixture = new InvoiceFixture();
    fixture.invoice = invoice;
    fixture.line = line;
    return fixture;
  }

  @IsTest
  static void savePaymentFromPreview_writesRegisterExtraOnInsert() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceOpsFieldService.setCachedRowsForTest(
        new List<InvoiceOpsField__mdt>{
          new InvoiceOpsField__mdt(
            DeveloperName = 'PayMemoExtra',
            Active__c = true,
            TargetObject__c = 'InvoicePayment__c',
            FieldApiName__c = 'Memo__c',
            ShowOnInvoicePurpose__c = false,
            ShowOnNonInvoicePurpose__c = true
          )
        }
      );
      InvoiceFixture fixture = createInvoice(true);
      Invoice__c invoice = [
        SELECT LastModifiedDate
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      Id paymentId = InvoicePreviewOpsController.savePaymentFromPreview(
        null,
        fixture.invoice.Id,
        100,
        InvoicePaymentService.PURPOSE_NON_INVOICE,
        Date.today(),
        '登録メモ引数',
        ContractOptimisticLockUtil.toToken(invoice.LastModifiedDate),
        null,
        null,
        'op-pay-extra',
        new Map<String, Object>{ 'Memo__c' => '登録追加項目' }
      );
      System.assertEquals(
        '登録追加項目',
        [SELECT Memo__c FROM InvoicePayment__c WHERE Id = :paymentId].Memo__c,
        'Core 第11.4.4節・第8.9節: 入出金登録フォームの追加項目は insert 時に書く'
      );
      InvoiceOpsFieldService.resetCache();
    }
  }

  @IsTest
  static void updatePaymentFromPreview_memoOkAmountBlocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceOpsFieldService.setCachedRowsForTest(
        new List<InvoiceOpsField__mdt>{
          new InvoiceOpsField__mdt(
            DeveloperName = 'PayMemoEdit',
            Active__c = true,
            TargetObject__c = 'InvoicePayment__c',
            FieldApiName__c = 'Memo__c',
            ShowOnInvoicePurpose__c = false,
            ShowOnNonInvoicePurpose__c = true
          ),
          new InvoiceOpsField__mdt(
            DeveloperName = 'PayAmountEdit',
            Active__c = true,
            TargetObject__c = 'InvoicePayment__c',
            FieldApiName__c = 'Amount__c',
            ShowOnInvoicePurpose__c = false,
            ShowOnNonInvoicePurpose__c = true
          )
        }
      );
      InvoicePaymentLockUtil.testLockExemptFieldApiNames = 'Memo__c,Amount__c';
      InvoiceFixture fixture = createInvoice(true);
      Invoice__c invoice = [
        SELECT LastModifiedDate, ContractHistory__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      Test.startTest();
      Id paymentId = InvoicePreviewOpsController.savePaymentFromPreview(
        null,
        fixture.invoice.Id,
        100,
        InvoicePaymentService.PURPOSE_NON_INVOICE,
        Date.today(),
        '初回',
        ContractOptimisticLockUtil.toToken(invoice.LastModifiedDate),
        null,
        null
      );
      invoice = [
        SELECT LastModifiedDate, ContractHistory__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      InvoicePreviewOpsController.updatePaymentFromPreview(
        paymentId,
        fixture.invoice.Id,
        '登録後メモ',
        new Map<String, Object>{ 'Memo__c' => '登録後メモ' },
        ContractOptimisticLockUtil.toToken(invoice.LastModifiedDate),
        'op-pay-edit',
        invoice.ContractHistory__c
      );
      System.assertEquals(
        '登録後メモ',
        [SELECT Memo__c FROM InvoicePayment__c WHERE Id = :paymentId].Memo__c,
        'Core 第8.4節・第11.4.4節: 登録後はメモを直せる'
      );
      invoice = [
        SELECT LastModifiedDate, ContractHistory__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      Boolean amountBlocked = false;
      try {
        InvoicePreviewOpsController.updatePaymentFromPreview(
          paymentId,
          fixture.invoice.Id,
          '登録後メモ',
          new Map<String, Object>{ 'Amount__c' => 999 },
          ContractOptimisticLockUtil.toToken(invoice.LastModifiedDate),
          'op-pay-amount',
          invoice.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        amountBlocked = true;
        System.assertEquals(
          InvoicePaymentLockUtil.NEVER_EXEMPT_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        amountBlocked,
        'Core 第8.4節・第11.4.4節: 入出金の金額は除外一覧に書いても更新できない'
      );
      System.assertEquals(
        100,
        [SELECT Amount__c FROM InvoicePayment__c WHERE Id = :paymentId]
          .Amount__c
      );
      Test.stopTest();
      InvoicePaymentLockUtil.testLockExemptFieldApiNames = null;
      InvoiceOpsFieldService.resetCache();
    }
  }

  @IsTest
  static void updatePaymentFromPreview_usesInvoiceOperationToken() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceOpsFieldService.setCachedRowsForTest(
        new List<InvoiceOpsField__mdt>{
          new InvoiceOpsField__mdt(
            DeveloperName = 'PayMemoToken',
            Active__c = true,
            TargetObject__c = 'InvoicePayment__c',
            FieldApiName__c = 'Memo__c',
            ShowOnInvoicePurpose__c = false,
            ShowOnNonInvoicePurpose__c = true
          )
        }
      );
      InvoicePaymentLockUtil.testLockExemptFieldApiNames = 'Memo__c';
      InvoiceFixture fixture = createInvoice(true);
      Invoice__c invoice = [
        SELECT LastModifiedDate, ContractHistory__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      Test.startTest();
      Id paymentId = InvoicePreviewOpsController.savePaymentFromPreview(
        null,
        fixture.invoice.Id,
        100,
        InvoicePaymentService.PURPOSE_NON_INVOICE,
        Date.today(),
        '初回',
        ContractOptimisticLockUtil.toToken(invoice.LastModifiedDate),
        null,
        null
      );
      String paymentMaxToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      InvoicePreviewOpsController.updatePaymentFromPreview(
        paymentId,
        fixture.invoice.Id,
        '入出金最大',
        new Map<String, Object>{ 'Memo__c' => '入出金最大' },
        paymentMaxToken,
        'op-pay-token-max',
        invoice.ContractHistory__c
      );
      System.assertEquals(
        '入出金最大',
        [SELECT Memo__c FROM InvoicePayment__c WHERE Id = :paymentId].Memo__c,
        'Core 第7.9.7節: 入出金が最大のとき請求操作の版でメモを保存できる'
      );
      insertJournal(fixture.invoice.Id, false, 'Active', 'PAYEDIT');
      String afterJournalToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      InvoicePreviewOpsController.updatePaymentFromPreview(
        paymentId,
        fixture.invoice.Id,
        '仕訳後',
        new Map<String, Object>{ 'Memo__c' => '仕訳後' },
        afterJournalToken,
        'op-pay-token-journal',
        invoice.ContractHistory__c
      );
      Test.stopTest();
      System.assertEquals(
        '仕訳後',
        [SELECT Memo__c FROM InvoicePayment__c WHERE Id = :paymentId].Memo__c,
        'Core 第7.9.7節: 仕訳が新しくても請求操作の版でメモを保存できる'
      );
      InvoicePaymentLockUtil.testLockExemptFieldApiNames = null;
      InvoiceOpsFieldService.resetCache();
    }
  }

  @IsTest
  static void updateJournalMemo_unlockedExtraWritesLockedExemptOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceOpsFieldService.setCachedRowsForTest(
        new List<InvoiceOpsField__mdt>{
          new InvoiceOpsField__mdt(
            DeveloperName = 'JnlMemo',
            Active__c = true,
            TargetObject__c = 'GlJournal__c',
            FieldApiName__c = 'Memo__c'
          ),
          new InvoiceOpsField__mdt(
            DeveloperName = 'JnlUnlockReason',
            Active__c = true,
            TargetObject__c = 'GlJournal__c',
            FieldApiName__c = 'UnlockReason__c'
          )
        }
      );
      JournalLockService.testLockExemptFieldApiNames = 'Memo__c';
      InvoiceFixture fixture = createInvoice(true);
      insertJournal(fixture.invoice.Id, false, 'Active', 'JEXTRA');
      GlJournal__c unlocked = [
        SELECT Id
        FROM GlJournal__c
        WHERE Invoice__c = :fixture.invoice.Id AND IsLocked__c = FALSE
        LIMIT 1
      ];
      Test.startTest();
      InvoicePreviewOpsController.updateJournalMemo(
        unlocked.Id,
        '未Lockメモ',
        fixture.invoice.Id,
        new Map<String, Object>{ 'UnlockReason__c' => '画面追加' }
      );
      System.assertEquals(
        '画面追加',
        [
          SELECT UnlockReason__c
          FROM GlJournal__c
          WHERE Id = :unlocked.Id
        ]
          .UnlockReason__c,
        'Core 第11.4.4節・Accounting 第9.5節: 未Lockは出している追加項目を直せる'
      );
      insertJournal(fixture.invoice.Id, true, 'Active', 'JLOCKX');
      GlJournal__c locked = [
        SELECT Id, UnlockReason__c
        FROM GlJournal__c
        WHERE Invoice__c = :fixture.invoice.Id AND IsLocked__c = TRUE
        LIMIT 1
      ];
      InvoicePreviewOpsController.updateJournalMemo(
        locked.Id,
        'Lockメモ',
        fixture.invoice.Id,
        new Map<String, Object>{ 'UnlockReason__c' => 'Lock後は書かない' }
      );
      System.assertEquals(
        null,
        [
          SELECT UnlockReason__c
          FROM GlJournal__c
          WHERE Id = :locked.Id
        ]
          .UnlockReason__c,
        'Core 第11.4.4節・Accounting 第9.5節: Lock後は仕訳ロック除外に無い追加項目を書かない'
      );
      Test.stopTest();
      JournalLockService.testLockExemptFieldApiNames = null;
      InvoiceOpsFieldService.resetCache();
    }
  }
}
