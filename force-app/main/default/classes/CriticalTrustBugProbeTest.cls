/**
 * 信頼低下バグ再現プローブ。
 * 端数調整した明細Aを残したまま、別明細Bを同一請求内分割すると
 * 請求ヘッダの手動調整フラグ／調整前合計が消えるかを検証する。
 */
@IsTest
private class CriticalTrustBugProbeTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  @IsTest
  static void splitOtherLine_mustKeepSiblingManualAdjustmentOnHeader() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Trust Probe BA');
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = '株式会社プローブ 御中',
        BillingEmailTo__c = 'probe@example.com',
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
        Name = 'Trust Probe Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = 0.1
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Trust Probe History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 8, 31)
      );
      insert history;

      Product2 productA = ContractTestDataFactory.buildProduct(
        'Probe Recurring A'
      );
      productA.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      Product2 productB = ContractTestDataFactory.buildProduct(
        'Probe Recurring B'
      );
      productB.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(productA);
      ContractTestDataFactory.insertProduct(productB);

      ContractProduct__c cpA = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = productA.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Unit__c = 'ID',
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 8, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New',
        Amount__c = 30000
      );
      ContractProduct__c cpB = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = productB.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Unit__c = 'ID',
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 8, 31),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New',
        Amount__c = 30000
      );
      insert new List<ContractProduct__c>{ cpA, cpB };

      Date invoiceDate = Date.newInstance(2026, 6, 1);
      Date paymentDate = Date.newInstance(2026, 6, 30);
      String bucketKey = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
        billingAccount.Id,
        history.Id,
        invoiceDate,
        paymentDate
      );
      List<InvoiceProduct__c> periodLines = new List<InvoiceProduct__c>();
      for (ContractProduct__c cp : new List<ContractProduct__c>{ cpA, cpB }) {
        periodLines.add(
          new InvoiceProduct__c(
            ContractHistory__c = history.Id,
            ContractProduct__c = cp.Id,
            InvoiceBucketKey__c = bucketKey,
            StartDate__c = Date.newInstance(2026, 6, 1),
            Enddate__c = Date.newInstance(2026, 6, 30),
            Quantity__c = 1,
            UnitPrice__c = 10000,
            Amount__c = 10000
          )
        );
        periodLines.add(
          new InvoiceProduct__c(
            ContractHistory__c = history.Id,
            ContractProduct__c = cp.Id,
            InvoiceBucketKey__c = bucketKey,
            StartDate__c = Date.newInstance(2026, 7, 1),
            Enddate__c = Date.newInstance(2026, 7, 31),
            Quantity__c = 1,
            UnitPrice__c = 10000,
            Amount__c = 10000
          )
        );
        periodLines.add(
          new InvoiceProduct__c(
            ContractHistory__c = history.Id,
            ContractProduct__c = cp.Id,
            InvoiceBucketKey__c = bucketKey,
            StartDate__c = Date.newInstance(2026, 8, 1),
            Enddate__c = Date.newInstance(2026, 8, 31),
            Quantity__c = 1,
            UnitPrice__c = 10000,
            Amount__c = 10000
          )
        );
      }
      insert periodLines;

      InvoiceCanonicalService.rebuildForHistories(new Set<Id>{ history.Id });

      List<InvoiceLine__c> lines = [
        SELECT
          Id,
          Invoice__c,
          Amount__c,
          UnitPrice__c,
          Quantity__c,
          ProductName__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :history.Id
        ORDER BY ProductName__c ASC
      ];
      System.assertEquals(2, lines.size(), '同一請求に明細2行あること');
      Id invoiceId = lines[0].Invoice__c;
      InvoiceLine__c lineA = lines[0];
      InvoiceLine__c lineB = lines[1];

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      // 明細Aだけ端数調整
      InvoiceCanonicalService.updateLineAmount(lineA.Id, lineA.Amount__c + 10);

      Invoice__c afterAdjust = [
        SELECT Amount__c, PeriodLineAmountTotal__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :invoiceId
      ];
      System.assertEquals(
        true,
        afterAdjust.IsManuallyAdjusted__c,
        '端数調整後は請求ヘッダが手動調整済'
      );
      Decimal baselineBeforeSplit = afterAdjust.PeriodLineAmountTotal__c;
      System.assertEquals(
        60000,
        baselineBeforeSplit,
        '調整前合計は分割前の税抜合計を保持'
      );

      // 明細Bを単価分割（Aは触らない）
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

      InvoiceLine__c lineAAfter = [
        SELECT Id, Amount__c, IsManuallyAdjusted__c
        FROM InvoiceLine__c
        WHERE Id = :lineA.Id
      ];
      System.assertEquals(
        true,
        lineAAfter.IsManuallyAdjusted__c,
        '未分割の明細Aの手動調整フラグは残る'
      );
      System.assertEquals(
        30010,
        lineAAfter.Amount__c,
        '明細Aの端数調整額は維持'
      );

      Invoice__c afterSplit = [
        SELECT Amount__c, PeriodLineAmountTotal__c, IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :invoiceId
      ];
      Boolean hasManual = OrderCreateController.hasManualInvoiceAdjustment(
        history.Id
      );

      // 兄弟明細に調整が残るならヘッダも手動調整済・調整前合計を維持
      System.assertEquals(
        true,
        afterSplit.IsManuallyAdjusted__c,
        '別明細分割でもヘッダ手動調整フラグは残る'
      );
      System.assertEquals(
        true,
        hasManual,
        '差し戻し警告 hasManualInvoiceAdjustment が true のまま'
      );
      System.assertEquals(
        baselineBeforeSplit,
        afterSplit.PeriodLineAmountTotal__c,
        '調整前合計は分割後も据え置き（端数実績を消さない）'
      );
    }
  }
}
