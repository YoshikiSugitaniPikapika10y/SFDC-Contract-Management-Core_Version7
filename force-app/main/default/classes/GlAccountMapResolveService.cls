public without sharing class GlAccountMapResolveService {
  public class ResolveException extends Exception {
  }

  public class ResolvedAccount {
    public Id assignmentId;
    public Id accountId;
  }

  /** 仕様: Accounting 第6.2節、第6.3節、第4.1節 */
  public static ResolvedAccount resolve(
    String slotKey,
    String evaluationContext,
    ConditionEvaluationService.Context context
  ) {
    if (String.isBlank(slotKey) || String.isBlank(evaluationContext)) {
      throw new ResolveException('勘定科目割当のスロットまたは評価コンテキストがありません。');
    }
    List<GlAccountMap__c> candidates = [
      SELECT
        Id,
        Account__c,
        Priority__c,
        ConditionSourceType__c,
        FixedConditionSetKey__c,
        TenantConditionSet__c,
        Account__r.IsActive__c,
        Account__r.AccountType__c
      FROM GlAccountMap__c
      WHERE
        SlotKey__c = :slotKey
        AND EvaluationContext__c = :evaluationContext
        AND IsActive__c = TRUE
      WITH SYSTEM_MODE
    ];
    List<GlAccountMap__c> matched = new List<GlAccountMap__c>();
    for (GlAccountMap__c mapping : candidates) {
      if (matches(mapping, context)) {
        matched.add(mapping);
      }
    }
    if (matched.isEmpty()) {
      throw new ResolveException('スロット ' + slotKey + ' の勘定科目割当がありません。');
    }
    Decimal highest = null;
    for (GlAccountMap__c mapping : matched) {
      Decimal priority = mapping.Priority__c == null ? 0 : mapping.Priority__c;
      if (highest == null || priority > highest) {
        highest = priority;
      }
    }
    List<GlAccountMap__c> top = new List<GlAccountMap__c>();
    for (GlAccountMap__c mapping : matched) {
      Decimal priority = mapping.Priority__c == null ? 0 : mapping.Priority__c;
      if (priority == highest) {
        top.add(mapping);
      }
    }
    if (top.size() != 1) {
      throw new ResolveException('スロット ' + slotKey + ' の最高優先度の勘定科目割当が複数あります。');
    }
    if (top[0].Account__r.IsActive__c != true) {
      throw new ResolveException(
        'スロット ' + slotKey + ' の勘定科目割当の科目が無効です。'
      );
    }
    ResolvedAccount resolved = new ResolvedAccount();
    resolved.assignmentId = top[0].Id;
    resolved.accountId = top[0].Account__c;
    return resolved;
  }

  private static Boolean matches(
    GlAccountMap__c mapping,
    ConditionEvaluationService.Context context
  ) {
    if (mapping.ConditionSourceType__c == 'None' || String.isBlank(mapping.ConditionSourceType__c)) {
      return true;
    }
    if (mapping.ConditionSourceType__c == 'Fixed') {
      if (String.isBlank(mapping.FixedConditionSetKey__c)) {
        return false;
      }
      return ConditionEvaluationService.evaluate(
        FixedConditionSetFixedCatalog.require(mapping.FixedConditionSetKey__c),
        context
      );
    }
    if (mapping.ConditionSourceType__c == 'Tenant') {
      return ConditionEvaluationService.evaluateTenant(mapping.TenantConditionSet__c, context);
    }
    return false;
  }
}
