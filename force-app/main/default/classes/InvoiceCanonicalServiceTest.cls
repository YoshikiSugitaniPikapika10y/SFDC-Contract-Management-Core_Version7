@IsTest
private class InvoiceCanonicalServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void rebuild_createsInvoiceAndLineFromPeriodLines() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();

      Test.startTest();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Test.stopTest();

      List<Invoice__c> invoices = [
        SELECT
          Id,
          Amount__c,
          TaxAmount__c,
          InvoiceDate__c,
          IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
      ];
      System.assertEquals(1, invoices.size(), '一括前払は請求1件');
      System.assertEquals(30000, invoices[0].Amount__c);
      System.assertEquals(
        TaxCalculationUtil.calculateTaxAmount(30000, 10),
        invoices[0].TaxAmount__c,
        '税率10%の税額'
      );
      System.assertEquals(false, invoices[0].IsManuallyAdjusted__c);

      List<InvoiceLine__c> lines = [
        SELECT Id, Amount__c, ProductName__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoices[0].Id
      ];
      System.assertEquals(1, lines.size(), '同一契約商品は明細1行に集約');
      System.assertEquals(30000, lines[0].Amount__c);
    }
  }

  @IsTest
  static void updateLineAmounts_rejectsWithoutEditPermission() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      InvoiceLine__c line = [
        SELECT Id, Amount__c, Invoice__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      Invoice__c beforeInvoice = [
        SELECT Amount__c, TaxAmount__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :line.Invoice__c
      ];

      InvoiceCanonicalService.testHasEditPreviewPermission = false;
      Boolean thrown = false;
      try {
        InvoiceCanonicalService.updateLineAmount(line.Id, 30001);
      } catch (InvoiceCanonicalService.InvoiceEditException ex) {
        thrown = true;
        System.assertEquals(
          '請求プレビューを編集する権限がありません。',
          ex.getMessage()
        );
      } finally {
        InvoiceCanonicalService.testHasEditPreviewPermission = true;
      }
      System.assertEquals(true, thrown);

      Invoice__c afterInvoice = [
        SELECT Amount__c, TaxAmount__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :line.Invoice__c
      ];
      System.assertEquals(beforeInvoice.Amount__c, afterInvoice.Amount__c);
      System.assertEquals(beforeInvoice.TaxAmount__c, afterInvoice.TaxAmount__c);
      System.assertEquals(
        false,
        afterInvoice.IsManuallyAdjusted__c,
        '権限不足では手動調整にならない'
      );
    }
  }

  @IsTest
  static void updateLineAmounts_rejectsEmptyEdits() {
    InvoiceCanonicalService.testHasEditPreviewPermission = true;
    Boolean thrown = false;
    try {
      InvoiceCanonicalService.updateLineAmounts(
        new List<InvoiceCanonicalService.LineAmountEdit>()
      );
    } catch (InvoiceCanonicalService.InvoiceEditException ex) {
      thrown = true;
      System.assertEquals('明細と金額は必須です。', ex.getMessage());
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void rebuildForHistories_rejectsWhenAnyInvoiceLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c invoice = [
        SELECT Id, Amount__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      invoice.SystemIntegrationDate__c = Date.today();
      update invoice;

      Boolean thrown = false;
      try {
        InvoiceCanonicalService.rebuildForHistories(
          new Set<Id>{ fixture.history.Id }
        );
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);

      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :fixture.history.Id
        ],
        'ロック時の作り直し拒否では請求は消えない'
      );
      Invoice__c still = [
        SELECT Amount__c, SystemIntegrationDate__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(30000, still.Amount__c);
      System.assertEquals(Date.today(), still.SystemIntegrationDate__c);
    }
  }

  @IsTest
  static void updateInvoiceDates_marksAdjustedClearsMergeKey() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          PaymentScheduledDate__c,
          TaxAmount__c,
          TaxPercent__c,
          Amount__c,
          MergeKey__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      // 日付変更前に MergeKey を立てておく（クリアされること）
      update new Invoice__c(Id = invoice.Id, MergeKey__c = 'test-merge-key');

      Date newInvoiceDate = Date.newInstance(2026, 7, 1);
      Date newPaymentDate = Date.newInstance(2026, 7, 31);
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.updateInvoiceDates(
        invoice.Id,
        newInvoiceDate,
        newPaymentDate
      );
      Test.stopTest();

      Invoice__c updated = [
        SELECT
          InvoiceDate__c,
          PaymentScheduledDate__c,
          IsManuallyAdjusted__c,
          MergeKey__c,
          TaxAmount__c,
          TaxPercent__c,
          Amount__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(newInvoiceDate, updated.InvoiceDate__c);
      System.assertEquals(newPaymentDate, updated.PaymentScheduledDate__c);
      System.assertEquals(true, updated.IsManuallyAdjusted__c);
      System.assertEquals(null, updated.MergeKey__c, '日付変更で統合キーを外す');
      System.assertEquals(invoice.Amount__c, updated.Amount__c);
      System.assertEquals(invoice.TaxAmount__c, updated.TaxAmount__c);
      System.assertEquals(invoice.TaxPercent__c, updated.TaxPercent__c);
    }
  }

  @IsTest
  static void updateLineAmount_marksAdjustedAndRecalculatesTax() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      InvoiceLine__c line = [
        SELECT Id, Invoice__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.updateLineAmount(line.Id, 30001);
      Test.stopTest();

      Invoice__c invoice = [
        SELECT Amount__c, TaxAmount__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :line.Invoice__c
      ];
      System.assertEquals(30001, invoice.Amount__c);
      System.assertEquals(true, invoice.IsManuallyAdjusted__c);
      System.assertEquals(
        TaxCalculationUtil.calculateTaxAmount(30001, 10),
        invoice.TaxAmount__c
      );
    }
  }

  @IsTest
  static void splitInvoiceByDate_movesAmountToNewInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id, BillingAccountSnapShot__c, BillingAddresseeSnapShot__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      String originalAddressee = source.BillingAddresseeSnapShot__c;
      InvoiceLine__c line = [
        SELECT Id, ContractProduct__c, ContractProduct__r.Product__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      System.assertNotEquals(
        null,
        line.ContractProduct__r.Product__c,
        '分割前明細に商品参照があること'
      );

      // 生成後に BA マスタを更新しても既存請求は据え置き、分割で生まれる新請求は最新を取る
      System.assertNotEquals(null, source.BillingAccountSnapShot__c);
      update new BillingAccount__c(
        Id = source.BillingAccountSnapShot__c,
        BillingAddressee__c = '分割時点の最新宛名 御中',
        ConfirmSharedUpdate__c = true
      );

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 10000;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      Id createdId = InvoiceCanonicalService.splitInvoiceByDate(
        source.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      Invoice__c created = [
        SELECT
          Amount__c,
          PeriodLineAmountTotal__c,
          InvoiceDate__c,
          IsManuallyAdjusted__c,
          BillingAddresseeSnapShot__c,
          MergeKey__c
        FROM Invoice__c
        WHERE Id = :createdId
      ];
      System.assertEquals(10000, created.Amount__c);
      System.assertEquals(
        10000,
        created.PeriodLineAmountTotal__c,
        '分割新請求の調整前請求額は移した金額と一致すること'
      );
      System.assertEquals(Date.newInstance(2026, 7, 1), created.InvoiceDate__c);
      System.assertEquals(true, created.IsManuallyAdjusted__c);
      System.assertEquals(
        '分割時点の最新宛名 御中',
        created.BillingAddresseeSnapShot__c
      );
      System.assertEquals(
        null,
        created.MergeKey__c,
        '分割新請求の MergeKey は付与しない（突合は Id ベース）'
      );

      InvoiceLine__c createdLine = [
        SELECT Product__c, ContractProduct__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :createdId
        LIMIT 1
      ];
      System.assertEquals(
        line.ContractProduct__r.Product__c,
        createdLine.Product__c,
        '分割明細の商品参照は作成時の契約商品から明示セット'
      );
      System.assertEquals(
        line.ContractProduct__c,
        createdLine.ContractProduct__c
      );

      Invoice__c remain = [
        SELECT Amount__c, PeriodLineAmountTotal__c, BillingAddresseeSnapShot__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(20000, remain.Amount__c);
      System.assertEquals(
        20000,
        remain.PeriodLineAmountTotal__c,
        '分割元請求の調整前請求額は残す金額と一致すること'
      );
      System.assertEquals(
        originalAddressee,
        remain.BillingAddresseeSnapShot__c
      );
    }
  }

  @IsTest
  static void splitInvoiceByDate_reallocatesPeriodLineAmountTotalAfterAdjustment() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      InvoiceLine__c line = [
        SELECT Id, Invoice__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      // 端数 +1 後に分割: 調整前 30000 / 金額 30001 → 移す 10000 は金額比で按分
      InvoiceCanonicalService.updateLineAmount(line.Id, 30001);

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 10000;

      Test.startTest();
      Id createdId = InvoiceCanonicalService.splitInvoiceByDate(
        line.Invoice__c,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      Invoice__c created = [
        SELECT Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :createdId
      ];
      Invoice__c remain = [
        SELECT Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :line.Invoice__c
      ];
      System.assertEquals(10000, created.Amount__c);
      System.assertEquals(20001, remain.Amount__c);
      System.assertEquals(
        10000,
        created.PeriodLineAmountTotal__c,
        '調整前は移す金額比で按分（30000×10000/30001 → 10000）'
      );
      System.assertEquals(
        20000,
        remain.PeriodLineAmountTotal__c,
        '残側の調整前は元調整前−移す側（端数ギャップ+1は残側に残る）'
      );
      System.assertEquals(
        30000,
        created.PeriodLineAmountTotal__c + remain.PeriodLineAmountTotal__c,
        '分割前後で調整前請求額の合計は保存される'
      );
    }
  }

  @IsTest
  static void allocatePeriodTotalByAbsShare_splitsBaselineByAbsContribution() {
    System.assertEquals(
      1000,
      InvoiceCanonicalService.allocatePeriodTotalByAbsShare(2000, 1000, 1000),
      '絶対値寄与が等しければ半々'
    );
    System.assertEquals(
      2000,
      InvoiceCanonicalService.allocatePeriodTotalByAbsShare(2000, 1000, 0),
      '残寄与0なら新側へ全額'
    );
    System.assertEquals(
      0,
      InvoiceCanonicalService.allocatePeriodTotalByAbsShare(2000, 0, 1000),
      '移す寄与0なら新側0'
    );
    System.assertEquals(
      2000,
      InvoiceCanonicalService.allocatePeriodTotalByAbsShare(2000, 0, 0),
      '双方寄与0かつ残寄与0扱いで新側へ全額'
    );
    System.assertEquals(
      67,
      InvoiceCanonicalService.allocatePeriodTotalByAbsShare(100, 2, 1),
      'HALF_UP で奇数ベースラインを按分'
    );
  }

  @IsTest
  static void moveLinesToExistingInvoice_reallocatesPeriodTotalWhenAmountZero() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id, PeriodLineAmountTotal__c, ContractService__c, ContractHistory__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c lineA = [
        SELECT
          Id,
          Invoice__c,
          Amount__c,
          ProductName__c,
          Unit__c,
          UnitPrice__c,
          Quantity__c,
          PeriodLabel__c,
          LineMergeKey__c,
          HistoryVersionLabel__c,
          SourcePeriodLineIds__c,
          ContractProduct__c,
          Product__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      InvoiceLine__c lineB = lineA.clone(false, true, false, false);
      lineB.Amount__c = 30000;
      lineB.IsManuallyAdjusted__c = true;
      insert lineB;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      InvoiceCanonicalService.updateLineAmount(lineA.Id, -30000);

      Invoice__c target = new Invoice__c(
        ContractService__c = source.ContractService__c,
        ContractHistory__c = source.ContractHistory__c,
        InvoiceDate__c = Date.newInstance(2026, 9, 1),
        Amount__c = 0,
        TaxAmount__c = 0,
        PeriodLineAmountTotal__c = 0
      );
      insert target;

      Invoice__c beforeMove = [
        SELECT Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(0, beforeMove.Amount__c, 'ヘッダ税抜が0であること');
      System.assertEquals(
        30000,
        beforeMove.PeriodLineAmountTotal__c,
        '調整前は端数調整後も残る'
      );

      Test.startTest();
      InvoiceCanonicalService.moveLinesToExistingInvoice(
        source.Id,
        target.Id,
        new List<Id>{ lineB.Id }
      );
      Test.stopTest();

      Invoice__c afterSource = [
        SELECT Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      Invoice__c afterTarget = [
        SELECT Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :target.Id
      ];
      System.assertEquals(
        15000,
        afterTarget.PeriodLineAmountTotal__c,
        '税抜0の移設でも調整前は絶対値寄与で按分される'
      );
      System.assertEquals(
        15000,
        afterSource.PeriodLineAmountTotal__c,
        '残側の調整前も半分'
      );
      System.assertEquals(
        30000,
        afterSource.PeriodLineAmountTotal__c +
        afterTarget.PeriodLineAmountTotal__c,
        '移設前後で調整前請求額の合計は保存される'
      );
    }
  }

  @IsTest
  static void splitInvoiceByDate_reallocatesPeriodLineAmountTotalWhenAmountZero() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c lineA = [
        SELECT
          Id,
          Invoice__c,
          Amount__c,
          ProductName__c,
          Unit__c,
          UnitPrice__c,
          Quantity__c,
          PeriodLabel__c,
          LineMergeKey__c,
          HistoryVersionLabel__c,
          SourcePeriodLineIds__c,
          ContractProduct__c,
          Product__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      // 同一請求に相手明細を足し、端数でヘッダ税抜を 0 にする
      InvoiceLine__c lineB = lineA.clone(false, true, false, false);
      lineB.Amount__c = 30000;
      lineB.IsManuallyAdjusted__c = true;
      insert lineB;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      InvoiceCanonicalService.updateLineAmount(lineA.Id, -30000);

      Invoice__c beforeSplit = [
        SELECT Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(0, beforeSplit.Amount__c, 'ヘッダ税抜が0であること');
      System.assertEquals(
        30000,
        beforeSplit.PeriodLineAmountTotal__c,
        '調整前は端数調整後も残る'
      );

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = lineB.Id;
      split.moveAmount = 30000;

      Test.startTest();
      Id createdId = InvoiceCanonicalService.splitInvoiceByDate(
        source.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      Invoice__c created = [
        SELECT Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :createdId
      ];
      Invoice__c remain = [
        SELECT Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(30000, created.Amount__c);
      System.assertEquals(-30000, remain.Amount__c);
      System.assertEquals(
        15000,
        created.PeriodLineAmountTotal__c,
        '税抜0でも調整前は絶対値寄与で按分される'
      );
      System.assertEquals(
        15000,
        remain.PeriodLineAmountTotal__c,
        '残側の調整前も半分'
      );
      System.assertEquals(
        30000,
        created.PeriodLineAmountTotal__c + remain.PeriodLineAmountTotal__c,
        '分割前後で調整前請求額の合計は保存される'
      );
    }
  }

  @IsTest
  static void splitInvoiceByDate_movesNegativeAmountToNewInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      InvoiceLine__c line = [
        SELECT Id, Invoice__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      InvoiceCanonicalService.updateLineAmount(line.Id, -10000);

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = -4000;

      Test.startTest();
      Id createdId = InvoiceCanonicalService.splitInvoiceByDate(
        line.Invoice__c,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      Invoice__c created = [
        SELECT Amount__c
        FROM Invoice__c
        WHERE Id = :createdId
      ];
      System.assertEquals(
        -4000,
        created.Amount__c,
        'マイナス打消しも新請求へ移せること'
      );

      Invoice__c remain = [
        SELECT Amount__c
        FROM Invoice__c
        WHERE Id = :line.Invoice__c
      ];
      System.assertEquals(
        -6000,
        remain.Amount__c,
        '残す側もマイナスのまま残ること'
      );
    }
  }

  @IsTest
  static void moveLinesToExistingInvoice_movesSelectedLinesAndDeletesEmptySource() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id, Amount__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 10000;
      Id createdId = InvoiceCanonicalService.splitInvoiceByDate(
        source.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      InvoiceLine__c movedLine = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :createdId
        LIMIT 1
      ];

      Test.startTest();
      InvoiceCanonicalService.moveLinesToExistingInvoice(
        createdId,
        source.Id,
        new List<Id>{ movedLine.Id }
      );
      Test.stopTest();

      List<Invoice__c> remainCreated = [
        SELECT Id
        FROM Invoice__c
        WHERE Id = :createdId
      ];
      System.assertEquals(
        0,
        remainCreated.size(),
        '全明細移動後は移動元請求が削除されること'
      );

      Invoice__c target = [
        SELECT
          Amount__c,
          PeriodLineAmountTotal__c,
          MergeKey__c,
          IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(30000, target.Amount__c, '移動先に金額が戻ること');
      System.assertEquals(
        30000,
        target.PeriodLineAmountTotal__c,
        '調整前請求額も合算されること'
      );
      System.assertEquals(null, target.MergeKey__c);
      System.assertEquals(true, target.IsManuallyAdjusted__c);
      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM InvoiceLine__c
          WHERE Invoice__c = :source.Id
        ],
        '合算せず別行のまま載ること'
      );
    }
  }

  @IsTest
  static void moveLinesToExistingInvoice_rejectsLockedTarget() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c target = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id
        FROM InvoiceLine__c
        WHERE Invoice__c = :target.Id
        LIMIT 1
      ];

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 10000;
      Id sourceId = InvoiceCanonicalService.splitInvoiceByDate(
        target.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      InvoiceLine__c movedLine = [
        SELECT Id
        FROM InvoiceLine__c
        WHERE Invoice__c = :sourceId
        LIMIT 1
      ];

      update new Invoice__c(
        Id = target.Id,
        SystemIntegrationDate__c = Date.today()
      );

      Decimal sourceAmountBefore = [
        SELECT Amount__c
        FROM Invoice__c
        WHERE Id = :sourceId
      ]
      .Amount__c;
      Integer sourceLineCountBefore = [
        SELECT COUNT()
        FROM InvoiceLine__c
        WHERE Invoice__c = :sourceId
      ];

      Boolean blocked = false;
      try {
        InvoiceCanonicalService.moveLinesToExistingInvoice(
          sourceId,
          target.Id,
          new List<Id>{ movedLine.Id }
        );
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        blocked = true;
        System.assertEquals(
          InvoiceLockUtil.INVOICE_EDIT_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, blocked, 'ロック先への明細移動は拒否');
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Invoice__c WHERE Id = :sourceId],
        '拒否時は移動元請求が残る'
      );
      System.assertEquals(
        sourceAmountBefore,
        [
          SELECT Amount__c
          FROM Invoice__c
          WHERE Id = :sourceId
        ]
        .Amount__c,
        '拒否時は移動元金額不変'
      );
      System.assertEquals(
        sourceLineCountBefore,
        [
          SELECT COUNT()
          FROM InvoiceLine__c
          WHERE Invoice__c = :sourceId
        ],
        '拒否時は移動元明細数不変'
      );
    }
  }

  @IsTest
  static void moveLinesToExistingInvoice_rejectsDifferentHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];

      // 2サービス分の正本生成は SOQL を食うので startTest 後に回す
      Test.startTest();
      Fixture other = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ other.history.Id }
      );
      Invoice__c otherInvoice = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :other.history.Id
        LIMIT 1
      ];

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Boolean failed = false;
      try {
        InvoiceCanonicalService.moveLinesToExistingInvoice(
          source.Id,
          otherInvoice.Id,
          new List<Id>{ line.Id }
        );
      } catch (InvoiceCanonicalService.InvoiceEditException ex) {
        failed = true;
        System.assertEquals(
          '同一 Version（契約履歴）の請求へだけ明細を移せます。',
          ex.getMessage()
        );
      }
      Test.stopTest();
      System.assertEquals(true, failed, '別契約履歴への移動は失敗すること');
    }
  }

  @IsTest
  static void splitInvoiceUnified_unitPriceSplitsFactorsAndClearsAdjustment() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      InvoiceLine__c line = [
        SELECT Id, Invoice__c, Amount__c, UnitPrice__c, Quantity__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      System.assertEquals(30000, line.Amount__c);
      System.assertEquals(10000, line.UnitPrice__c);

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      split.remainUnitPrice = 4000;
      split.moveUnitPrice = 6000;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      Id createdId = InvoiceCanonicalService.splitInvoiceUnified(
        line.Invoice__c,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        null,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      InvoiceLine__c moved = [
        SELECT Amount__c, UnitPrice__c, Quantity__c, IsManuallyAdjusted__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :createdId
        LIMIT 1
      ];
      InvoiceLine__c remain = [
        SELECT Amount__c, UnitPrice__c, Quantity__c, IsManuallyAdjusted__c
        FROM InvoiceLine__c
        WHERE Id = :line.Id
      ];
      System.assertEquals(6000, moved.UnitPrice__c);
      System.assertEquals(4000, remain.UnitPrice__c);
      System.assertEquals(1, moved.Quantity__c);
      System.assertEquals(1, remain.Quantity__c);
      System.assertEquals(18000, moved.Amount__c);
      System.assertEquals(12000, remain.Amount__c);
      System.assertEquals(false, moved.IsManuallyAdjusted__c);
      System.assertEquals(false, remain.IsManuallyAdjusted__c);
    }
  }

  @IsTest
  static void splitInvoiceUnified_quantityAndWholeMixed() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, Amount__c, Quantity__c, UnitPrice__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      line.Quantity__c = 10;
      update line;

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_QUANTITY;
      split.remainQuantity = 6;
      split.moveQuantity = 4;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      Id createdId = InvoiceCanonicalService.splitInvoiceUnified(
        source.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        null,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      InvoiceLine__c moved = [
        SELECT Amount__c, Quantity__c, UnitPrice__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :createdId
        LIMIT 1
      ];
      InvoiceLine__c remain = [
        SELECT Amount__c, Quantity__c, UnitPrice__c
        FROM InvoiceLine__c
        WHERE Id = :line.Id
      ];
      System.assertEquals(4, moved.Quantity__c);
      System.assertEquals(6, remain.Quantity__c);
      System.assertEquals(10000, moved.UnitPrice__c);
      System.assertEquals(12000, moved.Amount__c);
      System.assertEquals(18000, remain.Amount__c);
    }
  }

  @IsTest
  static void splitInvoiceUnified_periodOnSelectedLine() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c sourceLine = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      InvoiceProduct__c movePeriod = [
        SELECT Id
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
        ORDER BY StartDate__c ASC
        LIMIT 1
      ];

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = sourceLine.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_PERIOD;
      split.movePeriodLineIds = new List<Id>{ movePeriod.Id };

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      Id createdId = InvoiceCanonicalService.splitInvoiceUnified(
        source.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        null,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      Invoice__c created = [
        SELECT Amount__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :createdId
      ];
      System.assertEquals(10000, created.Amount__c);
      System.assertEquals(false, created.IsManuallyAdjusted__c);
      Invoice__c remain = [
        SELECT Amount__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(20000, remain.Amount__c);
    }
  }

  /** 端数調整した兄弟明細があるとき、別明細の同一請求内分割で親の手動調整を消さない。 */
  @IsTest
  static void splitLinesInPlace_keepsSiblingManualAdjustmentOnHeader() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );

      Invoice__c invoiceSeed = [
        SELECT
          Id,
          BillingAccountSnapShot__c,
          InvoiceDate__c,
          PaymentScheduledDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];

      Product2 productB = ContractTestDataFactory.buildProduct(
        'Canonical Product B'
      );
      productB.BillingType__c = '継続課金';
      ContractTestDataFactory.insertProduct(productB);
      ContractProduct__c cpB = new ContractProduct__c(
        ContractHistory__c = fixture.history.Id,
        Product__c = productB.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Unit__c = 'ID',
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 8, 31),
        InvoiceSetting__c = '一括前払',
        BillingType__c = '継続課金',
        Type__c = 'New',
        Amount__c = 30000
      );
      insert cpB;

      String bucketKey = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
        invoiceSeed.BillingAccountSnapShot__c,
        fixture.history.Id,
        invoiceSeed.InvoiceDate__c,
        invoiceSeed.PaymentScheduledDate__c
      );
      insert new List<InvoiceProduct__c>{
        new InvoiceProduct__c(
          ContractHistory__c = fixture.history.Id,
          ContractProduct__c = cpB.Id,
          InvoiceBucketKey__c = bucketKey,
          StartDate__c = Date.newInstance(2026, 6, 1),
          Enddate__c = Date.newInstance(2026, 6, 30),
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 10000,
          TaxPercent__c = 0.1
        ),
        new InvoiceProduct__c(
          ContractHistory__c = fixture.history.Id,
          ContractProduct__c = cpB.Id,
          InvoiceBucketKey__c = bucketKey,
          StartDate__c = Date.newInstance(2026, 7, 1),
          Enddate__c = Date.newInstance(2026, 7, 31),
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 10000,
          TaxPercent__c = 0.1
        ),
        new InvoiceProduct__c(
          ContractHistory__c = fixture.history.Id,
          ContractProduct__c = cpB.Id,
          InvoiceBucketKey__c = bucketKey,
          StartDate__c = Date.newInstance(2026, 8, 1),
          Enddate__c = Date.newInstance(2026, 8, 31),
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 10000,
          TaxPercent__c = 0.1
        )
      };

      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      List<InvoiceLine__c> lines = [
        SELECT Id, Invoice__c, Amount__c, ProductName__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        ORDER BY ProductName__c ASC
      ];
      System.assertEquals(2, lines.size());
      Id invoiceId = lines[0].Invoice__c;
      InvoiceLine__c lineA = lines[0];
      InvoiceLine__c lineB = lines[1];

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      InvoiceCanonicalService.updateLineAmount(lineA.Id, lineA.Amount__c + 10);
      Decimal baseline = [
        SELECT PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :invoiceId
      ]
      .PeriodLineAmountTotal__c;

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = lineB.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      split.remainUnitPrice = 4000;
      split.moveUnitPrice = 6000;

      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        invoiceId,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      Invoice__c after = [
        SELECT Amount__c, PeriodLineAmountTotal__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :invoiceId
      ];
      System.assertEquals(true, after.IsManuallyAdjusted__c);
      System.assertEquals(baseline, after.PeriodLineAmountTotal__c);
      System.assertEquals(60010, after.Amount__c);
      System.assertEquals(
        true,
        [
          SELECT IsManuallyAdjusted__c
          FROM InvoiceLine__c
          WHERE Id = :lineA.Id
        ]
        .IsManuallyAdjusted__c
      );
    }
  }

  @IsTest
  static void splitLinesInPlace_unitPriceKeepsSameInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      InvoiceLine__c line = [
        SELECT Id, Invoice__c, Amount__c, UnitPrice__c, Quantity__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      Id invoiceId = line.Invoice__c;

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      split.remainUnitPrice = 4000;
      split.moveUnitPrice = 6000;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        invoiceId,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :fixture.history.Id
        ],
        '同一請求内分割では新請求を作らない'
      );
      List<InvoiceLine__c> lines = [
        SELECT Amount__c, UnitPrice__c, Quantity__c, IsManuallyAdjusted__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoiceId
        ORDER BY UnitPrice__c ASC
      ];
      System.assertEquals(2, lines.size());
      System.assertEquals(4000, lines[0].UnitPrice__c);
      System.assertEquals(6000, lines[1].UnitPrice__c);
      System.assertEquals(12000, lines[0].Amount__c);
      System.assertEquals(18000, lines[1].Amount__c);
      System.assertEquals(false, lines[0].IsManuallyAdjusted__c);
      System.assertEquals(false, lines[1].IsManuallyAdjusted__c);

      Invoice__c invoice = [
        SELECT Amount__c, PeriodLineAmountTotal__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :invoiceId
      ];
      System.assertEquals(30000, invoice.Amount__c);
      System.assertEquals(30000, invoice.PeriodLineAmountTotal__c);
      System.assertEquals(false, invoice.IsManuallyAdjusted__c);
    }
  }

  /** 値引き／Change Original 相当の負単価明細でも単価分割できること。 */
  @IsTest
  static void splitLinesInPlace_negativeUnitPriceDiscount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      InvoiceLine__c line = [
        SELECT
          Id,
          Invoice__c,
          Amount__c,
          UnitPrice__c,
          Quantity__c,
          ContractProduct__c,
          SourcePeriodLineIds__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      line.UnitPrice__c = -10000;
      line.Quantity__c = 1;
      line.Amount__c = -30000;
      update line;
      update new Invoice__c(
        Id = line.Invoice__c,
        Amount__c = -30000,
        PeriodLineAmountTotal__c = -30000
      );
      update new ContractProduct__c(
        Id = line.ContractProduct__c,
        Amount__c = -30000,
        UnitPrice__c = -10000
      );
      List<Id> periodIds = new List<Id>();
      if (String.isNotBlank(line.SourcePeriodLineIds__c)) {
        for (String part : line.SourcePeriodLineIds__c.split(',')) {
          String trimmed = part == null ? null : part.trim();
          if (String.isNotBlank(trimmed)) {
            periodIds.add((Id) trimmed);
          }
        }
      }
      if (!periodIds.isEmpty()) {
        List<InvoiceProduct__c> periodUpdates = new List<InvoiceProduct__c>();
        for (Id periodId : periodIds) {
          periodUpdates.add(
            new InvoiceProduct__c(
              Id = periodId,
              Amount__c = -10000,
              UnitPrice__c = -10000
            )
          );
        }
        update periodUpdates;
      }

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      split.remainUnitPrice = -4000;
      split.moveUnitPrice = -6000;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        line.Invoice__c,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        fixture.history.Id
      );
      Test.stopTest();

      List<InvoiceLine__c> lines = [
        SELECT Amount__c, UnitPrice__c, Quantity__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :line.Invoice__c
        ORDER BY UnitPrice__c ASC
      ];
      System.assertEquals(2, lines.size());
      System.assertEquals(-6000, lines[0].UnitPrice__c);
      System.assertEquals(-4000, lines[1].UnitPrice__c);
      System.assertEquals(-18000, lines[0].Amount__c);
      System.assertEquals(-12000, lines[1].Amount__c);
      System.assertEquals(
        -30000,
        lines[0].Amount__c + lines[1].Amount__c,
        '負明細でも合計保全'
      );

      Invoice__c invoice = [
        SELECT Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :line.Invoice__c
      ];
      System.assertEquals(-30000, invoice.Amount__c);
      System.assertEquals(-30000, invoice.PeriodLineAmountTotal__c);
      System.assertEquals(
        0,
        preview.amountDifference,
        '負の発生金額でもヘッダ端数0'
      );
      for (OrderCreateController.InvoiceGroupDto groupRow : preview.invoices) {
        for (OrderCreateController.InvoiceMergedLineDto row : groupRow.lines) {
          System.assertEquals(
            false,
            row.hasAmountDrift,
            '負明細の単価分割後も行端数なし: ' + row.amountDeltaFromSource
          );
        }
      }
    }
  }

  /** 負金額の数量分割（打消し行の数量按分）。 */
  @IsTest
  static void splitLinesInPlace_negativeAmountQuantitySplit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      InvoiceLine__c line = [
        SELECT Id, Invoice__c, Amount__c, UnitPrice__c, Quantity__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      line.UnitPrice__c = -1000;
      line.Quantity__c = 10;
      line.Amount__c = -30000;
      update line;
      update new Invoice__c(
        Id = line.Invoice__c,
        Amount__c = -30000,
        PeriodLineAmountTotal__c = -30000
      );

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_QUANTITY;
      split.remainQuantity = 6;
      split.moveQuantity = 4;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        line.Invoice__c,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      List<InvoiceLine__c> lines = [
        SELECT Amount__c, Quantity__c, UnitPrice__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :line.Invoice__c
        ORDER BY Quantity__c ASC
      ];
      System.assertEquals(2, lines.size());
      System.assertEquals(4, lines[0].Quantity__c);
      System.assertEquals(6, lines[1].Quantity__c);
      System.assertEquals(-12000, lines[0].Amount__c);
      System.assertEquals(-18000, lines[1].Amount__c);
      System.assertEquals(-1000, lines[0].UnitPrice__c);
      System.assertEquals(
        -30000,
        lines[0].Amount__c + lines[1].Amount__c,
        '負金額でも数量分割の合計保全'
      );
    }
  }

  @IsTest
  static void splitLinesInPlace_quantityScalesAmounts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      InvoiceLine__c line = [
        SELECT Id, Invoice__c, Amount__c, Quantity__c, UnitPrice__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      line.Quantity__c = 10;
      update line;

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_QUANTITY;
      split.remainQuantity = 6;
      split.moveQuantity = 4;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        line.Invoice__c,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      List<InvoiceLine__c> lines = [
        SELECT Amount__c, Quantity__c, UnitPrice__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :line.Invoice__c
        ORDER BY Quantity__c ASC
      ];
      System.assertEquals(2, lines.size());
      System.assertEquals(4, lines[0].Quantity__c);
      System.assertEquals(6, lines[1].Quantity__c);
      System.assertEquals(12000, lines[0].Amount__c);
      System.assertEquals(18000, lines[1].Amount__c);
      System.assertEquals(10000, lines[0].UnitPrice__c);
    }
  }

  @IsTest
  static void splitLinesInPlace_periodThresholdSplitsSibling() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id, Amount__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c sourceLine = [
        SELECT Id, Amount__c, SourcePeriodLineIds__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = sourceLine.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_PERIOD;
      split.thresholdDate = Date.newInstance(2026, 7, 1);

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        source.Id,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      System.assertEquals(
        1,
        [SELECT COUNT() FROM Invoice__c WHERE Id = :source.Id]
      );
      List<InvoiceLine__c> lines = [
        SELECT
          Amount__c,
          SourcePeriodLineIds__c,
          PeriodLabel__c,
          IsManuallyAdjusted__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        ORDER BY Amount__c ASC
      ];
      System.assertEquals(2, lines.size());
      System.assertEquals(10000, lines[0].Amount__c);
      System.assertEquals(20000, lines[1].Amount__c);
      System.assertEquals(false, lines[0].IsManuallyAdjusted__c);
      System.assertEquals(false, lines[1].IsManuallyAdjusted__c);

      Date juneStart = Date.newInstance(2026, 6, 1);
      InvoiceProduct__c june = [
        SELECT Id
        FROM InvoiceProduct__c
        WHERE
          ContractHistory__c = :fixture.history.Id
          AND StartDate__c = :juneStart
        LIMIT 1
      ];
      // remain = June only; move = Jul+Aug
      Boolean sawJuneOnly = false;
      Boolean sawMoved = false;
      for (InvoiceLine__c row : lines) {
        if (row.Amount__c == 10000) {
          System.assertEquals(
            String.valueOf(june.Id),
            row.SourcePeriodLineIds__c
          );
          sawJuneOnly = true;
        }
        if (row.Amount__c == 20000) {
          System.assert(
            !row.SourcePeriodLineIds__c.contains(String.valueOf(june.Id)),
            '移す側に最早月が含まれないこと'
          );
          sawMoved = true;
        }
      }
      System.assertEquals(true, sawJuneOnly);
      System.assertEquals(true, sawMoved);

      Invoice__c invoice = [
        SELECT Amount__c, PeriodLineAmountTotal__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(30000, invoice.Amount__c);
      System.assertEquals(30000, invoice.PeriodLineAmountTotal__c);
      System.assertEquals(false, invoice.IsManuallyAdjusted__c);
    }
  }

  @IsTest
  static void getSplitThresholdDateOptions_returnsNonEarliestMonths() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];

      Test.startTest();
      List<InvoiceCanonicalService.SplitThresholdLineOptions> rows = InvoiceCanonicalService.getSplitThresholdDateOptions(
        source.Id
      );
      Test.stopTest();

      System.assertEquals(1, rows.size());
      System.assertEquals(line.Id, rows[0].invoiceLineId);
      System.assertEquals(2, rows[0].options.size());
      System.assertEquals('2026-07-01', rows[0].options[0].value);
      System.assertEquals('2026-08-01', rows[0].options[1].value);
      System.assert(String.isNotBlank(rows[0].options[0].label));
    }
  }

  @IsTest
  static void splitLinesInPlace_rejectsLockedInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      InvoiceLine__c line = [
        SELECT Id, Invoice__c, UnitPrice__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      update new Invoice__c(
        Id = line.Invoice__c,
        SystemIntegrationDate__c = Date.today()
      );

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      split.remainUnitPrice = 4000;
      split.moveUnitPrice = 6000;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Boolean blocked = false;
      try {
        InvoiceCanonicalService.splitLinesInPlace(
          line.Invoice__c,
          new List<InvoiceCanonicalService.SplitLineInput>{ split }
        );
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        blocked = true;
        System.assertEquals(
          InvoiceLockUtil.INVOICE_EDIT_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, blocked, 'ロック請求の同一請求内分割は拒否');
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM InvoiceLine__c
          WHERE Invoice__c = :line.Invoice__c
        ],
        '拒否時は明細が増えない'
      );
      Invoice__c still = [
        SELECT Amount__c
        FROM Invoice__c
        WHERE Id = :line.Invoice__c
      ];
      System.assertEquals(30000, still.Amount__c);
    }
  }

  @IsTest
  static void splitInvoiceByDate_rejectsInconsistentRemainAmount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, Amount__c, ProductName__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      Decimal originalAmount = line.Amount__c;
      System.assert(originalAmount > 1000, '分割検証用に十分な金額があること');

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 1000;
      // 元金額を残す指定 → move+remain が元を超える（水増し）
      split.remainAmount = originalAmount;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Boolean blocked = false;
      try {
        InvoiceCanonicalService.splitInvoiceByDate(
          source.Id,
          Date.newInstance(2026, 7, 1),
          Date.newInstance(2026, 7, 31),
          new List<InvoiceCanonicalService.SplitLineInput>{ split }
        );
      } catch (InvoiceCanonicalService.InvoiceEditException ex) {
        blocked = true;
        System.assertEquals(
          InvoiceCanonicalService.SPLIT_AMOUNT_CONSERVE_MESSAGE +
            ': ' +
            line.ProductName__c,
          ex.getMessage()
        );
      }
      System.assertEquals(true, blocked, 'remain 不一致は拒否');

      AggregateResult total = [
        SELECT SUM(Amount__c) amt
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
      ];
      System.assertEquals(
        originalAmount,
        (Decimal) total.get('amt'),
        '拒否後も明細合計は変わらない'
      );
    }
  }

  @IsTest
  static void resolveConservingRemainAmount_rejectsInconsistentRemain() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean blocked = false;
      try {
        InvoiceCanonicalService.resolveConservingRemainAmount(
          1000,
          10000,
          10000,
          'Test Product'
        );
      } catch (InvoiceCanonicalService.InvoiceEditException ex) {
        blocked = true;
        System.assertEquals(
          InvoiceCanonicalService.SPLIT_AMOUNT_CONSERVE_MESSAGE + ': Test Product',
          ex.getMessage()
        );
      }
      System.assertEquals(true, blocked);

      System.assertEquals(
        9000,
        InvoiceCanonicalService.resolveConservingRemainAmount(
          1000,
          null,
          10000,
          null
        ),
        '未指定なら current - move'
      );
      System.assertEquals(
        9000,
        InvoiceCanonicalService.resolveConservingRemainAmount(
          1000,
          9000,
          10000,
          null
        ),
        '一致する remain は許可'
      );
    }
  }

  @IsTest
  static void splitInvoiceByPeriod_rewritesProvenanceAndAmounts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c sourceLine = [
        SELECT Id, Amount__c, SourcePeriodLineIds__c, PeriodLabel__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      System.assertEquals(30000, sourceLine.Amount__c);

      InvoiceProduct__c movePeriod = [
        SELECT Id, Amount__c, StartDate__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
        ORDER BY StartDate__c ASC
        LIMIT 1
      ];

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      Id createdId = InvoiceCanonicalService.splitInvoiceByPeriod(
        source.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<Id>{ movePeriod.Id }
      );
      Test.stopTest();

      Invoice__c created = [
        SELECT
          Amount__c,
          PeriodLineAmountTotal__c,
          InvoiceDate__c,
          IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :createdId
      ];
      System.assertEquals(10000, created.Amount__c);
      System.assertEquals(
        10000,
        created.PeriodLineAmountTotal__c,
        '利用期間分割の新請求は調整前＝金額'
      );
      System.assertEquals(Date.newInstance(2026, 7, 1), created.InvoiceDate__c);
      System.assertEquals(
        false,
        created.IsManuallyAdjusted__c,
        '利用期間分割後の新請求は手動調整クリア'
      );

      InvoiceLine__c movedLine = [
        SELECT
          Amount__c,
          SourcePeriodLineIds__c,
          PeriodLabel__c,
          IsManuallyAdjusted__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :createdId
        LIMIT 1
      ];
      System.assertEquals(10000, movedLine.Amount__c);
      System.assertEquals(false, movedLine.IsManuallyAdjusted__c);
      System.assertEquals(
        String.valueOf(movePeriod.Id),
        movedLine.SourcePeriodLineIds__c
      );
      System.assert(
        String.isNotBlank(movedLine.PeriodLabel__c),
        '移す側の期間ラベルが設定されること'
      );

      Invoice__c remainInvoice = [
        SELECT Amount__c, PeriodLineAmountTotal__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(20000, remainInvoice.Amount__c);
      System.assertEquals(
        20000,
        remainInvoice.PeriodLineAmountTotal__c,
        '利用期間分割の残請求は調整前＝金額'
      );
      System.assertEquals(
        false,
        remainInvoice.IsManuallyAdjusted__c,
        '利用期間分割後の残請求も手動調整クリア'
      );

      InvoiceLine__c remainLine = [
        SELECT
          Amount__c,
          SourcePeriodLineIds__c,
          PeriodLabel__c,
          IsManuallyAdjusted__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      System.assertEquals(20000, remainLine.Amount__c);
      System.assertEquals(false, remainLine.IsManuallyAdjusted__c);
      System.assert(
        !remainLine.SourcePeriodLineIds__c.contains(
          String.valueOf(movePeriod.Id)
        ),
        '残す側から移した期間明細IDが外れていること'
      );
      System.assert(
        String.isNotBlank(remainLine.PeriodLabel__c),
        '残す側の期間ラベルが設定されること'
      );
    }
  }

  @IsTest
  static void splitInvoiceByPeriod_afterAmountSplit_preservesServiceTotal() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id, ContractService__c, Amount__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      System.assertEquals(30000, source.Amount__c);
      InvoiceLine__c line = [
        SELECT Id
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      List<InvoiceProduct__c> periods = [
        SELECT Id, Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
        ORDER BY StartDate__c ASC
      ];
      System.assert(
        periods.size() >= 2,
        '利用期間分割できるよう期間が2件以上必要'
      );

      InvoiceCanonicalService.SplitLineInput amountSplit = new InvoiceCanonicalService.SplitLineInput();
      amountSplit.lineId = line.Id;
      amountSplit.moveAmount = 15000;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      Id halfInvoiceId = InvoiceCanonicalService.splitInvoiceByDate(
        source.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ amountSplit }
      );
      // 半額請求（共有由来のまま）で先頭月を利用期間分割 → 水増しせずサービス合計 30000 を維持
      InvoiceCanonicalService.splitInvoiceByPeriod(
        halfInvoiceId,
        Date.newInstance(2026, 8, 1),
        Date.newInstance(2026, 8, 31),
        new List<Id>{ periods[0].Id }
      );
      Test.stopTest();

      Decimal serviceTotal = 0;
      for (Invoice__c invoice : [
        SELECT Amount__c
        FROM Invoice__c
        WHERE ContractService__c = :source.ContractService__c
      ]) {
        serviceTotal += invoice.Amount__c == null ? 0 : invoice.Amount__c;
      }
      System.assertEquals(
        30000,
        serviceTotal,
        '請求日分割→利用期間分割のあとでもサービス税抜合計は変わらない'
      );
    }
  }

  @IsTest
  static void splitInvoiceByPeriod_afterAmountSplit_moveAllPeriodsKeepsHalf() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id, ContractService__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      List<Id> allPeriodIds = new List<Id>();
      for (InvoiceProduct__c period : [
        SELECT Id
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
      ]) {
        allPeriodIds.add(period.Id);
      }

      InvoiceCanonicalService.SplitLineInput amountSplit = new InvoiceCanonicalService.SplitLineInput();
      amountSplit.lineId = line.Id;
      amountSplit.moveAmount = 15000;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      Id halfInvoiceId = InvoiceCanonicalService.splitInvoiceByDate(
        source.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ amountSplit }
      );
      Id createdId = InvoiceCanonicalService.splitInvoiceByPeriod(
        halfInvoiceId,
        Date.newInstance(2026, 8, 1),
        Date.newInstance(2026, 8, 31),
        allPeriodIds
      );
      Test.stopTest();

      Invoice__c created = [
        SELECT Amount__c
        FROM Invoice__c
        WHERE Id = :createdId
      ];
      System.assertEquals(
        15000,
        created.Amount__c,
        '半額請求の全期間移動でも満額（30000）に膨らまない'
      );

      Decimal serviceTotal = 0;
      for (Invoice__c invoice : [
        SELECT Amount__c
        FROM Invoice__c
        WHERE ContractService__c = :source.ContractService__c
      ]) {
        serviceTotal += invoice.Amount__c == null ? 0 : invoice.Amount__c;
      }
      System.assertEquals(30000, serviceTotal);
    }
  }

  @IsTest
  static void updateInvoiceBillingHeader_updatesSnapshots() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c invoice = [
        SELECT Id, BillingAddresseeSnapShot__c, PaymentTermSnapShot__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      String originalPaymentTerm = invoice.PaymentTermSnapShot__c;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.updateInvoiceBillingHeader(
        invoice.Id,
        null,
        '変更後宛名 御中',
        'new-to@example.com',
        'new-cc@example.com',
        'new-bcc@example.com',
        ContractTestDataFactory.TENANT_PAYMENT_TERM_NEXT_MONTH_END,
        8
      );
      Test.stopTest();

      Invoice__c updated = [
        SELECT
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c,
          PaymentTermSnapShot__c,
          TaxPercent__c,
          TaxAmount__c,
          Amount__c,
          IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        '変更後宛名 御中',
        updated.BillingAddresseeSnapShot__c
      );
      System.assertEquals(
        'new-to@example.com',
        updated.BillingEmailToSnapShot__c
      );
      System.assertEquals(
        originalPaymentTerm,
        updated.PaymentTermSnapShot__c,
        '支払条件 SnapShot はプレビュー編集で変えない'
      );
      System.assertEquals(
        8,
        TaxCalculationUtil.fromPercentFieldStorage(updated.TaxPercent__c),
        '税率は表示％で保存される'
      );
      System.assertEquals(
        TaxCalculationUtil.calculateTaxAmount(updated.Amount__c, 8),
        updated.TaxAmount__c,
        '税率変更時は税額を再計算する'
      );
      System.assertEquals(true, updated.IsManuallyAdjusted__c);
    }
  }

  @IsTest
  static void updateInvoiceHeaderAndDates_updatesDatesAndHeaderInOneCall() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c invoice = [
        SELECT Id, PaymentTermSnapShot__c, Amount__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      String originalPaymentTerm = invoice.PaymentTermSnapShot__c;
      Date newInvoiceDate = Date.newInstance(2026, 8, 20);
      Date newPaymentDate = Date.newInstance(2026, 9, 30);

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.updateInvoiceHeaderAndDates(
        invoice.Id,
        newInvoiceDate,
        newPaymentDate,
        null,
        '一体保存宛名 御中',
        'combined-to@example.com',
        'combined-cc@example.com',
        'combined-bcc@example.com',
        ContractTestDataFactory.TENANT_PAYMENT_TERM_NEXT_MONTH_END,
        8
      );
      Test.stopTest();

      Invoice__c updated = [
        SELECT
          InvoiceDate__c,
          PaymentScheduledDate__c,
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c,
          PaymentTermSnapShot__c,
          TaxPercent__c,
          TaxAmount__c,
          Amount__c,
          IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(newInvoiceDate, updated.InvoiceDate__c);
      System.assertEquals(newPaymentDate, updated.PaymentScheduledDate__c);
      System.assertEquals(
        '一体保存宛名 御中',
        updated.BillingAddresseeSnapShot__c
      );
      System.assertEquals(
        'combined-to@example.com',
        updated.BillingEmailToSnapShot__c
      );
      System.assertEquals(
        originalPaymentTerm,
        updated.PaymentTermSnapShot__c,
        '支払条件 SnapShot はプレビュー編集で変えない'
      );
      System.assertEquals(
        8,
        TaxCalculationUtil.fromPercentFieldStorage(updated.TaxPercent__c)
      );
      System.assertEquals(
        TaxCalculationUtil.calculateTaxAmount(updated.Amount__c, 8),
        updated.TaxAmount__c
      );
      System.assertEquals(true, updated.IsManuallyAdjusted__c);
    }
  }

  @IsTest
  static void previewEdits_doNotMutateUpstreamMasters() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );

      Invoice__c invoice = [
        SELECT
          Id,
          BillingAccountSnapShot__c,
          InvoiceDate__c,
          PaymentScheduledDate__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoice.Id
        LIMIT 1
      ];
      List<InvoiceProduct__c> periodBefore = [
        SELECT Id, Amount__c, InvoiceBucketKey__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
        ORDER BY Id
      ];
      BillingAccount__c baBefore = [
        SELECT
          Id,
          BillingAddressee__c,
          BillingEmailTo__c,
          PaymentTerm__c,
          BillingDayOfMonth__c
        FROM BillingAccount__c
        WHERE Id = :invoice.BillingAccountSnapShot__c
      ];
      ContractHistory__c historyBefore = [
        SELECT Id, historystatus__c, Name
        FROM ContractHistory__c
        WHERE Id = :fixture.history.Id
      ];
      ContractService__c serviceBefore = [
        SELECT Id, BiilingAcccount__c, Name
        FROM ContractService__c
        WHERE
          Id IN (
            SELECT ContractService__c
            FROM ContractHistory__c
            WHERE Id = :fixture.history.Id
          )
        LIMIT 1
      ];

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.updateLineAmount(line.Id, 30001);
      InvoiceCanonicalService.updateInvoiceDates(
        invoice.Id,
        Date.newInstance(2026, 8, 15),
        Date.newInstance(2026, 9, 30)
      );
      InvoiceCanonicalService.updateInvoiceBillingHeader(
        invoice.Id,
        baBefore.Id,
        '編集後宛名',
        'edited@example.com',
        'edited-cc@example.com',
        'edited-bcc@example.com',
        ContractTestDataFactory.TENANT_PAYMENT_TERM_NEXT_MONTH_END,
        null
      );
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 1;
      InvoiceCanonicalService.splitInvoiceByDate(
        invoice.Id,
        Date.newInstance(2026, 10, 1),
        Date.newInstance(2026, 10, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      List<InvoiceProduct__c> periodAfter = [
        SELECT Id, Amount__c, InvoiceBucketKey__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
        ORDER BY Id
      ];
      System.assertEquals(periodBefore.size(), periodAfter.size());
      for (Integer i = 0; i < periodBefore.size(); i++) {
        System.assertEquals(
          periodBefore[i].Amount__c,
          periodAfter[i].Amount__c
        );
        System.assertEquals(
          periodBefore[i].InvoiceBucketKey__c,
          periodAfter[i].InvoiceBucketKey__c
        );
      }

      BillingAccount__c baAfter = [
        SELECT
          BillingAddressee__c,
          BillingEmailTo__c,
          PaymentTerm__c,
          BillingDayOfMonth__c
        FROM BillingAccount__c
        WHERE Id = :baBefore.Id
      ];
      System.assertEquals(
        baBefore.BillingAddressee__c,
        baAfter.BillingAddressee__c
      );
      System.assertEquals(
        baBefore.BillingEmailTo__c,
        baAfter.BillingEmailTo__c
      );
      System.assertEquals(baBefore.PaymentTerm__c, baAfter.PaymentTerm__c);
      System.assertEquals(
        baBefore.BillingDayOfMonth__c,
        baAfter.BillingDayOfMonth__c
      );

      ContractHistory__c historyAfter = [
        SELECT historystatus__c, Name
        FROM ContractHistory__c
        WHERE Id = :historyBefore.Id
      ];
      System.assertEquals(
        historyBefore.historystatus__c,
        historyAfter.historystatus__c
      );
      System.assertEquals(historyBefore.Name, historyAfter.Name);

      ContractService__c serviceAfter = [
        SELECT BiilingAcccount__c, Name
        FROM ContractService__c
        WHERE Id = :serviceBefore.Id
      ];
      System.assertEquals(
        serviceBefore.BiilingAcccount__c,
        serviceAfter.BiilingAcccount__c
      );
      System.assertEquals(serviceBefore.Name, serviceAfter.Name);

      Invoice__c invoiceAfter = [
        SELECT BillingAddresseeSnapShot__c, BillingEmailToSnapShot__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        '編集後宛名',
        invoiceAfter.BillingAddresseeSnapShot__c
      );
      System.assertEquals(
        'edited@example.com',
        invoiceAfter.BillingEmailToSnapShot__c
      );
    }
  }

  @IsTest
  static void splitInvoiceByBillingAccount_movesAmount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id, BillingAccountSnapShot__c, ContractService__r.Account__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      BillingAccount__c otherBa = new BillingAccount__c(
        Account__c = source.ContractService__r.Account__c,
        BillingAddressee__c = '別請求先 御中',
        BillingEmailTo__c = 'other@example.com',
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_15,
        AdjustInvoiceDateToBusinessDay__c = false
      );
      ContractTestDataFactory.applyRequiredFields(otherBa);
      insert otherBa;

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 5000;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      Id createdId = InvoiceCanonicalService.splitInvoiceByBillingAccount(
        source.Id,
        otherBa.Id,
        null,
        null,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      Invoice__c created = [
        SELECT
          Amount__c,
          BillingAccountSnapShot__c,
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c,
          PaymentTermSnapShot__c,
          IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :createdId
      ];
      System.assertEquals(5000, created.Amount__c);
      System.assertEquals(otherBa.Id, created.BillingAccountSnapShot__c);
      // 分割新規請求は作成時 BA マスタをハードコードで SnapShot
      System.assertEquals('別請求先 御中', created.BillingAddresseeSnapShot__c);
      System.assertEquals(
        'other@example.com',
        created.BillingEmailToSnapShot__c
      );
      System.assertEquals(
        ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        created.PaymentTermSnapShot__c
      );
      System.assertEquals(true, created.IsManuallyAdjusted__c);
    }
  }

  @IsTest
  static void revertService_deletesCanonicalInvoices() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :fixture.history.Id
        ]
      );

      Test.startTest();
      EstimateRevertInvoiceService.adjustForRevertedToEstimateHistories(
        new List<ContractHistory__c>{ fixture.history }
      );
      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :fixture.history.Id
        ]
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :fixture.history.Id
        ]
      );
    }
  }

  @IsTest
  static void historyDelete_clearsCanonicalForEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      // 非 Ordered に誤って残った請求でも、履歴削除で Invoice が孤児にならないこと
      Fixture fixture = createOrderedFixture();
      Id historyId = fixture.history.Id;
      Id contractProductId = [
        SELECT Id
        FROM ContractProduct__c
        WHERE ContractHistory__c = :historyId
        LIMIT 1
      ]
      .Id;

      fixture.history.historystatus__c = 'Estimate';
      update fixture.history;
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :historyId
        ],
        '差し戻しで請求は消える'
      );

      insert new InvoiceProduct__c(
        ContractHistory__c = historyId,
        ContractProduct__c = contractProductId,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30),
        Amount__c = 1000
      );
      insert new Invoice__c(
        ContractHistory__c = historyId,
        ContractService__c = fixture.history.ContractService__c,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100
      );

      Test.startTest();
      delete fixture.history;
      Test.stopTest();

      System.assertEquals(
        0,
        [SELECT COUNT() FROM Invoice__c WHERE ContractHistory__c = :historyId]
      );
    }
  }

  @IsTest
  static void rebuildForHistories_rejectsNonOrderedHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      fixture.history.historystatus__c = 'Estimate';
      update fixture.history;

      Boolean thrown = false;
      try {
        InvoiceCanonicalService.rebuildForHistories(
          new Set<Id>{ fixture.history.Id }
        );
      } catch (InvoiceCanonicalService.InvoiceEditException ex) {
        thrown = true;
        System.assertEquals(
          '期間明細・請求・請求明細は受注済み（Ordered）の契約履歴にのみ作成できます。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown, '非 Ordered への rebuild は拒否');
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :fixture.history.Id
        ],
        '見積状態では正本が作られない'
      );
      ContractHistory__c still = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :fixture.history.Id
      ];
      System.assertEquals('Estimate', still.historystatus__c);
    }
  }

  @IsTest
  static void historyDelete_blocksWhenCanonicalInvoiceLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c invoice = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      invoice.SystemIntegrationDate__c = Date.today();
      update invoice;

      fixture.history.historystatus__c = 'Estimate';
      Boolean reverted = false;
      try {
        update fixture.history;
      } catch (DmlException ex) {
        reverted = true;
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          ex.getDmlMessage(0)
        );
      }
      System.assertEquals(
        true,
        reverted,
        'ロック済み請求がある Version は差し戻し不可'
      );

      ContractHistory__c stillHistory = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :fixture.history.Id
      ];
      System.assertEquals(
        'Ordered',
        stillHistory.historystatus__c,
        '差し戻し失敗後も受注のまま'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE
            Id = :invoice.Id
            AND SystemIntegrationDate__c != NULL
        ],
        '連携済請求は残る'
      );
    }
  }

  @IsTest
  static void getInvoicePreview_readsCanonicalAndBackfills() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      // 正本なし（期間明細のみ）→ プレビュー取得でバックフィル
      Test.startTest();
      OrderCreateController.InvoicePreviewDto preview = OrderCreateController.getInvoicePreview(
        fixture.history.Id
      );
      Test.stopTest();

      System.assertEquals(1, preview.invoiceCount);
      System.assertEquals(30000, preview.totalAmount);
      System.assertNotEquals(null, preview.invoices[0].invoiceId);
      System.assertEquals(1, preview.lineCount);
    }
  }

  @IsTest
  static void previewEdit_allowsUnlockedInvoiceWhenSiblingLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 10000;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Id unlockedId = InvoiceCanonicalService.splitInvoiceByDate(
        source.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );

      // 分割元（残）を消込済にしてロック。新請求は未ロックのまま
      update new Invoice__c(
        Id = source.Id,
        PaymentClearingCompletedDate__c = Date.today()
      );

      InvoiceLine__c unlockedLine = [
        SELECT Id, Amount__c, Invoice__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :unlockedId
        LIMIT 1
      ];
      Decimal nextAmount = unlockedLine.Amount__c + 1;

      Test.startTest();
      InvoiceCanonicalService.updateLineAmount(unlockedLine.Id, nextAmount);
      Boolean lockedBlocked = false;
      try {
        InvoiceCanonicalService.updateInvoiceDates(
          source.Id,
          Date.newInstance(2026, 8, 1),
          Date.newInstance(2026, 8, 31)
        );
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        lockedBlocked = true;
        System.assertEquals(
          InvoiceLockUtil.INVOICE_EDIT_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      Test.stopTest();

      Invoice__c unlocked = [
        SELECT Amount__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :unlockedId
      ];
      System.assertEquals(nextAmount, unlocked.Amount__c);
      System.assertEquals(true, unlocked.IsManuallyAdjusted__c);
      System.assertEquals(true, lockedBlocked, 'ロック請求の編集は拒否');

      Invoice__c lockedStill = [
        SELECT
          Amount__c,
          InvoiceDate__c,
          PaymentClearingCompletedDate__c,
          IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(
        Date.today(),
        lockedStill.PaymentClearingCompletedDate__c
      );
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        lockedStill.InvoiceDate__c,
        'ロック側の請求日は変わらない'
      );
      System.assertEquals(
        20000,
        lockedStill.Amount__c,
        'ロック側の税抜は分割残のまま'
      );
    }
  }

  private class Fixture {
    ContractHistory__c history;
  }

  private static Fixture createOrderedFixture() {
    Account account = ContractTestDataFactory.insertAccount(
      'Canonical Invoice Account'
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_1,
      AdjustInvoiceDateToBusinessDay__c = false
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;

    ContractService__c service = new ContractService__c(
      Name = 'Canonical Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;

    ContractHistory__c history = new ContractHistory__c(
      Name = 'Canonical History',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2026, 8, 31)
    );
    insert history;

    Product2 product = ContractTestDataFactory.buildProduct(
      'Canonical Product'
    );
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    ContractTestDataFactory.insertProduct(product);

    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 10000,
      Unit__c = 'ID',
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2026, 8, 31),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = 'New'
    );
    insert contractProduct;

    Date invoiceDate = Date.newInstance(2026, 6, 1);
    Date paymentDate = Date.newInstance(2026, 6, 30);
    String bucketKey = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
      billingAccount.Id,
      history.Id,
      invoiceDate,
      paymentDate
    );
    insert new List<InvoiceProduct__c>{
      new InvoiceProduct__c(
        ContractHistory__c = history.Id,
        ContractProduct__c = contractProduct.Id,
        InvoiceBucketKey__c = bucketKey,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30),
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Amount__c = 10000,
        TaxPercent__c = 0.1
      ),
      new InvoiceProduct__c(
        ContractHistory__c = history.Id,
        ContractProduct__c = contractProduct.Id,
        InvoiceBucketKey__c = bucketKey,
        StartDate__c = Date.newInstance(2026, 7, 1),
        Enddate__c = Date.newInstance(2026, 7, 31),
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Amount__c = 10000,
        TaxPercent__c = 0.1
      ),
      new InvoiceProduct__c(
        ContractHistory__c = history.Id,
        ContractProduct__c = contractProduct.Id,
        InvoiceBucketKey__c = bucketKey,
        StartDate__c = Date.newInstance(2026, 8, 1),
        Enddate__c = Date.newInstance(2026, 8, 31),
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Amount__c = 10000,
        TaxPercent__c = 0.1
      )
    };

    Fixture fixture = new Fixture();
    fixture.history = history;
    return fixture;
  }
}
