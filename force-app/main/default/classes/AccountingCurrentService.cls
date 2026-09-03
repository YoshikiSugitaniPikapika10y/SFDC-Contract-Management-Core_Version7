public without sharing class AccountingCurrentService {
  private static Map<Id, List<GlJournal__c>> cachedByInvoiceId = new Map<Id, List<GlJournal__c>>();

  /** 仕様: Accounting 第8.2節。同一請求の Current 再照会を1回にする。 */
  public static void invalidate(Id invoiceId) {
    if (invoiceId != null) {
      cachedByInvoiceId.remove(invoiceId);
    }
  }

  /** 仕様: Accounting 第8.2節、第8.7節 */
  public static List<GlJournal__c> load(Id invoiceId) {
    if (invoiceId == null) {
      return new List<GlJournal__c>();
    }
    if (!cachedByInvoiceId.containsKey(invoiceId)) {
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
      cachedByInvoiceId.put(
        invoiceId,
        Database.query(
          'SELECT ' +
            String.join(fields, ',') +
            ' FROM GlJournal__c WHERE Invoice__c = :invoiceId WITH SYSTEM_MODE'
        )
      );
    }
    return copyOf(cachedByInvoiceId.get(invoiceId));
  }

  /**
   * 仕様: Accounting 第8.2節。preview の Diff 計算がキャッシュ行の取引状態を書き換えない。
   */
  private static List<GlJournal__c> copyOf(List<GlJournal__c> rows) {
    List<GlJournal__c> copy = new List<GlJournal__c>();
    if (rows == null) {
      return copy;
    }
    for (GlJournal__c row : rows) {
      copy.add(row.clone(true, true, true, true));
    }
    return copy;
  }
}
