/**
 * 請求（Invoice__c）のロック判定。
 * プレビュー編集は請求書単位。差し戻し・再生成は Version 内にロックが1件でもあれば止める。
 * ロック中の更新許可項目は階層 CS InvoiceLockExemptFields__c（カンマ区切り API 名）。
 */
public without sharing class InvoiceLockUtil {
  /** 仕様: Core 第7.11節。行の内容変更・削除を止める。確定済みと取消済み。 */
  public static final String SOQL_IS_LOCKED =
    '(InvoiceTransactionStatus__c IN (\'Confirmed\',\'Cancelled\'))';

  /** 仕様: Core 第1.1.5節。Version再生成・差し戻しを止めるのは有効な確定済みだけ。 */
  public static final String SOQL_IS_ACTIVE_CONFIRMED =
    '(InvoiceTransactionStatus__c = \'Confirmed\')';

  /** 仕様: Core 第1.1.5節、第5.3節、第7.9.2節。差し戻し・再生成は有効な確定済み。 */
  public static final String LOCKED_HISTORY_BLOCK_MESSAGE = '有効な確定済み請求があるため、この契約履歴の請求を削除・再生成できません。';

  public static final String LOCKED_ROW_DML_BLOCK_MESSAGE = '請求済またはエクスポート済の請求は更新・削除できません。';

  /** 仕様: Core 第7.8節、第7.11節。確定済みと取消済み。 */
  public static final String INVOICE_EDIT_BLOCK_MESSAGE = '確定済み・取消済みの請求は編集できません。';

  /** @deprecated プレビュー編集は assertInvoiceEditable を使う。Version 全体操作向けに残置。 */
  public static final String VERSION_EDIT_BLOCK_MESSAGE = 'この Version に連携済または消込済の請求があるため、請求を編集できません。';

  /** 仕様: Core 第11.6節、第7.9.2節。インストール時シード。実行時の空欄代替には使わない。 */
  public static final String SEED_LOCK_EXEMPT_FIELDS =
    'InvoiceTransactionStatus__c,DeliveryStatus__c,CollectionRefundStatus__c,InvoicePaymentNet__c,PaymentInclusiveTotal__c,PaymentClearingCompletedDate__c,SystemIntegrationDate__c,SentDate__c,Memo__c';

  public static final String MISSING_LOCK_EXEMPT_MESSAGE = '請求ロック除外項目の組織設定が無い、または空です。';

  /** 仕様: Core 第11.6節。確定後の請求日・入金予定日・税率・請求アカウントは除外一覧に書いても拒否する。 */
  public static final String CONFIRMED_CORE_FIELDS_BLOCK_MESSAGE =
    '確定済み請求の請求日・入金予定日・税率・請求アカウントは変更できません。';

  private static final Set<String> NEVER_EXEMPT_WHEN_LOCKED = new Set<String>{
    'InvoiceDate__c',
    'PaymentScheduledDate__c',
    'TaxPercent__c',
    'BillingAccountSnapShot__c'
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
  private static Boolean testCanBypassLockedDml;

  /**
   * 回収ステータス再計算など、ロック中でも書いてよいエンジン更新用。
   * 呼び出し側で true にして DML し、finally で必ず戻す。
   */
  public static Boolean allowLockedStatusWrite;

  /** テスト用。null でなければ CS より優先 */
  @TestVisible
  private static String testLockExemptFieldApiNames;

  /** 仕様: Core 第7.11節。行の内容変更・削除を止める。確定済みと取消済み。 */
  public static Boolean isLocked(Invoice__c invoice) {
    if (invoice == null) {
      return false;
    }
    return InvoiceTransactionStatusService.isConfirmed(invoice) ||
      InvoiceTransactionStatusService.isCancelled(invoice);
  }

  /** 仕様: Core 第1.1.5節。Version再生成・差し戻しを止めるのは有効な確定済みだけ。 */
  public static Boolean isActiveConfirmed(Invoice__c invoice) {
    return InvoiceTransactionStatusService.isConfirmed(invoice);
  }

  public static Boolean isInvoiced(Invoice__c invoice) {
    return isActiveConfirmed(invoice);
  }

  public static Boolean isExported(Invoice__c invoice) {
    return invoice != null &&
      invoice.CollectionRefundStatus__c ==
      InvoiceTransactionStatusService.COLLECTION_COMPLETED;
  }

  public static Boolean canBypassLockedDml() {
    if (allowLockedStatusWrite == true) {
      return true;
    }
    if (testCanBypassLockedDml != null) {
      return testCanBypassLockedDml;
    }
    return ContractPermissionUtil.hasFixConfirmedInvoice();
  }

  /** 仕様: 共通基盤 第3.6節。確定済み請求の削除は 103／104。 */
  public static Boolean canBypassLockedDelete() {
    if (allowLockedStatusWrite == true) {
      return true;
    }
    if (testCanBypassLockedDml != null) {
      return testCanBypassLockedDml;
    }
    return ContractPermissionUtil.hasDeleteRecords();
  }

  public static void blockLockedRowDml(
    List<Invoice__c> records,
    Map<Id, Invoice__c> oldMap
  ) {
    Boolean bypass = oldMap == null
      ? canBypassLockedDelete()
      : canBypassLockedDml();
    if (bypass || records == null || records.isEmpty()) {
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

  /** 仕様: Core 第11.6節。Accountingの内部更新に限り、有効タグルールの保存先も除外する。 */
  public static Boolean allowAccountingTagLockExempt;

  /**
   * 仕様: Core 第1.1.10節、第11.6節。
   * 階層 CS InvoiceLockExemptFields__c.FieldApiNames__c（カンマ区切り）。
   * レコード無し・空はシードへ落とさずエラー。
   * 有効な会計タグルールの保存先チェックボックスは Accounting 内部更新だけ動的に足す。
   */
  public static Set<String> resolveLockExemptFieldNames() {
    String raw = testLockExemptFieldApiNames;
    if (raw == null) {
      InvoiceLockExemptFields__c setting = InvoiceLockExemptFields__c.getOrgDefaults();
      if (setting == null || setting.Id == null) {
        throw new LockExemptException(MISSING_LOCK_EXEMPT_MESSAGE);
      }
      raw = setting.FieldApiNames__c;
    }
    if (String.isBlank(raw)) {
      throw new LockExemptException(MISSING_LOCK_EXEMPT_MESSAGE);
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
    if (names.isEmpty()) {
      throw new LockExemptException(MISSING_LOCK_EXEMPT_MESSAGE);
    }
    if (allowAccountingTagLockExempt == true) {
      names.addAll(enabledAccountingTagTargetFields());
    }
    return names;
  }

  private static Set<String> enabledAccountingTagTargetFields() {
    Set<String> targets = new Set<String>();
    for (GlAccountingTagRule__c rule : [
      SELECT TargetFieldApiName__c
      FROM GlAccountingTagRule__c
      WHERE IsEnabled__c = TRUE
      WITH SYSTEM_MODE
    ]) {
      if (String.isNotBlank(rule.TargetFieldApiName__c)) {
        targets.add(rule.TargetFieldApiName__c);
      }
    }
    return targets;
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
        NEVER_EXEMPT_WHEN_LOCKED.contains(fieldName) ||
        NEVER_EXEMPT_WHEN_LOCKED.contains(apiName)
      ) {
        return false;
      }
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
      SOQL_IS_ACTIVE_CONFIRMED +
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
      SELECT
        Id,
        InvoiceTransactionStatus__c,
        SystemIntegrationDate__c,
        PaymentClearingCompletedDate__c
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

  public class LockExemptException extends Exception {
  }
}
