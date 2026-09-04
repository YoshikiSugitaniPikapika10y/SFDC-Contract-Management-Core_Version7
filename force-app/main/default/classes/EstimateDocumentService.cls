/**
 * 見積書の表示データ組み立て・PDF 発行・ファイル保存。
 *
 * 会社名・住所は ContractDocumentSetting__c の発行時点の値を使う。
 */
public without sharing class EstimateDocumentService {

  /** 仕様: Core 第0.1節、第4.8節 */
  @TestVisible
  private static final String ESTIMATE_STATUS_REQUIRED_MESSAGE =
    '見積書の表示・発行はステータスが見積の契約履歴のみ利用できます。';

  public class LineDto {
    public String productName;
    public Decimal quantity;
    public String unit;
    public Decimal unitPrice;
    public Decimal amount;
    public String periodLabel;
    public String billingType;
    public String invoiceSetting;
    public String typeLabel;
  }

  /** 商談 EstimatePdf と同じ明細行 DTO */
  public class GroupedLineDto {
    public String breakdown;
    public String unit;
    public Decimal quantity;
    public Decimal amount;
    public String period;
  }

  /** 商談 EstimatePdf と同じ商品名グループ DTO */
  public class GroupDto {
    public String productName;
    public List<GroupedLineDto> items;
    public Decimal groupTotal;
    public Decimal taxAmount;
    public Decimal totalAmountIncTax;

    public GroupDto(String name) {
      productName = String.isBlank(name) ? '' : name;
      items = new List<GroupedLineDto>();
      groupTotal = 0;
      taxAmount = 0;
      totalAmountIncTax = 0;
    }
  }

  /**
   * 見積帳票の表示文言。
   * 発行元情報は請求書と共通の ContractDocumentSetting__c を正とし、
   * 帳票固有の固定ラベルはこの DTO で組み立てる。
   */
  public class EstimateDocumentTextDto {
    public String toCompanyName { get; set; }
    public String estimateTitle { get; set; }
    public String otherFeeLabel { get; set; }
    public Decimal tax { get; set; }
    public String termFeeStartDateLabel { get; set; }
    public String termFeeStartDateSentence { get; set; }
    public String estimateDateLabel { get; set; }
    public String estimateDateSentence { get; set; }
    public String ownerLabel { get; set; }
    public String ownerName { get; set; }
    public String postalNumber { get; set; }
    public String addressFirstHalf { get; set; }
    public String addressLastHalf { get; set; }
    public String companyName { get; set; }
    public String telLabel { get; set; }
    public String telValue { get; set; }
    public String faxLabel { get; set; }
    public String faxSentence { get; set; }
    public String paymentTermLabel { get; set; }
    public String paymentTermSentence { get; set; }
    public String termDueDateLabel { get; set; }
    public String estimateDueDateSentence { get; set; }
    public String basicTermPeriodLabel { get; set; }
    public String basicTermPeriod { get; set; }
    public String estimateSumLabel { get; set; }
    public String unitLabel { get; set; }
    public String unitSentence { get; set; }
    public String honorificTitle { get; set; }
    public String digitalLicenceFeeLabel { get; set; }
    public String consultingFeeLabel { get; set; }
    public String feedbackCoachingFeeLabel { get; set; }
    public String noteSentenceLabel { get; set; }
    public String noteSentence { get; set; }
    public String documentFooter { get; set; }
    public String privacyPolicyUrl { get; set; }
    public String estimateNumberLabel { get; set; }
    public String estimateSentence { get; set; }
  }

  public class DocumentContext {
    public ContractHistory__c history;
    public List<LineDto> lines;
    public Decimal lineTotal;
    public Decimal taxPercent;
    public Decimal taxAmount;
    public Decimal lineTotalInclTax;
    public String taxPercentLabel;
    public String companyName;
    public String companyPostalCode;
    public String companyAddressLine1;
    public String companyAddressLine2;
    public String companyRegistrationNumber;
    public String addresseeName;
    public String accountName;
    public String masterNoteText;
    public String documentTitle;
    public String estimateDateLabel;
    public String validDateLabel;
    public String issueDateLabel;
    public String termLabel;
    public String typeLabel;
    public EstimateDocumentTextDto documentText;
    public String toCompanyNameDisplay;
    public String ownerNameDisplay;
    public String estimateDateDisplay;
    public String termFeeStartDateDisplay;
    public String estimateNumber;
    public List<GroupDto> digitalGroups;
    public List<GroupDto> consultingGroups;
    public List<GroupDto> trainingGroups;
    public List<GroupDto> otherGroups;
    public Decimal digitalTotalIncTax;
    public Decimal consultingTotalIncTax;
    public Decimal trainingTotalIncTax;
    public Decimal otherTotalIncTax;
    public Decimal totalAmount;
  }

  public class IssueResult {
    public Id contentVersionId;
    public Id contentDocumentId;
    public String fileName;
    public Date issueDate;
    public String templateKey;
    public String visualforcePage;
  }

  public class EstimateDocumentException extends Exception {
  }

  public static DocumentContext loadContext(Id contractHistoryId) {
    if (contractHistoryId == null) {
      throw new EstimateDocumentException('契約履歴IDが指定されていません。');
    }

    List<ContractHistory__c> histories = [
      SELECT
        Id,
        Name,
        Type__c,
        historystatus__c,
        EstimateTitleName__c,
        EstimateDate__c,
        EstimateValidDate__c,
        EstimateIssueDate__c,
        Note__c,
        CurrentTermStartDate__c,
        CurrentTermEndDate__c,
        DeltaAmountSum__c,
        EstimateNoteMaster__r.NoteText__c,
        Opportunity__c,
        Opportunity__r.Name,
        Opportunity__r.Owner.Name,
        ContractService__r.TaxPercent__c,
        ContractService__r.Account__r.Name,
        ContractService__r.BiilingAcccount__r.BillingAddressee__c
      FROM ContractHistory__c
      WHERE Id = :contractHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (histories.isEmpty()) {
      throw new EstimateDocumentException('契約履歴が見つかりません。');
    }
    assertEstimateStatusForDocument(histories[0]);

    DocumentContext context = new DocumentContext();
    context.history = histories[0];
    ContractDocumentSetting__c orgSetting = loadDocumentOrgSetting();
    context.companyName = orgDocumentText(orgSetting.CompanyName__c);
    context.companyPostalCode = '';
    context.companyAddressLine1 = orgDocumentText(orgSetting.Address__c);
    context.companyAddressLine2 = '';
    context.companyRegistrationNumber = '';
    context.lines = loadLines(contractHistoryId, context.history.Type__c);
    context.lineTotal = resolveLineTotal(context.history, context.lines);
    // Percent 項目の Apex 値（0.1＝10%）を表示％へ戻してから正規化する。未入力は 0%。
    context.taxPercent = TaxCalculationUtil.resolveTaxPercent(
      TaxCalculationUtil.fromPercentFieldStorage(
        context.history.ContractService__r == null
          ? null
          : context.history.ContractService__r.TaxPercent__c
      )
    );
    context.taxAmount = TaxCalculationUtil.calculateTaxAmount(
      context.lineTotal,
      context.taxPercent
    );
    context.lineTotalInclTax = TaxCalculationUtil.calculateAmountInclTax(
      context.lineTotal,
      context.taxPercent
    );
    context.taxPercentLabel = TaxCalculationUtil.formatTaxPercentLabel(
      context.taxPercent
    );
    context.addresseeName = resolveAddresseeName(context.history);
    context.accountName = resolveAccountName(context.history);
    context.masterNoteText = context.history.EstimateNoteMaster__r == null
      ? null
      : context.history.EstimateNoteMaster__r.NoteText__c;
    context.documentTitle = resolveDocumentTitle(context.history);
    context.estimateDateLabel = formatDisplayDate(
      context.history.EstimateDate__c
    );
    context.validDateLabel = formatDisplayDate(
      context.history.EstimateValidDate__c
    );
    context.issueDateLabel = formatDisplayDate(
      context.history.EstimateIssueDate__c
    );
    context.termLabel = buildTermLabel(
      context.history.CurrentTermStartDate__c,
      context.history.CurrentTermEndDate__c
    );
    context.typeLabel = resolveHistoryTypeLabel(context.history.Type__c);
    buildGroupedPdfContext(context);
    return context;
  }

  /**
   * 見積書 PDF は Estimate のみ。Ordered／Archive は Dynamic Actions 非表示に加え、
   * URL 直叩きでも Apex で拒否する。
   */
  @TestVisible
  private static void assertEstimateStatusForDocument(
    ContractHistory__c history
  ) {
    if (
      history == null ||
      history.historystatus__c !=
      ContractDomainConstants.HISTORY_STATUS_ESTIMATE
    ) {
      throw new EstimateDocumentException(ESTIMATE_STATUS_REQUIRED_MESSAGE);
    }
  }

  public static IssueResult issueEstimateDocument(Id contractHistoryId) {
    return issueEstimateDocument(contractHistoryId, null);
  }

  /** 仕様: Core 第4.8節、第7.10節、第11.3.2節。キー空は発行できない。 */
  public static IssueResult issueEstimateDocument(
    Id contractHistoryId,
    String templateKey
  ) {
    return issueEstimateDocument(contractHistoryId, templateKey, null);
  }

  /** 仕様: Core 第4.8節、第7.10節。attachmentFileName は「新しく発行する」の送付添付名。個別発行は処理中に重ねない。 */
  public static IssueResult issueEstimateDocument(
    Id contractHistoryId,
    String templateKey,
    String attachmentFileName
  ) {
    ContractDocumentTemplateService.TemplateDefinition template = resolveIssueTemplate(
      templateKey
    );
    try {
      if (
        ContractDocumentSettingService.requireSendMode('Estimate') ==
        ContractDocumentSettingService.MODE_UNUSED
      ) {
        throw new EstimateDocumentException(
          '見積書設定が使わないのため、発行も送付もできません。'
        );
      }
      ContractDocumentSettingService.assertRequiredCompanyFields();
    } catch (ContractDocumentSettingService.SettingException ex) {
      throw new EstimateDocumentException(
        ContractDocumentSettingService.withDocumentSendHeading(ex.getMessage())
      );
    }
    lockHistoryForDocumentIssue(contractHistoryId);
    DocumentContext context = loadContext(contractHistoryId);
    Date issueDate = ensureIssueDate(context.history);
    context.history.EstimateIssueDate__c = issueDate;
    context.issueDateLabel = formatDisplayDate(issueDate);

    String fileName = String.isNotBlank(attachmentFileName)
      ? attachmentFileName.trim()
      : buildFileName(context.history, issueDate, template);
    Blob pdfBody = generatePdfBlob(contractHistoryId, template);
    Id contentVersionId = savePdfToRecord(contractHistoryId, fileName, pdfBody);

    IssueResult result = new IssueResult();
    result.contentVersionId = contentVersionId;
    result.contentDocumentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :contentVersionId
      WITH SYSTEM_MODE
      LIMIT 1
    ]
    .ContentDocumentId;
    result.fileName = fileName;
    result.issueDate = issueDate;
    result.templateKey = template.templateKey;
    result.visualforcePage = template.visualforcePage;
    if (ContractOperationLogService.suppressIssueLog != true) {
      ContractOperationLogService.write(
        'EstimatePdfIssue',
        null,
        'ContractHistory__c',
        String.valueOf(contractHistoryId)
      );
    }
    return result;
  }

  /** 仕様: Core 第7.10節。個別発行・送付は開始時に行ロックし、同時の後着を失敗させる。 */
  private static void lockHistoryForDocumentIssue(Id contractHistoryId) {
    if (contractHistoryId == null) {
      throw new EstimateDocumentException('契約履歴が指定されていません。');
    }
    List<ContractHistory__c> locked = [
      SELECT Id
      FROM ContractHistory__c
      WHERE Id = :contractHistoryId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (locked.isEmpty()) {
      throw new EstimateDocumentException('契約履歴が見つかりません。');
    }
  }

  /**
   * 仕様: Core 第4.10節。発行日は自動で本日をセットしない。未設定なら null のまま返す。
   */
  public static Date ensureIssueDate(ContractHistory__c history) {
    if (history == null || history.Id == null) {
      throw new EstimateDocumentException('契約履歴が指定されていません。');
    }
    return history.EstimateIssueDate__c;
  }

  /** 仕様: Core 第11.3.2節、日付仕様 第8章 */
  public static String buildFileName(
    ContractHistory__c history,
    Date issueDate
  ) {
    String title = resolveDocumentTitle(history);
    String sanitizedTitle = sanitizeFileName(title);
    Date targetIssueDate = issueDate == null
      ? InvoiceTransactionStatusService.organizationToday()
      : issueDate;
    return sanitizedTitle + '_' + formatFileDate(targetIssueDate) + '.pdf';
  }

  /** 仕様: Core 第11.3.2節、日付仕様 第8章 */
  public static String buildFileName(
    ContractHistory__c history,
    Date issueDate,
    ContractDocumentTemplateService.TemplateDefinition template
  ) {
    if (template == null) {
      return buildFileName(history, issueDate);
    }
    String pattern = String.isBlank(template.fileNamePattern)
      ? '{TemplateKey}_{Title}_{yyyyMMdd}.pdf'
      : template.fileNamePattern;
    Date targetIssueDate = issueDate == null
      ? InvoiceTransactionStatusService.organizationToday()
      : issueDate;
    String rendered = pattern
      .replace('{TemplateKey}', sanitizeFileName(template.templateKey))
      .replace('{Title}', sanitizeFileName(resolveDocumentTitle(history)))
      .replace(
        '{DocumentType}',
        sanitizeFileName(template.documentType)
      )
      .replace('{yyyyMMdd}', formatCompactFileDate(targetIssueDate));
    rendered = sanitizeFileName(rendered);
    if (!rendered.toLowerCase().endsWith('.pdf')) {
      rendered += '.pdf';
    }
    return rendered;
  }

  public static Id savePdfToRecord(Id recordId, String fileName, Blob pdfBody) {
    if (recordId == null) {
      throw new EstimateDocumentException(
        '保存先の契約履歴IDが指定されていません。'
      );
    }
    if (pdfBody == null || pdfBody.size() == 0) {
      throw new EstimateDocumentException('PDFデータが空です。');
    }

    String normalizedFileName = String.isBlank(fileName)
      ? 'estimate.pdf'
      : fileName;
    String title = normalizedFileName.endsWith('.pdf')
      ? normalizedFileName.substring(0, normalizedFileName.length() - 4)
      : normalizedFileName;

    ContentVersion contentVersion = new ContentVersion(
      Title = title,
      PathOnClient = normalizedFileName,
      VersionData = pdfBody,
      ContractDocumentIssued__c = true
    );
    SystemContextAccess.insertRecords(new List<SObject>{ contentVersion });

    Id contentDocumentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :contentVersion.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ]
    .ContentDocumentId;

    ContentDocumentLink documentLink = new ContentDocumentLink(
      ContentDocumentId = contentDocumentId,
      LinkedEntityId = recordId,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );
    SystemContextAccess.insertRecords(new List<SObject>{ documentLink });
    return contentVersion.Id;
  }

  public class FileOptionDto {
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public Boolean issued;
  }

  public static final String ATTACHMENT_NEW = 'NEW';

  /** 仕様: Core 第7.10節。候補は最新の発行1つと「新しく発行する」だけ。印は画面に出さない。 */
  public static List<FileOptionDto> listLinkedFiles(Id linkedEntityId) {
    List<FileOptionDto> options = new List<FileOptionDto>();
    FileOptionDto createNew = new FileOptionDto();
    createNew.value = ATTACHMENT_NEW;
    createNew.label = '新しく発行する';
    createNew.fileName = null;
    createNew.issued = false;
    options.add(createNew);
    ContentVersion latest = latestIssuedVersion(linkedEntityId);
    if (latest == null) {
      return options;
    }
    FileOptionDto option = new FileOptionDto();
    option.value = String.valueOf(latest.ContentDocumentId);
    option.issued = true;
    option.fileName = linkedFileName(latest);
    option.label = option.fileName;
    options.add(option);
    return options;
  }

  /** 仕様: Core 第7.10節。古い発行は候補に出さない・送れない。 */
  public static Id latestIssuedContentDocumentId(Id linkedEntityId) {
    ContentVersion latest = latestIssuedVersion(linkedEntityId);
    return latest == null ? null : latest.ContentDocumentId;
  }

  /**
   * 仕様: Core 第7.10節。請求プレビュー・横断一覧は発行ファイルを一括で取る。
   */
  public static Map<Id, Id> latestIssuedContentDocumentIds(Set<Id> linkedEntityIds) {
    Map<Id, Id> result = new Map<Id, Id>();
    Map<Id, ContentVersion> latestByEntity = latestIssuedVersions(linkedEntityIds);
    for (Id linkedId : latestByEntity.keySet()) {
      ContentVersion latest = latestByEntity.get(linkedId);
      if (latest != null) {
        result.put(linkedId, latest.ContentDocumentId);
      }
    }
    return result;
  }

  private static ContentVersion latestIssuedVersion(Id linkedEntityId) {
    if (linkedEntityId == null) {
      return null;
    }
    return latestIssuedVersions(new Set<Id>{ linkedEntityId }).get(linkedEntityId);
  }

  private static Map<Id, ContentVersion> latestIssuedVersions(Set<Id> linkedEntityIds) {
    Map<Id, ContentVersion> latestByEntity = new Map<Id, ContentVersion>();
    if (linkedEntityIds == null || linkedEntityIds.isEmpty()) {
      return latestByEntity;
    }
    List<ContentDocumentLink> links = [
      SELECT LinkedEntityId, ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :linkedEntityIds
      WITH SYSTEM_MODE
    ];
    if (links.isEmpty()) {
      return latestByEntity;
    }
    Set<Id> documentIds = new Set<Id>();
    Map<Id, List<Id>> documentToEntities = new Map<Id, List<Id>>();
    for (ContentDocumentLink link : links) {
      if (link.ContentDocumentId == null || link.LinkedEntityId == null) {
        continue;
      }
      documentIds.add(link.ContentDocumentId);
      if (!documentToEntities.containsKey(link.ContentDocumentId)) {
        documentToEntities.put(link.ContentDocumentId, new List<Id>());
      }
      documentToEntities.get(link.ContentDocumentId).add(link.LinkedEntityId);
    }
    if (documentIds.isEmpty()) {
      return latestByEntity;
    }
    for (ContentVersion version : [
      SELECT
        ContentDocumentId,
        Title,
        FileExtension,
        PathOnClient,
        ContractDocumentIssued__c
      FROM ContentVersion
      WHERE
        ContentDocumentId IN :documentIds
        AND IsLatest = true
        AND ContractDocumentIssued__c = true
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC, Id DESC
    ]) {
      List<Id> entities = documentToEntities.get(version.ContentDocumentId);
      if (entities == null) {
        continue;
      }
      for (Id entityId : entities) {
        if (!latestByEntity.containsKey(entityId)) {
          latestByEntity.put(entityId, version);
        }
      }
    }
    return latestByEntity;
  }

  /** 仕様: Core 第7.10節。0件は新しく発行する、1件以上は最新の発行ファイル。 */
  public static String initialAttachmentId(
    List<FileOptionDto> options,
    String preferredDocumentId
  ) {
    if (preferredDocumentId == ATTACHMENT_NEW) {
      return ATTACHMENT_NEW;
    }
    List<FileOptionDto> files = new List<FileOptionDto>();
    if (options != null) {
      for (FileOptionDto option : options) {
        if (option != null && option.value != ATTACHMENT_NEW) {
          files.add(option);
          if (
            String.isNotBlank(preferredDocumentId) &&
            option.value == preferredDocumentId
          ) {
            return option.value;
          }
        }
      }
    }
    if (files.isEmpty()) {
      return ATTACHMENT_NEW;
    }
    return files[0].value;
  }

  public static String fileNameForAttachment(
    List<FileOptionDto> options,
    String attachmentId,
    String newIssueFileName
  ) {
    if (attachmentId == ATTACHMENT_NEW || String.isBlank(attachmentId)) {
      return newIssueFileName;
    }
    if (options != null) {
      for (FileOptionDto option : options) {
        if (option != null && option.value == attachmentId) {
          return option.fileName;
        }
      }
    }
    return newIssueFileName;
  }

  /** 仕様: Core 第7.10節。既存ファイルの添付名初期値は Files の Title（拡張子付き）。 */
  private static String linkedFileName(ContentVersion version) {
    if (version == null) {
      return '';
    }
    String title = String.isBlank(version.Title) ? '' : version.Title;
    String extension = String.isBlank(version.FileExtension)
      ? ''
      : version.FileExtension;
    if (String.isNotBlank(title) && String.isNotBlank(extension)) {
      String suffix = '.' + extension;
      return title.toLowerCase().endsWith(suffix.toLowerCase())
        ? title
        : title + suffix;
    }
    if (String.isNotBlank(title)) {
      return title;
    }
    if (String.isNotBlank(version.PathOnClient)) {
      return version.PathOnClient;
    }
    return 'file';
  }

  public static Blob generatePdfBlob(Id contractHistoryId) {
    ContractDocumentTemplateService.TemplateDefinition template = resolveIssueTemplate(
      null
    );
    return generatePdfBlob(contractHistoryId, template);
  }

  public static Blob generatePdfBlob(
    Id contractHistoryId,
    String templateKey
  ) {
    ContractDocumentTemplateService.TemplateDefinition template = resolveIssueTemplate(
      templateKey
    );
    return generatePdfBlob(contractHistoryId, template);
  }

  private static Blob generatePdfBlob(
    Id contractHistoryId,
    ContractDocumentTemplateService.TemplateDefinition template
  ) {
    if (Test.isRunningTest()) {
      return Blob.valueOf('%PDF-1.4 test');
    }

    PageReference pdfPage = ContractDocumentTemplateService.buildPageReference(
      template,
      contractHistoryId
    );
    return pdfPage.getContentAsPDF();
  }

  /** 仕様: Core 第4.8節、第11.9節。数量・単価は OrgDefault。HALF_UP 直書きしない。 */
  private static List<LineDto> loadLines(
    Id contractHistoryId,
    String historyType
  ) {
    List<ContractProduct__c> products = [
      SELECT
        Id,
        Product__c,
        Product__r.Name,
        Product__r.UnitName__c,
        Product__r.BillingType__c,
        Unit__c,
        UnitPrice__c,
        Quantity__c,
        StartDate__c,
        Enddate__c,
        InvoiceSetting__c,
        BillingType__c,
        Type__c,
        Amount__c,
        PreviousContractProduct__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :contractHistoryId
      WITH SYSTEM_MODE
      ORDER BY Name ASC
    ];
    products = ChangeBillingEventUtil.filterProductsForEstimateDocument(
      historyType,
      products
    );

    List<LineDto> lines = new List<LineDto>();
    for (ContractProduct__c product : products) {
      LineDto line = new LineDto();
      line.billingType = ContractMetadataService.resolveLineBillingType(product);
      line.productName = product.Product__r == null
        ? ''
        : product.Product__r.Name;
      line.quantity = product.Quantity__c == null
        ? 0
        : AmountCalculationSettingService.roundQuantityUnitPrice(
            product.Quantity__c
          );
      line.unitPrice = product.UnitPrice__c == null
        ? 0
        : AmountCalculationSettingService.roundQuantityUnitPrice(
            product.UnitPrice__c
          );
      line.amount = resolveLineAmount(product, line.billingType);
      line.invoiceSetting = ContractMetadataService.normalizeInvoiceSettingLabel(
        product.InvoiceSetting__c
      );
      line.unit = String.isNotBlank(product.Unit__c)
        ? product.Unit__c
        : buildDisplayUnit(
            product.Product__r == null ? null : product.Product__r.UnitName__c,
            line.billingType
          );
      line.periodLabel = buildPeriodLabel(
        product.StartDate__c,
        product.Enddate__c
      );
      line.typeLabel = resolveProductTypeLabel(product.Type__c);
      lines.add(line);
    }
    return lines;
  }

  private static Decimal resolveLineAmount(
    ContractProduct__c product,
    String billingType
  ) {
    if (product.Amount__c != null) {
      return product.Amount__c;
    }
    Decimal calculatedAmount = ContractProductAmountUtil.calculateSignedAmount(
      product,
      billingType
    );
    return calculatedAmount == null ? 0 : calculatedAmount;
  }

  private static Decimal resolveLineTotal(
    ContractHistory__c history,
    List<LineDto> lines
  ) {
    if (history != null && history.DeltaAmountSum__c != null) {
      return history.DeltaAmountSum__c;
    }
    return sumLineAmounts(lines);
  }

  private static Decimal sumLineAmounts(List<LineDto> lines) {
    Decimal total = 0;
    if (lines == null) {
      return total;
    }
    for (LineDto line : lines) {
      total += line.amount == null ? 0 : line.amount;
    }
    return total;
  }

  private static String resolveDocumentTitle(ContractHistory__c history) {
    if (history == null) {
      return '見積書';
    }
    if (String.isNotBlank(history.EstimateTitleName__c)) {
      return history.EstimateTitleName__c.trim();
    }
    if (
      history.Opportunity__r != null &&
      String.isNotBlank(history.Opportunity__r.Name)
    ) {
      return history.Opportunity__r.Name.trim();
    }
    if (String.isNotBlank(history.Name)) {
      return history.Name.trim();
    }
    return '見積書';
  }

  private static String resolveAddresseeName(ContractHistory__c history) {
    if (
      history.ContractService__r != null &&
      history.ContractService__r.BiilingAcccount__r != null &&
      String.isNotBlank(
        history.ContractService__r.BiilingAcccount__r.BillingAddressee__c
      )
    ) {
      return history.ContractService__r.BiilingAcccount__r.BillingAddressee__c;
    }
    return resolveAccountName(history);
  }

  private static String resolveAccountName(ContractHistory__c history) {
    if (
      history != null &&
      history.ContractService__r != null &&
      history.ContractService__r.Account__r != null &&
      String.isNotBlank(history.ContractService__r.Account__r.Name)
    ) {
      return history.ContractService__r.Account__r.Name;
    }
    return '';
  }

  /** 仕様: Core 第0.1節 */
  private static String resolveHistoryTypeLabel(String historyType) {
    if (historyType == 'New') {
      return '新規';
    }
    if (historyType == 'Change') {
      return '追加変更';
    }
    if (historyType == 'Renew') {
      return '更新';
    }
    if (historyType == 'Cancel') {
      return '解約';
    }
    return historyType;
  }

  /** 仕様: Core 第0.1節 */
  private static String resolveProductTypeLabel(String productType) {
    if (productType == 'New') {
      return '追加';
    }
    if (productType == 'Renew') {
      return '更新';
    }
    if (productType == 'Original') {
      return '変更前';
    }
    if (productType == 'Remake' || productType == 'derivative') {
      return '変更後';
    }
    return productType;
  }

  private static String buildDisplayUnit(String unitName, String billingType) {
    // マスタ単位をそのまま表示する（継続課金でも「・月」は付与しない）。
    if (String.isBlank(unitName)) {
      return '式';
    }
    return unitName;
  }

  private static String buildPeriodLabel(Date startDate, Date endDate) {
    if (startDate == null && endDate == null) {
      return '';
    }
    if (startDate != null && endDate != null) {
      return formatDisplayDate(startDate) + ' 〜 ' + formatDisplayDate(endDate);
    }
    if (startDate != null) {
      return formatDisplayDate(startDate) + ' 〜';
    }
    return '〜 ' + formatDisplayDate(endDate);
  }

  private static String buildTermLabel(Date startDate, Date endDate) {
    return buildPeriodLabel(startDate, endDate);
  }

  public static String formatDisplayDate(Date value) {
    if (value == null) {
      return '';
    }
    return String.valueOf(value.year()) +
      '年' +
      String.valueOf(value.month()).leftPad(2, '0') +
      '月' +
      String.valueOf(value.day()).leftPad(2, '0') +
      '日';
  }

  public static String formatFileDate(Date value) {
    Date targetDate = value == null
      ? InvoiceTransactionStatusService.organizationToday()
      : value;
    return String.valueOf(targetDate.year()) +
      '_' +
      String.valueOf(targetDate.month()).leftPad(2, '0') +
      '_' +
      String.valueOf(targetDate.day()).leftPad(2, '0');
  }

  private static String formatCompactFileDate(Date value) {
    Date targetDate = value == null
      ? InvoiceTransactionStatusService.organizationToday()
      : value;
    return String.valueOf(targetDate.year()) +
      String.valueOf(targetDate.month()).leftPad(2, '0') +
      String.valueOf(targetDate.day()).leftPad(2, '0');
  }

  public static String sanitizeFileName(String value) {
    if (String.isBlank(value)) {
      return '見積書';
    }
    String sanitized = value.trim();
    sanitized = sanitized.replaceAll('[\\\\/:*?"<>|]', '_');
    sanitized = sanitized.replaceAll('\\s+', '_');
    return String.isBlank(sanitized) ? '見積書' : sanitized;
  }

  /**
   * カテゴリ別グループを組み立て、税込を付与する。
   * 税の正はウィザード／請求ヘッダと同じく「PDF 掲載明細の税抜合計 × 税率を1回切り捨て」。
   * グループ／カテゴリ税込は金額計算設定の帳票グループ税込に従う。
   */
  @TestVisible
  private static void buildGroupedPdfContext(DocumentContext context) {
    context.documentText = buildEstimateDocumentText(context.history);
    context.estimateNumber = generateEstimateNumber(context.history);
    buildDisplayValues(context);

    context.digitalGroups = new List<GroupDto>();
    context.consultingGroups = new List<GroupDto>();
    context.trainingGroups = new List<GroupDto>();
    context.otherGroups = new List<GroupDto>();
    context.digitalTotalIncTax = 0;
    context.consultingTotalIncTax = 0;
    context.trainingTotalIncTax = 0;
    context.otherTotalIncTax = 0;
    context.totalAmount = 0;

    List<ContractProduct__c> products = queryProductsForGroupedPdf(
      context.history.Id,
      context.history.Type__c
    );
    Map<Id, String> categoryByProductId = loadProductCategories(products);

    for (ContractProduct__c product : products) {
      GroupedLineDto item = toGroupedLine(product);
      String category = categoryByProductId.get(product.Product__c);
      String groupingName = resolveGroupingProductName(product);

      if (category == '研修（エンパワー）') {
        addToGroup(context.trainingGroups, groupingName, item);
      } else if (category != null && category.left(4) == 'SaaS') {
        addToGroup(context.digitalGroups, groupingName, item);
      } else if (category == 'コンサル') {
        addToGroup(context.consultingGroups, groupingName, item);
      } else {
        addToGroup(context.otherGroups, groupingName, item);
      }
    }

    List<GroupDto> allGroups = new List<GroupDto>();
    allGroups.addAll(context.digitalGroups);
    allGroups.addAll(context.consultingGroups);
    allGroups.addAll(context.trainingGroups);
    allGroups.addAll(context.otherGroups);

    Decimal grandExcl = sumGroupExcl(allGroups);
    Decimal grandTax = TaxCalculationUtil.calculateTaxAmount(
      grandExcl,
      context.taxPercent
    );
    allocateGrandTaxToGroups(allGroups, grandExcl, grandTax);

    context.digitalTotalIncTax = sumGroupTotalIncTax(context.digitalGroups);
    context.consultingTotalIncTax = sumGroupTotalIncTax(
      context.consultingGroups
    );
    context.trainingTotalIncTax = sumGroupTotalIncTax(context.trainingGroups);
    context.otherTotalIncTax = sumGroupTotalIncTax(context.otherGroups);
    context.totalAmount = grandExcl + grandTax;
    // PDF 御見積と loadContext 側の税込正本を揃える（掲載明細ベース）。
    context.lineTotal = grandExcl;
    context.taxAmount = grandTax;
    context.lineTotalInclTax = context.totalAmount;
  }

  private static Decimal sumGroupExcl(List<GroupDto> groups) {
    Decimal total = 0;
    if (groups == null) {
      return total;
    }
    for (GroupDto groupDto : groups) {
      if (groupDto != null && groupDto.groupTotal != null) {
        total += groupDto.groupTotal;
      }
    }
    return total;
  }

  private static Decimal sumGroupTotalIncTax(List<GroupDto> groups) {
    Decimal total = 0;
    if (groups == null) {
      return total;
    }
    for (GroupDto groupDto : groups) {
      if (groupDto != null && groupDto.totalAmountIncTax != null) {
        total += groupDto.totalAmountIncTax;
      }
    }
    return total;
  }

  /**
   * 総額税を帳票グループ税込設定で按分する。
   * 仕様: Core 第4.8節・第11.9節。税抜比。非最終は0方向切捨て。最後のグループで端数を吸収する。
   */
  @TestVisible
  private static void allocateGrandTaxToGroups(
    List<GroupDto> groups,
    Decimal grandExcl,
    Decimal grandTax
  ) {
    AmountCalculationSettingService.requireOrgDefault();
    if (groups == null || groups.isEmpty()) {
      return;
    }
    Decimal taxTotal = grandTax == null ? 0 : grandTax;
    Decimal exclTotal = grandExcl == null ? 0 : grandExcl;
    if (exclTotal == 0 || taxTotal == 0) {
      for (GroupDto groupDto : groups) {
        if (groupDto == null) {
          continue;
        }
        groupDto.taxAmount = 0;
        groupDto.totalAmountIncTax = groupDto.groupTotal == null
          ? 0
          : groupDto.groupTotal;
      }
      return;
    }

    Decimal remainingTax = taxTotal;
    for (Integer i = 0; i < groups.size(); i++) {
      GroupDto groupDto = groups[i];
      if (groupDto == null) {
        continue;
      }
      Decimal groupExcl = groupDto.groupTotal == null ? 0 : groupDto.groupTotal;
      Decimal groupTax;
      if (i == groups.size() - 1) {
        groupTax = remainingTax;
      } else {
        groupTax = (taxTotal *
          groupExcl /
          exclTotal)
          .setScale(0, RoundingMode.DOWN);
        remainingTax -= groupTax;
      }
      groupDto.taxAmount = groupTax;
      groupDto.totalAmountIncTax = groupExcl + groupTax;
    }
  }

  private static List<ContractProduct__c> queryProductsForGroupedPdf(
    Id contractHistoryId,
    String historyType
  ) {
    List<ContractProduct__c> products = [
      SELECT
        Id,
        Product__c,
        Product__r.Name,
        Product__r.UnitName__c,
        Product__r.BillingType__c,
        Description__c,
        Unit__c,
        UnitPrice__c,
        Quantity__c,
        StartDate__c,
        Enddate__c,
        InvoiceSetting__c,
        BillingType__c,
        Type__c,
        Amount__c,
        PreviousContractProduct__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :contractHistoryId
      WITH SYSTEM_MODE
      ORDER BY StartDate__c ASC NULLS LAST, Name ASC
    ];
    return ChangeBillingEventUtil.filterProductsForEstimateDocument(
      historyType,
      products
    );
  }

  private static Map<Id, String> loadProductCategories(
    List<ContractProduct__c> products
  ) {
    Map<Id, String> categoryByProductId = new Map<Id, String>();
    if (
      products == null ||
      products.isEmpty() ||
      !Schema.SObjectType.Product2.fields.getMap().containsKey('Field1__c')
    ) {
      return categoryByProductId;
    }
    Set<Id> productIds = new Set<Id>();
    for (ContractProduct__c product : products) {
      if (product.Product__c != null) {
        productIds.add(product.Product__c);
      }
    }
    if (productIds.isEmpty()) {
      return categoryByProductId;
    }
    for (
      SObject product : Database.query(
        'SELECT Id, Field1__c FROM Product2 WHERE Id IN :productIds WITH SYSTEM_MODE'
      )
    ) {
      categoryByProductId.put(
        (Id) product.get('Id'),
        (String) product.get('Field1__c')
      );
    }
    return categoryByProductId;
  }

  /** 仕様: Core 第4.8節、第11.9節。数量は OrgDefault。HALF_UP 直書きしない。 */
  private static GroupedLineDto toGroupedLine(ContractProduct__c product) {
    String billingType = ContractMetadataService.resolveLineBillingType(product);

    GroupedLineDto item = new GroupedLineDto();
    item.breakdown = String.isNotBlank(product.Description__c)
      ? product.Description__c
      : product.Product__r == null ? '' : product.Product__r.Name;
    item.unit = String.isNotBlank(product.Unit__c)
      ? product.Unit__c
      : buildDisplayUnit(
          product.Product__r == null ? null : product.Product__r.UnitName__c,
          billingType
        );
    item.quantity = product.Quantity__c == null
      ? 0
      : AmountCalculationSettingService.roundQuantityUnitPrice(
          product.Quantity__c
        );
    item.amount = resolveLineAmount(product, billingType);
    item.period = buildPeriodLabel(product.StartDate__c, product.Enddate__c);
    return item;
  }

  private static String resolveGroupingProductName(ContractProduct__c product) {
    if (
      product.Product__r != null && String.isNotBlank(product.Product__r.Name)
    ) {
      return product.Product__r.Name;
    }
    return itemFallbackName(product);
  }

  private static String itemFallbackName(ContractProduct__c product) {
    return String.isNotBlank(product.Description__c)
      ? product.Description__c
      : '';
  }

  private static void addToGroup(
    List<GroupDto> targetList,
    String productName,
    GroupedLineDto item
  ) {
    GroupDto foundGroup = null;
    for (GroupDto existingGroup : targetList) {
      if (existingGroup.productName == productName) {
        foundGroup = existingGroup;
        break;
      }
    }
    if (foundGroup == null) {
      foundGroup = new GroupDto(productName);
      targetList.add(foundGroup);
    }
    foundGroup.items.add(item);
    if (item.amount != null) {
      foundGroup.groupTotal += item.amount;
    }
  }

  @TestVisible
  private static EstimateDocumentTextDto buildEstimateDocumentText(
    ContractHistory__c history
  ) {
    EstimateDocumentTextDto text = new EstimateDocumentTextDto();
    ContractDocumentSetting__c orgSetting = loadDocumentOrgSetting();
    text.estimateTitle = resolveDocumentTitle(history);
    text.toCompanyName = resolveAddresseeName(history);
    text.companyName = orgDocumentText(orgSetting.CompanyName__c);
    text.postalNumber = '';
    text.addressFirstHalf = orgDocumentText(orgSetting.Address__c);
    text.addressLastHalf = '';
    text.honorificTitle = '御中';
    text.estimateSentence = '下記の通り、お見積り申し上げます。';
    text.basicTermPeriodLabel = '基本契約期間';
    text.basicTermPeriod = buildTermLabel(
      history == null ? null : history.CurrentTermStartDate__c,
      history == null ? null : history.CurrentTermEndDate__c
    );
    text.paymentTermLabel = '支払条件';
    text.paymentTermSentence = '';
    text.termFeeStartDateLabel = '取引料金開始日';
    text.termDueDateLabel = '見積有効期限';
    text.estimateDueDateSentence = history == null
      ? ''
      : formatDisplayDate(history.EstimateValidDate__c);
    text.estimateSumLabel = '御見積金額';
    text.unitSentence = '円';
    text.digitalLicenceFeeLabel = 'デジタルライセンス料';
    text.consultingFeeLabel = 'コンサルティング料';
    text.feedbackCoachingFeeLabel = 'フィードバックコーチング料';
    text.otherFeeLabel = 'その他';
    text.noteSentenceLabel = '特記事項';
    // 仕様: Core 第4.10節、第4.8節、第1.1.10節。備考空はマスタ本文で埋めない。
    text.noteSentence = resolveFallbackNoteText(history);
    text.ownerLabel = '担当：';
    // 仕様: Core 第11.3.1節・第4.8節。帳票フッターとプライバシーポリシーURLは空でなければ出す。定数で埋めない。
    text.documentFooter = orgDocumentText(orgSetting.DocumentFooter__c);
    text.privacyPolicyUrl = orgDocumentText(orgSetting.PrivacyPolicyUrl__c);
    if (
      history != null &&
      history.ContractService__r != null &&
      history.ContractService__r.TaxPercent__c != null
    ) {
      text.tax = TaxCalculationUtil.fromPercentFieldStorage(
        history.ContractService__r.TaxPercent__c
      );
    }
    return text;
  }

  /** 仕様: Core 第7.10節・第11.3.2節。キー空は発行できない。組織既定も既定印も使わない。 */
  private static ContractDocumentTemplateService.TemplateDefinition resolveIssueTemplate(
    String templateKey
  ) {
    try {
      return ContractDocumentTemplateService.resolveTemplate(
        ContractDocumentTemplateService.TYPE_ESTIMATE,
        templateKey
      );
    } catch (ContractDocumentTemplateService.DocumentTemplateException ex) {
      String message = ex.getMessage();
      if (message == ContractDocumentSettingService.MISSING_DEFAULT_DOCUMENT_MESSAGE) {
        message = ContractDocumentSettingService.withDocumentSendHeading(message);
      }
      throw new EstimateDocumentException(message);
    }
  }

  /** 仕様: Core 第4.8節、第1.1.10節。会社名・住所は発行時点の組織設定。空欄は定数で埋めない。 */
  private static String orgDocumentText(String value) {
    return String.isBlank(value) ? '' : value;
  }

  private static ContractDocumentSetting__c loadDocumentOrgSetting() {
    List<ContractDocumentSetting__c> settings = [
      SELECT
        CompanyName__c,
        Address__c,
        InvoiceRegistrationNumber__c,
        BankTransferInfo__c,
        DocumentFooter__c,
        PrivacyPolicyUrl__c
      FROM ContractDocumentSetting__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return settings.isEmpty()
      ? new ContractDocumentSetting__c()
      : settings[0];
  }

  /** 仕様: Core 第4.10節、第4.8節、第1.1.10節。備考空はマスタ本文で埋めない。 */
  private static String resolveFallbackNoteText(ContractHistory__c history) {
    if (history == null || String.isBlank(history.Note__c)) {
      return '';
    }
    return history.Note__c;
  }

  @TestVisible
  private static void buildDisplayValues(DocumentContext context) {
    ContractHistory__c history = context.history;
    EstimateDocumentTextDto setting = context.documentText;

    if (setting != null && String.isNotBlank(setting.toCompanyName)) {
      context.toCompanyNameDisplay = setting.toCompanyName;
    } else {
      context.toCompanyNameDisplay = resolveAddresseeName(history);
    }

    if (setting != null && String.isNotBlank(setting.ownerName)) {
      context.ownerNameDisplay = setting.ownerName;
    } else if (
      history != null &&
      history.Opportunity__r != null &&
      history.Opportunity__r.Owner != null &&
      String.isNotBlank(history.Opportunity__r.Owner.Name)
    ) {
      context.ownerNameDisplay = history.Opportunity__r.Owner.Name;
    } else {
      context.ownerNameDisplay = '';
    }

    if (setting != null && String.isNotBlank(setting.estimateDateSentence)) {
      context.estimateDateDisplay = setting.estimateDateSentence;
    } else {
      // 仕様: Core 第4.8節。見積日・発行日は保存値だけ。両方空なら日付行は空。今日で埋めない。
      Date estimateDate = null;
      if (history != null) {
        if (history.EstimateIssueDate__c != null) {
          estimateDate = history.EstimateIssueDate__c;
        } else if (history.EstimateDate__c != null) {
          estimateDate = history.EstimateDate__c;
        }
      }
      context.estimateDateDisplay = estimateDate == null
        ? ''
        : formatEstimateDateWithWeekday(estimateDate);
    }

    if (
      setting != null && String.isNotBlank(setting.termFeeStartDateSentence)
    ) {
      context.termFeeStartDateDisplay = setting.termFeeStartDateSentence;
    } else {
      Date earliest = getEarliestProductStartDate(
        history == null ? null : history.Id
      );
      context.termFeeStartDateDisplay = earliest == null
        ? ''
        : formatEstimateDateWithWeekday(earliest);
    }
  }

  private static Date getEarliestProductStartDate(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return null;
    }
    List<ContractProduct__c> products = [
      SELECT StartDate__c
      FROM ContractProduct__c
      WHERE ContractHistory__c = :contractHistoryId AND StartDate__c != NULL
      WITH SYSTEM_MODE
      ORDER BY StartDate__c ASC
      LIMIT 1
    ];
    return products.isEmpty() ? null : products[0].StartDate__c;
  }

  @TestVisible
  private static String formatEstimateDateWithWeekday(Date value) {
    if (value == null) {
      return '';
    }
    Date knownSunday = Date.newInstance(1900, 1, 7);
    Integer daysBetween = knownSunday.daysBetween(value);
    Integer dayIdx = Math.mod(daysBetween, 7);
    if (dayIdx < 0) {
      dayIdx += 7;
    }
    List<String> daysJP = new List<String>{
      '日',
      '月',
      '火',
      '水',
      '木',
      '金',
      '土'
    };
    Datetime dt = Datetime.newInstance(
      value.year(),
      value.month(),
      value.day()
    );
    return dt.format('yyyy/M/d') + '(' + daysJP[dayIdx] + ')';
  }

  @TestVisible
  private static String generateEstimateNumber(ContractHistory__c history) {
    if (history != null && String.isNotBlank(history.Name)) {
      return history.Name.trim();
    }
    String datePart = Date.today().format().replace('/', '');
    return 'HZ-' + datePart + '-001';
  }
}
