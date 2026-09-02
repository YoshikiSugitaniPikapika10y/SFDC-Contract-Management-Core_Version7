public without sharing class AccountingCauseLockService {
  public class LockException extends Exception {
  }

  /** 仕様: Core 第7.9.7節、第4.3.12節 */
  public static String issueOperationKey() {
    return EncodingUtil.convertToHex(Crypto.generateAesKey(128));
  }

  /** 仕様: Core 第7.9.7節、第4.3.12節 */
  public static String resolveOrIssueOperationKey(String provided) {
    return String.isBlank(provided) ? issueOperationKey() : provided.trim();
  }

  /** 仕様: Core 第4.3.12節。見積編集・受注・差し戻し・手動Archiveは契約履歴を行ロックする。 */
  public static ContractHistory__c lockHistory(Id historyId) {
    if (historyId == null) {
      throw new LockException('契約履歴が指定されていません。');
    }
    List<ContractHistory__c> histories = [
      SELECT
        Id,
        Type__c,
        historystatus__c,
        Version__c,
        ContractService__c,
        Opportunity__c,
        PreviousHistory__c,
        BusinessOperationKey__c,
        LastModifiedDate,
        CreateRenewOpportunity__c,
        RenewOpportunityRequestCount__c,
        RenewalOpportunity__c
      FROM ContractHistory__c
      WHERE Id = :historyId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (histories.isEmpty()) {
      throw new LockException('契約履歴をロックできませんでした。');
    }
    return histories[0];
  }

  /** 仕様: Core 第3.4.1節、第4.3.12節。契約サービスを編集は対象の契約サービスを行ロックする。 */
  public static ContractService__c lockService(Id serviceId) {
    if (serviceId == null) {
      throw new LockException('契約サービスが指定されていません。');
    }
    List<ContractService__c> services = [
      SELECT
        Id,
        Account__c,
        LastModifiedDate,
        BusinessOperationKey__c
      FROM ContractService__c
      WHERE Id = :serviceId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (services.isEmpty()) {
      throw new LockException('契約サービスをロックできませんでした。');
    }
    return services[0];
  }

  /** 仕様: Accounting 第1.8.1節、第8.2節、Core 第7.9.7節 */
  public static Invoice__c lockInvoice(Id invoiceId) {
    if (invoiceId == null) {
      throw new LockException('請求が指定されていません。');
    }
    Map<Id, Invoice__c> locked = lockInvoices(new Set<Id>{ invoiceId });
    return locked.get(invoiceId);
  }

  /**
   * 仕様: Core 第7.9.7節。書き換える請求を行ロックする。
   * 複数枚は1回の FOR UPDATE で取り、ロック順は Id 昇順。
   */
  public static Map<Id, Invoice__c> lockInvoices(Set<Id> invoiceIds) {
    Map<Id, Invoice__c> locked = new Map<Id, Invoice__c>();
    if (invoiceIds == null || invoiceIds.isEmpty()) {
      throw new LockException('請求が指定されていません。');
    }
    Set<Id> compact = new Set<Id>();
    for (Id invoiceId : invoiceIds) {
      if (invoiceId != null) {
        compact.add(invoiceId);
      }
    }
    if (compact.isEmpty()) {
      throw new LockException('請求が指定されていません。');
    }
    List<Invoice__c> invoices = [
      SELECT
        Id,
        InvoiceDate__c,
        InvoiceTransactionStatus__c,
        TaxInclusiveAmount__c,
        InvoicePaymentNet__c,
        BillingAccountSnapShot__c,
        BillingAccountKeySnapShot__c,
        ContractHistory__c,
        ContractService__c,
        BusinessOperationKey__c,
        DeliveryStatus__c,
        LastModifiedDate
      FROM Invoice__c
      WHERE Id IN :compact
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (invoices.size() != compact.size()) {
      throw new LockException('請求をロックできませんでした。');
    }
    for (Invoice__c invoice : invoices) {
      locked.put(invoice.Id, invoice);
    }
    return locked;
  }

  /** 仕様: Core 第7.9.7節 */
  public static String resolveInvoiceOperationToken(Id invoiceId) {
    return ContractOptimisticLockUtil.toToken(
      resolveInvoiceOperationDatetime(invoiceId)
    );
  }

  /** 仕様: Core 第7.9.7節 */
  public static Datetime resolveInvoiceOperationDatetime(Id invoiceId) {
    if (invoiceId == null) {
      return null;
    }
    return resolveInvoiceOperationDatetimes(new Set<Id>{ invoiceId })
      .get(invoiceId);
  }

  /** 仕様: Core 第7.9.7節 */
  public static Map<Id, Datetime> resolveInvoiceOperationDatetimes(
    Set<Id> invoiceIds
  ) {
    return resolveInvoiceOperationDatetimes(invoiceIds, null);
  }

  /** 仕様: Core 第7.9.7節。請求の LastModified は呼び出し側で渡して再照会しない。 */
  public static Map<Id, Datetime> resolveInvoiceOperationDatetimes(
    Set<Id> invoiceIds,
    Map<Id, Datetime> knownInvoiceModified
  ) {
    Map<Id, Datetime> result = new Map<Id, Datetime>();
    if (invoiceIds == null || invoiceIds.isEmpty()) {
      return result;
    }
    if (knownInvoiceModified != null) {
      result.putAll(knownInvoiceModified);
    } else {
      for (Invoice__c invoice : [
        SELECT Id, LastModifiedDate
        FROM Invoice__c
        WHERE Id IN :invoiceIds
        WITH SYSTEM_MODE
      ]) {
        result.put(invoice.Id, invoice.LastModifiedDate);
      }
    }
    bumpMax(
      result,
      [
        SELECT Invoice__c, MAX(LastModifiedDate) maxLm
        FROM InvoicePayment__c
        WHERE Invoice__c IN :invoiceIds
        WITH SYSTEM_MODE
        GROUP BY Invoice__c
      ]
    );
    bumpMax(
      result,
      [
        SELECT Invoice__c, MAX(LastModifiedDate) maxLm
        FROM GlManualJournalHeader__c
        WHERE Invoice__c IN :invoiceIds
        WITH SYSTEM_MODE
        GROUP BY Invoice__c
      ]
    );
    bumpMax(
      result,
      [
        SELECT Invoice__c, MAX(LastModifiedDate) maxLm
        FROM GlJournal__c
        WHERE Invoice__c IN :invoiceIds
        WITH SYSTEM_MODE
        GROUP BY Invoice__c
      ]
    );
    return result;
  }

  /** 仕様: Core 第7.9.7節 */
  public static void assertInvoiceOperationUnchanged(
    Id invoiceId,
    String expectedToken
  ) {
    Map<Id, String> tokens = new Map<Id, String>();
    tokens.put(invoiceId, expectedToken);
    assertInvoiceOperationsUnchanged(tokens, null);
  }

  /**
   * 仕様: Core 第7.9.7節。版比較の請求・入出金・手動仕訳・仕訳は1回の集合照会。
   */
  public static void assertInvoiceOperationsUnchanged(
    Map<Id, String> expectedTokenByInvoiceId,
    Map<Id, Datetime> knownInvoiceModified
  ) {
    if (expectedTokenByInvoiceId == null || expectedTokenByInvoiceId.isEmpty()) {
      throw ContractOptimisticLockUtil.conflict('請求');
    }
    Set<Id> invoiceIds = new Set<Id>();
    for (Id invoiceId : expectedTokenByInvoiceId.keySet()) {
      if (invoiceId != null) {
        invoiceIds.add(invoiceId);
      }
    }
    if (invoiceIds.isEmpty()) {
      throw ContractOptimisticLockUtil.conflict('請求');
    }
    Map<Id, Datetime> actuals = resolveInvoiceOperationDatetimes(
      invoiceIds,
      knownInvoiceModified
    );
    for (Id invoiceId : invoiceIds) {
      ContractOptimisticLockUtil.assertRequiredUnchanged(
        actuals.get(invoiceId),
        expectedTokenByInvoiceId.get(invoiceId),
        '請求'
      );
    }
  }

  private static void bumpMax(
    Map<Id, Datetime> result,
    List<AggregateResult> rows
  ) {
    for (AggregateResult row : rows) {
      Id invoiceId = (Id) row.get('Invoice__c');
      Datetime value = (Datetime) row.get('maxLm');
      if (invoiceId == null || value == null) {
        continue;
      }
      Datetime current = result.get(invoiceId);
      if (current == null || value.getTime() > current.getTime()) {
        result.put(invoiceId, value);
      }
    }
  }
}
