public without sharing class AccountingCurrentService {
  private static Map<Id, List<GlJournal__c>> cachedByInvoiceId = new Map<Id, List<GlJournal__c>>();
  @TestVisible
  static Integer currentLoadSelectCount = 0;
  @TestVisible
  static Set<Id> lastLoadExcludedIds = new Set<Id>();

  /** 仕様: Accounting 第8.2節。同一請求の Current 再照会を1回にする。 */
  public static void invalidate(Id invoiceId) {
    if (invoiceId != null) {
      cachedByInvoiceId.remove(invoiceId);
    }
  }

  /**
   * 仕様: Accounting 第8.2節。
   * Diff保存後の仕訳はメモリ上の収集結果で置き、Currentを取り直さない。
   */
  public static void replace(Id invoiceId, List<GlJournal__c> rows) {
    if (invoiceId == null) {
      return;
    }
    cachedByInvoiceId.put(invoiceId, copyOf(rows));
  }

  /** 仕様: Accounting 第8.2節、第8.5節。収集済みCurrentから Active かつ Lock を見る。 */
  public static Boolean hasActiveLocked(Id invoiceId) {
    if (invoiceId == null) {
      return false;
    }
    for (GlJournal__c journal : load(invoiceId)) {
      if (journal.IsLocked__c == true && journal.TransactionStatus__c == 'Active') {
        return true;
      }
    }
    return false;
  }

  /** 仕様: Accounting 第8.2節、第8.7節 */
  public static List<GlJournal__c> load(Id invoiceId) {
    return load(invoiceId, null);
  }

  /**
   * 仕様: Core 第12.4節・第7.9.7節。行ロック済み仕訳は Current で取り直さない。
   * 更新日時が載っている行だけ除外する。未取得分の SELECT は残す。
   */
  public static List<GlJournal__c> load(
    Id invoiceId,
    List<GlJournal__c> knownJournals
  ) {
    lastLoadExcludedIds = new Set<Id>();
    if (invoiceId == null) {
      return new List<GlJournal__c>();
    }
    if (!cachedByInvoiceId.containsKey(invoiceId)) {
      Map<Id, GlJournal__c> knownById = knownJournalsByInvoice(
        invoiceId,
        knownJournals
      );
      lastLoadExcludedIds.addAll(knownById.keySet());
      Set<Id> knownIds = knownById.keySet();
      currentLoadSelectCount++;
      List<String> fields = currentFieldApiNames();
      String soql =
        'SELECT ' +
        String.join(fields, ',') +
        ' FROM GlJournal__c WHERE Invoice__c = :invoiceId';
      if (!knownIds.isEmpty()) {
        soql += ' AND Id NOT IN :knownIds';
      }
      soql += ' WITH SYSTEM_MODE';
      List<GlJournal__c> loaded = Database.query(soql);
      List<GlJournal__c> merged = new List<GlJournal__c>();
      merged.addAll(loaded);
      merged.addAll(knownById.values());
      cachedByInvoiceId.put(invoiceId, merged);
    }
    return copyOf(cachedByInvoiceId.get(invoiceId));
  }

  private static Map<Id, GlJournal__c> knownJournalsByInvoice(
    Id invoiceId,
    List<GlJournal__c> knownJournals
  ) {
    Map<Id, GlJournal__c> knownById = new Map<Id, GlJournal__c>();
    if (knownJournals == null) {
      return knownById;
    }
    for (GlJournal__c journal : knownJournals) {
      if (journal == null || journal.Id == null) {
        continue;
      }
      if (journal.Invoice__c != null && journal.Invoice__c != invoiceId) {
        continue;
      }
      if (journal.LastModifiedDate == null) {
        continue;
      }
      knownById.put(journal.Id, journal);
    }
    return knownById;
  }

  private static List<String> currentFieldApiNames() {
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
      'LastModifiedDate',
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
    return fields;
  }

  /** 仕様: Accounting 第8.2節。版比較は収集済みCurrentの更新日時を使う。 */
  public static Boolean hasLoaded(Id invoiceId) {
    return invoiceId != null && cachedByInvoiceId.containsKey(invoiceId);
  }

  public static Boolean hasLoadedAll(Set<Id> invoiceIds) {
    if (invoiceIds == null || invoiceIds.isEmpty()) {
      return false;
    }
    for (Id invoiceId : invoiceIds) {
      if (!hasLoaded(invoiceId)) {
        return false;
      }
    }
    return true;
  }

  public static Datetime maxLastModified(Id invoiceId) {
    Datetime latest = null;
    if (!hasLoaded(invoiceId)) {
      return latest;
    }
    for (GlJournal__c journal : cachedByInvoiceId.get(invoiceId)) {
      if (journal == null || journal.LastModifiedDate == null) {
        continue;
      }
      if (latest == null || journal.LastModifiedDate.getTime() > latest.getTime()) {
        latest = journal.LastModifiedDate;
      }
    }
    return latest;
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
