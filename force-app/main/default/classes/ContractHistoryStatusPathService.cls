/**
 * 契約履歴の StatusPath__c を historystatus と請求積み上げから算出・同期する。
 * 画面（Path 含む）からの手動変更は拒否する。
 *
 * Path 本線: Estimate → Ordered → Invoicing → Invoiced → Paid
 * Archive は Path に出さない（StatusPath は null。業務の正は historystatus）。
 */
public without sharing class ContractHistoryStatusPathService {
  public static final String PATH_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  public static final String PATH_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;
  public static final String PATH_INVOICING = ContractDomainConstants.STATUS_PATH_INVOICING;
  public static final String PATH_INVOICED = ContractDomainConstants.STATUS_PATH_INVOICED;
  public static final String PATH_PAID = ContractDomainConstants.STATUS_PATH_PAID;
  public static final String PATH_ARCHIVE = ContractDomainConstants.HISTORY_STATUS_ARCHIVE;

  public static final String MANUAL_CHANGE_BLOCK_MESSAGE = 'ステータスパスは自動更新のみです。パス上からは変更できません。';

  /**
   * 請求の連続 DML（分割・再生成など）中は Path 同期を保留し、終了時に1回だけ流す。
   * 請求トリガごとの親再クエリを抑えて SOQL 101 を防ぐ。
   */
  private static Integer pathSyncDeferDepth = 0;
  private static Set<Id> deferredPathSyncHistoryIds = new Set<Id>();

  public static void beginPathSyncDefer() {
    pathSyncDeferDepth++;
  }

  public static void endPathSyncDefer() {
    if (pathSyncDeferDepth > 0) {
      pathSyncDeferDepth--;
    }
    if (pathSyncDeferDepth == 0 && !deferredPathSyncHistoryIds.isEmpty()) {
      Set<Id> pending = deferredPathSyncHistoryIds;
      deferredPathSyncHistoryIds = new Set<Id>();
      syncForInvoiceParentsNow(pending);
    }
  }

  /**
   * 仕様: Core 第5.7節。before insert/update: 期待値を強制セット。ユーザーが別値へ変えた場合はエラー。
   */
  public static void applyOnBeforeWrite(
    List<ContractHistory__c> newHistories,
    Map<Id, ContractHistory__c> oldMap
  ) {
    if (newHistories == null || newHistories.isEmpty()) {
      return;
    }
    for (ContractHistory__c history : newHistories) {
      if (history == null) {
        continue;
      }
      String expected = resolvePath(history);
      ContractHistory__c prior = oldMap == null ? null : oldMap.get(history.Id);
      if (
        prior != null &&
        history.StatusPath__c != prior.StatusPath__c &&
        history.StatusPath__c != expected
      ) {
        history.addError(MANUAL_CHANGE_BLOCK_MESSAGE);
        continue;
      }
      history.StatusPath__c = expected;
    }
  }

  /**
   * 仕様: Core 第5.7節。請求の作成・更新・削除後に親履歴の StatusPath を再計算する。
   */
  public static void syncForInvoiceParents(Set<Id> contractHistoryIds) {
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return;
    }
    if (pathSyncDeferDepth > 0) {
      deferredPathSyncHistoryIds.addAll(contractHistoryIds);
      return;
    }
    syncForInvoiceParentsNow(contractHistoryIds);
  }

  private static void syncForInvoiceParentsNow(Set<Id> contractHistoryIds) {
    if (contractHistoryIds == null || contractHistoryIds.isEmpty()) {
      return;
    }
    List<ContractHistory__c> histories = [
      SELECT
        Id,
        Type__c,
        historystatus__c,
        StatusPath__c,
        InvoiceCount__c,
        InvoicedCount__c,
        PaidCount__c
      FROM ContractHistory__c
      WHERE Id IN :contractHistoryIds
      WITH SYSTEM_MODE
    ];
    List<ContractHistory__c> toUpdate = new List<ContractHistory__c>();
    for (ContractHistory__c history : histories) {
      String expected = resolvePath(history);
      if (history.StatusPath__c != expected) {
        history.StatusPath__c = expected;
        toUpdate.add(history);
      }
    }
    if (!toUpdate.isEmpty()) {
      SystemContextAccess.updateRecords(toUpdate);
    }
  }

  public static void syncForInvoices(List<Invoice__c> invoices) {
    if (invoices == null || invoices.isEmpty()) {
      return;
    }
    Set<Id> historyIds = new Set<Id>();
    for (Invoice__c invoice : invoices) {
      if (invoice != null && invoice.ContractHistory__c != null) {
        historyIds.add(invoice.ContractHistory__c);
      }
    }
    syncForInvoiceParents(historyIds);
  }

  /** 仕様: Core 第5.7節 */
  public static String resolvePath(ContractHistory__c history) {
    if (history == null) {
      return null;
    }
    return resolvePath(
      history.historystatus__c,
      history.Type__c,
      history.InvoiceCount__c,
      history.InvoicedCount__c,
      history.PaidCount__c
    );
  }

  @TestVisible
  static String resolvePath(
    String historyStatus,
    Decimal invoiceCount,
    Decimal invoicedCount,
    Decimal paidCount
  ) {
    return resolvePath(historyStatus, null, invoiceCount, invoicedCount, paidCount);
  }

  @TestVisible
  static String resolvePath(
    String historyStatus,
    String historyType,
    Decimal invoiceCount,
    Decimal invoicedCount,
    Decimal paidCount
  ) {
    if (historyStatus == PATH_ARCHIVE) {
      // Path 本線外。RT の StatusPath からも外し、バーに出さない。
      return null;
    }
    if (historyStatus == PATH_ESTIMATE) {
      return PATH_ESTIMATE;
    }
    if (historyStatus != PATH_ORDERED) {
      return historyStatus;
    }
    if (historyType == ContractDomainConstants.HISTORY_TYPE_CANCEL) {
      return PATH_ORDERED;
    }

    Decimal invoices = nullToZero(invoiceCount);
    Decimal invoiced = nullToZero(invoicedCount);
    Decimal paid = nullToZero(paidCount);

    if (invoices == 0) {
      return PATH_ORDERED;
    }
    if (invoiced < invoices) {
      return PATH_INVOICING;
    }
    if (paid < invoices) {
      return PATH_INVOICED;
    }
    return PATH_PAID;
  }

  private static Decimal nullToZero(Decimal value) {
    return value == null ? 0 : value;
  }
}
