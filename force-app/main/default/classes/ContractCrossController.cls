/**
 * 契約横断画面のAura入口。一覧取得と既存手続きへの委譲。
 * 仕様: Core 第9章、横断画面.md
 */
public without sharing class ContractCrossController {
  public class CrossException extends Exception {
  }

  public class BootstrapDto {
    @AuraEnabled
    public Boolean accountingEnabled;
    @AuraEnabled
    public Date estimateCloseFrom;
    @AuraEnabled
    public Date estimateCloseTo;
    @AuraEnabled
    public Date journalPostingFrom;
    @AuraEnabled
    public Date journalPostingTo;
    @AuraEnabled
    public Boolean canIssueEstimate;
    @AuraEnabled
    public Boolean canSendEstimate;
    @AuraEnabled
    public Boolean canOrder;
    @AuraEnabled
    public Boolean canShowEstimateMenu;
    @AuraEnabled
    public Boolean canShowInvoiceMenu;
    @AuraEnabled
    public String estimateSendMode;
    /** 仕様: 横断画面.md 第1節、Core 第4.10節 */
    @AuraEnabled
    public String invoiceSendMode;
    @AuraEnabled
    public List<TagRuleDto> tagRules;
    @AuraEnabled
    public List<SelectOptionDto> eventOptions;
    /** 仕様: 横断画面.md 第2.4節、Core 第11.4.4節。 */
    @AuraEnabled
    public List<String> journalLockExemptFieldApiNames;
  }

  public class SelectOptionDto {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
  }

  public class TagRuleDto {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String fieldApiName;
    @AuraEnabled
    public String tagKey;
  }

  public class TagFilterDto {
    @AuraEnabled
    public String fieldApiName { get; set; }
    @AuraEnabled
    public String state { get; set; }
  }

  public class EstimateFilterDto {
    @AuraEnabled
    public Date closeDateFrom { get; set; }
    @AuraEnabled
    public Date closeDateTo { get; set; }
    @AuraEnabled
    public Id accountId { get; set; }
    @AuraEnabled
    public Id serviceId { get; set; }
    @AuraEnabled
    public String estimateType { get; set; }
    @AuraEnabled
    public Boolean sent { get; set; }
    @AuraEnabled
    public Boolean issued { get; set; }
    @AuraEnabled
    public Boolean autoRenew { get; set; }
    @AuraEnabled
    public Date validDateFrom { get; set; }
    @AuraEnabled
    public Date validDateTo { get; set; }
  }

  public class InvoiceFilterDto {
    @AuraEnabled
    public String invoiceStatus { get; set; }
    @AuraEnabled
    public String invoiceName { get; set; }
    @AuraEnabled
    public Id billingAccountId { get; set; }
    @AuraEnabled
    public Id accountId { get; set; }
    @AuraEnabled
    public Date invoiceDateFrom { get; set; }
    @AuraEnabled
    public Date invoiceDateTo { get; set; }
    @AuraEnabled
    public Date closeDateFrom { get; set; }
    @AuraEnabled
    public Date closeDateTo { get; set; }
    @AuraEnabled
    public Boolean includeCancelled { get; set; }
    @AuraEnabled
    public Boolean sent { get; set; }
    @AuraEnabled
    public Boolean issued { get; set; }
    @AuraEnabled
    public Boolean overdue { get; set; }
    @AuraEnabled
    public String collectionStatus { get; set; }
    @AuraEnabled
    public Date nextAcceptanceFrom { get; set; }
    @AuraEnabled
    public Date nextAcceptanceTo { get; set; }
    @AuraEnabled
    public List<TagFilterDto> tagFilters { get; set; }
  }

  public class JournalFilterDto {
    @AuraEnabled
    public Date postingDateFrom { get; set; }
    @AuraEnabled
    public Date postingDateTo { get; set; }
    @AuraEnabled
    public String lockState { get; set; }
    @AuraEnabled
    public String eventKey { get; set; }
    @AuraEnabled
    public Id billingAccountId { get; set; }
    @AuraEnabled
    public Id accountId { get; set; }
    @AuraEnabled
    public Id invoiceId { get; set; }
    @AuraEnabled
    public Date closeDateFrom { get; set; }
    @AuraEnabled
    public Date closeDateTo { get; set; }
  }

  public class ListResultDto {
    @AuraEnabled
    public Boolean truncated;
    @AuraEnabled
    public String truncatedMessage;
    @AuraEnabled
    public List<EstimateRowDto> estimates;
    @AuraEnabled
    public List<InvoiceRowDto> invoices;
    @AuraEnabled
    public List<JournalRowDto> journals;
  }

  public class EstimateRowDto {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public String estimateType;
    @AuraEnabled
    public String estimateTypeLabel;
    @AuraEnabled
    public Boolean autoRenew;
    @AuraEnabled
    public Id opportunityId;
    @AuraEnabled
    public String opportunityName;
    @AuraEnabled
    public Date closeDate;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Id serviceId;
    @AuraEnabled
    public String serviceName;
    @AuraEnabled
    public String historyName;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Date validDate;
    @AuraEnabled
    public Boolean sent;
    @AuraEnabled
    public Boolean issued;
  }

  public class InvoiceRowDto {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String invoiceName;
    @AuraEnabled
    public Id historyId;
    @AuraEnabled
    public String historyName;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public String serviceName;
    @AuraEnabled
    public Id opportunityId;
    @AuraEnabled
    public String opportunityName;
    @AuraEnabled
    public Date closeDate;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Id billingAccountId;
    @AuraEnabled
    public String billingAccountName;
    @AuraEnabled
    public Date invoiceDate;
    @AuraEnabled
    public Date paymentScheduledDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal estimateAmount;
    @AuraEnabled
    public Decimal versionInvoiceAmount;
    @AuraEnabled
    public Boolean sent;
    @AuraEnabled
    public Boolean issued;
    /** 仕様: 横断画面.md 操作23。取消済みは取消前の最新発行PDF。 */
    @AuraEnabled
    public Id latestIssuedContentDocumentId;
    @AuraEnabled
    public Boolean overdue;
    @AuraEnabled
    public String collectionStatus;
    @AuraEnabled
    public String invoiceStatus;
    @AuraEnabled
    public String memo;
    @AuraEnabled
    public Boolean cancelled;
    @AuraEnabled
    public Boolean hasMonthly;
    @AuraEnabled
    public Boolean hasLump;
    @AuraEnabled
    public Date nextAcceptance;
    @AuraEnabled
    public List<String> trueTagLabels;
  }

  public class JournalRowDto {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Id invoiceId;
    @AuraEnabled
    public Id historyId;
    @AuraEnabled
    public String invoiceName;
    @AuraEnabled
    public String invoiceToken;
    @AuraEnabled
    public String debitName;
    @AuraEnabled
    public String creditName;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String confirmationText;
    @AuraEnabled
    public String memo;
    @AuraEnabled
    public Date postingDate;
    @AuraEnabled
    public Boolean isLocked;
    @AuraEnabled
    public String transactionStatus;
    @AuraEnabled
    public String eventKey;
    @AuraEnabled
    public String eventName;
    @AuraEnabled
    public Id billingAccountId;
    @AuraEnabled
    public String billingAccountName;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Boolean invoiceCancelled;
    /** 仕様: Core 第11.4.4節、横断画面.md 第2.4節。 */
    @AuraEnabled
    public Map<String, Object> extraFieldValues;
  }

  public class EstimateTileDto {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String historyName;
    @AuraEnabled
    public String estimateType;
    @AuraEnabled
    public String estimateTypeLabel;
    @AuraEnabled
    public Boolean autoRenew;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal taxInclusiveAmount;
    @AuraEnabled
    public Date estimateDate;
    @AuraEnabled
    public Date validDate;
    @AuraEnabled
    public Id sendContactId;
    @AuraEnabled
    public String sendContactName;
    @AuraEnabled
    public Datetime sentAt;
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public String createdByName;
    @AuraEnabled
    public String lastModifiedByName;
    @AuraEnabled
    public Boolean isEstimate;
    @AuraEnabled
    public List<EstimateProductDto> lines;
  }

  public class EstimateProductDto {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String typeValue;
    @AuraEnabled
    public String typeLabel;
    @AuraEnabled
    public String productName;
    @AuraEnabled
    public Decimal unitPrice;
    @AuraEnabled
    public String unit;
    @AuraEnabled
    public Decimal quantity;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public Decimal cycleCount;
    @AuraEnabled
    public String invoiceSetting;
    @AuraEnabled
    public String revenueBasis;
    @AuraEnabled
    public Decimal amount;
  }

  public class IssueContextDto {
    @AuraEnabled
    public List<SelectOptionDto> documentTemplateOptions;
    @AuraEnabled
    public String defaultDocumentTemplateKey;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public Boolean canIssue;
    @AuraEnabled
    public Boolean canSendAfterIssue;
    @AuraEnabled
    public String companyBlockedReason;
    @AuraEnabled
    public Id latestIssuedContentDocumentId;
  }

  public class IssueResultDto {
    @AuraEnabled
    public Id contentDocumentId;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public String previewUrl;
    @AuraEnabled
    public Boolean showSendThisFile;
  }

  public class JournalMemoDraftDto {
    @AuraEnabled
    public Id journalId { get; set; }
    @AuraEnabled
    public Id invoiceId { get; set; }
    @AuraEnabled
    public String memo { get; set; }
    @AuraEnabled
    public Map<String, Object> extraFieldValues { get; set; }
  }

  public class JournalSaveRequestDto {
    @AuraEnabled
    public List<Id> checkedJournalIds { get; set; }
    @AuraEnabled
    public List<JournalMemoDraftDto> memos { get; set; }
    @AuraEnabled
    public String unlockReason { get; set; }
    @AuraEnabled
    public String lockState { get; set; }
    @AuraEnabled
    public Map<String, String> invoiceTokens { get; set; }
  }

  public class JournalSaveResultDto {
    @AuraEnabled
    public Boolean refreshed;
    @AuraEnabled
    public Integer lockCount;
  }

  /** 仕様: Core 第9章・第12.4節・第4.3.11節、横断画面.md 第5節・第1節 */
  @AuraEnabled
  public static BootstrapDto getBootstrap() {
    try {
      ContractPermissionUtil.assertCrossWork();
      BootstrapDto dto = new BootstrapDto();
      dto.accountingEnabled = ContractCrossQueryService.isAccountingEnabled();
      Date today = ContractCrossQueryService.organizationToday();
      ContractCrossQueryService.DateRange estimateDates = ContractCrossQueryService.defaultEstimateCloseDates(
        today
      );
      dto.estimateCloseFrom = estimateDates.dateFrom;
      dto.estimateCloseTo = estimateDates.dateTo;
      ContractCrossQueryService.DateRange journalDates = ContractCrossQueryService.defaultJournalPostingDates(
        today
      );
      dto.journalPostingFrom = journalDates.dateFrom;
      dto.journalPostingTo = journalDates.dateTo;
      String sendMode = ContractDocumentSettingService.requireSendMode('Estimate');
      dto.estimateSendMode = sendMode;
      dto.canIssueEstimate =
        ContractPermissionUtil.has(ContractPermissionUtil.ISSUE_ESTIMATE) &&
        sendMode != ContractDocumentSettingService.MODE_UNUSED;
      dto.canSendEstimate =
        ContractPermissionUtil.has(ContractPermissionUtil.SEND_ESTIMATE) &&
        sendMode == ContractDocumentSettingService.MODE_PDF_AND_EMAIL;
      dto.canOrder = ContractPermissionUtil.has(ContractPermissionUtil.ORDER);
      dto.canShowEstimateMenu =
        ContractPermissionUtil.has(ContractPermissionUtil.ISSUE_ESTIMATE) ||
        ContractPermissionUtil.has(ContractPermissionUtil.SEND_ESTIMATE) ||
        ContractPermissionUtil.has(ContractPermissionUtil.ORDER);
      dto.canShowInvoiceMenu = ContractPermissionUtil.canViewInvoiceBoard();
      dto.invoiceSendMode = ContractDocumentSettingService.requireSendMode(
        'Invoice'
      );
      dto.tagRules = ContractCrossQueryService.loadEnabledTagRules();
      dto.eventOptions = new List<SelectOptionDto>();
      for (JournalPatternFixedCatalog.Definition definition : JournalPatternFixedCatalog.values()) {
        SelectOptionDto option = new SelectOptionDto();
        option.label = JournalPatternFixedCatalog.listDisplayName(definition.key);
        option.value = definition.key;
        dto.eventOptions.add(option);
      }
      try {
        dto.journalLockExemptFieldApiNames = new List<String>(
          JournalLockService.resolveLockExemptFieldNames()
        );
      } catch (Exception ignore) {
        dto.journalLockExemptFieldApiNames = new List<String>();
      }
      return dto;
    } catch (Exception ex) {
      throw handled(ex);
    }
  }

  /** 仕様: 横断画面.md 第5節 見積一覧 */
  @AuraEnabled
  public static ListResultDto queryEstimates(EstimateFilterDto filter) {
    try {
      ContractPermissionUtil.assertCrossWork();
      return ContractCrossQueryService.queryEstimates(filter);
    } catch (Exception ex) {
      throw handled(ex);
    }
  }

  /** 仕様: 横断画面.md 第5節 請求一覧 */
  @AuraEnabled
  public static ListResultDto queryInvoices(InvoiceFilterDto filter) {
    try {
      ContractPermissionUtil.assertCrossWork();
      return ContractCrossQueryService.queryInvoices(filter);
    } catch (Exception ex) {
      throw handled(ex);
    }
  }

  /** 仕様: 横断画面.md 第5節 仕訳一覧 */
  @AuraEnabled
  public static ListResultDto queryJournals(JournalFilterDto filter) {
    try {
      ContractPermissionUtil.assertCrossWork();
      return ContractCrossQueryService.queryJournals(filter);
    } catch (Exception ex) {
      throw handled(ex);
    }
  }

  /** 仕様: 横断画面.md 見積書タイル、共通基盤 第10.4節。開くとき 18。 */
  @AuraEnabled
  public static EstimateTileDto getEstimateTile(Id historyId) {
    try {
      ContractPermissionUtil.assertCrossWork();
      return ContractCrossQueryService.getEstimateTile(historyId);
    } catch (Exception ex) {
      throw handled(ex);
    }
  }

  /** 仕様: Core 第4.8節・第11.3.1節、横断画面.md 操作4 */
  @AuraEnabled
  public static IssueContextDto getEstimateIssueContext(Id historyId) {
    try {
      ContractPermissionUtil.assertCrossWork();
      ContractPermissionUtil.assertIssueEstimate();
      if (historyId == null) {
        throw new CrossException('契約履歴が指定されていません。');
      }
      IssueContextDto dto = new IssueContextDto();
      dto.documentTemplateOptions = new List<SelectOptionDto>();
      ContractDocumentSetting__c setting = ContractDocumentSettingService.requireOrgSetting();
      for (
        ContractDocumentTemplateService.TemplateDefinition definition : ContractDocumentTemplateService.getActiveTemplates(
          ContractDocumentTemplateService.TYPE_ESTIMATE
        )
      ) {
        SelectOptionDto option = new SelectOptionDto();
        option.label = definition.label;
        option.value = definition.templateKey;
        dto.documentTemplateOptions.add(option);
      }
      // 仕様: Core 第11.3.2節。有効な既定がちょうど1つなら初期選択。発行の空キー埋めには使わない。
      String initialKey = ContractDocumentTemplateService.initialSelectionKey(
        ContractDocumentTemplateService.TYPE_ESTIMATE
      );
      dto.defaultDocumentTemplateKey = initialKey;
      List<ContractHistory__c> histories = [
        SELECT
          Id,
          Name,
          EstimateTitleName__c,
          EstimateIssueDate__c,
          Opportunity__r.Name
        FROM ContractHistory__c
        WHERE Id = :historyId
        WITH USER_MODE
        LIMIT 1
      ];
      if (histories.isEmpty()) {
        throw new CrossException('契約履歴が見つかりません。');
      }
      if (String.isNotBlank(initialKey)) {
        ContractDocumentTemplateService.TemplateDefinition selected =
          ContractDocumentTemplateService.resolveTemplate(
            ContractDocumentTemplateService.TYPE_ESTIMATE,
            initialKey
          );
        // 仕様: Core 第11.3.2節。{Title}は見積件名→商談名→契約履歴名。
        dto.fileName = EstimateDocumentService.buildFileName(
          histories[0],
          histories[0].EstimateIssueDate__c,
          selected
        );
      }
      String sendMode = ContractDocumentSettingService.requireSendMode('Estimate');
      dto.canIssue =
        ContractPermissionUtil.has(ContractPermissionUtil.ISSUE_ESTIMATE) &&
        sendMode != ContractDocumentSettingService.MODE_UNUSED;
      dto.canSendAfterIssue =
        sendMode == ContractDocumentSettingService.MODE_PDF_AND_EMAIL &&
        ContractPermissionUtil.has(ContractPermissionUtil.SEND_ESTIMATE);
      try {
        ContractDocumentSettingService.assertRequiredCompanyFields(setting);
      } catch (ContractDocumentSettingService.SettingException ex) {
        dto.companyBlockedReason = ContractDocumentSettingService.withDocumentSendHeading(
          ex.getMessage()
        );
      }
      dto.latestIssuedContentDocumentId = EstimateDocumentService.latestIssuedContentDocumentId(
        historyId
      );
      return dto;
    } catch (Exception ex) {
      throw handled(ex);
    }
  }

  /** 仕様: Core 第4.8節、横断画面.md 操作4、共通基盤 第1.4節・第10.4節。開くとき 18。発行は 04。 */
  @AuraEnabled
  public static String previewEstimateIssueFileName(
    Id historyId,
    String templateKey
  ) {
    try {
      ContractPermissionUtil.assertCrossWork();
      ContractPermissionUtil.assertIssueEstimate();
      if (historyId == null) {
        throw new CrossException('契約履歴が指定されていません。');
      }
      ContractDocumentTemplateService.TemplateDefinition template = ContractDocumentTemplateService.resolveTemplate(
        ContractDocumentTemplateService.TYPE_ESTIMATE,
        templateKey
      );
      // 仕様: Core 第11.3.2節。{Title}は見積件名→商談名→契約履歴名。
      List<ContractHistory__c> histories = [
        SELECT
          Id,
          Name,
          EstimateTitleName__c,
          EstimateIssueDate__c,
          Opportunity__r.Name
        FROM ContractHistory__c
        WHERE Id = :historyId
        WITH USER_MODE
        LIMIT 1
      ];
      if (histories.isEmpty()) {
        throw new CrossException('契約履歴が見つかりません。');
      }
      return EstimateDocumentService.buildFileName(
        histories[0],
        histories[0].EstimateIssueDate__c,
        template
      );
    } catch (Exception ex) {
      throw handled(ex);
    }
  }

  /** 仕様: Core 第4.8節、横断画面.md 操作4 */
  @AuraEnabled
  public static IssueResultDto issueEstimate(Id historyId, String templateKey) {
    try {
      ContractPermissionUtil.assertHas(
        ContractPermissionUtil.ISSUE_ESTIMATE,
        '見積書発行を実行する権限がありません。'
      );
      EstimateDocumentService.IssueResult issued = EstimateDocumentService.issueEstimateDocument(
        historyId,
        templateKey
      );
      IssueResultDto dto = new IssueResultDto();
      dto.contentDocumentId = issued.contentDocumentId;
      dto.fileName = issued.fileName;
      dto.previewUrl = '';
      dto.showSendThisFile =
        ContractDocumentSettingService.requireSendMode('Estimate') ==
        ContractDocumentSettingService.MODE_PDF_AND_EMAIL &&
        ContractPermissionUtil.has(ContractPermissionUtil.SEND_ESTIMATE);
      return dto;
    } catch (Exception ex) {
      throw handled(ex);
    }
  }

  /**
   * 仕様: 横断画面.md 第2.3節・第2.4節、Accounting 第9.5節、Core 第11.4.4節・第12.4節、共通基盤.md 第12章
   * Lock／Unlock拒否時はメモも追加項目も書かない。メモ／追加項目だけならLock権限を要しない。
   * 横断のLock／Unlock込み保存はLock／Unlock種別。メモだけならJournalMemo。
   * グルーピング済み仕訳は lockForInvoice で取り直さない。
   * グルーピング行の更新日時で Current 収集から同じ仕訳を除外する。
   * Lock後のメモ／追加項目は setLocked が読んだ仕訳と請求状態を取り直さない。
   */
  @AuraEnabled
  public static JournalSaveResultDto saveJournals(JournalSaveRequestDto request) {
    try {
      ContractPermissionUtil.assertCrossWork();
      if (request == null) {
        throw new CrossException('保存する内容がありません。');
      }
      List<Id> checked = request.checkedJournalIds == null
        ? new List<Id>()
        : request.checkedJournalIds;
      List<JournalMemoDraftDto> memos = request.memos == null
        ? new List<JournalMemoDraftDto>()
        : request.memos;
      if (checked.isEmpty() && memos.isEmpty()) {
        throw new CrossException(
          'チェックが無くメモの変更も追加項目の変更も無ければ実行できません。'
        );
      }
      JournalSaveResultDto result = new JournalSaveResultDto();
      result.lockCount = 0;
      result.refreshed = false;
      Map<Id, GlJournal__c> journalsAfterLock = new Map<Id, GlJournal__c>();
      if (!checked.isEmpty()) {
        if (
          request.lockState != ContractCrossQueryService.LOCK_UNLOCKED &&
          request.lockState != ContractCrossQueryService.LOCK_LOCKED
        ) {
          throw new CrossException('Lockは未Lock／Lock済みです。');
        }
        Boolean unlocking =
          request.lockState == ContractCrossQueryService.LOCK_LOCKED;
        if (unlocking && String.isBlank(request.unlockReason)) {
          throw new CrossException('Unlockには理由が必要です。');
        }
        Map<Id, List<GlJournal__c>> byInvoice = new Map<Id, List<GlJournal__c>>();
        // 仕様: Core 第12.4節・第7.9.7節。グルーピング済み仕訳は Current で取り直さない。
        for (GlJournal__c journal : [
          SELECT
            Id,
            Invoice__c,
            Invoice__r.InvoiceTransactionStatus__c,
            IsLocked__c,
            BusinessOperationKey__c,
            UnlockReason__c,
            TransactionStatus__c,
            LastModifiedDate
          FROM GlJournal__c
          WHERE Id IN :checked
          WITH SYSTEM_MODE
        ]) {
          if (journal.Invoice__c == null) {
            continue;
          }
          if (!byInvoice.containsKey(journal.Invoice__c)) {
            byInvoice.put(journal.Invoice__c, new List<GlJournal__c>());
          }
          byInvoice.get(journal.Invoice__c).add(journal);
        }
        String operationKey = InvoicePreviewOpsController.issueInvoiceOperationKey();
        List<GlJournal__c> lockedRows = new List<GlJournal__c>();
        Boolean previousSuppress = JournalLockService.suppressLockLog;
        JournalLockService.suppressLockLog = true;
        try {
          for (Id invoiceId : byInvoice.keySet()) {
            String token = request.invoiceTokens == null
              ? null
              : request.invoiceTokens.get(String.valueOf(invoiceId));
            List<GlJournal__c> grouped = byInvoice.get(invoiceId);
            List<Id> journalIds = new List<Id>();
            for (GlJournal__c groupedJournal : grouped) {
              journalIds.add(groupedJournal.Id);
            }
            if (unlocking) {
              InvoicePreviewOpsController.unlockJournalsForInvoice(
                invoiceId,
                journalIds,
                request.unlockReason,
                token,
                operationKey,
                grouped
              );
            } else {
              InvoicePreviewOpsController.lockJournalsForInvoice(
                invoiceId,
                journalIds,
                token,
                operationKey,
                grouped
              );
            }
            result.lockCount += journalIds.size();
            for (GlJournal__c groupedJournal : grouped) {
              journalsAfterLock.put(groupedJournal.Id, groupedJournal);
              lockedRows.add(new GlJournal__c(Id = groupedJournal.Id));
            }
          }
        } finally {
          JournalLockService.suppressLockLog = previousSuppress;
        }
        JournalLockService.writeLockLog(
          unlocking != true,
          operationKey,
          lockedRows,
          unlocking ? request.unlockReason : null
        );
        result.refreshed = true;
      }
      Boolean previousMemo = ContractOperationLogService.suppressJournalMemoWrites;
      if (!checked.isEmpty()) {
        ContractOperationLogService.suppressJournalMemoWrites = true;
      }
      try {
        for (JournalMemoDraftDto draft : memos) {
          if (draft == null || draft.journalId == null || draft.invoiceId == null) {
            continue;
          }
          InvoicePreviewOpsController.updateJournalMemo(
            draft.journalId,
            draft.memo,
            draft.invoiceId,
            draft.extraFieldValues,
            journalsAfterLock.get(draft.journalId)
          );
        }
      } finally {
        ContractOperationLogService.suppressJournalMemoWrites = previousMemo;
      }
      return result;
    } catch (Exception ex) {
      throw handled(ex);
    }
  }

  private static AuraHandledException handled(Exception ex) {
    String message = ex.getMessage();
    AuraHandledException wrapped = new AuraHandledException(message);
    wrapped.setMessage(message);
    return wrapped;
  }
}
