@IsTest
private class AccountingDiffServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void applyForInvoice_rejectsNullInvoice() {
    Boolean thrown = false;
    try {
      AccountingDiffService.applyForInvoice(
        null,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        'PAYMENT_RECORDED:TEST',
        null
      );
    } catch (Exception ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('請求が指定されていません'),
        'Accounting 第8.2節: 対象請求書が無ければGoal・Current・Diffを始めない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void applyForInvoice_skipsGenerationWhenAccountingOff() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        'PAYMENT_RECORDED:OFF',
        null
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE Invoice__c = :invoice.Id
        ],
        'Accounting 第8.2節: OFFなら通常の生成を行わない'
      );
    }
  }

  @IsTest
  static void applyForInvoice_blankOperationKey_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      Boolean thrown = false;
      try {
        AccountingDiffService.applyForInvoice(
          invoice.Id,
          AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
          '',
          null
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('業務操作キーがありません'),
          'Accounting 第8.2節: 業務操作キーが無ければGoal・Current・Diffを始めない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void previewApply_nullInvoice_throws() {
    Boolean thrown = false;
    try {
      AccountingDiffService.previewApply(
        null,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        null
      );
    } catch (Exception ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('請求が指定されていません'),
        'Accounting 第8.2節: 対象請求書が無ければプレビューを始めない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void previewApply_accountingOff_returnsEmpty() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewApply(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        null
      );
      System.assertEquals(
        0,
        preview.logicalDeleteCount,
        'Accounting 第8.2節: OFFなら通常の生成プレビューを行わない'
      );
      System.assertEquals(0, preview.reverseCount);
      System.assert(
        AccountingDiffService.toDisplayText(preview).contains('論理削除件数: 0'),
        'Accounting 第8.5節: 空プレビューは件数0を文言にする'
      );
    }
  }

  @IsTest
  static void applyForInvoice_onUnconfirmedDoesNotGenerate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertDraftInvoiceWithLine();
      enableAccounting();
      seedMaps();
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.BILLING_CONFIRMED.key,
        'TEST_ON_DRAFT_EVENT',
        null
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM GlJournal__c WHERE Invoice__c = :invoice.Id],
        'Accounting 第8.2節: 未確定ならGoalへ進んでも生成しない'
      );
    }
  }

  @IsTest
  static void applyForInvoice_draftSkipsGeneration() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertDraftInvoiceWithLine();
      enableAccounting();
      seedMaps();
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        'TEST_DRAFT',
        null
      );
      System.assertEquals(
        0,
        [SELECT COUNT() FROM GlJournal__c WHERE Invoice__c = :invoice.Id],
        'Accounting 第8.2節: 未確定・未取消なら生成しない'
      );
    }
  }

  @IsTest
  static void previewCancel_nullInvoice_throws() {
    Boolean thrown = false;
    try {
      AccountingDiffService.previewCancel(
        null,
        AccountingEventFixedCatalog.BILLING_CANCELLED.key,
        null,
        null,
        null
      );
    } catch (Exception ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('請求が指定されていません'),
        'Accounting 第8.5節: 対象請求書が無ければ取消プレビューを始めない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void previewCancel_unlockedCurrent_countsLogicalDelete() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      GlAccount__c debit = new GlAccount__c(
        Name = 'Diff Preview AR',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'Diff Preview REV',
        AccountType__c = 'Revenue',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1000,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'PREVIEW_UNLOCKED' }
        ),
        JournalLineKey__c = 'preview-unlocked',
        DebitSlotKey__c = AccountingSlotFixedCatalog.AccountsReceivable.key,
        CreditSlotKey__c = AccountingSlotFixedCatalog.Revenue.key,
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewCancel(
        invoice.Id,
        AccountingEventFixedCatalog.BILLING_CANCELLED.key,
        Date.newInstance(2026, 6, 15),
        null,
        null
      );
      System.assertEquals(
        1,
        preview.logicalDeleteCount,
        'Accounting 第8.5節: 未ロックCurrentは論理削除件数に数える'
      );
      System.assertEquals(0, preview.reverseCount);
      System.assert(
        AccountingDiffService.toDisplayText(preview).contains('論理削除件数: 1'),
        'Accounting 第8.5節: プレビュー文言に論理削除件数を出す'
      );
    }
  }

  @IsTest
  static void applyForInvoice_offCancelLogicallyDeletesCurrent() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      GlAccount__c debit = new GlAccount__c(
        Name = 'Diff OffCancel AR',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'Diff OffCancel REV',
        AccountType__c = 'Revenue',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      GlJournal__c leftover = new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1000,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'OFF_CANCEL' }
        ),
        JournalLineKey__c = 'off-cancel',
        DebitSlotKey__c = AccountingSlotFixedCatalog.AccountsReceivable.key,
        CreditSlotKey__c = AccountingSlotFixedCatalog.Revenue.key,
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Active'
      );
      insert leftover;
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.BILLING_CANCELLED.key,
        'TEST_OFF_CANCEL',
        Date.newInstance(2026, 6, 15)
      );
      leftover = [
        SELECT TransactionStatus__c
        FROM GlJournal__c
        WHERE Id = :leftover.Id
      ];
      System.assertEquals(
        'LogicallyDeleted',
        leftover.TransactionStatus__c,
        'Accounting 第8.2節: OFFでも取消イベントはCurrentを消す'
      );
    }
  }

  @IsTest
  static void applyForInvoice_offCancelLockedWithoutDate_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      insertActiveJournal(invoice.Id, 'off-cancel-locked', true);
      Boolean thrown = false;
      try {
        AccountingDiffService.applyForInvoice(
          invoice.Id,
          AccountingEventFixedCatalog.BILLING_CANCELLED.key,
          'TEST_OFF_CANCEL_LOCKED',
          null
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('取消基準日が必要'),
          'Accounting 第8.5節: ロック済み仕訳の取消は取消基準日が必要'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void applyForInvoice_offCancelLocked_reversesWithCancelDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      GlJournal__c leftover = insertActiveJournal(
        invoice.Id,
        'off-cancel-rev',
        true
      );
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.BILLING_CANCELLED.key,
        'TEST_OFF_CANCEL_REV',
        Date.newInstance(2026, 6, 15)
      );
      leftover = [
        SELECT TransactionStatus__c
        FROM GlJournal__c
        WHERE Id = :leftover.Id
      ];
      System.assertEquals(
        'Cancelled',
        leftover.TransactionStatus__c,
        'Accounting 第8.2節: ロック済みCurrentは逆仕訳し元をCancelledにする'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE OriginalJournal__c = :leftover.Id AND TransactionStatus__c = 'Reversal'
        ],
        'Accounting 第8.5節: ロック済みの取消は逆仕訳を残す'
      );
    }
  }

  @IsTest
  static void applyForInvoice_onCancelled_logicallyDeletesUnlockedCurrent() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      Invoice__c invoice = insertConfirmedInvoice();
      markCancelled(invoice);
      GlJournal__c leftover = insertActiveJournal(
        invoice.Id,
        'on-cancel-unlocked',
        false
      );
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        'TEST_ON_CANCEL_UNLOCKED',
        Date.newInstance(2026, 6, 15)
      );
      leftover = [
        SELECT TransactionStatus__c
        FROM GlJournal__c
        WHERE Id = :leftover.Id
      ];
      System.assertEquals(
        'LogicallyDeleted',
        leftover.TransactionStatus__c,
        'Accounting 第8.2節: 取消済み請求のGoalは空。未ロックCurrentは論理削除する'
      );
    }
  }

  @IsTest
  static void applyForInvoice_onCancelled_reversesLockedCurrent() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      Invoice__c invoice = insertConfirmedInvoice();
      markCancelled(invoice);
      GlJournal__c leftover = insertActiveJournal(
        invoice.Id,
        'on-cancel-locked',
        true
      );
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        'TEST_ON_CANCEL_LOCKED',
        Date.newInstance(2026, 6, 15)
      );
      leftover = [
        SELECT TransactionStatus__c
        FROM GlJournal__c
        WHERE Id = :leftover.Id
      ];
      System.assertEquals(
        'Cancelled',
        leftover.TransactionStatus__c,
        'Accounting 第8.2節: 取消済み請求でロック済みCurrentは逆仕訳する'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE OriginalJournal__c = :leftover.Id AND TransactionStatus__c = 'Reversal'
        ]
      );
    }
  }

  @IsTest
  static void applyForInvoice_duplicateActiveLineKey_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      Invoice__c invoice = insertConfirmedInvoice();
      markCancelled(invoice);
      insertActiveJournal(invoice.Id, 'dup-key', false);
      insertActiveJournal(invoice.Id, 'dup-key', false);
      Boolean thrown = false;
      try {
        AccountingDiffService.applyForInvoice(
          invoice.Id,
          AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
          'TEST_DUP_KEY',
          Date.newInstance(2026, 6, 15)
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('同じ仕訳行キーがCurrent内で重複'),
          'Accounting 第8.2節: Currentの仕訳行キー重複はDiffを始めない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void previewApply_cancelledUnlocked_countsLogicalDelete() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      Invoice__c invoice = insertConfirmedInvoice();
      markCancelled(invoice);
      insertActiveJournal(invoice.Id, 'preview-on-cancel', false);
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewApply(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        Date.newInstance(2026, 6, 15)
      );
      System.assertEquals(
        1,
        preview.logicalDeleteCount,
        'Accounting 第8.2節: 取消済み請求のプレビューは未ロックCurrentを論理削除件数にする'
      );
    }
  }

  @IsTest
  static void previewCancel_lockedWithoutDate_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      insertActiveJournal(invoice.Id, 'preview-locked', true);
      Boolean thrown = false;
      try {
        AccountingDiffService.previewCancel(
          invoice.Id,
          AccountingEventFixedCatalog.BILLING_CANCELLED.key,
          null,
          null,
          null
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('取消基準日が必要'),
          'Accounting 第8.5節: ロック済み仕訳がある取消プレビューは取消基準日が必要'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void previewCancel_locked_countsReverseByDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      insertActiveJournal(invoice.Id, 'preview-rev', true);
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewCancel(
        invoice.Id,
        AccountingEventFixedCatalog.BILLING_CANCELLED.key,
        Date.newInstance(2026, 6, 15),
        null,
        null
      );
      System.assertEquals(
        1,
        preview.reverseCount,
        'Accounting 第8.5節: ロック済みCurrentは逆仕訳件数に数える'
      );
      System.assertEquals(0, preview.logicalDeleteCount);
      System.assertEquals(1, preview.reverseDateCounts.size());
      System.assertEquals(
        Date.newInstance(2026, 6, 15),
        preview.reverseDateCounts[0].reverseDate
      );
      System.assert(
        AccountingDiffService.toDisplayText(preview).contains('2026-06-15: 1件'),
        'Accounting 第8.5節: プレビュー文言に逆仕訳日と件数を出す'
      );
    }
  }

  @IsTest
  static void toDisplayText_futureReverseDate() {
    AccountingDiffService.CancelPreview preview = new AccountingDiffService.CancelPreview();
    preview.logicalDeleteCount = 0;
    preview.reverseCount = 1;
    preview.hasFutureReverseDate = true;
    AccountingDiffService.ReverseDateCount row = new AccountingDiffService.ReverseDateCount();
    row.reverseDate = Date.newInstance(2099, 1, 1);
    row.journalCount = 1;
    preview.reverseDateCounts = new List<AccountingDiffService.ReverseDateCount>{
      row
    };
    String text = AccountingDiffService.toDisplayText(preview);
    System.assert(
      text.contains('将来日付: あり'),
      'Accounting 第8.5節: 将来の逆仕訳日はありと出す'
    );
  }

  @IsTest
  static void applyForInvoice_unknownEvent_throws() {
    Boolean thrown = false;
    try {
      AccountingDiffService.applyForInvoice(
        UserInfo.getUserId(),
        'NOT_A_CATALOG_EVENT',
        'OP',
        null
      );
    } catch (Exception ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('会計イベントキーがCatalogにありません'),
        'Accounting 第4.2節: Catalogに無い会計イベントではDiffを始めない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void applyForInvoice_onConfirmed_persistsManualGoal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      Invoice__c invoice = insertConfirmedInvoice();
      GlManualJournalSetting__c setting = insertManualSetting();
      insert new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = setting.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      Test.startTest();
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        'TEST_MANUAL_GOAL',
        null
      );
      Test.stopTest();
      System.assertEquals(
        false,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE Invoice__c = :invoice.Id AND TransactionStatus__c = 'Active'
        ] == 0,
        'Accounting 第8.2節・第4.6節: ONかつ確定なら手動仕訳もGoalとして残す'
      );
      Integer afterFirst = [
        SELECT COUNT()
        FROM GlJournal__c
        WHERE Invoice__c = :invoice.Id AND TransactionStatus__c = 'Active'
      ];
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        'TEST_MANUAL_GOAL_AGAIN',
        null
      );
      System.assertEquals(
        afterFirst,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE Invoice__c = :invoice.Id AND TransactionStatus__c = 'Active'
        ],
        'Accounting 第8.7節: Goalと一致するCurrentは維持する'
      );
    }
  }

  @IsTest
  static void applyForInvoice_onConfirmed_unlockedMismatch_replacesCurrent() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      Invoice__c invoice = insertConfirmedInvoice();
      GlManualJournalSetting__c setting = insertManualSetting();
      insert new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = setting.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        'TEST_MANUAL_MISMATCH',
        null
      );
      List<GlJournal__c> current = [
        SELECT Id, Amount__c, IsLocked__c
        FROM GlJournal__c
        WHERE Invoice__c = :invoice.Id AND TransactionStatus__c = 'Active'
      ];
      System.assertEquals(false, current.isEmpty());
      Boolean previous = GlJournalTriggerHandler.allowEngineWrite;
      GlJournalTriggerHandler.allowEngineWrite = true;
      try {
        for (GlJournal__c journal : current) {
          journal.Amount__c = journal.Amount__c + 1;
        }
        update current;
      } finally {
        GlJournalTriggerHandler.allowEngineWrite = previous;
      }
      Test.startTest();
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewApply(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        null
      );
      Test.stopTest();
      System.assertEquals(
        false,
        preview.logicalDeleteCount == 0,
        'Accounting 第8.7節: Goalと内容が違う未ロックCurrentは差し替え対象になる'
      );
    }
  }

  @IsTest
  static void applyForInvoice_onConfirmed_lockedMismatch_reversesCurrent() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      Invoice__c invoice = insertConfirmedInvoice();
      GlManualJournalSetting__c setting = insertManualSetting();
      insert new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = setting.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        'TEST_MANUAL_LOCK_MISMATCH',
        null
      );
      List<Id> journalIds = new List<Id>();
      List<GlJournal__c> current = [
        SELECT Id, Amount__c
        FROM GlJournal__c
        WHERE Invoice__c = :invoice.Id AND TransactionStatus__c = 'Active'
      ];
      for (GlJournal__c journal : current) {
        journalIds.add(journal.Id);
      }
      System.assertEquals(false, journalIds.isEmpty());
      Integer locked = JournalLockService.lockForInvoice(
        invoice.Id,
        journalIds,
        AccountingCauseLockService.resolveInvoiceOperationToken(invoice.Id),
        null
      );
      System.assert(locked > 0, 'Accounting 第1.8.1節: 比較対象の元仕訳をロックする');
      Boolean previous = GlJournalTriggerHandler.allowEngineWrite;
      GlJournalTriggerHandler.allowEngineWrite = true;
      try {
        for (GlJournal__c journal : current) {
          journal.Amount__c = journal.Amount__c + 1;
        }
        update current;
      } finally {
        GlJournalTriggerHandler.allowEngineWrite = previous;
      }
      Test.startTest();
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewApply(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        Date.newInstance(2026, 6, 15)
      );
      Test.stopTest();
      System.assertEquals(
        false,
        preview.reverseCount == 0,
        'Accounting 第1.8.1節: Goalと内容が違うロックCurrentは逆仕訳対象になる'
      );
    }
  }

  @IsTest
  static void previewCancel_locked_usesPostingWhenCancelDateEarlier() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      insertActiveJournal(invoice.Id, 'preview-early-cancel', true);
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewCancel(
        invoice.Id,
        AccountingEventFixedCatalog.BILLING_CANCELLED.key,
        Date.newInstance(2026, 5, 1),
        null,
        null
      );
      System.assertEquals(1, preview.reverseCount);
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        preview.reverseDateCounts[0].reverseDate,
        '日付仕様 第7.3節: 取消基準日が計上日より前なら逆仕訳日は計上日'
      );
    }
  }

  @IsTest
  static void hashKey_blankAndNullParts() {
    String withBlank = AccountingDiffService.hashKey(new List<String>{ 'a', '' });
    String withDash = AccountingDiffService.hashKey(new List<String>{ 'a', '-' });
    String withNullList = AccountingDiffService.hashKey(null);
    System.assertEquals(64, withBlank.length());
    System.assertEquals(64, withNullList.length());
    System.assertEquals(
      withBlank,
      withDash,
      'Accounting 第8.7節: 空部品はハイフンと同じ結合'
    );
  }

  @IsTest
  static void applyForInvoice_offCancelLocked_reverseDateKeepsPosting() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      GlJournal__c leftover = insertActiveJournal(
        invoice.Id,
        'off-cancel-early',
        true
      );
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.BILLING_CANCELLED.key,
        'TEST_OFF_EARLY_REV',
        Date.newInstance(2026, 5, 1)
      );
      GlJournal__c reversal = [
        SELECT PostingDate__c, DebitSlotKey__c, CreditSlotKey__c
        FROM GlJournal__c
        WHERE OriginalJournal__c = :leftover.Id AND TransactionStatus__c = 'Reversal'
      ];
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        reversal.PostingDate__c,
        '日付仕様 第7.3節: 取消基準日が前なら逆仕訳の計上日は元の計上日'
      );
      System.assertEquals(
        AccountingSlotFixedCatalog.Revenue.key,
        reversal.DebitSlotKey__c,
        'Accounting 第8.8節: 逆仕訳は借貸を入れ替える'
      );
    }
  }

  @IsTest
  static void applyForInvoice_reversalWithoutOriginal_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      GlJournal__c original = insertActiveJournal(invoice.Id, 'rev-orig', false);
      GlAccount__c debit = new GlAccount__c(
        Name = 'Diff Rev Debit',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      GlAccount__c credit = new GlAccount__c(
        Name = 'Diff Rev Credit',
        AccountType__c = 'Revenue',
        IsActive__c = true
      );
      insert new List<GlAccount__c>{ debit, credit };
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1000,
        IdempotencyKey__c = AccountingDiffService.hashKey(
          new List<String>{ 'REV_ORPHAN' }
        ),
        DebitSlotKey__c = AccountingSlotFixedCatalog.Revenue.key,
        CreditSlotKey__c = AccountingSlotFixedCatalog.AccountsReceivable.key,
        DebitAccount__c = debit.Id,
        CreditAccount__c = credit.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        TransactionStatus__c = 'Reversal'
      );
      Boolean thrown = false;
      try {
        AccountingDiffService.applyForInvoice(
          invoice.Id,
          AccountingEventFixedCatalog.BILLING_CANCELLED.key,
          'TEST_REV_ORPHAN',
          Date.newInstance(2026, 6, 15)
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('取消仕訳の取消元がありません'),
          'Accounting 第8.2節: 取消仕訳に元が無ければDiffを始めない'
        );
      }
      System.assertEquals(true, thrown);
      System.assertNotEquals(null, original.Id);
    }
  }

  @IsTest
  static void hashKey_isStableDigestOfParts() {
    String first = AccountingDiffService.hashKey(new List<String>{ 'a', 'b' });
    String second = AccountingDiffService.hashKey(new List<String>{ 'a', 'b' });
    String other = AccountingDiffService.hashKey(new List<String>{ 'a', 'c' });
    System.assertEquals(
      first,
      second,
      'Accounting 第8.7節: 同じ部品なら同じ冪等キー'
    );
    System.assertNotEquals(
      first,
      other,
      'Accounting 第8.7節: 部品が違えばキーも違う'
    );
    System.assertEquals(64, first.length());
  }

  @IsTest
  static void previewApply_onUnconfirmed_returnsEmpty() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertDraftInvoiceWithLine();
      enableAccounting();
      seedMaps();
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewApply(
        invoice.Id,
        AccountingEventFixedCatalog.BILLING_CONFIRMED.key,
        null
      );
      System.assertEquals(
        0,
        preview.logicalDeleteCount,
        'Accounting 第8.2節: 未確定ならプレビューも通常生成しない'
      );
      System.assertEquals(0, preview.reverseCount);
    }
  }

  @IsTest
  static void applyForInvoice_duplicateReversalOriginal_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      GlJournal__c original = insertActiveJournal(invoice.Id, 'dup-rev-orig', false);
      insertReversalOf(original, 1000, 'DUP_REV_A');
      insertReversalOf(original, 1000, 'DUP_REV_B');
      Boolean thrown = false;
      try {
        AccountingDiffService.applyForInvoice(
          invoice.Id,
          AccountingEventFixedCatalog.BILLING_CANCELLED.key,
          'TEST_DUP_REV',
          Date.newInstance(2026, 6, 15)
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('同じ元仕訳を参照する取消仕訳が複数'),
          'Accounting 第1.8.1節: 取消仕訳は元仕訳から差し引く1件だけ'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void applyForInvoice_reversalAmountMismatch_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      GlJournal__c original = insertActiveJournal(invoice.Id, 'amt-rev-orig', false);
      insertReversalOf(original, 999, 'AMT_REV');
      Boolean thrown = false;
      try {
        AccountingDiffService.applyForInvoice(
          invoice.Id,
          AccountingEventFixedCatalog.BILLING_CANCELLED.key,
          'TEST_AMT_REV',
          Date.newInstance(2026, 6, 15)
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('取消仕訳の金額が元仕訳と一致しません'),
          'Accounting 第1.8.1節: 取消仕訳は元と同額で差し引く'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void applyForInvoice_onCancelled_billingCancelAppliesAudit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      Invoice__c invoice = insertConfirmedInvoice();
      markCancelled(invoice);
      GlJournal__c leftover = insertActiveJournal(
        invoice.Id,
        'on-billing-cancel-audit',
        false
      );
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.BILLING_CANCELLED.key,
        'TEST_ON_BILLING_CANCEL_AUDIT',
        Date.newInstance(2026, 6, 15)
      );
      leftover = [
        SELECT TransactionStatus__c, BusinessOperationKey__c
        FROM GlJournal__c
        WHERE Id = :leftover.Id
      ];
      System.assertEquals(
        'LogicallyDeleted',
        leftover.TransactionStatus__c,
        'Accounting 第8.2節: 取消済み請求のGoalは空。未ロックCurrentは論理削除する'
      );
      System.assertEquals(
        'TEST_ON_BILLING_CANCEL_AUDIT',
        leftover.BusinessOperationKey__c,
        'Accounting 第8.1節: 取消仕訳には実際の請求取消を記録する'
      );
    }
  }

  @IsTest
  static void previewCancel_paymentCancelled_excludingPaymentCounts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      InvoicePayment__c payment = insertNonInvoicePayment(invoice.Id);
      insertActiveJournalForPayment(invoice.Id, 'pay-excl', payment.Id, false);
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewCancel(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_CANCELLED.key,
        null,
        payment.Id,
        null
      );
      System.assertEquals(
        1,
        preview.logicalDeleteCount,
        'Accounting 第8.4節: 入出金取消は原因から外した入出金の仕訳だけをDiffする'
      );
      System.assertEquals(0, preview.reverseCount);
    }
  }

  @IsTest
  static void previewCancel_manualJournal_excludingHeaderCounts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      GlManualJournalSetting__c setting = insertManualSetting();
      GlManualJournalHeader__c header = new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = setting.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      insert header;
      insertActiveJournalForHeader(invoice.Id, 'hdr-excl', header.Id, false);
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewCancel(
        invoice.Id,
        AccountingEventFixedCatalog.MANUAL_JOURNAL.key,
        null,
        null,
        header.Id
      );
      System.assertEquals(
        1,
        preview.logicalDeleteCount,
        'Accounting 第1.9節: 手動仕訳取消は当該ヘッダーを原因から外してDiffする'
      );
    }
  }

  @IsTest
  static void applyForInvoice_offPaymentCancelled_logicallyDeletes() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      InvoicePayment__c payment = insertNonInvoicePayment(invoice.Id);
      GlJournal__c leftover = insertActiveJournalForPayment(
        invoice.Id,
        'off-pay-cancel',
        payment.Id,
        false
      );
      Boolean previous = InvoicePaymentService.allowLifecycleWrite;
      InvoicePaymentService.allowLifecycleWrite = true;
      try {
        payment.PaymentTransactionStatus__c = InvoicePaymentService.STATUS_CANCELLED;
        update payment;
      } finally {
        InvoicePaymentService.allowLifecycleWrite = previous;
      }
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_CANCELLED.key,
        'TEST_OFF_PAY_CANCEL',
        Date.newInstance(2026, 6, 15)
      );
      leftover = [
        SELECT TransactionStatus__c, CancellationReasonText__c
        FROM GlJournal__c
        WHERE Id = :leftover.Id
      ];
      System.assertEquals(
        'LogicallyDeleted',
        leftover.TransactionStatus__c,
        'Accounting 第8.2節: OFFでも入出金取消は対象Currentを消す'
      );
    }
  }

  @IsTest
  static void applyForInvoice_offManualCancel_logicallyDeletes() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      GlManualJournalSetting__c setting = insertManualSetting();
      GlManualJournalHeader__c header = new GlManualJournalHeader__c(
        Invoice__c = invoice.Id,
        GlManualJournalSetting__c = setting.Id,
        PostingDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 100,
        TransactionStatus__c = 'Active'
      );
      insert header;
      GlJournal__c leftover = insertActiveJournalForHeader(
        invoice.Id,
        'off-mj-cancel',
        header.Id,
        false
      );
      header.TransactionStatus__c = 'Cancelled';
      update header;
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.MANUAL_JOURNAL.key,
        'TEST_OFF_MJ_CANCEL',
        Date.newInstance(2026, 6, 15)
      );
      leftover = [
        SELECT TransactionStatus__c
        FROM GlJournal__c
        WHERE Id = :leftover.Id
      ];
      System.assertEquals(
        'LogicallyDeleted',
        leftover.TransactionStatus__c,
        'Accounting 第8.2節: OFFでも手動仕訳取消は対象Currentを消す'
      );
    }
  }

  @IsTest
  static void applyForInvoice_billingConfirmed_emptyInvoiceDoesNotThrow() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      enableAccounting();
      seedMaps();
      Invoice__c invoice = insertConfirmedInvoice();
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.BILLING_CONFIRMED.key,
        'TEST_CONFIRM_EMPTY',
        null
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE Invoice__c = :invoice.Id
        ],
        'Accounting 第8.4節: 自動計算値が0なら0円仕訳を作らない'
      );
    }
  }

  @IsTest
  static void toDisplayText_emptyReverseDates_saysNone() {
    AccountingDiffService.CancelPreview preview = new AccountingDiffService.CancelPreview();
    preview.logicalDeleteCount = 2;
    preview.reverseCount = 0;
    preview.hasFutureReverseDate = false;
    preview.reverseDateCounts = null;
    String text = AccountingDiffService.toDisplayText(preview);
    System.assert(
      text.contains('論理削除件数: 2'),
      'Accounting 第8.5節: プレビュー文言に論理削除件数を出す'
    );
    System.assert(
      text.contains('逆仕訳件数: 0'),
      'Accounting 第8.5節: プレビュー文言に逆仕訳件数を出す'
    );
    System.assert(
      text.contains('なし'),
      'Accounting 第8.5節: 逆仕訳日が無ければなしと出す'
    );
    System.assert(
      text.contains('将来日付: なし'),
      'Accounting 第8.5節: 将来の逆仕訳日が無ければなしと出す'
    );
  }

  @IsTest
  static void previewApply_unknownEvent_throws() {
    Boolean thrown = false;
    try {
      AccountingDiffService.previewApply(
        UserInfo.getUserId(),
        'NOT_A_CATALOG_EVENT',
        null
      );
    } catch (Exception ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('会計イベントキーがCatalogにありません'),
        'Accounting 第4.2節: Catalogに無い会計イベントではプレビューを始めない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void previewCancel_unknownEvent_throws() {
    Boolean thrown = false;
    try {
      AccountingDiffService.previewCancel(
        UserInfo.getUserId(),
        'NOT_A_CATALOG_EVENT',
        null,
        null,
        null
      );
    } catch (Exception ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('会計イベントキーがCatalogにありません'),
        'Accounting 第4.2節: Catalogに無い会計イベントでは取消プレビューを始めない'
      );
    }
    System.assertEquals(true, thrown);
  }

  private static Invoice__c insertConfirmedInvoice() {
    Account account = ContractTestDataFactory.insertAccount(
      'Diff ' + String.valueOf(Crypto.getRandomInteger())
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'diff@example.com',
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
      'Diff Opp'
    );
    ContractService__c service = new ContractService__c(
      Name = 'Diff Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Diff History',
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
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      SystemIntegrationDate__c = Date.today()
    );
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    return invoice;
  }

  private static Invoice__c insertDraftInvoiceWithLine() {
    Account account = ContractTestDataFactory.insertAccount(
      'DiffLine ' + String.valueOf(Crypto.getRandomInteger())
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'diffline@example.com',
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
      Name = 'Diff Line Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Diff Line History',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
    insert history;
    Product2 product = ContractTestDataFactory.buildProduct('Diff Line Product');
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
      BillingAccountSnapShot__c = billingAccount.Id,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT
    );
    insert invoice;
    insert new InvoiceLine__c(
      Invoice__c = invoice.Id,
      ContractProduct__c = contractProduct.Id,
      ProductName__c = 'Diff Line',
      Amount__c = 1000,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME,
      AcceptanceEndDate__c = Date.newInstance(2026, 6, 30),
      ServicePeriodStartDate__c = Date.newInstance(2026, 6, 1),
      ServicePeriodEndDate__c = Date.newInstance(2026, 6, 30)
    );
    return invoice;
  }

  private static GlManualJournalSetting__c insertManualSetting() {
    GlAccount__c debit = new GlAccount__c(
      Name = 'Diff MJ Debit ' + String.valueOf(Crypto.getRandomInteger()),
      AccountType__c = 'Expense',
      IsActive__c = true
    );
    GlAccount__c credit = new GlAccount__c(
      Name = 'Diff MJ Credit ' + String.valueOf(Crypto.getRandomInteger()),
      AccountType__c = 'Asset',
      IsActive__c = true
    );
    insert new List<GlAccount__c>{ debit, credit };
    GlManualJournalSetting__c setting = new GlManualJournalSetting__c(
      Name = 'Diff 手動',
      DebitSlotKey__c = 'FxLoss',
      DebitAccount__c = debit.Id,
      CreditSlotKey__c = 'AccountsReceivable',
      CreditAccount__c = credit.Id,
      Description__c = 'Diff manual',
      IsActive__c = true
    );
    insert setting;
    return setting;
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

  private static InvoicePayment__c insertNonInvoicePayment(Id invoiceId) {
    InvoicePayment__c payment = new InvoicePayment__c(
      Invoice__c = invoiceId,
      Amount__c = 100,
      PaymentPurpose__c = InvoicePaymentService.PURPOSE_NON_INVOICE,
      PaymentDate__c = Date.newInstance(2026, 6, 1)
    );
    insert payment;
    return payment;
  }

  private static GlJournal__c insertReversalOf(
    GlJournal__c original,
    Decimal amount,
    String keyPart
  ) {
    GlAccount__c debit = new GlAccount__c(
      Name = 'Diff Rev ' + String.valueOf(Crypto.getRandomInteger()),
      AccountType__c = 'Revenue',
      IsActive__c = true
    );
    GlAccount__c credit = new GlAccount__c(
      Name = 'Diff Rev ' + String.valueOf(Crypto.getRandomInteger()),
      AccountType__c = 'Asset',
      IsActive__c = true
    );
    insert new List<GlAccount__c>{ debit, credit };
    GlJournal__c reversal = new GlJournal__c(
      Invoice__c = original.Invoice__c,
      Amount__c = amount,
      IdempotencyKey__c = AccountingDiffService.hashKey(
        new List<String>{ keyPart, String.valueOf(Crypto.getRandomInteger()) }
      ),
      DebitSlotKey__c = AccountingSlotFixedCatalog.Revenue.key,
      CreditSlotKey__c = AccountingSlotFixedCatalog.AccountsReceivable.key,
      DebitAccount__c = debit.Id,
      CreditAccount__c = credit.Id,
      PostingDate__c = Date.newInstance(2026, 6, 1),
      TransactionStatus__c = 'Reversal',
      OriginalJournal__c = original.Id
    );
    insert reversal;
    return reversal;
  }

  private static GlJournal__c insertActiveJournalForPayment(
    Id invoiceId,
    String lineKey,
    Id paymentId,
    Boolean locked
  ) {
    GlJournal__c journal = baseActiveJournal(invoiceId, lineKey, locked);
    journal.InvoicePayment__c = paymentId;
    insert journal;
    return journal;
  }

  private static GlJournal__c insertActiveJournalForHeader(
    Id invoiceId,
    String lineKey,
    Id headerId,
    Boolean locked
  ) {
    GlJournal__c journal = baseActiveJournal(invoiceId, lineKey, locked);
    journal.GlManualJournalHeader__c = headerId;
    insert journal;
    return journal;
  }

  private static GlJournal__c insertActiveJournal(
    Id invoiceId,
    String lineKey,
    Boolean locked
  ) {
    GlJournal__c journal = baseActiveJournal(invoiceId, lineKey, locked);
    insert journal;
    return journal;
  }

  private static GlJournal__c baseActiveJournal(
    Id invoiceId,
    String lineKey,
    Boolean locked
  ) {
    GlAccount__c debit = new GlAccount__c(
      Name = 'Diff J ' + String.valueOf(Crypto.getRandomInteger()),
      AccountType__c = 'Asset',
      IsActive__c = true
    );
    GlAccount__c credit = new GlAccount__c(
      Name = 'Diff J ' + String.valueOf(Crypto.getRandomInteger()),
      AccountType__c = 'Revenue',
      IsActive__c = true
    );
    insert new List<GlAccount__c>{ debit, credit };
    GlJournal__c journal = new GlJournal__c(
      Invoice__c = invoiceId,
      Amount__c = 1000,
      IdempotencyKey__c = AccountingDiffService.hashKey(
        new List<String>{ lineKey, String.valueOf(Crypto.getRandomInteger()) }
      ),
      JournalLineKey__c = lineKey,
      DebitSlotKey__c = AccountingSlotFixedCatalog.AccountsReceivable.key,
      CreditSlotKey__c = AccountingSlotFixedCatalog.Revenue.key,
      DebitAccount__c = debit.Id,
      CreditAccount__c = credit.Id,
      PostingDate__c = Date.newInstance(2026, 6, 1),
      TransactionStatus__c = 'Active',
      IsLocked__c = locked
    );
    return journal;
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
          Name = 'Diff ' + name,
          AccountType__c = types.get(name),
          IsActive__c = true
        )
      );
    }
    insert accounts;
    for (GlAccount__c account : accounts) {
      accountIds.put(account.Name.substringAfter('Diff '), account.Id);
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
          Name = 'Diff ' + slot,
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
