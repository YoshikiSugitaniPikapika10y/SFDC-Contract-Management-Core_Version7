public without sharing class GlJournalTriggerHandler {
  public static Boolean allowEngineWrite;

  /** 仕様: Accounting 第9.5節 */
  public static void beforeUpdate(
    List<GlJournal__c> newRecords,
    Map<Id, GlJournal__c> oldMap
  ) {
    if (allowEngineWrite == true) {
      return;
    }
    for (GlJournal__c row : newRecords) {
      GlJournal__c previous = oldMap.get(row.Id);
      if (JournalLockService.allowLockWrite == true) {
        if (
          changed(previous.Amount__c, row.Amount__c) ||
          changed(previous.PostingDate__c, row.PostingDate__c) ||
          changed(previous.DebitSlotKey__c, row.DebitSlotKey__c) ||
          changed(previous.CreditSlotKey__c, row.CreditSlotKey__c) ||
          changed(previous.DebitAccount__c, row.DebitAccount__c) ||
          changed(previous.CreditAccount__c, row.CreditAccount__c) ||
          changed(previous.DebitAccountAssignment__c, row.DebitAccountAssignment__c) ||
          changed(previous.CreditAccountAssignment__c, row.CreditAccountAssignment__c) ||
          changed(previous.TransactionStatus__c, row.TransactionStatus__c)
        ) {
          row.addError('Lock/Unlockはロック状態以外を変更できません。');
        }
        continue;
      }
      if (changed(previous.IsLocked__c, row.IsLocked__c)) {
        row.addError('ロック状態は専用処理以外から変更できません。');
      }
      if (changed(previous.TransactionStatus__c, row.TransactionStatus__c)) {
        row.addError('仕訳の取引状態は専用処理以外から変更できません。');
      }
      if (
        changed(previous.Amount__c, row.Amount__c) ||
        changed(previous.PostingDate__c, row.PostingDate__c) ||
        changed(previous.DebitSlotKey__c, row.DebitSlotKey__c) ||
        changed(previous.CreditSlotKey__c, row.CreditSlotKey__c) ||
        changed(previous.DebitAccount__c, row.DebitAccount__c) ||
        changed(previous.CreditAccount__c, row.CreditAccount__c) ||
        changed(previous.DebitAccountAssignment__c, row.DebitAccountAssignment__c) ||
        changed(previous.CreditAccountAssignment__c, row.CreditAccountAssignment__c)
      ) {
        row.addError('仕訳の金額・科目・日付・借貸は変更できません。');
        continue;
      }
      try {
        // 仕様: Core 第11.4.4節、第11.6節、Accounting 第9.5節。
        JournalLockService.assertExemptUpdate(previous, row);
      } catch (JournalLockService.LockException ex) {
        row.addError(ex.getMessage());
      }
    }
  }

  /** 仕様: Accounting 第2.5節、共通基盤 第3.6節。物理削除は 103／104（hasDeleteRecords。104 は 103 を含む）。 */
  public static void beforeDelete(List<GlJournal__c> oldRecords) {
    if (ContractPermissionUtil.hasDeleteRecords()) {
      return;
    }
    for (GlJournal__c row : oldRecords) {
      row.addError('仕訳は物理削除できません。');
    }
  }

  private static Boolean changed(Object left, Object right) {
    return left != right;
  }
}
