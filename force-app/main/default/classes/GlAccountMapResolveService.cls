public without sharing class GlAccountMapResolveService {
  public class ResolveException extends Exception {
  }

  public class ResolvedAccount {
    public Id assignmentId;
    public Id accountId;
  }

  private static Map<String, List<GlAccountMap__c>> mapsBySlotContext;
  private static Map<String, ResolvedAccount> resolvedByContextKey;

  /** 仕様: Accounting 第6.1節、第6.2節、第6.3節、第4.1節、第8.2節 */
  public static ResolvedAccount resolve(
    String slotKey,
    ConditionEvaluationService.Context context
  ) {
    if (String.isBlank(slotKey)) {
      throw new ResolveException('勘定科目割当のスロットがありません。');
    }
    String cacheKey = resolveCacheKey(slotKey, context);
    if (
      cacheKey != null &&
      resolvedByContextKey != null &&
      resolvedByContextKey.containsKey(cacheKey)
    ) {
      return resolvedByContextKey.get(cacheKey);
    }
    List<GlAccountMap__c> candidates = mapsOf(slotKey);
    List<GlAccountMap__c> matched = new List<GlAccountMap__c>();
    for (GlAccountMap__c mapping : candidates) {
      if (matches(mapping, context)) {
        matched.add(mapping);
      }
    }
    if (matched.isEmpty()) {
      throw new ResolveException(
        'スロット ' + slotKey + ' の勘定科目割当がありません。'
      );
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
      throw new ResolveException(
        'スロット ' + slotKey + ' の最高優先度の勘定科目割当が複数あります。'
      );
    }
    if (top[0].Account__r.IsActive__c != true) {
      throw new ResolveException(
        'スロット ' + slotKey + ' の勘定科目割当の科目が無効です。'
      );
    }
    ResolvedAccount resolved = new ResolvedAccount();
    resolved.assignmentId = top[0].Id;
    resolved.accountId = top[0].Account__c;
    if (cacheKey != null) {
      if (resolvedByContextKey == null) {
        resolvedByContextKey = new Map<String, ResolvedAccount>();
      }
      resolvedByContextKey.put(cacheKey, resolved);
    }
    return resolved;
  }

  /**
   * 仕様: Accounting 第8.2節手順2。
   * 同じスロットの解決結果は使い回す。保存済み原因の Id が無い呼び出しはキャッシュしない。
   */
  private static String resolveCacheKey(
    String slotKey,
    ConditionEvaluationService.Context context
  ) {
    if (context == null) {
      return null;
    }
    String invoiceId = context.invoice == null
      ? null
      : String.valueOf(context.invoice.Id);
    String lineId = context.invoiceLine == null
      ? null
      : String.valueOf(context.invoiceLine.Id);
    String paymentId = context.invoicePayment == null
      ? null
      : String.valueOf(context.invoicePayment.Id);
    String allocationId = context.allocation == null
      ? null
      : String.valueOf(context.allocation.Id);
    if (
      String.isBlank(invoiceId) &&
      String.isBlank(lineId) &&
      String.isBlank(paymentId) &&
      String.isBlank(allocationId)
    ) {
      return null;
    }
    return slotKey +
      '\n' +
      invoiceId +
      '\n' +
      lineId +
      '\n' +
      paymentId +
      '\n' +
      allocationId;
  }

  /**
   * 仕様: Accounting 第6.1節、第6.3節、第8.2節。
   * 同一操作内の有効割当照会は1回にまとめ、スロットで濾る。
   * 条件評価は収集済み定義のメモリ上で行う。
   */
  private static List<GlAccountMap__c> mapsOf(String slotKey) {
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
          Account__r.IsActive__c,
          Account__r.AccountType__c
        FROM GlAccountMap__c
        WHERE IsActive__c = TRUE
        WITH SYSTEM_MODE
      ]) {
        if (!mapsBySlotContext.containsKey(mapping.SlotKey__c)) {
          mapsBySlotContext.put(mapping.SlotKey__c, new List<GlAccountMap__c>());
        }
        mapsBySlotContext.get(mapping.SlotKey__c).add(mapping);
      }
    }
    if (!mapsBySlotContext.containsKey(slotKey)) {
      mapsBySlotContext.put(slotKey, new List<GlAccountMap__c>());
    }
    return mapsBySlotContext.get(slotKey);
  }

  private static Boolean matches(
    GlAccountMap__c mapping,
    ConditionEvaluationService.Context context
  ) {
    if (
      mapping.ConditionSourceType__c == 'None' ||
      String.isBlank(mapping.ConditionSourceType__c)
    ) {
      return true;
    }
    if (mapping.ConditionSourceType__c == 'Fixed') {
      if (String.isBlank(mapping.FixedConditionSetKey__c)) {
        return false;
      }
      FixedConditionSetFixedCatalog.Definition fixedSet = FixedConditionSetFixedCatalog.require(
        mapping.FixedConditionSetKey__c
      );
      if (
        !ConditionEvaluationService.hasLaunchRecord(
          String.valueOf(fixedSet.evaluationContext),
          context
        )
      ) {
        return false;
      }
      return ConditionEvaluationService.evaluate(fixedSet, context);
    }
    if (mapping.ConditionSourceType__c == 'Tenant') {
      String launch = ConditionEvaluationService.launchContext(
        mapping.TenantConditionSet__c
      );
      if (!ConditionEvaluationService.hasLaunchRecord(launch, context)) {
        return false;
      }
      return ConditionEvaluationService.evaluateTenant(
        mapping.TenantConditionSet__c,
        context
      );
    }
    return false;
  }
}
