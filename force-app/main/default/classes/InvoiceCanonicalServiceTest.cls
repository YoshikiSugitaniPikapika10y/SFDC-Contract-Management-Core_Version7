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
      System.assertEquals(1, invoices.size(), '???????E?');
      System.assertEquals(30000, invoices[0].Amount__c);
      System.assertEquals(
        TaxCalculationUtil.calculateTaxAmount(30000, 10),
        invoices[0].TaxAmount__c,
        '??10%???E
      );
      System.assertEquals(false, invoices[0].IsManuallyAdjusted__c);

      List<InvoiceLine__c> lines = [
        SELECT Id, Amount__c, ProductName__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoices[0].Id
      ];
      System.assertEquals(1, lines.size(), '????E????E??1???E??E);
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
          '???E?????E????????????E,
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
      System.assertEquals(
        beforeInvoice.TaxAmount__c,
        afterInvoice.TaxAmount__c
      );
      System.assertEquals(
        false,
        afterInvoice.IsManuallyAdjusted__c,
        '???????????????E
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
      System.assertEquals('??????E?E?????E, ex.getMessage());
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void updateLineAmounts_missingOrgDefault_errorsInsteadOfHalfUp() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      InvoiceLine__c line = [
        SELECT Id
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceCanonicalService.LineAmountEdit edit = new InvoiceCanonicalService.LineAmountEdit();
      edit.lineId = line.Id;
      edit.amount = 100.4;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      AmountCalculationSettingService.testMissingOrgDefault = true;
      AmountCalculationSettingService.clearCache();
      Exception thrown = null;
      try {
        InvoiceCanonicalService.updateLineAmounts(
          new List<InvoiceCanonicalService.LineAmountEdit>{ edit }
        );
      } catch (InvoiceCanonicalService.InvoiceEditException ex) {
        thrown = ex;
      } finally {
        AmountCalculationSettingService.testMissingOrgDefault = false;
        AmountCalculationSettingService.clearCache();
      }
      System.assertNotEquals(
        null,
        thrown,
        'Core 第11.9節・第1.1.10節: 金額計算設定が無ければ端数調整をエラーにする'
      );
      System.assert(
        thrown.getMessage().contains('金額計算設定'),
        thrown.getMessage()
      );
    }
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
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = Date.today();
      InvoiceTransactionStatusService.allowStatusWrite = true;
      update invoice;
      InvoiceTransactionStatusService.allowStatusWrite = false;

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
        '??E????E???????????E????E
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
  static void updateInvoiceHeaderAndDates_marksAdjustedClearsMergeKey() {
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
      // ?????? MergeKey ???????E??????????E?E
      update new Invoice__c(Id = invoice.Id, MergeKey__c = 'test-merge-key');

      Date newInvoiceDate = Date.newInstance(2026, 7, 1);
      Date newPaymentDate = Date.newInstance(2026, 7, 31);
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.updateInvoiceHeaderAndDates(
        invoice.Id,
        newInvoiceDate,
        newPaymentDate,
        null,
        null,
        null,
        null,
        null,
        null,
        TaxCalculationUtil.fromPercentFieldStorage(invoice.TaxPercent__c)
      );
      Test.stopTest();

      Invoice__c updated = [
        SELECT
          InvoiceDate__c,
          PaymentScheduledDate__c,
          IsManuallyAdjusted__c,
          IsSplitMoved__c,
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
      System.assertEquals(
        false,
        updated.IsSplitMoved__c,
        '??????E?E?E??????E?E? IsSplitMoved ?????E
      );
      System.assertEquals(
        null,
        updated.MergeKey__c,
        '????????????'
      );
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
        '?E????E???E????E?????'
      );

      // ??E?? BA ??????????????E??????E??????????E?????E
      System.assertNotEquals(null, source.BillingAccountSnapShot__c);
      update new BillingAccount__c(
        Id = source.BillingAccountSnapShot__c,
        BillingAddressee__c = '?E????????? ??'
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
        '?E??????E???????E????????????'
      );
      System.assertEquals(Date.newInstance(2026, 7, 1), created.InvoiceDate__c);
      System.assertEquals(true, created.IsManuallyAdjusted__c);
      System.assertEquals(
        '?E????????? ??',
        created.BillingAddresseeSnapShot__c
      );
      System.assertEquals(
        null,
        created.MergeKey__c,
        '?E??????E MergeKey ??????E????? Id ??E??E?E
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
        '?E??????E????E???E??E??E??????E???E??'
      );
      System.assertEquals(
        line.ContractProduct__c,
        createdLine.ContractProduct__c
      );

      Invoice__c remain = [
        SELECT
          Amount__c,
          PeriodLineAmountTotal__c,
          BillingAddresseeSnapShot__c,
          MergeKey__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(20000, remain.Amount__c);
      System.assertEquals(
        20000,
        remain.PeriodLineAmountTotal__c,
        '?E???E????E???????E???????????'
      );
      System.assertEquals(
        originalAddressee,
        remain.BillingAddresseeSnapShot__c
      );
      System.assertEquals(
        null,
        remain.MergeKey__c,
        '?E???E??????E MergeKey ???E??????? Id ??E??E?E
      );
    }
  }

  @IsTest
  static void splitInvoiceByDate_requiresPaymentScheduledDate() {
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
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 10000;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Boolean threw = false;
      try {
        InvoiceCanonicalService.splitInvoiceByDate(
          source.Id,
          Date.newInstance(2026, 7, 1),
          null,
          new List<InvoiceCanonicalService.SplitLineInput>{ split }
        );
      } catch (InvoiceCanonicalService.InvoiceEditException e) {
        threw = true;
        System.assert(
          e.getMessage().contains('?????'),
          e.getMessage()
        );
      }
      System.assertEquals(true, threw, '????? null ???????');
    }
  }

  @IsTest
  static void splitInvoiceByDate_gapWithoutLineFlag_marksAmountAdjustedAndKeepsPeriod() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id, Amount__c, PeriodLineAmountTotal__c, TaxPercent__c
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
          Product__c,
          RevenueRecognitionBasis__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      // ?????E??E?????E???E40000?E????�?????????????
      InvoiceLine__c lineB = lineA.clone(false, true, false, false);
      lineB.Amount__c = 10000;
      lineB.UnitPrice__c = 10000;
      lineB.Quantity__c = 1;
      lineB.IsAmountAdjusted__c = false;
      lineB.IsSplitMoved__c = false;
      lineB.IsManuallyAdjusted__c = false;
      insert lineB;
      update new Invoice__c(
        Id = source.Id,
        Amount__c = 40000,
        PeriodLineAmountTotal__c = 40000,
        TaxAmount__c = TaxCalculationUtil.calculateTaxAmount(40000, 10)
      );

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      // A ??E+3?E????E??E ??????E??
      InvoiceCanonicalService.updateLineAmount(lineA.Id, 30003);

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = lineB.Id;
      split.moveAmount = 10000;

      Test.startTest();
      Id createdId = InvoiceCanonicalService.splitInvoiceByDate(
        source.Id,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );

      Invoice__c created = [
        SELECT
          Amount__c,
          PeriodLineAmountTotal__c,
          IsAmountAdjusted__c,
          IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :createdId
      ];
      System.assertEquals(10000, created.Amount__c);
      System.assertNotEquals(
        created.Amount__c,
        created.PeriodLineAmountTotal__c,
        '????E????E?E??E?????'
      );
      System.assertEquals(
        true,
        created.IsAmountAdjusted__c,
        '???E?E???????E???????????'
      );
      System.assertEquals(true, created.IsSplitMoved__c);

      Decimal periodBeforeInPlace = created.PeriodLineAmountTotal__c;
      InvoiceLine__c movedLine = [
        SELECT Id, UnitPrice__c, Quantity__c, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :createdId
        LIMIT 1
      ];
      InvoiceCanonicalService.SplitLineInput inPlace = new InvoiceCanonicalService.SplitLineInput();
      inPlace.lineId = movedLine.Id;
      inPlace.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      inPlace.remainUnitPrice = 4000;
      inPlace.moveUnitPrice = 6000;

      InvoiceCanonicalService.splitLinesInPlace(
        createdId,
        new List<InvoiceCanonicalService.SplitLineInput>{ inPlace }
      );
      Test.stopTest();

      Invoice__c afterInPlace = [
        SELECT Amount__c, PeriodLineAmountTotal__c, IsAmountAdjusted__c
        FROM Invoice__c
        WHERE Id = :createdId
      ];
      System.assertEquals(
        true,
        afterInPlace.IsAmountAdjusted__c,
        '?????E?E???????E?E???????????E
      );
      System.assertEquals(
        periodBeforeInPlace,
        afterInPlace.PeriodLineAmountTotal__c,
        '????E?E????E????????????E???'
      );
      System.assertNotEquals(
        afterInPlace.Amount__c,
        afterInPlace.PeriodLineAmountTotal__c
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
      // ?? +1 ???E??: ???E30000 / ??E30001 ?E??E10000 ???????E
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
        '????E?????????E?E?E0000�E0000/30001 ?E10000?E?E
      );
      System.assertEquals(
        20000,
        remain.PeriodLineAmountTotal__c,
        '??E?????E?E?????E???E?E??????E?E+1???E????E?E
      );
      System.assertEquals(
        30000,
        created.PeriodLineAmountTotal__c + remain.PeriodLineAmountTotal__c,
        '?E????????????E???E?????'
      );
    }
  }

  @IsTest
  static void allocatePeriodTotalByAbsShare_splitsBaselineByAbsContribution() {
    System.assertEquals(
      1000,
      InvoiceCanonicalService.allocatePeriodTotalByAbsShare(2000, 1000, 1000),
      '????E??????????E
    );
    System.assertEquals(
      2000,
      InvoiceCanonicalService.allocatePeriodTotalByAbsShare(2000, 1000, 0),
      '??E??E???????E
    );
    System.assertEquals(
      0,
      InvoiceCanonicalService.allocatePeriodTotalByAbsShare(2000, 0, 1000),
      '???E??E????0'
    );
    System.assertEquals(
      2000,
      InvoiceCanonicalService.allocatePeriodTotalByAbsShare(2000, 0, 0),
      '???E??E????E??E??E???????E
    );
    System.assertEquals(
      67,
      InvoiceCanonicalService.allocatePeriodTotalByAbsShare(100, 2, 1),
      'HALF_UP ??E????E???????E
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
        SELECT
          Id,
          PeriodLineAmountTotal__c,
          ContractService__c,
          ContractHistory__c
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
          Product__c,
          RevenueRecognitionBasis__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      InvoiceLine__c lineB = lineA.clone(false, true, false, false);
      lineB.Amount__c = 30000;
      lineB.IsAmountAdjusted__c = true;
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
      System.assertEquals(0, beforeMove.Amount__c, '??????E?????');
      System.assertEquals(
        30000,
        beforeMove.PeriodLineAmountTotal__c,
        '????E????????'
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
        '??0?????????E????E?????E???E
      );
      System.assertEquals(
        15000,
        afterSource.PeriodLineAmountTotal__c,
        '??E???????E'
      );
      System.assertEquals(
        30000,
        afterSource.PeriodLineAmountTotal__c +
        afterTarget.PeriodLineAmountTotal__c,
        '????????????E???E?????'
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
          Product__c,
          RevenueRecognitionBasis__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        LIMIT 1
      ];
      // ????????E??????????????E0 ???
      InvoiceLine__c lineB = lineA.clone(false, true, false, false);
      lineB.Amount__c = 30000;
      lineB.IsAmountAdjusted__c = true;
      lineB.IsManuallyAdjusted__c = true;
      insert lineB;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      InvoiceCanonicalService.updateLineAmount(lineA.Id, -30000);

      Invoice__c beforeSplit = [
        SELECT Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(0, beforeSplit.Amount__c, '??????E?????');
      System.assertEquals(
        30000,
        beforeSplit.PeriodLineAmountTotal__c,
        '????E????????'
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
        '??0??????E????E?????E???E
      );
      System.assertEquals(
        15000,
        remain.PeriodLineAmountTotal__c,
        '??E???????E'
      );
      System.assertEquals(
        30000,
        created.PeriodLineAmountTotal__c + remain.PeriodLineAmountTotal__c,
        '?E????????????E???E?????'
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
        '?????????????????'
      );

      Invoice__c remain = [
        SELECT Amount__c
        FROM Invoice__c
        WHERE Id = :line.Invoice__c
      ];
      System.assertEquals(
        -6000,
        remain.Amount__c,
        '?????E??????????'
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
        '???????E???E??????????'
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
      System.assertEquals(30000, target.Amount__c, '???E????????');
      System.assertEquals(
        30000,
        target.PeriodLineAmountTotal__c,
        '??????????????'
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
        '???????E??????'
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
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
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
      System.assertEquals(true, blocked, '??E??????????E??');
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Invoice__c WHERE Id = :sourceId],
        '????E???E?????'
      );
      System.assertEquals(
        sourceAmountBefore,
        [
          SELECT Amount__c
          FROM Invoice__c
          WHERE Id = :sourceId
        ]
        .Amount__c,
        '????E???E????E
      );
      System.assertEquals(
        sourceLineCountBefore,
        [
          SELECT COUNT()
          FROM InvoiceLine__c
          WHERE Invoice__c = :sourceId
        ],
        '????E???E?????E
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

      // 2?????E?E????E? SOQL ????? startTest ????
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
          '?? Version?E???E????E??E??????E???????E,
          ex.getMessage()
        );
      }
      Test.stopTest();
      System.assertEquals(true, failed, '???E????????E??????');
    }
  }


  /** ???????E???E????????????????E?E??????????????E??E*/
  @IsTest
  static void splitLinesInPlace_keepsSiblingManualAdjustmentOnHeader() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      Test.startTest();
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
      productB.BillingType__c = '????E;
      ContractTestDataFactory.insertProduct(productB);
      ContractProduct__c cpB = new ContractProduct__c(
        ContractHistory__c = fixture.history.Id,
        Product__c = productB.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Unit__c = 'ID',
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 8, 31),
        InvoiceSetting__c = '????',
        BillingType__c = '????E,
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

      InvoiceCanonicalService.splitLinesInPlace(
        invoiceId,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );

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
      Test.stopTest();
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
        '?????E?E????????????E
      );
      List<InvoiceLine__c> lines = [
        SELECT
          Amount__c,
          UnitPrice__c,
          Quantity__c,
          IsManuallyAdjusted__c,
          IsAmountAdjusted__c,
          IsSplitMoved__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoiceId
        ORDER BY UnitPrice__c ASC
      ];
      System.assertEquals(2, lines.size());
      System.assertEquals(4000, lines[0].UnitPrice__c);
      System.assertEquals(6000, lines[1].UnitPrice__c);
      System.assertEquals(12000, lines[0].Amount__c);
      System.assertEquals(18000, lines[1].Amount__c);
      System.assertEquals(false, lines[0].IsAmountAdjusted__c);
      System.assertEquals(false, lines[1].IsAmountAdjusted__c);
      System.assertEquals(true, lines[0].IsSplitMoved__c);
      System.assertEquals(true, lines[1].IsSplitMoved__c);
      System.assertEquals(true, lines[0].IsManuallyAdjusted__c);
      System.assertEquals(true, lines[1].IsManuallyAdjusted__c);

      Invoice__c invoice = [
        SELECT
          Amount__c,
          PeriodLineAmountTotal__c,
          IsManuallyAdjusted__c,
          IsAmountAdjusted__c,
          IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoiceId
      ];
      System.assertEquals(30000, invoice.Amount__c);
      System.assertEquals(30000, invoice.PeriodLineAmountTotal__c);
      System.assertEquals(false, invoice.IsAmountAdjusted__c);
      System.assertEquals(true, invoice.IsSplitMoved__c);
      System.assertEquals(true, invoice.IsManuallyAdjusted__c);
    }
  }

  @IsTest
  static void splitLinesInPlace_copiesUnitFromSourceLine() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      InvoiceLine__c line = [
        SELECT Id, Invoice__c, Unit__c, ContractProduct__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      line.Unit__c = '式';
      update line;
      update new ContractProduct__c(
        Id = line.ContractProduct__c,
        Unit__c = 'ライセンス'
      );

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      split.remainUnitPrice = 4000;
      split.moveUnitPrice = 6000;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        line.Invoice__c,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      for (InvoiceLine__c row : [
        SELECT Unit__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :line.Invoice__c
      ]) {
        System.assertEquals(
          '式',
          row.Unit__c,
          'Core 第7.8節・第1.1.10節: 分割先の単位は元明細であり商品マスタではない'
        );
      }
    }
  }

  /**
   * ???????E?????????????E?E??????E
   * ??ESourcePeriodLineIds ????????????????E????E
   */
  @IsTest
  static void splitLinesInPlace_afterDateSplitDoesNotInflateOnAmountReset() {
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
      Id sourceInvoiceId = line.Invoice__c;
      Decimal original = line.Amount__c;
      Decimal moveAmount = (original / 2).setScale(0, RoundingMode.HALF_UP);
      Decimal remainShare = original - moveAmount;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      InvoiceCanonicalService.SplitLineInput dateSplit = new InvoiceCanonicalService.SplitLineInput();
      dateSplit.lineId = line.Id;
      dateSplit.moveAmount = moveAmount;
      InvoiceCanonicalService.splitInvoiceByDate(
        sourceInvoiceId,
        Date.newInstance(2026, 7, 1),
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ dateSplit }
      );

      InvoiceLine__c remainLine = [
        SELECT Id, Invoice__c, Amount__c, UnitPrice__c, Quantity__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :sourceInvoiceId
        LIMIT 1
      ];
      System.assertEquals(remainShare, remainLine.Amount__c);

      InvoiceCanonicalService.updateLineAmount(remainLine.Id, remainShare + 10);

      // ?????E????E???E??: ?????E40%/60% ??E???E
      Decimal remainUnit = remainLine.UnitPrice__c == null
        ? 0
        : remainLine.UnitPrice__c;
      InvoiceCanonicalService.SplitLineInput unitSplit = new InvoiceCanonicalService.SplitLineInput();
      unitSplit.lineId = remainLine.Id;
      unitSplit.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      unitSplit.remainUnitPrice = (remainUnit * 0.4)
        .setScale(2, RoundingMode.HALF_UP);
      unitSplit.moveUnitPrice = (remainUnit * 0.6)
        .setScale(2, RoundingMode.HALF_UP);

      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        sourceInvoiceId,
        new List<InvoiceCanonicalService.SplitLineInput>{ unitSplit }
      );
      Test.stopTest();

      Invoice__c remainInvoice = [
        SELECT Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :sourceInvoiceId
      ];
      System.assertEquals(
        remainShare,
        remainInvoice.Amount__c,
        '?????E????????????????????????E
      );
      System.assertEquals(remainShare, remainInvoice.PeriodLineAmountTotal__c);

      Decimal lineSum = 0;
      for (InvoiceLine__c row : [
        SELECT Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :sourceInvoiceId
      ]) {
        lineSum += row.Amount__c == null ? 0 : row.Amount__c;
      }
      System.assertEquals(remainShare, lineSum);

      AggregateResult serviceTotal = [
        SELECT SUM(Amount__c) total
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
      ];
      System.assertEquals(
        original,
        (Decimal) serviceTotal.get('total'),
        '?????????E????E??????'
      );
    }
  }

  /**
   * ?????E????E????????E?E???????E???ID???????E????E
   */
  @IsTest
  static void splitLinesInPlace_afterUnitSplitDoesNotInflateOnAmountReset() {
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
      Decimal original = line.Amount__c;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      InvoiceCanonicalService.SplitLineInput first = new InvoiceCanonicalService.SplitLineInput();
      first.lineId = line.Id;
      first.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      first.remainUnitPrice = 4000;
      first.moveUnitPrice = 6000;
      InvoiceCanonicalService.splitLinesInPlace(
        invoiceId,
        new List<InvoiceCanonicalService.SplitLineInput>{ first }
      );

      InvoiceLine__c remain4000 = [
        SELECT Id, Amount__c, UnitPrice__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoiceId AND UnitPrice__c = 4000
        LIMIT 1
      ];
      System.assertEquals(12000, remain4000.Amount__c);
      InvoiceCanonicalService.updateLineAmount(remain4000.Id, 12010);

      InvoiceCanonicalService.SplitLineInput second = new InvoiceCanonicalService.SplitLineInput();
      second.lineId = remain4000.Id;
      second.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      second.remainUnitPrice = 1600;
      second.moveUnitPrice = 2400;

      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        invoiceId,
        new List<InvoiceCanonicalService.SplitLineInput>{ second }
      );
      Test.stopTest();

      Invoice__c invoice = [
        SELECT Amount__c, PeriodLineAmountTotal__c
        FROM Invoice__c
        WHERE Id = :invoiceId
      ];
      System.assertEquals(
        original,
        invoice.Amount__c,
        '???E???????E?E???????????????E
      );
      System.assertEquals(original, invoice.PeriodLineAmountTotal__c);
    }
  }

  /** ????????????E??????????????????E????E*/
  @IsTest
  static void splitLinesInPlace_resetsManualAdjustmentBeforeUnitPriceSplit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      InvoiceLine__c line = [
        SELECT Id, Invoice__c, Amount__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      Id invoiceId = line.Invoice__c;
      Decimal baseline = line.Amount__c;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      InvoiceCanonicalService.updateLineAmount(line.Id, baseline + 10);

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      split.remainUnitPrice = 4000;
      split.moveUnitPrice = 6000;

      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        invoiceId,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      Invoice__c invoice = [
        SELECT
          Amount__c,
          PeriodLineAmountTotal__c,
          IsManuallyAdjusted__c,
          IsAmountAdjusted__c,
          IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoiceId
      ];
      System.assertEquals(
        baseline,
        invoice.Amount__c,
        '?? +10 ??E???????E?????????????E
      );
      System.assertEquals(baseline, invoice.PeriodLineAmountTotal__c);
      System.assertEquals(false, invoice.IsAmountAdjusted__c);
      System.assertEquals(true, invoice.IsSplitMoved__c);
      System.assertEquals(true, invoice.IsManuallyAdjusted__c);

      List<InvoiceLine__c> lines = [
        SELECT
          Amount__c,
          IsManuallyAdjusted__c,
          IsAmountAdjusted__c,
          IsSplitMoved__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoiceId
      ];
      Decimal lineSum = 0;
      for (InvoiceLine__c row : lines) {
        lineSum += row.Amount__c == null ? 0 : row.Amount__c;
        System.assertEquals(false, row.IsAmountAdjusted__c);
        System.assertEquals(true, row.IsSplitMoved__c);
        System.assertEquals(true, row.IsManuallyAdjusted__c);
      }
      System.assertEquals(baseline, lineSum);
    }
  }

  /** ????E?Change Original ???E??????????E????????E*/
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
        '?????????E'
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
        '??????????E?E????0'
      );
      for (OrderCreateController.InvoiceGroupDto groupRow : preview.invoices) {
        for (OrderCreateController.InvoiceMergedLineDto row : groupRow.lines) {
          System.assertEquals(
            false,
            row.hasAmountDrift,
            '???????E?????????E ' + row.amountDeltaFromSource
          );
        }
      }
    }
  }

  /** ????E???E??E??????E????E???E*/
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
        '????????E??????E'
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
  static void splitLinesInPlace_unitPriceHalfUpFullAmountIsConserved() {
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
      line.UnitPrice__c = 1;
      line.Quantity__c = 1;
      line.Amount__c = 1;
      update line;

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_UNIT_PRICE;
      split.remainUnitPrice = 0.5;
      split.moveUnitPrice = 0.5;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        line.Invoice__c,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      List<InvoiceLine__c> lines = [
        SELECT Amount__c, UnitPrice__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :line.Invoice__c
        ORDER BY Amount__c DESC
      ];
      System.assertEquals(
        2,
        lines.size(),
        'Core 第7.8節: 単価分割は2行に分ける'
      );
      System.assertEquals(
        1,
        lines[0].Amount__c + lines[1].Amount__c,
        'Core 第7.8.4節: moveAmount + remainAmount == 元明細Amount'
      );
      System.assertEquals(
        0,
        lines[1].Amount__c,
        'Core 第1.1.4節: HALF_UPで片方が0円になっても混在できる'
      );
    }
  }

  @IsTest
  static void splitLinesInPlace_quantityHalfUpFullAmountIsConserved() {
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
      line.Quantity__c = 1;
      line.UnitPrice__c = 1;
      line.Amount__c = 1;
      update line;

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.splitMode = InvoiceCanonicalService.SPLIT_MODE_QUANTITY;
      split.remainQuantity = 0.5;
      split.moveQuantity = 0.5;

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.splitLinesInPlace(
        line.Invoice__c,
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      List<InvoiceLine__c> lines = [
        SELECT Amount__c, Quantity__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :line.Invoice__c
        ORDER BY Amount__c DESC
      ];
      System.assertEquals(
        2,
        lines.size(),
        'Core 第7.8節: 個数分割は2行に分ける'
      );
      System.assertEquals(
        1,
        lines[0].Amount__c + lines[1].Amount__c,
        'Core 第7.8.4節: moveAmount + remainAmount == 元明細Amount'
      );
      System.assertEquals(
        0,
        lines[1].Amount__c,
        'Core 第1.1.4節: HALF_UPで片方が0円になっても混在できる'
      );
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
          IsManuallyAdjusted__c,
          IsAmountAdjusted__c,
          IsSplitMoved__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :source.Id
        ORDER BY Amount__c ASC
      ];
      System.assertEquals(2, lines.size());
      System.assertEquals(10000, lines[0].Amount__c);
      System.assertEquals(20000, lines[1].Amount__c);
      System.assertEquals(false, lines[0].IsAmountAdjusted__c);
      System.assertEquals(false, lines[1].IsAmountAdjusted__c);
      System.assertEquals(true, lines[0].IsSplitMoved__c);
      System.assertEquals(true, lines[1].IsSplitMoved__c);
      System.assertEquals(true, lines[0].IsManuallyAdjusted__c);
      System.assertEquals(true, lines[1].IsManuallyAdjusted__c);

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
            '???E??????????E???'
          );
          sawMoved = true;
        }
      }
      System.assertEquals(true, sawJuneOnly);
      System.assertEquals(true, sawMoved);

      Invoice__c invoice = [
        SELECT
          Amount__c,
          PeriodLineAmountTotal__c,
          IsManuallyAdjusted__c,
          IsAmountAdjusted__c,
          IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :source.Id
      ];
      System.assertEquals(30000, invoice.Amount__c);
      System.assertEquals(30000, invoice.PeriodLineAmountTotal__c);
      System.assertEquals(false, invoice.IsAmountAdjusted__c);
      System.assertEquals(true, invoice.IsSplitMoved__c);
      System.assertEquals(true, invoice.IsManuallyAdjusted__c);
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
      // ???E??E?: 6??E/ 7?E????Eixture ??E?E?E?E?E
      System.assertEquals(10000, rows[0].options[0].remainAmount);
      System.assertEquals(20000, rows[0].options[0].moveAmount);
      System.assertEquals(20000, rows[0].options[1].remainAmount);
      System.assertEquals(10000, rows[0].options[1].moveAmount);
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
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
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
      System.assertEquals(true, blocked, '??E?????E?????E?E?????');
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM InvoiceLine__c
          WHERE Invoice__c = :line.Invoice__c
        ],
        '????E???????E
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
      System.assert(originalAmount > 1000, '?E????????E????????');

      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 1000;
      // ?E???????E??E?Emove+remain ??E??E????????E?E
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
      System.assertEquals(true, blocked, 'remain ??????');

      AggregateResult total = [
        SELECT SUM(Amount__c) amt
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
      ];
      System.assertEquals(
        originalAmount,
        (Decimal) total.get('amt'),
        '?????????E?????E
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
          InvoiceCanonicalService.SPLIT_AMOUNT_CONSERVE_MESSAGE +
          ': Test Product',
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
        '??E????Ecurrent - move'
      );
      System.assertEquals(
        9000,
        InvoiceCanonicalService.resolveConservingRemainAmount(
          1000,
          9000,
          10000,
          null
        ),
        '???? remain ???'
      );
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
        SELECT
          Id,
          PaymentTermMethodSnapShot__c,
          Amount__c,
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      String originalPaymentTerm = invoice.PaymentTermMethodSnapShot__c;
      Date newInvoiceDate = Date.newInstance(2026, 8, 20);
      Date newPaymentDate = Date.newInstance(2026, 9, 30);

      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.updateInvoiceHeaderAndDates(
        invoice.Id,
        newInvoiceDate,
        newPaymentDate,
        null,
        '?????? ??',
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
          PaymentTermMethodSnapShot__c,
          TaxPercent__c,
          TaxAmount__c,
          Amount__c,
          IsManuallyAdjusted__c,
          IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(newInvoiceDate, updated.InvoiceDate__c);
      System.assertEquals(newPaymentDate, updated.PaymentScheduledDate__c);
      System.assertEquals(
        invoice.BillingAddresseeSnapShot__c,
        updated.BillingAddresseeSnapShot__c,
        '??????E?E?????????E
      );
      System.assertEquals(
        invoice.BillingEmailToSnapShot__c,
        updated.BillingEmailToSnapShot__c,
        '??????E?E??????????E
      );
      System.assertEquals(
        originalPaymentTerm,
        updated.PaymentTermMethodSnapShot__c,
        '???? SnapShot ????????E??????E
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
      System.assertEquals(
        false,
        updated.IsSplitMoved__c,
        '??????E?E?E??????E?E? IsSplitMoved ?????E
      );
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
          PaymentScheduledDate__c,
          TaxPercent__c
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
        PaymentTermMethod__c,
        InvoiceDateDayOfMonth__c
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
      InvoiceCanonicalService.updateInvoiceHeaderAndDates(
        invoice.Id,
        Date.newInstance(2026, 8, 15),
        Date.newInstance(2026, 9, 30),
        null,
        null,
        null,
        null,
        null,
        null,
        TaxCalculationUtil.fromPercentFieldStorage(invoice.TaxPercent__c)
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
        PaymentTermMethod__c,
        InvoiceDateDayOfMonth__c
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
      System.assertEquals(baBefore.PaymentTermMethod__c, baAfter.PaymentTermMethod__c);
      System.assertEquals(
        baBefore.InvoiceDateDayOfMonth__c,
        baAfter.InvoiceDateDayOfMonth__c
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
        '??E????',
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
        SELECT Id, BillingAccountSnapShot__c, ContractService__r.Account__c, InvoiceDate__c
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
        BillingAddressee__c = '????E ??',
        BillingEmailTo__c = 'other@example.com',
        InvoiceDeliveryMethod__c = InvoiceDeliveryMethodService.POST,
              InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
              InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
              InvoiceDateDayOfMonth__c = 15,
              InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
        PaymentTermMonthOffset__c = 0,
        PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
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
        source.InvoiceDate__c,
        Date.newInstance(2026, 7, 31),
        new List<InvoiceCanonicalService.SplitLineInput>{ split }
      );
      Test.stopTest();

      Invoice__c created = [
        SELECT
          Amount__c,
          BillingAccountSnapShot__c,
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c,
          PaymentTermMethodSnapShot__c,
          InvoiceDeliveryMethodSnapShot__c,
          IsManuallyAdjusted__c
        FROM Invoice__c
        WHERE Id = :createdId
      ];
      System.assertEquals(5000, created.Amount__c);
      System.assertEquals(otherBa.Id, created.BillingAccountSnapShot__c);
      // ?E???????E??E?EBA ??????????? SnapShot
      System.assertEquals('????E ??', created.BillingAddresseeSnapShot__c);
      System.assertEquals(
        'other@example.com',
        created.BillingEmailToSnapShot__c
      );
      System.assertEquals(
        BillingScheduleService.METHOD_MONTH_OFFSET,
        created.PaymentTermMethodSnapShot__c,
        'Core 第7.5節: 分割先請求へ支払条件の計算方式をスナップショットする'
      );
      System.assertEquals(
        InvoiceDeliveryMethodService.POST,
        created.InvoiceDeliveryMethodSnapShot__c,
        'Core 第3.3.7節: 分割先請求へ届け方をスナップショットする'
      );
      System.assertEquals(true, created.IsManuallyAdjusted__c);
    }
  }

  @IsTest
  static void splitInvoiceByBillingAccount_rejectsNullInvoiceDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c source = [
        SELECT Id, ContractService__r.Account__c
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
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'ba-date@example.com',
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
        InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
        InvoiceDateDayOfMonth__c = 15,
        InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
        PaymentTermMonthOffset__c = 0,
        PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE
      );
      ContractTestDataFactory.applyRequiredFields(otherBa);
      insert otherBa;
      InvoiceCanonicalService.SplitLineInput split = new InvoiceCanonicalService.SplitLineInput();
      split.lineId = line.Id;
      split.moveAmount = 1;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;

      Boolean rejected = false;
      try {
        InvoiceCanonicalService.splitInvoiceByBillingAccount(
          source.Id,
          otherBa.Id,
          null,
          Date.newInstance(2026, 7, 31),
          new List<InvoiceCanonicalService.SplitLineInput>{ split }
        );
      } catch (InvoiceCanonicalService.InvoiceEditException ex) {
        rejected = true;
        System.assertEquals('分割先の請求日は必須です。', ex.getMessage());
      }
      System.assertEquals(
        true,
        rejected,
        'Core 第7.8節: 新しい請求日の未入力をサーバで拒否する'
      );
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
      // ?EOrdered ????????????????? Invoice ????????E???
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
        '????????E???E
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
          '????????E???E?????????E????????E?????E,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown, '?EOrdered ?? rebuild ???');
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE ContractHistory__c = :fixture.history.Id
        ],
        '??????????????E
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
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = Date.today();
      InvoiceTransactionStatusService.allowStatusWrite = true;
      update invoice;
      InvoiceTransactionStatusService.allowStatusWrite = false;

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
        '??E????????? Version ???????'
      );

      ContractHistory__c stillHistory = [
        SELECT historystatus__c
        FROM ContractHistory__c
        WHERE Id = :fixture.history.Id
      ];
      System.assertEquals(
        'Ordered',
        stillHistory.historystatus__c,
        '?????????????'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Invoice__c
          WHERE Id = :invoice.Id AND SystemIntegrationDate__c != NULL
        ],
        '??????E??'
      );
    }
  }

  @IsTest
  static void getInvoicePreview_readsCanonicalAndBackfills() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      // ???????????E???? open ??????E?E???E? rebuild ???E
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
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

      // ?E???E?????????????E???????E???E?????
      update new Invoice__c(
        Id = source.Id,
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
        CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_COMPLETED,
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
        InvoiceCanonicalService.updateInvoiceHeaderAndDates(
          source.Id,
          Date.newInstance(2026, 8, 1),
          Date.newInstance(2026, 8, 31),
          null,
          null,
          null,
          null,
          null,
          null,
          10
        );
      } catch (InvoiceCanonicalService.InvoiceEditException ex) {
        lockedBlocked = true;
        System.assertEquals(
          InvoiceLockUtil.CONFIRMED_CORE_FIELDS_BLOCK_MESSAGE,
          ex.getMessage(),
          'Core 第7.8節・第11.4.4節: 確定後は請求日・入金予定日・税率を拒否する'
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
      System.assertEquals(true, lockedBlocked, '??E?????E??E?E??');

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
        '??E?????????????E
      );
      System.assertEquals(
        20000,
        lockedStill.Amount__c,
        '??E????????E????E??'
      );
    }
  }

  @IsTest
  static void updateInvoiceHeaderAndDates_confirmedExtraExemptUpdatesDateRefused() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceOpsFieldService.setCachedRowsForTest(
        new List<InvoiceOpsField__mdt>{
          new InvoiceOpsField__mdt(
            DeveloperName = 'InvoiceMemoExtra',
            Active__c = true,
            TargetObject__c = 'Invoice__c',
            FieldApiName__c = 'Memo__c'
          )
        }
      );
      InvoiceLockUtil.testLockExemptFieldApiNames = InvoiceLockUtil.SEED_LOCK_EXEMPT_FIELDS;
      InvoiceLockUtil.testCanBypassLockedDml = false;
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          PaymentScheduledDate__c,
          TaxPercent__c,
          Memo__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      InvoiceLockUtil.allowLockedStatusWrite = true;
      InvoiceTransactionStatusService.allowStatusWrite = true;
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      invoice.SystemIntegrationDate__c = Date.today();
      update invoice;
      InvoiceTransactionStatusService.allowStatusWrite = false;
      InvoiceLockUtil.allowLockedStatusWrite = false;
      invoice = [
        SELECT
          Id,
          InvoiceDate__c,
          PaymentScheduledDate__c,
          TaxPercent__c,
          Memo__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      Decimal taxPercent = TaxCalculationUtil.fromPercentFieldStorage(
        invoice.TaxPercent__c
      );
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.updateInvoiceHeaderAndDates(
        invoice.Id,
        invoice.InvoiceDate__c,
        invoice.PaymentScheduledDate__c,
        null,
        null,
        null,
        null,
        null,
        null,
        taxPercent,
        new Map<String, Object>{ 'Memo__c' => '確定後メモ' }
      );
      Boolean dateBlocked = false;
      try {
        InvoiceCanonicalService.updateInvoiceHeaderAndDates(
          invoice.Id,
          Date.newInstance(2026, 12, 1),
          invoice.PaymentScheduledDate__c,
          null,
          null,
          null,
          null,
          null,
          null,
          taxPercent,
          new Map<String, Object>{ 'Memo__c' => '確定後メモ' }
        );
      } catch (InvoiceCanonicalService.InvoiceEditException ex) {
        dateBlocked = true;
        System.assertEquals(
          InvoiceLockUtil.CONFIRMED_CORE_FIELDS_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      Test.stopTest();
      Invoice__c updated = [
        SELECT Memo__c, InvoiceDate__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        '確定後メモ',
        updated.Memo__c,
        'Core 第11.4.4節: 確定後はロック除外の追加項目だけ更新できる'
      );
      System.assertEquals(invoice.InvoiceDate__c, updated.InvoiceDate__c);
      System.assertEquals(
        true,
        dateBlocked,
        'Core 第7.8節・第11.4.4節: 確定後の請求日変更は拒否する'
      );
      InvoiceOpsFieldService.resetCache();
      InvoiceLockUtil.testLockExemptFieldApiNames = null;
      InvoiceLockUtil.testCanBypassLockedDml = null;
    }
  }

  @IsTest
  static void applyRecognitionBucketCount_monthlyJan11ToMar24_is3() {
    ContractTestDataFactory.ensureOrgAccountingPolicy();
    InvoiceLine__c line = new InvoiceLine__c(
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME,
      ServicePeriodStartDate__c = Date.newInstance(2025, 1, 11),
      ServicePeriodEndDate__c = Date.newInstance(2025, 3, 24),
      AcceptanceEndDate__c = Date.newInstance(2025, 12, 31)
    );
    InvoiceCanonicalService.applyRecognitionBucketCount(
      new List<InvoiceLine__c>{ line }
    );
    System.assertEquals(
      3,
      line.RecognitionBucketCount__c,
      'Accounting 第3.2節: 1/11～3/24 は3。検収終了日は使わない'
    );
  }

  @IsTest
  static void applyRecognitionBucketCount_lumpIs1() {
    InvoiceLine__c line = new InvoiceLine__c(
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME,
      ServicePeriodStartDate__c = Date.newInstance(2025, 1, 11),
      ServicePeriodEndDate__c = Date.newInstance(2025, 3, 24)
    );
    InvoiceCanonicalService.applyRecognitionBucketCount(
      new List<InvoiceLine__c>{ line }
    );
    System.assertEquals(
      1,
      line.RecognitionBucketCount__c,
      'Accounting 第3.2節: 一括計上は1'
    );
  }

  @IsTest
  static void applyRecognitionBucketCount_monthlyEmptyPeriod_staysBlank() {
    InvoiceLine__c line = new InvoiceLine__c(
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
    );
    InvoiceCanonicalService.applyRecognitionBucketCount(
      new List<InvoiceLine__c>{ line }
    );
    System.assertEquals(
      null,
      line.RecognitionBucketCount__c,
      'Accounting 第3.2節: 月次でサービス期間が空なら空欄'
    );
  }

  @IsTest
  static void applyRecognitionBucketCount_jan31TwelveCycles_endsJan27() {
    ContractTestDataFactory.ensureOrgAccountingPolicy();
    InvoiceLine__c line = new InvoiceLine__c(
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME,
      ServicePeriodStartDate__c = Date.newInstance(2025, 1, 31),
      ServicePeriodEndDate__c = Date.newInstance(2026, 1, 27)
    );
    InvoiceCanonicalService.applyRecognitionBucketCount(
      new List<InvoiceLine__c>{ line }
    );
    System.assertEquals(
      12,
      line.RecognitionBucketCount__c,
      '日付仕様 第1.2節: 1/31開始の12サイクル終了は翌年1/27。addMonths一発計算は使わない'
    );
  }

  @IsTest
  static void applyRecognitionBucketCount_autoApr15Lands_is12() {
    ContractTestDataFactory.ensureOrgAccountingPolicy();
    InvoiceLine__c line = new InvoiceLine__c(
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME,
      ServicePeriodStartDate__c = Date.newInstance(2025, 4, 15),
      ServicePeriodEndDate__c = Date.newInstance(2026, 4, 14)
    );
    InvoiceCanonicalService.applyRecognitionBucketCount(
      new List<InvoiceLine__c>{ line }
    );
    System.assertEquals(
      12,
      line.RecognitionBucketCount__c,
      'Accounting 第3.3節: 4/15～翌4/14 は着地するので契約日アンカー12'
    );
  }

  @IsTest
  static void applyRecognitionBucketCount_missingPolicy_errors() {
    InvoiceLine__c line = new InvoiceLine__c(
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME,
      ServicePeriodStartDate__c = Date.newInstance(2025, 1, 11),
      ServicePeriodEndDate__c = Date.newInstance(2025, 3, 24)
    );
    Boolean thrown = false;
    try {
      InvoiceCanonicalService.applyRecognitionBucketCount(
        new List<InvoiceLine__c>{ line }
      );
    } catch (Exception ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('Accounting会計方針がありません'),
        'Accounting 第3.1節・Core 第1.1.10節: 方針0件を Auto へ落とさない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void applyRecognitionBucketCount_blankMonthlyMethod_errors() {
    insert GlAccountingPolicyService.newOrgDefault();
    GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
    policy.MonthlyBucketMethod__c = null;
    update policy;
    InvoiceLine__c line = new InvoiceLine__c(
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME,
      ServicePeriodStartDate__c = Date.newInstance(2025, 1, 11),
      ServicePeriodEndDate__c = Date.newInstance(2025, 3, 24)
    );
    Boolean thrown = false;
    try {
      InvoiceCanonicalService.applyRecognitionBucketCount(
        new List<InvoiceLine__c>{ line }
      );
    } catch (Exception ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('月次バケットの刻み方がありません'),
        'Accounting 第3.2節・Core 第1.1.10節: 月次方式空を Auto へ落とさない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void trigger_writesBucketCountAndLineTaxInclusive() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      List<InvoiceLine__c> lines = [
        SELECT
          RecognitionBucketCount__c,
          TaxInclusiveAmount__c,
          Amount__c,
          AllocatedTaxAmount__c,
          AmountCommaText__c,
          TaxInclusiveCommaText__c,
          ServicePeriodStartDate__c,
          ServicePeriodEndDate__c,
          RevenueRecognitionBasis__c
        FROM InvoiceLine__c
        WHERE Invoice__r.ContractHistory__c = :fixture.history.Id
      ];
      System.assertEquals(1, lines.size());
      InvoiceLine__c line = lines[0];
      InvoiceLine__c expectedComma = new InvoiceLine__c(
        Amount__c = line.Amount__c,
        AllocatedTaxAmount__c = line.AllocatedTaxAmount__c
      );
      InvoiceCanonicalService.applyYenCommaTexts(
        new List<InvoiceLine__c>{ expectedComma }
      );
      System.assertEquals(
        '月次計上',
        ContractMetadataService.normalizeRevenueRecognitionBasis(
          line.RevenueRecognitionBasis__c
        )
      );
      System.assertEquals(
        Date.newInstance(2026, 6, 1),
        line.ServicePeriodStartDate__c
      );
      System.assertEquals(
        Date.newInstance(2026, 8, 31),
        line.ServicePeriodEndDate__c
      );
      System.assertEquals(
        3,
        line.RecognitionBucketCount__c,
        'Accounting 第3.2節: 6/1～8/31 は3'
      );
      System.assertEquals(
        line.Amount__c + nvl(line.AllocatedTaxAmount__c),
        line.TaxInclusiveAmount__c,
        'Core 第7.1節: 明細税込は税抜＋明細配分税'
      );
      System.assertEquals(
        expectedComma.AmountCommaText__c,
        line.AmountCommaText__c,
        'Accounting 第9.1.1節: Trigger が確認用の明細税抜テキストを書く'
      );
      System.assertEquals(
        expectedComma.TaxInclusiveCommaText__c,
        line.TaxInclusiveCommaText__c,
        'Accounting 第9.1.1節: 明細税込テキストは税抜＋明細税'
      );
    }
  }

  @IsTest
  static void slotKeys_blank_rejected() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      Invoice__c invoice = new Invoice__c(
        ContractService__c = fixture.history.ContractService__c,
        ContractHistory__c = fixture.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000
      );
      insert invoice;
      Boolean thrown = false;
      try {
        insert new GlJournal__c(
          Invoice__c = invoice.Id,
          Amount__c = 1000,
          IdempotencyKey__c = 'SLOT-KEYS-BLANK',
          PostingDate__c = Date.newInstance(2026, 6, 1)
        );
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('借方・貸方スロットは必須です。'),
          'Accounting 第9.1節: 借方・貸方スロットキーは必須'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void applyYenCommaTexts_millionAndDiscount() {
    InvoiceLine__c million = new InvoiceLine__c(
      Amount__c = 1000000,
      AllocatedTaxAmount__c = 0
    );
    InvoiceCanonicalService.applyYenCommaTexts(new List<InvoiceLine__c>{ million });
    System.assertEquals(
      '1,000,000',
      million.AmountCommaText__c,
      'Accounting 第9.1.1節: 桁区切りはカンマ（1,000,000）'
    );
    System.assertEquals(
      '1,000,000',
      million.TaxInclusiveCommaText__c,
      'Accounting 第9.1.1節: 明細税込は税抜＋明細税'
    );
    InvoiceLine__c discount = new InvoiceLine__c(
      Amount__c = -50000,
      AllocatedTaxAmount__c = 0
    );
    InvoiceCanonicalService.applyYenCommaTexts(new List<InvoiceLine__c>{ discount });
    System.assertEquals(
      '-50,000',
      discount.AmountCommaText__c,
      'Accounting 第9.1.1節: 値引きは 明細税抜 -50,000円'
    );
  }

  @IsTest
  static void confirmationText_monthlyRevenueBody_matchesSpecExample() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      Invoice__c invoice = new Invoice__c(
        ContractService__c = fixture.history.ContractService__c,
        ContractHistory__c = fixture.history.Id,
        InvoiceDate__c = Date.newInstance(2025, 1, 11),
        Amount__c = 300000,
        TaxAmount__c = 30000
      );
      insert invoice;
      InvoiceLine__c line = new InvoiceLine__c(
        Invoice__c = invoice.Id,
        Amount__c = 300000,
        AllocatedTaxAmount__c = 30000,
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME,
        ServicePeriodStartDate__c = Date.newInstance(2025, 1, 11),
        ServicePeriodEndDate__c = Date.newInstance(2025, 3, 24)
      );
      insert line;
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        InvoiceLine__c = line.Id,
        Amount__c = 100000,
        IdempotencyKey__c = 'CONF-TEXT-REV-BODY',
        JournalPatternKey__c = 'BILLING_BASIS_REVENUE_BODY',
        RecognitionSequence__c = 2,
        DebitSlotKey__c = 'DEF',
        CreditSlotKey__c = 'REV',
        PostingDate__c = Date.newInstance(2025, 2, 10)
      );
      GlJournal__c journal = [
        SELECT ConfirmationText__c, InvoiceLine__r.RecognitionBucketCount__c
        FROM GlJournal__c
        WHERE IdempotencyKey__c = 'CONF-TEXT-REV-BODY'
      ];
      System.assertEquals(
        3,
        journal.InvoiceLine__r.RecognitionBucketCount__c,
        'Accounting 第3.2節: 1/11～3/24 は3'
      );
      System.assertEquals(
        '明細税抜 300,000円　2025/01/11～2025/03/24　月次計上で 2/3 回目',
        journal.ConfirmationText__c,
        'Accounting 第9.1.1節: 売上本体（月次）の確認用'
      );
    }
  }

  @IsTest
  static void confirmationText_blankWhenNoInvoiceLine() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      Invoice__c invoice = new Invoice__c(
        ContractService__c = fixture.history.ContractService__c,
        ContractHistory__c = fixture.history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000
      );
      insert invoice;
      insert new GlJournal__c(
        Invoice__c = invoice.Id,
        Amount__c = 1000,
        IdempotencyKey__c = 'CONF-TEXT-MANUAL',
        DebitSlotKey__c = 'CASH',
        CreditSlotKey__c = 'REV',
        PostingDate__c = Date.newInstance(2026, 6, 1)
      );
      GlJournal__c journal = [
        SELECT ConfirmationText__c
        FROM GlJournal__c
        WHERE IdempotencyKey__c = 'CONF-TEXT-MANUAL'
      ];
      System.assertEquals(
        '',
        journal.ConfirmationText__c,
        'Accounting 第9.1.1節: 請求明細参照が空なら全文空'
      );
    }
  }

  @IsTest
  static void applyBillingAccountContent_copiesDeliveryMethod() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createOrderedFixture();
      InvoiceCanonicalService.rebuildForHistories(
        new Set<Id>{ fixture.history.Id }
      );
      Invoice__c invoice = [
        SELECT Id, BillingAccountSnapShot__c
        FROM Invoice__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      BillingAccount__c account = [
        SELECT Id
        FROM BillingAccount__c
        WHERE Id = :invoice.BillingAccountSnapShot__c
      ];
      account.InvoiceDeliveryMethod__c = InvoiceDeliveryMethodService.POST;
      update account;
      InvoiceCanonicalService.testHasEditPreviewPermission = true;
      Test.startTest();
      InvoiceCanonicalService.applyBillingAccountContent(invoice.Id);
      Test.stopTest();
      Invoice__c updated = [
        SELECT InvoiceDeliveryMethodSnapShot__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        InvoiceDeliveryMethodService.POST,
        updated.InvoiceDeliveryMethodSnapShot__c,
        'Core 第7.8節: 反映は届け方スナップショットを宛名と同じ集合で載せ直す'
      );
    }
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  private class Fixture {
    ContractHistory__c history;
  }

  private static Fixture createOrderedFixture() {
    ContractTestDataFactory.ensureOrgAccountingPolicy();
    Account account = ContractTestDataFactory.insertAccount(
      'Canonical Invoice Account'
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
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
