/**
 * 請求正本（Invoice__c）の確定とメモ更新。
 * 確定入口は Loop_11_Can_ConfirmInvoice 必須。
 */
public without sharing class InvoiceOpsController {
  @TestVisible
  private static final String SCOPE_MISMATCH_MESSAGE = '指定された請求が、対象の契約サービスに属していません。画面を開き直してください。';
  @TestVisible
  static Set<Id> lastEstimateMatchQueriedIds = new Set<Id>();

  /** 仕様: Core 第4.3.12節、第7.9.7節。確定の Aura 入口は confirmInvoiceFromPreview。 */
  public static Integer markInvoiced(
    Id contractHistoryId,
    List<Id> invoiceIds,
    Date integrationDate
  ) {
    return markInvoiced(contractHistoryId, invoiceIds, integrationDate, null);
  }

  /** 仕様: Core 第7.9.7節 */
  public static Integer markInvoiced(
    Id contractHistoryId,
    List<Id> invoiceIds,
    Date integrationDate,
    String businessOperationKey
  ) {
    return markInvoiced(
      contractHistoryId,
      invoiceIds,
      integrationDate,
      businessOperationKey,
      null
    );
  }

  /**
   * 仕様: Core 第12.4節、Accounting 第8.2節。
   * 先行ロック済み請求があれば取り直さない。
   */
  public static Integer markInvoiced(
    Id contractHistoryId,
    List<Id> invoiceIds,
    Date integrationDate,
    String businessOperationKey,
    Invoice__c knownLockedInvoice
  ) {
    ContractPermissionUtil.assertConfirmInvoice();
    assertInvoicesInScope(contractHistoryId, invoiceIds, knownLockedInvoice);
    return applyLockDates(
      invoiceIds,
      integrationDate,
      businessOperationKey,
      knownLockedInvoice
    );
  }

  /**
   * 操作対象の請求が、指定した契約履歴と同じ契約サービス配下であることを確認する。
   * 確定権限だけで任意の請求 Id を操作できないようにする。
   */
  /** 仕様: Core 第7.7.3節 */
  public static void assertInvoicesInScope(
    Id contractHistoryId,
    List<Id> invoiceIds
  ) {
    assertInvoicesInScope(contractHistoryId, invoiceIds, null);
  }

  /**
   * 仕様: Core 第7.7.3節、第12.4節。
   * ロック済み請求があれば契約サービス範囲を取り直さない。
   */
  public static void assertInvoicesInScope(
    Id contractHistoryId,
    List<Id> invoiceIds,
    Invoice__c knownLockedInvoice
  ) {
    if (invoiceIds == null || invoiceIds.isEmpty()) {
      return;
    }
    Set<Id> targetIds = new Set<Id>();
    for (Id invoiceId : invoiceIds) {
      if (invoiceId != null) {
        targetIds.add(invoiceId);
      }
    }
    if (targetIds.isEmpty()) {
      return;
    }
    if (
      tryAssertScopeFromLockedInvoice(
        contractHistoryId,
        targetIds,
        knownLockedInvoice
      )
    ) {
      return;
    }
    Id serviceId = resolveContractServiceId(contractHistoryId);
    if (serviceId == null) {
      throw toAuraHandled(SCOPE_MISMATCH_MESSAGE);
    }
    Integer inScope = [
      SELECT COUNT()
      FROM Invoice__c
      WHERE Id IN :targetIds AND ContractService__c = :serviceId
      WITH SYSTEM_MODE
    ];
    if (inScope != targetIds.size()) {
      throw toAuraHandled(SCOPE_MISMATCH_MESSAGE);
    }
  }

  private static Boolean tryAssertScopeFromLockedInvoice(
    Id contractHistoryId,
    Set<Id> targetIds,
    Invoice__c knownLockedInvoice
  ) {
    if (
      knownLockedInvoice == null ||
      knownLockedInvoice.Id == null ||
      targetIds.size() != 1 ||
      !targetIds.contains(knownLockedInvoice.Id)
    ) {
      return false;
    }
    if (
      contractHistoryId == null ||
      knownLockedInvoice.ContractHistory__c != contractHistoryId ||
      knownLockedInvoice.ContractService__c == null
    ) {
      throw toAuraHandled(SCOPE_MISMATCH_MESSAGE);
    }
    return true;
  }

  private static Id resolveContractServiceId(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return null;
    }
    for (ContractHistory__c history : [
      SELECT ContractService__c
      FROM ContractHistory__c
      WHERE Id = :contractHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      return history.ContractService__c;
    }
    return null;
  }

  public static void updateInvoiceMemo(Id invoiceId, String memo) {
    updateInvoiceMemoInternal(invoiceId, memo);
  }

  /** 仕様: Core 第7.7.0節、第7.7.3節。請求書メモはボードの「直す」。権限は編集12。 */
  @AuraEnabled
  public static void updateInvoiceMemo(
    Id invoiceId,
    String memo,
    Id contractHistoryId
  ) {
    assertCanEditInvoiceMemo();
    assertInvoicesInScope(contractHistoryId, new List<Id>{ invoiceId });
    updateInvoiceMemoInternal(invoiceId, memo);
  }

  private static void updateInvoiceMemoInternal(Id invoiceId, String memo) {
    assertCanEditInvoiceMemo();
    if (invoiceId == null) {
      throw toAuraHandled('請求が指定されていません。');
    }
    Invoice__c existing = [
      SELECT Id, InvoiceTransactionStatus__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    // 仕様: Core 第12.2節・第7.7.3節。取消済みは参照だけ。メモ編集の対象外。
    if (InvoiceTransactionStatusService.isCancelled(existing)) {
      throw toAuraHandled('取消済み請求のメモは編集できません。');
    }
    Invoice__c invoice = new Invoice__c(Id = invoiceId, Memo__c = memo);
    try {
      SystemContextAccess.updateRecords(new List<Invoice__c>{ invoice });
    } catch (Exception ex) {
      throw toAuraHandled(ex.getMessage());
    }
    ContractOperationLogService.write(
      'InvoiceMemo',
      null,
      'Invoice__c',
      String.valueOf(invoiceId)
    );
  }

  // 仕様: 共通基盤 第3.2節・第10.4節。請求書メモは 10。
  private static void assertCanEditInvoiceMemo() {
    ContractPermissionUtil.assertEditDraftInvoice();
  }

  private static Boolean hasEstimateMatchFields(Invoice__c invoice) {
    try {
      invoice.get('Amount__c');
      invoice.get('TaxAmount__c');
      invoice.get('TaxPercent__c');
      invoice.get('ContractHistory__c');
      return true;
    } catch (SObjectException ex) {
      return false;
    }
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  /** 仕様: Core 第7.9節、第7.9.1節、第12.4節、日付仕様 第8章 */
  private static Integer applyLockDates(
    List<Id> invoiceIds,
    Date integrationDate,
    String businessOperationKey,
    Invoice__c knownLockedInvoice
  ) {
    if (invoiceIds == null || invoiceIds.isEmpty()) {
      return 0;
    }
    Date value = integrationDate == null
      ? InvoiceTransactionStatusService.organizationToday()
      : integrationDate;
    List<Invoice__c> invoices;
    if (
      knownLockedInvoice != null &&
      invoiceIds.size() == 1 &&
      invoiceIds[0] == knownLockedInvoice.Id
    ) {
      invoices = new List<Invoice__c>{ knownLockedInvoice };
    } else {
      invoices = [
        SELECT
          Id,
          InvoiceDate__c,
          InvoiceTransactionStatus__c,
          DeliveryStatus__c,
          CollectionRefundStatus__c,
          Amount__c,
          TaxAmount__c,
          TaxPercent__c,
          TaxInclusiveAmount__c,
          InvoicePaymentNet__c,
          BillingAccountKeySnapShot__c,
          SystemIntegrationDate__c,
          PaymentClearingCompletedDate__c,
          InvoiceDeliveryMethodSnapShot__c,
          ContractHistory__c
        FROM Invoice__c
        WHERE Id IN :invoiceIds
        WITH SYSTEM_MODE
        ORDER BY Id ASC
      ];
    }

    Integer succeeded = 0;
    List<String> failures = new List<String>();
    for (Invoice__c invoice : invoices) {
      Savepoint sp = Database.setSavepoint();
      try {
        String keyForInvoice = invoices.size() == 1
          ? businessOperationKey
          : null;
        confirmOneInvoice(
          invoice,
          value,
          keyForInvoice,
          knownLockedInvoice != null && invoice.Id == knownLockedInvoice.Id
        );
        succeeded++;
      } catch (Exception ex) {
        Database.rollback(sp);
        failures.add(String.valueOf(invoice.Id) + ': ' + ex.getMessage());
      }
    }
    if (succeeded == 0 && !failures.isEmpty()) {
      throw toAuraHandled(
        '請求は確定できませんでした: ' + String.join(failures, ' / ')
      );
    }
    return succeeded;
  }

  /** 仕様: Accounting 第3.1節、第8.2節、第8.4節、Core 第7.4節、第7.9.7節、第12.4節 */
  private static void confirmOneInvoice(
    Invoice__c invoice,
    Date integrationDate,
    String businessOperationKey,
    Boolean alreadyLocked
  ) {
    if (alreadyLocked != true) {
      AccountingCauseLockService.lockInvoice(invoice.Id);
    }
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      businessOperationKey
    );
    Map<Id, InvoiceLine__c> collected = AccountingGoalService.collectLines(
      invoice.Id
    );
    List<Id> lineIds = new List<Id>(collected.keySet());
    lineIds.sort();
    List<InvoiceLine__c> lines = new List<InvoiceLine__c>();
    for (Id lineId : lineIds) {
      lines.add(collected.get(lineId));
    }
    assertAcceptanceEndDatesPresent(lines);
    assertEstimateTotalsMatch(new List<Invoice__c>{ invoice });
    InvoiceDeliveryMethodService.assertRequiredOnConfirm(invoice);
    GlAccountingPolicyService.freezeOnFirstConfirm();
    InvoiceTransactionStatusService.applyConfirmed(
      new List<Invoice__c>{ invoice },
      integrationDate
    );
    InvoiceTaxAllocationService.allocateOnConfirm(invoice, lines);
    invoice.BusinessOperationKey__c = operationKey;
    Boolean previousStatus = InvoiceTransactionStatusService.allowStatusWrite;
    Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
    InvoiceTransactionStatusService.allowStatusWrite = true;
    InvoiceLockUtil.allowLockedStatusWrite = true;
    try {
      SystemContextAccess.updateRecords(new List<Invoice__c>{ invoice });
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
      InvoiceLockUtil.allowLockedStatusWrite = previousLock;
    }
    AccountingDiffService.applyForInvoice(
      invoice.Id,
      AccountingEventFixedCatalog.BILLING_CONFIRMED.key,
      operationKey,
      null,
      invoice
    );
  }

  /** 仕様: Core 第12.4節。同一処理で収集した明細を取り直さない。 */
  private static void assertAcceptanceEndDatesPresent(
    List<InvoiceLine__c> lines
  ) {
    if (lines == null) {
      return;
    }
    for (InvoiceLine__c line : lines) {
      if (
        ContractMetadataService.normalizeRevenueRecognitionBasis(
          line.RevenueRecognitionBasis__c
        ) == ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME &&
        line.AcceptanceEndDate__c == null
      ) {
        throw new InvoiceOpsException(
          '検収終了日が空の明細があるため確定できません。'
        );
      }
    }
  }

  /** 仕様: Core 第7.9.1節、第12.4節 */
  private static void assertEstimateTotalsMatch(List<Invoice__c> invoices) {
    Set<Id> historyIds = new Set<Id>();
    Set<Id> invoiceIds = new Set<Id>();
    Map<Id, Invoice__c> knownById = new Map<Id, Invoice__c>();
    for (Invoice__c invoice : invoices) {
      if (invoice == null || invoice.Id == null) {
        continue;
      }
      invoiceIds.add(invoice.Id);
      if (invoice.ContractHistory__c != null) {
        historyIds.add(invoice.ContractHistory__c);
      }
      if (hasEstimateMatchFields(invoice)) {
        knownById.put(invoice.Id, invoice);
      }
    }
    if (historyIds.isEmpty() && !invoiceIds.isEmpty()) {
      for (Invoice__c invoice : [
        SELECT ContractHistory__c
        FROM Invoice__c
        WHERE Id IN :invoiceIds
        WITH SYSTEM_MODE
      ]) {
        if (invoice.ContractHistory__c != null) {
          historyIds.add(invoice.ContractHistory__c);
        }
      }
    }
    Map<Id, Decimal> invoiceExclTotals = new Map<Id, Decimal>();
    List<Invoice__c> versionInvoices = new List<Invoice__c>();
    if (!knownById.isEmpty()) {
      versionInvoices.addAll(knownById.values());
    }
    String statusCancelled = InvoiceTransactionStatusService.TX_CANCELLED;
    lastEstimateMatchQueriedIds = new Set<Id>();
    for (Invoice__c invoice : [
      SELECT Id, Amount__c, TaxAmount__c, TaxPercent__c, ContractHistory__c
      FROM Invoice__c
      WHERE
        ContractHistory__c IN :historyIds
        AND InvoiceTransactionStatus__c != :statusCancelled
        AND Id NOT IN :knownById.keySet()
      WITH SYSTEM_MODE
    ]) {
      lastEstimateMatchQueriedIds.add(invoice.Id);
      versionInvoices.add(invoice);
    }
    for (Invoice__c invoice : versionInvoices) {
      if (invoice.Amount__c == null) {
        throw new InvoiceOpsException('請求の税抜金額がありません。');
      }
      if (invoice.TaxAmount__c == null) {
        throw new InvoiceOpsException('請求の税額がありません。');
      }
      Decimal expectedTax;
      try {
        expectedTax = TaxCalculationUtil.calculateTaxAmount(
          invoice.Amount__c,
          TaxCalculationUtil.fromPercentFieldStorage(invoice.TaxPercent__c)
        );
      } catch (TaxCalculationUtil.TaxPercentException ex) {
        throw new InvoiceOpsException(ex.getMessage());
      }
      if (invoice.TaxAmount__c != expectedTax) {
        throw new InvoiceOpsException(
          '請求書の税額が税抜と税率から計算した値と一致しないため確定できません。'
        );
      }
      Id historyId = invoice.ContractHistory__c;
      invoiceExclTotals.put(
        historyId,
        nvl(invoiceExclTotals.get(historyId)) + invoice.Amount__c
      );
    }
    for (ContractHistory__c history : [
      SELECT Id, DeltaAmountSum__c
      FROM ContractHistory__c
      WHERE Id IN :historyIds
      WITH SYSTEM_MODE
    ]) {
      if (
        nvl(history.DeltaAmountSum__c) != nvl(invoiceExclTotals.get(history.Id))
      ) {
        throw new InvoiceOpsException(
          '見積合計と請求合計（税抜）が一致しないため確定できません。'
        );
      }
    }
  }

  private class InvoiceOpsException extends Exception {
  }

  private static AuraHandledException toAuraHandled(String message) {
    String resolved = String.isNotBlank(message)
      ? message
      : '処理中にエラーが発生しました。';
    AuraHandledException ex = new AuraHandledException(resolved);
    ex.setMessage(resolved);
    return ex;
  }
}
