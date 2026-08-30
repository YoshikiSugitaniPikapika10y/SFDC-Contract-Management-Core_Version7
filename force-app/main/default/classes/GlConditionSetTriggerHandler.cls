public without sharing class GlConditionSetTriggerHandler {
  /** 仕様: Accounting 第4.7節 */
  public static void beforeInsertUpdate(List<GlConditionSet__c> newRecords) {
    if (newRecords == null || newRecords.isEmpty()) {
      return;
    }
    Set<Id> setIds = new Set<Id>();
    for (GlConditionSet__c row : newRecords) {
      if (row.Id != null) {
        setIds.add(row.Id);
      }
    }
    Map<Id, Set<Decimal>> sequencesBySet = new Map<Id, Set<Decimal>>();
    if (!setIds.isEmpty()) {
      for (GlConditionRule__c rule : [
        SELECT ConditionSet__c, Sequence__c
        FROM GlConditionRule__c
        WHERE ConditionSet__c IN :setIds
        WITH SYSTEM_MODE
      ]) {
        Set<Decimal> sequences = sequencesBySet.get(rule.ConditionSet__c);
        if (sequences == null) {
          sequences = new Set<Decimal>();
          sequencesBySet.put(rule.ConditionSet__c, sequences);
        }
        if (rule.Sequence__c != null) {
          sequences.add(rule.Sequence__c);
        }
      }
    }
    for (GlConditionSet__c row : newRecords) {
      Set<Decimal> sequences = row.Id == null
        ? new Set<Decimal>()
        : sequencesBySet.get(row.Id);
      String logicError = ConditionEvaluationService.validateConditionLogic(
        row.ConditionLogic__c,
        sequences
      );
      if (logicError != null) {
        row.ConditionLogic__c.addError(logicError);
      }
    }
  }

  /** 仕様: Accounting 第4.7節。子または参照元がある間は評価コンテキストを変えない。 */
  public static void beforeUpdate(
    List<GlConditionSet__c> newRecords,
    Map<Id, GlConditionSet__c> oldMap
  ) {
    beforeInsertUpdate(newRecords);
    Set<Id> changedIds = new Set<Id>();
    for (GlConditionSet__c row : newRecords) {
      GlConditionSet__c previous = oldMap.get(row.Id);
      if (row.EvaluationContext__c != previous.EvaluationContext__c) {
        changedIds.add(row.Id);
      }
    }
    if (changedIds.isEmpty()) {
      return;
    }
    Set<Id> referenced = new Set<Id>();
    for (GlConditionRule__c rule : [
      SELECT ConditionSet__c
      FROM GlConditionRule__c
      WHERE ConditionSet__c IN :changedIds
      WITH SYSTEM_MODE
    ]) {
      referenced.add(rule.ConditionSet__c);
    }
    for (GlAccountMap__c mapping : [
      SELECT TenantConditionSet__c
      FROM GlAccountMap__c
      WHERE TenantConditionSet__c IN :changedIds
      WITH SYSTEM_MODE
    ]) {
      referenced.add(mapping.TenantConditionSet__c);
    }
    for (GlConditionSet__c row : newRecords) {
      if (referenced.contains(row.Id)) {
        row.EvaluationContext__c.addError(
          '子条件または参照元がある条件セットの評価コンテキストは変更できません。'
        );
      }
    }
  }

  /** 仕様: Accounting 第4.7節 */
  public static void assertTenantSetsHaveRules(List<GlAccountMap__c> mappings) {
    if (mappings == null || mappings.isEmpty()) {
      return;
    }
    Set<Id> setIds = new Set<Id>();
    for (GlAccountMap__c mapping : mappings) {
      if (
        mapping.ConditionSourceType__c == 'Tenant' &&
        mapping.TenantConditionSet__c != null
      ) {
        setIds.add(mapping.TenantConditionSet__c);
      }
    }
    if (setIds.isEmpty()) {
      return;
    }
    Map<Id, Integer> counts = new Map<Id, Integer>();
    for (Id setId : setIds) {
      counts.put(setId, 0);
    }
    for (GlConditionRule__c rule : [
      SELECT ConditionSet__c
      FROM GlConditionRule__c
      WHERE ConditionSet__c IN :setIds
      WITH SYSTEM_MODE
    ]) {
      Integer current = counts.get(rule.ConditionSet__c);
      counts.put(rule.ConditionSet__c, current == null ? 1 : current + 1);
    }
    for (GlAccountMap__c mapping : mappings) {
      if (
        mapping.ConditionSourceType__c != 'Tenant' ||
        mapping.TenantConditionSet__c == null
      ) {
        continue;
      }
      Integer ruleCount = counts.get(mapping.TenantConditionSet__c);
      if (ruleCount == null || ruleCount == 0) {
        mapping.TenantConditionSet__c.addError('条件が0件の条件セットは参照できません。');
      }
    }
  }
}
