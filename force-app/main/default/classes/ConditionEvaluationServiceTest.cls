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
    context.invoice = new Invoice__c(InvoiceDate__c = Date.newInstance(2026, 6, 1));
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
      ConditionEvaluationService.validateRule(rule, 'Invoice').contains('空判定'),
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
    context.invoice = new Invoice__c(InvoiceDate__c = Date.newInstance(2026, 6, 1));
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
    System.assertEquals(false, ConditionEvaluationService.evaluateTenant(conditionSet.Id, context));
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
      ConditionEvaluationService.validateRule(unreachable, 'Invoice').contains('到達'),
      'Accounting 第4.7節: 評価コンテキストから到達できない対象は拒否'
    );
    GlConditionRule__c noType = new GlConditionRule__c(
      TargetObject__c = 'Invoice__c',
      TargetField__c = 'Amount__c',
      Operator__c = 'Equals'
    );
    System.assert(
      ConditionEvaluationService.validateRule(noType, 'Invoice').contains('比較種別'),
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
  }
}
