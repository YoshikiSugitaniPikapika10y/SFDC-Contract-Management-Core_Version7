@IsTest
private class ConditionEvaluationServiceTest {
  @IsTest
  static void evaluate_unspecifiedSetIsTrue() {
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluate(
        null,
        new ConditionEvaluationService.Context()
      ),
      'Accounting 第4.7節: 条件未指定は常に成立'
    );
  }

  @IsTest
  static void evaluate_payInvoiceCurrentUsesPaymentDate() {
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoice = new Invoice__c(
      InvoiceDate__c = Date.newInstance(2026, 6, 1)
    );
    context.invoicePayment = new InvoicePayment__c(
      PaymentPurpose__c = 'Invoice',
      PaymentDate__c = Date.newInstance(2026, 6, 15)
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.PAY_INVOICE_CURRENT,
        context
      ),
      'Accounting 第4.7節: PAY_INVOICE_CURRENTは入出金日が請求日以後'
    );
    context.invoicePayment.PaymentDate__c = Date.newInstance(2026, 5, 1);
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.PAY_INVOICE_CURRENT,
        context
      ),
      'Accounting 第4.7節: 入出金日が請求日より前ならPAY_INVOICE_CURRENTは不成立'
    );
  }

  @IsTest
  static void evaluateTenant_rejectsEmptySet() {
    GlConditionSet__c conditionSet = new GlConditionSet__c(
      Name = 'Empty Eval Set',
      EvaluationContext__c = 'InvoiceLine',
      Description__c = '0件'
    );
    insert conditionSet;
    Boolean thrown = false;
    try {
      ConditionEvaluationService.evaluateTenant(
        conditionSet.Id,
        new ConditionEvaluationService.Context()
      );
    } catch (ConditionEvaluationService.EvaluationException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('0件'),
        'Accounting 第4.7節: 条件0件セットの参照禁止'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void validateConditionLogic_requiresParensForMixedJunctions() {
    System.assertEquals(
      null,
      ConditionEvaluationService.validateConditionLogic(
        '1 AND (2 OR 3)',
        new Set<Decimal>{ 1, 2, 3 }
      )
    );
    System.assert(
      ConditionEvaluationService.validateConditionLogic(
          '1 AND 2 OR 3',
          new Set<Decimal>{ 1, 2, 3 }
        )
        .contains('括弧'),
      'Accounting 第4.7節: ANDとORの混在時は括弧が必要'
    );
  }

  @IsTest
  static void evaluate_payNonInvoicePositiveUsesAmountSign() {
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoicePayment = new InvoicePayment__c(
      PaymentPurpose__c = 'NonInvoice',
      Amount__c = 100
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.PAY_NON_INVOICE_POSITIVE,
        context
      ),
      'Accounting 第4.7節: PAY_NON_INVOICE_POSITIVE は Purpose=NonInvoice かつ Amount>0'
    );
    context.invoicePayment.Amount__c = -1;
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.PAY_NON_INVOICE_POSITIVE,
        context
      ),
      'Accounting 第4.7節: Amount<0 なら PAY_NON_INVOICE_POSITIVE は不成立'
    );
  }

  @IsTest
  static void evaluateTenant_unspecifiedSetIsTrue() {
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(
        null,
        new ConditionEvaluationService.Context()
      ),
      'Accounting 第4.7節: 条件未指定は常に成立'
    );
  }

  @IsTest
  static void evaluateTenant_equalsFixedValue() {
    GlConditionSet__c conditionSet = new GlConditionSet__c(
      Name = 'Eval Equals Set',
      EvaluationContext__c = 'Invoice',
      Description__c = '税抜一致'
    );
    insert conditionSet;
    insert new GlConditionRule__c(
      ConditionSet__c = conditionSet.Id,
      Sequence__c = 1,
      TargetObject__c = 'Invoice__c',
      TargetField__c = 'Amount__c',
      Operator__c = 'Equals',
      CompareType__c = 'FixedValue',
      CompareValue__c = '1000'
    );
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoice = new Invoice__c(Amount__c = 1000);
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(conditionSet.Id, context),
      'Accounting 第4.7節: 固定値比較の等しい'
    );
    context.invoice.Amount__c = 1;
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(conditionSet.Id, context)
    );
  }

  @IsTest
  static void evaluateTenant_readsRelatedAccountAndContractProduct() {
    GlConditionSet__c conditionSet = new GlConditionSet__c(
      Name = 'Eval Related Set',
      EvaluationContext__c = 'InvoiceLine',
      Description__c = '関連11種'
    );
    insert conditionSet;
    insert new List<GlConditionRule__c>{
      new GlConditionRule__c(
        ConditionSet__c = conditionSet.Id,
        Sequence__c = 1,
        TargetObject__c = 'Account',
        TargetField__c = 'Name',
        Operator__c = 'Equals',
        CompareType__c = 'FixedValue',
        CompareValue__c = '関連取引先'
      ),
      new GlConditionRule__c(
        ConditionSet__c = conditionSet.Id,
        Sequence__c = 2,
        TargetObject__c = 'ContractProduct__c',
        TargetField__c = 'Description__c',
        Operator__c = 'IsNotNull'
      )
    };
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(conditionSet.Id, context),
      'Accounting 第4.7節: Contextに関連が無ければ空として評価する'
    );
    context.account = new Account(Name = '関連取引先');
    context.contractProduct = new ContractProduct__c(
      Description__c = '関連契約商品'
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(conditionSet.Id, context),
      'Accounting 第4.7節: 関連レコードの項目を評価する'
    );
  }

  @IsTest
  static void evaluateTenant_appliesOrLogicFromConditionLogic() {
    GlConditionSet__c conditionSet = new GlConditionSet__c(
      Name = 'Eval Or Set',
      EvaluationContext__c = 'Invoice',
      Description__c = 'OR'
    );
    insert conditionSet;
    insert new List<GlConditionRule__c>{
      new GlConditionRule__c(
        ConditionSet__c = conditionSet.Id,
        Sequence__c = 1,
        TargetObject__c = 'Account',
        TargetField__c = 'Name',
        Operator__c = 'Equals',
        CompareType__c = 'FixedValue',
        CompareValue__c = '一致しない'
      ),
      new GlConditionRule__c(
        ConditionSet__c = conditionSet.Id,
        Sequence__c = 2,
        TargetObject__c = 'Invoice__c',
        TargetField__c = 'Memo__c',
        Operator__c = 'IsNotNull'
      )
    };
    conditionSet.ConditionLogic__c = '1 OR 2';
    update conditionSet;
    GlConditionSet__c loadedSet = [
      SELECT Id, ConditionLogic__c
      FROM GlConditionSet__c
      WHERE Id = :conditionSet.Id
    ];
    List<GlConditionRule__c> loadedRules = [
      SELECT Sequence__c, TargetObject__c, TargetField__c, Operator__c
      FROM GlConditionRule__c
      WHERE ConditionSet__c = :loadedSet.Id
      ORDER BY Sequence__c
    ];
    System.assertEquals(
      '1 OR 2',
      loadedSet.ConditionLogic__c,
      'Accounting 第4.7節: 条件ロジックは保存する'
    );
    System.assertEquals(2, loadedRules.size());
    System.assertEquals(1, loadedRules[0].Sequence__c);
    System.assertEquals(2, loadedRules[1].Sequence__c);
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoice = new Invoice__c(Memo__c = 'あり');
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(loadedSet.Id, context),
      'Accounting 第4.7節: 条件ロジックの OR を評価する'
    );
  }

  @IsTest
  static void evaluateTenant_matchesPaymentPurposeApiValue() {
    GlConditionSet__c conditionSet = new GlConditionSet__c(
      Name = 'Eval Purpose Set',
      EvaluationContext__c = 'InvoicePayment',
      Description__c = '目的API'
    );
    insert conditionSet;
    insert new GlConditionRule__c(
      ConditionSet__c = conditionSet.Id,
      Sequence__c = 1,
      TargetObject__c = 'InvoicePayment__c',
      TargetField__c = 'PaymentPurpose__c',
      Operator__c = 'Equals',
      CompareType__c = 'FixedValue',
      CompareValue__c = '請求金額'
    );
    System.assertEquals(
      'Invoice',
      [
        SELECT CompareValue__c
        FROM GlConditionRule__c
        WHERE ConditionSet__c = :conditionSet.Id
      ]
      .CompareValue__c,
      'Accounting 第4.7節: 保存値はAPI値'
    );
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoicePayment = new InvoicePayment__c(
      PaymentPurpose__c = 'Invoice'
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(conditionSet.Id, context),
      'Accounting 第4.7節: get()のAPI値と文字列一致する'
    );
    context.invoicePayment.PaymentPurpose__c = 'NonInvoice';
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(conditionSet.Id, context),
      'Accounting 第4.7節: API値が違えば不成立'
    );
  }

  @IsTest
  static void validateRule_requiresAggregateForInvoiceLineOnInvoiceContext() {
    GlConditionRule__c rule = new GlConditionRule__c(
      TargetObject__c = 'InvoiceLine__c',
      TargetField__c = 'Amount__c',
      Operator__c = 'Equals',
      CompareType__c = 'FixedValue',
      CompareValue__c = '0'
    );
    System.assert(
      ConditionEvaluationService.validateRule(rule, 'Invoice').contains('集約'),
      'Accounting 第4.7節: 子対象では集約が必要'
    );
  }

  @IsTest
  static void validateRule_isNullRejectsCompareFields() {
    GlConditionRule__c rule = new GlConditionRule__c(
      TargetObject__c = 'Invoice__c',
      TargetField__c = 'Memo__c',
      Operator__c = 'IsNull',
      CompareType__c = 'FixedValue',
      CompareValue__c = 'x'
    );
    System.assert(
      ConditionEvaluationService.validateRule(rule, 'Invoice')
        .contains('空判定'),
      'Accounting 第4.7節: 空判定では比較関連項目を空にする'
    );
  }

  @IsTest
  static void evaluate_payNonInvoiceNegativeUsesAmountSign() {
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoicePayment = new InvoicePayment__c(
      PaymentPurpose__c = 'NonInvoice',
      Amount__c = -50
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.PAY_NON_INVOICE_NEGATIVE,
        context
      ),
      'Accounting 第4.7節: PAY_NON_INVOICE_NEGATIVE は Purpose=NonInvoice かつ Amount<0'
    );
    context.invoicePayment.Amount__c = 1;
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.PAY_NON_INVOICE_NEGATIVE,
        context
      ),
      'Accounting 第4.7節: Amount>0 なら PAY_NON_INVOICE_NEGATIVE は不成立'
    );
  }

  @IsTest
  static void evaluate_historicalInvoiceSetsUsePaymentDateAndAllocation() {
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoice = new Invoice__c(
      InvoiceDate__c = Date.newInstance(2026, 6, 1)
    );
    context.invoicePayment = new InvoicePayment__c(
      PaymentPurpose__c = 'Invoice',
      PaymentDate__c = Date.newInstance(2026, 5, 1)
    );
    context.allocation = new InvoicePaymentAllocation__c(Amount__c = 10);
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_POSITIVE_CASH,
        context
      ),
      'Accounting 第4.7節: 入出金日が請求日より前かつ明細別割当額>0'
    );
    context.allocation.Amount__c = -10;
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_NEGATIVE_CASH,
        context
      ),
      'Accounting 第4.7節: 入出金日が請求日より前かつ明細別割当額<0'
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_UAC_TRANSFER,
        context
      ),
      'Accounting 第4.7節: PAY_INVOICE_HISTORICAL_UAC_TRANSFER は入出金日が請求日より前'
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_SP_TRANSFER,
        context
      ),
      'Accounting 第4.7節: PAY_INVOICE_HISTORICAL_SP_TRANSFER は入出金日が請求日より前'
    );
    context.invoicePayment.PaymentDate__c = Date.newInstance(2026, 6, 15);
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_UAC_TRANSFER,
        context
      ),
      'Accounting 第4.7節: 入出金日が請求日以後なら過去日条件は不成立'
    );
  }

  @IsTest
  static void evaluateTenant_fieldCompareAndInvoiceLineTarget() {
    GlConditionSet__c conditionSet = new GlConditionSet__c(
      Name = 'Eval Field Set',
      EvaluationContext__c = 'Invoice',
      Description__c = '項目比較'
    );
    insert conditionSet;
    insert new GlConditionRule__c(
      ConditionSet__c = conditionSet.Id,
      Sequence__c = 1,
      TargetObject__c = 'InvoiceLine__c',
      TargetField__c = 'Amount__c',
      Operator__c = 'Equals',
      CompareType__c = 'Field',
      CompareObject__c = 'Invoice__c',
      CompareField__c = 'Amount__c',
      Aggregate__c = 'Any'
    );
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoice = new Invoice__c(Amount__c = 200);
    context.invoiceLine = new InvoiceLine__c(Amount__c = 200);
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(conditionSet.Id, context),
      'Accounting 第4.7節: 項目比較は対象項目と比較対象項目'
    );
    context.invoiceLine.Amount__c = 1;
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(conditionSet.Id, context)
    );
  }

  @IsTest
  static void evaluateTenant_invoiceLineAllAndAnyOverInvoiceLines() {
    GlConditionSet__c allSet = new GlConditionSet__c(
      Name = 'Eval All Lines',
      EvaluationContext__c = 'Invoice',
      Description__c = 'すべて'
    );
    insert allSet;
    insert new GlConditionRule__c(
      ConditionSet__c = allSet.Id,
      Sequence__c = 1,
      Aggregate__c = 'All',
      TargetObject__c = 'InvoiceLine__c',
      TargetField__c = 'Amount__c',
      Operator__c = 'Equals',
      CompareType__c = 'FixedValue',
      CompareValue__c = '1000'
    );
    GlConditionSet__c anySet = new GlConditionSet__c(
      Name = 'Eval Any Lines',
      EvaluationContext__c = 'Invoice',
      Description__c = 'いずれか'
    );
    insert anySet;
    insert new GlConditionRule__c(
      ConditionSet__c = anySet.Id,
      Sequence__c = 1,
      Aggregate__c = 'Any',
      TargetObject__c = 'InvoiceLine__c',
      TargetField__c = 'Amount__c',
      Operator__c = 'Equals',
      CompareType__c = 'FixedValue',
      CompareValue__c = '1000'
    );
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoice = new Invoice__c(Amount__c = 2000);
    context.invoiceLine = new InvoiceLine__c(Amount__c = 1000);
    context.invoiceLines = new List<InvoiceLine__c>{
      new InvoiceLine__c(Amount__c = 1000),
      new InvoiceLine__c(Amount__c = 1)
    };
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(allSet.Id, context),
      'Accounting 第4.7節: すべては請求明細の全件が一致する'
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(anySet.Id, context),
      'Accounting 第4.7節: いずれかは請求明細の1件が一致すれば成立'
    );
    context.invoiceLines[1].Amount__c = 1000;
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(allSet.Id, context),
      'Accounting 第4.7節: すべては全明細が一致するとき成立'
    );
    context.invoiceLines[0].Amount__c = 1;
    context.invoiceLines[1].Amount__c = 1;
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(anySet.Id, context),
      'Accounting 第4.7節: いずれかも全明細不一致なら不成立'
    );
  }

  @IsTest
  static void evaluateTenant_textContainsAndNullOperators() {
    GlConditionSet__c conditionSet = new GlConditionSet__c(
      Name = 'Eval Text Set',
      EvaluationContext__c = 'Invoice',
      Description__c = '含むと空'
    );
    insert conditionSet;
    insert new GlConditionRule__c(
      ConditionSet__c = conditionSet.Id,
      Sequence__c = 1,
      TargetObject__c = 'Invoice__c',
      TargetField__c = 'Memo__c',
      Operator__c = 'Contains',
      CompareType__c = 'FixedValue',
      CompareValue__c = '税'
    );
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoice = new Invoice__c(Memo__c = '消費税');
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(conditionSet.Id, context),
      'Accounting 第4.7節: 含むはテキスト'
    );
    context.invoice.Memo__c = '摘要なし';
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(conditionSet.Id, context)
    );
  }

  @IsTest
  static void validateRule_rejectsUnreachableAndMissingCompareType() {
    GlConditionRule__c unreachable = new GlConditionRule__c(
      TargetObject__c = 'InvoicePayment__c',
      TargetField__c = 'Amount__c',
      Operator__c = 'Equals',
      CompareType__c = 'FixedValue',
      CompareValue__c = '0'
    );
    System.assert(
      ConditionEvaluationService.validateRule(unreachable, 'Invoice')
        .contains('到達'),
      'Accounting 第4.7節: 評価コンテキストから到達できない対象は拒否'
    );
    GlConditionRule__c noType = new GlConditionRule__c(
      TargetObject__c = 'Invoice__c',
      TargetField__c = 'Amount__c',
      Operator__c = 'Equals'
    );
    System.assert(
      ConditionEvaluationService.validateRule(noType, 'Invoice')
        .contains('比較種別'),
      'Accounting 第4.7節: 比較種別を指定する'
    );
  }

  @IsTest
  static void validateConditionLogic_rejectsMissingNumberAndUnmatchedParen() {
    System.assert(
      ConditionEvaluationService.validateConditionLogic(
          '1 AND 9',
          new Set<Decimal>{ 1, 2 }
        )
        .contains('番号'),
      'Accounting 第4.7節: 条件ロジック内の番号実在'
    );
    System.assert(
      ConditionEvaluationService.validateConditionLogic(
          '(1 AND 2',
          new Set<Decimal>{ 1, 2 }
        )
        .contains('括弧'),
      'Accounting 第4.7節: 括弧対応'
    );
    System.assertEquals(
      null,
      ConditionEvaluationService.validateConditionLogic(
        'NOT 1',
        new Set<Decimal>{ 1 }
      )
    );
    System.assert(
      ConditionEvaluationService.validateConditionLogic(
          '1 2',
          new Set<Decimal>{ 1, 2 }
        )
        .contains('構文'),
      'Accounting 第4.7節: 番号の並置は構文不正'
    );
    System.assert(
      ConditionEvaluationService.validateConditionLogic(
          'AND 1',
          new Set<Decimal>{ 1 }
        )
        .contains('構文'),
      'Accounting 第4.7節: 先頭のANDは構文不正'
    );
  }

  @IsTest
  static void evaluateTenant_orTrueLeftConsumesRightHandSide() {
    GlConditionSet__c orSet = new GlConditionSet__c(
      Name = 'Eval Or True Left Set',
      EvaluationContext__c = 'Invoice',
      Description__c = 'OR短絡'
    );
    insert orSet;
    insert new List<GlConditionRule__c>{
      new GlConditionRule__c(
        ConditionSet__c = orSet.Id,
        Sequence__c = 1,
        TargetObject__c = 'Invoice__c',
        TargetField__c = 'Memo__c',
        Operator__c = 'IsNotNull'
      ),
      new GlConditionRule__c(
        ConditionSet__c = orSet.Id,
        Sequence__c = 2,
        TargetObject__c = 'Invoice__c',
        TargetField__c = 'Amount__c',
        Operator__c = 'Equals',
        CompareType__c = 'FixedValue',
        CompareValue__c = '1'
      )
    };
    orSet.ConditionLogic__c = '1 OR 2';
    update orSet;
    ConditionEvaluationService.Context orContext = new ConditionEvaluationService.Context();
    orContext.invoice = new Invoice__c(Memo__c = 'あり', Amount__c = 0);
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(orSet.Id, orContext),
      'Accounting 第4.7節: 左辺trueのORでも右辺を消費して成立する'
    );
  }

  @IsTest
  static void evaluateTenant_andFalseLeftConsumesRightHandSide() {
    GlConditionSet__c andSet = new GlConditionSet__c(
      Name = 'Eval And False Left Set',
      EvaluationContext__c = 'Invoice',
      Description__c = 'AND短絡'
    );
    insert andSet;
    insert new List<GlConditionRule__c>{
      new GlConditionRule__c(
        ConditionSet__c = andSet.Id,
        Sequence__c = 1,
        TargetObject__c = 'Invoice__c',
        TargetField__c = 'Memo__c',
        Operator__c = 'IsNotNull'
      ),
      new GlConditionRule__c(
        ConditionSet__c = andSet.Id,
        Sequence__c = 2,
        TargetObject__c = 'Invoice__c',
        TargetField__c = 'Amount__c',
        Operator__c = 'Equals',
        CompareType__c = 'FixedValue',
        CompareValue__c = '1000'
      )
    };
    andSet.ConditionLogic__c = '1 AND 2';
    update andSet;
    ConditionEvaluationService.Context andContext = new ConditionEvaluationService.Context();
    andContext.invoice = new Invoice__c(Amount__c = 1000);
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(andSet.Id, andContext),
      'Accounting 第4.7節: 左辺falseのANDでも右辺を消費して不成立とする'
    );
  }

  @IsTest
  static void evaluateTenant_doesNotRequeryCollectedSet() {
    GlConditionSet__c conditionSet = new GlConditionSet__c(
      Name = 'Eval Cache Set',
      EvaluationContext__c = 'InvoiceLine',
      Description__c = '収集1回'
    );
    insert conditionSet;
    insert new GlConditionRule__c(
      ConditionSet__c = conditionSet.Id,
      Sequence__c = 1,
      TargetObject__c = 'InvoiceLine__c',
      TargetField__c = 'Amount__c',
      Operator__c = 'Equals',
      CompareType__c = 'FixedValue',
      CompareValue__c = '100'
    );
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoiceLine = new InvoiceLine__c(Amount__c = 100);
    ConditionEvaluationService.evaluateTenant(conditionSet.Id, context);
    Integer afterFirst = Limits.getQueries();
    Boolean second = ConditionEvaluationService.evaluateTenant(
      conditionSet.Id,
      context
    );
    System.assertEquals(
      true,
      second,
      'Accounting 第8.2節: 収集済み条件の評価結果は変えない'
    );
    System.assertEquals(
      afterFirst,
      Limits.getQueries(),
      'Accounting 第8.2節: 同一処理で条件セットとルールを取り直さない'
    );
  }

  @IsTest
  static void collectedTenantRules_feedsEvaluateWithoutSecondQuery() {
    GlConditionSet__c conditionSet = new GlConditionSet__c(
      Name = 'Eval Shared Collect Set',
      EvaluationContext__c = 'InvoiceLine',
      Description__c = '項目収集と評価'
    );
    insert conditionSet;
    insert new GlConditionRule__c(
      ConditionSet__c = conditionSet.Id,
      Sequence__c = 1,
      TargetObject__c = 'InvoiceLine__c',
      TargetField__c = 'Amount__c',
      Operator__c = 'Equals',
      CompareType__c = 'FixedValue',
      CompareValue__c = '100'
    );
    ConditionEvaluationService.collectedTenantRules();
    Integer afterCollect = Limits.getQueries();
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoiceLine = new InvoiceLine__c(Amount__c = 100);
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(conditionSet.Id, context),
      'Accounting 第8.2節: 条件項目用のルール照会も同じ収集を使う'
    );
    System.assertEquals(
      afterCollect,
      Limits.getQueries(),
      'Accounting 第8.2節: 条件項目用のルール照会のあと評価で取り直さない'
    );
  }

  @IsTest
  static void evaluateTenant_notEqualsLessOrEqualAndNotContainsSplit() {
    Id notEqualsId = insertFixedRule(
      'Eval Not Equals',
      'Invoice',
      'Invoice__c',
      'Amount__c',
      'NotEquals',
      '1000',
      null
    );
    Id lessOrEqualId = insertFixedRule(
      'Eval Less Or Equal',
      'Invoice',
      'Invoice__c',
      'Amount__c',
      'LessOrEqual',
      '100',
      null
    );
    Id notContainsId = insertFixedRule(
      'Eval Not Contains',
      'Invoice',
      'Invoice__c',
      'Memo__c',
      'NotContains',
      '税',
      null
    );
    ConditionEvaluationService.Context same = new ConditionEvaluationService.Context();
    same.invoice = new Invoice__c(Amount__c = 1000, Memo__c = '消費税');
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(notEqualsId, same),
      'Accounting 第4.7節: 等しくないは同じ値で不成立'
    );
    ConditionEvaluationService.Context other = new ConditionEvaluationService.Context();
    other.invoice = new Invoice__c(Amount__c = 1);
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(notEqualsId, other),
      'Accounting 第4.7節: 等しくないは違う値で成立'
    );

    ConditionEvaluationService.Context atMost = new ConditionEvaluationService.Context();
    atMost.invoice = new Invoice__c(Amount__c = 100);
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(lessOrEqualId, atMost),
      'Accounting 第4.7節: 以下は同じ値で成立'
    );
    atMost.invoice.Amount__c = 99;
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(lessOrEqualId, atMost),
      'Accounting 第4.7節: 以下は小さい値で成立'
    );
    atMost.invoice.Amount__c = 101;
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(lessOrEqualId, atMost),
      'Accounting 第4.7節: 以下は大きい値で不成立'
    );

    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(notContainsId, same),
      'Accounting 第4.7節: 含まないは含まれていれば不成立'
    );
    same.invoice.Memo__c = '摘要なし';
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(notContainsId, same),
      'Accounting 第4.7節: 含まないは含まれていなければ成立'
    );
  }

  @IsTest
  static void evaluateTenant_notInvertsMatch() {
    GlConditionSet__c conditionSet = new GlConditionSet__c(
      Name = 'Eval Not Logic',
      EvaluationContext__c = 'Invoice',
      Description__c = '否定'
    );
    insert conditionSet;
    insert new GlConditionRule__c(
      ConditionSet__c = conditionSet.Id,
      Sequence__c = 1,
      TargetObject__c = 'Invoice__c',
      TargetField__c = 'Amount__c',
      Operator__c = 'Equals',
      CompareType__c = 'FixedValue',
      CompareValue__c = '1000'
    );
    conditionSet.ConditionLogic__c = 'NOT 1';
    update conditionSet;
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoice = new Invoice__c(Amount__c = 1000);
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(conditionSet.Id, context),
      'Accounting 第4.7節: 否定は元の成立を不成立にする'
    );
    context.invoice.Amount__c = 1;
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(conditionSet.Id, context),
      'Accounting 第4.7節: 否定は元の不成立を成立にする'
    );
  }

  @IsTest
  static void evaluateTenant_relatedMastersMatchAndMismatch() {
    Id productId = insertFixedRule(
      '対象商品',
      'InvoiceLine',
      'Product2',
      'Name',
      'Equals',
      '対象商品',
      null
    );
    Id opportunityId = insertFixedRule(
      '対象商談',
      'InvoiceLine',
      'Opportunity',
      'Name',
      'Equals',
      '対象商談',
      null
    );
    Id historyId = insertFixedRule(
      '対象履歴',
      'InvoiceLine',
      'ContractHistory__c',
      'Name',
      'Equals',
      '対象履歴',
      null
    );
    Id serviceId = insertFixedRule(
      '対象サービス',
      'InvoiceLine',
      'ContractService__c',
      'Name',
      'Equals',
      '対象サービス',
      null
    );
    Id billingAccountId = insertFixedRule(
      '対象請求先',
      'InvoiceLine',
      'BillingAccount__c',
      'Name',
      'Equals',
      '対象請求先',
      null
    );
    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.product = new Product2(Name = '対象商品');
    context.opportunity = new Opportunity(Name = '対象商談');
    context.contractHistory = new ContractHistory__c(Name = '対象履歴');
    context.contractService = new ContractService__c(Name = '対象サービス');
    context.billingAccount = new BillingAccount__c(Name = '対象請求先');
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(productId, context),
      'Accounting 第4.7節: 商品の項目が一致すれば成立'
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(opportunityId, context),
      'Accounting 第4.7節: 商談の項目が一致すれば成立'
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(historyId, context),
      'Accounting 第4.7節: 契約履歴の項目が一致すれば成立'
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(serviceId, context),
      'Accounting 第4.7節: 契約サービスの項目が一致すれば成立'
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(billingAccountId, context),
      'Accounting 第4.7節: 請求アカウントの項目が一致すれば成立'
    );
    context.product.Name = '別商品';
    context.opportunity.Name = '別商談';
    context.contractHistory.Name = '別履歴';
    context.contractService.Name = '別サービス';
    context.billingAccount.Name = '別請求先';
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(productId, context),
      'Accounting 第4.7節: 商品の項目が不一致なら不成立'
    );
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(opportunityId, context),
      'Accounting 第4.7節: 商談の項目が不一致なら不成立'
    );
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(historyId, context),
      'Accounting 第4.7節: 契約履歴の項目が不一致なら不成立'
    );
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(serviceId, context),
      'Accounting 第4.7節: 契約サービスの項目が不一致なら不成立'
    );
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(billingAccountId, context),
      'Accounting 第4.7節: 請求アカウントの項目が不一致なら不成立'
    );
  }

  @IsTest
  static void evaluateTenant_parenthesesChangeAndOrGrouping() {
    GlConditionSet__c groupedAnd = new GlConditionSet__c(
      Name = 'Eval Paren And',
      EvaluationContext__c = 'Invoice',
      Description__c = '括弧AND'
    );
    GlConditionSet__c groupedOr = new GlConditionSet__c(
      Name = 'Eval Paren Or',
      EvaluationContext__c = 'Invoice',
      Description__c = '括弧OR'
    );
    insert new List<GlConditionSet__c>{ groupedAnd, groupedOr };
    List<GlConditionRule__c> rules = new List<GlConditionRule__c>();
    for (
      GlConditionSet__c conditionSet : new List<GlConditionSet__c>{
        groupedAnd,
        groupedOr
      }
    ) {
      rules.add(
        new GlConditionRule__c(
          ConditionSet__c = conditionSet.Id,
          Sequence__c = 1,
          TargetObject__c = 'Invoice__c',
          TargetField__c = 'Memo__c',
          Operator__c = 'Equals',
          CompareType__c = 'FixedValue',
          CompareValue__c = 'A'
        )
      );
      rules.add(
        new GlConditionRule__c(
          ConditionSet__c = conditionSet.Id,
          Sequence__c = 2,
          TargetObject__c = 'Invoice__c',
          TargetField__c = 'Memo__c',
          Operator__c = 'Equals',
          CompareType__c = 'FixedValue',
          CompareValue__c = 'B'
        )
      );
      rules.add(
        new GlConditionRule__c(
          ConditionSet__c = conditionSet.Id,
          Sequence__c = 3,
          TargetObject__c = 'Invoice__c',
          TargetField__c = 'Memo__c',
          Operator__c = 'Equals',
          CompareType__c = 'FixedValue',
          CompareValue__c = 'C'
        )
      );
    }
    insert rules;
    groupedAnd.ConditionLogic__c = '(1 OR 2) AND 3';
    groupedOr.ConditionLogic__c = '1 OR (2 AND 3)';
    update new List<GlConditionSet__c>{ groupedAnd, groupedOr };

    ConditionEvaluationService.Context context = new ConditionEvaluationService.Context();
    context.invoice = new Invoice__c(Memo__c = 'A');
    System.assertEquals(
      false,
      ConditionEvaluationService.evaluateTenant(groupedAnd.Id, context),
      'Accounting 第4.7節: (1 OR 2) AND 3 は3が不成立なら不成立'
    );
    System.assertEquals(
      true,
      ConditionEvaluationService.evaluateTenant(groupedOr.Id, context),
      'Accounting 第4.7節: 1 OR (2 AND 3) は1が成立なら成立'
    );
  }

  private static Id insertFixedRule(
    String label,
    String evaluationContext,
    String targetObject,
    String targetField,
    String operatorName,
    String compareValue,
    String aggregateName
  ) {
    GlConditionSet__c conditionSet = new GlConditionSet__c(
      Name = label,
      EvaluationContext__c = evaluationContext,
      Description__c = label
    );
    insert conditionSet;
    insert new GlConditionRule__c(
      ConditionSet__c = conditionSet.Id,
      Sequence__c = 1,
      Aggregate__c = aggregateName,
      TargetObject__c = targetObject,
      TargetField__c = targetField,
      Operator__c = operatorName,
      CompareType__c = 'FixedValue',
      CompareValue__c = compareValue
    );
    return conditionSet.Id;
  }
}
