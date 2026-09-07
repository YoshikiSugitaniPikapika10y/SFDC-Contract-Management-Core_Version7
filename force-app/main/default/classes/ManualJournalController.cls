public with sharing class ManualJournalController {
  /** 仕様: Accounting 第10.3節、第11.4節 */
  public static Id register(
    Id invoiceId,
    Id settingId,
    Date postingDate,
    Decimal amount
  ) {
    return register(invoiceId, settingId, postingDate, amount, null, null, null);
  }

  /** 仕様: Accounting 第10.3節、第11.4節、Core 第7.7.3節・第7.9.7節 */
  public static Id register(
    Id invoiceId,
    Id settingId,
    Date postingDate,
    Decimal amount,
    String expectedToken,
    String businessOperationKey
  ) {
    return register(
      invoiceId,
      settingId,
      postingDate,
      amount,
      null,
      expectedToken,
      businessOperationKey
    );
  }

  /**
   * 仕様: Core 第7.7.3節、Accounting 第10.3節、第8.2節・第8.5節・第8.8節、
   * Core 第7.9.6節・第7.9.7節。Lock時は取消基準日必須。件数プレビューは previewRegister。
   */
  @AuraEnabled
  public static Id register(
    Id invoiceId,
    Id settingId,
    Date postingDate,
    Decimal amount,
    Date cancellationDate,
    String expectedToken,
    String businessOperationKey,
    Id contractHistoryId
  ) {
    Invoice__c locked = AccountingCauseLockService.lockInvoice(invoiceId);
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId },
      locked
    );
    ManualJournalService.RegisterRequest request = new ManualJournalService.RegisterRequest();
    request.invoiceId = invoiceId;
    request.settingId = settingId;
    request.postingDate = postingDate;
    request.amount = amount;
    request.cancellationDate = cancellationDate;
    request.businessOperationKey = businessOperationKey;
    request.expectedToken = expectedToken;
    request.knownLockedInvoice = locked;
    return ManualJournalService.register(request);
  }

  /** 仕様: Accounting 第10.3節、第8.2節・第8.5節・第8.8節、Core 第7.7.3節・第7.9.6節・第7.9.7節 */
  public static Id register(
    Id invoiceId,
    Id settingId,
    Date postingDate,
    Decimal amount,
    Date cancellationDate,
    String expectedToken,
    String businessOperationKey
  ) {
    // 権限は ManualJournalService.register → assertManualJournal
    ManualJournalService.RegisterRequest request = new ManualJournalService.RegisterRequest();
    request.invoiceId = invoiceId;
    request.settingId = settingId;
    request.postingDate = postingDate;
    request.amount = amount;
    request.cancellationDate = cancellationDate;
    request.businessOperationKey = businessOperationKey;
    request.expectedToken = expectedToken;
    return ManualJournalService.register(request);
  }

  /** 仕様: Core 第7.7.3節、第7.9.6節、Accounting 第10.4節、第8.5節 */
  @AuraEnabled
  public static AccountingDiffService.CancelPreview previewCancel(
    Id headerId,
    Date cancellationDate,
    Id contractHistoryId
  ) {
    GlManualJournalHeader__c header = loadHeader(headerId);
    Invoice__c locked = AccountingCauseLockService.lockInvoice(header.Invoice__c);
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ header.Invoice__c },
      locked
    );
    return previewCancel(header.Id, cancellationDate, locked, header);
  }

  /** 仕様: Core 第7.9.6節、Accounting 第10.4節、第8.5節 */
  public static AccountingDiffService.CancelPreview previewCancel(
    Id headerId,
    Date cancellationDate
  ) {
    return previewCancel(headerId, cancellationDate, null, null);
  }

  private static AccountingDiffService.CancelPreview previewCancel(
    Id headerId,
    Date cancellationDate,
    Invoice__c knownLockedInvoice,
    GlManualJournalHeader__c knownHeader
  ) {
    try {
      return ManualJournalService.previewCancel(
        headerId,
        cancellationDate,
        knownLockedInvoice,
        knownHeader
      );
    } catch (Exception ex) {
      String resolved = String.isNotBlank(ex.getMessage())
        ? ex.getMessage()
        : '処理中にエラーが発生しました。';
      AuraHandledException handled = new AuraHandledException(resolved);
      handled.setMessage(resolved);
      throw handled;
    }
  }

  /**
   * 仕様: Core 第7.7.3節、Accounting 第8.8節・第8.2節・第8.5節、Core 第7.9.6節。
   * 手動登録の実行前件数プレビュー。保存しない。
   */
  @AuraEnabled
  public static AccountingDiffService.CancelPreview previewRegister(
    Id invoiceId,
    Id settingId,
    Date postingDate,
    Decimal amount,
    Date cancellationDate,
    String expectedToken,
    Id contractHistoryId
  ) {
    Invoice__c locked = AccountingCauseLockService.lockInvoice(invoiceId);
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId },
      locked
    );
    ContractPermissionUtil.assertManualJournal();
    try {
      ManualJournalService.RegisterRequest request = new ManualJournalService.RegisterRequest();
      request.invoiceId = invoiceId;
      request.settingId = settingId;
      request.postingDate = postingDate;
      request.amount = amount;
      request.cancellationDate = cancellationDate;
      request.expectedToken = expectedToken;
      request.knownLockedInvoice = locked;
      return ManualJournalService.previewRegister(request);
    } catch (Exception ex) {
      String resolved = String.isNotBlank(ex.getMessage())
        ? ex.getMessage()
        : '処理中にエラーが発生しました。';
      AuraHandledException handled = new AuraHandledException(resolved);
      handled.setMessage(resolved);
      throw handled;
    }
  }

  /** 仕様: Accounting 第10.4節、第11.4節 */
  public static void cancel(
    Id headerId,
    String cancellationReason,
    String cancellationReasonText,
    Date cancellationDate
  ) {
    cancel(
      headerId,
      cancellationReason,
      cancellationReasonText,
      cancellationDate,
      null,
      null
    );
  }

  /** 仕様: Core 第7.7.3節、Accounting 第10.4節、第11.4節、Core 第7.9.7節 */
  @AuraEnabled
  public static void cancel(
    Id headerId,
    String cancellationReason,
    String cancellationReasonText,
    Date cancellationDate,
    String expectedToken,
    String businessOperationKey,
    Id contractHistoryId
  ) {
    GlManualJournalHeader__c header = loadHeader(headerId);
    Invoice__c locked = AccountingCauseLockService.lockInvoice(header.Invoice__c);
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ header.Invoice__c },
      locked
    );
    ManualJournalService.CancelRequest request = new ManualJournalService.CancelRequest();
    request.headerId = headerId;
    request.cancellationReason = cancellationReason;
    request.cancellationReasonText = cancellationReasonText;
    request.cancellationDate = cancellationDate;
    request.businessOperationKey = businessOperationKey;
    request.expectedToken = expectedToken;
    request.knownLockedInvoice = locked;
    request.knownHeader = header;
    ManualJournalService.cancel(request);
  }

  /** 仕様: Accounting 第10.4節、第11.4節、Core 第7.7.3節・第7.9.7節 */
  public static void cancel(
    Id headerId,
    String cancellationReason,
    String cancellationReasonText,
    Date cancellationDate,
    String expectedToken,
    String businessOperationKey
  ) {
    // 権限は ManualJournalService.cancel → assertManualJournal
    ManualJournalService.CancelRequest request = new ManualJournalService.CancelRequest();
    request.headerId = headerId;
    request.cancellationReason = cancellationReason;
    request.cancellationReasonText = cancellationReasonText;
    request.cancellationDate = cancellationDate;
    request.businessOperationKey = businessOperationKey;
    request.expectedToken = expectedToken;
    ManualJournalService.cancel(request);
  }

  /** 仕様: Core 第7.7.3節、第12.4節。ヘッダーは1回読み、請求範囲と取消へ渡す。 */
  private static GlManualJournalHeader__c loadHeader(Id headerId) {
    if (headerId == null) {
      AuraHandledException handled = new AuraHandledException(
        '取消する手動仕訳が指定されていません。'
      );
      handled.setMessage('取消する手動仕訳が指定されていません。');
      throw handled;
    }
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
      AuraHandledException handled = new AuraHandledException(
        '取消する手動仕訳が指定されていません。'
      );
      handled.setMessage('取消する手動仕訳が指定されていません。');
      throw handled;
    }
    return headers[0];
  }
}
