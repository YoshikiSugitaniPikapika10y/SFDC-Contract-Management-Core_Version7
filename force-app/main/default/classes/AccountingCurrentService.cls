public without sharing class AccountingCurrentService {
  /** 仕様: Accounting 第8.2節、第8.7節 */
  public static List<GlJournal__c> load(Id invoiceId) {
    if (invoiceId == null) {
      return new List<GlJournal__c>();
    }
    List<String> fields = new List<String>{
      'Id',
      'Invoice__c',
      'InvoiceLine__c',
      'InvoicePayment__c',
      'InvoicePaymentAllocation__c',
      'GlManualJournalHeader__c',
      'GlManualJournalSetting__c',
      'AccountingEventKey__c',
      'JournalPatternKey__c',
      'DebitSlotKey__c',
      'CreditSlotKey__c',
      'DebitAccountAssignment__c',
      'CreditAccountAssignment__c',
      'DebitAccount__c',
      'CreditAccount__c',
      'Amount__c',
      'PostingDate__c',
      'TransactionStatus__c',
      'IsLocked__c',
      'RecognitionSequence__c',
      'GenerationUnitKey__c',
      'JournalLineKey__c',
      'OriginalJournal__c',
      'BillingAccount__c',
      'BillingAccountKeySnapShot__c'
    };
    for (String copyField : FieldCopyDefinitionService.targetFieldApiNames('GlJournal__c')) {
      if (!fields.contains(copyField)) {
        fields.add(copyField);
      }
    }
    return Database.query(
      'SELECT ' +
        String.join(fields, ',') +
        ' FROM GlJournal__c WHERE Invoice__c = :invoiceId WITH SYSTEM_MODE'
    );
  }
}
