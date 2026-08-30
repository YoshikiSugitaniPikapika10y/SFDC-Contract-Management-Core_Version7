/**
 * 契約ライフサイクル横断シナリオ。
 * 期間明細 + 請求正本（Invoice / InvoiceLine）+ ロック / 分割 / 端数をカバーする。
 */
@IsTest
private class ContractLifecycleScenarioTest {
  private static final Date TERM_START = Date.newInstance(2026, 4, 1);
  private static final Date TERM_END = Date.newInstance(2027, 3, 31);
  private static final Date CHANGE_EFFECTIVE_DATE = Date.newInstance(
    2026,
    5,
    1
  );
  private static final Date PRE_EFFECTIVE_END = Date.newInstance(2026, 4, 30);
  private static final Date APRIL_INVOICED_DATE = Date.newInstance(2026, 4, 10);

  private static final Decimal V1_UNIT_PRICE = 30000;
  private static final Decimal V2_UNIT_PRICE = 50000;
  private static final Decimal V1_QUANTITY = 1;
  private static final Decimal V3_QUANTITY = 2;

  private static final String INVOICE_SETTING_PREPAID = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
  private static final String INVOICE_SETTING_MONTHLY = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
  private static final String BILLING_TYPE_RECURRING = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
  private static final String BILLING_TYPE_ONE_TIME = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
  private static final Integer BILLING_DAY_OF_MONTH = ContractTestDataFactory.TENANT_BILLING_DAY_5;

  private class ScenarioContext {
    public Account account;
    public ContractService__c service;
    public BillingAccount__c billingAccount;
    public Product2 product;
    public ContractHistory__c priorHistory;
    public ContractHistory__c changeHistory;
    public ContractProduct__c priorContractProduct;
  }

  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  // -------------------------------------------------------------------------
  // 001 / 002 / 003
  // -------------------------------------------------------------------------

  @IsTest
  static void scenario001_changePriceIncrease_allUninvoiced() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ScenarioContext context = createPriceChangeContext('LC001', false);

      Test.startTest();
      orderHistory(context.changeHistory);
      Test.stopTest();

      assertV1PeriodLines(context.priorHistory.Id);
      assertV2PeriodLinesPriceOnly(context.changeHistory.Id);
      // 一括前払: V1 は税抜 360000 を請求1件・明細1行へ集約（Canonical 実測と同型）
      assertInvoiceBundle(context.priorHistory.Id, 1, 1, 360000, null);
      // V2 Change 差分ネット 220000（±11ヶ月）。明細はマイナス/プラスの2行
      assertInvoiceBundle(context.changeHistory.Id, 1, 2, 220000, null);
      assertServicePeriodLineTotals(context.service.Id, 34, 580000);
    }
  }

  @IsTest
  static void scenario002_changePriceIncrease_invoiceLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ScenarioContext context = createPriceChangeContext('LC002', true);

      Test.startTest();
      orderHistory(context.changeHistory);
      Test.stopTest();

      assertV1PeriodLines(context.priorHistory.Id);
      assertV2PeriodLinesPriceOnly(context.changeHistory.Id);
      assertInvoiceBundle(
        context.priorHistory.Id,
        1,
        1,
        360000,
        APRIL_INVOICED_DATE
      );
      assertInvoiceBundle(context.changeHistory.Id, 1, 2, 220000, null);
      Integer locked = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE
          ContractHistory__c = :context.priorHistory.Id
          AND SystemIntegrationDate__c = :APRIL_INVOICED_DATE
      ];
      System.assertEquals(1, locked, 'V1 請求ロックが残る');
    }
  }

  @IsTest
  static void scenario003_changePriceAndQuantityIncrease() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ScenarioContext context = createQtyPriceChangeContext('LC003');

      Test.startTest();
      orderHistory(context.changeHistory);
      Test.stopTest();

      assertV1PeriodLines(context.priorHistory.Id);
      // V2: 11ヶ月 × (100000 - 30000) = 770000
      List<InvoiceProduct__c> v2Lines = [
        SELECT Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :context.changeHistory.Id
      ];
      System.assertEquals(22, v2Lines.size(), 'V2 期間明細 ±11ヶ月');
      System.assertEquals(770000, sumAmounts(v2Lines), 'V2 期間明細合計');
      assertInvoiceBundle(context.priorHistory.Id, 1, 1, 360000, null);
      assertInvoiceBundle(context.changeHistory.Id, 1, 2, 770000, null);
    }
  }

  // -------------------------------------------------------------------------
  // 004 短縮フルライフサイクル（3ヶ月）
  // -------------------------------------------------------------------------

  @IsTest
  static void scenario004_shortLifecycle_newChangeRenewCancel() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2026, 6, 30);
      Date changeEff = Date.newInstance(2026, 5, 1);
      Date renewStart = Date.newInstance(2026, 7, 1);
      Date renewEnd = Date.newInstance(2026, 9, 30);
      Date cancelDate = Date.newInstance(2026, 10, 1);

      ScenarioContext base = createBaseService(
        'LC004',
        INVOICE_SETTING_PREPAID
      );
      ContractHistory__c v1 = insertOrderedNew(
        base,
        'LC004 V1',
        1,
        termStart,
        termEnd,
        V1_UNIT_PRICE,
        1
      );

      ContractHistory__c v2 = insertChangeEstimate(
        base,
        v1,
        'LC004 V2',
        2,
        termStart,
        termEnd,
        changeEff,
        V1_UNIT_PRICE,
        V2_UNIT_PRICE,
        1,
        1
      );

      ContractHistory__c v3 = new ContractHistory__c(
        Name = 'LC004 V3 Renew',
        ContractService__c = base.service.Id,
        Type__c = 'Renew',
        historystatus__c = 'Estimate',
        Version__c = 3,
        CurrentTermStartDate__c = renewStart,
        CurrentTermEndDate__c = renewEnd,
        EffectiveDate__c = renewStart,
        PreviousHistory__c = v2.Id
      );
      insert v3;
      insert new ContractProduct__c(
        ContractHistory__c = v3.Id,
        Product__c = base.product.Id,
        Quantity__c = 1,
        UnitPrice__c = V2_UNIT_PRICE,
        Amount__c = V2_UNIT_PRICE,
        StartDate__c = renewStart,
        Enddate__c = renewEnd,
        InvoiceSetting__c = INVOICE_SETTING_PREPAID,
        BillingType__c = BILLING_TYPE_RECURRING,
        Type__c = 'Renew'
      );

      Test.startTest();
      orderHistory(v2);
      orderHistory(v3);
      insert new ContractHistory__c(
        Name = 'LC004 V4 Cancel',
        ContractService__c = base.service.Id,
        Type__c = 'Cancel',
        historystatus__c = 'Ordered',
        Version__c = 4,
        CurrentTermStartDate__c = cancelDate,
        CurrentTermEndDate__c = cancelDate,
        EffectiveDate__c = cancelDate,
        PreviousHistory__c = v3.Id
      );
      Test.stopTest();

      Map<Id, Integer> periodCounts = new Map<Id, Integer>();
      Integer cancelPeriodCount = 0;
      for (AggregateResult row : [
        SELECT
          ContractHistory__c historyId,
          ContractHistory__r.Type__c historyType,
          COUNT(Id) rowCount
        FROM InvoiceProduct__c
        WHERE ContractHistory__r.ContractService__c = :base.service.Id
        GROUP BY ContractHistory__c, ContractHistory__r.Type__c
      ]) {
        Integer rowCount = (Integer) row.get('rowCount');
        periodCounts.put(
          (Id) row.get('historyId'),
          rowCount
        );
        if ((String) row.get('historyType') == 'Cancel') {
          cancelPeriodCount += rowCount;
        }
      }
      Map<Id, Integer> invoiceCounts = new Map<Id, Integer>();
      Integer cancelInvoiceCount = 0;
      for (AggregateResult row : [
        SELECT
          ContractHistory__c historyId,
          ContractHistory__r.Type__c historyType,
          COUNT(Id) rowCount
        FROM Invoice__c
        WHERE ContractHistory__r.ContractService__c = :base.service.Id
        GROUP BY ContractHistory__c, ContractHistory__r.Type__c
      ]) {
        Integer rowCount = (Integer) row.get('rowCount');
        invoiceCounts.put(
          (Id) row.get('historyId'),
          rowCount
        );
        if ((String) row.get('historyType') == 'Cancel') {
          cancelInvoiceCount += rowCount;
        }
      }
      System.assertEquals(3, periodCounts.get(v1.Id), 'V1 3ヶ月');
      System.assert(invoiceCounts.get(v1.Id) >= 1, 'V1 請求あり');
      System.assert(invoiceCounts.get(v2.Id) >= 1, 'V2 請求あり');
      System.assert(invoiceCounts.get(v3.Id) >= 1, 'Renew 請求あり');
      System.assertEquals(0, cancelPeriodCount, 'Cancel に期間明細なし');
      System.assertEquals(0, cancelInvoiceCount, 'Cancel に請求なし');
    }
  }

  // -------------------------------------------------------------------------
  // 005 分割3種（請求日 / 金額 / BA）
  // -------------------------------------------------------------------------

  @IsTest
  static void scenario005_threeSplitTypes() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2026, 6, 30);

      ScenarioContext base = createBaseService(
        'LC005',
        INVOICE_SETTING_PREPAID
      );
      base.service.TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10);
      update base.service;

      ContractHistory__c history = insertOrderedNew(
        base,
        'LC005 V1',
        1,
        termStart,
        termEnd,
        10000,
        1
      );
      // 3ヶ月×10000 = 30000 → 請求1 / 明細1
      Invoice__c source = [
        SELECT Id, Amount__c, BillingAccountSnapShot__c
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id, Amount__c, UnitPrice__c, Quantity__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      System.assertEquals(30000, source.Amount__c);

      BillingAccount__c ba2 = new BillingAccount__c(
        Account__c = base.account.Id,
        BillingAddressee__c = '分割先宛名 御中',
        BillingEmailTo__c = 'split-to@example.com'
      );
      ContractTestDataFactory.applyOnOrAfterBillingDay(ba2, BILLING_DAY_OF_MONTH);
      ContractTestDataFactory.applyPaymentMonthEnd(ba2, 1);
      ContractTestDataFactory.applyRequiredFields(ba2);
      insert ba2;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;

      Test.startTest();
      // 1) 請求日分割（金額 10000 移動）
      InvoiceCanonicalService.SplitLineInput dateSplit = new InvoiceCanonicalService.SplitLineInput();
      dateSplit.lineId = line.Id;
      dateSplit.moveAmount = 10000;
      Id dateSplitInvoiceId = InvoiceCanonicalService.splitInvoiceByDate(
        source.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ dateSplit }
      );
      System.assertEquals(
        10000,
        [SELECT Amount__c FROM Invoice__c WHERE Id = :dateSplitInvoiceId]
        .Amount__c,
        '請求日分割の新請求'
      );

      // 残請求を再取得して 2) 金額分割
      Invoice__c remainAfterDate = [
        SELECT Id, Amount__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(20000, remainAfterDate.Amount__c);
      InvoiceLine__c remainLine = [
        SELECT Id, Amount__c, UnitPrice__c, Quantity__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :remainAfterDate.Id
        LIMIT 1
      ];
      InvoiceCanonicalService.SplitLineInput amountSplit = new InvoiceCanonicalService.SplitLineInput();
      amountSplit.lineId = remainLine.Id;
      amountSplit.moveAmount = 8000;
      Id amountSplitInvoiceId = InvoiceCanonicalService.splitInvoiceByDate(
        remainAfterDate.Id,
        Date.newInstance(2026, 8, 1),
        Date.newInstance(2026, 8, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ amountSplit }
      );
      System.assertEquals(
        8000,
        [SELECT Amount__c FROM Invoice__c WHERE Id = :amountSplitInvoiceId]
        .Amount__c,
        '金額分割の新請求'
      );

      // 3) BA 分割（残請求から）
      Invoice__c remainForBa = [
        SELECT Id, Amount__c, InvoiceDate__c, PaymentScheduledDate__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      InvoiceLine__c baLine = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :remainForBa.Id
        LIMIT 1
      ];
      Decimal moveBa = baLine.Amount__c == null
        ? 0
        : (baLine.Amount__c / 2).setScale(0, System.RoundingMode.HALF_UP);
      System.assert(moveBa > 0, 'BA 分割できる残額があること');
      InvoiceCanonicalService.SplitLineInput baSplit = new InvoiceCanonicalService.SplitLineInput();
      baSplit.lineId = baLine.Id;
      baSplit.moveAmount = moveBa;
      Id baSplitInvoiceId = InvoiceCanonicalService.splitInvoiceByBillingAccount(
        remainForBa.Id,
        ba2.Id,
        remainForBa.InvoiceDate__c,
        remainForBa.PaymentScheduledDate__c,
        new List<InvoiceCanonicalService.SplitLineInput>{ baSplit }
      );

      Invoice__c baCreated = [
        SELECT Amount__c, BillingAccountSnapShot__c, BillingAddresseeSnapShot__c
        FROM Invoice__c
        WHERE Id = :baSplitInvoiceId
      ];
      Integer invoiceCount = [
        SELECT COUNT()
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
      ];
      Test.stopTest();

      System.assertEquals(moveBa, baCreated.Amount__c);
      System.assertEquals(ba2.Id, baCreated.BillingAccountSnapShot__c);
      System.assertEquals(4, invoiceCount, '元1 + 分割3 = 請求4件');
    }
  }

  // -------------------------------------------------------------------------
  // 005b 請求明細を既存の別請求へ移す
  // -------------------------------------------------------------------------

  @IsTest
  static void scenario005b_moveLinesToExistingInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2026, 6, 30);
      ScenarioContext base = createBaseService(
        'LC005b',
        INVOICE_SETTING_PREPAID
      );
      base.service.TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10);
      update base.service;

      ContractHistory__c history = insertOrderedNew(
        base,
        'LC005b V1',
        1,
        termStart,
        termEnd,
        10000,
        1
      );
      Invoice__c target = [
        SELECT Id, Amount__c
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
        LIMIT 1
      ];
      InvoiceLine__c line = [
        SELECT Id
        FROM InvoiceLine__c
        WHERE Invoice__c = :target.Id
        LIMIT 1
      ];
      System.assertEquals(30000, target.Amount__c);

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 10000;
      Test.startTest();
      Id sourceInvoiceId = InvoiceCanonicalService.splitInvoiceByDate(
        target.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      InvoiceLine__c movedLine = [
        SELECT Id, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :sourceInvoiceId
        LIMIT 1
      ];
      System.assertEquals(10000, movedLine.Amount__c);

      InvoiceCanonicalService.moveLinesToExistingInvoice(
        sourceInvoiceId,
        target.Id,
        new List<Id>{ movedLine.Id }
      );
      Test.stopTest();

      System.assertEquals(
        0,
        [SELECT COUNT() FROM Invoice__c WHERE Id = :sourceInvoiceId],
        '全明細移動後は移動元請求が削除される'
      );
      Invoice__c afterTarget = [
        SELECT Amount__c, PeriodLineAmountTotal__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :target.Id
      ];
      System.assertEquals(30000, afterTarget.Amount__c, '移動先に金額が戻る');
      System.assertEquals(
        30000,
        afterTarget.PeriodLineAmountTotal__c,
        '調整前請求額も合算'
      );
      System.assertEquals(true, afterTarget.IsManuallyAdjusted__c);
      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM InvoiceLine__c
          WHERE Invoice__c = :target.Id
        ],
        '合算せず別行のまま載る'
      );
    }
  }

  // -------------------------------------------------------------------------
  // 006 端数調整
  // -------------------------------------------------------------------------

  @IsTest
  static void scenario006_roundingAdjustmentPersists() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2026, 6, 30);
      ScenarioContext base = createBaseService(
        'LC006',
        INVOICE_SETTING_PREPAID
      );
      base.service.TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10);
      update base.service;

      ContractHistory__c history = insertOrderedNew(
        base,
        'LC006 V1',
        1,
        termStart,
        termEnd,
        10000,
        1
      );
      InvoiceLine__c line = [
        SELECT Id, Invoice__c, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :history.Id
        LIMIT 1
      ];
      System.assertEquals(30000, line.Amount__c);

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.updateLineAmount(line.Id, 30001);
      Test.stopTest();

      Invoice__c invoice = [
        SELECT Amount__c, IsManuallyAdjusted__c, TaxAmount__c
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

  /**
   * 端数を意図的に積み上げる:
   * 手動調整(+7) → 分割 → 再調整(+6) → 再分割。
   * Amount と PeriodLineAmountTotal のギャップが複数請求に残ることを見る。
   */
  @IsTest
  static void scenario006b_manyRoundingGapsAcrossSplits() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2026, 6, 30);
      ScenarioContext base = createBaseService(
        'LC006b',
        INVOICE_SETTING_PREPAID
      );
      base.service.TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10);
      update base.service;

      ContractHistory__c history = insertOrderedNew(
        base,
        'LC006b V1',
        1,
        termStart,
        termEnd,
        10000,
        1
      );
      Invoice__c root = [
        SELECT Id, Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
        LIMIT 1
      ];
      InvoiceLine__c rootLine = [
        SELECT Id
        FROM InvoiceLine__c
        WHERE Invoice__c = :root.Id
        LIMIT 1
      ];
      System.assertEquals(30000, root.Amount__c);
      System.assertEquals(30000, root.PeriodLineAmountTotal__c);

      InvoiceCanonicalService.testHasEditPreviewPermission = true;

      Test.startTest();
      // 1) 奇数端数を載せる（調整前 30000 / 金額 30007 → ギャップ +7）
      InvoiceCanonicalService.updateLineAmount(rootLine.Id, 30007);

      // 2) 分割: 移す 10000。ギャップは残側に残る想定
      InvoiceCanonicalService.SplitLineInput split1 = new InvoiceCanonicalService.SplitLineInput();
      split1.lineId = rootLine.Id;
      split1.moveAmount = 10000;
      Id julyId = InvoiceCanonicalService.splitInvoiceByDate(
        root.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split1 }
      );

      Invoice__c julyAfter1 = [
        SELECT Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :julyId
      ];
      Invoice__c remainAfter1 = [
        SELECT Id, Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :root.Id
      ];
      InvoiceLine__c remainLine = [
        SELECT Id
        FROM InvoiceLine__c
        WHERE Invoice__c = :remainAfter1.Id
        LIMIT 1
      ];
      System.assertEquals(20007, remainAfter1.Amount__c, '1回目分割後の残額');
      // 調整前按分: 30000×10000/30007 → 9998（HALF_UP）、残 20002。ギャップ+5 が残側
      System.assertEquals(10000, julyAfter1.Amount__c);
      System.assertEquals(9998, julyAfter1.PeriodLineAmountTotal__c);
      System.assertEquals(
        20002,
        remainAfter1.PeriodLineAmountTotal__c,
        '1回目分割後の残側調整前'
      );
      System.assertEquals(
        30000,
        julyAfter1.PeriodLineAmountTotal__c +
        remainAfter1.PeriodLineAmountTotal__c,
        '1回目分割で調整前合計は保存'
      );

      // 3) 残側にさらに端数を積む（20007 → 20013）
      InvoiceCanonicalService.updateLineAmount(remainLine.Id, 20013);

      // 4) 割り切れない金額で再分割
      InvoiceCanonicalService.SplitLineInput split2 = new InvoiceCanonicalService.SplitLineInput();
      split2.lineId = remainLine.Id;
      split2.moveAmount = 7777;
      Id augId = InvoiceCanonicalService.splitInvoiceByDate(
        remainAfter1.Id,
        Date.newInstance(2026, 8, 1),
        Date.newInstance(2026, 8, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split2 }
      );

      List<Invoice__c> invoices = [
        SELECT
          Id,
          Amount__c,
          PeriodLineAmountTotal__c,
          TaxAmount__c,
          IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
        ORDER BY InvoiceDate__c ASC NULLS LAST, CreatedDate ASC
      ];
      Invoice__c aug = [
        SELECT Amount__c
        FROM Invoice__c
        WHERE Id = :augId
      ];
      Test.stopTest();

      System.assertEquals(3, invoices.size(), '元 + 分割2 = 3請求');

      Decimal amountSum = 0;
      Decimal periodSum = 0;
      Integer gapCount = 0;
      for (Invoice__c inv : invoices) {
        amountSum += inv.Amount__c == null ? 0 : inv.Amount__c;
        periodSum += inv.PeriodLineAmountTotal__c == null
          ? 0
          : inv.PeriodLineAmountTotal__c;
        System.assertEquals(
          true,
          inv.IsManuallyAdjusted__c,
          '端数経路の請求は手動調整'
        );
        System.assertEquals(
          TaxCalculationUtil.calculateTaxAmount(inv.Amount__c, 10),
          inv.TaxAmount__c,
          '奇数税抜でも税額は DOWN 丸め'
        );
        if (
          inv.Amount__c != null &&
          inv.PeriodLineAmountTotal__c != null &&
          inv.Amount__c != inv.PeriodLineAmountTotal__c
        ) {
          gapCount++;
        }
      }

      System.assertEquals(
        30013,
        amountSum,
        '手動調整の積み上げ後の税抜合計（30000+7+6）'
      );
      System.assertEquals(
        30000,
        periodSum,
        '調整前請求額合計は期間明細由来のまま'
      );
      System.assert(
        gapCount >= 2,
        'Amount≠調整前 のギャップ請求が複数残ること: ' + gapCount
      );
      Invoice__c july = [
        SELECT Amount__c
        FROM Invoice__c
        WHERE Id = :julyId
      ];
      System.assertEquals(7777, aug.Amount__c);
      System.assertEquals(10000, july.Amount__c);
    }
  }

  // -------------------------------------------------------------------------
  // 008 値引: 継続本体 + 継続値引 + 一回課金値引
  // 継続 10000×3=+30000 / 継続値引 -3000×3=-9000 / 一回値引 -5000
  // → 期間明細 7件・合計 16000
  // -------------------------------------------------------------------------

  @IsTest
  static void scenario008_recurringAndOneTimeDiscounts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2026, 6, 30);
      ScenarioContext base = createBaseService(
        'LC008',
        INVOICE_SETTING_PREPAID
      );

      Product2 discountRecurring = ContractTestDataFactory.buildProduct(
        'LC008 Disc Recurring'
      );
      discountRecurring.BillingType__c = BILLING_TYPE_RECURRING;
      discountRecurring.invoicetype__c = INVOICE_SETTING_PREPAID;
      Product2 discountOneTime = ContractTestDataFactory.buildProduct(
        'LC008 Disc OneTime'
      );
      discountOneTime.BillingType__c = BILLING_TYPE_ONE_TIME;
      discountOneTime.invoicetype__c = INVOICE_SETTING_PREPAID;
      ContractTestDataFactory.insertProducts(
        new List<Product2>{ discountRecurring, discountOneTime }
      );

      ContractHistory__c history = new ContractHistory__c(
        Name = 'LC008 V1',
        ContractService__c = base.service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert history;
      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Product__c = base.product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 10000,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = INVOICE_SETTING_PREPAID,
          BillingType__c = BILLING_TYPE_RECURRING,
          Type__c = 'New'
        ),
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Product__c = discountRecurring.Id,
          Quantity__c = 1,
          UnitPrice__c = -3000,
          Amount__c = -3000,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = INVOICE_SETTING_PREPAID,
          BillingType__c = BILLING_TYPE_RECURRING,
          Type__c = 'New'
        ),
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Product__c = discountOneTime.Id,
          Quantity__c = 1,
          UnitPrice__c = -5000,
          Amount__c = -5000,
          StartDate__c = termStart,
          Enddate__c = Date.newInstance(2026, 4, 30),
          InvoiceSetting__c = INVOICE_SETTING_PREPAID,
          BillingType__c = BILLING_TYPE_ONE_TIME,
          Type__c = 'New'
        )
      };

      Test.startTest();
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ history.Id }
      );
      Test.stopTest();

      List<InvoiceProduct__c> periodLines = [
        SELECT Amount__c, StartDate__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :history.Id
        ORDER BY StartDate__c ASC, Amount__c DESC
      ];
      System.assertEquals(7, periodLines.size(), '継続3+値引3+一回1');
      System.assertEquals(16000, sumAmounts(periodLines), '期間明細ネット');

      Integer negativeLines = 0;
      for (InvoiceProduct__c row : periodLines) {
        if (row.Amount__c != null && row.Amount__c < 0) {
          negativeLines++;
        }
      }
      System.assertEquals(
        4,
        negativeLines,
        '値引期間明細は4行（-3000×3 + -5000）'
      );

      Decimal invoiceSum = 0;
      for (Invoice__c inv : [
        SELECT Amount__c
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
      ]) {
        invoiceSum += inv.Amount__c == null ? 0 : inv.Amount__c;
      }
      System.assertEquals(16000, invoiceSum, '請求税抜合計もネット16000');
      System.assert(
        [
          SELECT COUNT()
          FROM InvoiceLine__c
          WHERE Invoice__r.ContractHistory__c = :history.Id
        ] >= 2,
        '本体と値引が請求明細に載る'
      );
    }
  }

  // -------------------------------------------------------------------------
  // 009 継続課金の歯抜け（同一商品・期間非重複）
  // 4–5月 + 7–8月（6月欠）×10000 → 期間明細4・合計40000、6月開始なし
  // -------------------------------------------------------------------------

  @IsTest
  static void scenario009_recurringPeriodGap() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date seg1Start = Date.newInstance(2026, 4, 1);
      Date seg1End = Date.newInstance(2026, 5, 31);
      Date seg2Start = Date.newInstance(2026, 7, 1);
      Date seg2End = Date.newInstance(2026, 8, 31);
      Date headerStart = seg1Start;
      Date headerEnd = seg2End;

      ScenarioContext base = createBaseService(
        'LC009',
        INVOICE_SETTING_PREPAID
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'LC009 V1',
        ContractService__c = base.service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = headerStart,
        CurrentTermEndDate__c = headerEnd,
        EffectiveDate__c = headerStart
      );
      insert history;
      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Product__c = base.product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 10000,
          StartDate__c = seg1Start,
          Enddate__c = seg1End,
          InvoiceSetting__c = INVOICE_SETTING_PREPAID,
          BillingType__c = BILLING_TYPE_RECURRING,
          Type__c = 'New'
        ),
        new ContractProduct__c(
          ContractHistory__c = history.Id,
          Product__c = base.product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 10000,
          StartDate__c = seg2Start,
          Enddate__c = seg2End,
          InvoiceSetting__c = INVOICE_SETTING_PREPAID,
          BillingType__c = BILLING_TYPE_RECURRING,
          Type__c = 'New'
        )
      };

      Test.startTest();
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ history.Id }
      );
      Test.stopTest();

      List<InvoiceProduct__c> periodLines = [
        SELECT Amount__c, StartDate__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :history.Id
        ORDER BY StartDate__c ASC
      ];
      System.assertEquals(4, periodLines.size(), '歯抜け後も4ヶ月分のみ');
      System.assertEquals(40000, sumAmounts(periodLines), '4ヶ月×10000');
      for (InvoiceProduct__c row : periodLines) {
        System.assertNotEquals(
          Date.newInstance(2026, 6, 1),
          row.StartDate__c,
          '6月の期間明細は作られない'
        );
      }
      System.assertEquals(seg1Start, periodLines[0].StartDate__c);
      System.assertEquals(seg2Start, periodLines[2].StartDate__c);

      Decimal invoiceSum = 0;
      for (Invoice__c inv : [
        SELECT Amount__c
        FROM Invoice__c
        WHERE ContractHistory__c = :history.Id
      ]) {
        invoiceSum += inv.Amount__c == null ? 0 : inv.Amount__c;
      }
      System.assertEquals(40000, invoiceSum, '請求合計も40000');
      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM InvoiceLine__c
          WHERE Invoice__r.ContractHistory__c = :history.Id
        ],
        '歯抜けは連続区間ごとに請求明細を分ける'
      );
    }
  }

  // -------------------------------------------------------------------------
  // 007a Change×2（月境界・金額ネットまで固定）
  // V1: 4–6月×10000=30000
  // V2: 5/1 に 11000 → 変更月2ヶ月×(+1000)=ネット2000（±4行）
  // V3: 6/1 に 12000 → 変更月1ヶ月×(+1000)=ネット1000（±2行）
  // -------------------------------------------------------------------------

  @IsTest
  static void scenario007a_twoChanges() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2026, 6, 30);
      Date change1 = Date.newInstance(2026, 5, 1);
      Date change2 = Date.newInstance(2026, 6, 1);

      ScenarioContext base = createBaseService(
        'LC007a',
        INVOICE_SETTING_PREPAID
      );
      List<Product2> products = new List<Product2>{ base.product };

      ContractHistory__c v1 = insertOrderedNew(
        base,
        'LC007a V1',
        1,
        termStart,
        termEnd,
        10000,
        1
      );
      List<ContractProduct__c> v1Cps = [
        SELECT Id, Product__c, UnitPrice__c, Quantity__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :v1.Id
      ];

      ContractHistory__c v2 = buildMultiProductChange(
        base.service.Id,
        v1,
        products,
        v1Cps,
        'LC007a V2',
        2,
        termStart,
        termEnd,
        change1,
        new List<Decimal>{ 11000 }
      );
      ContractHistory__c v3Estimate = buildSecondMultiProductChange(
        base.service.Id,
        v2,
        products,
        'LC007a V3',
        3,
        termStart,
        termEnd,
        change1,
        change2,
        new List<Decimal>{ 11000 },
        new List<Decimal>{ 12000 }
      );

      Test.startTest();
      orderHistory(v2);
      orderHistory(v3Estimate);

      List<InvoiceProduct__c> v1Lines = [
        SELECT Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :v1.Id
      ];
      List<InvoiceProduct__c> v2Lines = [
        SELECT Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :v2.Id
      ];
      List<InvoiceProduct__c> v3Lines = [
        SELECT Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :v3Estimate.Id
      ];
      assertInvoiceBundle(v1.Id, 1, 1, 30000, null);
      assertInvoiceBundle(v2.Id, 1, 2, 2000, null);
      assertInvoiceBundle(v3Estimate.Id, 1, 2, 1000, null);
      Test.stopTest();

      System.assertEquals(3, v1Lines.size(), 'V1 3ヶ月');
      System.assertEquals(30000, sumAmounts(v1Lines), 'V1 期間明細合計');
      System.assertEquals(4, v2Lines.size(), 'V2 ±2ヶ月');
      System.assertEquals(2000, sumAmounts(v2Lines), 'V2 ネット +1000×2');
      System.assertEquals(2, v3Lines.size(), 'V3 ±1ヶ月');
      System.assertEquals(1000, sumAmounts(v3Lines), 'V3 ネット +1000');
    }
  }

  // -------------------------------------------------------------------------
  // 007b Change→Renew（請求集約）
  // -------------------------------------------------------------------------

  @IsTest
  static void scenario007b_changeThenRenew() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2026, 5, 31);
      Date change1 = Date.newInstance(2026, 5, 1);
      Date renewStart = Date.newInstance(2026, 6, 1);
      Date renewEnd = Date.newInstance(2026, 7, 31);

      ScenarioContext base = createBaseService(
        'LC007b',
        INVOICE_SETTING_PREPAID
      );
      ContractHistory__c v1 = insertOrderedNew(
        base,
        'LC007b V1',
        1,
        termStart,
        termEnd,
        10000,
        1
      );
      ContractHistory__c v2 = insertChangeEstimate(
        base,
        v1,
        'LC007b V2',
        2,
        termStart,
        termEnd,
        change1,
        10000,
        11000,
        1,
        1
      );

      ContractHistory__c v3 = new ContractHistory__c(
        Name = 'LC007b V3 Renew',
        ContractService__c = base.service.Id,
        Type__c = 'Renew',
        historystatus__c = 'Estimate',
        Version__c = 3,
        CurrentTermStartDate__c = renewStart,
        CurrentTermEndDate__c = renewEnd,
        EffectiveDate__c = renewStart,
        PreviousHistory__c = v2.Id
      );
      insert v3;
      insert new ContractProduct__c(
        ContractHistory__c = v3.Id,
        Product__c = base.product.Id,
        Quantity__c = 1,
        UnitPrice__c = 11000,
        Amount__c = 11000,
        StartDate__c = renewStart,
        Enddate__c = renewEnd,
        InvoiceSetting__c = INVOICE_SETTING_PREPAID,
        BillingType__c = BILLING_TYPE_RECURRING,
        Type__c = 'Renew'
      );

      Test.startTest();
      orderHistory(v2);
      orderHistory(v3);
      Test.stopTest();

      System.assert(
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :v3.Id
        ] >= 1,
        'Renew 請求あり'
      );
      System.assertEquals(
        'Ordered',
        [SELECT historystatus__c FROM ContractHistory__c WHERE Id = :v3.Id]
        .historystatus__c
      );
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  private static ScenarioContext createPriceChangeContext(
    String name,
    Boolean lockAprilInvoice
  ) {
    ScenarioContext context = createBaseService(name, INVOICE_SETTING_PREPAID);
    context.priorHistory = insertOrderedNew(
      context,
      name + ' V1',
      1,
      TERM_START,
      TERM_END,
      V1_UNIT_PRICE,
      1
    );
    context.priorContractProduct = [
      SELECT Id
      FROM ContractProduct__c
      WHERE ContractHistory__c = :context.priorHistory.Id
      LIMIT 1
    ];
    if (lockAprilInvoice) {
      lockInvoiceCoveringPeriodStart(
        context.priorHistory.Id,
        TERM_START,
        APRIL_INVOICED_DATE,
        null
      );
    }
    context.changeHistory = insertChangeEstimate(
      context,
      context.priorHistory,
      name + ' V2',
      2,
      TERM_START,
      TERM_END,
      CHANGE_EFFECTIVE_DATE,
      V1_UNIT_PRICE,
      V2_UNIT_PRICE,
      1,
      1
    );
    return context;
  }

  private static ScenarioContext createQtyPriceChangeContext(String name) {
    ScenarioContext context = createBaseService(name, INVOICE_SETTING_PREPAID);
    context.priorHistory = insertOrderedNew(
      context,
      name + ' V1',
      1,
      TERM_START,
      TERM_END,
      V1_UNIT_PRICE,
      V1_QUANTITY
    );
    context.priorContractProduct = [
      SELECT Id
      FROM ContractProduct__c
      WHERE ContractHistory__c = :context.priorHistory.Id
      LIMIT 1
    ];
    context.changeHistory = insertChangeEstimate(
      context,
      context.priorHistory,
      name + ' V2',
      2,
      TERM_START,
      TERM_END,
      CHANGE_EFFECTIVE_DATE,
      V1_UNIT_PRICE,
      V2_UNIT_PRICE,
      V1_QUANTITY,
      V3_QUANTITY
    );
    return context;
  }

  private static ScenarioContext createBaseService(
    String name,
    String invoiceSetting
  ) {
    Account account = ContractTestDataFactory.insertAccount(name + ' Account');
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com'
    );
    ContractTestDataFactory.applyOnOrAfterBillingDay(
      billingAccount,
      BILLING_DAY_OF_MONTH
    );
    ContractTestDataFactory.applyPaymentMonthEnd(billingAccount, 1);
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;

    ContractService__c service = new ContractService__c(
      Name = name + ' Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    insert service;

    Product2 product = ContractTestDataFactory.buildProduct(name + ' Product');
    product.BillingType__c = BILLING_TYPE_RECURRING;
    product.invoicetype__c = invoiceSetting;
    ContractTestDataFactory.insertProduct(product);

    ScenarioContext context = new ScenarioContext();
    context.account = account;
    context.service = service;
    context.billingAccount = billingAccount;
    context.product = product;
    return context;
  }

  private static ContractHistory__c insertOrderedNew(
    ScenarioContext base,
    String historyName,
    Decimal version,
    Date termStart,
    Date termEnd,
    Decimal unitPrice,
    Decimal quantity
  ) {
    ContractHistory__c history = new ContractHistory__c(
      Name = historyName,
      ContractService__c = base.service.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = version,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = termStart
    );
    insert history;
    insert new ContractProduct__c(
      ContractHistory__c = history.Id,
      Product__c = base.product.Id,
      Quantity__c = quantity,
      UnitPrice__c = unitPrice,
      Amount__c = unitPrice * quantity,
      StartDate__c = termStart,
      Enddate__c = termEnd,
      InvoiceSetting__c = INVOICE_SETTING_PREPAID,
      BillingType__c = BILLING_TYPE_RECURRING,
      Type__c = 'New'
    );
    InvoiceProductGenerationService.generateForHistories(
      new Set<Id>{ history.Id }
    );
    return history;
  }

  private static ContractHistory__c insertChangeEstimate(
    ScenarioContext base,
    ContractHistory__c prior,
    String historyName,
    Decimal version,
    Date termStart,
    Date termEnd,
    Date effectiveDate,
    Decimal priorUnitPrice,
    Decimal newUnitPrice,
    Decimal priorQty,
    Decimal newQty
  ) {
    ContractProduct__c priorCp = [
      SELECT Id
      FROM ContractProduct__c
      WHERE ContractHistory__c = :prior.Id
      LIMIT 1
    ];
    Date preEnd = effectiveDate.addDays(-1);
    ContractHistory__c changeHistory = new ContractHistory__c(
      Name = historyName,
      ContractService__c = base.service.Id,
      Type__c = 'Change',
      historystatus__c = 'Estimate',
      Version__c = version,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = effectiveDate,
      PreviousHistory__c = prior.Id
    );
    insert changeHistory;
    insert new List<ContractProduct__c>{
      new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = base.product.Id,
        Quantity__c = priorQty,
        UnitPrice__c = priorUnitPrice,
        Amount__c = priorUnitPrice * priorQty,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = INVOICE_SETTING_PREPAID,
        BillingType__c = BILLING_TYPE_RECURRING,
        Type__c = 'Original',
        PreviousContractProduct__c = priorCp.Id
      ),
      new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = base.product.Id,
        Quantity__c = priorQty,
        UnitPrice__c = priorUnitPrice,
        Amount__c = priorUnitPrice * priorQty,
        StartDate__c = termStart,
        Enddate__c = preEnd,
        InvoiceSetting__c = INVOICE_SETTING_PREPAID,
        BillingType__c = BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorCp.Id
      ),
      new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Product__c = base.product.Id,
        Quantity__c = newQty,
        UnitPrice__c = newUnitPrice,
        Amount__c = newUnitPrice * newQty,
        StartDate__c = effectiveDate,
        Enddate__c = termEnd,
        InvoiceSetting__c = INVOICE_SETTING_PREPAID,
        BillingType__c = BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorCp.Id
      )
    };
    return changeHistory;
  }

  private static ContractHistory__c buildMultiProductChange(
    Id serviceId,
    ContractHistory__c prior,
    List<Product2> products,
    List<ContractProduct__c> priorCps,
    String name,
    Decimal version,
    Date termStart,
    Date termEnd,
    Date effectiveDate,
    List<Decimal> newPrices
  ) {
    Date preEnd = effectiveDate.addDays(-1);
    ContractHistory__c change = new ContractHistory__c(
      Name = name,
      ContractService__c = serviceId,
      Type__c = 'Change',
      historystatus__c = 'Estimate',
      Version__c = version,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = effectiveDate,
      PreviousHistory__c = prior.Id
    );
    insert change;
    List<ContractProduct__c> rows = new List<ContractProduct__c>();
    for (Integer i = 0; i < products.size(); i++) {
      ContractProduct__c priorCp = priorCps[i];
      Decimal priorPrice = priorCp.UnitPrice__c;
      rows.add(
        new ContractProduct__c(
          ContractHistory__c = change.Id,
          Product__c = products[i].Id,
          Quantity__c = 1,
          UnitPrice__c = priorPrice,
          Amount__c = priorPrice,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = INVOICE_SETTING_PREPAID,
          BillingType__c = BILLING_TYPE_RECURRING,
          Type__c = 'Original',
          PreviousContractProduct__c = priorCp.Id
        )
      );
      rows.add(
        new ContractProduct__c(
          ContractHistory__c = change.Id,
          Product__c = products[i].Id,
          Quantity__c = 1,
          UnitPrice__c = priorPrice,
          Amount__c = priorPrice,
          StartDate__c = termStart,
          Enddate__c = preEnd,
          InvoiceSetting__c = INVOICE_SETTING_PREPAID,
          BillingType__c = BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorCp.Id
        )
      );
      rows.add(
        new ContractProduct__c(
          ContractHistory__c = change.Id,
          Product__c = products[i].Id,
          Quantity__c = 1,
          UnitPrice__c = newPrices[i],
          Amount__c = newPrices[i],
          StartDate__c = effectiveDate,
          Enddate__c = termEnd,
          InvoiceSetting__c = INVOICE_SETTING_PREPAID,
          BillingType__c = BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorCp.Id
        )
      );
    }
    insert rows;
    return change;
  }

  /**
   * 前回が Change のとき用。事前/事後 Remake の両方に Original を載せ、
   * 事後区間だけを有効日で再分割する。
   */
  private static ContractHistory__c buildSecondMultiProductChange(
    Id serviceId,
    ContractHistory__c priorChange,
    List<Product2> products,
    String name,
    Decimal version,
    Date termStart,
    Date termEnd,
    Date priorEffective,
    Date effectiveDate,
    List<Decimal> priorPostPrices,
    List<Decimal> newPrices
  ) {
    Date priorPreEnd = priorEffective.addDays(-1);
    Date preEnd = effectiveDate.addDays(-1);
    Map<Id, ContractProduct__c> preByProduct = new Map<Id, ContractProduct__c>();
    Map<Id, ContractProduct__c> postByProduct = new Map<Id, ContractProduct__c>();
    for (ContractProduct__c remake : [
      SELECT Id, Product__c, UnitPrice__c, Quantity__c, StartDate__c, Enddate__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :priorChange.Id AND Type__c = 'Remake'
    ]) {
      if (
        remake.StartDate__c == termStart &&
        remake.Enddate__c == priorPreEnd
      ) {
        preByProduct.put(remake.Product__c, remake);
      } else if (
        remake.StartDate__c == priorEffective &&
        remake.Enddate__c == termEnd
      ) {
        postByProduct.put(remake.Product__c, remake);
      }
    }

    ContractHistory__c change = new ContractHistory__c(
      Name = name,
      ContractService__c = serviceId,
      Type__c = 'Change',
      historystatus__c = 'Estimate',
      Version__c = version,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = effectiveDate,
      PreviousHistory__c = priorChange.Id
    );
    insert change;

    List<ContractProduct__c> rows = new List<ContractProduct__c>();
    for (Integer i = 0; i < products.size(); i++) {
      Product2 product = products[i];
      ContractProduct__c preRemake = preByProduct.get(product.Id);
      ContractProduct__c postRemake = postByProduct.get(product.Id);
      System.assertNotEquals(
        null,
        preRemake,
        '事前 Remake 不足: ' + product.Id
      );
      System.assertNotEquals(
        null,
        postRemake,
        '事後 Remake 不足: ' + product.Id
      );
      Decimal priorPrice = priorPostPrices[i];

      rows.add(
        new ContractProduct__c(
          ContractHistory__c = change.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = preRemake.UnitPrice__c,
          Amount__c = preRemake.UnitPrice__c,
          StartDate__c = termStart,
          Enddate__c = priorPreEnd,
          InvoiceSetting__c = INVOICE_SETTING_PREPAID,
          BillingType__c = BILLING_TYPE_RECURRING,
          Type__c = 'Original',
          PreviousContractProduct__c = preRemake.Id
        )
      );
      rows.add(
        new ContractProduct__c(
          ContractHistory__c = change.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = preRemake.UnitPrice__c,
          Amount__c = preRemake.UnitPrice__c,
          StartDate__c = termStart,
          Enddate__c = priorPreEnd,
          InvoiceSetting__c = INVOICE_SETTING_PREPAID,
          BillingType__c = BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = preRemake.Id
        )
      );
      rows.add(
        new ContractProduct__c(
          ContractHistory__c = change.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = priorPrice,
          Amount__c = priorPrice,
          StartDate__c = priorEffective,
          Enddate__c = termEnd,
          InvoiceSetting__c = INVOICE_SETTING_PREPAID,
          BillingType__c = BILLING_TYPE_RECURRING,
          Type__c = 'Original',
          PreviousContractProduct__c = postRemake.Id
        )
      );
      rows.add(
        new ContractProduct__c(
          ContractHistory__c = change.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = priorPrice,
          Amount__c = priorPrice,
          StartDate__c = priorEffective,
          Enddate__c = preEnd,
          InvoiceSetting__c = INVOICE_SETTING_PREPAID,
          BillingType__c = BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = postRemake.Id
        )
      );
      rows.add(
        new ContractProduct__c(
          ContractHistory__c = change.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = newPrices[i],
          Amount__c = newPrices[i],
          StartDate__c = effectiveDate,
          Enddate__c = termEnd,
          InvoiceSetting__c = INVOICE_SETTING_PREPAID,
          BillingType__c = BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = postRemake.Id
        )
      );
    }
    insert rows;
    return change;
  }

  private static void orderHistory(ContractHistory__c history) {
    history.historystatus__c = 'Ordered';
    update history;
  }

  private static void lockInvoiceCoveringPeriodStart(
    Id historyId,
    Date periodStart,
    Date actualInvoiceDate,
    String billingType
  ) {
    String soql =
      'SELECT Id FROM InvoiceProduct__c' +
      ' WHERE ContractHistory__c = :historyId AND StartDate__c = :periodStart';
    if (String.isNotBlank(billingType)) {
      soql += ' AND ContractProduct__r.BillingType__c = :billingType';
    }
    soql += ' LIMIT 1';
    List<InvoiceProduct__c> periodLines = Database.query(soql);
    System.assert(!periodLines.isEmpty(), 'ロック対象期間明細なし');
    String periodLineKey = String.valueOf(periodLines[0].Id);
    List<Invoice__c> invoices = [
      SELECT Id, SourcePeriodLineIds__c
      FROM Invoice__c
      WHERE ContractHistory__c = :historyId
    ];
    List<Invoice__c> toUpdate = new List<Invoice__c>();
    for (Invoice__c invoice : invoices) {
      String sources = invoice.SourcePeriodLineIds__c;
      if (
        String.isNotBlank(sources) &&
        (sources.contains(periodLineKey) ||
        sources.contains(periodLineKey.left(15)))
      ) {
        invoice.SystemIntegrationDate__c = actualInvoiceDate;
        toUpdate.add(invoice);
      }
    }
    if (toUpdate.isEmpty() && !invoices.isEmpty()) {
      invoices[0].SystemIntegrationDate__c = actualInvoiceDate;
      toUpdate.add(invoices[0]);
    }
    System.assert(!toUpdate.isEmpty(), 'ロック対象請求なし');
    update toUpdate;
  }

  private static void assertV1PeriodLines(Id priorHistoryId) {
    List<InvoiceProduct__c> rows = [
      SELECT Amount__c, StartDate__c, Enddate__c
      FROM InvoiceProduct__c
      WHERE ContractHistory__c = :priorHistoryId
      ORDER BY StartDate__c ASC
    ];
    System.assertEquals(12, rows.size(), 'V1 期間明細 12');
    System.assertEquals(360000, sumAmounts(rows), 'V1 期間明細合計');
    System.assertEquals(TERM_START, rows[0].StartDate__c);
    System.assertEquals(TERM_END, rows[11].Enddate__c);
  }

  private static void assertV2PeriodLinesPriceOnly(Id changeHistoryId) {
    List<InvoiceProduct__c> rows = [
      SELECT Amount__c, StartDate__c
      FROM InvoiceProduct__c
      WHERE ContractHistory__c = :changeHistoryId
      ORDER BY StartDate__c ASC, Amount__c ASC
    ];
    System.assertEquals(22, rows.size(), 'V2 ±11ヶ月');
    System.assertEquals(220000, sumAmounts(rows), 'V2 期間明細合計');
    System.assertEquals(CHANGE_EFFECTIVE_DATE, rows[0].StartDate__c);
  }

  private static void assertInvoiceBundle(
    Id historyId,
    Integer expectedInvoiceCount,
    Integer expectedLineCount,
    Decimal expectedAmountTotal,
    Date expectedIntegrationDate
  ) {
    List<Invoice__c> invoices = [
      SELECT
        Id,
        Amount__c,
        SystemIntegrationDate__c,
        (SELECT Amount__c FROM InvoiceLines__r)
      FROM Invoice__c
      WHERE ContractHistory__c = :historyId
    ];
    System.assertEquals(
      expectedInvoiceCount,
      invoices.size(),
      'Invoice 件数 history=' + historyId
    );
    Decimal invoiceSum = 0;
    Integer lineCount = 0;
    Decimal lineSum = 0;
    for (Invoice__c invoice : invoices) {
      invoiceSum += invoice.Amount__c == null ? 0 : invoice.Amount__c;
      if (expectedIntegrationDate != null) {
        System.assertEquals(
          expectedIntegrationDate,
          invoice.SystemIntegrationDate__c,
          '請求ロック日'
        );
      }
      if (invoice.InvoiceLines__r != null) {
        for (InvoiceLine__c line : invoice.InvoiceLines__r) {
          lineCount++;
          lineSum += line.Amount__c == null ? 0 : line.Amount__c;
        }
      }
    }
    System.assertEquals(
      expectedAmountTotal,
      invoiceSum,
      'Invoice Amount 合計 history=' + historyId
    );
    System.assertEquals(
      expectedLineCount,
      lineCount,
      'InvoiceLine 件数 history=' + historyId
    );
    System.assertEquals(
      expectedAmountTotal,
      lineSum,
      'InvoiceLine Amount 合計 history=' + historyId
    );
  }

  private static void assertServicePeriodLineTotals(
    Id serviceId,
    Integer expectedCount,
    Decimal expectedSum
  ) {
    List<InvoiceProduct__c> rows = [
      SELECT Amount__c
      FROM InvoiceProduct__c
      WHERE ContractHistory__r.ContractService__c = :serviceId
    ];
    System.assertEquals(expectedCount, rows.size(), 'サービス期間明細件数');
    System.assertEquals(expectedSum, sumAmounts(rows), 'サービス期間明細合計');
  }

  private static Decimal sumAmounts(List<InvoiceProduct__c> rows) {
    Decimal total = 0;
    for (InvoiceProduct__c row : rows) {
      total += row.Amount__c == null ? 0 : row.Amount__c;
    }
    return total;
  }
}
