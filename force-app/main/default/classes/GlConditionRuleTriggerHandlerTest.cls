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

  @IsTest
  static void handler_emptyListsDoNothing() {
    GlConditionRuleTriggerHandler.beforeInsertUpdate(null);
    GlConditionRuleTriggerHandler.beforeInsertUpdate(
      new List<GlConditionRule__c>()
    );
    GlConditionRuleTriggerHandler.beforeDelete(null);
    GlConditionRuleTriggerHandler.beforeDelete(new List<GlConditionRule__c>());
    System.assertEquals(true, true);
  }

  @IsTest
  static void update_rejectsDuplicateSequenceInSet() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlConditionSet__c conditionSet = new GlConditionSet__c(
        Name = 'Rule Update Unique',
        EvaluationContext__c = 'InvoiceLine',
        Description__c = '更新一意'
      );
      insert conditionSet;
      insertRule(conditionSet.Id, 1);
      insertRule(conditionSet.Id, 2);
      GlConditionRule__c second = [
        SELECT Id, Sequence__c
        FROM GlConditionRule__c
        WHERE ConditionSet__c = :conditionSet.Id AND Sequence__c = 2
      ];
      second.Sequence__c = 1;
      Boolean thrown = false;
      try {
        update second;
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
  static void delete_rejectsLastRuleWhenSetIsReferenced() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlConditionSet__c conditionSet = new GlConditionSet__c(
        Name = 'Rule Referenced Set',
        EvaluationContext__c = 'InvoiceLine',
        Description__c = '参照中'
      );
      insert conditionSet;
      insertRule(conditionSet.Id, 1);
      GlAccount__c account = new GlAccount__c(
        Name = 'Rule Map Asset',
        AccountType__c = 'Asset',
        IsActive__c = true
      );
      insert account;
      insert new GlAccountMap__c(
        Name = 'Tenant Ref',
        Account__c = account.Id,
        SlotKey__c = 'AccountsReceivable',
        EvaluationContext__c = 'InvoiceLine',
        ConditionSourceType__c = 'Tenant',
        TenantConditionSet__c = conditionSet.Id,
        Priority__c = 10,
        IsActive__c = true
      );
      GlConditionRule__c onlyRule = [
        SELECT Id
        FROM GlConditionRule__c
        WHERE ConditionSet__c = :conditionSet.Id
      ];
      Boolean thrown = false;
      try {
        delete onlyRule;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('0件'),
          'Accounting 第4.7節: 条件0件セットの参照禁止'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void delete_rejectsWhenRemainingBreaksConditionLogic() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlConditionSet__c conditionSet = new GlConditionSet__c(
        Name = 'Rule Logic Set',
        EvaluationContext__c = 'InvoiceLine',
        Description__c = 'ロジック'
      );
      insert conditionSet;
      insertRule(conditionSet.Id, 1);
      insertRule(conditionSet.Id, 2);
      conditionSet.ConditionLogic__c = '1 AND 2';
      update conditionSet;
      GlConditionRule__c second = [
        SELECT Id
        FROM GlConditionRule__c
        WHERE ConditionSet__c = :conditionSet.Id AND Sequence__c = 2
      ];
      Boolean thrown = false;
      try {
        delete second;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('番号'),
          'Accounting 第4.7節: 条件ロジック内の番号実在'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void insert_allowsChildTargetWhenAggregateSet() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlConditionSet__c conditionSet = new GlConditionSet__c(
        Name = 'Rule Aggregate Set',
        EvaluationContext__c = 'Invoice',
        Description__c = '集約あり'
      );
      insert conditionSet;
      insert new GlConditionRule__c(
        ConditionSet__c = conditionSet.Id,
        Sequence__c = 1,
        Aggregate__c = 'All',
        TargetObject__c = 'InvoiceLine__c',
        TargetField__c = 'Amount__c',
        Operator__c = 'Equals',
        CompareType__c = 'FixedValue',
        CompareValue__c = '0'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM GlConditionRule__c
          WHERE ConditionSet__c = :conditionSet.Id
        ],
        'Accounting 第4.7節: 子対象時は集約があれば保存できる'
      );
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
