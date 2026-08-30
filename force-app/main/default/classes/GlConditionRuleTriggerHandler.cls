public without sharing class GlConditionRuleTriggerHandler {
  /** 仕様: Accounting 第4.7節 */
  public static void beforeInsertUpdate(List<GlConditionRule__c> newRecords) {
    if (newRecords == null || newRecords.isEmpty()) {
      return;
    }
    Set<Id> setIds = new Set<Id>();
    Set<Id> updatingIds = new Set<Id>();
    for (GlConditionRule__c row : newRecords) {
      if (row.ConditionSet__c != null) {
        setIds.add(row.ConditionSet__c);
      }
      if (row.Id != null) {
        updatingIds.add(row.Id);
      }
    }
    if (setIds.isEmpty()) {
      return;
    }
    Map<Id, GlConditionSet__c> setsById = new Map<Id, GlConditionSet__c>(
      [
        SELECT Id, EvaluationContext__c, ConditionLogic__c
        FROM GlConditionSet__c
        WHERE Id IN :setIds
        WITH SYSTEM_MODE
      ]
    );
    Map<Id, Set<Decimal>> sequencesBySet = new Map<Id, Set<Decimal>>();
    List<GlConditionRule__c> existingRows;
    if (updatingIds.isEmpty()) {
      existingRows = [
        SELECT Id, ConditionSet__c, Sequence__c
        FROM GlConditionRule__c
        WHERE ConditionSet__c IN :setIds
        WITH SYSTEM_MODE
      ];
    } else {
      existingRows = [
        SELECT Id, ConditionSet__c, Sequence__c
        FROM GlConditionRule__c
        WHERE ConditionSet__c IN :setIds AND Id NOT IN :updatingIds
        WITH SYSTEM_MODE
      ];
    }
    for (GlConditionRule__c existing : existingRows) {
      addSequence(sequencesBySet, existing.ConditionSet__c, existing.Sequence__c);
    }
    for (GlConditionRule__c row : newRecords) {
      if (row.ConditionSet__c == null) {
        continue;
      }
      if (row.Sequence__c != null) {
        Set<Decimal> used = sequencesBySet.get(row.ConditionSet__c);
        if (used != null && used.contains(row.Sequence__c)) {
          row.Sequence__c.addError('番号は条件セット内で一意にしてください。');
          continue;
        }
        addSequence(sequencesBySet, row.ConditionSet__c, row.Sequence__c);
      }
      GlConditionSet__c parent = setsById.get(row.ConditionSet__c);
      String context = parent == null ? null : parent.EvaluationContext__c;
      String ruleError = ConditionEvaluationService.validateRule(row, context);
      if (ruleError != null) {
        row.addError(ruleError);
      }
    }
    for (Id setId : setIds) {
      GlConditionSet__c parent = setsById.get(setId);
      if (parent == null) {
        continue;
      }
      String logicError = ConditionEvaluationService.validateConditionLogic(
        parent.ConditionLogic__c,
        sequencesBySet.get(setId)
      );
      if (logicError != null) {
        for (GlConditionRule__c row : newRecords) {
          if (row.ConditionSet__c == setId) {
            row.addError(logicError);
          }
        }
      }
    }
  }

  /** 仕様: Accounting 第4.7節 */
  public static void beforeDelete(List<GlConditionRule__c> oldRecords) {
    if (oldRecords == null || oldRecords.isEmpty()) {
      return;
    }
    Set<Id> setIds = new Set<Id>();
    Set<Id> deletingIds = new Set<Id>();
    for (GlConditionRule__c row : oldRecords) {
      if (row.ConditionSet__c != null) {
        setIds.add(row.ConditionSet__c);
      }
      if (row.Id != null) {
        deletingIds.add(row.Id);
      }
    }
    if (setIds.isEmpty()) {
      return;
    }
    Map<Id, GlConditionSet__c> setsById = new Map<Id, GlConditionSet__c>(
      [
        SELECT Id, ConditionLogic__c
        FROM GlConditionSet__c
        WHERE Id IN :setIds
        WITH SYSTEM_MODE
      ]
    );
    Map<Id, Set<Decimal>> sequencesBySet = new Map<Id, Set<Decimal>>();
    for (GlConditionRule__c existing : [
      SELECT Id, ConditionSet__c, Sequence__c
      FROM GlConditionRule__c
      WHERE ConditionSet__c IN :setIds AND Id NOT IN :deletingIds
      WITH SYSTEM_MODE
    ]) {
      addSequence(sequencesBySet, existing.ConditionSet__c, existing.Sequence__c);
    }
    Set<Id> referenced = referencedSetIds(setIds);
    for (GlConditionRule__c row : oldRecords) {
      Set<Decimal> remaining = sequencesBySet.get(row.ConditionSet__c);
      if (
        referenced.contains(row.ConditionSet__c) &&
        (remaining == null || remaining.isEmpty())
      ) {
        row.addError('条件が0件の条件セットは参照できません。');
        continue;
      }
      GlConditionSet__c parent = setsById.get(row.ConditionSet__c);
      String logicError = ConditionEvaluationService.validateConditionLogic(
        parent == null ? null : parent.ConditionLogic__c,
        remaining
      );
      if (logicError != null) {
        row.addError(logicError);
      }
    }
  }

  private static Set<Id> referencedSetIds(Set<Id> setIds) {
    Set<Id> referenced = new Set<Id>();
    for (GlAccountMap__c mapping : [
      SELECT TenantConditionSet__c
      FROM GlAccountMap__c
      WHERE TenantConditionSet__c IN :setIds
      WITH SYSTEM_MODE
    ]) {
      referenced.add(mapping.TenantConditionSet__c);
    }
    return referenced;
  }

  private static void addSequence(
    Map<Id, Set<Decimal>> sequencesBySet,
    Id setId,
    Decimal sequence
  ) {
    if (setId == null || sequence == null) {
      return;
    }
    Set<Decimal> sequences = sequencesBySet.get(setId);
    if (sequences == null) {
      sequences = new Set<Decimal>();
      sequencesBySet.put(setId, sequences);
    }
    sequences.add(sequence);
  }
}
