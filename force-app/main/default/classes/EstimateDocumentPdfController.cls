/**
 * 見積書 Visualforce（EstimateDocumentPdf）用コントローラ。
 * 商談の EstimatePdfController と同じレイアウト向けに、
 * EstimateDocumentService.loadContext からグループ化済み表示値を供給する。
 */
public with sharing class EstimateDocumentPdfController {
  public EstimateSetting__c estimateSetting { get; private set; }
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

  public EstimateDocumentPdfController() {
    Id recordId = parseRecordId();
    if (recordId == null) {
      initEmpty();
      return;
    }
    try {
      bindContext(EstimateDocumentService.loadContext(recordId));
    } catch (EstimateDocumentService.EstimateDocumentException ex) {
      initEmpty();
      ApexPages.addMessage(
        new ApexPages.Message(ApexPages.Severity.ERROR, ex.getMessage())
      );
    }
  }

  public PageReference issuePdf() {
    Id recordId = parseRecordId();
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
        ContractPermissionUtil.ISSUE_ESTIMATE_DOCUMENT
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
      EstimateDocumentService.issueEstimateDocument(recordId);
      PageReference pdfPage = Page.EstimateDocumentPdf;
      pdfPage.getParameters().put('id', recordId);
      pdfPage.setRedirect(true);
      return pdfPage;
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

    estimateSetting = context.estimateSetting;
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
  }

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
            : sourceItem.quantity.setScale(2, RoundingMode.HALF_UP);
          itemView.amount = sourceItem.amount == null
            ? 0
            : sourceItem.amount.setScale(0, RoundingMode.HALF_UP);
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
    estimateSetting = null;
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
