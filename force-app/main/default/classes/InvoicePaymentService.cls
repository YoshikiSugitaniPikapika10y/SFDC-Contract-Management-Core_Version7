/**
 * 請求入出金の登録・取消と請求金額Netの再計算。
 */
public without sharing class InvoicePaymentService {
  public static final String PURPOSE_INVOICE = 'Invoice';
  public static final String PURPOSE_NON_INVOICE = 'NonInvoice';
  public static final String STATUS_ACTIVE = 'Active';
  public static final String STATUS_CANCELLED = 'Cancelled';
  public static final String STATUS_REVERSAL = 'Reversal';

  public static Boolean allowLifecycleWrite;

  public class RegisterRequest {
    public Id invoiceId;
    public Decimal amount;
    public String purpose;
    public Date paymentDate;
    public String memo;
    /** 仕様: Core 第8.9節、日付仕様 第7.3節 */
    public Date cancellationDate;
    public List<InvoicePaymentAllocationService.AllocationLine> allocations;
    public String businessOperationKey;
    public String expectedToken;
    /** 仕様: Core 第11.4.4節。登録フォームの追加項目。 */
    public Map<String, Object> extraFieldValues;
  }

  public class CancelRequest {
    public Id paymentId;
    public String cancellationReason;
    public String cancellationReasonText;
    public Date cancelDate;
    public String businessOperationKey;
    public String expectedToken;
  }

  /** 仕様: Core 第8.1節、第8.2節、第8.4節、第8.6節、第11.9節、第1.1.7節、第7.9.6節、第8.9節、Accounting 第1.8.1節、第8.2節、第8.5節、第8.8節、日付仕様 第7.3節 */
  public static Id register(RegisterRequest request) {
    // 仕様: Core 第8.4節。登録は請求入出金操作権限。画面・APIその他の経路でサーバ側検証。権限API名は既存13。
    ContractPermissionUtil.assertInvoicePayment();
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      request == null ? null : request.businessOperationKey
    );
    if (request != null && String.isNotBlank(request.businessOperationKey)) {
      List<InvoicePayment__c> existing = [
        SELECT Id
        FROM InvoicePayment__c
        WHERE BusinessOperationKey__c = :operationKey
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!existing.isEmpty()) {
        return existing[0].Id;
      }
    }
    Invoice__c invoice = prepareRegister(request);
    if (String.isNotBlank(request.businessOperationKey)) {
      List<InvoicePayment__c> existingAfterLock = [
        SELECT Id
        FROM InvoicePayment__c
        WHERE BusinessOperationKey__c = :operationKey
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!existingAfterLock.isEmpty()) {
        return existingAfterLock[0].Id;
      }
    }
    // 仕様: Core 第4.3.12節・第7.9.7節。比較値未指定は拒否。検査省略の互換は持たない。
    AccountingCauseLockService.assertInvoiceOperationUnchanged(
      invoice.Id,
      request.expectedToken
    );
    request.businessOperationKey = operationKey;
    Savepoint savepoint = Database.setSavepoint();
    Boolean previousWrite = allowLifecycleWrite;
    allowLifecycleWrite = true;
    try {
      Id paymentId = insertRegisteredPayment(request, invoice);
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        operationKey,
        request.cancellationDate
      );
      return paymentId;
    } catch (Exception ex) {
      Database.rollback(savepoint);
      throw ex;
    } finally {
      allowLifecycleWrite = previousWrite;
    }
  }

  /** 仕様: Core 第7.9.6節、第8.9節、Accounting 第8.5節・第8.8節、日付仕様 第7.3節 */
  public static AccountingDiffService.CancelPreview previewRegister(
    RegisterRequest request
  ) {
    Invoice__c invoice = prepareRegister(request);
    Savepoint savepoint = Database.setSavepoint();
    Boolean previousWrite = allowLifecycleWrite;
    allowLifecycleWrite = true;
    try {
      insertRegisteredPayment(request, invoice);
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewApply(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        request.cancellationDate
      );
      Database.rollback(savepoint);
      return preview;
    } catch (Exception ex) {
      Database.rollback(savepoint);
      throw ex;
    } finally {
      allowLifecycleWrite = previousWrite;
    }
  }

  private static Invoice__c prepareRegister(RegisterRequest request) {
    if (request == null || request.invoiceId == null) {
      throw new PaymentException('請求が指定されていません。');
    }
    // 仕様: Core 第11.4.2節
    FieldCopyDefinitionService.validateAllDefinitions();
    if (request.amount == null || request.amount == 0) {
      throw new PaymentException('入出金金額は0以外の整数を指定してください。');
    }
    if (request.amount != request.amount.intValue()) {
      throw new PaymentException('入出金金額は整数にしてください。');
    }
    if (request.purpose != PURPOSE_INVOICE && request.purpose != PURPOSE_NON_INVOICE) {
      throw new PaymentException('入出金目的は請求金額または請求金額以外です。');
    }
    if (request.paymentDate == null) {
      throw new PaymentException('入出金日を入力してください。');
    }
    if (
      request.purpose == PURPOSE_NON_INVOICE &&
      request.allocations != null &&
      !request.allocations.isEmpty()
    ) {
      throw new PaymentException('請求金額以外の入出金に明細別割当は持てません。');
    }
    // 仕様: Core 第7.9.7節・第11.8節、Accounting 第8.2節。行ロックで直列化してから残額検証。
    Invoice__c invoice = AccountingCauseLockService.lockInvoice(request.invoiceId);
    if (request.purpose == PURPOSE_INVOICE) {
      InvoicePaymentAllocationService.assertLines(
        request.invoiceId,
        request.amount,
        request.allocations
      );
    }
    if (InvoiceTransactionStatusService.isCancelled(invoice)) {
      throw new PaymentException('取消済みの請求に入出金は登録できません。');
    }
    if (!InvoiceTransactionStatusService.isConfirmed(invoice)) {
      throw new PaymentException('確定済みの請求にだけ入出金を登録できます。');
    }
    if (request.purpose == PURPOSE_INVOICE) {
      Decimal remaining =
        nvl(invoice.TaxInclusiveAmount__c) - nvl(invoice.InvoicePaymentNet__c);
      if (remaining == 0) {
        throw new PaymentException('請求金額の未処理Netが0のときは請求金額目的を登録できません。');
      }
      if (
        (request.amount > 0 && remaining < 0) ||
        (request.amount < 0 && remaining > 0)
      ) {
        throw new PaymentException('請求金額の入出金は未処理Netと同じ符号にしてください。');
      }
      if (request.amount.abs() > remaining.abs()) {
        throw new PaymentException('請求金額の入出金は未処理Netを超えられません。');
      }
    }
    // 仕様: Accounting 第1.1節・第8.5節、Core 第7.9.6節。
    // 入金登録の取消基準日は Accounting ON かつロック済み仕訳があるときだけ。OFFは仕訳を触らない。
    GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
    if (policy.AccountingEnabled__c == true) {
      Integer lockedJournals = [
        SELECT COUNT()
        FROM GlJournal__c
        WHERE
          Invoice__c = :invoice.Id
          AND IsLocked__c = TRUE
          AND TransactionStatus__c = 'Active'
        WITH SYSTEM_MODE
      ];
      if (lockedJournals > 0 && request.cancellationDate == null) {
        throw new PaymentException('ロック済み仕訳がある取消では取消基準日が必要です。');
      }
    }
    return invoice;
  }

  private static Id insertRegisteredPayment(
    RegisterRequest request,
    Invoice__c invoice
  ) {
    InvoicePayment__c payment = new InvoicePayment__c(
      Invoice__c = invoice.Id,
      Amount__c = request.amount,
      PaymentPurpose__c = request.purpose,
      PaymentDate__c = request.paymentDate,
      Memo__c = request.memo,
      PaymentTransactionStatus__c = STATUS_ACTIVE,
      BillingAccount__c = invoice.BillingAccountSnapShot__c,
      BillingAccountKeySnapShot__c = invoice.BillingAccountKeySnapShot__c,
      BusinessOperationKey__c = request.businessOperationKey
    );
    Set<String> extraAllowed = InvoiceOpsFieldService.paymentDisplayedFieldApiNames(
      request.purpose
    );
    InvoiceOpsFieldService.applyDisplayedValues(
      payment,
      'InvoicePayment__c',
      request.extraFieldValues,
      extraAllowed
    );
    SystemContextAccess.insertRecords(new List<SObject>{ payment });
    if (request.purpose == PURPOSE_INVOICE) {
      InvoicePaymentAllocationService.allocate(payment.Id, request.allocations);
    }
    recalculateNets(new Set<Id>{ invoice.Id });
    ContractOperationLogService.write(
      'RegisterPayment',
      request.businessOperationKey,
      'InvoicePayment__c',
      String.valueOf(payment.Id)
    );
    return payment.Id;
  }

  /** 仕様: Core 第8.1節、第8.4節、第1.1.7節、Accounting 第1.8.1節、第8.2節、第8.4節、第8.8節 */
  public static Id cancel(CancelRequest request) {
    // 仕様: Core 第8.4節。取消は請求入出金操作権限。画面・APIその他の経路でサーバ側検証。権限API名は既存13。
    ContractPermissionUtil.assertInvoicePayment();
    if (request == null || request.paymentId == null) {
      throw new PaymentException('取消する入出金が指定されていません。');
    }
    if (String.isBlank(request.cancellationReason)) {
      throw new PaymentException('取消理由を入力してください。');
    }
    if (
      request.cancellationReason == 'Other' &&
      String.isBlank(request.cancellationReasonText)
    ) {
      throw new PaymentException('取消理由がその他のときは内容を入力してください。');
    }
    InvoicePayment__c original = [
      SELECT
        Id,
        Invoice__c,
        Amount__c,
        PaymentPurpose__c,
        PaymentDate__c,
        Memo__c,
        PaymentTransactionStatus__c,
        BillingAccount__c,
        BillingAccountKeySnapShot__c,
        BusinessOperationKey__c
      FROM InvoicePayment__c
      WHERE Id = :request.paymentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    AccountingCauseLockService.lockInvoice(original.Invoice__c);
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      request.businessOperationKey
    );
    original = [
      SELECT
        Id,
        Invoice__c,
        Amount__c,
        PaymentPurpose__c,
        PaymentDate__c,
        Memo__c,
        PaymentTransactionStatus__c,
        BillingAccount__c,
        BillingAccountKeySnapShot__c,
        BusinessOperationKey__c
      FROM InvoicePayment__c
      WHERE Id = :request.paymentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (
      original.PaymentTransactionStatus__c == STATUS_CANCELLED &&
      original.BusinessOperationKey__c == operationKey
    ) {
      return original.Id;
    }
    // 仕様: Core 第4.3.12節・第7.9.7節。比較値未指定は拒否。検査省略の互換は持たない。
    AccountingCauseLockService.assertInvoiceOperationUnchanged(
      original.Invoice__c,
      request.expectedToken
    );
    if (original.PaymentTransactionStatus__c != STATUS_ACTIVE) {
      throw new PaymentException('有効な入出金だけ取消できます。');
    }
    Integer lockedJournals = [
      SELECT COUNT()
      FROM GlJournal__c
      WHERE
        Invoice__c = :original.Invoice__c
        AND IsLocked__c = TRUE
        AND TransactionStatus__c = 'Active'
      WITH SYSTEM_MODE
    ];
    if (lockedJournals > 0 && request.cancelDate == null) {
      throw new PaymentException('ロック済み仕訳がある取消では取消基準日が必要です。');
    }
    previewCancel(original.Id, request.cancelDate);
    Savepoint savepoint = Database.setSavepoint();
    Boolean previousWrite = allowLifecycleWrite;
    allowLifecycleWrite = true;
    try {
      original.PaymentTransactionStatus__c = STATUS_CANCELLED;
      original.CancellationReason__c = request.cancellationReason;
      original.CancellationReasonText__c = request.cancellationReasonText;
      original.BusinessOperationKey__c = operationKey;
      SystemContextAccess.updateRecords(new List<SObject>{ original });
      InvoicePayment__c reversal = new InvoicePayment__c(
        Invoice__c = original.Invoice__c,
        Amount__c = original.Amount__c == null ? 0 : -original.Amount__c,
        PaymentPurpose__c = original.PaymentPurpose__c,
        PaymentDate__c = original.PaymentDate__c,
        Memo__c = original.Memo__c,
        PaymentTransactionStatus__c = STATUS_REVERSAL,
        OriginalPayment__c = original.Id,
        CancellationReason__c = request.cancellationReason,
        CancellationReasonText__c = request.cancellationReasonText,
        BillingAccount__c = original.BillingAccount__c,
        BillingAccountKeySnapShot__c = original.BillingAccountKeySnapShot__c,
        BusinessOperationKey__c = operationKey
      );
      SystemContextAccess.insertRecords(new List<SObject>{ reversal });
      InvoicePaymentAllocationService.reverseAllocations(original.Id, reversal.Id);
      recalculateNets(new Set<Id>{ original.Invoice__c });
      AccountingDiffService.applyForInvoice(
        original.Invoice__c,
        AccountingEventFixedCatalog.PAYMENT_CANCELLED.key,
        operationKey,
        request.cancelDate
      );
      ContractOperationLogService.write(
        'CancelPayment',
        operationKey,
        'InvoicePayment__c',
        String.valueOf(original.Id),
        request.cancellationReason,
        request.cancellationReasonText,
        null,
        null
      );
      return reversal.Id;
    } catch (Exception ex) {
      Database.rollback(savepoint);
      throw ex;
    } finally {
      allowLifecycleWrite = previousWrite;
    }
  }

  /**
   * 仕様: Core 第7.9.6節、Accounting 第4.2節・第8.5節・第8.8節、日付仕様 第7.3節。
   * ON は入出金除外後の Goal Diff（previewApply）と実行後を一致させる。
   * OFF は cancelCurrent と同じ isCancelTarget 経路。
   */
  public static AccountingDiffService.CancelPreview previewCancel(
    Id paymentId,
    Date cancelDate
  ) {
    if (paymentId == null) {
      throw new PaymentException('取消する入出金が指定されていません。');
    }
    InvoicePayment__c payment = [
      SELECT Id, Invoice__c, PaymentTransactionStatus__c
      FROM InvoicePayment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
    if (policy.AccountingEnabled__c != true) {
      return AccountingDiffService.previewCancel(
        payment.Invoice__c,
        AccountingEventFixedCatalog.PAYMENT_CANCELLED.key,
        cancelDate,
        payment.Id,
        null
      );
    }
    // 登録 previewRegister と同じく、原因を外したうえで Goal Diff を数える。
    Savepoint savepoint = Database.setSavepoint();
    Boolean previousWrite = allowLifecycleWrite;
    allowLifecycleWrite = true;
    try {
      payment.PaymentTransactionStatus__c = STATUS_CANCELLED;
      SystemContextAccess.updateRecords(new List<SObject>{ payment });
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewApply(
        payment.Invoice__c,
        AccountingEventFixedCatalog.PAYMENT_CANCELLED.key,
        cancelDate
      );
      Database.rollback(savepoint);
      return preview;
    } catch (Exception ex) {
      Database.rollback(savepoint);
      throw ex;
    } finally {
      allowLifecycleWrite = previousWrite;
    }
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  /** 仕様: Core 第8.1節、第7.11節 */
  public static void recalculateNets(Set<Id> invoiceIds) {
    if (invoiceIds == null || invoiceIds.isEmpty()) {
      return;
    }
    Map<Id, Decimal> invoiceNets = new Map<Id, Decimal>();
    Map<Id, Decimal> inclusiveNets = new Map<Id, Decimal>();
    Map<Id, Integer> invoicePurposeCounts = new Map<Id, Integer>();
    for (Id invoiceId : invoiceIds) {
      invoiceNets.put(invoiceId, 0);
      inclusiveNets.put(invoiceId, 0);
      invoicePurposeCounts.put(invoiceId, 0);
    }
    for (InvoicePayment__c payment : [
      SELECT Invoice__c, Amount__c, PaymentPurpose__c, PaymentTransactionStatus__c
      FROM InvoicePayment__c
      WHERE Invoice__c IN :invoiceIds
      WITH SYSTEM_MODE
    ]) {
      if (payment.PaymentTransactionStatus__c != STATUS_ACTIVE) {
        continue;
      }
      Decimal amount = payment.Amount__c == null ? 0 : payment.Amount__c;
      inclusiveNets.put(
        payment.Invoice__c,
        inclusiveNets.get(payment.Invoice__c) + amount
      );
      if (payment.PaymentPurpose__c == PURPOSE_INVOICE) {
        invoiceNets.put(
          payment.Invoice__c,
          invoiceNets.get(payment.Invoice__c) + amount
        );
        invoicePurposeCounts.put(
          payment.Invoice__c,
          invoicePurposeCounts.get(payment.Invoice__c) + 1
        );
      }
    }
    List<Invoice__c> invoices = [
      SELECT
        Id,
        InvoiceTransactionStatus__c,
        TaxInclusiveAmount__c,
        InvoicePaymentNet__c,
        PaymentInclusiveTotal__c,
        CollectionRefundStatus__c,
        PaymentClearingCompletedDate__c
      FROM Invoice__c
      WHERE Id IN :invoiceIds
      WITH SYSTEM_MODE
    ];
    List<Invoice__c> updates = new List<Invoice__c>();
    for (Invoice__c invoice : invoices) {
      invoice.InvoicePaymentNet__c = invoiceNets.get(invoice.Id);
      invoice.PaymentInclusiveTotal__c = inclusiveNets.get(invoice.Id);
      InvoiceTransactionStatusService.applyCollectionRefund(
        invoice,
        invoicePurposeCounts.get(invoice.Id)
      );
      updates.add(invoice);
    }
    Boolean previousStatus = InvoiceTransactionStatusService.allowStatusWrite;
    Boolean previousLock = InvoiceLockUtil.allowLockedStatusWrite;
    InvoiceTransactionStatusService.allowStatusWrite = true;
    InvoiceLockUtil.allowLockedStatusWrite = true;
    try {
      SystemContextAccess.updateRecords(updates);
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
      InvoiceLockUtil.allowLockedStatusWrite = previousLock;
    }
  }

  public class PaymentException extends Exception {
  }
}
