public without sharing class GlAccountMapResolveService {
  public class ResolveException extends Exception {
  }

  public class ResolvedAccount {
    public Id assignmentId;
    public Id accountId;
  }

  private static Map<String, List<GlAccountMap__c>> mapsBySlotContext;

  /** 仕様: Accounting 第6.2節、第6.3節、第4.1節、第8.2節 */
  public static ResolvedAccount resolve(
    String slotKey,
    String evaluationContext,
    ConditionEvaluationService.Context context
  ) {
    if (String.isBlank(slotKey) || String.isBlank(evaluationContext)) {
      throw new ResolveException('勘定科目割当のスロットまたは評価コンテキストがありません。');
    }
    List<GlAccountMap__c> candidates = mapsOf(slotKey, evaluationContext);
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

  /**
   * 仕様: Accounting 第6.3節、第8.2節。
   * 同一操作内の有効割当照会は1回にまとめ、スロットと評価コンテキストで濾る。条件一致は呼び出しごとに評価する。
   */
  private static List<GlAccountMap__c> mapsOf(String slotKey, String evaluationContext) {
    if (mapsBySlotContext == null) {
      mapsBySlotContext = new Map<String, List<GlAccountMap__c>>();
      for (GlAccountMap__c mapping : [
        SELECT
          Id,
          Account__c,
          Priority__c,
          ConditionSourceType__c,
          FixedConditionSetKey__c,
          TenantConditionSet__c,
          SlotKey__c,
          EvaluationContext__c,
          Account__r.IsActive__c,
          Account__r.AccountType__c
        FROM GlAccountMap__c
        WHERE IsActive__c = TRUE
        WITH SYSTEM_MODE
      ]) {
        String loadedKey = mapping.SlotKey__c + '\n' + mapping.EvaluationContext__c;
        if (!mapsBySlotContext.containsKey(loadedKey)) {
          mapsBySlotContext.put(loadedKey, new List<GlAccountMap__c>());
        }
        mapsBySlotContext.get(loadedKey).add(mapping);
      }
    }
    String cacheKey = slotKey + '\n' + evaluationContext;
    if (!mapsBySlotContext.containsKey(cacheKey)) {
      mapsBySlotContext.put(cacheKey, new List<GlAccountMap__c>());
    }
    return mapsBySlotContext.get(cacheKey);
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
