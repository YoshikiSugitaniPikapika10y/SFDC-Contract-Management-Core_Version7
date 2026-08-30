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

      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id
      );

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
      Id paymentId = InvoicePaymentService.register(request);
      InvoicePayment__c payment = [
        SELECT LastModifiedDate
        FROM InvoicePayment__c
        WHERE Id = :paymentId
      ];

      Id reversalId = InvoicePreviewOpsController.cancelPaymentFromPreview(
        paymentId,
        fixture.invoice.Id,
        null,
        'Duplicate',
        null,
        ContractOptimisticLockUtil.toToken(payment.LastModifiedDate)
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
    }
  }

  @IsTest
  static void getOpsBundle_doesNotReturnDedicatedDocumentList() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);

      InvoicePreviewOpsController.OpsBundleDto bundle = InvoicePreviewOpsController.getOpsBundle(
        fixture.invoice.Id
      );

      System.assertNotEquals(null, bundle.journals, 'Core 第7.7.3節: 仕訳タブは仕訳を返す');
    }
  }

  @IsTest
  static void previewOps_rejectInvoiceOutsideContractService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture own = createInvoice(true);
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
          own.invoice.ContractHistory__c
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
    }
  }

  @IsTest
  static void updateJournalMemo_rejectsJournalOutsideInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture own = createInvoice(true);
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
    }
  }

  @IsTest
  static void updateJournalMemo_rejectsCancelledInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceFixture fixture = createInvoice(true);
      fixture.invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      fixture.invoice.SystemIntegrationDate__c = Date.today();
      InvoiceTransactionStatusService.allowStatusWrite = true;
      update fixture.invoice;
      InvoiceTransactionStatusService.applyCancelled(
        new List<Invoice__c>{ fixture.invoice }
      );
      update fixture.invoice;
      InvoiceTransactionStatusService.allowStatusWrite = false;
      insertJournal(fixture.invoice.Id, false, 'Active', 'MEMOCAN');
      GlJournal__c journal = [
        SELECT Id, Memo__c
        FROM GlJournal__c
        WHERE Invoice__c = :fixture.invoice.Id
        LIMIT 1
      ];

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
        ContractPermissionUtil.FIX_CONFIRMED_INVOICE => true,
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
          'Accounting 第9.5節: 閲覧・編集・確定・Unlock・101〜104 では Lock しない'
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
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      'PayPrev Opp'
    );
    ContractService__c service = new ContractService__c(
      Name = 'PayPrev Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'PayPrev History',
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
      ProductName__c = 'PayPrev Line',
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
        SELECT LastModifiedDate
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
      JournalLockService.testLockExemptFieldApiNames = null;
      InvoiceOpsFieldService.resetCache();
    }
  }
}
