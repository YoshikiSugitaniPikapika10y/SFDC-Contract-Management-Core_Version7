/**
 * 見積書 Visualforce（EstimateDocumentPdf）用コントローラ。
 * 商談の EstimatePdfController と同じレイアウト向けに、
 * EstimateDocumentService.loadContext からグループ化済み表示値を供給する。
 */
public with sharing class EstimateDocumentPdfController {
  public EstimateDocumentService.EstimateDocumentTextDto documentText {
    get;
    private set;
  }
  public String toCompanyNameDisplay { get; private set; }
  public String ownerNameDisplay { get; private set; }
  public String estimateDateDisplay { get; private set; }
  public String termFeeStartDateDisplay { get; private set; }
  public String estimateNumber { get; private set; }
  public List<GroupView> digitalGroups { get; private set; }
  public List<GroupView> consultingGroups { get; private set; }
  public List<GroupView> trainingGroups { get; private set; }
  public List<GroupView> otherGroups { get; private set; }
  public Decimal digitalTotalIncTax { get; private set; }
  public Decimal consultingTotalIncTax { get; private set; }
  public Decimal trainingTotalIncTax { get; private set; }
  public Decimal otherTotalIncTax { get; private set; }
  public Decimal totalAmount { get; private set; }
  public Boolean hasContext { get; private set; }
  public String companyBlockedReason { get; private set; }
  public String sendModeBlockedReason { get; private set; }

  /** 仕様: Core 第4.8節、第4.10節、第11.3.1節、第1.1.10節、共通基盤 第1.4節・第3.3節・第10.4節。使わない／必須会社情報空／04なしなら発行を出さない。 */
  public Boolean canIssuePdf {
    get {
      return hasContext == true &&
        String.isBlank(companyBlockedReason) &&
        String.isBlank(sendModeBlockedReason) &&
        ContractPermissionUtil.has(ContractPermissionUtil.ISSUE_ESTIMATE);
    }
  }
  public String selectedTemplateKey { get; set; }
  public List<SelectOption> templateOptions { get; private set; }
  public Boolean issueSucceeded { get; private set; }
  public Id issuedContentDocumentId { get; private set; }
  public Boolean showSendThisFile { get; private set; }
  public String filesPreviewUrl { get; private set; }
  public Id historyId { get; private set; }

  public class GroupView {
    public String productName { get; set; }
    public List<LineItemView> items { get; set; }
    public Decimal groupTotal { get; set; }
    public Decimal taxAmount { get; set; }
    public Decimal totalAmountIncTax { get; set; }
  }

  public class LineItemView {
    public String breakdown { get; set; }
    public String unit { get; set; }
    public Decimal quantity { get; set; }
    public Decimal amount { get; set; }
    public String period { get; set; }
  }

  public String issueFileName { get; private set; }
  private ContractHistory__c issueHistory;

  public EstimateDocumentPdfController() {
    try {
      initializeTemplateOptions();
    } catch (
      ContractDocumentTemplateService.DocumentTemplateException ex
    ) {
      initEmpty();
      ApexPages.addMessage(
        new ApexPages.Message(ApexPages.Severity.ERROR, ex.getMessage())
      );
      return;
    }
    Id recordId = parseRecordId();
    historyId = recordId;
    issueSucceeded = false;
    showSendThisFile = false;
    if (recordId == null) {
      initEmpty();
      return;
    }
    try {
      bindContext(EstimateDocumentService.loadContext(recordId));
      applyCompanyFieldGate();
      applySendModeGate();
    } catch (EstimateDocumentService.EstimateDocumentException ex) {
      initEmpty();
      ApexPages.addMessage(
        new ApexPages.Message(ApexPages.Severity.ERROR, ex.getMessage())
      );
    }
  }

  public PageReference issuePdf() {
    Id recordId = parseRecordId();
    historyId = recordId;
    if (recordId == null) {
      ApexPages.addMessage(
        new ApexPages.Message(
          ApexPages.Severity.ERROR,
          '契約履歴IDが指定されていません。'
        )
      );
      return null;
    }

    if (
      !ContractPermissionUtil.has(
        ContractPermissionUtil.ISSUE_ESTIMATE
      )
    ) {
      ApexPages.addMessage(
        new ApexPages.Message(
          ApexPages.Severity.ERROR,
          '見積書発行を実行する権限がありません。'
        )
      );
      return null;
    }

    try {
      EstimateDocumentService.IssueResult issueResult = EstimateDocumentService.issueEstimateDocument(
        recordId,
        selectedTemplateKey
      );
      issuedContentDocumentId = issueResult.contentDocumentId;
      issueSucceeded = true;
      filesPreviewUrl =
        '/lightning/r/ContentDocument/' +
        String.valueOf(issuedContentDocumentId) +
        '/view';
      showSendThisFile =
        ContractDocumentSettingService.requireSendMode('Estimate') ==
        ContractDocumentSettingService.MODE_PDF_AND_EMAIL &&
        ContractPermissionUtil.has(ContractPermissionUtil.SEND_ESTIMATE);
      ApexPages.addMessage(
        new ApexPages.Message(
          ApexPages.Severity.CONFIRM,
          '見積書を発行しました。'
        )
      );
      return null;
    } catch (Exception ex) {
      ApexPages.addMessage(
        new ApexPages.Message(ApexPages.Severity.ERROR, ex.getMessage())
      );
      return null;
    }
  }

  private void bindContext(EstimateDocumentService.DocumentContext context) {
    hasContext = context != null;
    if (context == null) {
      initEmpty();
      return;
    }

    documentText = context.documentText;
    toCompanyNameDisplay = context.toCompanyNameDisplay;
    ownerNameDisplay = context.ownerNameDisplay;
    estimateDateDisplay = context.estimateDateDisplay;
    termFeeStartDateDisplay = context.termFeeStartDateDisplay;
    estimateNumber = context.estimateNumber;
    digitalGroups = toGroupViews(context.digitalGroups);
    consultingGroups = toGroupViews(context.consultingGroups);
    trainingGroups = toGroupViews(context.trainingGroups);
    otherGroups = toGroupViews(context.otherGroups);
    digitalTotalIncTax = context.digitalTotalIncTax;
    consultingTotalIncTax = context.consultingTotalIncTax;
    trainingTotalIncTax = context.trainingTotalIncTax;
    otherTotalIncTax = context.otherTotalIncTax;
    totalAmount = context.totalAmount;
    issueHistory = context.history;
    refreshIssueFileName();
  }

  /** 仕様: Core 第4.8節、第7.10節。発行するときにファイル名を見せる。この画面では直さない。 */
  public PageReference refreshIssueFileName() {
    issueFileName = '';
    if (issueHistory == null || String.isBlank(selectedTemplateKey)) {
      return null;
    }
    try {
      ContractDocumentTemplateService.TemplateDefinition template =
        ContractDocumentTemplateService.resolveTemplate(
          ContractDocumentTemplateService.TYPE_ESTIMATE,
          selectedTemplateKey
        );
      issueFileName = EstimateDocumentService.buildFileName(
        issueHistory,
        issueHistory.EstimateIssueDate__c,
        template
      );
    } catch (Exception ex) {
      issueFileName = '';
    }
    return null;
  }

  /** 仕様: Core 第4.8節、第11.9節。数量・金額は OrgDefault。HALF_UP 直書きしない。 */
  private List<GroupView> toGroupViews(
    List<EstimateDocumentService.GroupDto> sourceGroups
  ) {
    List<GroupView> views = new List<GroupView>();
    if (sourceGroups == null) {
      return views;
    }
    for (EstimateDocumentService.GroupDto sourceGroup : sourceGroups) {
      GroupView view = new GroupView();
      view.productName = sourceGroup.productName;
      view.groupTotal = sourceGroup.groupTotal;
      view.taxAmount = sourceGroup.taxAmount;
      view.totalAmountIncTax = sourceGroup.totalAmountIncTax;
      view.items = new List<LineItemView>();
      if (sourceGroup.items != null) {
        for (
          EstimateDocumentService.GroupedLineDto sourceItem : sourceGroup.items
        ) {
          LineItemView itemView = new LineItemView();
          itemView.breakdown = sourceItem.breakdown;
          itemView.unit = sourceItem.unit;
          itemView.quantity = sourceItem.quantity == null
            ? 0
            : AmountCalculationSettingService.roundQuantityUnitPrice(
                sourceItem.quantity
              );
          itemView.amount = sourceItem.amount == null
            ? 0
            : AmountCalculationSettingService.roundAmount(sourceItem.amount);
          itemView.period = sourceItem.period;
          view.items.add(itemView);
        }
      }
      views.add(view);
    }
    return views;
  }

  private void initEmpty() {
    hasContext = false;
    documentText = null;
    toCompanyNameDisplay = '';
    ownerNameDisplay = '';
    estimateDateDisplay = '';
    termFeeStartDateDisplay = '';
    estimateNumber = '';
    digitalGroups = new List<GroupView>();
    consultingGroups = new List<GroupView>();
    trainingGroups = new List<GroupView>();
    otherGroups = new List<GroupView>();
    digitalTotalIncTax = 0;
    consultingTotalIncTax = 0;
    trainingTotalIncTax = 0;
    otherTotalIncTax = 0;
    totalAmount = 0;
    issueSucceeded = false;
    showSendThisFile = false;
    issuedContentDocumentId = null;
    filesPreviewUrl = '';
    issueFileName = '';
    issueHistory = null;
    companyBlockedReason = '';
    sendModeBlockedReason = '';
  }

  /** 仕様: Core 第4.8節、第11.3.1節、第1.1.10節。必須会社情報が空なら発行を止める。 */
  private void applyCompanyFieldGate() {
    companyBlockedReason = '';
    if (hasContext != true) {
      return;
    }
    try {
      ContractDocumentSettingService.assertRequiredCompanyFields();
    } catch (ContractDocumentSettingService.SettingException ex) {
      companyBlockedReason = ContractDocumentSettingService.withDocumentSendHeading(
        ex.getMessage()
      );
      ApexPages.addMessage(
        new ApexPages.Message(ApexPages.Severity.ERROR, companyBlockedReason)
      );
    }
  }

  /** 仕様: Core 第4.8節、第4.10節、第1.1.10節。使わないなら発行しない。 */
  private void applySendModeGate() {
    sendModeBlockedReason = '';
    if (hasContext != true) {
      return;
    }
    try {
      if (
        ContractDocumentSettingService.requireSendMode('Estimate') ==
        ContractDocumentSettingService.MODE_UNUSED
      ) {
        sendModeBlockedReason = '見積書設定が使わないのため、発行も送付もできません。';
        ApexPages.addMessage(
          new ApexPages.Message(
            ApexPages.Severity.ERROR,
            sendModeBlockedReason
          )
        );
      }
    } catch (ContractDocumentSettingService.SettingException ex) {
      sendModeBlockedReason = ex.getMessage();
      ApexPages.addMessage(
        new ApexPages.Message(ApexPages.Severity.ERROR, ex.getMessage())
      );
    }
  }

  private void initializeTemplateOptions() {
    templateOptions = new List<SelectOption>();
    List<ContractDocumentTemplateService.TemplateDefinition> templates = ContractDocumentTemplateService.getActiveTemplates(
      ContractDocumentTemplateService.TYPE_ESTIMATE
    );
    // 仕様: Core 第4.8節、第11.3.2節。有効な既定がちょうど1つなら最初に選ぶ。
    selectedTemplateKey = ContractDocumentTemplateService.initialSelectionKey(
      ContractDocumentTemplateService.TYPE_ESTIMATE
    );
    for (
      ContractDocumentTemplateService.TemplateDefinition template : templates
    ) {
      templateOptions.add(
        new SelectOption(template.templateKey, template.label)
      );
    }
  }

  private Id parseRecordId() {
    String rawId = ApexPages.currentPage().getParameters().get('id');
    if (String.isBlank(rawId)) {
      return null;
    }
    try {
      return (Id) rawId;
    } catch (Exception ex) {
      return null;
    }
  }
}
