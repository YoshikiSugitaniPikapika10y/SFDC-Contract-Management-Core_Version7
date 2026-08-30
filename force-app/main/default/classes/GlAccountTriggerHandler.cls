public without sharing class GlAccountTriggerHandler {
  /** 仕様: Accounting 第4.1節 */
  public static void beforeDelete(List<GlAccount__c> oldRecords) {
    Set<Id> ids = new Map<Id, GlAccount__c>(oldRecords).keySet();
    Set<Id> referenced = new Set<Id>();
    for (GlJournal__c journal : [
      SELECT DebitAccount__c, CreditAccount__c
      FROM GlJournal__c
      WHERE DebitAccount__c IN :ids OR CreditAccount__c IN :ids
      WITH SYSTEM_MODE
    ]) {
      referenced.add(journal.DebitAccount__c);
      referenced.add(journal.CreditAccount__c);
    }
    for (GlAccountMap__c mapping : [
      SELECT Account__c
      FROM GlAccountMap__c
      WHERE Account__c IN :ids
      WITH SYSTEM_MODE
    ]) {
      referenced.add(mapping.Account__c);
    }
    for (GlManualJournalSetting__c setting : [
      SELECT DebitAccount__c, CreditAccount__c
      FROM GlManualJournalSetting__c
      WHERE DebitAccount__c IN :ids OR CreditAccount__c IN :ids
      WITH SYSTEM_MODE
    ]) {
      referenced.add(setting.DebitAccount__c);
      referenced.add(setting.CreditAccount__c);
    }
    for (GlAccount__c account : oldRecords) {
      if (referenced.contains(account.Id)) {
        account.addError('参照されている勘定科目は削除できません。無効化してください。');
      }
    }
  }
}
