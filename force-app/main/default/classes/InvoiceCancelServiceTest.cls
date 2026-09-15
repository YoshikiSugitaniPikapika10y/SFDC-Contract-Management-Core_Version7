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
      Invoice__c invoice = insertConfirmedInvoice('CancelFlag', true, true, true, null);
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
          InvoiceTransactionStatus__c,
          CollectionRefundStatus__c,
          CancellationReason__c,
          CancellationReasonText__c,
          SystemIntegrationDate__c
        FROM Invoice__c
        WHERE Id = :result.correctionInvoiceId
      ];
      Invoice__c original = [
        SELECT
          InvoiceTransactionStatus__c,
          CancellationReason__c,
          CancellationReasonText__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        InvoiceTransactionStatusService.TX_CANCELLED,
        original.InvoiceTransactionStatus__c,
        'Core 第7.9.3節手順1: 元請求の取引状態を取消済みにする'
      );
      System.assertEquals(
        'Duplicate',
        original.CancellationReason__c,
        'Core 第7.9.5節: 取消理由は元請求へ保持する'
      );
      System.assertEquals(
        InvoiceTransactionStatusService.TX_DRAFT,
        correction.InvoiceTransactionStatus__c,
        'Core 第7.9.3節手順3: 訂正用の請求取引状態は Draft'
      );
      System.assertEquals(
        InvoiceTransactionStatusService.COLLECTION_NOT_STARTED,
        correction.CollectionRefundStatus__c,
        'Core 第7.9.3節手順3: 訂正用の回収・返金状態は NotStarted'
      );
      System.assertEquals(
        null,
        correction.CancellationReason__c,
        'Core 第7.9.3節手順3: 取消情報は訂正用へ引き継がない'
      );
      System.assertEquals(
        null,
        correction.CancellationReasonText__c,
        'Core 第7.9.3節手順3: 取消理由テキストは訂正用へ引き継がない'
      );
      System.assertEquals(
        null,
        correction.SystemIntegrationDate__c,
        'Core 第7.9.3節手順3: 確定日は訂正用へ引き継がない'
      );
      System.assertEquals(
        true,
        correction.IsAmountAdjusted__c,
        'Core 第7.9.3節: 訂正用へヘッダーの手動調整フラグをコピーする'
      );
      System.assertEquals(
        true,
        correction.IsSplitMoved__c,
        'Core 第7.9.3節: 訂正用へ分割・移動フラグをコピーする'
      );
      System.assertEquals(
        true,
        correction.IsManuallyAdjusted__c,
        'Core 第7.9.3節: 訂正用へ手動調整フラグをコピーする'
      );
      System.assertEquals(
        false,
        result.requiresCustomerNotice,
        'Core 第7.9.3節・第7.10節: 送付済みでなければ取消連絡案内を出さない'
      );
    }
  }

  @IsTest
  static void cancelConfirmed_knownLockedInvoice_skipsSecondLock() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c first = insertConfirmedInvoice('CancelKnownLockA');
      Invoice__c second = insertConfirmedInvoice('CancelKnownLockB');
      Invoice__c locked = AccountingCauseLockService.lockInvoice(first.Id);
      InvoiceCancelService.CancelRequest known = new InvoiceCancelService.CancelRequest();
      known.invoiceId = first.Id;
      known.cancellationReason = 'Duplicate';
      known.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        first.Id
      );
      known.knownLockedInvoice = locked;
      InvoiceCancelService.CancelRequest full = new InvoiceCancelService.CancelRequest();
      full.invoiceId = second.Id;
      full.cancellationReason = 'Duplicate';
      full.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        second.Id
      );

      Test.startTest();
      Integer beforeFull = Limits.getQueries();
      InvoiceCancelService.cancelConfirmed(full);
      Integer usedFull = Limits.getQueries() - beforeFull;
      Integer beforeKnown = Limits.getQueries();
      InvoiceCancelService.CancelResult knownResult = InvoiceCancelService.cancelConfirmed(
        known
      );
      Integer usedKnown = Limits.getQueries() - beforeKnown;
      Test.stopTest();

      System.assert(
        usedKnown < usedFull,
        'Core 第12.4節・Accounting 第8.2節: ロック済み請求を取り直さない'
      );
      System.assertEquals(first.Id, knownResult.cancelledInvoiceId);
      System.assertEquals(
        InvoiceTransactionStatusService.TX_CANCELLED,
        [
          SELECT InvoiceTransactionStatus__c
          FROM Invoice__c
          WHERE Id = :first.Id
        ]
        .InvoiceTransactionStatus__c,
        'Core 第7.9.3節: 範囲内の確定済みは取り消す'
      );
    }
  }

  @IsTest
  static void cancelConfirmed_reusesCurrentAndCancelReasonWithoutPreviewGoal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice('CancelReuseCur');
      InvoiceCancelService.CancelRequest request = new InvoiceCancelService.CancelRequest();
      request.invoiceId = invoice.Id;
      request.cancellationReason = 'Duplicate';
      request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      AccountingCurrentService.currentLoadSelectCount = 0;
      AccountingDiffService.cancelReasonSelectCount = 0;
      AccountingDiffService.invoiceCopySourceSelectCount = 0;
      Test.startTest();
      InvoiceCancelService.CancelResult result = InvoiceCancelService.cancelConfirmed(
        request
      );
      Test.stopTest();
      System.assertEquals(invoice.Id, result.cancelledInvoiceId);
      System.assertEquals(
        0,
        result.journalPreview.reverseCount,
        'Accounting 第8.8節: 実行結果に件数内訳を出さない'
      );
      System.assertEquals(
        1,
        AccountingCurrentService.currentLoadSelectCount,
        'Accounting 第8.2節: 取消実行はCurrentを取り直さない'
      );
      System.assertEquals(
        0,
        AccountingDiffService.cancelReasonSelectCount,
        'Core 第7.9.5節: 元請求へ書いた取消理由を仕訳ごとに取り直さない'
      );
      System.assertEquals(
        0,
        AccountingDiffService.invoiceCopySourceSelectCount,
        'Accounting 第8.2節: ロック済み請求のコピーFromを取り直さない'
      );
    }
  }

  @IsTest
  static void cancelConfirmed_reusesLockedInvoiceLastModifiedForVersion() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice('CancelVerReuse');
      Invoice__c locked = AccountingCauseLockService.lockInvoice(invoice.Id);
      String expectedToken = ContractOptimisticLockUtil.toToken(
        AccountingCauseLockService.resolveInvoiceOperationDatetimes(
            new Set<Id>{ locked.Id },
            new Map<Id, Datetime>{ locked.Id => locked.LastModifiedDate }
          )
          .get(locked.Id)
      );
      Test.startTest();
      Integer beforeKnown = Limits.getQueries();
      AccountingCauseLockService.assertInvoiceOperationUnchanged(
        locked.Id,
        expectedToken,
        locked.LastModifiedDate
      );
      Integer usedKnown = Limits.getQueries() - beforeKnown;
      Integer beforeFull = Limits.getQueries();
      AccountingCauseLockService.assertInvoiceOperationUnchanged(
        locked.Id,
        expectedToken
      );
      Integer usedFull = Limits.getQueries() - beforeFull;
      Test.stopTest();
      System.assert(
        usedKnown < usedFull,
        'Core 第12.4節・第7.9.7節: 取消はロック済み請求の版比較を取り直さない'
      );
    }
  }

  @IsTest
  static void cancelConfirmed_doesNotCopyMergeKey_andAssignsNewName() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice(
        'CancelMerge',
        false,
        false,
        false,
        'INV|CANCEL-MERGE-KEY'
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
  static void cancelConfirmed_copiesOriginalExtraMemo_andDoesNotOverwriteWithDefinition() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice('CancelExtraKeep');
      update new Invoice__c(Id = invoice.Id, Memo__c = 'BOARD-MEMO');
      insert new FieldCopyDefinition__c(
        Name = 'Cancel_Inv_Memo_Keep',
        TargetObject__c = InvoiceProductFieldCopyService.TARGET_INVOICE,
        SourceObject__c = InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c'
      );
      FieldCopyDefinitionService.resetCache();
      InvoiceProductFieldCopyService.resetCache();
      InvoiceOpsFieldService.setCachedRowsForTest(
        new List<InvoiceOpsField__mdt>{
          new InvoiceOpsField__mdt(
            DeveloperName = 'Cancel_Inv_Memo',
            Active__c = true,
            TargetObject__c = 'Invoice__c',
            FieldApiName__c = 'Memo__c',
            SortOrder__c = 10
          )
        }
      );
      try {
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
          SELECT Memo__c
          FROM Invoice__c
          WHERE Id = :result.correctionInvoiceId
        ];
        System.assertEquals(
          'BOARD-MEMO',
          correction.Memo__c,
          'Core 第7.9.3節・第11.4.2節: 訂正用は元の顧客追加項目をコピーし、空欄だけ定義スタンプする'
        );
      } finally {
        InvoiceOpsFieldService.resetCache();
        FieldCopyDefinitionService.resetCache();
        InvoiceProductFieldCopyService.resetCache();
      }
    }
  }

  @IsTest
  static void cancelConfirmed_stampsCopyDefinitionOntoBlankExtraMemo() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice('CancelExtraFill');
      ContractHistory__c history = [
        SELECT Name
        FROM ContractHistory__c
        WHERE Id IN (SELECT ContractHistory__c FROM Invoice__c WHERE Id = :invoice.Id)
      ];
      insert new FieldCopyDefinition__c(
        Name = 'Cancel_Inv_Memo_Fill',
        TargetObject__c = InvoiceProductFieldCopyService.TARGET_INVOICE,
        SourceObject__c = InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c'
      );
      FieldCopyDefinitionService.resetCache();
      InvoiceProductFieldCopyService.resetCache();
      try {
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
          SELECT Memo__c
          FROM Invoice__c
          WHERE Id = :result.correctionInvoiceId
        ];
        System.assertEquals(
          history.Name,
          correction.Memo__c,
          'Core 第11.4.2節: 訂正用の空欄だけ定義スタンプする'
        );
      } finally {
        FieldCopyDefinitionService.resetCache();
        InvoiceProductFieldCopyService.resetCache();
      }
    }
  }

  @IsTest
  static void cancelConfirmed_reusesLockedInvoiceForCorrectionCloneWithoutSecondInvoiceSelect() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice('CancelCloneReuse');
      insert new FieldCopyDefinition__c(
        Name = 'Cancel_Clone_Hist_Name',
        TargetObject__c = InvoiceProductFieldCopyService.TARGET_INVOICE,
        SourceObject__c = InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c'
      );
      FieldCopyDefinitionService.resetCache();
      InvoiceProductFieldCopyService.resetCache();
      Invoice__c locked = [
        SELECT Id
        FROM Invoice__c
        WHERE Id = :invoice.Id
        WITH SYSTEM_MODE
      ];
      try {
        InvoiceCancelService.CancelRequest request = new InvoiceCancelService.CancelRequest();
        request.invoiceId = locked.Id;
        request.cancellationReason = 'Duplicate';
        request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
          locked.Id
        );
        InvoiceCancelService.correctionInvoiceSelectCount = 0;
        Test.startTest();
        InvoiceCancelService.CancelResult result = InvoiceCancelService.cancelConfirmed(
          request
        );
        Test.stopTest();
        Invoice__c correction = [
          SELECT Memo__c, ContractHistory__c
          FROM Invoice__c
          WHERE Id = :result.correctionInvoiceId
        ];
        ContractHistory__c history = [
          SELECT Name
          FROM ContractHistory__c
          WHERE Id = :correction.ContractHistory__c
        ];
        System.assertEquals(
          0,
          InvoiceCancelService.correctionInvoiceSelectCount,
          'Core 第12.4節: 訂正cloneはロック行の関連Fromで足り、同じ請求を取り直さない'
        );
        System.assertEquals(
          history.Name,
          correction.Memo__c,
          'Core 第11.4.2節: 訂正用の空欄スタンプ結果は変えない'
        );
        System.assertNotEquals(
          null,
          result.correctionInvoiceId,
          'Core 第7.9.3節: 訂正用請求を作る'
        );
      } finally {
        FieldCopyDefinitionService.resetCache();
        InvoiceProductFieldCopyService.resetCache();
      }
    }
  }

  @IsTest
  static void cancelConfirmed_reusesCorrectionCopySourcesWithoutSecondHistorySelect() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice('CancelCopyReuse');
      insert new FieldCopyDefinition__c(
        Name = 'Cancel_Inv_Hist_Name',
        TargetObject__c = InvoiceProductFieldCopyService.TARGET_INVOICE,
        SourceObject__c = InvoiceProductFieldCopyService.OBJECT_CONTRACT_HISTORY,
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c'
      );
      FieldCopyDefinitionService.resetCache();
      InvoiceProductFieldCopyService.resetCache();
      try {
        InvoiceCancelService.CancelRequest request = new InvoiceCancelService.CancelRequest();
        request.invoiceId = invoice.Id;
        request.cancellationReason = 'Duplicate';
        request.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
          invoice.Id
        );
        Test.startTest();
        InvoiceCancelService.CancelResult result = InvoiceCancelService.cancelConfirmed(
          request
        );
        Test.stopTest();
        Invoice__c correction = [
          SELECT Memo__c, ContractHistory__c
          FROM Invoice__c
          WHERE Id = :result.correctionInvoiceId
        ];
        ContractHistory__c history = [
          SELECT Name
          FROM ContractHistory__c
          WHERE Id = :correction.ContractHistory__c
        ];
        System.assertEquals(
          history.Name,
          correction.Memo__c,
          'Core 第11.4.2節: 訂正用の空欄スタンプ結果は変えない'
        );
        System.assertNotEquals(
          null,
          result.correctionInvoiceId,
          'Core 第7.9.3節: 訂正用請求を作る'
        );
      } finally {
        FieldCopyDefinitionService.resetCache();
        InvoiceProductFieldCopyService.resetCache();
      }
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
        '共通基盤第12章（Core 第2.5節）: CancelInvoiceは成功1回に1行。再試行は2行目を作らない'
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
        System.assertEquals(
          'ロック済み仕訳がある取消では取消基準日が必要です。',
          ex.getMessage(),
          'Core 第7.9.6節、共通基盤 第7.3節: ロック済み仕訳がある取消は未入力をエラーにする'
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
      System.assertEquals(
        InvoiceTransactionStatusService.TX_CANCELLED,
        [
          SELECT InvoiceTransactionStatus__c
          FROM Invoice__c
          WHERE Id = :invoice.Id
        ]
        .InvoiceTransactionStatus__c,
        'Core 第7.9.3節手順1: 送付済みでも元請求は取消済みになる'
      );
      System.assertEquals(
        InvoiceTransactionStatusService.TX_DRAFT,
        [
          SELECT InvoiceTransactionStatus__c
          FROM Invoice__c
          WHERE Id = :result.correctionInvoiceId
        ]
        .InvoiceTransactionStatus__c,
        'Core 第7.9.3節手順3: 送付済み取消でも訂正用は未確定'
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
        'Core 第7.9.6節・Accounting 第8.5節: プレビューは未ロックを論理削除件数に数える（確認画面には出さない）'
      );
      System.assertEquals(
        2,
        preview.reverseCount,
        'Core 第7.9.6節・Accounting 第8.5節: プレビューはロック済みを逆仕訳件数に数える（確認画面には出さない）'
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
        'Core 第7.9.6節、共通基盤 第7.3節: プレビューは将来日付の有無を返す（確認画面には出さない）'
      );
      System.assertEquals(
        '',
        preview.displayText,
        '共通基盤 第7.3節・Core 第7.9.6節・Accounting 第8.8節: 内部件数・日付内訳・将来日付は請求取消画面へ表示しない'
      );

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
        0,
        result.journalPreview.reverseCount,
        'Core 第7.9.6節・Accounting 第8.8節: 実行後の成功表示に逆仕訳件数を出さない'
      );
      System.assertEquals(
        0,
        result.journalPreview.logicalDeleteCount,
        'Core 第7.9.6節・Accounting 第8.8節: 実行後の成功表示に論理削除件数を出さない'
      );
    }
  }

  @IsTest
  static void cancelConfirmed_rejectsBlankInvoiceAndReason() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      InvoiceCancelService.CancelRequest blankInvoice = new InvoiceCancelService.CancelRequest();
      blankInvoice.cancellationReason = 'Duplicate';
      Boolean invoiceThrown = false;
      try {
        InvoiceCancelService.cancelConfirmed(blankInvoice);
      } catch (InvoiceCancelService.CancelException ex) {
        invoiceThrown = true;
        System.assertEquals(
          '取消する請求が指定されていません。',
          ex.getMessage(),
          'Core 第7.9.3節: 取消する請求が無ければ始めない'
        );
      }
      System.assertEquals(true, invoiceThrown);

      Boolean previewThrown = false;
      try {
        InvoiceCancelService.previewConfirmed(null, Date.today());
      } catch (InvoiceCancelService.CancelException ex) {
        previewThrown = true;
        System.assertEquals(
          '取消する請求が指定されていません。',
          ex.getMessage(),
          'Core 第7.9.6節: プレビューも取消する請求が無ければ始めない'
        );
      }
      System.assertEquals(true, previewThrown);

      Invoice__c invoice = insertConfirmedInvoice('CancelReason');
      InvoiceCancelService.CancelRequest blankReason = new InvoiceCancelService.CancelRequest();
      blankReason.invoiceId = invoice.Id;
      blankReason.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        invoice.Id
      );
      Boolean reasonThrown = false;
      try {
        InvoiceCancelService.cancelConfirmed(blankReason);
      } catch (InvoiceCancelService.CancelException ex) {
        reasonThrown = true;
        System.assertEquals(
          '取消理由を入力してください。',
          ex.getMessage(),
          'Core 第7.9.5節: 取消理由を指定する'
        );
      }
      System.assertEquals(true, reasonThrown);
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
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage(),
          'Core 第7.9.7節: 比較値未指定は拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void cancelConfirmed_rejectsDraft() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();

      Invoice__c draftInvoice = insertConfirmedInvoice('CancelDraft');
      InvoiceTransactionStatusService.allowStatusWrite = true;
      InvoiceLockUtil.allowLockedStatusWrite = true;
      try {
        draftInvoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT;
        update draftInvoice;
      } finally {
        InvoiceTransactionStatusService.allowStatusWrite = false;
        InvoiceLockUtil.allowLockedStatusWrite = false;
      }
      InvoiceCancelService.CancelRequest draftRequest = new InvoiceCancelService.CancelRequest();
      draftRequest.invoiceId = draftInvoice.Id;
      draftRequest.cancellationReason = 'Duplicate';
      draftRequest.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        draftInvoice.Id
      );
      Boolean draftThrown = false;
      try {
        InvoiceCancelService.cancelConfirmed(draftRequest);
      } catch (InvoiceCancelService.CancelException ex) {
        draftThrown = true;
        System.assertEquals(
          '確定済みの請求だけ取消できます。',
          ex.getMessage(),
          'Core 第7.9.3節: 取消できるのは確定済み請求だけ'
        );
      }
      System.assertEquals(true, draftThrown);
    }
  }

  @IsTest
  static void cancelConfirmed_rejectsActivePayment() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c paymentInvoice = insertConfirmedInvoice('CancelPay');
      InvoicePaymentService.allowLifecycleWrite = true;
      try {
        insert new InvoicePayment__c(
          Invoice__c = paymentInvoice.Id,
          Amount__c = 1100,
          PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
          PaymentDate__c = Date.newInstance(2026, 6, 1),
          PaymentTransactionStatus__c = InvoicePaymentService.STATUS_ACTIVE
        );
      } finally {
        InvoicePaymentService.allowLifecycleWrite = false;
      }
      InvoiceCancelService.CancelRequest paymentRequest = new InvoiceCancelService.CancelRequest();
      paymentRequest.invoiceId = paymentInvoice.Id;
      paymentRequest.cancellationReason = 'Duplicate';
      paymentRequest.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        paymentInvoice.Id
      );
      Boolean paymentThrown = false;
      try {
        InvoiceCancelService.cancelConfirmed(paymentRequest);
      } catch (InvoiceCancelService.CancelException ex) {
        paymentThrown = true;
        System.assertEquals(
          '有効な請求入出金がある請求は取消できません。',
          ex.getMessage(),
          'Core 第7.9.3節: Purposeを問わず有効な請求入出金が0件であること'
        );
      }
      System.assertEquals(true, paymentThrown);
    }
  }

  @IsTest
  static void cancelConfirmed_rejectsActiveManualJournal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c manualInvoice = insertConfirmedInvoice('CancelMan');
      GlAccount__c debit = new GlAccount__c(
        Name = 'CancelMan Debit',
        AccountType__c = 'Expense',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'CancelMan Credit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlManualJournalSetting__c setting = new GlManualJournalSetting__c(
        Name = 'CancelMan Setting',
        DebitSlotKey__c = 'FxLoss',
        DebitAccount__c = debit.Id,
        CreditSlotKey__c = 'AccountsReceivable',
        CreditAccount__c = credit.Id,
        Description__c = '請求取消ゲート用',
        IsActive__c = true
      );
      insert setting;
      insert new GlManualJournalHeader__c(
        Invoice__c = manualInvoice.Id,
        GlManualJournalSetting__c = setting.Id,
        PostingDate__c = Date.today(),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      InvoiceCancelService.CancelRequest manualRequest = new InvoiceCancelService.CancelRequest();
      manualRequest.invoiceId = manualInvoice.Id;
      manualRequest.cancellationReason = 'Duplicate';
      manualRequest.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        manualInvoice.Id
      );
      Boolean manualThrown = false;
      try {
        InvoiceCancelService.cancelConfirmed(manualRequest);
      } catch (InvoiceCancelService.CancelException ex) {
        manualThrown = true;
        System.assertEquals(
          '有効な手動仕訳がある請求は取消できません。',
          ex.getMessage(),
          'Core 第7.9.3節: 有効な手動仕訳ヘッダーが0件であること'
        );
      }
      System.assertEquals(true, manualThrown);
    }
  }

  @IsTest
  static void cancelConfirmed_rejectsOtherWithoutText() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c otherInvoice = insertConfirmedInvoice('CancelOther');
      InvoiceCancelService.CancelRequest otherRequest = new InvoiceCancelService.CancelRequest();
      otherRequest.invoiceId = otherInvoice.Id;
      otherRequest.cancellationReason = 'Other';
      otherRequest.expectedToken = AccountingCauseLockService.resolveInvoiceOperationToken(
        otherInvoice.Id
      );
      Boolean otherThrown = false;
      try {
        InvoiceCancelService.cancelConfirmed(otherRequest);
      } catch (InvoiceCancelService.CancelException ex) {
        otherThrown = true;
        System.assertEquals(
          '取消理由がその他のときは内容を入力してください。',
          ex.getMessage(),
          'Core 第7.9.5節: その他の場合だけ理由テキストを必須とする'
        );
      }
      System.assertEquals(true, otherThrown);
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
        ContractPermissionUtil.MIGRATE_ALL => true,
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
          'Core 第7.9.3節: 請求確定・入金・手動仕訳・101〜103 では代替しない'
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
    return insertConfirmedInvoice(suffix, false, false, false, null);
  }

  private static Invoice__c insertConfirmedInvoice(
    String suffix,
    Boolean amountAdjusted,
    Boolean splitMoved,
    Boolean manuallyAdjusted,
    String mergeKey
  ) {
    Account account = ContractTestDataFactory.insertAccount(
      suffix + ' ' + String.valueOf(Crypto.getRandomInteger())
    );
    ContractService__c service = ContractTestDataFactory.insertContractService(
      account.Id,
      suffix + ' Service'
    );
    ContractHistory__c history = new ContractHistory__c(
      Name = suffix + ' History',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2026, 6, 30),
      EffectiveDate__c = Date.newInstance(2026, 6, 1)
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
    insert history;
    Product2 product = ContractTestDataFactory.buildProduct(suffix + ' Product');
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
      BillingAccountSnapShot__c = service.BiilingAcccount__c
    );
    ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
    invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
    invoice.SystemIntegrationDate__c = Date.today();
    invoice.IsAmountAdjusted__c = amountAdjusted;
    invoice.IsSplitMoved__c = splitMoved;
    invoice.IsManuallyAdjusted__c = manuallyAdjusted;
    invoice.MergeKey__c = mergeKey;
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    InvoiceLine__c invoiceLine = new InvoiceLine__c(
      Invoice__c = invoice.Id,
      ProductName__c = suffix + ' Line',
      Amount__c = 1000,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME,
      AcceptanceEndDate__c = Date.newInstance(2026, 6, 30),
      ServicePeriodStartDate__c = Date.newInstance(2026, 6, 1),
      ServicePeriodEndDate__c = Date.newInstance(2026, 6, 30)
    );
    ContractTestDataFactory.applyRequiredFields(invoiceLine);
    insert invoiceLine;
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
