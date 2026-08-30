@IsTest
private class InvoicePaymentServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void labels_matchCore81DisplayNames() {
    System.assertEquals(
      '請求入出金',
      InvoicePayment__c.SObjectType.getDescribe().getLabel(),
      '第8.1節: オブジェクト表示名は請求入出金'
    );
    System.assertEquals(
      '入出金日',
      InvoicePayment__c.PaymentDate__c.getDescribe().getLabel(),
      '第8.1節: PaymentDate__c の表示名は入出金日'
    );
    System.assertEquals(
      '符号付き金額',
      InvoicePayment__c.Amount__c.getDescribe().getLabel(),
      '第8.1節: Amount__c の表示名は符号付き金額'
    );
    System.assertEquals(
      false,
      InvoicePayment__c.SObjectType.getDescribe().fields.getMap().containsKey('IsLocked__c'),
      'Core 第8.1節 / Accounting 第2.3節: 請求入出金はIsLocked__cを持たない'
    );
  }

  @IsTest
  static void register_withoutManageInvoiceOps_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoicePaymentService.RegisterRequest request = new InvoicePaymentService.RegisterRequest();
      request.invoiceId = UserInfo.getUserId();
      request.amount = 100;
      request.purpose = InvoicePaymentService.PURPOSE_INVOICE;
      request.paymentDate = Date.today();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.INVOICE_PAYMENT => false
      };
      Boolean thrown = false;
      try {
        InvoicePaymentService.register(request);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '入金する権限がありません。',
          ex.getMessage(),
          'Core 第8.4節: 登録は請求入出金操作権限を見る'
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
      InvoicePaymentService.CancelRequest request = new InvoicePaymentService.CancelRequest();
      request.paymentId = UserInfo.getUserId();
      request.cancellationReason = 'Duplicate';
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.INVOICE_PAYMENT => false
      };
      Boolean thrown = false;
      try {
        InvoicePaymentService.cancel(request);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '入金する権限がありません。',
          ex.getMessage(),
          'Core 第8.4節: 取消は請求入出金操作権限を見る'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void register_rejectsBlankExpectedToken() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      InvoicePaymentService.RegisterRequest request = invoiceRequest(
        fixture,
        1100
      );
      request.expectedToken = null;
      Boolean thrown = false;
      try {
        InvoicePaymentService.register(request);
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains(ContractOptimisticLockUtil.CONFLICT_MESSAGE) ||
            ex.getMessage().contains('他のユーザーが先に更新しました'),
          'Core 第7.9.7節: 比較値未指定は拒否する。実際: ' + ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void register_rejectsDraftInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(false);
      InvoicePaymentService.RegisterRequest request = invoiceRequest(
        fixture,
        1100
      );
      Boolean thrown = false;
      try {
        InvoicePaymentService.register(request);
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('確定済みの請求にだけ入出金を登録できます'),
          'Core 第8.4節: 未確定請求への登録を拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void register_rejectsZeroAmount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoicePaymentService.RegisterRequest request = new InvoicePaymentService.RegisterRequest();
      request.invoiceId = UserInfo.getUserId();
      request.amount = 0;
      request.purpose = InvoicePaymentService.PURPOSE_INVOICE;
      request.paymentDate = Date.today();
      Boolean thrown = false;
      try {
        InvoicePaymentService.register(request);
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('0以外の整数'),
          'Core 第8.3節: 0円は登録しない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void register_rejectsInvoiceWithoutAllocations() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      InvoicePaymentService.RegisterRequest request = invoiceRequest(
        fixture,
        1100
      );
      request.allocations = null;
      Boolean thrown = false;
      try {
        InvoicePaymentService.register(request);
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('明細別割当が1件以上必要'),
          'Core 第8.6節: Invoice目的は明細別割当が必須'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void register_rejectsNonInvoiceWithAllocations() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      InvoicePaymentService.RegisterRequest request = invoiceRequest(
        fixture,
        100
      );
      request.purpose = InvoicePaymentService.PURPOSE_NON_INVOICE;
      Boolean thrown = false;
      try {
        InvoicePaymentService.register(request);
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('請求金額以外の入出金に明細別割当は持てません'),
          'Core 第8.6節: NonInvoiceは明細別割当を持たない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void register_rejectsUnknownInvoiceAfterLock() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoicePaymentService.RegisterRequest request = new InvoicePaymentService.RegisterRequest();
      request.invoiceId =
        Invoice__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
      request.amount = 100;
      request.purpose = InvoicePaymentService.PURPOSE_NON_INVOICE;
      request.paymentDate = Date.today();
      Boolean thrown = false;
      try {
        InvoicePaymentService.register(request);
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('請求をロックできませんでした'),
          'Accounting 第8.2節: 未処理Net判定の前に対象請求書を行ロックする'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void register_rejectsAmountOverRemainingNet() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      InvoicePaymentService.RegisterRequest request = invoiceRequest(
        fixture,
        1200
      );
      Boolean thrown = false;
      try {
        InvoicePaymentService.register(request);
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('未処理Netを超えられません'),
          'Core 第8.3節: |Amount| は未処理Netを超えない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void registerThenCancel_keepsOriginalAndOppositeSign() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      Id paymentId = InvoicePaymentService.register(
        invoiceRequest(fixture, 1100)
      );

      Invoice__c afterRegister = [
        SELECT InvoicePaymentNet__c
        FROM Invoice__c
        WHERE Id = :fixture.invoice.Id
      ];
      System.assertEquals(
        1100,
        afterRegister.InvoicePaymentNet__c,
        'Core 第8.1節: 請求金額NetはPurpose=Invoiceの有効Amount合計'
      );

      InvoicePaymentService.CancelRequest cancel = new InvoicePaymentService.CancelRequest();
      cancel.paymentId = paymentId;
      cancel.cancellationReason = 'Duplicate';
      cancel.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        fixture.invoice.Id
      );
      Id reversalId = InvoicePaymentService.cancel(cancel);

      InvoicePayment__c original = [
        SELECT Amount__c, PaymentPurpose__c, PaymentTransactionStatus__c
        FROM InvoicePayment__c
        WHERE Id = :paymentId
      ];
      InvoicePayment__c reversal = [
        SELECT
          Amount__c,
          PaymentPurpose__c,
          PaymentTransactionStatus__c,
          OriginalPayment__c
        FROM InvoicePayment__c
        WHERE Id = :reversalId
      ];
      System.assertEquals(
        1100,
        original.Amount__c,
        'Core 第8.5節: 元取引の金額は変えない'
      );
      System.assertEquals(
        InvoicePaymentService.STATUS_CANCELLED,
        original.PaymentTransactionStatus__c,
        'Core 第8.5節: 元取引は残して取消済みにする'
      );
      System.assertEquals(
        -1100,
        reversal.Amount__c,
        'Core 第8.5節: 取消は反対符号のAmount'
      );
      System.assertEquals(
        InvoicePaymentService.PURPOSE_INVOICE,
        reversal.PaymentPurpose__c,
        'Core 第8.5節: 取消は元と同じPurpose'
      );
      System.assertEquals(
        InvoicePaymentService.STATUS_REVERSAL,
        reversal.PaymentTransactionStatus__c
      );
      System.assertEquals(paymentId, reversal.OriginalPayment__c);

      InvoicePaymentAllocation__c reversalAllocation = [
        SELECT Amount__c
        FROM InvoicePaymentAllocation__c
        WHERE InvoicePayment__c = :reversalId
      ];
      System.assertEquals(
        -1100,
        reversalAllocation.Amount__c,
        'Core 第8.5節: 取消割当は再按分せず反転する'
      );

      Boolean thrown = false;
      try {
        cancel.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
          fixture.invoice.Id
        );
        InvoicePaymentService.cancel(cancel);
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('有効な入出金だけ取消できます'),
          'Core 第8.5節: 同じ元取引を二重に取り消さない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void register_lockedJournals_requiresCancellationDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      InvoiceFixture fixture = createInvoice(true);
      insertLockedJournal(fixture.invoice.Id, 'REGLOCK');
      InvoicePaymentService.RegisterRequest request = invoiceRequest(
        fixture,
        1100
      );
      Boolean thrown = false;
      try {
        InvoicePaymentService.register(request);
      } catch (InvoicePaymentService.PaymentException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('ロック済み仕訳がある取消では取消基準日が必要です'),
          'Accounting 第8.5節: ONかつロック済みなら取消基準日必須'
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        0,
        [SELECT COUNT() FROM InvoicePayment__c WHERE Invoice__c = :fixture.invoice.Id],
        '日付仕様 第7.3節: 未入力なら登録しない'
      );
    }
  }

  @IsTest
  static void register_accountingOff_lockedJournals_skipsCancellationDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      insertLockedJournal(fixture.invoice.Id, 'REGLOCKOFF');
      InvoicePaymentService.RegisterRequest request = invoiceRequest(
        fixture,
        1100
      );
      Integer journalsBefore = [
        SELECT COUNT()
        FROM GlJournal__c
        WHERE Invoice__c = :fixture.invoice.Id AND TransactionStatus__c = 'Active'
      ];
      Test.startTest();
      Id paymentId = InvoicePaymentService.register(request);
      Test.stopTest();
      System.assertNotEquals(
        null,
        paymentId,
        'Accounting 第1.1節: OFFの入金登録は取消基準日なしで通る'
      );
      System.assertEquals(
        journalsBefore,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE Invoice__c = :fixture.invoice.Id AND TransactionStatus__c = 'Active'
        ],
        'Accounting 第1.1節: OFFの入金登録は仕訳を触らない'
      );
    }
  }

  @IsTest
  static void register_lockedJournals_passesCancellationDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      InvoiceFixture fixture = createInvoice(true);
      insertLockedJournal(fixture.invoice.Id, 'REGLOCKOK');
      InvoicePaymentService.RegisterRequest request = invoiceRequest(
        fixture,
        1100
      );
      request.cancellationDate = Date.newInstance(2026, 8, 29);
      Test.startTest();
      Id paymentId = InvoicePaymentService.register(request);
      Test.stopTest();
      System.assertNotEquals(null, paymentId);
    }
  }

  @IsTest
  static void previewRegister_lockedJournals_doesNotPersist() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      insertLockedJournal(fixture.invoice.Id, 'REGPREV');
      InvoicePaymentService.RegisterRequest request = invoiceRequest(
        fixture,
        1100
      );
      request.cancellationDate = Date.newInstance(2026, 8, 29);
      Test.startTest();
      AccountingDiffService.CancelPreview preview = InvoicePaymentService.previewRegister(
        request
      );
      Test.stopTest();
      System.assertNotEquals(null, preview);
      System.assertNotEquals(null, preview.displayText);
      System.assertEquals(
        0,
        [SELECT COUNT() FROM InvoicePayment__c WHERE Invoice__c = :fixture.invoice.Id],
        'Core 第7.9.6節: 実行前プレビューは登録しない'
      );
    }
  }

  @IsTest
  static void cancel_requiresReason() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoicePaymentService.CancelRequest cancel = new InvoicePaymentService.CancelRequest();
      cancel.paymentId = UserInfo.getUserId();
      Boolean thrown = false;
      try {
        InvoicePaymentService.cancel(cancel);
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('取消理由を入力してください'),
          'Core 第8.5節: 取消理由は必須'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void cancel_otherRequiresText() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoicePaymentService.CancelRequest cancel = new InvoicePaymentService.CancelRequest();
      cancel.paymentId = UserInfo.getUserId();
      cancel.cancellationReason = 'Other';
      Boolean thrown = false;
      try {
        InvoicePaymentService.cancel(cancel);
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('その他のときは内容を入力してください'),
          'Core 第8.5節: Otherは内容必須'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void previewCancel_offCountsPaymentJournalsOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      // OFF は cancelCurrent / isCancelTarget（入出金仕訳だけ）
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      InvoicePaymentService.allowLifecycleWrite = true;
      InvoicePayment__c payment = new InvoicePayment__c(
        Invoice__c = fixture.invoice.Id,
        Amount__c = 1100,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.newInstance(2026, 6, 1),
        PaymentTransactionStatus__c = InvoicePaymentService.STATUS_ACTIVE
      );
      insert payment;
      InvoicePaymentService.allowLifecycleWrite = false;
      insertPaymentJournal(fixture.invoice.Id, payment.Id, true, 'PAYLOCK');
      insertPaymentJournal(fixture.invoice.Id, null, true, 'BILLLOCK');

      AccountingDiffService.CancelPreview preview = InvoicePaymentService.previewCancel(
        payment.Id,
        Date.today()
      );
      System.assertEquals(
        0,
        preview.logicalDeleteCount,
        'OFF: 未ロックは無い'
      );
      System.assertEquals(
        1,
        preview.reverseCount,
        'OFF: 対象入出金の Lock 仕訳だけを逆仕訳件数に数える'
      );
    }
  }

  @IsTest
  static void previewCancel_onCountsGoalDiffNotPaymentJournalsOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      InvoiceFixture fixture = createInvoice(true);
      // 明細を外し Goal を空に近づける（科目割当シード無しでも Diff 件数だけ検証する）
      delete fixture.line;
      InvoicePaymentService.allowLifecycleWrite = true;
      InvoicePayment__c payment = new InvoicePayment__c(
        Invoice__c = fixture.invoice.Id,
        Amount__c = 1100,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_NON_INVOICE,
        PaymentDate__c = Date.newInstance(2026, 6, 1),
        PaymentTransactionStatus__c = InvoicePaymentService.STATUS_ACTIVE
      );
      insert payment;
      InvoicePaymentService.allowLifecycleWrite = false;
      GlAccount__c debit = new GlAccount__c(
        Name = 'PayDiff Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'PayDiff Credit',
        AccountType__c = 'Liability',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      insert new GlJournal__c(
        Invoice__c = fixture.invoice.Id,
        InvoicePayment__c = payment.Id,
        Amount__c = 1100,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'PAYDIFF', String.valueOf(payment.Id) }
        ),
        JournalLineKey__c = 'pay-diff-payment',
        GenerationUnitKey__c = 'pay-diff-payment-gu',
        DebitSlotKey__c = 'Cash',
        CreditSlotKey__c = 'UnappliedCash',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active',
        IsLocked__c = false
      );
      // Goal に載らない売上側 Current（No.7相当）。入出金除外後 Diff で数える（BUG-092）。
      insert new GlJournal__c(
        Invoice__c = fixture.invoice.Id,
        Amount__c = 1000,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'REVENUE', String.valueOf(fixture.invoice.Id) }
        ),
        JournalLineKey__c = 'pay-diff-revenue',
        GenerationUnitKey__c = 'pay-diff-revenue-gu',
        DebitSlotKey__c = 'DeferredRevenue',
        CreditSlotKey__c = 'Revenue',
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active',
        IsLocked__c = false
      );

      AccountingDiffService.CancelPreview preview = InvoicePaymentService.previewCancel(
        payment.Id,
        null
      );
      System.assertEquals(
        2,
        preview.logicalDeleteCount,
        'Accounting 第4.2節・第8.8節・Core 第7.9.6節: ON は Goal Diff 全体（売上含む）を数える'
      );
      System.assertEquals(0, preview.reverseCount);
    }
  }

  private class InvoiceFixture {
    Invoice__c invoice;
    InvoiceLine__c line;
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
    request.paymentDate = Date.newInstance(2026, 6, 1);
    request.allocations = new List<InvoicePaymentAllocationService.AllocationLine>{
      allocation
    };
    request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
      fixture.invoice.Id
    );
    return request;
  }

  private static InvoiceFixture createInvoice(Boolean confirmed) {
    Account account = ContractTestDataFactory.insertAccount(
      'PaySvc ' + String.valueOf(Crypto.getRandomInteger())
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'paysvc@example.com',
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
      'PaySvc Opp'
    );
    ContractService__c service = new ContractService__c(
      Name = 'PaySvc Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'PaySvc History',
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
      TaxInclusiveAmount__c = 1100,
      BillingAccountSnapShot__c = billingAccount.Id,
      InvoiceTransactionStatus__c = confirmed
        ? InvoiceTransactionStatusService.TX_CONFIRMED
        : InvoiceTransactionStatusService.TX_DRAFT,
      SystemIntegrationDate__c = confirmed ? Date.today() : null
    );
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    InvoiceLine__c line = new InvoiceLine__c(
      Invoice__c = invoice.Id,
      ProductName__c = 'PaySvc Line',
      Amount__c = 1000,
      Quantity__c = 1,
      UnitPrice__c = 1000
    );
    insert line;
    InvoiceFixture fixture = new InvoiceFixture();
    fixture.invoice = invoice;
    fixture.line = line;
    return fixture;
  }

  private static void insertLockedJournal(Id invoiceId, String keySuffix) {
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
      TransactionStatus__c = 'Active',
      IsLocked__c = true
    );
  }

  private static void insertPaymentJournal(
    Id invoiceId,
    Id paymentId,
    Boolean locked,
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
      InvoicePayment__c = paymentId,
      Amount__c = 1,
      IdempotencyKey__c = AccountingDiffService.hashKey(
        new List<String>{ keySuffix, String.valueOf(invoiceId) }
      ),
      DebitSlotKey__c = 'Cash',
      CreditSlotKey__c = 'UnappliedCash',
      DebitAccount__c = debit.Id,
      CreditAccount__c = credit.Id,
      PostingDate__c = Date.newInstance(2026, 6, 1),
      TransactionStatus__c = 'Active',
      IsLocked__c = locked
    );
  }
}
