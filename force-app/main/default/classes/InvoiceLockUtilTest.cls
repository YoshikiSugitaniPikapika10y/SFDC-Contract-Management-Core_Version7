@IsTest
private class InvoiceLockUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  @IsTest
  static void lockHelpers_andAsserts() {
    Invoice__c unlocked = new Invoice__c();
    System.assertEquals(false, InvoiceLockUtil.isLocked(unlocked));
    System.assertEquals(false, InvoiceLockUtil.isInvoiced(unlocked));
    System.assertEquals(false, InvoiceLockUtil.isExported(unlocked));

    Invoice__c invoiced = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      SystemIntegrationDate__c = Date.today()
    );
    System.assertEquals(true, InvoiceLockUtil.isInvoiced(invoiced));
    System.assertEquals(true, InvoiceLockUtil.isLocked(invoiced));

    Invoice__c exported = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_COMPLETED,
      PaymentClearingCompletedDate__c = Date.today()
    );
    System.assertEquals(true, InvoiceLockUtil.isExported(exported));
    System.assertEquals(true, InvoiceLockUtil.isLocked(exported));

    Invoice__c cancelled = new Invoice__c(
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CANCELLED
    );
    System.assertEquals(true, InvoiceLockUtil.isLocked(cancelled));
    System.assertEquals(false, InvoiceLockUtil.isActiveConfirmed(cancelled));
    System.assertEquals(false, InvoiceLockUtil.isInvoiced(cancelled));
    System.assertEquals(
      '有効な確定済み請求があるため、この契約履歴の請求を削除・再生成できません。',
      InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
      'Core 第5.3節: 差し戻しは有効な確定済み請求で止める'
    );
    System.assertEquals(
      false,
      InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE.contains('請求済またはエクスポート済'),
      'Core 第5.3節: 旧状態名では出さない'
    );

    Id fakeInvoiceId =
      Invoice__c.SObjectType.getDescribe().getKeyPrefix() + '000000000002AAA';
    Invoice__c priorLocked = new Invoice__c(
      Id = fakeInvoiceId,
      Amount__c = 1000,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      SystemIntegrationDate__c = Date.today()
    );
    Invoice__c paymentOnly = new Invoice__c(
      Id = fakeInvoiceId,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_IN_PROGRESS,
      SystemIntegrationDate__c = Date.today(),
      PaymentClearingCompletedDate__c = null
    );
    InvoiceLockUtil.testCanBypassLockedDml = false;
    InvoiceLockUtil.testLockExemptFieldApiNames = null;
    InvoiceLockUtil.blockLockedRowDml(
      new List<Invoice__c>{ paymentOnly },
      new Map<Id, Invoice__c>{ fakeInvoiceId => priorLocked }
    );
    System.assertEquals(
      false,
      paymentOnly.hasErrors(),
      'ロック中の回収ステータス更新は許可'
    );

    Invoice__c amountChange = new Invoice__c(
      Id = fakeInvoiceId,
      Amount__c = 2000,
      SystemIntegrationDate__c = Date.today()
    );
    InvoiceLockUtil.blockLockedRowDml(
      new List<Invoice__c>{ amountChange },
      new Map<Id, Invoice__c>{ fakeInvoiceId => priorLocked }
    );
    System.assertEquals(
      true,
      amountChange.hasErrors(),
      '除外リスト外の金額変更は拒否'
    );

    InvoiceLockUtil.testCanBypassLockedDml = true;
    System.assertEquals(true, InvoiceLockUtil.canBypassLockedDml());
    InvoiceLockUtil.testCanBypassLockedDml = false;
    System.assertEquals(false, InvoiceLockUtil.canBypassLockedDml());
    InvoiceLockUtil.testCanBypassLockedDml = null;

    Invoice__c row = new Invoice__c();
    InvoiceLockUtil.testCanBypassLockedDml = false;
    InvoiceLockUtil.blockLockedRowDml(
      new List<Invoice__c>{ row },
      new Map<Id, Invoice__c>{
        UserInfo.getUserId() => new Invoice__c(
          SystemIntegrationDate__c = Date.today()
        )
      }
    );
    // oldMap に無い ID のときは自身で判定（未ロック）
    InvoiceLockUtil.blockLockedRowDml(new List<Invoice__c>{ row }, null);

    InvoiceLockUtil.assertNoLockedInvoices(new Set<Id>());
    System.assertEquals(
      false,
      InvoiceLockUtil.hasLockedInvoices(new Set<Id>())
    );

    InvoiceLockUtil.testLockExemptFieldApiNames = null;
    Set<String> defaults = InvoiceLockUtil.resolveLockExemptFieldNames();
    System.assertEquals(true, defaults.contains('PaymentInclusiveTotal__c'));
    System.assertEquals(
      true,
      defaults.contains('PaymentClearingCompletedDate__c')
    );
    System.assertEquals(true, defaults.contains('InvoiceTransactionStatus__c'));
  }

  @IsTest
  static void canBypassLockedDelete_allows104Alone() {
    InvoiceLockUtil.testCanBypassLockedDml = null;
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.MIGRATE_ALL => true
    };
    try {
      Invoice__c confirmed = new Invoice__c(
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED
      );
      InvoiceLockUtil.blockLockedRowDml(
        new List<Invoice__c>{ confirmed },
        null
      );
      System.assertEquals(
        false,
        confirmed.hasErrors(),
        '共通基盤 第3.6節: 101 単独で確定済み請求の削除を通す'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
  }

  @IsTest
  static void assertVersionEditable_blocksWhenInvoiceLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderedFixture fixture = insertOrderedFixture('Lock Util');
      Invoice__c invoice = new Invoice__c(
        ContractService__c = fixture.service.Id,
        ContractHistory__c = fixture.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100,
        BillingAccountSnapShot__c = fixture.service.BiilingAcccount__c
      );
      ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = Date.today();
      ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);

      Boolean thrown = false;
      try {
        InvoiceLockUtil.assertVersionEditable(fixture.history.Id);
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.VERSION_EDIT_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);

      thrown = false;
      try {
        InvoiceLockUtil.assertNoLockedInvoices(new Set<Id>{ fixture.history.Id });
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        true,
        InvoiceLockUtil.hasLockedInvoices(new Set<Id>{ fixture.history.Id })
      );

      InvoiceLockUtil.testCanBypassLockedDml = false;
      Invoice__c lockedUpdate = [
        SELECT
          Id,
          Amount__c,
          SystemIntegrationDate__c,
          PaymentClearingCompletedDate__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      lockedUpdate.Amount__c = 2000;
      Database.SaveResult[] results = Database.update(
        new List<Invoice__c>{ lockedUpdate },
        false
      );
      System.assertEquals(false, results[0].isSuccess());

      Boolean invoiceThrown = false;
      try {
        InvoiceLockUtil.assertInvoiceEditable(invoice.Id);
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        invoiceThrown = true;
        System.assertEquals(
          InvoiceLockUtil.INVOICE_EDIT_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, invoiceThrown, 'ロック請求は編集不可');

      Invoice__c unlockedSibling = new Invoice__c(
        ContractService__c = fixture.service.Id,
        ContractHistory__c = fixture.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 7, 1),
        Amount__c = 500,
        TaxAmount__c = 50,
        BillingAccountSnapShot__c = fixture.service.BiilingAcccount__c
      );
      ContractTestDataFactory.applyInvoiceInsertSeedStatuses(unlockedSibling);
      insert unlockedSibling;
      InvoiceLockUtil.assertInvoiceEditable(unlockedSibling.Id);
      InvoiceLockUtil.assertInvoicesEditable(new Set<Id>{ unlockedSibling.Id });

      Database.DeleteResult[] lockedDelete = Database.delete(
        new List<Invoice__c>{ invoice },
        false
      );
      System.assertEquals(
        false,
        lockedDelete[0].isSuccess(),
        'ロック請求の削除は拒否'
      );

      delete unlockedSibling;
    }
  }

  @IsTest
  static void blockLockedRowDml_allowsClearingExportWhenNotIntegrated() {
    Id fakeInvoiceId =
      Invoice__c.SObjectType.getDescribe().getKeyPrefix() + '000000000003AAA';
    Invoice__c priorExportedOnly = new Invoice__c(
      Id = fakeInvoiceId,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_COMPLETED,
      SystemIntegrationDate__c = null,
      PaymentClearingCompletedDate__c = Date.today()
    );
    Invoice__c clearExport = new Invoice__c(
      Id = fakeInvoiceId,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_COMPLETED,
      SystemIntegrationDate__c = null,
      PaymentClearingCompletedDate__c = null
    );

    InvoiceLockUtil.testCanBypassLockedDml = false;
    InvoiceLockUtil.blockLockedRowDml(
      new List<Invoice__c>{ clearExport },
      new Map<Id, Invoice__c>{ fakeInvoiceId => priorExportedOnly }
    );
    System.assertEquals(
      false,
      clearExport.hasErrors(),
      '連携未済の消込完了日クリアは許可'
    );
  }

  @IsTest
  static void resolveLockExemptFieldNames_honorsTestOverride() {
    InvoiceLockUtil.testLockExemptFieldApiNames = 'Amount__c, TaxAmount__c';
    Set<String> names = InvoiceLockUtil.resolveLockExemptFieldNames();
    System.assertEquals(true, names.contains('Amount__c'));
    System.assertEquals(true, names.contains('TaxAmount__c'));
    System.assertEquals(false, names.contains('PaymentInclusiveTotal__c'));

    InvoiceLockUtil.testLockExemptFieldApiNames = ' , ExtraField__c ,  ';
    names = InvoiceLockUtil.resolveLockExemptFieldNames();
    System.assertEquals(true, names.contains('ExtraField__c'));

    InvoiceLockUtil.testLockExemptFieldApiNames = '';
    try {
      InvoiceLockUtil.resolveLockExemptFieldNames();
      System.assert(false, '空のロック除外はシードへ落とさずエラー');
    } catch (InvoiceLockUtil.LockExemptException ex) {
      System.assertEquals(
        InvoiceLockUtil.MISSING_LOCK_EXEMPT_MESSAGE,
        ex.getMessage()
      );
    }

    InvoiceLockUtil.testLockExemptFieldApiNames = null;
  }

  @IsTest
  static void assertNoLockedInvoices_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderedFixture fixture = insertOrderedFixture('Lock Message');
      Invoice__c invoice = new Invoice__c(
        ContractService__c = fixture.service.Id,
        ContractHistory__c = fixture.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100,
        BillingAccountSnapShot__c = fixture.service.BiilingAcccount__c
      );
      ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_COMPLETED;
      invoice.PaymentClearingCompletedDate__c = Date.today();
      ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);

      InvoiceLockUtil.testCanBypassLockedDml = false;
      Boolean thrown = false;
      try {
        InvoiceLockUtil.assertNoLockedInvoices(new Set<Id>{ fixture.history.Id });
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);

      thrown = false;
      try {
        InvoiceLockUtil.assertVersionEditable(fixture.history.Id);
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.VERSION_EDIT_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void nullInvoice_helpersReturnFalseAndSkipAsserts() {
    System.assertEquals(false, InvoiceLockUtil.isLocked(null));
    System.assertEquals(false, InvoiceLockUtil.isInvoiced(null));
    System.assertEquals(false, InvoiceLockUtil.isExported(null));
    InvoiceLockUtil.assertInvoiceEditable((Id) null);
    InvoiceLockUtil.assertInvoiceEditable((Invoice__c) null);
    InvoiceLockUtil.assertVersionEditable(null);
    InvoiceLockUtil.assertInvoicesEditable(null);
    InvoiceLockUtil.assertInvoicesEditable(new Set<Id>());
    System.assertEquals(
      true,
      InvoiceLockUtil.queryHistoryIdsWithLockedInvoices(null).isEmpty()
    );
  }

  @IsTest
  static void invoiceProductUpdate_allowedWhenParentInvoiceLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      OrderedFixture fixture = insertOrderedFixture('Period Line Lock Abolish');
      String bucket = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
        null,
        fixture.history.Id,
        Date.newInstance(2026, 6, 1),
        null
      );
      InvoiceProduct__c periodLine = new InvoiceProduct__c(
        ContractHistory__c = fixture.history.Id,
        ContractProduct__c = fixture.contractProduct.Id,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30),
        InvoiceBucketKey__c = bucket,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000
      );
      insert periodLine;
      Invoice__c invoice = new Invoice__c(
        ContractService__c = fixture.service.Id,
        ContractHistory__c = fixture.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100,
        BillingAccountSnapShot__c = fixture.service.BiilingAcccount__c
      );
      ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = Date.today();
      ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);

      periodLine.Amount__c = 1100;
      update periodLine;

      System.assertEquals(
        1100,
        [
          SELECT Amount__c
          FROM InvoiceProduct__c
          WHERE Id = :periodLine.Id
        ]
        .Amount__c,
        '期間明細ロック廃止: 請求ロックでも期間明細更新は拒否されない'
      );
    }
  }

  @IsTest
  static void seedLockExemptFields_excludesAppliedTaxRoundingMode() {
    Set<String> fields = new Set<String>(
      InvoiceLockUtil.SEED_LOCK_EXEMPT_FIELDS.split(',')
    );
    System.assertEquals(
      false,
      fields.contains('AppliedTaxRoundingMode__c'),
      'Core 第11.6節: シードに税額丸め適用値を含めない'
    );
    System.assertEquals(
      true,
      fields.contains('Memo__c'),
      'Core 第11.6節: シードにメモを含める'
    );
  }

  @IsTest
  static void resolveLockExemptFieldNames_addsEnabledTagTargetsOnlyForAccounting() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new GlAccountingTagRule__c(
        Name = 'Lock Tag',
        TagKey__c = 'lock-tag-exempt',
        TagLabel__c = 'AR残',
        Expression__c = 'AR',
        ComparisonOperator__c = 'NE',
        ComparisonValue__c = 0,
        TargetFieldApiName__c = 'IsSplitMoved__c',
        IsEnabled__c = true
      );
      insert new GlAccountingTagRule__c(
        Name = 'Lock Tag Off',
        TagKey__c = 'lock-tag-disabled',
        TargetFieldApiName__c = 'IsManuallyAdjusted__c',
        IsEnabled__c = false
      );
      InvoiceLockUtil.testLockExemptFieldApiNames = InvoiceLockUtil.SEED_LOCK_EXEMPT_FIELDS;
      InvoiceLockUtil.allowAccountingTagLockExempt = false;
      Set<String> withoutFlag = InvoiceLockUtil.resolveLockExemptFieldNames();
      System.assertEquals(
        false,
        withoutFlag.contains('IsSplitMoved__c'),
        'Core 第11.6節: 画面・通常更新ではタグルール保存先を除外しない'
      );

      InvoiceLockUtil.allowAccountingTagLockExempt = true;
      Set<String> withFlag = InvoiceLockUtil.resolveLockExemptFieldNames();
      System.assertEquals(
        true,
        withFlag.contains('IsSplitMoved__c'),
        'Core 第11.6節: Accounting内部更新に限り有効タグルールの保存先を動的除外する'
      );
      System.assertEquals(
        false,
        withFlag.contains('IsManuallyAdjusted__c'),
        'Core 第11.6節: 無効ルールの保存先は除外しない'
      );
      InvoiceLockUtil.allowAccountingTagLockExempt = false;
      InvoiceLockUtil.testLockExemptFieldApiNames = null;
    }
  }

  @IsTest
  static void blockLockedRowDml_allowsAccountingTagUpdateOnly() {
    Id fakeInvoiceId =
      Invoice__c.SObjectType.getDescribe().getKeyPrefix() + '000000000003AAA';
    Invoice__c prior = new Invoice__c(
      Id = fakeInvoiceId,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      SystemIntegrationDate__c = Date.today(),
      IsSplitMoved__c = false
    );
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new GlAccountingTagRule__c(
        Name = 'Lock Tag Dml',
        TagKey__c = 'lock-tag-dml',
        TagLabel__c = 'AR残',
        Expression__c = 'AR',
        ComparisonOperator__c = 'NE',
        ComparisonValue__c = 0,
        TargetFieldApiName__c = 'IsSplitMoved__c',
        IsEnabled__c = true
      );
      InvoiceLockUtil.testCanBypassLockedDml = false;
      InvoiceLockUtil.testLockExemptFieldApiNames = InvoiceLockUtil.SEED_LOCK_EXEMPT_FIELDS;
      InvoiceLockUtil.allowAccountingTagLockExempt = false;
      Invoice__c userChange = new Invoice__c(
        Id = fakeInvoiceId,
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
        SystemIntegrationDate__c = Date.today(),
        IsSplitMoved__c = true
      );
      InvoiceLockUtil.blockLockedRowDml(
        new List<Invoice__c>{ userChange },
        new Map<Id, Invoice__c>{ fakeInvoiceId => prior }
      );
      System.assertEquals(
        true,
        userChange.hasErrors(),
        'Core 第11.6節: 確定済み請求のタグチェックボックスを利用者が直接は変えられない'
      );

      InvoiceLockUtil.allowAccountingTagLockExempt = true;
      Invoice__c accountingChange = new Invoice__c(
        Id = fakeInvoiceId,
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
        SystemIntegrationDate__c = Date.today(),
        IsSplitMoved__c = true
      );
      InvoiceLockUtil.blockLockedRowDml(
        new List<Invoice__c>{ accountingChange },
        new Map<Id, Invoice__c>{ fakeInvoiceId => prior }
      );
      System.assertEquals(
        false,
        accountingChange.hasErrors(),
        'Core 第11.6節: Accounting内部更新なら有効タグルールの保存先だけロック除外する'
      );
      InvoiceLockUtil.allowAccountingTagLockExempt = false;
      InvoiceLockUtil.testCanBypassLockedDml = null;
      InvoiceLockUtil.testLockExemptFieldApiNames = null;
    }
  }

  @IsTest
  static void blockLockedRowDml_rejectsConfirmedInvoiceDateEvenIfExempt() {
    Id fakeInvoiceId =
      Invoice__c.SObjectType.getDescribe().getKeyPrefix() + '000000000004AAA';
    Invoice__c prior = new Invoice__c(
      Id = fakeInvoiceId,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      SystemIntegrationDate__c = Date.today()
    );
    Invoice__c changed = new Invoice__c(
      Id = fakeInvoiceId,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      InvoiceDate__c = Date.newInstance(2026, 7, 1),
      SystemIntegrationDate__c = Date.today()
    );
    InvoiceLockUtil.testCanBypassLockedDml = false;
    InvoiceLockUtil.testLockExemptFieldApiNames =
      InvoiceLockUtil.SEED_LOCK_EXEMPT_FIELDS + ',InvoiceDate__c';
    InvoiceLockUtil.blockLockedRowDml(
      new List<Invoice__c>{ changed },
      new Map<Id, Invoice__c>{ fakeInvoiceId => prior }
    );
    System.assertEquals(
      true,
      changed.hasErrors(),
      'Core 第11.6節: 確定後の請求日は除外一覧に書いても拒否する'
    );
    InvoiceLockUtil.testLockExemptFieldApiNames = null;
  }

  private class OrderedFixture {
    ContractService__c service;
    ContractHistory__c history;
    ContractProduct__c contractProduct;
  }

  private static OrderedFixture insertOrderedFixture(String suffix) {
    OrderedFixture fixture = new OrderedFixture();
    Account account = ContractTestDataFactory.insertAccount(
      suffix + ' Account ' + String.valueOf(Crypto.getRandomInteger())
    );
    fixture.service = ContractTestDataFactory.insertContractService(
      account.Id,
      suffix + ' Service'
    );
    fixture.history = new ContractHistory__c(
      Name = suffix + ' History',
      ContractService__c = fixture.service.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2026, 6, 30),
      EffectiveDate__c = Date.newInstance(2026, 6, 1)
    );
    ContractTestDataFactory.applyRequiredFields(fixture.history);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(
      fixture.history,
      account.Id
    );
    insert fixture.history;
    Product2 product = ContractTestDataFactory.buildProduct(
      suffix + ' Product ' + String.valueOf(Crypto.getRandomInteger())
    );
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(product);
    fixture.contractProduct = new ContractProduct__c(
      ContractHistory__c = fixture.history.Id,
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
    ContractTestDataFactory.applyRequiredFields(fixture.contractProduct);
    fixture.contractProduct.Amount__c = 1000;
    insert fixture.contractProduct;
    fixture.history.historystatus__c = 'Ordered';
    update fixture.history;
    return fixture;
  }
}
