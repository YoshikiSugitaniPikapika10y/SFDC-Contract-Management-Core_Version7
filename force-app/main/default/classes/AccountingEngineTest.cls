@IsTest
private class AccountingEngineTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void deriveAllowedPatternKeys_fourPolicySets() {
    GlAccountingPolicy__c billingAtInvoice = GlAccountingPolicyService.newOrgDefault();
    billingAtInvoice.RevenueRecognitionBasis__c = 'BillingBasis';
    billingAtInvoice.TaxRecognitionTiming__c = 'AtInvoice';
    Set<String> keys = GlAccountingPolicyService.deriveAllowedPatternKeys(billingAtInvoice);
    System.assertEquals(true, keys.contains('BILLING_BASIS_INVOICE_BODY'));
    System.assertEquals(true, keys.contains('BILLING_TAX_AT_INVOICE'));
    System.assertEquals(true, keys.contains('BILLING_BASIS_REVENUE_BODY'));
    System.assertEquals(false, keys.contains('BILLING_BASIS_REVENUE_TAX'));
    System.assertEquals(true, keys.contains('PAYMENT_INVOICE_CURRENT'));

    billingAtInvoice.TaxRecognitionTiming__c = 'AtRecognition';
    keys = GlAccountingPolicyService.deriveAllowedPatternKeys(billingAtInvoice);
    System.assertEquals(true, keys.contains('BILLING_BASIS_INVOICE_TAX_DEFERRED'));
    System.assertEquals(true, keys.contains('BILLING_BASIS_REVENUE_TAX'));

    billingAtInvoice.RevenueRecognitionBasis__c = 'CashBasis';
    billingAtInvoice.TaxRecognitionTiming__c = 'AtInvoice';
    keys = GlAccountingPolicyService.deriveAllowedPatternKeys(billingAtInvoice);
    System.assertEquals(true, keys.contains('CASH_BASIS_INVOICE_BODY_CTA_TRANSFER'));
    System.assertEquals(true, keys.contains('CASH_BASIS_REVENUE_BODY'));

    billingAtInvoice.TaxRecognitionTiming__c = 'AtRecognition';
    keys = GlAccountingPolicyService.deriveAllowedPatternKeys(billingAtInvoice);
    System.assertEquals(true, keys.contains('CASH_BASIS_INVOICE_TAX_CTA_TRANSFER'));
    System.assertEquals(true, keys.contains('CASH_BASIS_REVENUE_TAX'));
  }

  @IsTest
  static void freezeOnFirstConfirm_rejectsLaterChange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      GlAccountingPolicyService.freezeOnFirstConfirm();
      GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
      System.assertNotEquals(null, policy.FrozenAt__c);
      Boolean thrown = false;
      try {
        policy.AccountingEnabled__c = true;
        update policy;
      } catch (DmlException ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void seedOnInstall_runsFromPostInstall() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Test.testInstall(new GlAccountInstallService(), null);
      System.assertEquals(5, [SELECT COUNT() FROM GlManualJournalSetting__c]);
    }
  }

  @IsTest
  static void seedOnInstall_isIdempotent() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountInstallService.seedOnInstall();
      GlAccountInstallService.seedOnInstall();
      System.assertEquals(
        7,
        [
          SELECT COUNT()
          FROM GlAccount__c
          WHERE
            Name IN (
              '売掛金',
              '仮受金',
              '為替差益',
              '為替差損',
              '支払手数料',
              '雑収入',
              '貸倒損失'
            )
        ]
      );
      System.assertEquals(5, [SELECT COUNT() FROM GlManualJournalSetting__c]);
    }
  }

  @IsTest
  static void conditionEvaluation_payInvoiceCurrent() {
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoice = new Invoice__c(InvoiceDate__c = Date.newInstance(2026, 6, 1));
    context.invoicePayment = new InvoicePayment__c(
      PaymentPurpose__c = 'Invoice',
      PaymentDate__c = Date.newInstance(2026, 6, 15)
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.PAY_INVOICE_CURRENT,
        context
      )
    );
    context.invoicePayment.PaymentDate__c = Date.newInstance(2026, 5, 1);
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.PAY_INVOICE_CURRENT,
        context
      )
    );
  }

  @IsTest
  static void fieldCopy_rejectsPackageTarget() {
    FieldCopyDefinition__c definition = new FieldCopyDefinition__c(
      Name = 'Denied',
      TargetObject__c = 'Invoice__c',
      TargetFieldApiName__c = 'Amount__c',
      SourceObject__c = 'Invoice__c',
      SourceFieldApiName__c = 'Memo__c'
    );
    Boolean thrown = false;
    try {
      FieldCopyDefinitionService.validateDefinition(definition);
    } catch (FieldCopyDefinitionService.FieldCopyException ex) {
      thrown = true;
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void applyForInvoice_offSkipsGeneration() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Off');
      insert GlAccountingPolicyService.newOrgDefault();
      markConfirmed(fixture.invoice);
      Test.startTest();
      AccountingDiffService.applyForInvoice(
        fixture.invoice.Id,
        AccountingEventFixedCatalog.BILLING_CONFIRMED.key,
        'TEST_OFF',
        null
      );
      Test.stopTest();
      System.assertEquals(
        0,
        [SELECT COUNT() FROM GlJournal__c WHERE Invoice__c = :fixture.invoice.Id]
      );
      System.assertNotEquals(null, GlAccountingPolicyService.requireOrgPolicy().FrozenAt__c);
    }
  }

  @IsTest
  static void applyForInvoice_onGeneratesBillingJournals() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('On');
      enableAccounting();
      seedMaps();
      markConfirmed(fixture.invoice);
      fixture.invoice.TaxAmount__c = 100;
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      Test.startTest();
      AccountingDiffService.applyForInvoice(
        fixture.invoice.Id,
        AccountingEventFixedCatalog.BILLING_CONFIRMED.key,
        'TEST_ON',
        null
      );
      Test.stopTest();
      List<GlJournal__c> journals = [
        SELECT
          JournalPatternKey__c,
          DebitSlotKey__c,
          CreditSlotKey__c,
          Amount__c,
          TransactionStatus__c
        FROM GlJournal__c
        WHERE Invoice__c = :fixture.invoice.Id
        ORDER BY JournalPatternKey__c
      ];
      System.assertEquals(false, journals.isEmpty());
      Set<String> patterns = new Set<String>();
      for (GlJournal__c journal : journals) {
        System.assertEquals('Active', journal.TransactionStatus__c);
        System.assert(journal.Amount__c > 0);
        patterns.add(journal.JournalPatternKey__c);
      }
      System.assertEquals(true, patterns.contains('BILLING_BASIS_INVOICE_BODY'));
      System.assertEquals(true, patterns.contains('BILLING_TAX_AT_INVOICE'));
      System.assertEquals(true, patterns.contains('BILLING_BASIS_REVENUE_BODY'));
    }
  }

  @IsTest
  static void applyForInvoice_matchingLockedCurrent_isKept() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('KeepLock');
      enableAccounting();
      seedMaps();
      fixture.invoice.TaxAmount__c = 100;
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      confirmWithJournals(fixture.invoice);
      Integer locked = JournalLockService.lockForInvoice(
        fixture.invoice.Id,
        activeJournalIds(fixture.invoice.Id),
        AccountingCauseLockService.resolveInvoiceOperationToken(fixture.invoice.Id),
        null
      );
      System.assert(locked > 0, 'Accounting 第1.8.1節: 比較対象の元仕訳をロックする');
      Test.startTest();
      AccountingDiffService.applyForInvoice(
        fixture.invoice.Id,
        AccountingEventFixedCatalog.BILLING_CONFIRMED.key,
        'TEST_KEEP_LOCK',
        null
      );
      Test.stopTest();
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE
            Invoice__c = :fixture.invoice.Id
            AND TransactionStatus__c = 'Reversal'
        ],
        'Accounting 第1.8.1節: Goalと一致するCurrentはロック状態を問わず維持する'
      );
      System.assertEquals(
        locked,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE
            Invoice__c = :fixture.invoice.Id
            AND TransactionStatus__c = 'Active'
            AND IsLocked__c = TRUE
        ]
      );
    }
  }

  @IsTest
  static void applyForInvoice_unlockedCurrentOnly_isLogicallyDeleted() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('LeftUnl');
      enableAccounting();
      seedMaps();
      fixture.invoice.TaxAmount__c = 100;
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      confirmWithJournals(fixture.invoice);
      GlAccount__c debit = [
        SELECT Id
        FROM GlAccount__c
        WHERE Name = 'Engine AR'
        LIMIT 1
      ];
      GlAccount__c credit = [
        SELECT Id
        FROM GlAccount__c
        WHERE Name = 'Engine REV'
        LIMIT 1
      ];
      GlJournal__c leftover = new GlJournal__c(
        Invoice__c = fixture.invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'LEFTOVER_UNLOCKED' }
        ),
        JournalLineKey__c = 'leftover-unlocked',
        DebitSlotKey__c = AccountingSlotFixedCatalog.Cash.key,
        CreditSlotKey__c = AccountingSlotFixedCatalog.UnappliedCash.key,
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      insert leftover;
      Test.startTest();
      AccountingDiffService.applyForInvoice(
        fixture.invoice.Id,
        AccountingEventFixedCatalog.BILLING_CONFIRMED.key,
        'TEST_LEFT_UNLOCKED',
        null
      );
      Test.stopTest();
      leftover = [
        SELECT TransactionStatus__c
        FROM GlJournal__c
        WHERE Id = :leftover.Id
      ];
      System.assertEquals(
        'LogicallyDeleted',
        leftover.TransactionStatus__c,
        'Accounting 第1.8.1節: Currentだけにある未ロックは論理削除する'
      );
    }
  }

  @IsTest
  static void applyForInvoice_cancelledInvoice_emptyGoalLogicallyDeletesUnlocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('CancelGoal');
      enableAccounting();
      seedMaps();
      fixture.invoice.TaxAmount__c = 100;
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      confirmWithJournals(fixture.invoice);
      Integer originalCount = [
        SELECT COUNT()
        FROM GlJournal__c
        WHERE Invoice__c = :fixture.invoice.Id AND TransactionStatus__c = 'Active'
      ];
      markCancelled(fixture.invoice);
      Test.startTest();
      AccountingDiffService.applyForInvoice(
        fixture.invoice.Id,
        AccountingEventFixedCatalog.BILLING_CANCELLED.key,
        'TEST_CANCEL_GOAL',
        null
      );
      Test.stopTest();
      System.assertEquals(
        originalCount,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE
            Invoice__c = :fixture.invoice.Id
            AND TransactionStatus__c = 'LogicallyDeleted'
        ],
        'Accounting 第8.8節: 請求取消はGoalを空にし、未ロックCurrentを論理削除する'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE
            Invoice__c = :fixture.invoice.Id
            AND TransactionStatus__c IN ('Active', 'Reversal')
        ]
      );
    }
  }

  @IsTest
  static void applyForInvoice_cancelledInvoice_reversesLockedAtMaxDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('CancelLock');
      enableAccounting();
      seedMaps();
      fixture.invoice.TaxAmount__c = 100;
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      confirmWithJournals(fixture.invoice);
      JournalLockService.lockForInvoice(
        fixture.invoice.Id,
        activeJournalIds(fixture.invoice.Id),
        AccountingCauseLockService.resolveInvoiceOperationToken(fixture.invoice.Id),
        null
      );
      Date cancellationDate = Date.newInstance(2026, 5, 1);
      markCancelled(fixture.invoice);
      Test.startTest();
      AccountingDiffService.applyForInvoice(
        fixture.invoice.Id,
        AccountingEventFixedCatalog.BILLING_CANCELLED.key,
        'TEST_CANCEL_LOCK',
        cancellationDate
      );
      Test.stopTest();
      List<GlJournal__c> originals = [
        SELECT
          Id,
          PostingDate__c,
          TransactionStatus__c,
          InvoiceLine__c,
          JournalPatternKey__c,
          RecognitionSequence__c
        FROM GlJournal__c
        WHERE Invoice__c = :fixture.invoice.Id AND TransactionStatus__c = 'Cancelled'
      ];
      System.assertEquals(false, originals.isEmpty());
      Map<Id, GlJournal__c> originalsById = new Map<Id, GlJournal__c>();
      for (GlJournal__c original : originals) {
        originalsById.put(original.Id, original);
      }
      List<GlJournal__c> reversals = [
        SELECT
          OriginalJournal__c,
          PostingDate__c,
          DebitSlotKey__c,
          CreditSlotKey__c,
          InvoiceLine__c,
          JournalPatternKey__c,
          RecognitionSequence__c
        FROM GlJournal__c
        WHERE Invoice__c = :fixture.invoice.Id AND TransactionStatus__c = 'Reversal'
      ];
      System.assertEquals(originals.size(), reversals.size());
      for (GlJournal__c reversal : reversals) {
        GlJournal__c original = originalsById.get(reversal.OriginalJournal__c);
        Date originalDate = original.PostingDate__c;
        Date expected = cancellationDate >= originalDate
          ? cancellationDate
          : originalDate;
        System.assertEquals(
          expected,
          reversal.PostingDate__c,
          'Accounting 第8.5節、日付仕様 第7.3節: 逆仕訳日はmax(取消基準日, 元仕訳日)'
        );
        System.assertEquals(
          original.InvoiceLine__c,
          reversal.InvoiceLine__c,
          'Accounting 第8.8節: 取消仕訳は請求明細を元のまま保持する'
        );
        System.assertEquals(
          original.JournalPatternKey__c,
          reversal.JournalPatternKey__c,
          'Accounting 第8.8節: 取消仕訳は仕訳パターンキーを元のまま保持する'
        );
        System.assertEquals(
          original.RecognitionSequence__c,
          reversal.RecognitionSequence__c,
          'Accounting 第8.8節: 取消仕訳は売上計上回番号を元のまま保持する'
        );
      }
    }
  }

  @IsTest
  static void goalBuild_fourPolicySets_excludesDisallowedPatterns() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('GoalSet');
      enableAccounting();
      seedMaps();
      markConfirmed(fixture.invoice);
      fixture.invoice.TaxAmount__c = 100;
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      Invoice__c invoice = [
        SELECT Id, InvoiceDate__c, InvoiceTransactionStatus__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      Set<String> confirmKeys = new Set<String>{
        'BILLING_BASIS_INVOICE_BODY',
        'CASH_BASIS_INVOICE_BODY_CTA_TRANSFER',
        'BILLING_TAX_AT_INVOICE',
        'BILLING_BASIS_INVOICE_TAX_DEFERRED',
        'CASH_BASIS_INVOICE_TAX_CTA_TRANSFER',
        'BILLING_BASIS_REVENUE_BODY',
        'CASH_BASIS_REVENUE_BODY',
        'BILLING_BASIS_REVENUE_TAX',
        'CASH_BASIS_REVENUE_TAX'
      };
      List<GlAccountingPolicy__c> policies = new List<GlAccountingPolicy__c>();
      GlAccountingPolicy__c billingAtInvoice = GlAccountingPolicyService.newOrgDefault();
      billingAtInvoice.AccountingEnabled__c = true;
      policies.add(billingAtInvoice);
      GlAccountingPolicy__c billingAtRecognition = GlAccountingPolicyService.newOrgDefault();
      billingAtRecognition.AccountingEnabled__c = true;
      billingAtRecognition.TaxRecognitionTiming__c = 'AtRecognition';
      policies.add(billingAtRecognition);
      GlAccountingPolicy__c cashAtInvoice = GlAccountingPolicyService.newOrgDefault();
      cashAtInvoice.AccountingEnabled__c = true;
      cashAtInvoice.RevenueRecognitionBasis__c = 'CashBasis';
      policies.add(cashAtInvoice);
      GlAccountingPolicy__c cashAtRecognition = GlAccountingPolicyService.newOrgDefault();
      cashAtRecognition.AccountingEnabled__c = true;
      cashAtRecognition.RevenueRecognitionBasis__c = 'CashBasis';
      cashAtRecognition.TaxRecognitionTiming__c = 'AtRecognition';
      policies.add(cashAtRecognition);

      Test.startTest();
      for (GlAccountingPolicy__c policy : policies) {
        Set<String> allowed = GlAccountingPolicyService.deriveAllowedPatternKeys(
          policy
        );
        List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
          invoice,
          policy,
          new List<GlJournal__c>()
        );
        for (AccountingGoalService.GoalJournal goal : goals) {
          String key = goal.record.JournalPatternKey__c;
          if (!confirmKeys.contains(key)) {
            continue;
          }
          System.assertEquals(
            true,
            allowed.contains(key),
            'Accounting 第5.6節: 許可外パターンを候補化しない ' +
              policy.RevenueRecognitionBasis__c +
              '/' +
              policy.TaxRecognitionTiming__c +
              ' ' +
              key
          );
        }
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void goalBuild_reusesExistingPatternOutsideAllowedSet() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('ReusePat');
      enableAccounting();
      seedMaps();
      markConfirmed(fixture.invoice);
      fixture.invoice.TaxAmount__c = 100;
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      Invoice__c invoice = [
        SELECT Id, InvoiceDate__c, InvoiceTransactionStatus__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      GlAccountingPolicy__c cashAtInvoice = GlAccountingPolicyService.newOrgDefault();
      cashAtInvoice.AccountingEnabled__c = true;
      cashAtInvoice.RevenueRecognitionBasis__c = 'CashBasis';
      GlJournal__c prior = new GlJournal__c(
        Invoice__c = invoice.Id,
        InvoiceLine__c = fixture.line.Id,
        JournalPatternKey__c = 'BILLING_BASIS_INVOICE_BODY',
        RecognitionSequence__c = 0
      );
      Test.startTest();
      List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
        invoice,
        cashAtInvoice,
        new List<GlJournal__c>{ prior }
      );
      Test.stopTest();
      Set<String> keys = new Set<String>();
      for (AccountingGoalService.GoalJournal goal : goals) {
        keys.add(goal.record.JournalPatternKey__c);
      }
      System.assertEquals(
        true,
        keys.contains('BILLING_BASIS_INVOICE_BODY'),
        'Accounting 第8.3節: 既存元仕訳のパターンを再利用する'
      );
    }
  }

  @IsTest
  static void applyForInvoice_offConfirmDoesNotCancelLeftovers() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Keep');
      insert GlAccountingPolicyService.newOrgDefault();
      markConfirmed(fixture.invoice);
      GlAccount__c debit = new GlAccount__c(
        Name = 'Keep Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'Keep Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      insert new GlJournal__c(
        Invoice__c = fixture.invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(new List<String>{ 'KEEP' }),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      Test.startTest();
      AccountingDiffService.applyForInvoice(
        fixture.invoice.Id,
        AccountingEventFixedCatalog.BILLING_CONFIRMED.key,
        'TEST_KEEP',
        null
      );
      Test.stopTest();
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE Invoice__c = :fixture.invoice.Id AND TransactionStatus__c = 'Active'
        ]
      );
    }
  }

  @IsTest
  static void acceptance_rejectsCancelledInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('AccCancel');
      insert GlAccountingPolicyService.newOrgDefault();
      markConfirmed(fixture.invoice);
      markCancelled(fixture.invoice);

      Boolean thrown = false;
      try {
        Test.startTest();
        InvoiceCanonicalService.updateLineAcceptanceEndDates(
          new Map<Id, Date>{
            fixture.line.Id => Date.newInstance(2026, 8, 31)
          },
          null,
          null,
          AccountingCauseLockService.resolveInvoiceOperationToken(
            fixture.invoice.Id
          )
        );
        Test.stopTest();
      } catch (InvoiceCanonicalService.InvoiceEditException ex) {
        thrown = true;
        System.assertEquals(
          '取消済み請求の検収終了日は変更できません。',
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        thrown,
        'Core 第1.1.5節・第7.6節・第12.2節: 取消済みの検収終了日は変更できない'
      );
    }
  }

  @IsTest
  static void acceptance_offAllowsLogicallyDeletedLeftover() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('OffDel');
      insert GlAccountingPolicyService.newOrgDefault();
      markConfirmed(fixture.invoice);
      insert new GlJournal__c(
        Invoice__c = fixture.invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'OFF_DELETED_LEFTOVER' }
        ),
        JournalLineKey__c = 'off-deleted-leftover',
        DebitSlotKey__c = AccountingSlotFixedCatalog.Cash.key,
        CreditSlotKey__c = AccountingSlotFixedCatalog.UnappliedCash.key,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'LogicallyDeleted'
      );
      Test.startTest();
      InvoiceCanonicalService.updateLineAcceptanceEndDates(
        new Map<Id, Date>{
          fixture.line.Id => Date.newInstance(2026, 7, 31)
        },
        null,
        null,
        AccountingCauseLockService.resolveInvoiceOperationToken(fixture.invoice.Id)
      );
      Test.stopTest();
      InvoiceLine__c stored = [
        SELECT AcceptanceEndDate__c
        FROM InvoiceLine__c
        WHERE Id = :fixture.line.Id
      ];
      System.assertEquals(
        Date.newInstance(2026, 7, 31),
        stored.AcceptanceEndDate__c,
        'Accounting 第1.1節: 論理削除はCurrentに残っていない'
      );
    }
  }

  @IsTest
  static void acceptance_offRejectsActiveCurrent() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('OffAct');
      insert GlAccountingPolicyService.newOrgDefault();
      markConfirmed(fixture.invoice);
      insert new GlJournal__c(
        Invoice__c = fixture.invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'OFF_ACTIVE_LEFTOVER' }
        ),
        JournalLineKey__c = 'off-active-leftover',
        DebitSlotKey__c = AccountingSlotFixedCatalog.Cash.key,
        CreditSlotKey__c = AccountingSlotFixedCatalog.UnappliedCash.key,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      Boolean thrown = false;
      try {
        InvoiceCanonicalService.updateLineAcceptanceEndDates(
          new Map<Id, Date>{
            fixture.line.Id => Date.newInstance(2026, 7, 31)
          },
          null,
          null,
          AccountingCauseLockService.resolveInvoiceOperationToken(fixture.invoice.Id)
        );
      } catch (InvoiceCanonicalService.InvoiceEditException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('過去の関連仕訳'),
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        thrown,
        'Accounting 第1.1節: Currentが1件以上ならOFFの検収日変更を拒否する'
      );
    }
  }

  @IsTest
  static void acceptance_missingPolicyRejectsChange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('NoPol');
      markConfirmed(fixture.invoice);
      Boolean thrown = false;
      try {
        InvoiceCanonicalService.updateLineAcceptanceEndDates(
          new Map<Id, Date>{
            fixture.line.Id => Date.newInstance(2026, 7, 31)
          },
          null,
          null,
          AccountingCauseLockService.resolveInvoiceOperationToken(fixture.invoice.Id)
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('Accounting会計方針がありません。'),
          'Core 第1.1.10節: 方針0件をOFF扱いしない。実際: ' + ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void acceptance_rejectsMonthlyLine() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Monthly');
      InvoiceLine__c monthly = fixture.line.clone(false, false, false, false);
      monthly.ProductName__c = 'Monthly Line';
      monthly.RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      monthly.AcceptanceEndDate__c = null;
      insert monthly;
      Boolean thrown = false;
      try {
        InvoiceCanonicalService.updateLineAcceptanceEndDates(
          new Map<Id, Date>{ monthly.Id => Date.newInstance(2026, 6, 30) },
          null
        );
      } catch (InvoiceCanonicalService.InvoiceEditException ex) {
        thrown = true;
      }
      System.assertEquals(
        true,
        thrown,
        'Core 第7.6節: 月次計上明細へ検収終了日を設定したら落ちること'
      );
    }
  }

  @IsTest
  static void acceptance_lockedJournals_requiresCancellationDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('AccLock');
      enableAccounting();
      seedMaps();
      fixture.invoice.TaxAmount__c = 100;
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      confirmWithJournals(fixture.invoice);
      JournalLockService.lockForInvoice(
        fixture.invoice.Id,
        activeJournalIds(fixture.invoice.Id),
        AccountingCauseLockService.resolveInvoiceOperationToken(fixture.invoice.Id),
        null
      );
      Boolean thrown = false;
      try {
        InvoiceCanonicalService.updateLineAcceptanceEndDates(
          new Map<Id, Date>{
            fixture.line.Id => Date.newInstance(2026, 8, 31)
          },
          null
        );
      } catch (InvoiceCanonicalService.InvoiceEditException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('ロック済み仕訳がある取消では取消基準日が必要です'),
          'Core 第7.6節、日付仕様 第7.3節: 空を操作日で埋めない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void acceptance_lockedJournals_passesCancellationDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('AccLockOk');
      enableAccounting();
      seedMaps();
      fixture.invoice.TaxAmount__c = 100;
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      confirmWithJournals(fixture.invoice);
      JournalLockService.lockForInvoice(
        fixture.invoice.Id,
        activeJournalIds(fixture.invoice.Id),
        AccountingCauseLockService.resolveInvoiceOperationToken(fixture.invoice.Id),
        null
      );
      Date cancellationDate = Date.newInstance(2026, 8, 29);
      Test.startTest();
      InvoiceCanonicalService.updateLineAcceptanceEndDates(
        new Map<Id, Date>{
          fixture.line.Id => Date.newInstance(2026, 8, 31)
        },
        cancellationDate,
        null,
        AccountingCauseLockService.resolveInvoiceOperationToken(fixture.invoice.Id)
      );
      Test.stopTest();
      InvoiceLine__c stored = [
        SELECT AcceptanceEndDate__c
        FROM InvoiceLine__c
        WHERE Id = :fixture.line.Id
      ];
      System.assertEquals(
        Date.newInstance(2026, 8, 31),
        stored.AcceptanceEndDate__c,
        'Core 第7.6節: 取消基準日があれば検収終了日を変更できる'
      );
    }
  }

  @IsTest
  static void acceptance_rejectsExistingBasisChangeToMonthly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('SwitchM');
      Date originalDate = fixture.line.AcceptanceEndDate__c;
      Boolean thrown = false;
      try {
        fixture.line.RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
        update fixture.line;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(InvoiceCanonicalService.EXISTING_BASIS_LOCKED_MESSAGE),
          '第7.6節: 既存明細の売上計上基準変更を拒否する。実際: ' +
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown, '第7.6節: 一括から月次への変更はエラー');
      InvoiceLine__c loaded = [
        SELECT AcceptanceEndDate__c, RevenueRecognitionBasis__c
        FROM InvoiceLine__c
        WHERE Id = :fixture.line.Id
      ];
      System.assertEquals(
        ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME,
        loaded.RevenueRecognitionBasis__c
      );
      System.assertEquals(
        originalDate,
        loaded.AcceptanceEndDate__c,
        '第7.6節: 基準変更を拒否したとき検収終了日を黙って直さない'
      );
    }
  }

  @IsTest
  static void acceptance_rejectsExistingBasisChangeToLump() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('SwitchL');
      InvoiceLine__c monthly = fixture.line.clone(false, false, false, false);
      monthly.ProductName__c = 'Monthly Line';
      monthly.RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      monthly.AcceptanceEndDate__c = null;
      insert monthly;
      Boolean thrown = false;
      try {
        monthly.RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME;
        update monthly;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(InvoiceCanonicalService.EXISTING_BASIS_LOCKED_MESSAGE),
          '第7.6節: 既存明細の売上計上基準変更を拒否する。実際: ' +
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown, '第7.6節: 月次から一括への変更はエラー');
      InvoiceLine__c loaded = [
        SELECT AcceptanceEndDate__c, RevenueRecognitionBasis__c
        FROM InvoiceLine__c
        WHERE Id = :monthly.Id
      ];
      System.assertEquals(
        ContractMetadataService.REVENUE_BASIS_OVER_TIME,
        loaded.RevenueRecognitionBasis__c
      );
      System.assertEquals(
        null,
        loaded.AcceptanceEndDate__c,
        '第7.6節: 基準変更を拒否したとき検収終了日を黙って直さない'
      );
    }
  }

  @IsTest
  static void acceptance_rejectsEmptyLumpWithoutBasisChange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Empty');
      Boolean thrown = false;
      try {
        fixture.line.AcceptanceEndDate__c = null;
        update fixture.line;
      } catch (DmlException ex) {
        thrown = true;
      }
      System.assertEquals(
        true,
        thrown,
        'Core 第7.6節: 一括計上の検収終了日を空にしたら落ちること'
      );
    }
  }

  @IsTest
  static void journal_rejectsPhysicalDelete() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Del');
      insert GlAccountingPolicyService.newOrgDefault();
      GlAccount__c debit = new GlAccount__c(
        Name = 'Del Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'Del Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlJournal__c journal = new GlJournal__c(
        Invoice__c = fixture.invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(new List<String>{ 'DEL' }),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      insert journal;
      Boolean thrown = false;
      try {
        delete journal;
      } catch (DmlException ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void journal_allowsPhysicalDeleteWith104() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Del104');
      insert GlAccountingPolicyService.newOrgDefault();
      GlAccount__c debit = new GlAccount__c(
        Name = 'Del104 Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'Del104 Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlJournal__c journal = new GlJournal__c(
        Invoice__c = fixture.invoice.Id,
        Amount__c = 1,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'DEL104' }
        ),
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      insert journal;
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
        '共通基盤 第3.6節: 104 単独で仕訳の物理削除を通す'
      );
    }
  }

  @IsTest
  static void historicalBreakdown_usesThisGoalNotRegistrationSnapshot() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createPaymentFixture();
      enableAccounting();
      seedMaps();
      seedPaymentMaps();
      confirmWithJournals(fixture.invoice);
      InvoicePaymentAllocationService.AllocationLine allocationLine =
        new InvoicePaymentAllocationService.AllocationLine();
      allocationLine.invoiceLineId = fixture.line.Id;
      allocationLine.amount = 100000;
      allocationLine.historicalUacAmount = 99999;
      allocationLine.historicalSpAmount = 11111;

      Test.startTest();
      InvoicePaymentService.RegisterRequest nonInvoice = new InvoicePaymentService.RegisterRequest();
      nonInvoice.invoiceId = fixture.invoice.Id;
      nonInvoice.amount = -20000;
      nonInvoice.purpose = InvoicePaymentService.PURPOSE_NON_INVOICE;
      nonInvoice.paymentDate = Date.newInstance(2026, 5, 1);
      nonInvoice.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      Id nonInvoiceId = InvoicePaymentService.register(nonInvoice);

      InvoicePaymentService.RegisterRequest invoicePayment = new InvoicePaymentService.RegisterRequest();
      invoicePayment.invoiceId = fixture.invoice.Id;
      invoicePayment.amount = 100000;
      invoicePayment.purpose = InvoicePaymentService.PURPOSE_INVOICE;
      invoicePayment.paymentDate = Date.newInstance(2026, 6, 1);
      invoicePayment.allocations = new List<InvoicePaymentAllocationService.AllocationLine>{
        allocationLine
      };
      invoicePayment.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      InvoicePaymentService.register(invoicePayment);

      InvoicePaymentService.CancelRequest cancel = new InvoicePaymentService.CancelRequest();
      cancel.paymentId = nonInvoiceId;
      cancel.cancellationReason = 'Duplicate';
      cancel.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      InvoicePaymentService.cancel(cancel);
      Test.stopTest();

      InvoicePaymentAllocation__c written = [
        SELECT Amount__c, HistoricalUacAmount__c, HistoricalSpAmount__c
        FROM InvoicePaymentAllocation__c
        WHERE
          InvoicePayment__r.PaymentPurpose__c = 'Invoice'
          AND InvoicePayment__r.PaymentTransactionStatus__c = 'Active'
        LIMIT 1
      ];
      System.assertEquals(100000, written.Amount__c);
      System.assertEquals(100000, written.HistoricalUacAmount__c);
      System.assertEquals(0, written.HistoricalSpAmount__c);

      Map<String, Decimal> afterCancel = transferAmountsByPattern(fixture.invoice.Id);
      System.assertEquals(100000, afterCancel.get('PAYMENT_INVOICE_HISTORICAL_UAC_TRANSFER'));
      System.assertEquals(null, afterCancel.get('PAYMENT_INVOICE_HISTORICAL_SP_TRANSFER'));
    }
  }

  @IsTest
  static void historicalBreakdown_writesSignedSplitFromExistingSp() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createPaymentFixture();
      enableAccounting();
      seedMaps();
      seedPaymentMaps();
      confirmWithJournals(fixture.invoice);
      InvoicePaymentAllocationService.AllocationLine allocationLine =
        new InvoicePaymentAllocationService.AllocationLine();
      allocationLine.invoiceLineId = fixture.line.Id;
      allocationLine.amount = 100000;
      allocationLine.historicalUacAmount = 99999;
      allocationLine.historicalSpAmount = 11111;

      Test.startTest();
      InvoicePaymentService.RegisterRequest nonInvoice = new InvoicePaymentService.RegisterRequest();
      nonInvoice.invoiceId = fixture.invoice.Id;
      nonInvoice.amount = -20000;
      nonInvoice.purpose = InvoicePaymentService.PURPOSE_NON_INVOICE;
      nonInvoice.paymentDate = Date.newInstance(2026, 5, 1);
      nonInvoice.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      InvoicePaymentService.register(nonInvoice);

      InvoicePaymentService.RegisterRequest invoicePayment = new InvoicePaymentService.RegisterRequest();
      invoicePayment.invoiceId = fixture.invoice.Id;
      invoicePayment.amount = 100000;
      invoicePayment.purpose = InvoicePaymentService.PURPOSE_INVOICE;
      invoicePayment.paymentDate = Date.newInstance(2026, 6, 1);
      invoicePayment.allocations = new List<InvoicePaymentAllocationService.AllocationLine>{
        allocationLine
      };
      invoicePayment.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      InvoicePaymentService.register(invoicePayment);
      Test.stopTest();

      InvoicePaymentAllocation__c written = [
        SELECT Amount__c, HistoricalUacAmount__c, HistoricalSpAmount__c
        FROM InvoicePaymentAllocation__c
        WHERE InvoicePayment__r.PaymentPurpose__c = 'Invoice'
        LIMIT 1
      ];
      System.assertEquals(100000, written.Amount__c);
      System.assertEquals(80000, written.HistoricalUacAmount__c);
      System.assertEquals(-20000, written.HistoricalSpAmount__c);

      Map<String, Decimal> transferAmounts = transferAmountsByPattern(fixture.invoice.Id);
      System.assertEquals(80000, transferAmounts.get('PAYMENT_INVOICE_HISTORICAL_UAC_TRANSFER'));
      System.assertEquals(20000, transferAmounts.get('PAYMENT_INVOICE_HISTORICAL_SP_TRANSFER'));
    }
  }

  @IsTest
  static void historicalBreakdown_negativeCash_matchesGoalTemporarySigns() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createPaymentFixture();
      fixture.invoice.Amount__c = -100000;
      fixture.invoice.TaxAmount__c = 0;
      fixture.invoice.TaxInclusiveAmount__c = -100000;
      update fixture.invoice;
      fixture.line.Amount__c = -100000;
      fixture.line.UnitPrice__c = -100000;
      update fixture.line;
      enableAccounting();
      seedMaps();
      seedPaymentMaps();
      confirmWithJournals(fixture.invoice);

      Test.startTest();
      InvoicePaymentService.RegisterRequest nonInvoice = new InvoicePaymentService.RegisterRequest();
      nonInvoice.invoiceId = fixture.invoice.Id;
      nonInvoice.amount = 20000;
      nonInvoice.purpose = InvoicePaymentService.PURPOSE_NON_INVOICE;
      nonInvoice.paymentDate = Date.newInstance(2026, 5, 1);
      nonInvoice.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      InvoicePaymentService.register(nonInvoice);

      InvoicePaymentAllocationService.AllocationLine allocationLine =
        new InvoicePaymentAllocationService.AllocationLine();
      allocationLine.invoiceLineId = fixture.line.Id;
      allocationLine.amount = -100000;
      InvoicePaymentService.RegisterRequest invoicePayment = new InvoicePaymentService.RegisterRequest();
      invoicePayment.invoiceId = fixture.invoice.Id;
      invoicePayment.amount = -100000;
      invoicePayment.purpose = InvoicePaymentService.PURPOSE_INVOICE;
      invoicePayment.paymentDate = Date.newInstance(2026, 6, 1);
      invoicePayment.allocations = new List<InvoicePaymentAllocationService.AllocationLine>{
        allocationLine
      };
      invoicePayment.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      InvoicePaymentService.register(invoicePayment);
      Test.stopTest();

      InvoicePaymentAllocation__c written = [
        SELECT Amount__c, HistoricalUacAmount__c, HistoricalSpAmount__c
        FROM InvoicePaymentAllocation__c
        WHERE
          InvoicePayment__r.PaymentPurpose__c = 'Invoice'
          AND InvoicePayment__r.PaymentTransactionStatus__c = 'Active'
        LIMIT 1
      ];
      System.assertEquals(-100000, written.Amount__c);
      System.assertEquals(
        -20000,
        written.HistoricalUacAmount__c,
        'Accounting 第4.4節・第5.2.14節: 負額現預金はUAC解消を負で書く'
      );
      System.assertEquals(
        80000,
        written.HistoricalSpAmount__c,
        'Accounting 第4.4節・第5.2.14節: 負額現預金の残はSP積みを正で書く'
      );
      System.assertEquals(
        written.Amount__c,
        written.HistoricalUacAmount__c - written.HistoricalSpAmount__c,
        'Accounting 第4.4節: Amount = HistoricalUac - HistoricalSp'
      );
    }
  }

  @IsTest
  static void historicalBreakdown_sameDayInvoiceStaysZero() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createPaymentFixture();
      enableAccounting();
      seedMaps();
      seedPaymentMaps();
      confirmWithJournals(fixture.invoice);
      InvoicePaymentAllocationService.AllocationLine allocationLine =
        new InvoicePaymentAllocationService.AllocationLine();
      allocationLine.invoiceLineId = fixture.line.Id;
      allocationLine.amount = 100000;

      Test.startTest();
      InvoicePaymentService.RegisterRequest invoicePayment = new InvoicePaymentService.RegisterRequest();
      invoicePayment.invoiceId = fixture.invoice.Id;
      invoicePayment.amount = 100000;
      invoicePayment.purpose = InvoicePaymentService.PURPOSE_INVOICE;
      invoicePayment.paymentDate = Date.newInstance(2026, 6, 15);
      invoicePayment.allocations = new List<InvoicePaymentAllocationService.AllocationLine>{
        allocationLine
      };
      invoicePayment.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      InvoicePaymentService.register(invoicePayment);
      Test.stopTest();

      InvoicePaymentAllocation__c written = [
        SELECT HistoricalUacAmount__c, HistoricalSpAmount__c
        FROM InvoicePaymentAllocation__c
        LIMIT 1
      ];
      System.assertEquals(0, written.HistoricalUacAmount__c);
      System.assertEquals(0, written.HistoricalSpAmount__c);
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE
            Invoice__c = :fixture.invoice.Id
            AND JournalPatternKey__c = 'PAYMENT_INVOICE_CURRENT'
            AND TransactionStatus__c = 'Active'
        ]
      );
    }
  }

  @IsTest
  static void sortCandidates_usesCauseCreatedDateBeforeId() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createPaymentFixture();
      enableAccounting();
      seedMaps();
      seedPaymentMaps();
      confirmWithJournals(fixture.invoice);

      InvoicePayment__c laterPayment = new InvoicePayment__c(
        Invoice__c = fixture.invoice.Id,
        Amount__c = 70000,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.newInstance(2026, 6, 1),
        PaymentTransactionStatus__c = InvoicePaymentService.STATUS_ACTIVE,
        BillingAccount__c = fixture.invoice.BillingAccountSnapShot__c
      );
      insertInvoicePurpose(laterPayment);
      InvoicePaymentAllocation__c laterAllocation = new InvoicePaymentAllocation__c(
        InvoicePayment__c = laterPayment.Id,
        InvoiceLine__c = fixture.line.Id,
        Amount__c = 70000,
        HistoricalUacAmount__c = 0,
        HistoricalSpAmount__c = 0
      );
      insert laterAllocation;

      InvoicePayment__c earlierPayment = new InvoicePayment__c(
        Invoice__c = fixture.invoice.Id,
        Amount__c = 30000,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.newInstance(2026, 6, 1),
        PaymentTransactionStatus__c = InvoicePaymentService.STATUS_ACTIVE,
        BillingAccount__c = fixture.invoice.BillingAccountSnapShot__c
      );
      insertInvoicePurpose(earlierPayment);
      InvoicePaymentAllocation__c earlierAllocation = new InvoicePaymentAllocation__c(
        InvoicePayment__c = earlierPayment.Id,
        InvoiceLine__c = fixture.line.Id,
        Amount__c = 30000,
        HistoricalUacAmount__c = 0,
        HistoricalSpAmount__c = 0
      );
      insert earlierAllocation;

      Test.setCreatedDate(earlierAllocation.Id, Datetime.newInstance(2026, 5, 1, 10, 0, 0));
      Test.setCreatedDate(laterAllocation.Id, Datetime.newInstance(2026, 5, 1, 12, 0, 0));

      Test.startTest();
      AccountingDiffService.applyForInvoice(
        fixture.invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        'TEST_SORT',
        null
      );
      Test.stopTest();

      List<GlJournal__c> cashJournals = [
        SELECT InvoicePaymentAllocation__c, CreatedDate
        FROM GlJournal__c
        WHERE
          Invoice__c = :fixture.invoice.Id
          AND JournalPatternKey__c = 'PAYMENT_INVOICE_HISTORICAL_POSITIVE_CASH'
          AND TransactionStatus__c = 'Active'
        ORDER BY CreatedDate ASC, Id ASC
      ];
      System.assertEquals(2, cashJournals.size());
      System.assertEquals(earlierAllocation.Id, cashJournals[0].InvoicePaymentAllocation__c);
      System.assertEquals(laterAllocation.Id, cashJournals[1].InvoicePaymentAllocation__c);
    }
  }

  @IsTest
  static void journalLock_requiresReason() {
    Boolean thrown = false;
    try {
      JournalLockService.unlockForInvoice(UserInfo.getUserId(), null, null);
    } catch (JournalLockService.LockException ex) {
      thrown = true;
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void journalLock_rejectsWhenAccountingOff() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Fixture fixture = createFixture('lockoff');
      Boolean thrown = false;
      try {
        JournalLockService.lockForInvoice(
          fixture.invoice.Id,
          new List<Id>()
        );
      } catch (JournalLockService.LockException ex) {
        thrown = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void getOpsBundle_showsTrueTagLabelsOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('tag');
      fixture.invoice.IsManuallyAdjusted__c = true;
      fixture.invoice.IsAmountAdjusted__c = false;
      update fixture.invoice;
      insert new List<GlAccountingTagRule__c>{
        new GlAccountingTagRule__c(
          Name = 'Rule True',
          TagKey__c = 'ar_open',
          TagLabel__c = 'AR残あり',
          Expression__c = 'AR',
          ComparisonOperator__c = 'NE',
          ComparisonValue__c = 0,
          TargetFieldApiName__c = 'IsManuallyAdjusted__c',
          IsEnabled__c = true
        ),
        new GlAccountingTagRule__c(
          Name = 'Rule False',
          TagKey__c = 'adj',
          TagLabel__c = '端数調整済',
          Expression__c = 'AR',
          ComparisonOperator__c = 'EQ',
          ComparisonValue__c = 0,
          TargetFieldApiName__c = 'IsAmountAdjusted__c',
          IsEnabled__c = true
        ),
        new GlAccountingTagRule__c(
          Name = 'Rule Disabled',
          TagKey__c = 'off',
          TagLabel__c = '無効タグ',
          IsEnabled__c = false
        )
      };
      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id
      );
      System.assertEquals(1, bundle.tagResults.size());
      System.assertEquals('AR残あり', bundle.tagResults[0].name);
      System.assertEquals(true, bundle.tagResults[0].value);
    }
  }

  @IsTest
  static void goalBuild_paymentUsesExistingArStampNotPaymentMap() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('ArStamp');
      enableAccounting();
      seedMaps();
      seedPaymentMaps();
      markConfirmed(fixture.invoice);
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);

      InvoicePaymentAllocationService.AllocationLine allocationLine =
        new InvoicePaymentAllocationService.AllocationLine();
      allocationLine.invoiceLineId = fixture.line.Id;
      allocationLine.amount = 1100;

      Test.startTest();
      InvoicePaymentService.RegisterRequest invoicePayment = new InvoicePaymentService.RegisterRequest();
      invoicePayment.invoiceId = fixture.invoice.Id;
      invoicePayment.amount = 1100;
      invoicePayment.purpose = InvoicePaymentService.PURPOSE_INVOICE;
      invoicePayment.paymentDate = Date.newInstance(2026, 6, 15);
      invoicePayment.allocations = new List<InvoicePaymentAllocationService.AllocationLine>{
        allocationLine
      };
      invoicePayment.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      InvoicePaymentService.register(invoicePayment);
      Test.stopTest();

      Id billingArId = [
        SELECT Account__c
        FROM GlAccountMap__c
        WHERE SlotKey__c = 'AccountsReceivable' AND EvaluationContext__c = 'InvoiceLine'
        LIMIT 1
      ]
      .Account__c;
      Id paymentMapArId = [
        SELECT Account__c
        FROM GlAccountMap__c
        WHERE
          SlotKey__c = 'AccountsReceivable'
          AND EvaluationContext__c = 'InvoicePaymentAllocation'
        LIMIT 1
      ]
      .Account__c;
      System.assertNotEquals(
        billingArId,
        paymentMapArId,
        'Accounting 第8.4節: テスト前提として請求明細割当と入金割当のAR科目を分ける'
      );
      List<GlJournal__c> paymentJournals = [
        SELECT CreditAccount__c, Amount__c
        FROM GlJournal__c
        WHERE
          Invoice__c = :fixture.invoice.Id
          AND JournalPatternKey__c = 'PAYMENT_INVOICE_CURRENT'
          AND TransactionStatus__c = 'Active'
      ];
      System.assertEquals(
        1,
        paymentJournals.size(),
        'Accounting 第8.4節: 同一明細の単一AR残高は1本の入金仕訳にする'
      );
      System.assertEquals(
        billingArId,
        paymentJournals[0].CreditAccount__c,
        'Accounting 第8.4節: 既存残高への充当は元仕訳の実勘定科目を使う'
      );
      System.assertEquals(1100, paymentJournals[0].Amount__c);
    }
  }

  @IsTest
  static void goalBuild_sameRateSplitsAllocationAcrossArAccounts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('ArSplit');
      enableAccounting();
      seedMaps();
      seedPaymentMaps();
      markConfirmed(fixture.invoice);
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      Invoice__c invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          InvoiceTransactionStatus__c,
          BillingAccountSnapShot__c,
          BillingAccountKeySnapShot__c,
          Amount__c,
          TaxAmount__c,
          TaxInclusiveAmount__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
      List<AccountingGoalService.GoalJournal> billingGoals = AccountingGoalService.build(
        invoice,
        policy,
        new List<GlJournal__c>()
      );
      GlAccount__c secondAr = new GlAccount__c(
        Name = 'Engine AR2',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      insert secondAr;
      List<GlJournal__c> current = new List<GlJournal__c>();
      for (AccountingGoalService.GoalJournal goal : billingGoals) {
        GlJournal__c row = goal.record;
        if (
          row.JournalPatternKey__c == 'BILLING_TAX_AT_INVOICE' &&
          row.DebitSlotKey__c == 'AccountsReceivable'
        ) {
          row.DebitAccount__c = secondAr.Id;
        }
        current.add(row);
      }
      InvoicePayment__c payment = new InvoicePayment__c(
        Invoice__c = invoice.Id,
        Amount__c = 550,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.newInstance(2026, 6, 15)
      );
      insertInvoicePurpose(payment);
      insert new InvoicePaymentAllocation__c(
        InvoicePayment__c = payment.Id,
        InvoiceLine__c = fixture.line.Id,
        Amount__c = 550
      );

      Test.startTest();
      List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
        invoice,
        policy,
        current
      );
      Test.stopTest();

      Map<Id, Decimal> paymentByAr = new Map<Id, Decimal>();
      for (AccountingGoalService.GoalJournal goal : goals) {
        if (goal.record.JournalPatternKey__c != 'PAYMENT_INVOICE_CURRENT') {
          continue;
        }
        paymentByAr.put(goal.record.CreditAccount__c, goal.record.Amount__c);
      }
      Id billingArId = [
        SELECT Account__c
        FROM GlAccountMap__c
        WHERE SlotKey__c = 'AccountsReceivable' AND EvaluationContext__c = 'InvoiceLine'
        LIMIT 1
      ]
      .Account__c;
      System.assertEquals(
        500,
        paymentByAr.get(billingArId),
        'Accounting 第8.4節 / Core 第11.9節: 同じ率で本体AR残高へ配分する'
      );
      System.assertEquals(
        50,
        paymentByAr.get(secondAr.Id),
        'Accounting 第8.4節 / Core 第11.9節: 同じ率で税AR残高へ配分する'
      );
    }
  }

  @IsTest
  static void goalBuild_finalSettlementZerosEachArRemaining() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('ArFinal');
      enableAccounting();
      seedMaps();
      seedPaymentMaps();
      markConfirmed(fixture.invoice);
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      Invoice__c invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          InvoiceTransactionStatus__c,
          BillingAccountSnapShot__c,
          BillingAccountKeySnapShot__c,
          Amount__c,
          TaxAmount__c,
          TaxInclusiveAmount__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
      List<AccountingGoalService.GoalJournal> billingGoals = AccountingGoalService.build(
        invoice,
        policy,
        new List<GlJournal__c>()
      );
      GlAccount__c secondAr = new GlAccount__c(
        Name = 'Engine AR2 Final',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      insert secondAr;
      List<GlJournal__c> current = new List<GlJournal__c>();
      for (AccountingGoalService.GoalJournal goal : billingGoals) {
        GlJournal__c row = goal.record;
        if (
          row.JournalPatternKey__c == 'BILLING_TAX_AT_INVOICE' &&
          row.DebitSlotKey__c == 'AccountsReceivable'
        ) {
          row.DebitAccount__c = secondAr.Id;
        }
        current.add(row);
      }
      InvoicePayment__c payment = new InvoicePayment__c(
        Invoice__c = invoice.Id,
        Amount__c = 1100,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.newInstance(2026, 6, 15)
      );
      insertInvoicePurpose(payment);
      insert new InvoicePaymentAllocation__c(
        InvoicePayment__c = payment.Id,
        InvoiceLine__c = fixture.line.Id,
        Amount__c = 1100
      );

      Test.startTest();
      List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
        invoice,
        policy,
        current
      );
      Test.stopTest();

      Map<Id, Decimal> paymentByAr = new Map<Id, Decimal>();
      for (AccountingGoalService.GoalJournal goal : goals) {
        if (goal.record.JournalPatternKey__c != 'PAYMENT_INVOICE_CURRENT') {
          continue;
        }
        paymentByAr.put(goal.record.CreditAccount__c, goal.record.Amount__c);
      }
      Id billingArId = [
        SELECT Account__c
        FROM GlAccountMap__c
        WHERE SlotKey__c = 'AccountsReceivable' AND EvaluationContext__c = 'InvoiceLine'
        LIMIT 1
      ]
      .Account__c;
      System.assertEquals(
        1000,
        paymentByAr.get(billingArId),
        'Accounting 第8.4節 / Core 第11.9節: 最終決済は科目別残額を直接0にする'
      );
      System.assertEquals(
        100,
        paymentByAr.get(secondAr.Id),
        'Accounting 第8.4節 / Core 第11.9節: 最終決済は税AR残額を直接0にする'
      );
    }
  }

  @IsTest
  static void goalBuild_taxScheduleFollowsSignedRevenueShare() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('TaxShare');
      InvoiceLine__c monthly = fixture.line.clone(false, false, false, false);
      monthly.ProductName__c = 'Tax Share Line';
      monthly.Amount__c = 10;
      monthly.AllocatedTaxAmount__c = 3;
      monthly.Quantity__c = 1;
      monthly.UnitPrice__c = 10;
      monthly.RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      monthly.AcceptanceEndDate__c = null;
      monthly.ServicePeriodStartDate__c = Date.newInstance(2026, 4, 15);
      monthly.ServicePeriodEndDate__c = Date.newInstance(2026, 7, 14);
      insert monthly;
      delete fixture.line;
      fixture.invoice.Amount__c = 10;
      fixture.invoice.TaxAmount__c = 3;
      fixture.invoice.InvoiceDate__c = Date.newInstance(2026, 4, 15);
      update fixture.invoice;

      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      policy.TaxRecognitionTiming__c = 'AtRecognition';
      policy.RoundingTargetBucket__c = 'First';
      insert policy;
      seedMaps();
      markConfirmed(fixture.invoice);
      Invoice__c invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          InvoiceTransactionStatus__c,
          BillingAccountSnapShot__c,
          BillingAccountKeySnapShot__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];

      Test.startTest();
      List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
        invoice,
        policy,
        new List<GlJournal__c>()
      );
      Test.stopTest();

      List<AccountingGoalService.GoalJournal> taxGoals = new List<AccountingGoalService.GoalJournal>();
      for (AccountingGoalService.GoalJournal goal : goals) {
        if (goal.record.JournalPatternKey__c == 'BILLING_BASIS_REVENUE_TAX') {
          taxGoals.add(goal);
        }
      }
      System.assertEquals(
        1,
        taxGoals.size(),
        'Core 第11.9節 / Accounting 第3.2節: 符号付き売上比なら税は3,0,0（0円仕訳は作らない）'
      );
      System.assertEquals(3, taxGoals[0].record.Amount__c);
      System.assertEquals(1, taxGoals[0].record.RecognitionSequence__c);
    }
  }

  @IsTest
  static void goalBuild_negativeLineCtaUsesNormalizedBooks() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('NegCta');
      InvoiceLine__c monthly = fixture.line.clone(false, false, false, false);
      monthly.ProductName__c = 'Neg Discount';
      monthly.Amount__c = -10000;
      monthly.AllocatedTaxAmount__c = 0;
      monthly.Quantity__c = 1;
      monthly.UnitPrice__c = -10000;
      monthly.RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      monthly.AcceptanceEndDate__c = null;
      monthly.ServicePeriodStartDate__c = Date.newInstance(2026, 4, 1);
      monthly.ServicePeriodEndDate__c = Date.newInstance(2026, 6, 30);
      insert monthly;
      delete fixture.line;
      fixture.invoice.Amount__c = -10000;
      fixture.invoice.TaxAmount__c = 0;
      fixture.invoice.InvoiceDate__c = Date.newInstance(2026, 5, 15);
      update fixture.invoice;

      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      policy.RevenueRecognitionBasis__c = 'CashBasis';
      policy.RoundingTargetBucket__c = 'Last';
      insert policy;
      seedMaps();
      markConfirmed(fixture.invoice);
      Invoice__c invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          InvoiceTransactionStatus__c,
          BillingAccountSnapShot__c,
          BillingAccountKeySnapShot__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];

      Test.startTest();
      List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
        invoice,
        policy,
        new List<GlJournal__c>()
      );
      Test.stopTest();

      AccountingGoalService.GoalJournal cta;
      for (AccountingGoalService.GoalJournal goal : goals) {
        if (goal.record.JournalPatternKey__c == 'CASH_BASIS_INVOICE_BODY_CTA_TRANSFER') {
          cta = goal;
        }
      }
      System.assertNotEquals(
        null,
        cta,
        'Accounting 第4.4節: 請求日前の認識済みCTAを振り替える'
      );
      System.assertEquals(
        3333,
        cta.record.Amount__c,
        'Accounting 第4.6節: 正規化した非負のC-Bを符号付き計算値へ戻す。20000や0にしない'
      );
      System.assertEquals(
        AccountingSlotFixedCatalog.ContractAsset.key,
        cta.record.DebitSlotKey__c,
        'Accounting 第1.3節 / 第4.4節: 負のCTA振替は借貸を反転する'
      );
      System.assertEquals(
        AccountingSlotFixedCatalog.AccountsReceivable.key,
        cta.record.CreditSlotKey__c
      );
    }
  }

  @IsTest
  static void goalBuild_negativeBillingLine_flipsSidesOnGoal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('NegBill');
      InvoiceLine__c discount = fixture.line.clone(false, false, false, false);
      discount.ProductName__c = 'Neg Billing';
      discount.Amount__c = -10000;
      discount.AllocatedTaxAmount__c = 0;
      discount.Quantity__c = 1;
      discount.UnitPrice__c = -10000;
      discount.RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME;
      discount.AcceptanceEndDate__c = Date.newInstance(2026, 5, 15);
      discount.ServicePeriodStartDate__c = Date.newInstance(2026, 5, 1);
      discount.ServicePeriodEndDate__c = Date.newInstance(2026, 5, 31);
      insert discount;
      delete fixture.line;
      fixture.invoice.Amount__c = -10000;
      fixture.invoice.TaxAmount__c = 0;
      fixture.invoice.InvoiceDate__c = Date.newInstance(2026, 5, 15);
      update fixture.invoice;

      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      policy.RevenueRecognitionBasis__c = 'BillingBasis';
      policy.TaxRecognitionTiming__c = 'AtInvoice';
      policy.RoundingTargetBucket__c = 'Last';
      insert policy;
      seedMaps();
      markConfirmed(fixture.invoice);
      Invoice__c invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          InvoiceTransactionStatus__c,
          BillingAccountSnapShot__c,
          BillingAccountKeySnapShot__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];

      Test.startTest();
      List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
        invoice,
        policy,
        new List<GlJournal__c>()
      );
      Test.stopTest();

      AccountingGoalService.GoalJournal body;
      for (AccountingGoalService.GoalJournal goal : goals) {
        if (goal.record.JournalPatternKey__c == 'BILLING_BASIS_INVOICE_BODY') {
          body = goal;
        }
        System.assert(
          goal.record.Amount__c > 0,
          'Accounting 第1.3節: 負額は借貸反転後に正で保存する'
        );
      }
      System.assertNotEquals(null, body, 'Accounting 第4.6節: 請求基準の負額明細もGoalを作る');
      System.assertEquals(
        AccountingSlotFixedCatalog.DeferredRevenue.key,
        body.record.DebitSlotKey__c,
        'Accounting 第1.3節 / 第4.6節: 負額は分割後に借貸を反転する'
      );
      System.assertEquals(
        AccountingSlotFixedCatalog.AccountsReceivable.key,
        body.record.CreditSlotKey__c
      );
    }
  }

  @IsTest
  static void goalBuild_reusesRevenueAccountsOnRegenerationWithPriority() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('ReuseRev');
      enableAccounting();
      seedMaps();
      markConfirmed(fixture.invoice);
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      Invoice__c invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          InvoiceTransactionStatus__c,
          BillingAccountSnapShot__c,
          BillingAccountKeySnapShot__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
      List<AccountingGoalService.GoalJournal> first = AccountingGoalService.build(
        invoice,
        policy,
        new List<GlJournal__c>()
      );
      GlAccount__c otherRev = new GlAccount__c(
        Name = 'Engine REV2',
        AccountType__c = 'Revenue',
        IsActive__c = true
      );
      insert otherRev;
      Id originalRev;
      List<GlJournal__c> current = new List<GlJournal__c>();
      for (AccountingGoalService.GoalJournal goal : first) {
        GlJournal__c row = goal.record;
        if (row.JournalPatternKey__c == 'BILLING_BASIS_REVENUE_BODY') {
          originalRev = row.CreditAccount__c;
          row.CreditAccount__c = otherRev.Id;
        }
        current.add(row);
      }
      System.assertNotEquals(null, originalRev);
      // 割当は初回のまま（originalRev）。Currentだけ otherRev にして再生成する。

      Test.startTest();
      List<AccountingGoalService.GoalJournal> rebuilt = AccountingGoalService.build(
        invoice,
        policy,
        current
      );
      Test.stopTest();

      AccountingGoalService.GoalJournal revenue;
      for (AccountingGoalService.GoalJournal goal : rebuilt) {
        if (goal.record.JournalPatternKey__c == 'BILLING_BASIS_REVENUE_BODY') {
          revenue = goal;
        }
      }
      System.assertNotEquals(null, revenue);
      System.assertEquals(
        otherRev.Id,
        revenue.record.CreditAccount__c,
        'Accounting 第8.8節: 優先解決ありの売上も同一生成単位の再生成で元の実勘定を維持する'
      );
      System.assertNotEquals(
        originalRev,
        revenue.record.CreditAccount__c,
        'Accounting 第8.8節: 現在割当へ解決し直さない'
      );
    }
  }

  @IsTest
  static void goalBuild_calendarMonthBucketsUseSharedUtil() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('CalBucket');
      InvoiceLine__c monthly = fixture.line.clone(false, false, false, false);
      monthly.ProductName__c = 'Cal Bucket Line';
      monthly.Amount__c = 3000;
      monthly.AllocatedTaxAmount__c = 0;
      monthly.Quantity__c = 1;
      monthly.UnitPrice__c = 3000;
      monthly.RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      monthly.AcceptanceEndDate__c = null;
      monthly.ServicePeriodStartDate__c = Date.newInstance(2026, 5, 15);
      monthly.ServicePeriodEndDate__c = Date.newInstance(2026, 7, 31);
      insert monthly;
      delete fixture.line;
      fixture.invoice.Amount__c = 3000;
      fixture.invoice.TaxAmount__c = 0;
      fixture.invoice.TaxInclusiveAmount__c = 3000;
      fixture.invoice.InvoiceDate__c = Date.newInstance(2026, 5, 15);
      update fixture.invoice;

      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      policy.MonthlyBucketMethod__c = 'CalendarMonth';
      insert policy;
      seedMaps();
      markConfirmed(fixture.invoice);
      Invoice__c invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          InvoiceTransactionStatus__c,
          BillingAccountSnapShot__c,
          BillingAccountKeySnapShot__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];

      Test.startTest();
      List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
        invoice,
        policy,
        new List<GlJournal__c>()
      );
      Test.stopTest();

      Integer expected = MonthlyBillingPeriodUtil.buildCalendarMonthPeriods(
          Date.newInstance(2026, 5, 15),
          Date.newInstance(2026, 7, 31)
        )
        .size();
      Integer revenueBodies = 0;
      for (AccountingGoalService.GoalJournal goal : goals) {
        if (goal.record.JournalPatternKey__c == 'BILLING_BASIS_REVENUE_BODY') {
          revenueBodies++;
        }
      }
      System.assertEquals(
        expected,
        revenueBodies,
        'Accounting 第3.3節 / 日付仕様 第2章: 暦月バケットはUtil.buildCalendarMonthPeriodsと一致する'
      );
      System.assertEquals(3, expected, '5/15～7/31の暦月は3バケット');
    }
  }

  @IsTest
  static void goalBuild_billingBasisDefDrawdownKeepsBodyAndTaxOriginsSeparate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('DefRole');
      fixture.line.Amount__c = 1000;
      fixture.line.AllocatedTaxAmount__c = 100;
      fixture.line.UnitPrice__c = 1000;
      fixture.line.RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME;
      fixture.line.AcceptanceEndDate__c = Date.newInstance(2026, 6, 30);
      fixture.line.ServicePeriodStartDate__c = Date.newInstance(2026, 6, 1);
      fixture.line.ServicePeriodEndDate__c = Date.newInstance(2026, 6, 30);
      update fixture.line;
      fixture.invoice.Amount__c = 1000;
      fixture.invoice.TaxAmount__c = 100;
      fixture.invoice.TaxInclusiveAmount__c = 1100;
      fixture.invoice.InvoiceDate__c = Date.newInstance(2026, 6, 1);
      update fixture.invoice;

      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      policy.RevenueRecognitionBasis__c = 'BillingBasis';
      policy.TaxRecognitionTiming__c = 'AtRecognition';
      insert policy;
      seedMaps();
      markConfirmed(fixture.invoice);
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      Invoice__c invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          InvoiceTransactionStatus__c,
          BillingAccountSnapShot__c,
          BillingAccountKeySnapShot__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];

      Test.startTest();
      List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
        invoice,
        policy,
        new List<GlJournal__c>()
      );
      Test.stopTest();

      Decimal bodyDefCreated = 0;
      Decimal taxDefCreated = 0;
      AccountingGoalService.GoalJournal bodyRevenue;
      AccountingGoalService.GoalJournal taxRevenue;
      for (AccountingGoalService.GoalJournal goal : goals) {
        String key = goal.record.JournalPatternKey__c;
        if (
          key == 'BILLING_BASIS_INVOICE_BODY' &&
          goal.record.CreditSlotKey__c == AccountingSlotFixedCatalog.DeferredRevenue.key
        ) {
          bodyDefCreated += goal.record.Amount__c;
        }
        if (
          key == 'BILLING_BASIS_INVOICE_TAX_DEFERRED' &&
          goal.record.CreditSlotKey__c == AccountingSlotFixedCatalog.DeferredRevenue.key
        ) {
          taxDefCreated += goal.record.Amount__c;
        }
        if (
          key == 'BILLING_BASIS_REVENUE_BODY' &&
          goal.record.DebitSlotKey__c == AccountingSlotFixedCatalog.DeferredRevenue.key
        ) {
          bodyRevenue = goal;
        }
        if (
          key == 'BILLING_BASIS_REVENUE_TAX' &&
          goal.record.DebitSlotKey__c == AccountingSlotFixedCatalog.DeferredRevenue.key
        ) {
          taxRevenue = goal;
        }
      }
      System.assert(
        bodyDefCreated > 0 && taxDefCreated > 0,
        'Accounting 第4.6節: 請求時に本体DEFと税DEFを積む前提'
      );
      System.assertNotEquals(
        null,
        bodyRevenue,
        'Accounting 第5.2.6節: No.6は本体DEFを取り崩す'
      );
      System.assertNotEquals(
        null,
        taxRevenue,
        'Accounting 第5.2.8節: No.8は税DEFを取り崩す'
      );
      System.assertEquals(
        bodyDefCreated,
        bodyRevenue.record.Amount__c,
        'Accounting 第4.6節: No.6は本体DEFだけを取り崩し、税DEFを混ぜない'
      );
      System.assertEquals(
        taxDefCreated,
        taxRevenue.record.Amount__c,
        'Accounting 第4.6節: No.8は税DEFだけを取り崩し、本体DEFを混ぜない'
      );
    }
  }

  @IsTest
  static void goalBuild_billingBasisInvoiceCtaKeepsBodyAndTaxOriginsSeparate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('BillCta');
      InvoiceLine__c monthly = fixture.line.clone(false, false, false, false);
      monthly.ProductName__c = 'Billing CTA Role Line';
      monthly.Amount__c = 9000;
      monthly.AllocatedTaxAmount__c = 900;
      monthly.Quantity__c = 1;
      monthly.UnitPrice__c = 9000;
      monthly.RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      monthly.AcceptanceEndDate__c = null;
      monthly.ServicePeriodStartDate__c = Date.newInstance(2026, 4, 1);
      monthly.ServicePeriodEndDate__c = Date.newInstance(2026, 6, 30);
      insert monthly;
      delete fixture.line;
      fixture.invoice.Amount__c = 9000;
      fixture.invoice.TaxAmount__c = 900;
      fixture.invoice.TaxInclusiveAmount__c = 9900;
      fixture.invoice.InvoiceDate__c = Date.newInstance(2026, 5, 15);
      update fixture.invoice;

      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      policy.RevenueRecognitionBasis__c = 'BillingBasis';
      policy.TaxRecognitionTiming__c = 'AtRecognition';
      policy.RoundingTargetBucket__c = 'Last';
      insert policy;
      seedMaps();
      markConfirmed(fixture.invoice);
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      Invoice__c invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          InvoiceTransactionStatus__c,
          BillingAccountSnapShot__c,
          BillingAccountKeySnapShot__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];

      Test.startTest();
      List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
        invoice,
        policy,
        new List<GlJournal__c>()
      );
      Test.stopTest();

      Id bodyCtaAccount;
      Id taxCtaAccount;
      Decimal bodyRevenueCtaBeforeBill = 0;
      Decimal taxRevenueCtaBeforeBill = 0;
      Decimal bodyInvoiceCta = 0;
      Decimal taxInvoiceCta = 0;
      Decimal bodyInvoiceDef = 0;
      Decimal taxInvoiceDef = 0;
      for (AccountingGoalService.GoalJournal goal : goals) {
        String key = goal.record.JournalPatternKey__c;
        Boolean beforeBill =
          goal.record.PostingDate__c != null &&
          goal.record.PostingDate__c < invoice.InvoiceDate__c;
        if (
          beforeBill &&
          key == 'BILLING_BASIS_REVENUE_BODY' &&
          goal.record.DebitSlotKey__c == AccountingSlotFixedCatalog.ContractAsset.key
        ) {
          bodyCtaAccount = goal.record.DebitAccount__c;
          bodyRevenueCtaBeforeBill += goal.record.Amount__c;
        }
        if (
          beforeBill &&
          key == 'BILLING_BASIS_REVENUE_TAX' &&
          goal.record.DebitSlotKey__c == AccountingSlotFixedCatalog.ContractAsset.key
        ) {
          taxCtaAccount = goal.record.DebitAccount__c;
          taxRevenueCtaBeforeBill += goal.record.Amount__c;
        }
        if (
          key == 'BILLING_BASIS_INVOICE_BODY' &&
          goal.record.CreditSlotKey__c == AccountingSlotFixedCatalog.ContractAsset.key
        ) {
          bodyInvoiceCta += goal.record.Amount__c;
        }
        if (
          key == 'BILLING_BASIS_INVOICE_TAX_DEFERRED' &&
          goal.record.CreditSlotKey__c == AccountingSlotFixedCatalog.ContractAsset.key
        ) {
          taxInvoiceCta += goal.record.Amount__c;
        }
        if (
          key == 'BILLING_BASIS_INVOICE_BODY' &&
          goal.record.CreditSlotKey__c == AccountingSlotFixedCatalog.DeferredRevenue.key
        ) {
          bodyInvoiceDef += goal.record.Amount__c;
        }
        if (
          key == 'BILLING_BASIS_INVOICE_TAX_DEFERRED' &&
          goal.record.CreditSlotKey__c == AccountingSlotFixedCatalog.DeferredRevenue.key
        ) {
          taxInvoiceDef += goal.record.Amount__c;
        }
      }
      System.assert(
        bodyRevenueCtaBeforeBill > 0 && taxRevenueCtaBeforeBill > 0,
        'Accounting 第4.6節: 請求日前に本体・税CTAがある前提'
      );
      System.assertEquals(
        bodyRevenueCtaBeforeBill,
        bodyInvoiceCta,
        'Accounting 第5.2.1節: No.1のCTA取り崩しは本体だけ（税を混ぜない）'
      );
      System.assertEquals(
        taxRevenueCtaBeforeBill,
        taxInvoiceCta,
        'Accounting 第5.2.4節: No.4のCTA取り崩しは税だけ（本体を混ぜない）'
      );
      System.assertEquals(
        9000 - bodyRevenueCtaBeforeBill,
        bodyInvoiceDef,
        'Accounting 第4.6節・第5.2.1節: No.1のDEF積上は本体B-Cだけ（請求日前税Cで削らない）'
      );
      System.assertEquals(
        900 - taxRevenueCtaBeforeBill,
        taxInvoiceDef,
        'Accounting 第4.6節・第5.2.4節: No.4のDEF積上は税B-Cだけ'
      );
      System.assertNotEquals(
        null,
        bodyCtaAccount,
        'Accounting 第6.2節: 本体CTAの作成元科目がある'
      );
      System.assertNotEquals(
        null,
        taxCtaAccount,
        'Accounting 第6.2節: 税CTAの作成元科目がある'
      );
    }
  }

  @IsTest
  static void goalBuild_cashBasisCtaTransferKeepsBodyAndTaxOriginsSeparate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('CtaRole');
      InvoiceLine__c monthly = fixture.line.clone(false, false, false, false);
      monthly.ProductName__c = 'CTA Role Line';
      monthly.Amount__c = 9000;
      monthly.AllocatedTaxAmount__c = 900;
      monthly.Quantity__c = 1;
      monthly.UnitPrice__c = 9000;
      monthly.RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME;
      monthly.AcceptanceEndDate__c = null;
      monthly.ServicePeriodStartDate__c = Date.newInstance(2026, 4, 1);
      monthly.ServicePeriodEndDate__c = Date.newInstance(2026, 6, 30);
      insert monthly;
      delete fixture.line;
      fixture.invoice.Amount__c = 9000;
      fixture.invoice.TaxAmount__c = 900;
      fixture.invoice.TaxInclusiveAmount__c = 9900;
      fixture.invoice.InvoiceDate__c = Date.newInstance(2026, 5, 15);
      update fixture.invoice;

      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      policy.RevenueRecognitionBasis__c = 'CashBasis';
      policy.TaxRecognitionTiming__c = 'AtRecognition';
      policy.RoundingTargetBucket__c = 'Last';
      insert policy;
      seedMaps();
      markConfirmed(fixture.invoice);
      InvoiceTaxAllocationService.allocateOnConfirm(fixture.invoice);
      Invoice__c invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          InvoiceTransactionStatus__c,
          BillingAccountSnapShot__c,
          BillingAccountKeySnapShot__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];

      Test.startTest();
      List<AccountingGoalService.GoalJournal> goals = AccountingGoalService.build(
        invoice,
        policy,
        new List<GlJournal__c>()
      );
      Test.stopTest();

      Id bodyCtaAccount;
      Id taxCtaAccount;
      Decimal bodyRevenueCtaBeforeBill = 0;
      Decimal taxRevenueCtaBeforeBill = 0;
      AccountingGoalService.GoalJournal bodyTransfer;
      AccountingGoalService.GoalJournal taxTransfer;
      for (AccountingGoalService.GoalJournal goal : goals) {
        String key = goal.record.JournalPatternKey__c;
        Boolean beforeBill =
          goal.record.PostingDate__c != null &&
          goal.record.PostingDate__c < invoice.InvoiceDate__c;
        if (
          beforeBill &&
          key == 'CASH_BASIS_REVENUE_BODY' &&
          goal.record.DebitSlotKey__c == AccountingSlotFixedCatalog.ContractAsset.key
        ) {
          bodyCtaAccount = goal.record.DebitAccount__c;
          bodyRevenueCtaBeforeBill += goal.record.Amount__c;
        }
        if (
          beforeBill &&
          key == 'CASH_BASIS_REVENUE_TAX' &&
          goal.record.DebitSlotKey__c == AccountingSlotFixedCatalog.ContractAsset.key
        ) {
          taxCtaAccount = goal.record.DebitAccount__c;
          taxRevenueCtaBeforeBill += goal.record.Amount__c;
        }
        if (key == 'CASH_BASIS_INVOICE_BODY_CTA_TRANSFER') {
          bodyTransfer = goal;
        }
        if (key == 'CASH_BASIS_INVOICE_TAX_CTA_TRANSFER') {
          taxTransfer = goal;
        }
      }
      System.assert(
        bodyRevenueCtaBeforeBill > 0,
        'Accounting 第4.4節: 請求日前の本体CTA実行残高がある前提'
      );
      System.assert(
        taxRevenueCtaBeforeBill > 0,
        'Accounting 第4.4節: 請求日前の税CTA実行残高がある前提'
      );
      System.assertNotEquals(
        null,
        bodyTransfer,
        'Accounting 第4.4節 / 第5.2.2節: 請求日前の本体CTAを振り替える'
      );
      System.assertNotEquals(
        null,
        taxTransfer,
        'Accounting 第4.4節 / 第5.2.5節: 請求日前の税CTAを振り替える'
      );
      System.assertEquals(
        bodyRevenueCtaBeforeBill,
        bodyTransfer.record.Amount__c,
        'Accounting 第4.4節: No.2は本体由来CTAだけを取り崩し、税スタンプを混ぜない'
      );
      System.assertEquals(
        taxRevenueCtaBeforeBill,
        taxTransfer.record.Amount__c,
        'Accounting 第4.4節: No.5は税由来CTAだけを取り崩し、本体スタンプを混ぜない'
      );
      System.assertEquals(
        bodyCtaAccount,
        bodyTransfer.record.CreditAccount__c,
        'Accounting 第6.2節: No.2のCTA側は作成元の実勘定を継承する'
      );
      System.assertEquals(
        taxCtaAccount,
        taxTransfer.record.CreditAccount__c,
        'Accounting 第6.2節: No.5のCTA側は作成元の実勘定を継承する'
      );
    }
  }

  private class Fixture {
    Invoice__c invoice;
    InvoiceLine__c line;
  }

  private static List<Id> activeJournalIds(Id invoiceId) {
    List<Id> ids = new List<Id>();
    for (GlJournal__c row : [
      SELECT Id
      FROM GlJournal__c
      WHERE Invoice__c = :invoiceId AND TransactionStatus__c = 'Active'
    ]) {
      ids.add(row.Id);
    }
    return ids;
  }

  private static void confirmWithJournals(Invoice__c invoice) {
    markConfirmed(invoice);
    AccountingDiffService.applyForInvoice(
      invoice.Id,
      AccountingEventFixedCatalog.BILLING_CONFIRMED.key,
      'TEST_CONFIRM',
      null
    );
  }

  private static Map<String, Decimal> transferAmountsByPattern(Id invoiceId) {
    Map<String, Decimal> amounts = new Map<String, Decimal>();
    for (GlJournal__c journal : [
      SELECT JournalPatternKey__c, Amount__c
      FROM GlJournal__c
      WHERE
        Invoice__c = :invoiceId
        AND TransactionStatus__c = 'Active'
        AND JournalPatternKey__c IN (
          'PAYMENT_INVOICE_HISTORICAL_UAC_TRANSFER',
          'PAYMENT_INVOICE_HISTORICAL_SP_TRANSFER'
        )
    ]) {
      amounts.put(journal.JournalPatternKey__c, journal.Amount__c);
    }
    return amounts;
  }

  private static Fixture createPaymentFixture() {
    Fixture fixture = createFixture('Pay');
    fixture.invoice.InvoiceDate__c = Date.newInstance(2026, 6, 15);
    fixture.invoice.Amount__c = 100000;
    fixture.invoice.TaxAmount__c = 0;
    fixture.invoice.TaxInclusiveAmount__c = 100000;
    update fixture.invoice;
    fixture.line.Amount__c = 100000;
    fixture.line.UnitPrice__c = 100000;
    update fixture.line;
    return fixture;
  }

  private static void insertInvoicePurpose(InvoicePayment__c payment) {
    Boolean previous = InvoicePaymentService.allowLifecycleWrite;
    InvoicePaymentService.allowLifecycleWrite = true;
    try {
      insert payment;
    } finally {
      InvoicePaymentService.allowLifecycleWrite = previous;
    }
  }

  private static void seedPaymentMaps() {
    Map<String, String> types = new Map<String, String>{
      'CASH' => 'Asset',
      'UAC' => 'Liability',
      'SP' => 'Asset',
      'AR' => 'Asset',
      'DEF' => 'Liability'
    };
    Map<String, Id> accountIds = new Map<String, Id>();
    List<GlAccount__c> accounts = new List<GlAccount__c>();
    for (String name : types.keySet()) {
      accounts.add(
        new GlAccount__c(
          Name = 'Pay ' + name,
          AccountType__c = types.get(name),
          IsActive__c = true
        )
      );
    }
    insert accounts;
    for (GlAccount__c account : accounts) {
      accountIds.put(account.Name.substringAfter('Pay '), account.Id);
    }
    Map<String, String> slots = new Map<String, String>{
      'Cash' => 'CASH',
      'UnappliedCash' => 'UAC',
      'SuspensePayment' => 'SP',
      'AccountsReceivable' => 'AR',
      'DeferredRevenue' => 'DEF'
    };
    List<GlAccountMap__c> maps = new List<GlAccountMap__c>();
    for (String context : new List<String>{ 'InvoicePaymentAllocation', 'InvoicePayment' }) {
      for (String slot : slots.keySet()) {
        maps.add(
          new GlAccountMap__c(
            Name = 'Pay ' + context + ' ' + slot,
            Account__c = accountIds.get(slots.get(slot)),
            SlotKey__c = slot,
            EvaluationContext__c = context,
            ConditionSourceType__c = 'None',
            Priority__c = 10,
            IsActive__c = true
          )
        );
      }
    }
    insert maps;
  }

  private static Fixture createFixture(String suffix) {
    Account account = ContractTestDataFactory.insertAccount('Engine ' + suffix);
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'engine@example.com',
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
    ContractService__c service = new ContractService__c(
      Name = 'Engine ' + suffix,
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Engine History ' + suffix,
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1
    );
    insert history;
    Product2 product = ContractTestDataFactory.buildProduct('Engine Prod ' + suffix);
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Account__c = account.Id,
      Product__c = product.Id,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2026, 6, 30)
    );
    ContractTestDataFactory.applyRequiredFields(contractProduct);
    insert contractProduct;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = 100,
      TaxInclusiveAmount__c = 1100,
      BillingAccountSnapShot__c = billingAccount.Id,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT
    );
    insert invoice;
    InvoiceLine__c line = new InvoiceLine__c(
      Invoice__c = invoice.Id,
      ContractProduct__c = contractProduct.Id,
      ProductName__c = 'Engine Line',
      Amount__c = 1000,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME,
      AcceptanceEndDate__c = Date.newInstance(2026, 6, 30),
      ServicePeriodStartDate__c = Date.newInstance(2026, 6, 1),
      ServicePeriodEndDate__c = Date.newInstance(2026, 6, 30)
    );
    insert line;
    Fixture fixture = new Fixture();
    fixture.invoice = invoice;
    fixture.line = line;
    return fixture;
  }

  private static void markCancelled(Invoice__c invoice) {
    InvoiceTransactionStatusService.applyCancelled(new List<Invoice__c>{ invoice });
    Boolean previousStatus = InvoiceTransactionStatusService.allowStatusWrite;
    Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
    InvoiceTransactionStatusService.allowStatusWrite = true;
    InvoiceLockUtil.allowLockedStatusWrite = true;
    try {
      update invoice;
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
      InvoiceLockUtil.allowLockedStatusWrite = previousLock;
    }
  }

  private static void markConfirmed(Invoice__c invoice) {
    InvoiceTransactionStatusService.applyConfirmed(
      new List<Invoice__c>{ invoice },
      Date.newInstance(2026, 6, 1)
    );
    Boolean previousStatus = InvoiceTransactionStatusService.allowStatusWrite;
    Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
    InvoiceTransactionStatusService.allowStatusWrite = true;
    InvoiceLockUtil.allowLockedStatusWrite = true;
    try {
      update invoice;
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
      InvoiceLockUtil.allowLockedStatusWrite = previousLock;
    }
  }

  private static void enableAccounting() {
    GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
    policy.AccountingEnabled__c = true;
    insert policy;
  }

  private static void seedMaps() {
    Map<String, String> types = new Map<String, String>{
      'AR' => 'Asset',
      'CTA' => 'Asset',
      'DEF' => 'Liability',
      'TAX' => 'Liability',
      'REV' => 'Revenue'
    };
    Map<String, Id> accountIds = new Map<String, Id>();
    List<GlAccount__c> accounts = new List<GlAccount__c>();
    for (String name : types.keySet()) {
      accounts.add(
        new GlAccount__c(
          Name = 'Engine ' + name,
          AccountType__c = types.get(name),
          IsActive__c = true
        )
      );
    }
    insert accounts;
    for (GlAccount__c account : accounts) {
      accountIds.put(account.Name.substringAfter('Engine '), account.Id);
    }
    Map<String, String> slots = new Map<String, String>{
      'AccountsReceivable' => 'AR',
      'ContractAsset' => 'CTA',
      'DeferredRevenue' => 'DEF',
      'TaxPayable' => 'TAX',
      'Revenue' => 'REV'
    };
    List<GlAccountMap__c> maps = new List<GlAccountMap__c>();
    for (String slot : slots.keySet()) {
      maps.add(
        new GlAccountMap__c(
          Name = 'Engine ' + slot,
          Account__c = accountIds.get(slots.get(slot)),
          SlotKey__c = slot,
          EvaluationContext__c = 'InvoiceLine',
          ConditionSourceType__c = 'None',
          Priority__c = 10,
          IsActive__c = true
        )
      );
    }
    insert maps;
  }
}
