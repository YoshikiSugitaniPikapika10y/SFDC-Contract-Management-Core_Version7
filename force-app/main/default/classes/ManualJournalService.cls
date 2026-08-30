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
  }

  public class CancelRequest {
    public Id headerId;
    public String cancellationReason;
    public String cancellationReasonText;
    public Date cancellationDate;
    public String businessOperationKey;
    public String expectedToken;
  }

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
      request.expectedToken
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
        request.cancellationDate
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
   * 仕様: Accounting 第8.8節・第8.2節・第8.5節、Core 第7.9.6節。
   * 手動登録も仕訳処理へ進む。実行前に Goal Diff 件数を出す。保存しない。
   */
  public static AccountingDiffService.CancelPreview previewRegister(
    RegisterRequest request
  ) {
    ContractPermissionUtil.assertManualJournal();
    Invoice__c invoice = prepareRegister(request);
    Savepoint savepoint = Database.setSavepoint();
    try {
      insert buildHeader(request, invoice.Id, null);
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewApply(
        invoice.Id,
        AccountingEventFixedCatalog.MANUAL_JOURNAL.key,
        request.cancellationDate
      );
      Database.rollback(savepoint);
      return preview;
    } catch (Exception ex) {
      Database.rollback(savepoint);
      throw ex;
    }
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
    Invoice__c invoice = AccountingCauseLockService.lockInvoice(request.invoiceId);
    GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
    if (policy.AccountingEnabled__c != true) {
      throw new ManualJournalException('AccountingがOFFのときは手動仕訳を登録できません。');
    }
    if (!InvoiceTransactionStatusService.isConfirmed(invoice)) {
      throw new ManualJournalException('確定済みの請求にだけ手動仕訳を登録できます。');
    }
    // 仕様: Accounting 第8.2節・第8.5節・第8.8節、Core 第7.9.6節。
    // 手動登録も Goal/Diff/Lock。請求書単位の Active Lock があるとき取消基準日必須（入金登録と同じ）。
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
      throw new ManualJournalException('ロック済み仕訳がある取消では取消基準日が必要です。');
    }
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
    GlManualJournalHeader__c header = [
      SELECT Id, Invoice__c, TransactionStatus__c, BusinessOperationKey__c
      FROM GlManualJournalHeader__c
      WHERE Id = :request.headerId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    AccountingCauseLockService.lockInvoice(header.Invoice__c);
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      request.businessOperationKey
    );
    header = [
      SELECT Id, Invoice__c, TransactionStatus__c, BusinessOperationKey__c
      FROM GlManualJournalHeader__c
      WHERE Id = :request.headerId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (
      header.TransactionStatus__c == 'Cancelled' &&
      header.BusinessOperationKey__c == operationKey
    ) {
      return;
    }
    // 仕様: Core 第4.3.12節・第7.9.7節。比較値未指定は拒否。検査省略の互換は持たない。
    AccountingCauseLockService.assertInvoiceOperationUnchanged(
      header.Invoice__c,
      request.expectedToken
    );
    if (header.TransactionStatus__c != 'Active') {
      throw new ManualJournalException('有効な手動仕訳だけ取消できます。');
    }
    // 仕様: Accounting 第8.5節・第8.8節、Core 第7.9.6節。
    // 取消基準日要否は請求書単位の Active Lock（入金取消と同じ）。ヘッダー配下だけ見ない。
    Integer locked = [
      SELECT COUNT()
      FROM GlJournal__c
      WHERE
        Invoice__c = :header.Invoice__c
        AND IsLocked__c = TRUE
        AND TransactionStatus__c = 'Active'
      WITH SYSTEM_MODE
    ];
    if (locked > 0 && request.cancellationDate == null) {
      throw new ManualJournalException('ロック済み仕訳がある取消では取消基準日が必要です。');
    }
    previewCancel(header.Id, request.cancellationDate);
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
      AccountingDiffService.applyForInvoice(
        header.Invoice__c,
        AccountingEventFixedCatalog.MANUAL_JOURNAL.key,
        operationKey,
        request.cancellationDate
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
   * 仕様: Core 第7.9.6節、Accounting 第8.5節・第8.8節・第10.4節、日付仕様 第7.3節。
   * ON はヘッダー除外後の Goal Diff（previewApply）と実行後を一致させる。
   * OFF は cancelCurrent と同じ isCancelTarget 経路。
   */
  public static AccountingDiffService.CancelPreview previewCancel(
    Id headerId,
    Date cancellationDate
  ) {
    ContractPermissionUtil.assertManualJournal();
    if (headerId == null) {
      throw new ManualJournalException('取消する手動仕訳が指定されていません。');
    }
    GlManualJournalHeader__c header = [
      SELECT Id, Invoice__c, TransactionStatus__c
      FROM GlManualJournalHeader__c
      WHERE Id = :headerId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
    if (policy.AccountingEnabled__c != true) {
      return AccountingDiffService.previewCancel(
        header.Invoice__c,
        AccountingEventFixedCatalog.MANUAL_JOURNAL.key,
        cancellationDate,
        null,
        header.Id
      );
    }
    // 入金登録 previewRegister と同じく、原因を外したうえで Goal Diff を数える。
    Savepoint savepoint = Database.setSavepoint();
    try {
      header.TransactionStatus__c = 'Cancelled';
      update header;
      AccountingDiffService.CancelPreview preview = AccountingDiffService.previewApply(
        header.Invoice__c,
        AccountingEventFixedCatalog.MANUAL_JOURNAL.key,
        cancellationDate
      );
      Database.rollback(savepoint);
      return preview;
    } catch (Exception ex) {
      Database.rollback(savepoint);
      throw ex;
    }
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
