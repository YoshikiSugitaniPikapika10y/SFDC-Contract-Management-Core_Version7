public without sharing class JournalLockService {
  public class LockException extends Exception {
  }

  public static Boolean allowLockWrite;

  /** 仕様: Accounting 第9.5節、Core 第7.7.3節 */
  public static Integer lockForInvoice(Id invoiceId, List<Id> journalIds) {
    return lockForInvoice(invoiceId, journalIds, null, null);
  }

  /** 仕様: Accounting 第9.5節、Core 第7.7.3節、第7.9.7節 */
  public static Integer lockForInvoice(
    Id invoiceId,
    List<Id> journalIds,
    String expectedToken,
    String businessOperationKey
  ) {
    return setLocked(invoiceId, journalIds, true, null, expectedToken, businessOperationKey);
  }

  /** 仕様: Accounting 第9.5節、第9.1節、Core 第7.7.3節、第1.1.10節 */
  public static Integer unlockForInvoice(
    Id invoiceId,
    List<Id> journalIds,
    String reason
  ) {
    return unlockForInvoice(invoiceId, journalIds, reason, null, null);
  }

  /** 仕様: Accounting 第9.5節、第9.1節、Core 第7.7.3節、第7.9.7節、第1.1.10節 */
  public static Integer unlockForInvoice(
    Id invoiceId,
    List<Id> journalIds,
    String reason,
    String expectedToken,
    String businessOperationKey
  ) {
    if (String.isBlank(reason)) {
      throw new LockException('Unlockには理由が必要です。');
    }
    if (reason.length() > 255) {
      throw new LockException('Unlock理由は255文字以内で指定してください。');
    }
    return setLocked(
      invoiceId,
      journalIds,
      false,
      reason,
      expectedToken,
      businessOperationKey
    );
  }

  private static Integer setLocked(
    Id invoiceId,
    List<Id> journalIds,
    Boolean locked,
    String reason,
    String expectedToken,
    String businessOperationKey
  ) {
    if (invoiceId == null) {
      throw new LockException('請求が指定されていません。');
    }
    Invoice__c invoice = [
      SELECT Id, InvoiceTransactionStatus__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    // 仕様: Core 第12.2節・第7.7.3節。取消済み請求は通常操作の対象外。仕訳閲覧は可。
    if (InvoiceTransactionStatusService.isCancelled(invoice)) {
      throw new LockException('取消済み請求の仕訳はLock/Unlockできません。');
    }
    AccountingCauseLockService.lockInvoice(invoiceId);
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      businessOperationKey
    );
    GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
    if (policy.AccountingEnabled__c != true) {
      throw new LockException('AccountingがOFFのときはLock/Unlockできません。');
    }
    Set<Id> selected = new Set<Id>();
    if (journalIds != null) {
      for (Id journalId : journalIds) {
        if (journalId != null) {
          selected.add(journalId);
        }
      }
    }
    if (selected.isEmpty()) {
      throw new LockException(
        locked
          ? 'Lockする仕訳を選んでください。'
          : 'Unlockする仕訳を選んでください。'
      );
    }
    List<GlJournal__c> journals = [
      SELECT
        Id,
        Invoice__c,
        IsLocked__c,
        BusinessOperationKey__c,
        UnlockReason__c,
        TransactionStatus__c
      FROM GlJournal__c
      WHERE Id IN :selected AND Invoice__c = :invoiceId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (journals.size() != selected.size()) {
      throw new LockException('この請求以外の仕訳はLock/Unlockできません。');
    }
    // 仕様: Accounting 第2.3節・第2.5節・第9.5節。手動Lock／Unlockは有効仕訳だけ。
    for (GlJournal__c journal : journals) {
      if (journal.TransactionStatus__c != 'Active') {
        throw new LockException('有効な仕訳だけをLock/Unlockできます。');
      }
    }
    List<GlJournal__c> updates = new List<GlJournal__c>();
    Boolean allAlreadyApplied = true;
    for (GlJournal__c journal : journals) {
      // 仕様: Accounting 第9.5節。再Unlockは理由を上書き。LockではUnlockReasonを消さない。
      Boolean reasonNeedsUpdate =
        !locked && journal.UnlockReason__c != reason;
      if (
        journal.IsLocked__c == locked &&
        journal.BusinessOperationKey__c == operationKey &&
        !reasonNeedsUpdate
      ) {
        continue;
      }
      allAlreadyApplied = false;
      if (journal.IsLocked__c != locked) {
        journal.IsLocked__c = locked;
      }
      journal.BusinessOperationKey__c = operationKey;
      if (!locked) {
        journal.UnlockReason__c = reason;
      }
      updates.add(journal);
    }
    if (allAlreadyApplied) {
      writeLockLog(locked, operationKey, journals, reason);
      return journals.size();
    }
    // 仕様: Core 第4.3.12節・第7.9.7節。比較値未指定は拒否。検査省略の互換は持たない。
    AccountingCauseLockService.assertInvoiceOperationUnchanged(
      invoiceId,
      expectedToken
    );
    if (updates.isEmpty()) {
      return 0;
    }
    Boolean previous = allowLockWrite;
    allowLockWrite = true;
    try {
      update updates;
    } finally {
      allowLockWrite = previous;
    }
    writeLockLog(locked, operationKey, journals, reason);
    return updates.size();
  }

  public static Boolean suppressLockLog;

  /** 仕様: 共通基盤.md 第12章。Lock／Unlockで仕訳が複数なら主対象は空。 */
  public static void writeLockLog(
    Boolean locked,
    String operationKey,
    List<GlJournal__c> journals,
    String reason
  ) {
    if (suppressLockLog == true) {
      return;
    }
    String targetObject = journals != null && journals.size() == 1
      ? 'GlJournal__c'
      : null;
    String targetId = journals != null && journals.size() == 1
      ? String.valueOf(journals[0].Id)
      : null;
    ContractOperationLogService.write(
      locked == true ? 'LockJournal' : 'UnlockJournal',
      operationKey,
      targetObject,
      targetId,
      null,
      null,
      locked == true ? null : reason,
      null
    );
  }

  /** 仕様: Core 第11.6節。インストール時シード。実行時の空欄代替には使わない。 */
  public static final String SEED_LOCK_EXEMPT_FIELDS = 'Memo__c';

  public static final String MISSING_LOCK_EXEMPT_MESSAGE =
    '仕訳ロック除外項目の組織設定が無い、または空です。';

  public static final String NEVER_EXEMPT_MESSAGE =
    '仕訳の金額・科目・日付・借貸は変更できません。';

  public static final String LOCKED_NOT_EXEMPT_MESSAGE =
    'Lock済み仕訳は、仕訳ロック除外項目以外を更新できません。';

  public static final String UNLOCKED_NOT_SCREEN_MESSAGE =
    '未Lockの仕訳は、画面定義の追加項目以外を更新できません。';

  private static final Set<String> NEVER_EXEMPT = new Set<String>{
    'Amount__c',
    'PostingDate__c',
    'DebitSlotKey__c',
    'CreditSlotKey__c',
    'DebitAccount__c',
    'CreditAccount__c',
    'DebitAccountAssignment__c',
    'CreditAccountAssignment__c'
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

  /** 仕様: Core 第1.1.10節、第11.6節。無い・空はシードへ落とさずエラー。 */
  public static Set<String> resolveLockExemptFieldNames() {
    String raw = testLockExemptFieldApiNames;
    if (raw == null) {
      GlJournalLockExemptFields__c setting = GlJournalLockExemptFields__c.getOrgDefaults();
      if (setting == null || setting.Id == null) {
        throw new LockException(MISSING_LOCK_EXEMPT_MESSAGE);
      }
      raw = setting.FieldApiNames__c;
    }
    if (String.isBlank(raw)) {
      throw new LockException(MISSING_LOCK_EXEMPT_MESSAGE);
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
      throw new LockException(MISSING_LOCK_EXEMPT_MESSAGE);
    }
    return names;
  }

  /**
   * 仕様: Core 第11.4.4節、第11.6節、Accounting 第9.5節。
   * 未Lockは画面定義の追加項目（メモ含む）。Lock後は除外一覧だけ。金額・科目・日付は一覧に書いても不可。
   */
  public static void assertExemptUpdate(
    GlJournal__c prior,
    GlJournal__c current
  ) {
    if (prior == null || current == null) {
      throw new LockException(LOCKED_NOT_EXEMPT_MESSAGE);
    }
    Boolean locked = prior.IsLocked__c == true;
    Set<String> allowed = locked
      ? resolveLockExemptFieldNames()
      : unlockedAllowedFieldNames();
    Map<String, Schema.SObjectField> fieldMap = GlJournal__c.SObjectType.getDescribe()
      .fields.getMap();
    for (String apiName : fieldMap.keySet()) {
      if (IGNORED_FIELD_NAMES.contains(apiName)) {
        continue;
      }
      Schema.SObjectField token = fieldMap.get(apiName);
      if (token == null || !current.isSet(token)) {
        continue;
      }
      if (valuesEqual(prior.get(token), current.get(token))) {
        continue;
      }
      String fieldName = token.getDescribe().getName();
      if (NEVER_EXEMPT.contains(fieldName) || NEVER_EXEMPT.contains(apiName)) {
        throw new LockException(NEVER_EXEMPT_MESSAGE);
      }
      if (
        fieldName == 'IsLocked__c' ||
        apiName == 'islocked__c' ||
        fieldName == 'TransactionStatus__c' ||
        apiName == 'transactionstatus__c'
      ) {
        continue;
      }
      if (!allowed.contains(fieldName) && !allowed.contains(apiName)) {
        throw new LockException(
          locked ? LOCKED_NOT_EXEMPT_MESSAGE : UNLOCKED_NOT_SCREEN_MESSAGE
        );
      }
    }
  }

  private static Set<String> unlockedAllowedFieldNames() {
    Set<String> names = InvoiceOpsFieldService.journalScreenFieldApiNames();
    names.add('Memo__c');
    return names;
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
