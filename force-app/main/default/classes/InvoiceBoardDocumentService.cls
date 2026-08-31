/**
 * 請求ボードからの個別発行・送付。顧客へ送らない発行と、メール送付を分ける。
 */
public without sharing class InvoiceBoardDocumentService {
  public static final String UNUSED_BLOCK_MESSAGE = '請求書設定が使わないのため、発行も送付もできません。';
  public static final String SEND_MODE_BLOCK_MESSAGE = '請求書設定がPDFとメール送付のときだけ送付できます。';
  public static final String CANCELLED_BLOCK_MESSAGE = '取消済みの請求は発行・送付できません。';
  public static final String DRAFT_BLOCK_MESSAGE = '確定済みの請求だけ発行・送付できます。';
  public static final String MISSING_ATTACHMENT_MESSAGE =
    '添付ファイルを選択してください。';
  public static final String MISSING_ATTACHMENT_NAME_MESSAGE =
    '添付ファイル名を設定してください。';
  public static final String ATTACHMENT_NEW = EstimateDocumentService.ATTACHMENT_NEW;

  @TestVisible
  private static Boolean skipEmailSend = false;

  public class SendDraftDto {
    @AuraEnabled public String toAddresses;
    @AuraEnabled public String ccAddresses;
    @AuraEnabled public String bccAddresses;
    @AuraEnabled public String subject;
    @AuraEnabled public String body;
    @AuraEnabled public String fileName;
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
    @AuraEnabled public String attachmentId;
    @AuraEnabled public List<EstimateDocumentService.FileOptionDto> attachmentOptions;
    @AuraEnabled public String newIssueFileName;
  }

  public class DocumentResultDto {
    @AuraEnabled
    public Id contentVersionId;
    @AuraEnabled
    public Id contentDocumentId;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public String documentTemplateKey;
    @AuraEnabled
    public Datetime sentAt;
  }

  /** 仕様: Core 第7.7.3節、第4.8節、第7.10節、第11.3.2節。発行するときにファイル名を見せる。この画面では直さない。 */
  @AuraEnabled
  public static DocumentResultDto previewIssueFromPreview(
    Id invoiceId,
    String documentTemplateKey,
    Id contractHistoryId
  ) {
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId }
    );
    return previewIssueFromPreview(invoiceId, documentTemplateKey);
  }

  /** 仕様: Core 第4.8節、第7.10節、第11.3.2節、第12.2節。発行するときにファイル名を見せる。この画面では直さない。 */
  public static DocumentResultDto previewIssueFromPreview(
    Id invoiceId,
    String documentTemplateKey
  ) {
    ContractPermissionUtil.assertSendInvoice();
    try {
      Invoice__c invoice = loadInvoice(invoiceId);
      String mode = ContractDocumentSettingService.requireSendMode('Invoice');
      if (mode == ContractDocumentSettingService.MODE_UNUSED) {
        throw handledMessage(UNUSED_BLOCK_MESSAGE);
      }
      if (InvoiceTransactionStatusService.isCancelled(invoice)) {
        throw handledMessage(CANCELLED_BLOCK_MESSAGE);
      }
      if (!InvoiceTransactionStatusService.isConfirmed(invoice)) {
        throw handledMessage(DRAFT_BLOCK_MESSAGE);
      }
      ContractDocumentSetting__c setting = loadSendSetting();
      String resolvedKey = String.isNotBlank(documentTemplateKey)
        ? documentTemplateKey.trim()
        : setting.InvoiceDefaultDocumentTemplateKey__c;
      ContractDocumentTemplateService.TemplateDefinition template =
        ContractDocumentTemplateService.resolveTemplate(
          ContractDocumentTemplateService.TYPE_INVOICE,
          resolvedKey
        );
      DocumentResultDto preview = new DocumentResultDto();
      preview.fileName = InvoiceDocumentService.buildFileName(invoice, template);
      preview.documentTemplateKey = template.templateKey;
      return preview;
    } catch (AuraHandledException ex) {
      throw ex;
    } catch (Exception ex) {
      throw handled('請求書の発行ファイル名を取得できませんでした。', ex);
    }
  }

  /** 仕様: Core 第7.7.3節、第7.10節 */
  @AuraEnabled
  public static DocumentResultDto issueFromPreview(
    Id invoiceId,
    String documentTemplateKey,
    String expectedToken,
    Id contractHistoryId
  ) {
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId }
    );
    return issueFromPreview(invoiceId, documentTemplateKey, expectedToken);
  }

  /** 仕様: Core 第7.7.3節、第7.10節、第12.2節。個別発行は処理中に重ねない。 */
  public static DocumentResultDto issueFromPreview(
    Id invoiceId,
    String documentTemplateKey,
    String expectedToken
  ) {
    ContractPermissionUtil.assertSendInvoice();
    try {
      Invoice__c invoice = loadInvoice(invoiceId, true);
      assertIssuable(invoice, false);
      InvoiceDocumentService.IssueResult issued = InvoiceDocumentService.issueInvoiceDocument(
        invoice.Id,
        documentTemplateKey
      );
      return toResult(issued);
    } catch (AuraHandledException ex) {
      throw ex;
    } catch (Exception ex) {
      throw handled('請求書を発行できませんでした。', ex);
    }
  }

  /** 仕様: Core 第7.7.3節、第7.10節、第11.3.2節 */
  public static DocumentResultDto sendFromPreview(
    Id invoiceId,
    String documentTemplateKey,
    String emailTemplateApiName,
    String expectedToken
  ) {
    return sendFromPreview(
      invoiceId,
      documentTemplateKey,
      emailTemplateApiName,
      expectedToken,
      null
    );
  }

  /** 仕様: Core 第7.7.3節、第7.10節、第4.8節 */
  @AuraEnabled
  public static DocumentResultDto sendFromPreview(
    Id invoiceId,
    String documentTemplateKey,
    String emailTemplateApiName,
    String expectedToken,
    SendDraftDto draft,
    Id contractHistoryId
  ) {
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId }
    );
    return sendFromPreview(
      invoiceId,
      documentTemplateKey,
      emailTemplateApiName,
      expectedToken,
      draft
    );
  }

  /** 仕様: Core 第7.7.3節、第7.10節、第4.8節、第12.2節 */
  public static DocumentResultDto sendFromPreview(
    Id invoiceId,
    String documentTemplateKey,
    String emailTemplateApiName,
    String expectedToken,
    SendDraftDto draft
  ) {
    ContractPermissionUtil.assertSendInvoice();
    try {
      Invoice__c invoice = loadInvoice(invoiceId, true);
      assertIssuable(invoice, true);
      return sendConfirmedInvoice(
        invoice,
        documentTemplateKey,
        emailTemplateApiName,
        draft
      );
    } catch (AuraHandledException ex) {
      throw ex;
    } catch (Exception ex) {
      throw handled('請求書を送付できませんでした。', ex);
    }
  }

  /** 仕様: Core 第7.10節、第4.8節。Aura互換の3引数入口。 */
  public static SendPreviewDto previewFromPreview(
    Id invoiceId,
    String documentTemplateKey,
    String emailTemplateApiName
  ) {
    return previewFromPreview(
      invoiceId,
      documentTemplateKey,
      emailTemplateApiName,
      null
    );
  }

  /** 仕様: Core 第7.7.3節、第7.10節、第4.8節 */
  @AuraEnabled
  public static SendPreviewDto previewFromPreview(
    Id invoiceId,
    String documentTemplateKey,
    String emailTemplateApiName,
    String preferredAttachmentId,
    Id contractHistoryId
  ) {
    InvoiceOpsController.assertInvoicesInScope(
      contractHistoryId,
      new List<Id>{ invoiceId }
    );
    return previewFromPreview(
      invoiceId,
      documentTemplateKey,
      emailTemplateApiName,
      preferredAttachmentId
    );
  }

  /** 仕様: Core 第7.10節、第4.8節、第12.2節 */
  public static SendPreviewDto previewFromPreview(
    Id invoiceId,
    String documentTemplateKey,
    String emailTemplateApiName,
    String preferredAttachmentId
  ) {
    ContractPermissionUtil.assertSendInvoice();
    try {
      Invoice__c invoice = loadInvoice(invoiceId);
      String mode = ContractDocumentSettingService.requireSendMode('Invoice');
      if (mode == ContractDocumentSettingService.MODE_UNUSED) {
        throw handledMessage(UNUSED_BLOCK_MESSAGE);
      }
      if (mode != ContractDocumentSettingService.MODE_PDF_AND_EMAIL) {
        throw handledMessage(SEND_MODE_BLOCK_MESSAGE);
      }
      if (InvoiceTransactionStatusService.isCancelled(invoice)) {
        throw handledMessage(CANCELLED_BLOCK_MESSAGE);
      }
      if (!InvoiceTransactionStatusService.isConfirmed(invoice)) {
        throw handledMessage(DRAFT_BLOCK_MESSAGE);
      }
      ContractDocumentSetting__c setting = loadSendSetting();
      ContractEmailTemplateService.MergeResult merged;
      ContractEmailTemplateService.OrgWideResolved sender;
      try {
        merged = ContractEmailTemplateService.renderForSend(
          ContractEmailTemplateService.TYPE_INVOICE,
          emailTemplateApiName,
          setting.InvoiceDefaultEmailTemplateApiName__c,
          invoice.Id
        );
        sender = ContractEmailTemplateService.resolveOrgWide(
          setting.InvoiceOrgWideEmailAddress__c
        );
      } catch (ContractEmailTemplateService.EmailTemplateException ex) {
        throw handledMessage(ex.getMessage());
      }
      String resolvedKey = String.isNotBlank(documentTemplateKey)
        ? documentTemplateKey.trim()
        : setting.InvoiceDefaultDocumentTemplateKey__c;
      ContractDocumentTemplateService.TemplateDefinition template =
        ContractDocumentTemplateService.resolveTemplate(
          ContractDocumentTemplateService.TYPE_INVOICE,
          resolvedKey
        );
      SendPreviewDto preview = new SendPreviewDto();
      preview.orgWideEmailAddress = sender.address;
      preview.fromLabel = ContractEmailTemplateService.formatOrgWideFrom(
        sender
      );
      preview.toAddresses = invoice.BillingEmailToSnapShot__c;
      preview.ccAddresses = invoice.BillingEmailCcSnapShot__c;
      preview.bccAddresses = invoice.BillingEmailBccSnapShot__c;
      preview.subject = merged.subject;
      preview.body = merged.body;
      preview.documentTemplateKey = template.templateKey;
      preview.emailTemplateApiName = merged.apiName;
      preview.attachmentOptions = EstimateDocumentService.listLinkedFiles(
        invoice.Id
      );
      preview.attachmentId = EstimateDocumentService.initialAttachmentId(
        preview.attachmentOptions,
        preferredAttachmentId
      );
      preview.fileName = EstimateDocumentService.fileNameForAttachment(
        preview.attachmentOptions,
        preview.attachmentId,
        InvoiceDocumentService.buildFileName(invoice, template)
      );
      preview.newIssueFileName = InvoiceDocumentService.buildFileName(
        invoice,
        template
      );
      return preview;
    } catch (AuraHandledException ex) {
      throw ex;
    } catch (Exception ex) {
      throw handled('請求書送付プレビューを取得できませんでした。', ex);
    }
  }

  private static DocumentResultDto sendConfirmedInvoice(
    Invoice__c invoice,
    String documentTemplateKey,
    String emailTemplateApiName,
    SendDraftDto draft
  ) {
    // 仕様: Core 第7.10節。請求の To／Cc／Bcc は送付画面では直さない。スナップショットの参照。
    String toRaw = invoice.BillingEmailToSnapShot__c;
    String ccRaw = invoice.BillingEmailCcSnapShot__c;
    String bccRaw = invoice.BillingEmailBccSnapShot__c;
    List<String> toAddresses = parseAddresses(toRaw, 'To');
    if (toAddresses.isEmpty()) {
      throw handledMessage('請求のToメールアドレスを設定してください。');
    }
    List<String> ccAddresses = parseAddresses(ccRaw, 'Cc');
    List<String> bccAddresses = parseAddresses(bccRaw, 'Bcc');

    ContractDocumentSetting__c setting = loadSendSetting();
    ContractEmailTemplateService.EmailTemplateDefinition emailTemplate;
    ContractEmailTemplateService.OrgWideResolved sender;
    try {
      emailTemplate = ContractEmailTemplateService.resolveForOperation(
        ContractEmailTemplateService.TYPE_INVOICE,
        emailTemplateApiName,
        setting.InvoiceDefaultEmailTemplateApiName__c
      );
      sender = ContractEmailTemplateService.resolveOrgWide(
        setting.InvoiceOrgWideEmailAddress__c
      );
    } catch (ContractEmailTemplateService.EmailTemplateException ex) {
      throw handledMessage(ex.getMessage());
    }
    String resolvedDocumentTemplateKey = String.isNotBlank(documentTemplateKey)
      ? documentTemplateKey.trim()
      : setting.InvoiceDefaultDocumentTemplateKey__c;
    if (
      String.isNotBlank(resolvedDocumentTemplateKey) &&
      resolvedDocumentTemplateKey.length() > 80
    ) {
      throw handledMessage('帳票テンプレートキーは80文字以内で指定してください。');
    }

    String attachmentFileName = draft != null &&
      String.isNotBlank(draft.fileName)
      ? draft.fileName.trim()
      : null;
    if (String.isBlank(attachmentFileName)) {
      throw handledMessage(MISSING_ATTACHMENT_NAME_MESSAGE);
    }
    String attachmentId = draft == null ? null : draft.attachmentId;
    ContentVersion versionRecord = resolveSendContent(
      invoice.Id,
      attachmentId,
      resolvedDocumentTemplateKey,
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
    message.setOrgWideEmailAddressId(sender.orgWideId);
    if (draft != null) {
      message.setSubject(draft.subject == null ? '' : draft.subject);
      message.setPlainTextBody(draft.body == null ? '' : draft.body);
    } else {
      message.setTemplateId(emailTemplate.emailTemplateId);
      // 仕様: Core 第7.10節。TargetObjectId は操作者 User。To に足さない。
      message.setTargetObjectId(UserInfo.getUserId());
      message.setTreatTargetObjectAsRecipient(false);
      message.setWhatId(invoice.Id);
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
    Invoice__c sentInvoice = new Invoice__c(
      Id = invoice.Id,
      InvoiceTransactionStatus__c = invoice.InvoiceTransactionStatus__c
    );
    // 仕様: Core 第7.10節・第7.11節、日付仕様 第8章
    InvoiceTransactionStatusService.applyDelivery(
      sentInvoice,
      InvoiceTransactionStatusService.DELIVERY_SENT,
      InvoiceTransactionStatusService.organizationToday()
    );
    Boolean previousStatus = InvoiceTransactionStatusService.allowStatusWrite;
    InvoiceTransactionStatusService.allowStatusWrite = true;
    try {
      SystemContextAccess.updateRecords(new List<SObject>{ sentInvoice });
    } finally {
      InvoiceTransactionStatusService.allowStatusWrite = previousStatus;
    }

    DocumentResultDto result = new DocumentResultDto();
    result.contentVersionId = versionRecord.Id;
    result.contentDocumentId = versionRecord.ContentDocumentId;
    result.fileName = attachmentFileName;
    result.documentTemplateKey = resolvedDocumentTemplateKey;
    result.sentAt = sentAt;
    ContractOperationLogService.write(
      'InvoiceSend',
      null,
      'Invoice__c',
      String.valueOf(invoice.Id)
    );
    return result;
  }

  /** 仕様: Core 第7.10節。未選択では送れない。新しく発行するは送るときに作る。 */
  private static ContentVersion resolveSendContent(
    Id invoiceId,
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
      InvoiceDocumentService.IssueResult issued;
      try {
        issued = InvoiceDocumentService.issueInvoiceDocument(
          invoiceId,
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
      invoiceId
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

  /** 仕様: Core 第4.3.12節、第7.10節。個別発行・送付は比較なし。 */
  private static void assertIssuable(
    Invoice__c invoice,
    Boolean forSend
  ) {
    String mode = ContractDocumentSettingService.requireSendMode('Invoice');
    if (mode == ContractDocumentSettingService.MODE_UNUSED) {
      throw handledMessage(UNUSED_BLOCK_MESSAGE);
    }
    if (forSend && mode != ContractDocumentSettingService.MODE_PDF_AND_EMAIL) {
      throw handledMessage(SEND_MODE_BLOCK_MESSAGE);
    }
    if (forSend && !InvoiceDeliveryMethodService.allowsEmailSend(invoice)) {
      throw handledMessage(InvoiceDeliveryMethodService.SEND_NOT_ALLOWED_MESSAGE);
    }
    if (InvoiceTransactionStatusService.isCancelled(invoice)) {
      throw handledMessage(CANCELLED_BLOCK_MESSAGE);
    }
    if (!InvoiceTransactionStatusService.isConfirmed(invoice)) {
      throw handledMessage(DRAFT_BLOCK_MESSAGE);
    }
  }

  private static Invoice__c loadInvoice(Id invoiceId) {
    return loadInvoice(invoiceId, false);
  }

  /** 仕様: Core 第7.10節。個別発行・送付の開始時に行ロックし、同時の後着を失敗させる。 */
  private static Invoice__c loadInvoice(Id invoiceId, Boolean lockForUpdate) {
    if (invoiceId == null) {
      throw handledMessage('請求IDが指定されていません。');
    }
    List<Invoice__c> records = lockForUpdate
      ? [
          SELECT
            Id,
            Name,
            InvoiceDate__c,
            InvoiceTransactionStatus__c,
            BillingAddresseeSnapShot__c,
            BillingEmailToSnapShot__c,
            BillingEmailCcSnapShot__c,
            BillingEmailBccSnapShot__c,
            InvoiceDeliveryMethodSnapShot__c,
            LastModifiedDate
          FROM Invoice__c
          WHERE Id = :invoiceId
          WITH SYSTEM_MODE
          LIMIT 1
          FOR UPDATE
        ]
      : [
          SELECT
            Id,
            Name,
            InvoiceDate__c,
            InvoiceTransactionStatus__c,
            BillingAddresseeSnapShot__c,
            BillingEmailToSnapShot__c,
            BillingEmailCcSnapShot__c,
            BillingEmailBccSnapShot__c,
            InvoiceDeliveryMethodSnapShot__c,
            LastModifiedDate
          FROM Invoice__c
          WHERE Id = :invoiceId
          WITH SYSTEM_MODE
          LIMIT 1
        ];
    if (records.isEmpty()) {
      throw handledMessage('請求が見つかりません。');
    }
    return records[0];
  }

  private static ContractDocumentSetting__c loadSendSetting() {
    List<ContractDocumentSetting__c> settings = [
      SELECT
        InvoiceDefaultDocumentTemplateKey__c,
        InvoiceDefaultEmailTemplateApiName__c,
        InvoiceOrgWideEmailAddress__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return settings.isEmpty() ? new ContractDocumentSetting__c() : settings[0];
  }

  /** 仕様: Core 第7.10節。カンマ区切り。255文字以内。前後空白除去。空の区切りは無視。 */
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

  private static Id parseOptionalId(String raw, String errorMessage) {
    if (String.isBlank(raw)) {
      return null;
    }
    try {
      return (Id) raw.trim();
    } catch (Exception ex) {
      throw handledMessage(errorMessage);
    }
  }

  private static DocumentResultDto toResult(
    InvoiceDocumentService.IssueResult issued
  ) {
    DocumentResultDto result = new DocumentResultDto();
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

  private static AuraHandledException handled(String prefix, Exception source) {
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
