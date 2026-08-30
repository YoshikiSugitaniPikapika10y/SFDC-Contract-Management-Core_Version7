/**
 * 見積送付ボードの参照、PDF発行、メール送付を提供する。
 * 共有/FLSに依存しない業務処理のため、入口でカスタム権限と機能設定を必ず検査する。
 */
public without sharing class EstimateSendBoardController {
  public static final Integer LIST_LIMIT = 500;
  private static final String STATUS_ESTIMATE = 'Estimate';
  /** 仕様: Core 第0.1節、第4.8節 */
  @TestVisible
  private static final String ESTIMATE_STATUS_REQUIRED_MESSAGE =
    'ステータスが見積の契約履歴のみ操作できます。';
  public static final String FROM_SELF = 'Self';
  public static final String FROM_ORG = 'Org';
  public static final String MISSING_TO_MESSAGE = 'Toメールアドレスを設定してください。';
  public static final String MISSING_OPERATOR_EMAIL_MESSAGE =
    '操作者のメールが空のため送付できません。';
  public static final String MISSING_ATTACHMENT_MESSAGE =
    '添付ファイルを選択してください。';
  public static final String MISSING_ATTACHMENT_NAME_MESSAGE =
    '添付ファイル名を設定してください。';
  public static final String ATTACHMENT_NEW = EstimateDocumentService.ATTACHMENT_NEW;

  @TestVisible
  private static Boolean skipEmailSend = false;

  public class SelectOptionDto {
    @AuraEnabled public String label;
    @AuraEnabled public String value;
  }

  public class BoardContextDto {
    @AuraEnabled public Boolean canSend;
    @AuraEnabled public Boolean featureEnabled;
    @AuraEnabled public List<SelectOptionDto> documentTemplateOptions;
    @AuraEnabled public List<SelectOptionDto> emailTemplateOptions;
    @AuraEnabled public String defaultDocumentTemplateKey;
    @AuraEnabled public String defaultEmailTemplateApiName;
    @AuraEnabled public Integer listLimit;
    /** 仕様: Core 第4.8節。見積Fromの初期値は自分。 */
    @AuraEnabled public String defaultFromChoice;
    @AuraEnabled public String operatorEmail;
    @AuraEnabled public String orgFromLabel;
  }

  public class EstimateRowDto {
    @AuraEnabled public Id historyId;
    @AuraEnabled public String historyName;
    @AuraEnabled public String title;
    @AuraEnabled public String historyType;
    @AuraEnabled public Decimal version;
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public Id serviceId;
    @AuraEnabled public String serviceName;
    @AuraEnabled public Id opportunityId;
    @AuraEnabled public String opportunityName;
    @AuraEnabled public Date estimateDate;
    @AuraEnabled public Date validDate;
    @AuraEnabled public Decimal taxPercent;
    @AuraEnabled public Decimal amountIncludingTax;
    @AuraEnabled public Datetime estimateSentAt;
    @AuraEnabled public Boolean autoCreated;
    @AuraEnabled public String billingAddressee;
    @AuraEnabled public String toAddresses;
    @AuraEnabled public String ccAddresses;
    @AuraEnabled public String bccAddresses;
    @AuraEnabled public Boolean sendable;
    @AuraEnabled public String sendableReason;
    @AuraEnabled public String lastModifiedToken;
  }

  public class SendDraftDto {
    @AuraEnabled public String toAddresses;
    @AuraEnabled public String ccAddresses;
    @AuraEnabled public String bccAddresses;
    @AuraEnabled public String subject;
    @AuraEnabled public String body;
    @AuraEnabled public String fileName;
    /** 仕様: Core 第4.8節。Self または Org。空なら自分。 */
    @AuraEnabled public String fromChoice;
    /** 仕様: Core 第7.10節。NEW または ContentDocument Id。 */
    @AuraEnabled public String attachmentId;
  }

  public class SendPreviewDto {
    @AuraEnabled public String fromLabel;
    @AuraEnabled public String orgWideEmailAddress;
    @AuraEnabled public String toAddresses;
    @AuraEnabled public String ccAddresses;
    @AuraEnabled public String bccAddresses;
    @AuraEnabled public String subject;
    @AuraEnabled public String body;
    @AuraEnabled public String fileName;
    @AuraEnabled public String documentTemplateKey;
    @AuraEnabled public String emailTemplateApiName;
    @AuraEnabled public String fromChoice;
    @AuraEnabled public String operatorEmail;
    @AuraEnabled public String attachmentId;
    @AuraEnabled public List<EstimateDocumentService.FileOptionDto> attachmentOptions;
    @AuraEnabled public String newIssueFileName;
  }

  public class ActionResultDto {
    @AuraEnabled public Id contentVersionId;
    @AuraEnabled public Id contentDocumentId;
    @AuraEnabled public String fileName;
    @AuraEnabled public String documentTemplateKey;
    @AuraEnabled public Datetime sentAt;
  }

  /** 仕様: Core 第11.3節、第11.3.2節、共通基盤 第1.4節・第3.3節。送る入口は 05。 */
  @AuraEnabled(cacheable=true)
  public static BoardContextDto getBoardContext() {
    try {
      ContractPermissionUtil.assertSendEstimates();
      ContractDocumentSetting__c setting = loadOrganizationSetting();
      BoardContextDto result = new BoardContextDto();
      result.canSend = ContractPermissionUtil.has(
        ContractPermissionUtil.SEND_ESTIMATE
      );
      result.featureEnabled =
        ContractDocumentSettingService.requireSendMode('Estimate') !=
        ContractDocumentSettingService.MODE_UNUSED;
      result.documentTemplateOptions = new List<SelectOptionDto>();
      for (
        ContractDocumentTemplateService.TemplateDefinition definition :
        ContractDocumentTemplateService.getActiveTemplates(
          ContractDocumentTemplateService.TYPE_ESTIMATE
        )
      ) {
        result.documentTemplateOptions.add(
          option(definition.label, definition.templateKey)
        );
      }
      result.emailTemplateOptions = new List<SelectOptionDto>();
      for (
        ContractEmailTemplateService.EmailTemplateDefinition definition :
        ContractEmailTemplateService.getActiveTemplates(
          ContractEmailTemplateService.TYPE_ESTIMATE
        )
      ) {
        result.emailTemplateOptions.add(
          option(definition.label, definition.apiName)
        );
      }
      result.defaultDocumentTemplateKey =
        setting.EstimateDefaultDocumentTemplateKey__c;
      result.defaultEmailTemplateApiName =
        setting.EstimateDefaultEmailTemplateApiName__c;
      result.listLimit = LIST_LIMIT;
      result.defaultFromChoice = FROM_SELF;
      result.operatorEmail = UserInfo.getUserEmail();
      result.orgFromLabel = formatEstimateOrgFromLabel(
        setting.EstimateOrgWideEmailAddress__c
      );
      return result;
    } catch (Exception ex) {
      throw handled('見積送付画面の設定を取得できませんでした。', ex);
    }
  }

  // レコードアクションも再利用キャッシュではなく、表示時点の最新を返す。
  /** 仕様: 共通基盤 第1.4節・第3.3節。送る入口は 05。 */
  @AuraEnabled
  public static EstimateRowDto getRecordActionEstimate(Id historyId) {
    try {
      ContractPermissionUtil.assertSendEstimates();
      ContractHistory__c history = loadActionHistory(historyId);
      if (history.historystatus__c != STATUS_ESTIMATE) {
        throw handledMessage(ESTIMATE_STATUS_REQUIRED_MESSAGE);
      }
      return toRow(history, true, isEmailEnabled());
    } catch (AuraHandledException ex) {
      throw ex;
    } catch (Exception ex) {
      throw handled('見積の送付情報を取得できませんでした。', ex);
    }
  }

  /** 仕様: Core 第4.3.1節、第4.8節、第4.3.12節。見積送付権限をサーバで強制する。 */
  @AuraEnabled
  public static ActionResultDto sendEstimateFromRecordPage(
    Id historyId,
    String documentTemplateKey,
    String emailTemplateApiName,
    String expectedToken,
    SendDraftDto draft
  ) {
    return sendEstimateInternal(
      historyId,
      documentTemplateKey,
      emailTemplateApiName,
      expectedToken,
      true,
      draft
    );
  }

  public static ActionResultDto sendEstimateFromRecordPage(
    Id historyId,
    String documentTemplateKey,
    String emailTemplateApiName,
    String expectedToken
  ) {
    return sendEstimateFromRecordPage(
      historyId,
      documentTemplateKey,
      emailTemplateApiName,
      expectedToken,
      null
    );
  }

  /** 仕様: Core 第7.10節、第4.8節 */
  public static SendPreviewDto previewEstimateFromRecordPage(
    Id historyId,
    String documentTemplateKey,
    String emailTemplateApiName
  ) {
    return previewEstimateFromRecordPage(
      historyId,
      documentTemplateKey,
      emailTemplateApiName,
      FROM_SELF
    );
  }

  /** 仕様: Core 第7.10節、第4.8節。From 初期値は自分。組織を選んだときだけ OWE を引く。 */
  public static SendPreviewDto previewEstimateFromRecordPage(
    Id historyId,
    String documentTemplateKey,
    String emailTemplateApiName,
    String fromChoice
  ) {
    return previewEstimateFromRecordPage(
      historyId,
      documentTemplateKey,
      emailTemplateApiName,
      fromChoice,
      null
    );
  }

  /** 仕様: Core 第7.10節。preferredAttachmentId は発行成功の「このファイルを送る」。共通基盤 第1.4節・第3.3節。入口は 05。 */
  @AuraEnabled
  public static SendPreviewDto previewEstimateFromRecordPage(
    Id historyId,
    String documentTemplateKey,
    String emailTemplateApiName,
    String fromChoice,
    String preferredAttachmentId
  ) {
    try {
      ContractPermissionUtil.assertSendEstimates();
      ContractHistory__c history = loadActionHistory(historyId);
      if (history.historystatus__c != STATUS_ESTIMATE) {
        throw handledMessage(ESTIMATE_STATUS_REQUIRED_MESSAGE);
      }
      assertDocumentModeAllowed(true);
      ContractDocumentSetting__c setting = loadOrganizationSetting();
      String resolvedFromChoice = normalizeFromChoice(fromChoice);
      ContractEmailTemplateService.MergeResult merged;
      try {
        merged = ContractEmailTemplateService.renderForSend(
          ContractEmailTemplateService.TYPE_ESTIMATE,
          emailTemplateApiName,
          setting.EstimateDefaultEmailTemplateApiName__c,
          history.Id,
          resolveEstimateWhoId(history)
        );
      } catch (ContractEmailTemplateService.EmailTemplateException ex) {
        throw handledMessage(ex.getMessage());
      }
      EstimateFromResolved fromResolved = resolveEstimateFrom(
        resolvedFromChoice,
        setting,
        false
      );
      ContractDocumentTemplateService.TemplateDefinition template =
        ContractDocumentTemplateService.resolveTemplate(
          ContractDocumentTemplateService.TYPE_ESTIMATE,
          resolveDocumentTemplateKey(documentTemplateKey, setting)
        );
      SendPreviewDto preview = new SendPreviewDto();
      preview.fromChoice = resolvedFromChoice;
      preview.operatorEmail = UserInfo.getUserEmail();
      preview.orgWideEmailAddress = fromResolved.address;
      preview.fromLabel = fromResolved.fromLabel;
      preview.toAddresses = estimateSendContactEmail(history);
      preview.ccAddresses = null;
      preview.bccAddresses = null;
      preview.subject = merged.subject;
      preview.body = merged.body;
      preview.documentTemplateKey = template.templateKey;
      preview.emailTemplateApiName = merged.apiName;
      preview.attachmentOptions = EstimateDocumentService.listLinkedFiles(
        history.Id
      );
      preview.attachmentId = EstimateDocumentService.initialAttachmentId(
        preview.attachmentOptions,
        preferredAttachmentId
      );
      preview.fileName = EstimateDocumentService.fileNameForAttachment(
        preview.attachmentOptions,
        preview.attachmentId,
        EstimateDocumentService.buildFileName(
          history,
          history.EstimateIssueDate__c,
          template
        )
      );
      preview.newIssueFileName = EstimateDocumentService.buildFileName(
        history,
        history.EstimateIssueDate__c,
        template
      );
      return preview;
    } catch (AuraHandledException ex) {
      throw ex;
    } catch (Exception ex) {
      throw handled('見積送付プレビューを取得できませんでした。', ex);
    }
  }

  private static ActionResultDto sendEstimateInternal(
    Id historyId,
    String documentTemplateKey,
    String emailTemplateApiName,
    String expectedToken,
    Boolean enforcePermission,
    SendDraftDto draft
  ) {
    try {
      ContractHistory__c history = loadActionHistory(historyId, true);
      assertActionAllowed(history, enforcePermission, true);
      // 仕様: Core 第4.8節、第7.10節。見積の To は見積送付先1人。この画面では直さない。
      String toRaw = estimateSendContactEmail(history);
      String ccRaw = draft != null && draft.ccAddresses != null
        ? draft.ccAddresses
        : null;
      String bccRaw = draft != null && draft.bccAddresses != null
        ? draft.bccAddresses
        : null;
      List<String> toAddresses = parseSingleToAddress(toRaw);
      if (toAddresses.isEmpty()) {
        throw handledMessage(MISSING_TO_MESSAGE);
      }
      List<String> ccAddresses = parseAddresses(ccRaw, 'Cc');
      List<String> bccAddresses = parseAddresses(bccRaw, 'Bcc');

      ContractDocumentSetting__c setting = loadOrganizationSetting();
      String fromChoice = draft == null
        ? FROM_SELF
        : normalizeFromChoice(draft.fromChoice);
      EstimateFromResolved fromResolved;
      ContractEmailTemplateService.EmailTemplateDefinition emailTemplate;
      try {
        emailTemplate = ContractEmailTemplateService.resolveForOperation(
          ContractEmailTemplateService.TYPE_ESTIMATE,
          emailTemplateApiName,
          setting.EstimateDefaultEmailTemplateApiName__c
        );
        fromResolved = resolveEstimateFrom(fromChoice, setting, true);
      } catch (ContractEmailTemplateService.EmailTemplateException ex) {
        throw handledMessage(ex.getMessage());
      }
      String resolvedTemplateKey = resolveDocumentTemplateKey(
        documentTemplateKey,
        setting
      );
      String attachmentFileName = draft != null &&
        String.isNotBlank(draft.fileName)
        ? draft.fileName.trim()
        : null;
      if (String.isBlank(attachmentFileName)) {
        throw handledMessage(MISSING_ATTACHMENT_NAME_MESSAGE);
      }
      String attachmentId = draft == null ? null : draft.attachmentId;
      ContentVersion versionRecord = resolveSendContent(
        history.Id,
        attachmentId,
        resolvedTemplateKey,
        attachmentFileName
      );

      Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
      message.setToAddresses(toAddresses);
      if (!ccAddresses.isEmpty()) {
        message.setCcAddresses(ccAddresses);
      }
      if (!bccAddresses.isEmpty()) {
        message.setBccAddresses(bccAddresses);
      }
      if (fromResolved.orgWideId != null) {
        message.setOrgWideEmailAddressId(fromResolved.orgWideId);
      }
      if (draft != null) {
        message.setSubject(draft.subject == null ? '' : draft.subject);
        message.setPlainTextBody(draft.body == null ? '' : draft.body);
      } else {
        message.setTemplateId(emailTemplate.emailTemplateId);
        message.setTargetObjectId(resolveEstimateWhoId(history));
        message.setTreatTargetObjectAsRecipient(false);
        message.setWhatId(history.Id);
      }
      Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
      attachment.setFileName(attachmentFileName);
      attachment.setBody(versionRecord.VersionData);
      attachment.setContentType('application/pdf');
      message.setFileAttachments(
        new List<Messaging.EmailFileAttachment>{ attachment }
      );
      if (!skipEmailSend) {
        Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(
          new List<Messaging.SingleEmailMessage>{ message },
          false
        );
        if (sendResults.isEmpty() || !sendResults[0].isSuccess()) {
          String detail = 'メール送信に失敗しました。';
          if (
            !sendResults.isEmpty() &&
            sendResults[0].getErrors() != null &&
            !sendResults[0].getErrors().isEmpty()
          ) {
            detail += ' ' + sendResults[0].getErrors()[0].getMessage();
          }
          throw handledMessage(detail);
        }
      }

      Datetime sentAt = System.now();
      SystemContextAccess.updateRecords(
        new List<SObject>{
          new ContractHistory__c(
            Id = history.Id,
            EstimateSentAt__c = sentAt
          )
        }
      );

      ActionResultDto result = new ActionResultDto();
      result.contentVersionId = versionRecord.Id;
      result.contentDocumentId = versionRecord.ContentDocumentId;
      result.fileName = attachmentFileName;
      result.documentTemplateKey = resolvedTemplateKey;
      result.sentAt = sentAt;
      ContractOperationLogService.write(
        'EstimateSend',
        null,
        'ContractHistory__c',
        String.valueOf(history.Id)
      );
      return result;
    } catch (AuraHandledException ex) {
      throw ex;
    } catch (Exception ex) {
      throw handled('見積書を送付できませんでした。', ex);
    }
  }

  /** 仕様: Core 第7.10節。未選択では送れない。新しく発行するは送るときに作る。 */
  private static ContentVersion resolveSendContent(
    Id historyId,
    String attachmentId,
    String documentTemplateKey,
    String attachmentFileName
  ) {
    if (String.isBlank(attachmentId)) {
      throw handledMessage(MISSING_ATTACHMENT_MESSAGE);
    }
    if (attachmentId == ATTACHMENT_NEW) {
      Boolean previous = ContractOperationLogService.suppressIssueLog;
      ContractOperationLogService.suppressIssueLog = true;
      EstimateDocumentService.IssueResult issued;
      try {
        issued = EstimateDocumentService.issueEstimateDocument(
          historyId,
          documentTemplateKey,
          attachmentFileName
        );
      } finally {
        ContractOperationLogService.suppressIssueLog = previous;
      }
      return [
        SELECT Id, ContentDocumentId, VersionData
        FROM ContentVersion
        WHERE Id = :issued.contentVersionId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
    }
    Id documentId;
    try {
      documentId = Id.valueOf(attachmentId);
    } catch (Exception ex) {
      throw handledMessage(MISSING_ATTACHMENT_MESSAGE);
    }
    Id latestIssuedId = EstimateDocumentService.latestIssuedContentDocumentId(
      historyId
    );
    if (latestIssuedId == null || latestIssuedId != documentId) {
      throw handledMessage(MISSING_ATTACHMENT_MESSAGE);
    }
    List<ContentVersion> versions = [
      SELECT Id, ContentDocumentId, VersionData
      FROM ContentVersion
      WHERE ContentDocumentId = :documentId AND IsLatest = true
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (versions.isEmpty()) {
      throw handledMessage(MISSING_ATTACHMENT_MESSAGE);
    }
    return versions[0];
  }

  private class EstimateFromResolved {
    Id orgWideId;
    String address;
    String fromLabel;
  }

  /** 仕様: Core 第4.8節、第11.3.2節。初期値は自分。組織を選んだときだけ OWE を引く。 */
  private static EstimateFromResolved resolveEstimateFrom(
    String fromChoice,
    ContractDocumentSetting__c setting,
    Boolean requireForSend
  ) {
    EstimateFromResolved resolved = new EstimateFromResolved();
    if (fromChoice == FROM_ORG) {
      ContractEmailTemplateService.OrgWideResolved sender = ContractEmailTemplateService.resolveOrgWide(
        setting == null ? null : setting.EstimateOrgWideEmailAddress__c
      );
      resolved.orgWideId = sender.orgWideId;
      resolved.address = sender.address;
      resolved.fromLabel = ContractEmailTemplateService.formatOrgWideFrom(
        sender
      );
      return resolved;
    }
    String operatorEmail = UserInfo.getUserEmail();
    if (requireForSend == true && String.isBlank(operatorEmail)) {
      throw handledMessage(MISSING_OPERATOR_EMAIL_MESSAGE);
    }
    resolved.address = operatorEmail;
    resolved.fromLabel = operatorEmail;
    return resolved;
  }

  private static String normalizeFromChoice(String fromChoice) {
    return fromChoice == FROM_ORG ? FROM_ORG : FROM_SELF;
  }

  /** 仕様: Core 第7.10節。見積送付先があればその Contact、無ければ操作者 User。 */
  private static Id resolveEstimateWhoId(ContractHistory__c history) {
    if (history != null && history.EstimateSendContact__c != null) {
      return history.EstimateSendContact__c;
    }
    return UserInfo.getUserId();
  }

  /** 仕様: Core 第4.8節。初期 To は見積送付先のメール。空または責任者空なら空。 */
  private static String estimateSendContactEmail(ContractHistory__c history) {
    if (history == null || history.EstimateSendContact__r == null) {
      return null;
    }
    return history.EstimateSendContact__r.Email;
  }

  /** 仕様: Core 第4.8節、第7.10節。見積の To は1人。カンマ区切りの複数にはしない。 */
  private static List<String> parseSingleToAddress(String raw) {
    List<String> addresses = new List<String>();
    if (String.isBlank(raw)) {
      return addresses;
    }
    String address = raw.trim();
    if (address.length() > 255) {
      throw handledMessage('Toは255文字以内で指定してください。');
    }
    if (
      !Pattern.matches(
        '^[A-Za-z0-9.!#$%&\'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+$',
        address
      )
    ) {
      throw handledMessage('Toに不正なメールアドレスがあります: ' + address);
    }
    addresses.add(address);
    return addresses;
  }

  private static String formatEstimateOrgFromLabel(String savedAddress) {
    if (String.isBlank(savedAddress)) {
      return '';
    }
    try {
      return ContractEmailTemplateService.formatOrgWideFrom(
        ContractEmailTemplateService.resolveOrgWide(savedAddress)
      );
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      return savedAddress.trim();
    }
  }

  /** 仕様: Core 第7.10節。カンマ区切り。255文字以内。前後空白除去。空の区切りは無視。 */
  @TestVisible
  private static List<String> parseAddresses(String raw, String label) {
    List<String> addresses = new List<String>();
    if (String.isBlank(raw)) {
      return addresses;
    }
    if (raw.length() > 255) {
      throw handledMessage(label + 'は255文字以内で指定してください。');
    }
    Set<String> seen = new Set<String>();
    for (String candidate : raw.split(',')) {
      String address = candidate == null ? null : candidate.trim();
      if (String.isBlank(address)) {
        continue;
      }
      if (
        !Pattern.matches(
          '^[A-Za-z0-9.!#$%&\'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+$',
          address
        )
      ) {
        throw handledMessage(label + 'に不正なメールアドレスがあります: ' + address);
      }
      String key = address.toLowerCase();
      if (!seen.contains(key)) {
        seen.add(key);
        addresses.add(address);
      }
    }
    return addresses;
  }

  private static EstimateRowDto toRow(
    ContractHistory__c history,
    Boolean canSend,
    Boolean featureEnabled
  ) {
    EstimateRowDto row = new EstimateRowDto();
    row.historyId = history.Id;
    row.historyName = history.Name;
    row.title = history.EstimateTitleName__c;
    row.historyType = history.Type__c;
    row.version = history.Version__c;
    row.estimateDate = history.EstimateDate__c;
    row.validDate = history.EstimateValidDate__c;
    row.estimateSentAt = history.EstimateSentAt__c;
    row.autoCreated = history.RenewEstimateAutoCreated__c == true;
    row.opportunityId = history.Opportunity__c;
    row.opportunityName = history.Opportunity__r == null
      ? null
      : history.Opportunity__r.Name;
    row.serviceId = history.ContractService__c;
    row.serviceName = history.ContractService__r == null
      ? null
      : history.ContractService__r.Name;
    row.accountId = history.ContractService__r == null
      ? null
      : history.ContractService__r.Account__c;
    row.accountName =
      history.ContractService__r == null ||
      history.ContractService__r.Account__r == null
        ? null
        : history.ContractService__r.Account__r.Name;
    Decimal storedTax = history.ContractService__r == null
      ? null
      : history.ContractService__r.TaxPercent__c;
    row.taxPercent = TaxCalculationUtil.resolveTaxPercent(
      TaxCalculationUtil.fromPercentFieldStorage(storedTax)
    );
    row.amountIncludingTax = TaxCalculationUtil.calculateAmountInclTax(
      history.DeltaAmountSum__c,
      row.taxPercent
    );
    BillingAccount__c billing = history.ContractService__r == null
      ? null
      : history.ContractService__r.BiilingAcccount__r;
    if (billing != null) {
      row.billingAddressee = billing.BillingAddressee__c;
    }
    row.toAddresses = estimateSendContactEmail(history);
    row.ccAddresses = null;
    row.bccAddresses = null;
    row.sendable = true;
    if (!canSend) {
      row.sendable = false;
      row.sendableReason = '見積送付権限がありません。';
    } else if (!featureEnabled) {
      row.sendable = false;
      row.sendableReason = '見積送付機能が無効です。';
    }
    row.lastModifiedToken = ContractOptimisticLockUtil.toToken(
      history.LastModifiedDate
    );
    return row;
  }

  private static ContractHistory__c loadActionHistory(Id historyId) {
    return loadActionHistory(historyId, false);
  }

  /** 仕様: Core 第7.10節。送付開始時に行ロックし、同時送付の後着を失敗させる。 */
  private static ContractHistory__c loadActionHistory(
    Id historyId,
    Boolean lockForUpdate
  ) {
    if (historyId == null) {
      throw handledMessage('契約履歴IDが指定されていません。');
    }
    List<ContractHistory__c> records = lockForUpdate
      ? [
          SELECT
            Id,
            Name,
            historystatus__c,
            EstimateTitleName__c,
            Type__c,
            Version__c,
            EstimateDate__c,
            EstimateValidDate__c,
            DeltaAmountSum__c,
            EstimateSentAt__c,
            RenewEstimateAutoCreated__c,
            LastModifiedDate,
            Opportunity__c,
            Opportunity__r.Name,
            EstimateSendContact__c,
            EstimateSendContact__r.Email,
            ContractService__c,
            ContractService__r.Name,
            ContractService__r.TaxPercent__c,
            ContractService__r.Account__c,
            ContractService__r.Account__r.Name,
            ContractService__r.BiilingAcccount__c,
            ContractService__r.BiilingAcccount__r.BillingAddressee__c,
            ContractService__r.BiilingAcccount__r.BillingEmailTo__c,
            ContractService__r.BiilingAcccount__r.BillingEmailCc__c,
            ContractService__r.BiilingAcccount__r.BillingEmailBcc__c
          FROM ContractHistory__c
          WHERE Id = :historyId
          WITH SYSTEM_MODE
          FOR UPDATE
          LIMIT 1
        ]
      : [
      SELECT
        Id,
        Name,
        historystatus__c,
        EstimateTitleName__c,
        Type__c,
        Version__c,
        EstimateDate__c,
        EstimateValidDate__c,
        DeltaAmountSum__c,
        EstimateSentAt__c,
        RenewEstimateAutoCreated__c,
        LastModifiedDate,
        Opportunity__c,
        Opportunity__r.Name,
        EstimateSendContact__c,
        EstimateSendContact__r.Email,
        ContractService__c,
        ContractService__r.Name,
        ContractService__r.TaxPercent__c,
        ContractService__r.Account__c,
        ContractService__r.Account__r.Name,
        ContractService__r.BiilingAcccount__c,
        ContractService__r.BiilingAcccount__r.BillingAddressee__c,
        ContractService__r.BiilingAcccount__r.BillingEmailTo__c,
        ContractService__r.BiilingAcccount__r.BillingEmailCc__c,
        ContractService__r.BiilingAcccount__r.BillingEmailBcc__c
      FROM ContractHistory__c
      WHERE Id = :historyId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (records.isEmpty()) {
      throw handledMessage('契約履歴が見つかりません。');
    }
    return records[0];
  }

  /** 仕様: Core 第4.3.12節、第4.8節、第7.10節。個別送付は比較なし。 */
  private static void assertActionAllowed(
    ContractHistory__c history,
    Boolean enforcePermission,
    Boolean forSend
  ) {
    if (enforcePermission) {
      ContractPermissionUtil.assertSendEstimates();
    }
    assertDocumentModeAllowed(forSend);
    if (history.historystatus__c != STATUS_ESTIMATE) {
      throw handledMessage(ESTIMATE_STATUS_REQUIRED_MESSAGE);
    }
  }

  /** 仕様: Core 第11.3節 */
  private static void assertDocumentModeAllowed(Boolean forSend) {
    String mode = ContractDocumentSettingService.requireSendMode('Estimate');
    if (mode == ContractDocumentSettingService.MODE_UNUSED) {
      throw handledMessage('見積書機能が使わないのため発行・送付できません。');
    }
    if (forSend && mode != ContractDocumentSettingService.MODE_PDF_AND_EMAIL) {
      throw handledMessage('PDFとメール送付のときだけメール送付できます。');
    }
  }

  private static Boolean isEmailEnabled() {
    return ContractDocumentSettingService.requireSendMode('Estimate') ==
      ContractDocumentSettingService.MODE_PDF_AND_EMAIL;
  }

  private static ContractDocumentSetting__c loadOrganizationSetting() {
    List<ContractDocumentSetting__c> settings = [
      SELECT
        EstimateSendMode__c,
        EstimateDefaultDocumentTemplateKey__c,
        EstimateDefaultEmailTemplateApiName__c,
        EstimateOrgWideEmailAddress__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return settings.isEmpty() ? new ContractDocumentSetting__c() : settings[0];
  }

  private static SelectOptionDto option(String label, String value) {
    SelectOptionDto item = new SelectOptionDto();
    item.label = label;
    item.value = value;
    return item;
  }

  private static String resolveDocumentTemplateKey(
    String requestedKey,
    ContractDocumentSetting__c setting
  ) {
    if (String.isNotBlank(requestedKey)) {
      return requestedKey.trim();
    }
    return setting.EstimateDefaultDocumentTemplateKey__c;
  }

  private static ActionResultDto toActionResult(
    EstimateDocumentService.IssueResult issued
  ) {
    ActionResultDto result = new ActionResultDto();
    result.contentVersionId = issued.contentVersionId;
    result.fileName = issued.fileName;
    result.documentTemplateKey = issued.templateKey;
    List<ContentVersion> versions = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :issued.contentVersionId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!versions.isEmpty()) {
      result.contentDocumentId = versions[0].ContentDocumentId;
    }
    return result;
  }

  private static AuraHandledException handled(
    String prefix,
    Exception source
  ) {
    String message = prefix;
    if (source != null && String.isNotBlank(source.getMessage())) {
      message += ' ' + source.getMessage();
    }
    return handledMessage(message);
  }

  private static AuraHandledException handledMessage(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
