@IsTest
private class InvoicePaymentAllocationServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void assertLines_rejectsEmpty() {
    Boolean thrown = false;
    try {
      InvoicePaymentAllocationService.assertLines(
        UserInfo.getUserId(),
        1100,
        new List<InvoicePaymentAllocationService.AllocationLine>()
      );
    } catch (Exception ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('明細別割当が1件以上必要'),
        'Core 第8.6節: Invoice目的は明細別割当が1件以上必須'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void assertLines_rejectsTotalMismatch() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceLine__c line = insertLineOnNewInvoice();
      InvoicePaymentAllocationService.AllocationLine allocation = new InvoicePaymentAllocationService.AllocationLine();
      allocation.invoiceLineId = line.Id;
      allocation.amount = 500;
      Boolean thrown = false;
      try {
        InvoicePaymentAllocationService.assertLines(
          line.Invoice__c,
          1100,
          new List<InvoicePaymentAllocationService.AllocationLine>{ allocation }
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('合計は親の金額と一致'),
          'Core 第8.6節: 割当合計は親Amountと完全一致'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void assertLines_rejectsDuplicateLine() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceLine__c line = insertLineOnNewInvoice();
      InvoicePaymentAllocationService.AllocationLine first = new InvoicePaymentAllocationService.AllocationLine();
      first.invoiceLineId = line.Id;
      first.amount = 600;
      InvoicePaymentAllocationService.AllocationLine second = new InvoicePaymentAllocationService.AllocationLine();
      second.invoiceLineId = line.Id;
      second.amount = 500;
      Boolean thrown = false;
      try {
        InvoicePaymentAllocationService.assertLines(
          line.Invoice__c,
          1100,
          new List<InvoicePaymentAllocationService.AllocationLine>{
            first,
            second
          }
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('同じ請求明細へ重複して割り当てられません'),
          'Core 第8.6節: 同じ請求明細を重複させない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void assertLines_rejectsForeignInvoiceLine() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceLine__c ownLine = insertLineOnNewInvoice();
      InvoiceLine__c foreignLine = insertLineOnNewInvoice();
      InvoicePaymentAllocationService.AllocationLine allocation = new InvoicePaymentAllocationService.AllocationLine();
      allocation.invoiceLineId = foreignLine.Id;
      allocation.amount = 1100;
      Boolean thrown = false;
      try {
        InvoicePaymentAllocationService.assertLines(
          ownLine.Invoice__c,
          1100,
          new List<InvoicePaymentAllocationService.AllocationLine>{ allocation }
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('親と同じ請求書の請求明細だけ'),
          'Core 第8.6節: 割当先は親と同じ請求書の明細だけ'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void proposeLines_rejectsInvoiceWithoutLines() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertInvoiceWithoutLine();
      Boolean thrown = false;
      try {
        InvoicePaymentAllocationService.proposeLines(invoice.Id, 1100);
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('明細別割当が1件以上必要'),
          'Core 第8.6節: 請求明細が無いInvoice目的は割当を作れない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void proposeLines_usesOpenInclusiveRatioAndSignedRemainder() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TwoLineInvoice fixture = insertTwoLineInvoice(1000, 0, 1000, 100);
      List<InvoicePaymentAllocationService.AllocationLine> proposed =
        InvoicePaymentAllocationService.proposeLines(fixture.invoice.Id, 700);
      Map<Id, Decimal> byLine = new Map<Id, Decimal>();
      for (InvoicePaymentAllocationService.AllocationLine row : proposed) {
        byLine.put(row.invoiceLineId, row.amount);
      }
      System.assertEquals(
        333,
        byLine.get(fixture.firstLine.Id),
        'Core 第11.9節: 未処理税込の比例を0方向へ整数化する'
      );
      System.assertEquals(
        367,
        byLine.get(fixture.secondLine.Id),
        'Core 第11.9節: 端数は符号付き最大剰余'
      );
    }
  }

  @IsTest
  static void proposeLines_negativeParent_assignsSignedRemainderToLargerFraction() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TwoLineInvoice fixture = insertTwoLineInvoice(1000, 0, 1000, 100);
      List<InvoicePaymentAllocationService.AllocationLine> proposed =
        InvoicePaymentAllocationService.proposeLines(fixture.invoice.Id, -700);
      Map<Id, Decimal> byLine = new Map<Id, Decimal>();
      for (InvoicePaymentAllocationService.AllocationLine row : proposed) {
        byLine.put(row.invoiceLineId, row.amount);
      }
      System.assertEquals(
        -334,
        byLine.get(fixture.firstLine.Id),
        'Core 第11.9節: 差が負なら小数剰余の大きい順に負方向へ配る'
      );
      System.assertEquals(
        -366,
        byLine.get(fixture.secondLine.Id),
        'Core 第11.9節: 符号付き剰余は絶対値順ではない'
      );
    }
  }

  @IsTest
  static void proposeLines_finalAssignsEachRemaining() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TwoLineInvoice fixture = insertTwoLineInvoice(1000, 0, 1000, 100);
      List<InvoicePaymentAllocationService.AllocationLine> proposed =
        InvoicePaymentAllocationService.proposeLines(fixture.invoice.Id, 2100);
      Map<Id, Decimal> byLine = new Map<Id, Decimal>();
      for (InvoicePaymentAllocationService.AllocationLine row : proposed) {
        byLine.put(row.invoiceLineId, row.amount);
      }
      System.assertEquals(
        1000,
        byLine.get(fixture.firstLine.Id),
        'Core 第8.6節: 最終決済は各明細の未処理税込をそのまま載せる'
      );
      System.assertEquals(1100, byLine.get(fixture.secondLine.Id));
    }
  }

  @IsTest
  static void assertLines_rejectsOppositeSignRemaining() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TwoLineInvoice fixture = insertTwoLineInvoice(1000, 0, 1000, 100);
      InvoicePaymentAllocationService.AllocationLine first = new InvoicePaymentAllocationService.AllocationLine();
      first.invoiceLineId = fixture.firstLine.Id;
      first.amount = -50;
      InvoicePaymentAllocationService.AllocationLine second = new InvoicePaymentAllocationService.AllocationLine();
      second.invoiceLineId = fixture.secondLine.Id;
      second.amount = 50;
      Boolean thrown = false;
      try {
        InvoicePaymentAllocationService.assertLines(
          fixture.invoice.Id,
          0,
          new List<InvoicePaymentAllocationService.AllocationLine>{ first, second }
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('処理可能残額以内'),
          'Core 第8.6節: 残額と異符号の割当は処理可能残額を超える'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void assertLines_rejectsOverRemaining() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TwoLineInvoice fixture = insertTwoLineInvoice(1000, 0, 1000, 100);
      InvoicePaymentAllocationService.AllocationLine first = new InvoicePaymentAllocationService.AllocationLine();
      first.invoiceLineId = fixture.firstLine.Id;
      first.amount = 1001;
      InvoicePaymentAllocationService.AllocationLine second = new InvoicePaymentAllocationService.AllocationLine();
      second.invoiceLineId = fixture.secondLine.Id;
      second.amount = -1;
      Boolean thrown = false;
      try {
        InvoicePaymentAllocationService.assertLines(
          fixture.invoice.Id,
          1000,
          new List<InvoicePaymentAllocationService.AllocationLine>{ first, second }
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('処理可能残額以内'),
          'Core 第8.6節: 明細の処理可能残額を超えた割当を拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void assertLines_rejectsFinalWhenLineRemainingLeft() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      TwoLineInvoice fixture = insertTwoLineInvoice(1000, 0, 200, 0, 1100);
      InvoicePaymentAllocationService.AllocationLine first = new InvoicePaymentAllocationService.AllocationLine();
      first.invoiceLineId = fixture.firstLine.Id;
      first.amount = 900;
      InvoicePaymentAllocationService.AllocationLine second = new InvoicePaymentAllocationService.AllocationLine();
      second.invoiceLineId = fixture.secondLine.Id;
      second.amount = 200;
      Boolean thrown = false;
      try {
        InvoicePaymentAllocationService.assertLines(
          fixture.invoice.Id,
          1100,
          new List<InvoicePaymentAllocationService.AllocationLine>{ first, second }
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('全明細の未処理税込残額を0'),
          'Core 第8.6節: ヘッダ完了なのに明細残が残る保存を拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void allocate_writesInvoiceLinesAndRejectsNonInvoice() {
    Exception nullPayment = null;
    try {
      InvoicePaymentAllocationService.allocate(
        null,
        new List<InvoicePaymentAllocationService.AllocationLine>()
      );
    } catch (Exception ex) {
      nullPayment = ex;
    }
    System.assert(
      nullPayment != null &&
      nullPayment.getMessage().contains('請求入出金が指定されていません'),
      'Core 第8.1節: 割当先の請求入出金は必須'
    );

    Exception proposeBlank = null;
    try {
      InvoicePaymentAllocationService.proposeLines(null, 1100);
    } catch (Exception ex) {
      proposeBlank = ex;
    }
    System.assert(
      proposeBlank != null &&
      proposeBlank.getMessage().contains('明細別割当の初期値を作れません'),
      'Core 第8.6節: 親金額0や請求書空では初期配分できない'
    );

    InvoicePaymentAllocationService.AllocationLine fraction = new InvoicePaymentAllocationService.AllocationLine();
    fraction.invoiceLineId = UserInfo.getUserId();
    fraction.amount = 1.5;
    Exception fractionEx = null;
    try {
      InvoicePaymentAllocationService.assertLines(
        UserInfo.getUserId(),
        1.5,
        new List<InvoicePaymentAllocationService.AllocationLine>{ fraction }
      );
    } catch (Exception ex) {
      fractionEx = ex;
    }
    System.assert(
      fractionEx != null &&
      fractionEx.getMessage().contains('明細別割当の金額は整数にしてください'),
      'Core 第8.6節: 割当額は符号付き整数'
    );

    InvoicePaymentAllocationService.reverseAllocations(
      UserInfo.getUserId(),
      UserInfo.getUserId()
    );

    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceLine__c line = insertLineOnNewInvoice();
      InvoicePayment__c payment = new InvoicePayment__c(
        Invoice__c = line.Invoice__c,
        Amount__c = 1000,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.today()
      );
      Boolean previousWrite = InvoicePaymentService.allowLifecycleWrite;
      InvoicePaymentService.allowLifecycleWrite = true;
      try {
        insert payment;
      } finally {
        InvoicePaymentService.allowLifecycleWrite = previousWrite;
      }
      InvoicePaymentAllocationService.AllocationLine row = new InvoicePaymentAllocationService.AllocationLine();
      row.invoiceLineId = line.Id;
      row.amount = 1000;
      InvoicePaymentAllocationService.allocate(
        payment.Id,
        new List<InvoicePaymentAllocationService.AllocationLine>{ row }
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM InvoicePaymentAllocation__c
          WHERE InvoicePayment__c = :payment.Id AND Amount__c = 1000
        ],
        'Core 第8.6節: Invoice目的は明細別割当を保持する'
      );

      InvoicePayment__c reversal = new InvoicePayment__c(
        Invoice__c = line.Invoice__c,
        Amount__c = -1000,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.today()
      );
      previousWrite = InvoicePaymentService.allowLifecycleWrite;
      InvoicePaymentService.allowLifecycleWrite = true;
      try {
        insert reversal;
      } finally {
        InvoicePaymentService.allowLifecycleWrite = previousWrite;
      }
      InvoicePaymentAllocationService.reverseAllocations(payment.Id, reversal.Id);
      InvoicePaymentAllocation__c reversed = [
        SELECT Amount__c
        FROM InvoicePaymentAllocation__c
        WHERE InvoicePayment__c = :reversal.Id
      ];
      System.assertEquals(
        -1000,
        reversed.Amount__c,
        'Core 第8.5節: 取消割当は元割当の反対符号であり再按分しない'
      );

      InvoicePayment__c nonInvoice = new InvoicePayment__c(
        Invoice__c = line.Invoice__c,
        Amount__c = 50,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_NON_INVOICE,
        PaymentDate__c = Date.today()
      );
      previousWrite = InvoicePaymentService.allowLifecycleWrite;
      InvoicePaymentService.allowLifecycleWrite = true;
      try {
        insert nonInvoice;
      } finally {
        InvoicePaymentService.allowLifecycleWrite = previousWrite;
      }
      Exception nonInvoiceEx = null;
      try {
        InvoicePaymentAllocationService.allocate(
          nonInvoice.Id,
          new List<InvoicePaymentAllocationService.AllocationLine>{ row }
        );
      } catch (Exception ex) {
        nonInvoiceEx = ex;
      }
      System.assert(
        nonInvoiceEx != null &&
        nonInvoiceEx.getMessage().contains('請求金額以外の入出金に明細別割当は持てません'),
        'Core 第8.6節: Purpose=NonInvoiceは明細別割当を持たない'
      );
    }
  }

  @IsTest
  static void guardHistoricalAmounts_rejectsDirectUserUpdate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceLine__c line = insertLineOnNewInvoice();
      InvoicePayment__c payment = new InvoicePayment__c(
        Invoice__c = line.Invoice__c,
        Amount__c = 1100,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.today()
      );
      Boolean previousWrite = InvoicePaymentService.allowLifecycleWrite;
      InvoicePaymentService.allowLifecycleWrite = true;
      try {
        insert payment;
      } finally {
        InvoicePaymentService.allowLifecycleWrite = previousWrite;
      }
      InvoicePaymentAllocation__c allocation = new InvoicePaymentAllocation__c(
        InvoicePayment__c = payment.Id,
        InvoiceLine__c = line.Id,
        Amount__c = 1100,
        HistoricalUacAmount__c = 0,
        HistoricalSpAmount__c = 0
      );
      insert allocation;
      allocation.HistoricalUacAmount__c = 1100;
      Boolean thrown = false;
      try {
        update allocation;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('直接編集できません'),
          'Core 第8.6節、Accounting 第4.4節: 利用者が過去日UAC／SP振替額を直接編集できない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void guardHistoricalAmounts_allowsGoalWrite() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceLine__c line = insertLineOnNewInvoice();
      InvoicePayment__c payment = new InvoicePayment__c(
        Invoice__c = line.Invoice__c,
        Amount__c = 1100,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.today()
      );
      Boolean previousWrite = InvoicePaymentService.allowLifecycleWrite;
      InvoicePaymentService.allowLifecycleWrite = true;
      try {
        insert payment;
      } finally {
        InvoicePaymentService.allowLifecycleWrite = previousWrite;
      }
      InvoicePaymentAllocation__c allocation = new InvoicePaymentAllocation__c(
        InvoicePayment__c = payment.Id,
        InvoiceLine__c = line.Id,
        Amount__c = 1100,
        HistoricalUacAmount__c = 0,
        HistoricalSpAmount__c = 0
      );
      insert allocation;
      allocation.HistoricalUacAmount__c = 1100;
      InvoicePaymentAllocationService.allowHistoricalAmountWrite = true;
      try {
        update allocation;
      } finally {
        InvoicePaymentAllocationService.allowHistoricalAmountWrite = false;
      }
      InvoicePaymentAllocation__c written = [
        SELECT HistoricalUacAmount__c
        FROM InvoicePaymentAllocation__c
        WHERE Id = :allocation.Id
      ];
      System.assertEquals(
        1100,
        written.HistoricalUacAmount__c,
        'Core 第8.6節: Goal書込は許可する'
      );
    }
  }

  @IsTest
  static void irregularCreate_on104DirectInsert() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoicePaymentAllocation__c allocation = newAllocationRow();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        insert allocation;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'IrregularCreate'
            AND TargetObject__c = 'InvoicePaymentAllocation__c'
            AND TargetRecordId__c = :String.valueOf(allocation.Id)
        ],
        '共通基盤第12章・第3.6節: 104の割当新規作成はIrregularCreateを1件書く'
      );
    }
  }

  @IsTest
  static void irregularUpdate_on104DirectUpdate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoicePaymentAllocation__c allocation = newAllocationRow();
      insert allocation;
      allocation.Amount__c = 1000;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        update allocation;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'IrregularUpdate'
            AND TargetObject__c = 'InvoicePaymentAllocation__c'
            AND TargetRecordId__c = :String.valueOf(allocation.Id)
        ],
        '共通基盤第12章・第3.6節: 104の割当項目更新はIrregularUpdateを1件書く'
      );
    }
  }

  @IsTest
  static void irregularDelete_on104DirectDelete() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoicePaymentAllocation__c allocation = newAllocationRow();
      insert allocation;
      Id allocationId = allocation.Id;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        delete allocation;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'IrregularDelete'
            AND TargetObject__c = 'InvoicePaymentAllocation__c'
            AND TargetRecordId__c = :String.valueOf(allocationId)
        ],
        '共通基盤第12章・第3.6節: 104の割当削除はIrregularDeleteを1件書く'
      );
    }
  }

  @IsTest
  static void regularLifecycle_doesNotWriteIrregularCreate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoicePaymentAllocation__c allocation = newAllocationRow();
      Boolean previousWrite = InvoicePaymentService.allowLifecycleWrite;
      InvoicePaymentService.allowLifecycleWrite = true;
      try {
        ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
          ContractPermissionUtil.MIGRATE_ALL => true
        };
        try {
          insert allocation;
        } finally {
          ContractPermissionUtil.testOverrides = null;
        }
      } finally {
        InvoicePaymentService.allowLifecycleWrite = previousWrite;
      }
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'IrregularCreate'
            AND TargetObject__c = 'InvoicePaymentAllocation__c'
        ],
        '共通基盤第12章: 正規の入金登録経路の割当作成はIrregularCreateを書かない'
      );
    }
  }

  @IsTest
  static void goalHistoricalWrite_doesNotWriteIrregularUpdate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoicePaymentAllocation__c allocation = newAllocationRow();
      insert allocation;
      allocation.HistoricalUacAmount__c = 1100;
      InvoicePaymentAllocationService.allowHistoricalAmountWrite = true;
      try {
        ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
          ContractPermissionUtil.MIGRATE_ALL => true
        };
        try {
          update allocation;
        } finally {
          ContractPermissionUtil.testOverrides = null;
        }
      } finally {
        InvoicePaymentAllocationService.allowHistoricalAmountWrite = false;
      }
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'IrregularUpdate'
            AND TargetObject__c = 'InvoicePaymentAllocation__c'
        ],
        '共通基盤第12章: Goalの過去日額書込はIrregularUpdateを書かない'
      );
    }
  }

  private static InvoicePaymentAllocation__c newAllocationRow() {
    InvoiceLine__c line = insertLineOnNewInvoice();
    InvoicePayment__c payment = new InvoicePayment__c(
      Invoice__c = line.Invoice__c,
      Amount__c = 1100,
      PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
      PaymentDate__c = Date.today()
    );
    Boolean previousWrite = InvoicePaymentService.allowLifecycleWrite;
    InvoicePaymentService.allowLifecycleWrite = true;
    try {
      insert payment;
    } finally {
      InvoicePaymentService.allowLifecycleWrite = previousWrite;
    }
    return new InvoicePaymentAllocation__c(
      InvoicePayment__c = payment.Id,
      InvoiceLine__c = line.Id,
      Amount__c = 1100,
      HistoricalUacAmount__c = 0,
      HistoricalSpAmount__c = 0
    );
  }

  private static TwoLineInvoice insertTwoLineInvoice(
    Decimal firstAmount,
    Decimal firstTax,
    Decimal secondAmount,
    Decimal secondTax
  ) {
    return insertTwoLineInvoice(
      firstAmount,
      firstTax,
      secondAmount,
      secondTax,
      firstAmount + firstTax + secondAmount + secondTax
    );
  }

  private static TwoLineInvoice insertTwoLineInvoice(
    Decimal firstAmount,
    Decimal firstTax,
    Decimal secondAmount,
    Decimal secondTax,
    Decimal taxInclusive
  ) {
    Invoice__c invoice = insertInvoiceWithoutLine(
      taxInclusive,
      0,
      taxInclusive
    );
    InvoiceLine__c first = new InvoiceLine__c(
      Invoice__c = invoice.Id,
      ProductName__c = 'Alloc Line A',
      Amount__c = firstAmount,
      AllocatedTaxAmount__c = firstTax,
      Quantity__c = 1,
      UnitPrice__c = firstAmount
    );
    ContractTestDataFactory.applyRequiredFields(first);
    insert first;
    InvoiceLine__c second = new InvoiceLine__c(
      Invoice__c = invoice.Id,
      ProductName__c = 'Alloc Line B',
      Amount__c = secondAmount,
      AllocatedTaxAmount__c = secondTax,
      Quantity__c = 1,
      UnitPrice__c = secondAmount
    );
    ContractTestDataFactory.applyRequiredFields(second);
    insert second;
    TwoLineInvoice fixture = new TwoLineInvoice();
    fixture.invoice = invoice;
    fixture.firstLine = first;
    fixture.secondLine = second;
    return fixture;
  }

  private class TwoLineInvoice {
    Invoice__c invoice;
    InvoiceLine__c firstLine;
    InvoiceLine__c secondLine;
  }

  private static InvoiceLine__c insertLineOnNewInvoice() {
    Invoice__c invoice = insertInvoiceWithoutLine();
    InvoiceLine__c line = new InvoiceLine__c(
      Invoice__c = invoice.Id,
      ProductName__c = 'Alloc Line',
      Amount__c = 1000,
      Quantity__c = 1,
      UnitPrice__c = 1000
    );
    ContractTestDataFactory.applyRequiredFields(line);
    insert line;
    return line;
  }

  private static Invoice__c insertInvoiceWithoutLine() {
    return insertInvoiceWithoutLine(1000, 100, 1100);
  }

  private static Invoice__c insertInvoiceWithoutLine(
    Decimal amount,
    Decimal tax,
    Decimal taxInclusive
  ) {
    Account account = ContractTestDataFactory.insertAccount(
      'Alloc ' + String.valueOf(Crypto.getRandomInteger())
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'alloc@example.com',
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
      'Alloc Opp'
    );
    ContractService__c service = new ContractService__c(
      Name = 'Alloc Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Alloc History',
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
      Amount__c = amount,
      TaxAmount__c = tax,
      BillingAccountSnapShot__c = billingAccount.Id,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      SystemIntegrationDate__c = Date.today()
    );
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    return invoice;
  }
}
