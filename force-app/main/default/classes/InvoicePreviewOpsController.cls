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
    public List<SlotNetRowDto> slotNets;
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

  public class JournalRowDto implements Comparable {
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
    /** 仕様: Accounting 第9.1.1節、Core 第7.7.3節。表列に出す。 */
    @AuraEnabled
    public String confirmationText;
    /** 仕様: Core 第7.7.3節。明細フィルタ。商品名列は置かない。 */
    @AuraEnabled
    public Id invoiceLineId;
    @AuraEnabled
    public String productName;
    @AuraEnabled
    public Date servicePeriodStartDate;
    @AuraEnabled
    public Date servicePeriodEndDate;
    /** 仕様: Core 第11.4.4節。 */
    @AuraEnabled
    public Map<String, Object> extraFieldValues;
    /** 仕様: Accounting 第8.7節。画面の同日順。 */
    @AuraEnabled
    public Integer sameDayOrder;
    @AuraEnabled
    public Datetime causeCreatedDate;
    @AuraEnabled
    public String causeRecordId;
    @AuraEnabled
    public Integer recognitionSequence;
    @AuraEnabled
    public Id manualHeaderId;

    /** 仕様: Accounting 第8.7節。計上日・sameDayOrder・原因CreatedDate・原因ID。同じ明細の同日は回番号。 */
    public Integer compareTo(Object otherObj) {
      JournalRowDto other = (JournalRowDto) otherObj;
      Integer dateCmp = compareDates(postingDate, other.postingDate);
      if (dateCmp != 0) {
        return dateCmp;
      }
      Integer leftOrder = sameDayOrder == null ? 0 : sameDayOrder;
      Integer rightOrder = other.sameDayOrder == null ? 0 : other.sameDayOrder;
      if (leftOrder != rightOrder) {
        return leftOrder < rightOrder ? -1 : 1;
      }
      Integer createdCmp = compareDatetimes(causeCreatedDate, other.causeCreatedDate);
      if (createdCmp != 0) {
        return createdCmp;
      }
      Integer leftSeq = recognitionSequence == null ? 0 : recognitionSequence;
      Integer rightSeq = other.recognitionSequence == null ? 0 : other.recognitionSequence;
      if (leftSeq != rightSeq) {
        return leftSeq < rightSeq ? -1 : 1;
      }
      String leftId = causeRecordId == null ? '' : causeRecordId;
      String rightId = other.causeRecordId == null ? '' : other.causeRecordId;
      Integer idCmp = leftId.compareTo(rightId);
      if (idCmp != 0) {
        return idCmp;
      }
      String leftJournal = journalId == null ? '' : String.valueOf(journalId);
      String rightJournal = other.journalId == null ? '' : String.valueOf(other.journalId);
      return leftJournal.compareTo(rightJournal);
    }
  }

  /** 仕様: Core 第8.10節、Accounting 第7.3節。 */
  public class SlotNetRowDto {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String abbreviation;
    @AuraEnabled
    public Decimal amount;
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
    /** 仕様: Accounting 第10.3節・第11.4節。読取専用の借方（略称＋科目名）。 */
    @AuraEnabled
    public String debitAccountName;
    /** 仕様: Accounting 第10.3節・第11.4節。読取専用の貸方（略称＋科目名）。 */
    @AuraEnabled
    public String creditAccountName;
  }

  public class PaymentLineRemainingDto {
    @AuraEnabled
    public Id lineId;
    @AuraEnabled
    public String productName;
    @AuraEnabled
    public Decimal remainingInclusive;
  }

  /** 仕様: Core 第8.6節・第8.9節。LWCから入る明細別割当。受信は get/set。 */
  /** 仕様: Core 第8.6節・第8.9節。LWC JSON は {get;set;} が無いと空。 */
  public class AllocationInputDto {
    @AuraEnabled
    public Id invoiceLineId { get; set; }
    @AuraEnabled
    public Decimal amount { get; set; }
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

  /**
   * 仕様: Core 第7.7.3節、第12.4節、第4.3.11節。
   * 同一取得で範囲COUNTと本体の請求を重ねない。範囲不正の拒否とバンドルは変えない。
   */
  @AuraEnabled
  public static OpsBundleDto getOpsBundle(Id invoiceId, Id contractHistoryId) {
    if (invoiceId == null) {
      return getOpsBundle(invoiceId);
    }
    Id serviceId = resolveOpsBundleContractServiceId(contractHistoryId);
    if (serviceId == null) {
      throw handled(
        '指定された請求が、対象の契約サービスに属していません。画面を開き直してください。'
      );
    }
    List<Invoice__c> invoices = queryOpsInvoices(invoiceId, serviceId);
    if (invoices.isEmpty()) {
      throw handled(
        '指定された請求が、対象の契約サービスに属していません。画面を開き直してください。'
      );
    }
    ContractPermissionUtil.assertViewInvoicePreview();
    return buildOpsBundle(invoices[0]);
  }

  /** 仕様: Core 第7.7.3節、第7.10節。専用の保存済みPDF一覧は返さない。閲覧は「PDFを見る」。 */
  public static OpsBundleDto getOpsBundle(Id invoiceId) {
    ContractPermissionUtil.assertViewInvoicePreview();
    if (invoiceId == null) {
      throw handled('請求が指定されていません。');
    }
    List<Invoice__c> invoices = queryOpsInvoices(invoiceId, null);
    Invoice__c invoice = invoices.isEmpty()
      ? [
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
            LastModifiedDate,
            ContractService__c
          FROM Invoice__c
          WHERE Id = :invoiceId
          WITH SYSTEM_MODE
          LIMIT 1
        ]
      : invoices[0];
    return buildOpsBundle(invoice);
  }

  private static Id resolveOpsBundleContractServiceId(Id contractHistoryId) {
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

  private static List<Invoice__c> queryOpsInvoices(Id invoiceId, Id serviceId) {
    String soql =
      'SELECT ' +
      String.join(opsInvoiceSelectFields(), ',') +
      ' FROM Invoice__c WHERE Id = :invoiceId';
    if (serviceId != null) {
      soql += ' AND ContractService__c = :serviceId';
    }
    soql += ' WITH SYSTEM_MODE LIMIT 1';
    return Database.query(soql);
  }

  private static List<String> opsInvoiceSelectFields() {
    List<String> fields = new List<String>{
      'Id',
      'InvoiceTransactionStatus__c',
      'InvoiceDate__c',
      'SentDate__c',
      'Amount__c',
      'TaxAmount__c',
      'TaxInclusiveAmount__c',
      'PaymentInclusiveTotal__c',
      'InvoicePaymentNet__c',
      'LastModifiedDate',
      'ContractService__c'
    };
    ensureEnabledTagRules();
    Map<String, Schema.SObjectField> invoiceFields = Invoice__c.SObjectType.getDescribe()
      .fields.getMap();
    Set<String> seen = new Set<String>(fields);
    for (GlAccountingTagRule__c rule : cachedEnabledTagRules) {
      if (
        String.isNotBlank(rule.TargetFieldApiName__c) &&
        invoiceFields.containsKey(rule.TargetFieldApiName__c) &&
        seen.add(rule.TargetFieldApiName__c)
      ) {
        fields.add(rule.TargetFieldApiName__c);
      }
    }
    return fields;
  }

  private static OpsBundleDto buildOpsBundle(Invoice__c invoice) {
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
    // 仕様: Core 第12.4節・第4.3.11節・第7.9.7節。本体で読んだ請求の LastModified を渡し、版トークンで取り直さない。invoiceToken は変えない。
    bundle.invoiceToken = AccountingCauseLockService.resolveInvoiceOperationToken(
      invoice.Id,
      invoice.LastModifiedDate
    );
    bundle.paymentLines = loadPaymentLines(invoice.Id);
    bundle.payments = loadPayments(invoice.Id);
    bundle.journals = loadJournals(invoice.Id);
    bundle.slotNets = slotNetsFromJournalRows(bundle.journals);
    // 仕様: Core 第12.4節・第4.3.11節・第7.7.3節。本体で読んだ請求をタグ結果で取り直さない。タグ行は変えない。
    bundle.tagResults = loadTagResults(invoice);
    bundle.manualJournals = loadManualJournals(invoice.Id, bundle.journals);
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
      throw handledFrom(ex);
    }
  }

  /** 仕様: Accounting 第9.5節、Core 第12.4節。グルーピング済み仕訳は取り直さない。 */
  public static Integer lockJournalsForInvoice(
    Id invoiceId,
    List<Id> journalIds,
    String expectedToken,
    String businessOperationKey,
    List<GlJournal__c> knownJournals
  ) {
    ContractPermissionUtil.assertLockJournal();
    try {
      return JournalLockService.lockForInvoice(
        invoiceId,
        journalIds,
        expectedToken,
        businessOperationKey,
        knownJournals
      );
    } catch (Exception ex) {
      throw handledFrom(ex);
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
      throw handledFrom(ex);
    }
  }

  /** 仕様: Accounting 第9.5節、Core 第12.4節。グルーピング済み仕訳は取り直さない。 */
  public static Integer unlockJournalsForInvoice(
    Id invoiceId,
    List<Id> journalIds,
    String reason,
    String expectedToken,
    String businessOperationKey,
    List<GlJournal__c> knownJournals
  ) {
    ContractPermissionUtil.assertUnlockJournal();
    try {
      return JournalLockService.unlockForInvoice(
        invoiceId,
        journalIds,
        reason,
        expectedToken,
        businessOperationKey,
        knownJournals
      );
    } catch (Exception ex) {
      throw handledFrom(ex);
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

  @TestVisible
  static Integer journalMemoSelectCount = 0;

  @AuraEnabled
  public static void updateJournalMemo(
    Id journalId,
    String memo,
    Id invoiceId,
    Map<String, Object> extraFieldValues
  ) {
    updateJournalMemo(journalId, memo, invoiceId, extraFieldValues, null);
  }

  /** 仕様: Core 第12.4節。Lock済み仕訳は取り直さない。メモだけの保存は従来どおりSELECTする。 */
  public static void updateJournalMemo(
    Id journalId,
    String memo,
    Id invoiceId,
    Map<String, Object> extraFieldValues,
    GlJournal__c knownJournal
  ) {
    assertCanEditJournalMemo();
    if (journalId == null || invoiceId == null) {
      throw handled('仕訳が指定されていません。');
    }
    GlJournal__c journal = journalForMemo(journalId, knownJournal);
    if (journal.Invoice__c != invoiceId) {
      throw handled('この請求以外の仕訳のメモは保存できません。');
    }
    if (InvoiceTransactionStatusService.isCancelled(journal.Invoice__r)) {
      throw handled('取消済み請求の仕訳メモは編集できません。');
    }
    updateJournalMemoInternal(journalId, memo, extraFieldValues, journal.IsLocked__c == true);
  }

  private static GlJournal__c journalForMemo(
    Id journalId,
    GlJournal__c knownJournal
  ) {
    if (knownJournal != null && knownJournal.Id == journalId) {
      return knownJournal;
    }
    journalMemoSelectCount++;
    return [
      SELECT Id, Invoice__c, Invoice__r.InvoiceTransactionStatus__c, IsLocked__c
      FROM GlJournal__c
      WHERE Id = :journalId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
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
      throw handledFrom(ex);
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
    try {
      Invoice__c locked = AccountingCauseLockService.lockInvoice(invoiceId);
      InvoiceOpsController.assertInvoicesInScope(
        contractHistoryId,
        new List<Id>{ invoiceId },
        locked
      );
      return savePaymentFromPreviewNow(
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
        extraFieldValues,
        locked
      );
    } catch (AuraHandledException ex) {
      throw ex;
    } catch (Exception ex) {
      throw handledFrom(ex);
    }
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
    return savePaymentFromPreviewNow(
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
      null,
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
    return savePaymentFromPreviewNow(
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
      extraFieldValues,
      null
    );
  }

  private static Id savePaymentFromPreviewNow(
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
    Map<String, Object> extraFieldValues,
    Invoice__c knownLockedInvoice
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
    request.knownLockedInvoice = knownLockedInvoice;
    if (resolvedPurpose == InvoicePaymentService.PURPOSE_INVOICE) {
      request.allocations = toAllocationLines(
        allocations == null ? new List<AllocationInputDto>() : allocations
      );
    }
    try {
      return InvoicePaymentService.register(request);
    } catch (Exception ex) {
      throw handledFrom(ex);
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
      throw handledFrom(ex);
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
    Invoice__c locked = AccountingCauseLockService.lockInvoice(invoiceId);
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId },
      locked
    );
    return previewRegisterFromPreviewNow(
      invoiceId,
      amount,
      purpose,
      paymentDate,
      memo,
      expectedToken,
      allocations,
      cancellationDate,
      locked
    );
  }

  /** 仕様: Core 第7.9.6節、第7.9.7節、第8.9節、Accounting 第8.5節・第8.8節、日付仕様 第7.3節 */
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
    return previewRegisterFromPreviewNow(
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

  /** 仕様: Accounting 第8.2節、Core 第7.9.7節・第12.4節。ロック済み請求の版と比較し取り直さない。 */
  private static AccountingDiffService.CancelPreview previewRegisterFromPreviewNow(
    Id invoiceId,
    Decimal amount,
    String purpose,
    Date paymentDate,
    String memo,
    String expectedToken,
    List<AllocationInputDto> allocations,
    Date cancellationDate,
    Invoice__c knownLockedInvoice
  ) {
    ContractPermissionUtil.assertInvoicePayment();
    if (invoiceId == null || amount == null || amount == 0 || paymentDate == null) {
      throw handled('請求、0以外の金額、入出金日を入力してください。');
    }
    Invoice__c invoice =
      knownLockedInvoice != null && knownLockedInvoice.Id == invoiceId
        ? knownLockedInvoice
        : AccountingCauseLockService.lockInvoice(invoiceId);
    AccountingCauseLockService.assertInvoiceOperationsUnchanged(
      new Map<Id, String>{ invoice.Id => expectedToken },
      new Map<Id, Datetime>{ invoice.Id => invoice.LastModifiedDate }
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
    request.knownLockedInvoice = invoice;
    if (resolvedPurpose == InvoicePaymentService.PURPOSE_INVOICE) {
      request.allocations = toAllocationLines(
        allocations == null ? new List<AllocationInputDto>() : allocations
      );
    }
    try {
      return InvoicePaymentService.previewRegister(request);
    } catch (Exception ex) {
      throw handledFrom(ex);
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
    Invoice__c locked = AccountingCauseLockService.lockInvoice(invoiceId);
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId },
      locked
    );
    return previewCancelPaymentFromPreviewNow(paymentId, invoiceId, cancelDate, locked);
  }

  /** 仕様: Core 第7.9.6節、Accounting 第8.5節 */
  public static AccountingDiffService.CancelPreview previewCancelPaymentFromPreview(
    Id paymentId,
    Id invoiceId,
    Date cancelDate
  ) {
    return previewCancelPaymentFromPreviewNow(paymentId, invoiceId, cancelDate, null);
  }

  /** 仕様: Accounting 第8.2節。入口で読んだ入出金とロック済み請求は取り直さない。 */
  private static AccountingDiffService.CancelPreview previewCancelPaymentFromPreviewNow(
    Id paymentId,
    Id invoiceId,
    Date cancelDate,
    Invoice__c knownLockedInvoice
  ) {
    ContractPermissionUtil.assertInvoicePayment();
    if (paymentId == null || invoiceId == null) {
      throw handled('取消する入出金が指定されていません。');
    }
    InvoicePayment__c existing = [
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
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (existing.Invoice__c != invoiceId) {
      throw handled('入金が指定した請求に属していません。');
    }
    try {
      return InvoicePaymentService.previewCancel(
        paymentId,
        cancelDate,
        knownLockedInvoice,
        existing
      );
    } catch (Exception ex) {
      throw handledFrom(ex);
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
    Invoice__c locked = AccountingCauseLockService.lockInvoice(invoiceId);
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId },
      locked
    );
    return cancelPaymentFromPreviewNow(
      paymentId,
      invoiceId,
      cancelDate,
      cancellationReason,
      cancellationReasonText,
      expectedToken,
      businessOperationKey,
      locked
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
    return cancelPaymentFromPreviewNow(
      paymentId,
      invoiceId,
      cancelDate,
      cancellationReason,
      cancellationReasonText,
      expectedToken,
      businessOperationKey,
      null
    );
  }

  /** 仕様: Accounting 第8.2節、Core 第7.7.3節・第12.4節。入口で読んだ入出金とロック済み請求は取り直さない。 */
  private static Id cancelPaymentFromPreviewNow(
    Id paymentId,
    Id invoiceId,
    Date cancelDate,
    String cancellationReason,
    String cancellationReasonText,
    String expectedToken,
    String businessOperationKey,
    Invoice__c knownLockedInvoice
  ) {
    ContractPermissionUtil.assertInvoicePayment();
    InvoicePayment__c existing = [
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
    request.knownLockedInvoice = knownLockedInvoice;
    request.knownPayment = existing;
    try {
      return InvoicePaymentService.cancel(request);
    } catch (Exception ex) {
      throw handledFrom(ex);
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

  /** 仕様: Core 第7.7.3節、Accounting 第5.2節、第9.3節、第8.7節、第9.5節、第11.1節 */
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
        ConfirmationText__c,
        RecognitionSequence__c,
        InvoiceLine__c,
        InvoiceLine__r.ProductName__c,
        InvoiceLine__r.ServicePeriodStartDate__c,
        InvoiceLine__r.ServicePeriodEndDate__c,
        InvoiceLine__r.CreatedDate,
        InvoicePayment__c,
        InvoicePayment__r.CreatedDate,
        InvoicePaymentAllocation__c,
        InvoicePaymentAllocation__r.CreatedDate,
        GlManualJournalHeader__c,
        GlManualJournalHeader__r.CreatedDate,
        GlManualJournalSetting__c,
        GlManualJournalSetting__r.Name
      FROM GlJournal__c
      WHERE Invoice__c = :invoiceId
      AND TransactionStatus__c != 'LogicallyDeleted'
      WITH SYSTEM_MODE
    ]) {
      JournalRowDto row = new JournalRowDto();
      row.journalId = journal.Id;
      row.eventKey = journal.AccountingEventKey__c;
      row.eventName = journalListDisplayName(journal);
      row.patternKey = journal.JournalPatternKey__c;
      row.debitSlotKey = journal.DebitSlotKey__c;
      row.creditSlotKey = journal.CreditSlotKey__c;
      row.debitAccountName = AccountingSlotFixedCatalog.slotAndAccount(
        journal.DebitSlotKey__c,
        journal.DebitAccount__r == null ? null : journal.DebitAccount__r.Name
      );
      row.creditAccountName = AccountingSlotFixedCatalog.slotAndAccount(
        journal.CreditSlotKey__c,
        journal.CreditAccount__r == null ? null : journal.CreditAccount__r.Name
      );
      row.amount = journal.Amount__c;
      row.postingDate = journal.PostingDate__c;
      row.transactionStatus = journal.TransactionStatus__c;
      row.isLocked = journal.IsLocked__c == true;
      row.memo = journal.Memo__c;
      row.confirmationText = journal.ConfirmationText__c;
      row.invoiceLineId = journal.InvoiceLine__c;
      row.productName = journal.InvoiceLine__r == null
        ? null
        : journal.InvoiceLine__r.ProductName__c;
      row.servicePeriodStartDate = journal.InvoiceLine__r == null
        ? null
        : journal.InvoiceLine__r.ServicePeriodStartDate__c;
      row.servicePeriodEndDate = journal.InvoiceLine__r == null
        ? null
        : journal.InvoiceLine__r.ServicePeriodEndDate__c;
      row.sameDayOrder = sameDayOrderOf(journal.JournalPatternKey__c);
      row.recognitionSequence = journal.RecognitionSequence__c == null
        ? 0
        : journal.RecognitionSequence__c.intValue();
      row.manualHeaderId = journal.GlManualJournalHeader__c;
      fillCauseSort(journal, row);
      rows.add(row);
    }
    rows.sort();
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

  /** 仕様: Core 第8.10節、Accounting 第7.3節。 */
  private static List<SlotNetRowDto> slotNetsFromJournalRows(
    List<JournalRowDto> rows
  ) {
    List<GlJournal__c> records = new List<GlJournal__c>();
    if (rows != null) {
      for (JournalRowDto row : rows) {
        records.add(
          new GlJournal__c(
            Amount__c = row.amount,
            DebitSlotKey__c = row.debitSlotKey,
            CreditSlotKey__c = row.creditSlotKey,
            TransactionStatus__c = row.transactionStatus
          )
        );
      }
    }
    Map<String, Decimal> nets = AccountingTagEvaluationService.slotAbbreviationNets(
      records
    );
    List<SlotNetRowDto> out = new List<SlotNetRowDto>();
    for (
      AccountingSlotFixedCatalog.Definition slot : AccountingSlotFixedCatalog.values()
    ) {
      if (!nets.containsKey(slot.abbreviation)) {
        continue;
      }
      SlotNetRowDto dto = new SlotNetRowDto();
      dto.key = slot.abbreviation;
      dto.abbreviation = slot.abbreviation;
      dto.amount = nets.get(slot.abbreviation);
      out.add(dto);
    }
    return out;
  }

  private static List<GlAccountingTagRule__c> cachedEnabledTagRules;

  @TestVisible
  static Integer tagInvoiceSelectCount = 0;

  private static void ensureEnabledTagRules() {
    if (cachedEnabledTagRules == null) {
      cachedEnabledTagRules = [
        SELECT TagLabel__c, TargetFieldApiName__c
        FROM GlAccountingTagRule__c
        WHERE IsEnabled__c = TRUE
        WITH SYSTEM_MODE
        ORDER BY TagLabel__c ASC
      ];
    }
  }

  /** 仕様: Accounting 第7.6節、第11.2節、Core 第12.4節・第4.3.11節・第7.7.3節・第8.10節 */
  private static List<TagResultRowDto> loadTagResults(Invoice__c invoice) {
    List<TagResultRowDto> rows = new List<TagResultRowDto>();
    ensureEnabledTagRules();
    List<GlAccountingTagRule__c> rules = cachedEnabledTagRules;
    if (rules.isEmpty()) {
      return rows;
    }
    Map<String, Schema.SObjectField> invoiceFields = Invoice__c.SObjectType.getDescribe()
      .fields.getMap();
    for (GlAccountingTagRule__c rule : rules) {
      Boolean value = invoiceFields.containsKey(rule.TargetFieldApiName__c)
        ? (Boolean) invoice.get(rule.TargetFieldApiName__c) == true
        : false;
      TagResultRowDto row = new TagResultRowDto();
      row.name = rule.TagLabel__c;
      row.fieldApiName = rule.TargetFieldApiName__c;
      row.value = value;
      rows.add(row);
    }
    return rows;
  }

  @TestVisible
  static Integer manualJournalLockSelectCount = 0;

  /** 仕様: Accounting 第10.3節、第10.4節、第8.5節、Core 第0.1節、第7.9.6節、日付仕様 第7.3節 */
  private static List<ManualJournalRowDto> loadManualJournals(
    Id invoiceId,
    List<JournalRowDto> journals
  ) {
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
    // 仕様: Accounting 第8.5節。取消基準日要否はこのヘッダーのDiffで逆仕訳になるLock。請求書全体では見ない。
    Map<Id, Boolean> lockedByHeaderId = new Map<Id, Boolean>();
    if (journals != null) {
      for (JournalRowDto journal : journals) {
        if (
          journal != null &&
          journal.manualHeaderId != null &&
          journal.isLocked == true &&
          journal.transactionStatus == 'Active'
        ) {
          lockedByHeaderId.put(journal.manualHeaderId, true);
        }
      }
    }
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
      row.hasLockedJournals = lockedByHeaderId.get(header.Id) == true;
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
      SELECT
        Id,
        Name,
        Description__c,
        DebitSlotKey__c,
        DebitAccount__r.Name,
        CreditSlotKey__c,
        CreditAccount__r.Name
      FROM GlManualJournalSetting__c
      WHERE IsActive__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY SortOrder__c ASC NULLS LAST, Name ASC
    ]) {
      ManualSettingRowDto row = new ManualSettingRowDto();
      row.settingId = setting.Id;
      row.label = setting.Name;
      row.description = setting.Description__c;
      row.debitAccountName = AccountingSlotFixedCatalog.slotAndAccount(
        setting.DebitSlotKey__c,
        setting.DebitAccount__r == null ? null : setting.DebitAccount__r.Name
      );
      row.creditAccountName = AccountingSlotFixedCatalog.slotAndAccount(
        setting.CreditSlotKey__c,
        setting.CreditAccount__r == null ? null : setting.CreditAccount__r.Name
      );
      rows.add(row);
    }
    return rows;
  }

  /** 仕様: Accounting 第5.2節。列表示はパターン別名。手動は設定Name。 */
  private static String journalListDisplayName(GlJournal__c journal) {
    String patternName = JournalPatternFixedCatalog.listDisplayName(
      journal.JournalPatternKey__c
    );
    if (!String.isBlank(patternName)) {
      return patternName;
    }
    return journal.GlManualJournalSetting__r == null
      ? null
      : journal.GlManualJournalSetting__r.Name;
  }

  /** 仕様: Accounting 第8.7節。手動はパターン無し。Goalの手動sameDayOrderは80。 */
  private static Integer sameDayOrderOf(String patternKey) {
    if (String.isBlank(patternKey)) {
      return 80;
    }
    for (JournalPatternFixedCatalog.Definition definition : JournalPatternFixedCatalog.values()) {
      if (definition.key == patternKey) {
        return definition.sameDayOrder;
      }
    }
    return 80;
  }

  /** 仕様: Accounting 第8.7節。原因は割当／入出金／明細／手動ヘッダー。 */
  private static void fillCauseSort(GlJournal__c journal, JournalRowDto row) {
    if (journal.InvoicePaymentAllocation__c != null) {
      row.causeRecordId = String.valueOf(journal.InvoicePaymentAllocation__c);
      row.causeCreatedDate = journal.InvoicePaymentAllocation__r == null
        ? null
        : journal.InvoicePaymentAllocation__r.CreatedDate;
      return;
    }
    if (journal.InvoicePayment__c != null) {
      row.causeRecordId = String.valueOf(journal.InvoicePayment__c);
      row.causeCreatedDate = journal.InvoicePayment__r == null
        ? null
        : journal.InvoicePayment__r.CreatedDate;
      return;
    }
    if (journal.InvoiceLine__c != null) {
      row.causeRecordId = String.valueOf(journal.InvoiceLine__c);
      row.causeCreatedDate = journal.InvoiceLine__r == null
        ? null
        : journal.InvoiceLine__r.CreatedDate;
      return;
    }
    if (journal.GlManualJournalHeader__c != null) {
      row.causeRecordId = String.valueOf(journal.GlManualJournalHeader__c);
      row.causeCreatedDate = journal.GlManualJournalHeader__r == null
        ? null
        : journal.GlManualJournalHeader__r.CreatedDate;
    }
  }

  private static Integer compareDates(Date left, Date right) {
    if (left == right) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return left < right ? -1 : 1;
  }

  private static Integer compareDatetimes(Datetime left, Datetime right) {
    if (left == right) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return left.getTime() < right.getTime() ? -1 : 1;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  /** 仕様: Core 第0章。DML 拒否は項目検証の日本語本文を返す。 */
  private static AuraHandledException handledFrom(Exception ex) {
    if (ex instanceof DmlException) {
      DmlException dml = (DmlException) ex;
      if (dml.getNumDml() > 0 && String.isNotBlank(dml.getDmlMessage(0))) {
        return handled(dml.getDmlMessage(0));
      }
    }
    return handled(ex == null ? null : ex.getMessage());
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
