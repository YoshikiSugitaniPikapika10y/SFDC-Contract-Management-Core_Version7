@IsTest
private class GlConditionSetTriggerHandlerTest {
  @IsTest
  static void evaluationContextChange_rejectedWhenRuleExists() {
    GlConditionSet__c conditionSet = insertConditionSet('InvoiceLine');
    insertRule(conditionSet.Id, 1);
    conditionSet.EvaluationContext__c = 'Invoice';
    Database.SaveResult result = Database.update(conditionSet, false);
    System.assertEquals(false, result.isSuccess());
    System.assert(
      result.getErrors()[0].getMessage().contains('評価コンテキストは変更できません')
    );
  }

  @IsTest
  static void sequenceMustBeUniqueInSet() {
    GlConditionSet__c conditionSet = insertConditionSet('InvoiceLine');
    insertRule(conditionSet.Id, 1);
    Boolean thrown = false;
    try {
      insertRule(conditionSet.Id, 1);
    } catch (DmlException ex) {
      thrown = true;
      System.assert(ex.getMessage().contains('一意'));
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void accountMapRejectsNoneWithFixedKey() {
    GlAccount__c account = new GlAccount__c(
      Name = 'Map Asset',
      AccountType__c = 'Asset',
      IsActive__c = true
    );
    insert account;
    Boolean thrown = false;
    try {
      insert new GlAccountMap__c(
        Name = 'Invalid None',
        Account__c = account.Id,
        SlotKey__c = 'AccountsReceivable',
        EvaluationContext__c = 'InvoiceLine',
        ConditionSourceType__c = 'None',
        FixedConditionSetKey__c = 'PAY_INVOICE_CURRENT',
        Priority__c = 10,
        IsActive__c = true
      );
    } catch (DmlException ex) {
      thrown = true;
      System.assert(ex.getMessage().contains('なし'));
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void conditionLogic_rejectsMixedAndOrWithoutParens() {
    GlConditionSet__c conditionSet = insertConditionSet('InvoiceLine');
    insertRule(conditionSet.Id, 1);
    insertRule(conditionSet.Id, 2);
    insertRule(conditionSet.Id, 3);
    conditionSet.ConditionLogic__c = '1 AND 2 OR 3';
    Database.SaveResult result = Database.update(conditionSet, false);
    System.assertEquals(false, result.isSuccess());
    System.assert(
      result.getErrors()[0].getMessage().contains('括弧'),
      'Accounting 第4.7節: ANDとORの混在時は括弧が必要'
    );
  }

  @IsTest
  static void conditionLogic_rejectsUnknownSequence() {
    GlConditionSet__c conditionSet = insertConditionSet('InvoiceLine');
    insertRule(conditionSet.Id, 1);
    conditionSet.ConditionLogic__c = '1 AND 2';
    Database.SaveResult result = Database.update(conditionSet, false);
    System.assertEquals(false, result.isSuccess());
    System.assert(
      result.getErrors()[0].getMessage().contains('番号'),
      'Accounting 第4.7節: 条件ロジック内の番号実在'
    );
  }

  @IsTest
  static void accountMap_rejectsEmptyTenantSet() {
    GlConditionSet__c conditionSet = insertConditionSet('InvoiceLine');
    GlAccount__c account = new GlAccount__c(
      Name = 'Empty Set Asset',
      AccountType__c = 'Asset',
      IsActive__c = true
    );
    insert account;
    Boolean thrown = false;
    try {
      insert new GlAccountMap__c(
        Name = 'Empty Tenant Ref',
        Account__c = account.Id,
        SlotKey__c = 'AccountsReceivable',
        EvaluationContext__c = 'InvoiceLine',
        ConditionSourceType__c = 'Tenant',
        TenantConditionSet__c = conditionSet.Id,
        Priority__c = 10,
        IsActive__c = true
      );
    } catch (DmlException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('0件'),
        'Accounting 第4.7節: 条件0件セットの参照禁止'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void evaluationContextChange_allowedWhenNoChildOrReference() {
    GlConditionSetTriggerHandler.beforeInsertUpdate(null);
    GlConditionSetTriggerHandler.assertTenantSetsHaveRules(null);
    GlConditionSetTriggerHandler.assertTenantSetsHaveRules(
      new List<GlAccountMap__c>()
    );
    GlConditionSet__c conditionSet = insertConditionSet('InvoiceLine');
    conditionSet.EvaluationContext__c = 'Invoice';
    update conditionSet;
    GlConditionSet__c stored = [
      SELECT EvaluationContext__c
      FROM GlConditionSet__c
      WHERE Id = :conditionSet.Id
    ];
    System.assertEquals(
      'Invoice',
      stored.EvaluationContext__c,
      'Accounting 第4.7節: 子条件も参照元も無い間は評価コンテキストを変えられる'
    );
  }

  @IsTest
  static void evaluationContextChange_rejectedWhenAccountMapReferences() {
    GlConditionSet__c conditionSet = insertConditionSet('InvoiceLine');
    insertRule(conditionSet.Id, 1);
    GlAccount__c account = new GlAccount__c(
      Name = 'Tenant Ref Asset',
      AccountType__c = 'Asset',
      IsActive__c = true
    );
    insert account;
    insert new GlAccountMap__c(
      Name = 'Tenant Ref Map',
      Account__c = account.Id,
      SlotKey__c = 'AccountsReceivable',
      EvaluationContext__c = 'InvoiceLine',
      ConditionSourceType__c = 'Tenant',
      TenantConditionSet__c = conditionSet.Id,
      Priority__c = 10,
      IsActive__c = true
    );
    conditionSet.EvaluationContext__c = 'Invoice';
    Database.SaveResult result = Database.update(conditionSet, false);
    System.assertEquals(false, result.isSuccess());
    System.assert(
      result.getErrors()[0].getMessage().contains('評価コンテキストは変更できません'),
      'Accounting 第4.7節: 参照元がある間は評価コンテキストを変えない'
    );
  }

  private static GlConditionSet__c insertConditionSet(String context) {
    GlConditionSet__c conditionSet = new GlConditionSet__c(
      Name = 'Tenant Set',
      EvaluationContext__c = context,
      Description__c = 'テスト条件'
    );
    insert conditionSet;
    return conditionSet;
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
