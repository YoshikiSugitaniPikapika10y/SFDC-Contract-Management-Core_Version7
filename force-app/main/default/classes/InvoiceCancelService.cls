public without sharing class InvoiceCancelService {
  public class CancelException extends Exception {
  }

  public class CancelRequest {
    public Id invoiceId;
    public String cancellationReason;
    public String cancellationReasonText;
    public Date cancellationDate;
    public String businessOperationKey;
    public String expectedToken;
  }

  public class CancelResult {
    public Id cancelledInvoiceId;
    public Id correctionInvoiceId;
    public AccountingDiffService.CancelPreview journalPreview;
    public Boolean requiresCustomerNotice;
    public String businessOperationKey;
  }

  /** 仕様: Core 第7.9.3節、第7.9.6節、第7.10節、日付仕様 第7.3節、Accounting 第8.2節、第8.8節 */
  public static CancelResult cancelConfirmed(CancelRequest request) {
    ContractPermissionUtil.assertCancelInvoice();
    if (request == null || request.invoiceId == null) {
      throw new CancelException('取消する請求が指定されていません。');
    }
    if (String.isBlank(request.cancellationReason)) {
      throw new CancelException('取消理由を入力してください。');
    }
    if (request.cancellationReason == 'Other' && String.isBlank(request.cancellationReasonText)) {
      throw new CancelException('取消理由がその他のときは内容を入力してください。');
    }
    Invoice__c invoice = AccountingCauseLockService.lockInvoice(request.invoiceId);
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      request.businessOperationKey
    );
    if (
      InvoiceTransactionStatusService.isCancelled(invoice) &&
      invoice.BusinessOperationKey__c == operationKey
    ) {
      return existingCancelResult(invoice, request.cancellationDate, operationKey);
    }
    // 仕様: Core 第4.3.12節・第7.9.7節。比較値未指定は拒否。検査省略の互換は持たない。
    AccountingCauseLockService.assertInvoiceOperationUnchanged(
      request.invoiceId,
      request.expectedToken
    );
    if (!InvoiceTransactionStatusService.isConfirmed(invoice)) {
      throw new CancelException('確定済みの請求だけ取消できます。');
    }
    Integer activePayments = [
      SELECT COUNT()
      FROM InvoicePayment__c
      WHERE Invoice__c = :invoice.Id AND PaymentTransactionStatus__c = 'Active'
      WITH SYSTEM_MODE
    ];
    if (activePayments > 0) {
      throw new CancelException('有効な請求入出金がある請求は取消できません。');
    }
    Integer activeManuals = [
      SELECT COUNT()
      FROM GlManualJournalHeader__c
      WHERE Invoice__c = :invoice.Id AND TransactionStatus__c = 'Active'
      WITH SYSTEM_MODE
    ];
    if (activeManuals > 0) {
      throw new CancelException('有効な手動仕訳がある請求は取消できません。');
    }
    Integer lockedJournals = [
      SELECT COUNT()
      FROM GlJournal__c
      WHERE Invoice__c = :invoice.Id AND IsLocked__c = TRUE AND TransactionStatus__c = 'Active'
      WITH SYSTEM_MODE
    ];
    if (lockedJournals > 0 && request.cancellationDate == null) {
      throw new CancelException('ロック済み仕訳がある取消では取消基準日が必要です。');
    }
    AccountingDiffService.CancelPreview journalPreview = previewConfirmed(
      invoice.Id,
      request.cancellationDate
    );
    Invoice__c original = [
      SELECT
        Id,
        ContractService__c,
        ContractHistory__c,
        InvoiceDate__c,
        PaymentScheduledDate__c,
        Amount__c,
        TaxAmount__c,
        TaxPercent__c,
        TaxInclusiveAmount__c,
        BillingAccountSnapShot__c,
        BillingAccountKeySnapShot__c,
        BillingAddresseeSnapShot__c,
        BillingEmailToSnapShot__c,
        BillingEmailCcSnapShot__c,
        BillingEmailBccSnapShot__c,
        InvoiceDeliveryMethodSnapShot__c,
        InvoiceDateMethodSnapShot__c,
        InvoiceDateDayKindSnapShot__c,
        InvoiceDateDayOfMonthSnapShot__c,
        InvoiceDateMonthOffsetSnapShot__c,
        InvoiceDateDayOffsetSnapShot__c,
        InvoiceDateAdjustSnapShot__c,
        PaymentTermMethodSnapShot__c,
        PaymentTermDayKindSnapShot__c,
        PaymentTermDayOfMonthSnapShot__c,
        PaymentTermMonthOffsetSnapShot__c,
        PaymentTermDayOffsetSnapShot__c,
        PaymentTermAdjustSnapShot__c,
        MergeKey__c,
        SourcePeriodLineIds__c,
        PeriodLineAmountTotal__c,
        Memo__c,
        InvoiceTransactionStatus__c,
        IsAmountAdjusted__c,
        IsSplitMoved__c,
        IsManuallyAdjusted__c,
        DeliveryStatus__c,
        BusinessOperationKey__c
      FROM Invoice__c
      WHERE Id = :invoice.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    InvoiceTransactionStatusService.applyCancelled(new List<Invoice__c>{ original });
    // 仕様: Core 第7.9.3節手順5・第7.9.5節。理由は元請求へ保持。取消者・日時は監査項目。
    original.CancellationReason__c = request.cancellationReason;
    original.CancellationReasonText__c = request.cancellationReasonText;
    original.BusinessOperationKey__c = operationKey;
    Boolean previousStatus = InvoiceTransactionStatusService.allowStatusWrite;
    Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
    InvoiceTransactionStatusService.allowStatusWrite = true;
    InvoiceLockUtil.allowLockedStatusWrite = true;
    try {
      SystemContextAccess.updateRecords(new List<Invoice__c>{ original });
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
      InvoiceLockUtil.allowLockedStatusWrite = previousLock;
    }
    Invoice__c correction = original.clone(false, true, false, false);
    // 仕様: Core 第7.9.3節。MergeKeyはコピー対象に無い。Nameは自動採番。
    correction.MergeKey__c = null;
    correction.Name = null;
    correction.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT;
    correction.CollectionRefundStatus__c = null;
    correction.DeliveryStatus__c = null;
    InvoiceTransactionStatusService.seedDefaults(correction);
    correction.SystemIntegrationDate__c = null;
    correction.SentDate__c = null;
    correction.PaymentClearingCompletedDate__c = null;
    correction.InvoicePaymentNet__c = 0;
    correction.PaymentInclusiveTotal__c = 0;
    correction.AppliedTaxRoundingMode__c = null;
    // 仕様: Core 第7.9.3節手順3。取消情報は訂正用へ引き継がない。業務操作キーは手順5で両方へ。
    correction.CancellationReason__c = null;
    correction.CancellationReasonText__c = null;
    // 仕様: Core 第7.9.3節手順3、Accounting 第7.1節。会計タグは引き継がない。
    AccountingTagEvaluationService.clearEnabledTagTargets(correction);
    InvoiceTransactionStatusService.allowStatusWrite = true;
    InvoiceLockUtil.allowLockedStatusWrite = true;
    try {
      insert correction;
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
      InvoiceLockUtil.allowLockedStatusWrite = previousLock;
    }
    List<InvoiceLine__c> copies = new List<InvoiceLine__c>();
    for (InvoiceLine__c line : [
      SELECT
        Id,
        ContractProduct__c,
        Product__c,
        ProductName__c,
        ProductCodeSnapShot__c,
        Quantity__c,
        Unit__c,
        UnitPrice__c,
        Amount__c,
        PeriodLabel__c,
        ServicePeriodStartDate__c,
        ServicePeriodEndDate__c,
        AcceptanceEndDate__c,
        RevenueRecognitionBasis__c,
        LineMergeKey__c,
        SourcePeriodLineIds__c,
        HistoryVersionLabel__c,
        IsSplitMoved__c,
        IsManuallyAdjusted__c,
        IsAmountAdjusted__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :original.Id
      WITH SYSTEM_MODE
    ]) {
      InvoiceLine__c copy = line.clone(false, true, false, false);
      copy.Invoice__c = correction.Id;
      copy.AllocatedTaxAmount__c = null;
      copies.add(copy);
    }
    if (!copies.isEmpty()) {
      insert copies;
    }
    AccountingDiffService.applyForInvoice(
      original.Id,
      AccountingEventFixedCatalog.BILLING_CANCELLED.key,
      operationKey,
      request.cancellationDate
    );
    ContractOperationLogService.write(
      'CancelInvoice',
      operationKey,
      'Invoice__c',
      String.valueOf(original.Id),
      request.cancellationReason,
      request.cancellationReasonText,
      null,
      null
    );
    CancelResult result = new CancelResult();
    result.cancelledInvoiceId = original.Id;
    result.correctionInvoiceId = correction.Id;
    result.journalPreview = journalPreview;
    result.businessOperationKey = operationKey;
    result.requiresCustomerNotice = InvoiceTransactionStatusService.DELIVERY_SENT.equals(
      original.DeliveryStatus__c
    );
    return result;
  }

  /** 仕様: Core 第7.9.6節、Accounting 第8.5節、日付仕様 第7.3節、共通基盤 第10.4節 */
  public static AccountingDiffService.CancelPreview previewConfirmed(
    Id invoiceId,
    Date cancellationDate
  ) {
    ContractPermissionUtil.assertCancelInvoice();
    if (invoiceId == null) {
      throw new CancelException('取消する請求が指定されていません。');
    }
    return AccountingDiffService.previewCancel(
      invoiceId,
      AccountingEventFixedCatalog.BILLING_CANCELLED.key,
      cancellationDate,
      null,
      null
    );
  }

  /** 仕様: Core 第7.9.3節、第7.9.7節 */
  private static CancelResult existingCancelResult(
    Invoice__c original,
    Date cancellationDate,
    String operationKey
  ) {
    List<Invoice__c> corrections = [
      SELECT Id, DeliveryStatus__c
      FROM Invoice__c
      WHERE
        BusinessOperationKey__c = :operationKey
        AND Id != :original.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    CancelResult result = new CancelResult();
    result.cancelledInvoiceId = original.Id;
    result.correctionInvoiceId = corrections.isEmpty()
      ? null
      : corrections[0].Id;
    result.journalPreview = previewConfirmed(original.Id, cancellationDate);
    result.businessOperationKey = operationKey;
    result.requiresCustomerNotice = InvoiceTransactionStatusService.DELIVERY_SENT.equals(
      original.DeliveryStatus__c
    );
    return result;
  }
}
