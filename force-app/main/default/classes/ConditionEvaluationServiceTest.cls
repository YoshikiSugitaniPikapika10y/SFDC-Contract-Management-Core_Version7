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
}
