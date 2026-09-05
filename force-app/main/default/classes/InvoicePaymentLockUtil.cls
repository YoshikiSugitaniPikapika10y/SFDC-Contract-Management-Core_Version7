/**
 * 請求入出金の登録後更新可否。
 * 仕様: Core 第11.6節、第8.4節、第11.4.4節。
 */
public without sharing class InvoicePaymentLockUtil {
  public class LockExemptException extends Exception {
  }

  /** 仕様: Core 第11.6節。人が足す一覧の外。製品固定で登録後も直せる。 */
  public static final String PRODUCT_FIXED_EXEMPT_FIELD = 'Memo__c';

  /** @deprecated Core 第11.6節。初回インストールでは組織既定を作らない。 */
  public static final String SEED_LOCK_EXEMPT_FIELDS = 'Memo__c';

  public static final String NEVER_EXEMPT_MESSAGE =
    '入出金の金額・日付・目的は更新できません。';

  public static final String NOT_EXEMPT_MESSAGE =
    '登録後の入出金は、入出金ロック除外項目以外を更新できません。';

  private static final Set<String> NEVER_EXEMPT = new Set<String>{
    'Amount__c',
    'PaymentDate__c',
    'PaymentPurpose__c'
  };

  private static final Set<String> IGNORED_FIELD_NAMES = new Set<String>{
    'Id',
    'IsDeleted',
    'CreatedDate',
    'CreatedById',
    'LastModifiedDate',
    'LastModifiedById',
    'SystemModstamp',
    'LastActivityDate',
    'LastViewedDate',
    'LastReferencedDate',
    'UserRecordAccessId'
  };

  @TestVisible
  private static String testLockExemptFieldApiNames;

  /** 仕様: Core 第11.6節、第11.4.4節。人が直せる追加項目だけ。無い・空は追加なし。 */
  public static Set<String> resolveLockExemptFieldNames() {
    String raw = testLockExemptFieldApiNames;
    if (raw == null) {
      InvoicePaymentLockExemptFields__c setting = InvoicePaymentLockExemptFields__c.getOrgDefaults();
      raw = setting == null || setting.Id == null
        ? null
        : setting.FieldApiNames__c;
    }
    Set<String> names = new Set<String>();
    if (String.isBlank(raw)) {
      return names;
    }
    for (String part : raw.split(',')) {
      if (part == null) {
        continue;
      }
      String trimmed = part.trim();
      if (String.isNotBlank(trimmed)) {
        names.add(trimmed);
      }
    }
    return names;
  }

  /**
   * 仕様: Core 第11.6節、第8.4節。
   * 値が変わった項目がすべて除外一覧内の場合だけ許す。金額・日付・目的は一覧に書いても不可。
   */
  public static void assertExemptUpdate(
    InvoicePayment__c prior,
    InvoicePayment__c current
  ) {
    Set<String> exemptFields = resolveLockExemptFieldNames();
    String rejection = firstForbiddenChange(prior, current, exemptFields);
    if (rejection != null) {
      throw new LockExemptException(rejection);
    }
  }

  @TestVisible
  private static String firstForbiddenChange(
    InvoicePayment__c prior,
    InvoicePayment__c current,
    Set<String> exemptFields
  ) {
    if (prior == null || current == null) {
      return NOT_EXEMPT_MESSAGE;
    }
    Map<String, Schema.SObjectField> fieldMap = InvoicePayment__c.SObjectType.getDescribe()
      .fields.getMap();
    for (String apiName : fieldMap.keySet()) {
      if (IGNORED_FIELD_NAMES.contains(apiName)) {
        continue;
      }
      Schema.SObjectField token = fieldMap.get(apiName);
      if (token == null || !current.isSet(token)) {
        continue;
      }
      Object priorValue = prior.get(token);
      Object currentValue = current.get(token);
      if (valuesEqual(priorValue, currentValue)) {
        continue;
      }
      String fieldName = token.getDescribe().getName();
      if (isNeverExempt(fieldName) || isNeverExempt(apiName)) {
        return NEVER_EXEMPT_MESSAGE;
      }
      if (isProductFixedExempt(fieldName) || isProductFixedExempt(apiName)) {
        continue;
      }
      if (
        !containsName(exemptFields, fieldName) &&
        !containsName(exemptFields, apiName)
      ) {
        return NOT_EXEMPT_MESSAGE;
      }
    }
    return null;
  }

  private static Boolean isProductFixedExempt(String fieldName) {
    return PRODUCT_FIXED_EXEMPT_FIELD.equals(fieldName);
  }

  private static Boolean isNeverExempt(String fieldName) {
    return NEVER_EXEMPT.contains(fieldName);
  }

  private static Boolean containsName(Set<String> names, String fieldName) {
    return names != null && names.contains(fieldName);
  }

  private static Boolean valuesEqual(Object left, Object right) {
    if (left == null && right == null) {
      return true;
    }
    if (left == null || right == null) {
      return false;
    }
    if (left instanceof Decimal && right instanceof Decimal) {
      return (Decimal) left == (Decimal) right;
    }
    return left == right;
  }
}
