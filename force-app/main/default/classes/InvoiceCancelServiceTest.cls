@IsTest
private class InvoiceCancelServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void cancelConfirmed_copiesHeaderAdjustmentFlags() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Account account = ContractTestDataFactory.insertAccount(
        'CancelFlag ' + String.valueOf(Crypto.getRandomInteger())
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'cancelflag@example.com',
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
        'CancelFlag Opp'
      );
      ContractService__c service = new ContractService__c(
        Name = 'CancelFlag Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = 0.1
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'CancelFlag History',
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
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
        SystemIntegrationDate__c = Date.today(),
        IsAmountAdjusted__c = true,
        IsSplitMoved__c = true,
        IsManuallyAdjusted__c = true
      );
      ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
      insert new InvoiceLine__c(
        Invoice__c = invoice.Id,
        ProductName__c = 'CancelFlag Line',
        Amount__c = 1000,
        Quantity__c = 1,
        UnitPrice__c = 1000
      );

      InvoiceCancelService.CancelRequest request = new InvoiceCancelService.CancelRequest();
      request.invoiceId = invoice.Id;
      request.cancellationReason = 'Duplicate';
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      InvoiceCancelService.CancelResult result = InvoiceCancelService.cancelConfirmed(
        request
      );

      Invoice__c correction = [
        SELECT
          IsAmountAdjusted__c,
          IsSplitMoved__c,
          IsManuallyAdjusted__c,
          InvoiceTransactionStatus__c
        FROM Invoice__c
        WHERE Id = :result.correctionInvoiceId
      ];
      System.assertEquals(
        InvoiceTransactionStatusService.TX_DRAFT,
        correction.InvoiceTransactionStatus__c
      );
      System.assertEquals(
        true,
        correction.IsAmountAdjusted__c,
        'Core 第7.9.3節: 訂正用へヘッダーの手動調整フラグをコピーする'
      );
      System.assertEquals(true, correction.IsSplitMoved__c);
      System.assertEquals(true, correction.IsManuallyAdjusted__c);
      System.assertEquals(
        false,
        result.requiresCustomerNotice,
        'Core 第7.10節: 未送付の取消では取消連絡案内を出さない'
      );
    }
  }

  @IsTest
  static void cancelConfirmed_doesNotCopyMergeKey_andAssignsNewName() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Account account = ContractTestDataFactory.insertAccount(
        'CancelMerge ' + String.valueOf(Crypto.getRandomInteger())
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'cancelmerge@example.com',
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
        'CancelMerge Opp'
      );
      ContractService__c service = new ContractService__c(
        Name = 'CancelMerge Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = 0.1
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'CancelMerge History',
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
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
        SystemIntegrationDate__c = Date.today(),
        MergeKey__c = 'INV|CANCEL-MERGE-KEY'
      );
      ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
      insert new InvoiceLine__c(
        Invoice__c = invoice.Id,
        ProductName__c = 'CancelMerge Line',
        Amount__c = 1000,
        Quantity__c = 1,
        UnitPrice__c = 1000
      );
      String originalName = [SELECT Name FROM Invoice__c WHERE Id = :invoice.Id]
        .Name;

      InvoiceCancelService.CancelRequest request = new InvoiceCancelService.CancelRequest();
      request.invoiceId = invoice.Id;
      request.cancellationReason = 'Duplicate';
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      InvoiceCancelService.CancelResult result = InvoiceCancelService.cancelConfirmed(
        request
      );

      Invoice__c correction = [
        SELECT Name, MergeKey__c
        FROM Invoice__c
        WHERE Id = :result.correctionInvoiceId
      ];
      System.assertEquals(
        null,
        correction.MergeKey__c,
        'Core 第7.9.3節: 訂正用請求へ MergeKey をコピーしない'
      );
      System.assertNotEquals(
        originalName,
        correction.Name,
        'Core 第7.9.3節: 新しい請求名は自動採番する'
      );
      System.assertEquals(
        'INV|CANCEL-MERGE-KEY',
        [SELECT MergeKey__c FROM Invoice__c WHERE Id = :invoice.Id].MergeKey__c,
        'Core 第7.9.3節: 元請求の MergeKey は監査用に残す'
      );
    }
  }

  @IsTest
  static void cancelConfirmed_writesSameOperationKey_andRetryDoesNotDuplicate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice('CancelKey');
      String operationKey = AccountingCauseLockService.issueOperationKey();
      String staleToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      InvoiceCancelService.CancelRequest request = new InvoiceCancelService.CancelRequest();
      request.invoiceId = invoice.Id;
      request.cancellationReason = 'Duplicate';
      request.businessOperationKey = operationKey;
      request.expectedToken = staleToken;

      InvoiceCancelService.CancelResult first = InvoiceCancelService.cancelConfirmed(
        request
      );
      Invoice__c original = [
        SELECT BusinessOperationKey__c, InvoiceTransactionStatus__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      Invoice__c correction = [
        SELECT BusinessOperationKey__c
        FROM Invoice__c
        WHERE Id = :first.correctionInvoiceId
      ];
      System.assertEquals(
        operationKey,
        original.BusinessOperationKey__c,
        'Core 第7.9.3節: 同じ業務操作キーを元請求へ書く'
      );
      System.assertEquals(
        operationKey,
        correction.BusinessOperationKey__c,
        'Core 第7.9.3節: 同じ業務操作キーを訂正用請求へ書く'
      );

      InvoiceCancelService.CancelResult retry = InvoiceCancelService.cancelConfirmed(
        request
      );
      System.assertEquals(
        first.correctionInvoiceId,
        retry.correctionInvoiceId,
        'Core 第7.9.3節: 同じキーの再試行では訂正用請求を重複作成しない'
      );
      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE BusinessOperationKey__c = :operationKey
        ],
        'Core 第7.9.3節: 同じキーの再試行でも請求は元と訂正の2件'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'CancelInvoice'
            AND BusinessOperationKey__c = :operationKey
        ],
        '共通基盤第12章: CancelInvoiceは成功1回に1行。再試行は2行目を作らない'
      );
    }
  }

  @IsTest
  static void cancelConfirmed_requiresCancellationDateWhenLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice('CancelDate');
      insertLockedJournal(invoice.Id, null);
      InvoiceCancelService.CancelRequest request = new InvoiceCancelService.CancelRequest();
      request.invoiceId = invoice.Id;
      request.cancellationReason = 'Duplicate';
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Boolean thrown = false;
      try {
        InvoiceCancelService.cancelConfirmed(request);
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('取消基準日が必要'),
          'Core 第7.9.6節、日付仕様 第7.3節: ロック済み仕訳がある取消は未入力をエラーにする'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void cancelConfirmed_flagsCustomerNoticeWhenSent() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice('CancelSent');
      InvoiceTransactionStatusService.applyDelivery(
        invoice,
        InvoiceTransactionStatusService.DELIVERY_SENT,
        Date.today()
      );
      InvoiceTransactionStatusService.allowStatusWrite = true;
      InvoiceLockUtil.allowLockedStatusWrite = true;
      try {
        update invoice;
      } finally {
        InvoiceTransactionStatusService.allowStatusWrite = false;
        InvoiceLockUtil.allowLockedStatusWrite = false;
      }

      InvoiceCancelService.CancelRequest request = new InvoiceCancelService.CancelRequest();
      request.invoiceId = invoice.Id;
      request.cancellationReason = 'Duplicate';
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      InvoiceCancelService.CancelResult result = InvoiceCancelService.cancelConfirmed(
        request
      );
      System.assertEquals(
        true,
        result.requiresCustomerNotice,
        'Core 第7.9.3節・第7.10節: 送付済み請求の取消は顧客への取消連絡が必要と返す'
      );
    }
  }

  @IsTest
  static void previewConfirmed_countsLogicalDeleteAndReverseByDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice('PreviewCounts');
      insertJournal(invoice.Id, false, Date.newInstance(2026, 6, 1), 'UNLOCK');
      insertJournal(invoice.Id, true, Date.newInstance(2026, 6, 1), 'LOCKPAST');
      insertJournal(
        invoice.Id,
        true,
        Date.today().addMonths(2),
        'LOCKFUTURE'
      );

      AccountingDiffService.CancelPreview preview = InvoiceCancelService.previewConfirmed(
        invoice.Id,
        Date.today()
      );

      System.assertEquals(
        1,
        preview.logicalDeleteCount,
        'Core 第7.9.6節: 未ロックは論理削除件数に数える'
      );
      System.assertEquals(
        2,
        preview.reverseCount,
        'Core 第7.9.6節: ロック済みは逆仕訳件数に数える'
      );
      System.assertEquals(2, preview.reverseDateCounts.size());
      System.assertEquals(Date.today(), preview.reverseDateCounts[0].reverseDate);
      System.assertEquals(1, preview.reverseDateCounts[0].journalCount);
      System.assertEquals(
        Date.today().addMonths(2),
        preview.reverseDateCounts[1].reverseDate
      );
      System.assertEquals(
        true,
        preview.hasFutureReverseDate,
        'Core 第7.9.6節、日付仕様 第7.3節: 将来日付の有無を出す'
      );
      System.assert(
        preview.displayText.contains('論理削除件数: 1'),
        'Core 第7.9.6節: 論理削除件数を表示する'
      );
      System.assert(preview.displayText.contains('逆仕訳件数: 2'));
      System.assert(preview.displayText.contains('将来日付: あり'));

      InvoiceCancelService.CancelRequest request = new InvoiceCancelService.CancelRequest();
      request.invoiceId = invoice.Id;
      request.cancellationReason = 'Duplicate';
      request.cancellationDate = Date.today();
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      InvoiceCancelService.CancelResult result = InvoiceCancelService.cancelConfirmed(
        request
      );
      System.assertEquals(
        preview.displayText,
        result.journalPreview.displayText,
        'Core 第7.9.6節: 実行後も同じ結果を表示する'
      );
    }
  }

  @IsTest
  static void cancelConfirmed_rejectsBlankExpectedToken() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice('CancelBlankTok');
      InvoiceCancelService.CancelRequest request = new InvoiceCancelService.CancelRequest();
      request.invoiceId = invoice.Id;
      request.cancellationReason = 'Duplicate';
      request.expectedToken = null;
      Boolean thrown = false;
      try {
        InvoiceCancelService.cancelConfirmed(request);
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
  static void cancelConfirmed_requiresCancelInvoice_notSubstitutedByConfirmPaymentManualOrIrregular() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice('CancelPerm');
      InvoiceCancelService.CancelRequest request = new InvoiceCancelService.CancelRequest();
      request.invoiceId = invoice.Id;
      request.cancellationReason = 'Duplicate';
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      ContractPermissionUtil.testAllowAll = false;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.CONFIRM_INVOICE => true,
        ContractPermissionUtil.INVOICE_PAYMENT => true,
        ContractPermissionUtil.MANUAL_JOURNAL => true,
        ContractPermissionUtil.FIX_CONFIRMED_INVOICE => true,
        ContractPermissionUtil.FIX_CONTRACT => true,
        ContractPermissionUtil.DELETE_RECORDS => true,
        ContractPermissionUtil.MIGRATE_ALL => true,
        ContractPermissionUtil.CANCEL_INVOICE => false
      };
      Boolean thrown = false;
      try {
        InvoiceCancelService.cancelConfirmed(request);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '確定済み請求を取り消す権限がありません。',
          ex.getMessage(),
          'Core 第7.9.3節: 請求確定・入金・手動仕訳・101〜104 では代替しない'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
        ContractPermissionUtil.testAllowAll = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void previewConfirmed_requiresCancelInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice('PreviewPerm');
      ContractPermissionUtil.testAllowAll = false;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.VIEW_INVOICE => true,
        ContractPermissionUtil.CONFIRM_INVOICE => true,
        ContractPermissionUtil.CANCEL_INVOICE => false
      };
      Boolean thrown = false;
      try {
        InvoiceCancelService.previewConfirmed(invoice.Id, Date.today());
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '確定済み請求を取り消す権限がありません。',
          ex.getMessage(),
          '共通基盤 第10.4節: 確定取消プレビューは 15。09・11 では代替しない'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
        ContractPermissionUtil.testAllowAll = true;
      }
      System.assertEquals(true, thrown);
    }
  }

  private static Invoice__c insertConfirmedInvoice(String suffix) {
    Account account = ContractTestDataFactory.insertAccount(
      suffix + ' ' + String.valueOf(Crypto.getRandomInteger())
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = suffix.toLowerCase() + '@example.com',
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
      suffix + ' Opp'
    );
    ContractService__c service = new ContractService__c(
      Name = suffix + ' Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = suffix + ' History',
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
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      SystemIntegrationDate__c = Date.today()
    );
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    insert new InvoiceLine__c(
      Invoice__c = invoice.Id,
      ProductName__c = suffix + ' Line',
      Amount__c = 1000,
      Quantity__c = 1,
      UnitPrice__c = 1000
    );
    return invoice;
  }

  private static void insertLockedJournal(Id invoiceId, Id headerId) {
    insertJournal(invoiceId, true, Date.newInstance(2026, 6, 1), 'CANCELDATE');
  }

  private static void insertJournal(
    Id invoiceId,
    Boolean locked,
    Date postingDate,
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
      PostingDate__c = postingDate,
      TransactionStatus__c = 'Active',
      IsLocked__c = locked
    );
  }
}
