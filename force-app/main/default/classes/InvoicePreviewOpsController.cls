/**
 * 請求プレビュー向けの入出金入口。正本は InvoicePaymentService。
 */
public without sharing class InvoicePreviewOpsController {
  public class InvoicePreviewOpsException extends Exception {
  }

  public class OpsBundleDto {
    @AuraEnabled
    public Id invoiceId;
    @AuraEnabled
    public String invoiceTransactionStatus;
    @AuraEnabled
    public Date invoiceDate;
    @AuraEnabled
    public Date sentDate;
    @AuraEnabled
    public Decimal taxInclusiveAmount;
    @AuraEnabled
    public Decimal paymentNetTotal;
    @AuraEnabled
    public Decimal invoicePaymentNet;
    @AuraEnabled
    public Boolean accountingEnabled;
    @AuraEnabled
    public Boolean paymentAllowed;
    @AuraEnabled
    public String paymentBlockedReason;
    @AuraEnabled
    public List<PaymentLineRemainingDto> paymentLines;
    @AuraEnabled
    public List<PaymentRowDto> payments;
    @AuraEnabled
    public List<JournalRowDto> journals;
    @AuraEnabled
    public List<TagResultRowDto> tagResults;
    @AuraEnabled
    public List<ManualJournalRowDto> manualJournals;
    @AuraEnabled
    public List<ManualSettingRowDto> manualSettings;
    @AuraEnabled
    public Boolean hasLockedJournals;
    @AuraEnabled
    public Boolean hasUnlockedJournals;
    @AuraEnabled
    public String invoiceToken;
  }

  public class JournalRowDto {
    @AuraEnabled
    public Id journalId;
    @AuraEnabled
    public String eventKey;
    @AuraEnabled
    public String eventName;
    @AuraEnabled
    public String patternKey;
    @AuraEnabled
    public String debitSlotKey;
    @AuraEnabled
    public String creditSlotKey;
    @AuraEnabled
    public String debitAccountName;
    @AuraEnabled
    public String creditAccountName;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Date postingDate;
    @AuraEnabled
    public String transactionStatus;
    @AuraEnabled
    public Boolean isLocked;
    @AuraEnabled
    public String memo;
    /** 仕様: Accounting 第9.1.1節。行トグル展開で出す。 */
    @AuraEnabled
    public String confirmationText;
    /** 仕様: Core 第11.4.4節。 */
    @AuraEnabled
    public Map<String, Object> extraFieldValues;
  }

  public class TagResultRowDto {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String fieldApiName;
    @AuraEnabled
    public Boolean value;
  }

  public class ManualJournalRowDto {
    @AuraEnabled
    public Id headerId;
    @AuraEnabled
    public String settingName;
    @AuraEnabled
    public Date postingDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String transactionStatus;
    @AuraEnabled
    public String transactionStatusLabel;
    @AuraEnabled
    public Boolean canCancel;
    @AuraEnabled
    public Boolean hasLockedJournals;
  }

  public class ManualSettingRowDto {
    @AuraEnabled
    public Id settingId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String description;
  }

  public class PaymentLineRemainingDto {
    @AuraEnabled
    public Id lineId;
    @AuraEnabled
    public String productName;
    @AuraEnabled
    public Decimal remainingInclusive;
  }

  public class AllocationInputDto {
    @AuraEnabled
    public Id invoiceLineId;
    @AuraEnabled
    public Decimal amount;
  }

  public class PaymentRowDto {
    @AuraEnabled
    public Id paymentId;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal displayAmount;
    @AuraEnabled
    public String paymentPurpose;
    @AuraEnabled
    public Date paymentDate;
    @AuraEnabled
    public String memo;
    @AuraEnabled
    public Boolean isCancellation;
    @AuraEnabled
    public Boolean isCancelled;
    @AuraEnabled
    public Boolean canCancel;
    @AuraEnabled
    public String paymentTransactionStatus;
    @AuraEnabled
    public String lastModifiedToken;
    /** 仕様: Core 第11.4.4節。 */
    @AuraEnabled
    public Map<String, Object> extraFieldValues;
  }

  /** 仕様: Core 第7.7.3節 */
  @AuraEnabled
  public static OpsBundleDto getOpsBundle(Id invoiceId, Id contractHistoryId) {
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId }
    );
    return getOpsBundle(invoiceId);
  }

  /** 仕様: Core 第7.7.3節、第7.10節。専用の保存済みPDF一覧は返さない。閲覧は「PDFを見る」。 */
  public static OpsBundleDto getOpsBundle(Id invoiceId) {
    ContractPermissionUtil.assertViewInvoicePreview();
    if (invoiceId == null) {
      throw handled('請求が指定されていません。');
    }
    Invoice__c invoice = [
      SELECT
        Id,
        InvoiceTransactionStatus__c,
        InvoiceDate__c,
        SentDate__c,
        Amount__c,
        TaxAmount__c,
        TaxInclusiveAmount__c,
        PaymentInclusiveTotal__c,
        InvoicePaymentNet__c,
        LastModifiedDate
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    OpsBundleDto bundle = new OpsBundleDto();
    bundle.invoiceId = invoice.Id;
    bundle.invoiceTransactionStatus = invoice.InvoiceTransactionStatus__c;
    bundle.invoiceDate = invoice.InvoiceDate__c;
    bundle.sentDate = invoice.SentDate__c;
    bundle.taxInclusiveAmount = InvoiceTransactionStatusService.resolveTaxInclusive(
      invoice
    );
    bundle.paymentNetTotal = nvl(invoice.PaymentInclusiveTotal__c);
    bundle.invoicePaymentNet = nvl(invoice.InvoicePaymentNet__c);
    bundle.accountingEnabled = resolveAccountingEnabled();
    Boolean confirmed = InvoiceTransactionStatusService.isConfirmed(invoice);
    Boolean cancelled = InvoiceTransactionStatusService.isCancelled(invoice);
    bundle.paymentAllowed = confirmed && !cancelled;
    if (cancelled) {
      bundle.paymentBlockedReason = '取消済みの請求に入出金は登録できません。';
    } else if (!confirmed) {
      bundle.paymentBlockedReason = '請求を確定してから入金できます。';
    }
    bundle.invoiceToken = AccountingCauseLockService.resolveInvoiceOperationToken(
      invoice.Id
    );
    bundle.paymentLines = loadPaymentLines(invoice.Id);
    bundle.payments = loadPayments(invoice.Id);
    bundle.journals = loadJournals(invoice.Id);
    bundle.tagResults = loadTagResults(invoice.Id);
    bundle.manualJournals = loadManualJournals(invoice.Id);
    bundle.manualSettings = loadManualSettings();
    bundle.hasLockedJournals = false;
    bundle.hasUnlockedJournals = false;
    // 仕様: Core 第7.9.6節。取消基準日は有効かつLock済みだけ。
    for (JournalRowDto journal : bundle.journals) {
      if (journal.isLocked == true && journal.transactionStatus == 'Active') {
        bundle.hasLockedJournals = true;
      } else if (journal.isLocked != true) {
        bundle.hasUnlockedJournals = true;
      }
    }
    return bundle;
  }

  /** 仕様: Core 第7.9.7節 */
  @AuraEnabled
  public static String issueInvoiceOperationKey() {
    ContractPermissionUtil.assertInvoiceOperationKey();
    return AccountingCauseLockService.issueOperationKey();
  }

  /** 仕様: Accounting 第9.5節、Core 第7.7.3節 */
  public static Integer lockJournalsForInvoice(Id invoiceId, List<Id> journalIds) {
    return lockJournalsForInvoice(invoiceId, journalIds, null, null);
  }

  /** 仕様: Accounting 第9.5節、Core 第7.7.3節、第7.9.7節 */
  @AuraEnabled
  public static Integer lockJournalsForInvoice(
    Id invoiceId,
    List<Id> journalIds,
    String expectedToken,
    String businessOperationKey
  ) {
    ContractPermissionUtil.assertLockJournal();
    try {
      return JournalLockService.lockForInvoice(
        invoiceId,
        journalIds,
        expectedToken,
        businessOperationKey
      );
    } catch (Exception ex) {
      throw handled(ex.getMessage());
    }
  }

  public static Integer unlockJournalsForInvoice(
    Id invoiceId,
    List<Id> journalIds,
    String reason
  ) {
    return unlockJournalsForInvoice(invoiceId, journalIds, reason, null, null);
  }

  /** 仕様: Accounting 第9.5節、Core 第7.7.3節、第7.9.7節 */
  @AuraEnabled
  public static Integer unlockJournalsForInvoice(
    Id invoiceId,
    List<Id> journalIds,
    String reason,
    String expectedToken,
    String businessOperationKey
  ) {
    ContractPermissionUtil.assertUnlockJournal();
    try {
      return JournalLockService.unlockForInvoice(
        invoiceId,
        journalIds,
        reason,
        expectedToken,
        businessOperationKey
      );
    } catch (Exception ex) {
      throw handled(ex.getMessage());
    }
  }

  /** 仕様: Core 第7.7.3節、Accounting 第9.1節 */
  public static void updateJournalMemo(Id journalId, String memo) {
    updateJournalMemoInternal(journalId, memo);
  }

  /** 仕様: Core 第7.7.0節、第7.7.3節、第12.2節、Accounting 第9.1節・第9.5節。仕訳メモはボードの「直す」。権限は編集12。取消済み請求は参照だけ。 */
  public static void updateJournalMemo(
    Id journalId,
    String memo,
    Id invoiceId
  ) {
    updateJournalMemo(journalId, memo, invoiceId, null);
  }

  @AuraEnabled
  public static void updateJournalMemo(
    Id journalId,
    String memo,
    Id invoiceId,
    Map<String, Object> extraFieldValues
  ) {
    assertCanEditJournalMemo();
    if (journalId == null || invoiceId == null) {
      throw handled('仕訳が指定されていません。');
    }
    GlJournal__c journal = [
      SELECT Id, Invoice__c, Invoice__r.InvoiceTransactionStatus__c, IsLocked__c
      FROM GlJournal__c
      WHERE Id = :journalId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (journal.Invoice__c != invoiceId) {
      throw handled('この請求以外の仕訳のメモは保存できません。');
    }
    if (InvoiceTransactionStatusService.isCancelled(journal.Invoice__r)) {
      throw handled('取消済み請求の仕訳メモは編集できません。');
    }
    updateJournalMemoInternal(journalId, memo, extraFieldValues, journal.IsLocked__c == true);
  }

  private static void updateJournalMemoInternal(
    Id journalId,
    String memo
  ) {
    updateJournalMemoInternal(journalId, memo, null, false);
  }

  /** 仕様: Core 第11.4.4節、Accounting 第9.5節。行保存は操作キー・版なし。 */
  private static void updateJournalMemoInternal(
    Id journalId,
    String memo,
    Map<String, Object> extraFieldValues,
    Boolean locked
  ) {
    assertCanEditJournalMemo();
    if (journalId == null) {
      throw handled('仕訳が指定されていません。');
    }
    try {
      GlJournal__c row = new GlJournal__c(Id = journalId, Memo__c = memo);
      Set<String> allowed = locked
        ? JournalLockService.resolveLockExemptFieldNames()
        : InvoiceOpsFieldService.journalScreenFieldApiNames();
      allowed.add('Memo__c');
      InvoiceOpsFieldService.applyDisplayedValues(
        row,
        'GlJournal__c',
        extraFieldValues,
        allowed
      );
      update row;
    } catch (Exception ex) {
      throw handled(ex.getMessage());
    }
    ContractOperationLogService.write(
      'JournalMemo',
      null,
      'GlJournal__c',
      String.valueOf(journalId)
    );
  }

  // 仕様: 共通基盤 第3.2節・第10.4節。仕訳メモは 10。
  private static void assertCanEditJournalMemo() {
    ContractPermissionUtil.assertEditDraftInvoice();
  }

  /** 仕様: Core 第8.1節、第8.2節、第8.9節、第7.9.6節、日付仕様 第7.3節。取消基準日は呼び出し側が渡す。null 固定しない。 */
  public static Id savePaymentFromPreview(
    Id paymentId,
    Id invoiceId,
    Decimal amount,
    String purpose,
    Date paymentDate,
    String memo,
    String expectedToken,
    List<AllocationInputDto> allocations,
    Date cancellationDate
  ) {
    return savePaymentFromPreview(
      paymentId,
      invoiceId,
      amount,
      purpose,
      paymentDate,
      memo,
      expectedToken,
      allocations,
      cancellationDate,
      null
    );
  }

  /** 仕様: Core 第7.7.3節、第8.1節、第8.2節、第8.9節、第7.9.6節、第7.9.7節、日付仕様 第7.3節 */
  @AuraEnabled
  public static Id savePaymentFromPreview(
    Id paymentId,
    Id invoiceId,
    Decimal amount,
    String purpose,
    Date paymentDate,
    String memo,
    String expectedToken,
    List<AllocationInputDto> allocations,
    Date cancellationDate,
    String businessOperationKey,
    Id contractHistoryId,
    Map<String, Object> extraFieldValues
  ) {
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId }
    );
    return savePaymentFromPreview(
      paymentId,
      invoiceId,
      amount,
      purpose,
      paymentDate,
      memo,
      expectedToken,
      allocations,
      cancellationDate,
      businessOperationKey,
      extraFieldValues
    );
  }

  /** 仕様: Core 第8.1節、第8.2節、第8.9節、第7.9.6節、第7.9.7節、第11.4.4節、日付仕様 第7.3節 */
  public static Id savePaymentFromPreview(
    Id paymentId,
    Id invoiceId,
    Decimal amount,
    String purpose,
    Date paymentDate,
    String memo,
    String expectedToken,
    List<AllocationInputDto> allocations,
    Date cancellationDate,
    String businessOperationKey
  ) {
    return savePaymentFromPreview(
      paymentId,
      invoiceId,
      amount,
      purpose,
      paymentDate,
      memo,
      expectedToken,
      allocations,
      cancellationDate,
      businessOperationKey,
      null
    );
  }

  public static Id savePaymentFromPreview(
    Id paymentId,
    Id invoiceId,
    Decimal amount,
    String purpose,
    Date paymentDate,
    String memo,
    String expectedToken,
    List<AllocationInputDto> allocations,
    Date cancellationDate,
    String businessOperationKey,
    Map<String, Object> extraFieldValues
  ) {
    ContractPermissionUtil.assertInvoicePayment();
    if (paymentId != null) {
      throw handled('入金は直接更新できません。取消して再登録してください。');
    }
    if (invoiceId == null || amount == null || amount == 0 || paymentDate == null) {
      throw handled('請求、0以外の金額、入出金日を入力してください。');
    }
    String resolvedPurpose = purpose;
    if (
      resolvedPurpose != InvoicePaymentService.PURPOSE_INVOICE &&
      resolvedPurpose != InvoicePaymentService.PURPOSE_NON_INVOICE
    ) {
      throw handled('入出金目的は請求金額または請求金額以外です。');
    }
    InvoicePaymentService.RegisterRequest request = new InvoicePaymentService.RegisterRequest();
    request.invoiceId = invoiceId;
    request.amount = amount;
    request.purpose = resolvedPurpose;
    request.paymentDate = paymentDate;
    request.memo = memo;
    request.extraFieldValues = extraFieldValues;
    request.cancellationDate = cancellationDate;
    request.businessOperationKey = businessOperationKey;
    request.expectedToken = expectedToken;
    if (resolvedPurpose == InvoicePaymentService.PURPOSE_INVOICE) {
      if (allocations == null) {
        request.allocations = InvoicePaymentAllocationService.proposeLines(
          invoiceId,
          amount
        );
      } else {
        request.allocations = toAllocationLines(allocations);
      }
    }
    try {
      return InvoicePaymentService.register(request);
    } catch (Exception ex) {
      throw handled(ex.getMessage());
    }
  }

  /**
   * 仕様: Core 第8.4節、第8.9節、第7.9.7節、第11.4.4節。
   * 登録後はメモと入出金ロック除外へ人が足した追加項目だけ。
   */
  @AuraEnabled
  public static void updatePaymentFromPreview(
    Id paymentId,
    Id invoiceId,
    String memo,
    Map<String, Object> extraFieldValues,
    String expectedToken,
    String businessOperationKey,
    Id contractHistoryId
  ) {
    ContractPermissionUtil.assertEditDraftInvoice();
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId }
    );
    if (paymentId == null || invoiceId == null) {
      throw handled('入出金が指定されていません。');
    }
    InvoicePayment__c payment = [
      SELECT
        Id,
        Invoice__c,
        Invoice__r.InvoiceTransactionStatus__c,
        PaymentTransactionStatus__c,
        Memo__c
      FROM InvoicePayment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (payment.Invoice__c != invoiceId) {
      throw handled('この請求以外の入出金は編集できません。');
    }
    if (InvoiceTransactionStatusService.isCancelled(payment.Invoice__r)) {
      throw handled('取消済み請求の入出金は編集できません。');
    }
    if (payment.PaymentTransactionStatus__c != InvoicePaymentService.STATUS_ACTIVE) {
      throw handled('取消済／取消の入出金は編集できません。');
    }
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      businessOperationKey
    );
    if (String.isNotBlank(businessOperationKey)) {
      Integer existing = [
        SELECT COUNT()
        FROM InvoicePayment__c
        WHERE BusinessOperationKey__c = :operationKey
        WITH SYSTEM_MODE
      ];
      if (existing > 0) {
        return;
      }
    }
    AccountingCauseLockService.lockInvoice(invoiceId);
    AccountingCauseLockService.assertInvoiceOperationUnchanged(
      invoiceId,
      expectedToken
    );
    payment.Memo__c = memo;
    InvoiceOpsFieldService.applyDisplayedValues(
      payment,
      'InvoicePayment__c',
      extraFieldValues,
      InvoicePaymentLockUtil.resolveLockExemptFieldNames()
    );
    try {
      update payment;
      Boolean previousLifecycle = InvoicePaymentService.allowLifecycleWrite;
      InvoicePaymentService.allowLifecycleWrite = true;
      try {
        update new InvoicePayment__c(
          Id = paymentId,
          BusinessOperationKey__c = operationKey
        );
      } finally {
        InvoicePaymentService.allowLifecycleWrite = previousLifecycle;
      }
    } catch (Exception ex) {
      throw handled(ex.getMessage());
    }
    ContractOperationLogService.write(
      'EditPayment',
      operationKey,
      'InvoicePayment__c',
      String.valueOf(paymentId)
    );
  }

  /** 仕様: Core 第7.7.3節、第7.9.6節、第8.9節、Accounting 第8.5節・第8.8節、日付仕様 第7.3節 */
  @AuraEnabled
  public static AccountingDiffService.CancelPreview previewRegisterFromPreview(
    Id invoiceId,
    Decimal amount,
    String purpose,
    Date paymentDate,
    String memo,
    String expectedToken,
    List<AllocationInputDto> allocations,
    Date cancellationDate,
    Id contractHistoryId
  ) {
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId }
    );
    return previewRegisterFromPreview(
      invoiceId,
      amount,
      purpose,
      paymentDate,
      memo,
      expectedToken,
      allocations,
      cancellationDate
    );
  }

  /** 仕様: Core 第7.9.6節、第8.9節、Accounting 第8.5節・第8.8節、日付仕様 第7.3節 */
  public static AccountingDiffService.CancelPreview previewRegisterFromPreview(
    Id invoiceId,
    Decimal amount,
    String purpose,
    Date paymentDate,
    String memo,
    String expectedToken,
    List<AllocationInputDto> allocations,
    Date cancellationDate
  ) {
    ContractPermissionUtil.assertInvoicePayment();
    if (invoiceId == null || amount == null || amount == 0 || paymentDate == null) {
      throw handled('請求、0以外の金額、入出金日を入力してください。');
    }
    Invoice__c invoice = [
      SELECT
        Id,
        LastModifiedDate,
        InvoiceTransactionStatus__c,
        TaxInclusiveAmount__c,
        InvoicePaymentNet__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    ContractOptimisticLockUtil.assertRequiredUnchanged(
      invoice.LastModifiedDate,
      expectedToken,
      '請求'
    );
    String resolvedPurpose = purpose;
    if (
      resolvedPurpose != InvoicePaymentService.PURPOSE_INVOICE &&
      resolvedPurpose != InvoicePaymentService.PURPOSE_NON_INVOICE
    ) {
      throw handled('入出金目的は請求金額または請求金額以外です。');
    }
    InvoicePaymentService.RegisterRequest request = new InvoicePaymentService.RegisterRequest();
    request.invoiceId = invoiceId;
    request.amount = amount;
    request.purpose = resolvedPurpose;
    request.paymentDate = paymentDate;
    request.memo = memo;
    request.cancellationDate = cancellationDate;
    if (resolvedPurpose == InvoicePaymentService.PURPOSE_INVOICE) {
      if (allocations == null) {
        request.allocations = InvoicePaymentAllocationService.proposeLines(
          invoiceId,
          amount
        );
      } else {
        request.allocations = toAllocationLines(allocations);
      }
    }
    try {
      return InvoicePaymentService.previewRegister(request);
    } catch (Exception ex) {
      throw handled(ex.getMessage());
    }
  }

  /** 仕様: Core 第7.7.3節、第7.9.6節、Accounting 第8.5節 */
  @AuraEnabled
  public static AccountingDiffService.CancelPreview previewCancelPaymentFromPreview(
    Id paymentId,
    Id invoiceId,
    Date cancelDate,
    Id contractHistoryId
  ) {
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId }
    );
    return previewCancelPaymentFromPreview(paymentId, invoiceId, cancelDate);
  }

  /** 仕様: Core 第7.9.6節、Accounting 第8.5節 */
  public static AccountingDiffService.CancelPreview previewCancelPaymentFromPreview(
    Id paymentId,
    Id invoiceId,
    Date cancelDate
  ) {
    ContractPermissionUtil.assertInvoicePayment();
    if (paymentId == null || invoiceId == null) {
      throw handled('取消する入出金が指定されていません。');
    }
    InvoicePayment__c existing = [
      SELECT Id, Invoice__c
      FROM InvoicePayment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (existing.Invoice__c != invoiceId) {
      throw handled('入金が指定した請求に属していません。');
    }
    try {
      return InvoicePaymentService.previewCancel(paymentId, cancelDate);
    } catch (Exception ex) {
      throw handled(ex.getMessage());
    }
  }

  /** 仕様: Core 第8.1節、第8.9節 */
  public static Id cancelPaymentFromPreview(
    Id paymentId,
    Id invoiceId,
    Date cancelDate,
    String cancellationReason,
    String cancellationReasonText,
    String expectedToken
  ) {
    return cancelPaymentFromPreview(
      paymentId,
      invoiceId,
      cancelDate,
      cancellationReason,
      cancellationReasonText,
      expectedToken,
      null
    );
  }

  /** 仕様: Core 第7.7.3節、第8.1節、第8.9節、第7.9.7節 */
  @AuraEnabled
  public static Id cancelPaymentFromPreview(
    Id paymentId,
    Id invoiceId,
    Date cancelDate,
    String cancellationReason,
    String cancellationReasonText,
    String expectedToken,
    String businessOperationKey,
    Id contractHistoryId
  ) {
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId }
    );
    return cancelPaymentFromPreview(
      paymentId,
      invoiceId,
      cancelDate,
      cancellationReason,
      cancellationReasonText,
      expectedToken,
      businessOperationKey
    );
  }

  /** 仕様: Core 第8.1節、第8.9節、第7.9.7節 */
  public static Id cancelPaymentFromPreview(
    Id paymentId,
    Id invoiceId,
    Date cancelDate,
    String cancellationReason,
    String cancellationReasonText,
    String expectedToken,
    String businessOperationKey
  ) {
    ContractPermissionUtil.assertInvoicePayment();
    InvoicePayment__c existing = [
      SELECT Id, Invoice__c, LastModifiedDate, PaymentTransactionStatus__c
      FROM InvoicePayment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (existing.Invoice__c != invoiceId) {
      throw handled('入金が指定した請求に属していません。');
    }
    InvoicePaymentService.CancelRequest request = new InvoicePaymentService.CancelRequest();
    request.paymentId = paymentId;
    request.cancellationReason = cancellationReason;
    request.cancellationReasonText = cancellationReasonText;
    request.cancelDate = cancelDate;
    request.businessOperationKey = businessOperationKey;
    request.expectedToken = expectedToken;
    try {
      return InvoicePaymentService.cancel(request);
    } catch (Exception ex) {
      throw handled(ex.getMessage());
    }
  }

  /** 仕様: Core 第8.6節。明細の決済対象額は税抜＋配分税の符号付き税込。 */
  private static List<PaymentLineRemainingDto> loadPaymentLines(Id invoiceId) {
    Map<Id, Decimal> allocatedByLine = new Map<Id, Decimal>();
    for (InvoicePaymentAllocation__c allocation : [
      SELECT InvoiceLine__c, Amount__c
      FROM InvoicePaymentAllocation__c
      WHERE
        InvoicePayment__r.Invoice__c = :invoiceId
        AND InvoicePayment__r.PaymentPurpose__c = :InvoicePaymentService.PURPOSE_INVOICE
        AND InvoicePayment__r.PaymentTransactionStatus__c = :InvoicePaymentService.STATUS_ACTIVE
      WITH SYSTEM_MODE
    ]) {
      Decimal current = allocatedByLine.containsKey(allocation.InvoiceLine__c)
        ? allocatedByLine.get(allocation.InvoiceLine__c)
        : 0;
      allocatedByLine.put(
        allocation.InvoiceLine__c,
        current + nvl(allocation.Amount__c)
      );
    }
    List<PaymentLineRemainingDto> rows = new List<PaymentLineRemainingDto>();
    for (InvoiceLine__c line : [
      SELECT Id, ProductName__c, Amount__c, AllocatedTaxAmount__c
      FROM InvoiceLine__c
      WHERE Invoice__c = :invoiceId
      WITH SYSTEM_MODE
      ORDER BY Id
    ]) {
      PaymentLineRemainingDto row = new PaymentLineRemainingDto();
      row.lineId = line.Id;
      row.productName = line.ProductName__c;
      Decimal inclusive = nvl(line.Amount__c) + nvl(line.AllocatedTaxAmount__c);
      row.remainingInclusive =
        inclusive - (allocatedByLine.containsKey(line.Id) ? allocatedByLine.get(line.Id) : 0);
      rows.add(row);
    }
    return rows;
  }

  private static List<InvoicePaymentAllocationService.AllocationLine> toAllocationLines(
    List<AllocationInputDto> inputs
  ) {
    List<InvoicePaymentAllocationService.AllocationLine> lines = new List<InvoicePaymentAllocationService.AllocationLine>();
    for (AllocationInputDto input : inputs) {
      InvoicePaymentAllocationService.AllocationLine line = new InvoicePaymentAllocationService.AllocationLine();
      line.invoiceLineId = input == null ? null : input.invoiceLineId;
      line.amount = input == null ? null : input.amount;
      lines.add(line);
    }
    return lines;
  }

  /** 仕様: Core 第8.4節、第2.3.1節 */
  private static List<PaymentRowDto> loadPayments(Id invoiceId) {
    List<PaymentRowDto> rows = new List<PaymentRowDto>();
    for (InvoicePayment__c payment : [
      SELECT
        Id,
        Amount__c,
        PaymentPurpose__c,
        PaymentDate__c,
        Memo__c,
        PaymentTransactionStatus__c,
        LastModifiedDate
      FROM InvoicePayment__c
      WHERE Invoice__c = :invoiceId
      WITH SYSTEM_MODE
      ORDER BY PaymentDate__c ASC, CreatedDate ASC
    ]) {
      PaymentRowDto row = new PaymentRowDto();
      row.paymentId = payment.Id;
      row.amount = payment.Amount__c;
      row.displayAmount = payment.Amount__c;
      row.paymentPurpose = payment.PaymentPurpose__c;
      row.paymentDate = payment.PaymentDate__c;
      row.memo = payment.Memo__c;
      row.isCancellation =
        payment.PaymentTransactionStatus__c == InvoicePaymentService.STATUS_REVERSAL;
      row.isCancelled =
        payment.PaymentTransactionStatus__c == InvoicePaymentService.STATUS_CANCELLED;
      row.canCancel =
        payment.PaymentTransactionStatus__c == InvoicePaymentService.STATUS_ACTIVE;
      row.paymentTransactionStatus = payment.PaymentTransactionStatus__c;
      row.lastModifiedToken = ContractOptimisticLockUtil.toToken(
        payment.LastModifiedDate
      );
      rows.add(row);
    }
    Set<Id> paymentIds = new Set<Id>();
    for (PaymentRowDto row : rows) {
      paymentIds.add(row.paymentId);
    }
    Map<Id, Map<String, Object>> extraById =
      InvoiceOpsFieldService.readValuesById('InvoicePayment__c', paymentIds);
    for (PaymentRowDto row : rows) {
      row.extraFieldValues = extraById.get(row.paymentId);
    }
    return rows;
  }

  /** 仕様: Core 第1.1.10節、第7.6節。0件はOFFと埋めない。 */
  private static Boolean resolveAccountingEnabled() {
    return GlAccountingPolicyService.requireOrgPolicy().AccountingEnabled__c ==
      true;
  }

  /** 仕様: Core 第7.7.3節、Accounting 第4.2節、第9.3節 */
  private static List<JournalRowDto> loadJournals(Id invoiceId) {
    List<JournalRowDto> rows = new List<JournalRowDto>();
    for (GlJournal__c journal : [
      SELECT
        Id,
        AccountingEventKey__c,
        JournalPatternKey__c,
        DebitSlotKey__c,
        CreditSlotKey__c,
        DebitAccount__r.Name,
        CreditAccount__r.Name,
        Amount__c,
        PostingDate__c,
        TransactionStatus__c,
        IsLocked__c,
        Memo__c,
        ConfirmationText__c
      FROM GlJournal__c
      WHERE Invoice__c = :invoiceId
      WITH SYSTEM_MODE
      ORDER BY PostingDate__c ASC, CreatedDate ASC
    ]) {
      JournalRowDto row = new JournalRowDto();
      row.journalId = journal.Id;
      row.eventKey = journal.AccountingEventKey__c;
      row.eventName = accountingEventName(journal.AccountingEventKey__c);
      row.patternKey = journal.JournalPatternKey__c;
      row.debitSlotKey = journal.DebitSlotKey__c;
      row.creditSlotKey = journal.CreditSlotKey__c;
      row.debitAccountName = journal.DebitAccount__r == null
        ? null
        : journal.DebitAccount__r.Name;
      row.creditAccountName = journal.CreditAccount__r == null
        ? null
        : journal.CreditAccount__r.Name;
      row.amount = journal.Amount__c;
      row.postingDate = journal.PostingDate__c;
      row.transactionStatus = journal.TransactionStatus__c;
      row.isLocked = journal.IsLocked__c == true;
      row.memo = journal.Memo__c;
      row.confirmationText = journal.ConfirmationText__c;
      rows.add(row);
    }
    Set<Id> journalIds = new Set<Id>();
    for (JournalRowDto row : rows) {
      journalIds.add(row.journalId);
    }
    Map<Id, Map<String, Object>> extraById =
      InvoiceOpsFieldService.readValuesById('GlJournal__c', journalIds);
    for (JournalRowDto row : rows) {
      row.extraFieldValues = extraById.get(row.journalId);
    }
    return rows;
  }

  /** 仕様: Accounting 第7.6節、第11.2節 */
  private static List<TagResultRowDto> loadTagResults(Id invoiceId) {
    List<TagResultRowDto> rows = new List<TagResultRowDto>();
    List<GlAccountingTagRule__c> rules = [
      SELECT TagLabel__c, TargetFieldApiName__c
      FROM GlAccountingTagRule__c
      WHERE IsEnabled__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY TagLabel__c ASC
    ];
    if (rules.isEmpty()) {
      return rows;
    }
    Map<String, Schema.SObjectField> invoiceFields = Invoice__c.SObjectType.getDescribe()
      .fields.getMap();
    Set<String> fieldNames = new Set<String>{ 'Id' };
    for (GlAccountingTagRule__c rule : rules) {
      if (
        String.isNotBlank(rule.TargetFieldApiName__c) &&
        invoiceFields.containsKey(rule.TargetFieldApiName__c)
      ) {
        fieldNames.add(rule.TargetFieldApiName__c);
      }
    }
    Invoice__c invoice = (Invoice__c) Database.query(
      'SELECT ' +
        String.join(new List<String>(fieldNames), ',') +
        ' FROM Invoice__c WHERE Id = :invoiceId WITH SYSTEM_MODE LIMIT 1'
    );
    for (GlAccountingTagRule__c rule : rules) {
      Boolean value = invoiceFields.containsKey(rule.TargetFieldApiName__c)
        ? (Boolean) invoice.get(rule.TargetFieldApiName__c) == true
        : false;
      if (value != true) {
        continue;
      }
      TagResultRowDto row = new TagResultRowDto();
      row.name = rule.TagLabel__c;
      row.fieldApiName = rule.TargetFieldApiName__c;
      row.value = true;
      rows.add(row);
    }
    return rows;
  }

  /** 仕様: Accounting 第10.3節、第10.4節、第8.5節、Core 第0.1節、第7.9.6節、日付仕様 第7.3節 */
  private static List<ManualJournalRowDto> loadManualJournals(Id invoiceId) {
    List<ManualJournalRowDto> rows = new List<ManualJournalRowDto>();
    List<GlManualJournalHeader__c> headers = [
      SELECT
        Id,
        Amount__c,
        PostingDate__c,
        TransactionStatus__c,
        GlManualJournalSetting__r.Name
      FROM GlManualJournalHeader__c
      WHERE Invoice__c = :invoiceId
      WITH SYSTEM_MODE
      ORDER BY PostingDate__c ASC, CreatedDate ASC
    ];
    // 仕様: Accounting 第8.5節。取消基準日要否は請求書単位の Active Lock（入金取消と同じ）。
    Boolean invoiceHasLocked = [
      SELECT COUNT()
      FROM GlJournal__c
      WHERE
        Invoice__c = :invoiceId
        AND IsLocked__c = TRUE
        AND TransactionStatus__c = 'Active'
      WITH SYSTEM_MODE
    ] > 0;
    for (GlManualJournalHeader__c header : headers) {
      ManualJournalRowDto row = new ManualJournalRowDto();
      row.headerId = header.Id;
      row.settingName = header.GlManualJournalSetting__r == null
        ? null
        : header.GlManualJournalSetting__r.Name;
      row.postingDate = header.PostingDate__c;
      row.amount = header.Amount__c;
      row.transactionStatus = header.TransactionStatus__c;
      row.transactionStatusLabel = manualJournalStatusLabel(
        header.TransactionStatus__c
      );
      row.canCancel = header.TransactionStatus__c == 'Active';
      row.hasLockedJournals = invoiceHasLocked;
      rows.add(row);
    }
    return rows;
  }

  /** 仕様: Core 第0.1節、Accounting 第10.3節 */
  private static String manualJournalStatusLabel(String status) {
    if (status == 'Active') {
      return '有効';
    }
    if (status == 'Cancelled') {
      return '取消済';
    }
    return status;
  }

  /** 仕様: Accounting 第10.2節、第11.4節。Name＝メニュー表示名、Description＝選択すべき事象。 */
  private static List<ManualSettingRowDto> loadManualSettings() {
    List<ManualSettingRowDto> rows = new List<ManualSettingRowDto>();
    for (GlManualJournalSetting__c setting : [
      SELECT Id, Name, Description__c
      FROM GlManualJournalSetting__c
      WHERE IsActive__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY SortOrder__c ASC NULLS LAST, Name ASC
    ]) {
      ManualSettingRowDto row = new ManualSettingRowDto();
      row.settingId = setting.Id;
      row.label = setting.Name;
      row.description = setting.Description__c;
      rows.add(row);
    }
    return rows;
  }

  /** 仕様: Accounting 第4.2節 */
  private static String accountingEventName(String eventKey) {
    if (String.isBlank(eventKey)) {
      return eventKey;
    }
    for (AccountingEventFixedCatalog.Definition definition : AccountingEventFixedCatalog.values()) {
      if (definition.key == eventKey) {
        return definition.name;
      }
    }
    return eventKey;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  /** 仕様: Core 第0章。人が見る文字は日本語。Aura 拒否は setMessage して本文をテストで取れるようにする */
  private static AuraHandledException handled(String message) {
    String resolved = String.isBlank(message)
      ? '処理に失敗しました。'
      : message;
    AuraHandledException ex = new AuraHandledException(resolved);
    ex.setMessage(resolved);
    return ex;
  }
}
