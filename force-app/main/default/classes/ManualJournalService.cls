public without sharing class ManualJournalService {
  public static Boolean allowLifecycleWrite;

  public class ManualJournalException extends Exception {
  }

  public class RegisterRequest {
    public Id invoiceId;
    public Id settingId;
    public Date postingDate;
    public Decimal amount;
    public Date cancellationDate;
    public String businessOperationKey;
    public String expectedToken;
    public Invoice__c knownLockedInvoice;
  }

  public class CancelRequest {
    public Id headerId;
    public String cancellationReason;
    public String cancellationReasonText;
    public Date cancellationDate;
    public String businessOperationKey;
    public String expectedToken;
    public Invoice__c knownLockedInvoice;
    public GlManualJournalHeader__c knownHeader;
  }

  @TestVisible
  static Integer headerSelectCount = 0;

  /** 仕様: Accounting 第10.3節、第8.2節、第8.8節、Core 第7.7.3節 */
  public static Id register(RegisterRequest request) {
    // 仕様: 共通基盤 第3.2節・第10.4節。手動仕訳は 14。
    ContractPermissionUtil.assertManualJournal();
    Invoice__c invoice = prepareRegister(request);
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      request.businessOperationKey
    );
    if (String.isNotBlank(request.businessOperationKey)) {
      List<GlManualJournalHeader__c> existing = [
        SELECT Id
        FROM GlManualJournalHeader__c
        WHERE
          BusinessOperationKey__c = :operationKey
          AND Invoice__c = :request.invoiceId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!existing.isEmpty()) {
        return existing[0].Id;
      }
    }
    // 仕様: Core 第4.3.12節・第7.9.7節。比較値未指定は拒否。検査省略の互換は持たない。
    AccountingCauseLockService.assertInvoiceOperationUnchanged(
      request.invoiceId,
      request.expectedToken,
      invoice.LastModifiedDate
    );
    GlManualJournalHeader__c header = buildHeader(
      request,
      invoice.Id,
      operationKey
    );
    Savepoint savepoint = Database.setSavepoint();
    try {
      Boolean previousWrite = allowLifecycleWrite;
      allowLifecycleWrite = true;
      try {
        insert header;
      } finally {
        allowLifecycleWrite = previousWrite;
      }
      AccountingDiffService.applyForInvoice(
        request.invoiceId,
        AccountingEventFixedCatalog.MANUAL_JOURNAL.key,
        operationKey,
        request.cancellationDate,
        invoice
      );
    } catch (Exception ex) {
      Database.rollback(savepoint);
      throw ex;
    }
    ContractOperationLogService.write(
      'RegisterManualJournal',
      operationKey,
      'GlManualJournalHeader__c',
      String.valueOf(header.Id)
    );
    return header.Id;
  }

  /**
   * 仕様: Accounting 第8.8節・第8.2節・第10.3節、Core 第7.9.6節。
   * Goal を組む実行前プレビューは組まない。確認可否は prepareRegister の業務確認と取消基準日。
   */
  public static AccountingDiffService.CancelPreview previewRegister(
    RegisterRequest request
  ) {
    ContractPermissionUtil.assertManualJournal();
    prepareRegister(request);
    return emptyConfirmPreview();
  }

  private static AccountingDiffService.CancelPreview emptyConfirmPreview() {
    AccountingDiffService.CancelPreview preview = new AccountingDiffService.CancelPreview();
    preview.logicalDeleteCount = 0;
    preview.reverseCount = 0;
    preview.reverseDateCounts = new List<AccountingDiffService.ReverseDateCount>();
    preview.hasFutureReverseDate = false;
    preview.displayText = '';
    return preview;
  }

  private static Invoice__c prepareRegister(RegisterRequest request) {
    if (request == null || request.invoiceId == null || request.settingId == null) {
      throw new ManualJournalException('請求と手動仕訳設定を指定してください。');
    }
    if (request.postingDate == null) {
      throw new ManualJournalException('計上日を入力してください。');
    }
    if (request.amount == null || request.amount <= 0 || request.amount != request.amount.intValue()) {
      throw new ManualJournalException('金額は0より大きい整数にしてください。');
    }
    // 仕様: Accounting 第8.2節。Goal・Current・Diffの前に行ロックし、続けて利用設定を確認する。
    Invoice__c invoice =
      request.knownLockedInvoice != null &&
      request.knownLockedInvoice.Id == request.invoiceId
        ? request.knownLockedInvoice
        : AccountingCauseLockService.lockInvoice(request.invoiceId);
    GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
    if (policy.AccountingEnabled__c != true) {
      throw new ManualJournalException('AccountingがOFFのときは手動仕訳を登録できません。');
    }
    if (!InvoiceTransactionStatusService.isConfirmed(invoice)) {
      throw new ManualJournalException('確定済みの請求にだけ手動仕訳を登録できます。');
    }
    // 仕様: Accounting 第8.2節・第8.5節・第8.8節、Core 第7.9.6節。
    // 取消基準日の要否は保存時のこの操作のDiff逆仕訳（plan.reversals）。請求書のActive Lock全体では取らない。
    GlManualJournalSetting__c setting = [
      SELECT Id, IsActive__c, DebitSlotKey__c, CreditSlotKey__c
      FROM GlManualJournalSetting__c
      WHERE Id = :request.settingId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (setting.IsActive__c != true) {
      throw new ManualJournalException('有効な手動仕訳設定だけ選べます。');
    }
    if (
      setting.DebitSlotKey__c == AccountingSlotFixedCatalog.Cash.key ||
      setting.CreditSlotKey__c == AccountingSlotFixedCatalog.Cash.key
    ) {
      throw new ManualJournalException(
        '借方または貸方のスロットが現金・預金です。現預金は請求入出金を使ってください。'
      );
    }
    return invoice;
  }

  private static GlManualJournalHeader__c buildHeader(
    RegisterRequest request,
    Id invoiceId,
    String operationKey
  ) {
    return new GlManualJournalHeader__c(
      Invoice__c = invoiceId,
      GlManualJournalSetting__c = request.settingId,
      PostingDate__c = request.postingDate,
      Amount__c = request.amount,
      TransactionStatus__c = 'Active',
      BusinessOperationKey__c = operationKey
    );
  }

  /** 仕様: Accounting 第10.3節、第10.4節、第8.2節、第8.8節、日付仕様 第7.3節、Core 第7.7.3節 */
  public static void cancel(CancelRequest request) {
    if (request == null || request.headerId == null) {
      throw new ManualJournalException('取消する手動仕訳が指定されていません。');
    }
    if (String.isBlank(request.cancellationReason)) {
      throw new ManualJournalException('取消理由を入力してください。');
    }
    if (request.cancellationReason == 'Other' && String.isBlank(request.cancellationReasonText)) {
      throw new ManualJournalException('取消理由がその他のときは内容を入力してください。');
    }
    // 仕様: 共通基盤 第3.2節・第10.4節。手動仕訳は 14。
    ContractPermissionUtil.assertManualJournal();
    GlManualJournalHeader__c header = resolveHeader(request);
    Invoice__c lockedInvoice =
      request.knownLockedInvoice != null &&
      request.knownLockedInvoice.Id == header.Invoice__c
        ? request.knownLockedInvoice
        : AccountingCauseLockService.lockInvoice(header.Invoice__c);
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      request.businessOperationKey
    );
    if (
      header.TransactionStatus__c == 'Cancelled' &&
      header.BusinessOperationKey__c == operationKey
    ) {
      return;
    }
    // 仕様: Core 第4.3.12節・第7.9.7節。比較値未指定は拒否。検査省略の互換は持たない。
    AccountingCauseLockService.assertInvoiceOperationUnchanged(
      header.Invoice__c,
      request.expectedToken,
      lockedInvoice.LastModifiedDate
    );
    AccountingCurrentService.load(header.Invoice__c);
    if (header.TransactionStatus__c != 'Active') {
      throw new ManualJournalException('有効な手動仕訳だけ取消できます。');
    }
    header.TransactionStatus__c = 'Cancelled';
    header.CancellationReason__c = request.cancellationReason;
    header.CancellationReasonText__c = request.cancellationReasonText;
    header.CancellationDate__c = request.cancellationDate;
    header.BusinessOperationKey__c = operationKey;
    Savepoint savepoint = Database.setSavepoint();
    try {
      Boolean previousWrite = allowLifecycleWrite;
      allowLifecycleWrite = true;
      try {
        update header;
      } finally {
        allowLifecycleWrite = previousWrite;
      }
      AccountingDiffService.rememberManualCancelReason(
        header.Id,
        header.CancellationReason__c,
        header.CancellationReasonText__c
      );
      AccountingDiffService.applyForInvoice(
        header.Invoice__c,
        AccountingEventFixedCatalog.MANUAL_JOURNAL.key,
        operationKey,
        request.cancellationDate,
        lockedInvoice
      );
    } catch (Exception ex) {
      Database.rollback(savepoint);
      throw ex;
    }
    ContractOperationLogService.write(
      'CancelManualJournal',
      operationKey,
      'GlManualJournalHeader__c',
      String.valueOf(header.Id),
      request.cancellationReason,
      request.cancellationReasonText,
      null,
      null
    );
  }

  /**
   * 仕様: Core 第7.9.6節、Accounting 第8.5節・第8.8節・第10.4節。
   * Goal を組む実行前プレビューは組まない。件数・日付内訳は出さない。
   * 取消基準日の要否だけ、このヘッダーの Active Lock 仕訳件数で返す。
   */
  public static AccountingDiffService.CancelPreview previewCancel(
    Id headerId,
    Date cancellationDate
  ) {
    return previewCancel(headerId, cancellationDate, null);
  }

  /** 仕様: Accounting 第8.2節。同一処理でロック済みならプレビューも取り直さない。 */
  public static AccountingDiffService.CancelPreview previewCancel(
    Id headerId,
    Date cancellationDate,
    Invoice__c knownLockedInvoice
  ) {
    return previewCancel(headerId, cancellationDate, knownLockedInvoice, null);
  }

  /** 仕様: Accounting 第8.2節、Core 第12.4節。同一処理で読んだヘッダーを取り直さない。 */
  public static AccountingDiffService.CancelPreview previewCancel(
    Id headerId,
    Date cancellationDate,
    Invoice__c knownLockedInvoice,
    GlManualJournalHeader__c knownHeader
  ) {
    ContractPermissionUtil.assertManualJournal();
    if (headerId == null) {
      throw new ManualJournalException('取消する手動仕訳が指定されていません。');
    }
    GlManualJournalHeader__c header =
      knownHeader != null && knownHeader.Id == headerId
        ? knownHeader
        : queryHeader(headerId);
    Integer lockedCount = [
      SELECT COUNT()
      FROM GlJournal__c
      WHERE
        GlManualJournalHeader__c = :headerId
        AND TransactionStatus__c = 'Active'
        AND IsLocked__c = TRUE
      WITH SYSTEM_MODE
    ];
    AccountingDiffService.CancelPreview preview = emptyConfirmPreview();
    preview.reverseCount = lockedCount;
    return preview;
  }

  private static GlManualJournalHeader__c resolveHeader(CancelRequest request) {
    if (
      request.knownHeader != null &&
      request.knownHeader.Id == request.headerId
    ) {
      return request.knownHeader;
    }
    return queryHeader(request.headerId);
  }

  private static GlManualJournalHeader__c queryHeader(Id headerId) {
    headerSelectCount++;
    List<GlManualJournalHeader__c> headers = [
      SELECT
        Id,
        Invoice__c,
        TransactionStatus__c,
        BusinessOperationKey__c,
        CancellationReason__c,
        CancellationReasonText__c
      FROM GlManualJournalHeader__c
      WHERE Id = :headerId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (headers.isEmpty()) {
      throw new ManualJournalException('取消する手動仕訳が指定されていません。');
    }
    return headers[0];
  }

  /** 仕様: Accounting 第10.2節。参照済みなら削除せず無効化する。 */
  public static void preventReferencedSettingDelete(
    List<GlManualJournalSetting__c> oldRecords
  ) {
    if (oldRecords == null || oldRecords.isEmpty()) {
      return;
    }
    Set<Id> ids = new Map<Id, GlManualJournalSetting__c>(oldRecords).keySet();
    Set<Id> referenced = new Set<Id>();
    for (GlManualJournalHeader__c header : [
      SELECT GlManualJournalSetting__c
      FROM GlManualJournalHeader__c
      WHERE GlManualJournalSetting__c IN :ids
      WITH SYSTEM_MODE
    ]) {
      referenced.add(header.GlManualJournalSetting__c);
    }
    for (GlManualJournalSetting__c setting : oldRecords) {
      if (referenced.contains(setting.Id)) {
        setting.addError('参照されている手動仕訳設定は削除できません。無効化してください。');
      }
    }
  }
}
