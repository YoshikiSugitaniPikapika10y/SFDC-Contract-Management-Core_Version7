/**
 * 請求（Invoice__c）のロック判定。
 * プレビュー編集は請求書単位。差し戻し・再生成は Version 内にロックが1件でもあれば止める。
 * ロック中の更新許可項目は階層 CS InvoiceLockExemptFields__c（カンマ区切り API 名）。
 */
public without sharing class InvoiceLockUtil {
  public static final String SOQL_IS_LOCKED = '(SystemIntegrationDate__c != NULL OR PaymentClearingCompletedDate__c != NULL)';

  public static final String LOCKED_HISTORY_BLOCK_MESSAGE = '請求済またはエクスポート済の請求があるため、この契約履歴の請求を削除・再生成できません。';

  public static final String LOCKED_ROW_DML_BLOCK_MESSAGE = '請求済またはエクスポート済の請求は更新・削除できません。';

  public static final String INVOICE_EDIT_BLOCK_MESSAGE = 'この請求は連携済または消込済のため編集できません。';

  /** @deprecated プレビュー編集は assertInvoiceEditable を使う。Version 全体操作向けに残置。 */
  public static final String VERSION_EDIT_BLOCK_MESSAGE = 'この Version に連携済または消込済の請求があるため、請求を編集できません。';

  /** CS 未設定時の既定: 入金消込額・消込完了日のみロック除外 */
  @TestVisible
  private static final String DEFAULT_LOCK_EXEMPT_FIELDS = 'PaymentClearedAmount__c,PaymentClearingCompletedDate__c';

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
  private static Boolean testCanBypassLockedDml;

  /** テスト用。null でなければ CS より優先 */
  @TestVisible
  private static String testLockExemptFieldApiNames;

  public static Boolean isLocked(Invoice__c invoice) {
    if (invoice == null) {
      return false;
    }
    return invoice.SystemIntegrationDate__c != null ||
      invoice.PaymentClearingCompletedDate__c != null;
  }

  public static Boolean isInvoiced(Invoice__c invoice) {
    return invoice != null && invoice.SystemIntegrationDate__c != null;
  }

  public static Boolean isExported(Invoice__c invoice) {
    return invoice != null && invoice.PaymentClearingCompletedDate__c != null;
  }

  public static Boolean canBypassLockedDml() {
    if (testCanBypassLockedDml != null) {
      return testCanBypassLockedDml;
    }
    return ContractPermissionUtil.canBypassIntegrityGuards();
  }

  public static void blockLockedRowDml(
    List<Invoice__c> records,
    Map<Id, Invoice__c> oldMap
  ) {
    if (canBypassLockedDml() || records == null || records.isEmpty()) {
      return;
    }
    Set<String> exemptFields = resolveLockExemptFieldNames();
    for (Invoice__c record : records) {
      if (record == null) {
        continue;
      }
      Invoice__c prior = oldMap == null ? record : oldMap.get(record.Id);
      if (prior == null) {
        prior = record;
      }
      if (!isLocked(prior)) {
        continue;
      }
      // 連携未済の消込日クリアだけは許可（エクスポート取り消し）
      if (
        oldMap != null &&
        prior.SystemIntegrationDate__c == null &&
        record.SystemIntegrationDate__c == null &&
        record.PaymentClearingCompletedDate__c == null
      ) {
        continue;
      }
      // 除外項目だけの更新はロック中も許可
      if (
        oldMap != null && isLockExemptOnlyUpdate(prior, record, exemptFields)
      ) {
        continue;
      }
      record.addError(LOCKED_ROW_DML_BLOCK_MESSAGE);
    }
  }

  /**
   * 階層 CS InvoiceLockExemptFields__c.FieldApiNames__c（カンマ区切り）。
   * 空／未設定時は消込額・消込完了日。
   */
  public static Set<String> resolveLockExemptFieldNames() {
    String raw = testLockExemptFieldApiNames;
    if (raw == null) {
      InvoiceLockExemptFields__c setting = InvoiceLockExemptFields__c.getInstance();
      raw = setting == null ? null : setting.FieldApiNames__c;
    }
    if (String.isBlank(raw)) {
      raw = DEFAULT_LOCK_EXEMPT_FIELDS;
    }
    Set<String> names = new Set<String>();
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

  @TestVisible
  private static Boolean isLockExemptOnlyUpdate(
    Invoice__c prior,
    Invoice__c current,
    Set<String> exemptFields
  ) {
    if (
      prior == null ||
      current == null ||
      exemptFields == null ||
      exemptFields.isEmpty()
    ) {
      return false;
    }
    Boolean anyExemptChange = false;
    Map<String, Schema.SObjectField> fieldMap = Invoice__c.SObjectType.getDescribe()
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
      // Describe のキーは小文字のことがあるため、正規名でも照合する
      String fieldName = token.getDescribe().getName();
      if (
        !exemptFields.contains(fieldName) && !exemptFields.contains(apiName)
      ) {
        return false;
      }
      anyExemptChange = true;
    }
    return anyExemptChange;
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

  public static Boolean hasLockedInvoices(Set<Id> contractHistoryIds) {
    return !queryHistoryIdsWithLockedInvoices(contractHistoryIds).isEmpty();
  }

  public static Set<Id> queryHistoryIdsWithLockedInvoices(
    Set<Id> contractHistoryIds
  ) {
    Set<Id> blockedHistoryIds = new Set<Id>();
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return blockedHistoryIds;
    }
    String lockedAggSoql =
      'SELECT ContractHistory__c historyId' +
      ' FROM Invoice__c' +
      ' WHERE ContractHistory__c IN :contractHistoryIds' +
      ' AND ' +
      SOQL_IS_LOCKED +
      ' WITH SYSTEM_MODE' +
      ' GROUP BY ContractHistory__c';
    for (AggregateResult result : Database.query(lockedAggSoql)) {
      blockedHistoryIds.add((Id) result.get('historyId'));
    }
    return blockedHistoryIds;
  }

  public static void assertNoLockedInvoices(Set<Id> contractHistoryIds) {
    if (canBypassLockedDml()) {
      return;
    }
    if (hasLockedInvoices(contractHistoryIds)) {
      throw new InvoiceLockException(LOCKED_HISTORY_BLOCK_MESSAGE);
    }
  }

  /**
   * 請求プレビュー編集用: 対象請求がロックなら編集不可。
   */
  public static void assertInvoiceEditable(Id invoiceId) {
    if (invoiceId == null || canBypassLockedDml()) {
      return;
    }
    List<Invoice__c> invoices = [
      SELECT Id, SystemIntegrationDate__c, PaymentClearingCompletedDate__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (invoices.isEmpty()) {
      return;
    }
    assertInvoiceEditable(invoices[0]);
  }

  public static void assertInvoiceEditable(Invoice__c invoice) {
    if (canBypassLockedDml() || invoice == null) {
      return;
    }
    if (isLocked(invoice)) {
      throw new InvoiceLockException(INVOICE_EDIT_BLOCK_MESSAGE);
    }
  }

  public static void assertInvoicesEditable(Set<Id> invoiceIds) {
    if (canBypassLockedDml() || invoiceIds == null || invoiceIds.isEmpty()) {
      return;
    }
    String lockedSoql =
      'SELECT Id' +
      ' FROM Invoice__c' +
      ' WHERE Id IN :invoiceIds' +
      ' AND ' +
      SOQL_IS_LOCKED +
      ' WITH SYSTEM_MODE' +
      ' LIMIT 1';
    List<Invoice__c> locked = Database.query(lockedSoql);
    if (!locked.isEmpty()) {
      throw new InvoiceLockException(INVOICE_EDIT_BLOCK_MESSAGE);
    }
  }

  /**
   * Version 内のいずれかがロックなら不可（差し戻し・再生成など Version 全体操作向け）。
   */
  public static void assertVersionEditable(Id contractHistoryId) {
    if (contractHistoryId == null || canBypassLockedDml()) {
      return;
    }
    if (hasLockedInvoices(new Set<Id>{ contractHistoryId })) {
      throw new InvoiceLockException(VERSION_EDIT_BLOCK_MESSAGE);
    }
  }

  public class InvoiceLockException extends Exception {
  }
}
