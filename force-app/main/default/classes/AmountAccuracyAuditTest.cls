/**
 * 金額優先バグトリ: 見積→期間明細→請求→プレビュー→差し戻し→ARR/PDF の円単位回帰。
 *
 * 境界（仕様）:
 * - 見積 ContractProduct.Amount = 画面確認値（保存正）。Trigger は再計算しない。
 * - 期間明細 = 常に数量×単価（月次行ごと HALF_UP）。見積 Amount と一致しなくてよい。
 * - 請求明細/ヘッダ = 期間明細集約。税はヘッダ税抜合計×税率を1回切り捨て。
 * - amountEntry / 単価小数による見積≠期間明細合計は仕様（請求正は単価側）。
 * - プレビュー端数調整は意図的な請求側差分。期間分割時は端数クリア。
 */
@IsTest
private class AmountAccuracyAuditTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  // --- Chunk1: 見積金額保存正本 ---

  @IsTest
  static void chunk1_buildContractProduct_preservesScreenAmountAndOriginalSign() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Product2 product = ContractTestDataFactory.buildProduct(
        'Audit Save Amount'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      EstimateCreateController.ProductLineItem newLine = new EstimateCreateController.ProductLineItem();
      newLine.productId = product.Id;
      newLine.quantity = 1.5;
      newLine.unitPrice = 100.455;
      newLine.amount = 1234.4;
      newLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      newLine.recordType = 'New';
      newLine.startDate = '2026-04-01';
      newLine.endDate = '2027-03-31';

      ContractProduct__c savedNew = EstimateSaveService.buildContractProduct(
        null,
        null,
        newLine,
        product,
        'New',
        Date.newInstance(2026, 4, 1)
      );
      System.assertEquals(1.5, savedNew.Quantity__c, '数量はそのまま保持');
      System.assertEquals(
        100.46,
        savedNew.UnitPrice__c,
        '単価 scale=2 HALF_UP'
      );
      System.assertEquals(
        1234,
        savedNew.Amount__c,
        '画面金額を整数円で保存（再計算しない）'
      );
      // 画面金額 ≠ qty×単価でも再計算で上書きしない
      System.assertNotEquals(
        (1.5 * 100.46).setScale(0, RoundingMode.HALF_UP),
        savedNew.Amount__c
      );

      EstimateCreateController.ProductLineItem originalLine = new EstimateCreateController.ProductLineItem();
      originalLine.productId = product.Id;
      originalLine.quantity = 2;
      originalLine.unitPrice = 5000;
      originalLine.amount = -120000;
      originalLine.invoiceType = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      originalLine.recordType = 'Original';
      originalLine.startDate = '2026-04-01';
      originalLine.endDate = '2027-03-31';

      ContractProduct__c savedOriginal = EstimateSaveService.buildContractProduct(
        null,
        null,
        originalLine,
        product,
        'Change',
        Date.newInstance(2026, 7, 1)
      );
      System.assertEquals('Original', savedOriginal.Type__c);
      System.assertEquals(
        -120000,
        savedOriginal.Amount__c,
        'Original は画面の符号付き金額をそのまま保存'
      );
    }
  }

  @IsTest
  static void chunk1_contractProductAmountUtil_matchesWizardRounding() {
    // 継続: qty×price×cycles 一括 HALF_UP。Original は符号反転。
    Decimal recurring = ContractProductAmountUtil.calculateUnsignedAmount(
      1300,
      742.85,
      ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Date.newInstance(2026, 5, 1),
      Date.newInstance(2027, 2, 28)
    );
    System.assertEquals(9657050, recurring);
    System.assertEquals(
      -9657050,
      ContractProductAmountUtil.applyProductTypeSign(recurring, 'Original')
    );
    System.assertEquals(
      1500,
      ContractProductAmountUtil.calculateUnsignedAmount(
        1.5,
        1000,
        ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Date.newInstance(2026, 4, 1),
        Date.newInstance(2026, 4, 30)
      )
    );
  }

  // --- Chunk2: 契約商品→期間明細（月次行ごと丸め） ---

  @IsTest
  static void chunk2_monthlyPeriodLines_useQtyTimesUnitPriceNotContractAmount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createMonthlyEstimate(
        1,
        33.33,
        400, // 一括丸めなら 33.33×12=399.96→400。月次積み上げは 33×12=396
        ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY
      );

      Test.startTest();
      fixture.history.historystatus__c = 'Ordered';
      update fixture.history;
      Test.stopTest();

      List<InvoiceProduct__c> periodLines = [
        SELECT Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
        ORDER BY StartDate__c
      ];
      System.assertEquals(12, periodLines.size());
      Decimal periodSum = 0;
      for (InvoiceProduct__c line : periodLines) {
        System.assertEquals(
          33,
          line.Amount__c,
          '月次行は qty×unitPrice を行ごと四捨五入'
        );
        periodSum += line.Amount__c;
      }
      System.assertEquals(396, periodSum);

      ContractProduct__c cp = [
        SELECT Amount__c
        FROM ContractProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      System.assertEquals(
        400,
        cp.Amount__c,
        '見積 Amount は一括丸めのまま残る'
      );
      System.assertNotEquals(
        cp.Amount__c,
        periodSum,
        'SPEC: 見積一括丸めと月次行積み上げは一致しなくてよい'
      );
    }
  }

  // --- Chunk3: amountEntry / 単価小数 ---

  @IsTest
  static void chunk3_amountEntry_contractAmountDiffersFromPeriodSum_billingUsesUnitPrice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      // 画面手入力 9657000、単価逆算 742.85 → 請求側は 1300×742.85×10=9657050
      Fixture fixture = createMonthlyEstimate(
        1300,
        742.85,
        9657000,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY
      );
      Date startDate = Date.newInstance(2026, 5, 1);
      Date endDate = Date.newInstance(2027, 2, 28);
      fixture.history.CurrentTermStartDate__c = startDate;
      fixture.history.CurrentTermEndDate__c = endDate;
      fixture.history.EffectiveDate__c = startDate;
      update fixture.history;
      ContractProduct__c cp = [
        SELECT Id
        FROM ContractProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      cp.StartDate__c = startDate;
      cp.Enddate__c = endDate;
      cp.Quantity__c = 1300;
      cp.UnitPrice__c = 742.85;
      cp.Amount__c = 9657000;
      update cp;

      Test.startTest();
      fixture.history.historystatus__c = 'Ordered';
      update fixture.history;
      Test.stopTest();

      AggregateResult ar = [
        SELECT SUM(Amount__c) totalAmount
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
      ];
      Decimal periodSum = (Decimal) ar.get('totalAmount');
      System.assertEquals(
        9657050,
        periodSum,
        '請求素材は単価×数量の月次積み上げ（見積手入力額ではない）'
      );
      ContractProduct__c saved = [
        SELECT Amount__c
        FROM ContractProduct__c
        WHERE Id = :cp.Id
      ];
      System.assertEquals(
        9657000,
        saved.Amount__c,
        '見積 Amount は手入力のまま'
      );
      System.assertEquals(50, periodSum - saved.Amount__c, 'SPEC 許容端数');
    }
  }

  // --- Chunk4: Change 差分金額 ---

  @IsTest
  static void chunk4_changeQuantityUp_diffAmountEqualsDeltaOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Audit Change Qty'
      );
      BillingAccount__c ba = insertBillingAccount(account.Id);
      ContractService__c service = new ContractService__c(
        Name = 'Audit Change Qty Service',
        Account__c = account.Id,
        BiilingAcccount__c = ba.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Audit Change Qty Opp'
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Audit Change Qty Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      product.UnitPrice__c = 10000;
      ContractTestDataFactory.insertProduct(product);

      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2027, 3, 31);
      Date effectiveDate = Date.newInstance(2026, 7, 1);

      ContractHistory__c prior = new ContractHistory__c(
        Name = 'Audit Prior',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert prior;
      ContractProduct__c priorCp = new ContractProduct__c(
        ContractHistory__c = prior.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Amount__c = 120000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert priorCp;
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ prior.Id }
      );

      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Audit Change',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = prior.Id
      );
      insert changeHistory;
      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = -120000,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Original',
          PreviousContractProduct__c = priorCp.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 10000,
          Amount__c = 30000,
          StartDate__c = termStart,
          Enddate__c = effectiveDate.addDays(-1),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorCp.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 2,
          UnitPrice__c = 10000,
          Amount__c = 180000,
          StartDate__c = effectiveDate,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorCp.Id
        )
      };

      Test.startTest();
      changeHistory.historystatus__c = 'Ordered';
      update changeHistory;
      Test.stopTest();

      Decimal changeSum = 0;
      for (InvoiceProduct__c line : [
        SELECT Amount__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :changeHistory.Id
      ]) {
        changeSum += line.Amount__c == null ? 0 : line.Amount__c;
      }
      // 有効日以降 9ヶ月: 数量+1 → +10000×9
      System.assertEquals(
        90000,
        changeSum,
        'Change 差分は有効日以降の増分のみ'
      );
    }
  }

  @IsTest
  static void chunk4_changeZeroPriceRemake_netsToZeroAfterEffective() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Audit Zero Remake'
      );
      BillingAccount__c ba = insertBillingAccount(account.Id);
      ContractService__c service = new ContractService__c(
        Name = 'Audit Zero Remake Service',
        Account__c = account.Id,
        BiilingAcccount__c = ba.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Audit Zero Remake Opp'
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Audit Zero Remake Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
      ContractTestDataFactory.insertProduct(product);

      Date termStart = Date.newInstance(2026, 4, 1);
      Date termEnd = Date.newInstance(2027, 3, 31);
      Date effectiveDate = Date.newInstance(2026, 10, 1);

      ContractHistory__c prior = new ContractHistory__c(
        Name = 'Audit Zero Prior',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert prior;
      ContractProduct__c priorCp = new ContractProduct__c(
        ContractHistory__c = prior.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Amount__c = 96000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert priorCp;
      InvoiceProductGenerationService.generateForHistories(
        new Set<Id>{ prior.Id }
      );

      ContractHistory__c changeHistory = new ContractHistory__c(
        Name = 'Audit Zero Change',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = effectiveDate,
        PreviousHistory__c = prior.Id
      );
      insert changeHistory;
      insert new List<ContractProduct__c>{
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 8000,
          Amount__c = -96000,
          StartDate__c = termStart,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Original',
          PreviousContractProduct__c = priorCp.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 8000,
          Amount__c = 48000,
          StartDate__c = termStart,
          Enddate__c = effectiveDate.addDays(-1),
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorCp.Id
        ),
        new ContractProduct__c(
          ContractHistory__c = changeHistory.Id,
          Product__c = product.Id,
          Quantity__c = 1,
          UnitPrice__c = 0,
          Amount__c = 0,
          StartDate__c = effectiveDate,
          Enddate__c = termEnd,
          InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
          BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
          Type__c = 'Remake',
          PreviousContractProduct__c = priorCp.Id
        )
      };

      Test.startTest();
      changeHistory.historystatus__c = 'Ordered';
      update changeHistory;
      Test.stopTest();

      Decimal changeSum = 0;
      for (InvoiceProduct__c line : [
        SELECT Amount__c, StartDate__c
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :changeHistory.Id
      ]) {
        changeSum += line.Amount__c == null ? 0 : line.Amount__c;
        System.assert(
          line.StartDate__c >= effectiveDate,
          '金額0 Remake の差分は有効日以降のみ'
        );
      }
      // 有効日以降6ヶ月を 8000→0 にする打消し = -48000
      System.assertEquals(
        -48000,
        changeSum,
        '期中停止（金額0 Remake）の差分合計'
      );
    }
  }

  // --- Chunk5: マージ・税 ---

  @IsTest
  static void chunk5_mergeTax_truncatesOnceOnHeaderExclTotal() {
    InvoiceProduct__c a = new InvoiceProduct__c(
      StartDate__c = Date.newInstance(2026, 1, 1),
      Enddate__c = Date.newInstance(2026, 1, 31),
      Amount__c = 15,
      TaxPercent__c = 0.1
    );
    InvoiceProduct__c b = new InvoiceProduct__c(
      StartDate__c = Date.newInstance(2026, 2, 1),
      Enddate__c = Date.newInstance(2026, 2, 28),
      Amount__c = 15,
      TaxPercent__c = 0.1
    );
    // 同一バケットに寄せる
    String invoiceKey = 'BA_HIST_2026-01-01_PAY';
    String lineKey = 'CP_100_1_unit_P';
    a.InvoiceBucketKey__c = invoiceKey;
    a.LineBucketKey__c = lineKey;
    b.InvoiceBucketKey__c = invoiceKey;
    b.LineBucketKey__c = lineKey;

    List<InvoiceProductMergeService.MergedInvoice> invoices = InvoiceProductMergeService.buildMergedInvoices(
      new List<InvoiceProduct__c>{ a, b }
    );
    System.assertEquals(1, invoices.size());
    System.assertEquals(30, invoices[0].amountTotal);
    System.assertEquals(
      3,
      invoices[0].taxTotal,
      '行ごと切捨て(1+1=2)ではなくヘッダ税抜30に対し1回切り捨てで3'
    );
    System.assertEquals(
      TaxCalculationUtil.calculateTaxAmount(30, 10),
      invoices[0].taxTotal
    );
  }

  // --- Chunk6: プレビュー端数調整 ---

  @IsTest
  static void chunk6_previewAmountAdjust_isIdempotentAndRecalculatesTax() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createMonthlyEstimate(
        1,
        10000,
        120000,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID
      );
      fixture.history.historystatus__c = 'Ordered';
      update fixture.history;
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );

      InvoiceLine__c line = [
        SELECT Id, Invoice__c, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      Decimal baseAmount = line.Amount__c;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;

      Test.startTest();
      InvoiceCanonicalService.updateLineAmount(line.Id, baseAmount + 1);
      InvoiceCanonicalService.updateLineAmount(line.Id, baseAmount + 1);
      Test.stopTest();

      Invoice__c invoice = [
        SELECT Amount__c, TaxAmount__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :line.Invoice__c
      ];
      System.assertEquals(
        baseAmount + 1,
        invoice.Amount__c,
        '再適用で二重加算しない'
      );
      System.assertEquals(true, invoice.IsManuallyAdjusted__c);
      System.assertEquals(
        TaxCalculationUtil.calculateTaxAmount(baseAmount + 1, 10),
        invoice.TaxAmount__c
      );
    }
  }

  // --- Chunk7: 差し戻し再受注・Cancel ---

  @IsTest
  static void chunk7_revertAndReorder_doesNotDuplicatePeriodAmounts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createMonthlyEstimate(
        1,
        8000,
        96000,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY
      );
      fixture.history.historystatus__c = 'Ordered';
      update fixture.history;

      AggregateResult beforeAr = [
        SELECT SUM(Amount__c) totalAmount, COUNT(Id) cnt
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
      ];
      Decimal beforeSum = (Decimal) beforeAr.get('totalAmount');
      Integer beforeCount = (Integer) beforeAr.get('cnt');
      System.assertEquals(12, beforeCount);
      System.assertEquals(96000, beforeSum);

      Test.startTest();
      fixture.history.historystatus__c = 'Estimate';
      update fixture.history;
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :fixture.history.Id
        ],
        '差し戻しで期間明細・請求を削除'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :fixture.history.Id
        ]
      );

      fixture.history.historystatus__c = 'Ordered';
      update fixture.history;
      Test.stopTest();

      AggregateResult afterAr = [
        SELECT SUM(Amount__c) totalAmount, COUNT(Id) cnt
        FROM InvoiceProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
      ];
      System.assertEquals(beforeCount, (Integer) afterAr.get('cnt'));
      System.assertEquals(beforeSum, (Decimal) afterAr.get('totalAmount'));
    }
  }

  @IsTest
  static void chunk7_revertBlockedWhenInvoiceLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createMonthlyEstimate(
        1,
        8000,
        96000,
        ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY
      );
      fixture.history.historystatus__c = 'Ordered';
      update fixture.history;

      Invoice__c invoice = [
        SELECT Id
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      invoice.SystemIntegrationDate__c = Date.today();
      update invoice;

      Boolean blocked = false;
      try {
        fixture.history.historystatus__c = 'Estimate';
        update fixture.history;
      } catch (DmlException ex) {
        blocked = true;
      }
      System.assertEquals(
        true,
        blocked,
        'ロック請求がある Version の差し戻しは拒否（§6.9）'
      );
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :fixture.history.Id
        ]
        .historystatus__c
      );
      System.assertEquals(
        12,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :fixture.history.Id
        ],
        '拒否時は期間明細が残る'
      );
    }
  }

  @IsTest
  static void chunk7_cancelOrdered_createsNoPeriodOrInvoiceAmounts() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Audit Cancel');
      BillingAccount__c ba = insertBillingAccount(account.Id);
      ContractService__c service = new ContractService__c(
        Name = 'Audit Cancel Service',
        Account__c = account.Id,
        BiilingAcccount__c = ba.Id
      );
      insert service;
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Audit Cancel Opp'
      );
      Date termEnd = Date.newInstance(2027, 3, 31);
      ContractHistory__c cancelHistory = new ContractHistory__c(
        Name = 'Audit Cancel History',
        ContractService__c = service.Id,
        Opportunity__c = opportunity.Id,
        Type__c = 'Cancel',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termEnd.addDays(1),
        CurrentTermEndDate__c = termEnd.addDays(1),
        EffectiveDate__c = termEnd.addDays(1)
      );
      insert cancelHistory;

      Test.startTest();
      cancelHistory.historystatus__c = 'Ordered';
      update cancelHistory;
      Test.stopTest();

      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM InvoiceProduct__c
          WHERE ContractHistory__c = :cancelHistory.Id
        ]
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :cancelHistory.Id
        ]
      );
    }
  }

  // --- Chunk8: ARR / 見積PDF税 ---

  @IsTest
  static void chunk8_arr_usesContractProductAmountNotPeriodSum() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd(); // 12ヶ月
      ContractProduct__c line = new ContractProduct__c(
        Quantity__c = 1300,
        UnitPrice__c = 742.85,
        Amount__c = 9657000, // 期間明細側なら 9657050
        StartDate__c = termStart,
        Enddate__c = termEnd,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New',
        ContractHistory__c = null
      );
      // history Id が無いと 0 になるのでダミー履歴を付ける
      Account account = ContractTestDataFactory.insertAccount('Audit ARR');
      ContractService__c service = new ContractService__c(
        Name = 'Audit ARR Service',
        Account__c = account.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Audit ARR History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      insert history;
      line.ContractHistory__c = history.Id;
      line.Product__r = new Product2(
        IncludeInARR__c = true,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      );

      Decimal arr = ContractArrCalculationService.calculateProductArr(
        line,
        termEnd
      );
      // Amount÷12×12 = Amount（見積正）。単価積み上げ 9657050 ではない。
      System.assertEquals(9657000, arr, 'ARR は契約商品 Amount ベース');
      System.assertNotEquals(
        9657050,
        arr,
        'SPEC: amountEntry 端数（単価積み上げ）は ARR に載せない'
      );
    }
  }

  @IsTest
  static void chunk8_estimateDocumentTax_truncatesOnceOnGrandExcl() {
    System.assertEquals(3, TaxCalculationUtil.calculateTaxAmount(30, 10));
    System.assertEquals(
      1,
      TaxCalculationUtil.calculateTaxAmount(15, 10),
      'カテゴリ別に切ると 1+1 になり得るが、正は税抜合計への1回切り捨て'
    );
    System.assertEquals(33, TaxCalculationUtil.calculateAmountInclTax(30, 10));
  }

  // --- helpers ---

  private class Fixture {
    ContractHistory__c history;
  }

  private static BillingAccount__c insertBillingAccount(Id accountId) {
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = accountId,
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_NEXT_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_1,
      BillingAddressee__c = '監査宛名',
      BillingEmailTo__c = 'to@example.com',
      AdjustInvoiceDateToBusinessDay__c = false
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    return billingAccount;
  }

  private static Fixture createMonthlyEstimate(
    Decimal quantity,
    Decimal unitPrice,
    Decimal amount,
    String invoiceSetting
  ) {
    Account account = ContractTestDataFactory.insertAccount(
      'Audit ' + String.valueOf(Crypto.getRandomInteger())
    );
    BillingAccount__c ba = insertBillingAccount(account.Id);
    ContractService__c service = new ContractService__c(
      Name = 'Audit Service',
      Account__c = account.Id,
      BiilingAcccount__c = ba.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    insert service;
    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      'Audit Opp'
    );
    Product2 product = ContractTestDataFactory.buildProduct(
      'Audit Product ' + String.valueOf(Crypto.getRandomInteger())
    );
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    product.invoicetype__c = invoiceSetting;
    product.UnitPrice__c = unitPrice;
    ContractTestDataFactory.insertProduct(product);

    Date termStart = Date.newInstance(2026, 4, 1);
    Date termEnd = Date.newInstance(2027, 3, 31);
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Audit History',
      ContractService__c = service.Id,
      Opportunity__c = opportunity.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = termStart
    );
    insert history;
    insert new ContractProduct__c(
      ContractHistory__c = history.Id,
      Product__c = product.Id,
      Quantity__c = quantity,
      UnitPrice__c = unitPrice,
      Amount__c = amount,
      StartDate__c = termStart,
      Enddate__c = termEnd,
      InvoiceSetting__c = invoiceSetting,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = 'New'
    );

    Fixture fixture = new Fixture();
    fixture.history = history;
    return fixture;
  }
}
