@IsTest
private class GlConditionRuleTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void sequenceMustBeUniqueInSet() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlConditionSet__c conditionSet = new GlConditionSet__c(
        Name = 'Rule Unique Set',
        EvaluationContext__c = 'InvoiceLine',
        Description__c = '番号一意'
      );
      insert conditionSet;
      insertRule(conditionSet.Id, 1);
      Boolean thrown = false;
      try {
        insertRule(conditionSet.Id, 1);
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('一意'),
          'Accounting 第4.7節: 番号はセット内一意'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void rejectsCompareExclusivityAndBlankOperatorFields() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlConditionSet__c conditionSet = new GlConditionSet__c(
        Name = 'Rule Exclusive Set',
        EvaluationContext__c = 'InvoiceLine',
        Description__c = '排他'
      );
      insert conditionSet;
      Boolean exclusive = false;
      try {
        insert new GlConditionRule__c(
          ConditionSet__c = conditionSet.Id,
          Sequence__c = 1,
          TargetObject__c = 'InvoiceLine__c',
          TargetField__c = 'Amount__c',
          Operator__c = 'Equals',
          CompareType__c = 'FixedValue',
          CompareValue__c = '0',
          CompareObject__c = 'Invoice__c',
          CompareField__c = 'Amount__c'
        );
      } catch (DmlException ex) {
        exclusive = true;
        System.assert(
          ex.getMessage().contains('固定値比較'),
          'Accounting 第4.7節: 固定値比較では比較値だけ'
        );
      }
      System.assertEquals(true, exclusive);

      Boolean blankCompare = false;
      try {
        insert new GlConditionRule__c(
          ConditionSet__c = conditionSet.Id,
          Sequence__c = 2,
          TargetObject__c = 'InvoiceLine__c',
          TargetField__c = 'Amount__c',
          Operator__c = 'IsNull',
          CompareType__c = 'FixedValue',
          CompareValue__c = '0'
        );
      } catch (DmlException ex) {
        blankCompare = true;
        System.assert(
          ex.getMessage().contains('空判定'),
          'Accounting 第4.7節: 空演算子では比較欄を空にする'
        );
      }
      System.assertEquals(true, blankCompare);
    }
  }

  @IsTest
  static void rejectsMissingFieldAndTypeMismatch() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlConditionSet__c conditionSet = new GlConditionSet__c(
        Name = 'Rule Type Set',
        EvaluationContext__c = 'InvoiceLine',
        Description__c = '型'
      );
      insert conditionSet;
      Boolean missing = false;
      try {
        insert new GlConditionRule__c(
          ConditionSet__c = conditionSet.Id,
          Sequence__c = 1,
          TargetObject__c = 'InvoiceLine__c',
          TargetField__c = 'NoSuchField__c',
          Operator__c = 'Equals',
          CompareType__c = 'FixedValue',
          CompareValue__c = '0'
        );
      } catch (DmlException ex) {
        missing = true;
        System.assert(
          ex.getMessage().contains('対象項目がありません'),
          'Accounting 第4.7節: 項目実在'
        );
      }
      System.assertEquals(true, missing);

      Boolean typeMismatch = false;
      try {
        insert new GlConditionRule__c(
          ConditionSet__c = conditionSet.Id,
          Sequence__c = 2,
          TargetObject__c = 'InvoiceLine__c',
          TargetField__c = 'Amount__c',
          Operator__c = 'Contains',
          CompareType__c = 'FixedValue',
          CompareValue__c = 'x'
        );
      } catch (DmlException ex) {
        typeMismatch = true;
        System.assert(
          ex.getMessage().contains('型'),
          'Accounting 第4.7節: 型と演算子の一致'
        );
      }
      System.assertEquals(true, typeMismatch);
    }
  }

  @IsTest
  static void rejectsChildWithoutAggregate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlConditionSet__c conditionSet = new GlConditionSet__c(
        Name = 'Rule Child Set',
        EvaluationContext__c = 'Invoice',
        Description__c = '集約'
      );
      insert conditionSet;
      Boolean thrown = false;
      try {
        insert new GlConditionRule__c(
          ConditionSet__c = conditionSet.Id,
          Sequence__c = 1,
          TargetObject__c = 'InvoiceLine__c',
          TargetField__c = 'Amount__c',
          Operator__c = 'Equals',
          CompareType__c = 'FixedValue',
          CompareValue__c = '0'
        );
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('集約'),
          'Accounting 第4.7節: 子対象時の集約必須'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  private static void insertRule(Id setId, Integer sequence) {
    insert new GlConditionRule__c(
      ConditionSet__c = setId,
      Sequence__c = sequence,
      TargetObject__c = 'InvoiceLine__c',
      TargetField__c = 'Amount__c',
      Operator__c = 'Equals',
      CompareType__c = 'FixedValue',
      CompareValue__c = '0'
    );
  }
}
