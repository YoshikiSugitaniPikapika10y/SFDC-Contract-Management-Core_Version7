/**
 * 見積一覧（横断）と複数選択受注。
 * 受注1件の正は OrderCreateController.confirmOrder。ここは一覧と順次実行だけ。
 */
public without sharing class EstimateOrderBoardController {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final Integer LIST_LIMIT = 500;
  private static final Integer SELECT_ALL_CONFIRM_THRESHOLD = 100;

  public class BoardContextDto {
    @AuraEnabled
    public Boolean canOrder;
    @AuraEnabled
    public Integer selectAllConfirmThreshold;
    @AuraEnabled
    public Integer listLimit;
  }

  public class EstimateRowDto {
    @AuraEnabled
    public Id contractHistoryId;
    @AuraEnabled
    public String historyName;
    @AuraEnabled
    public String historyType;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String contractServiceName;
    @AuraEnabled
    public Date termStartDate;
    @AuraEnabled
    public Date termEndDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Date applicationDate;
    @AuraEnabled
    public Decimal version;
  }

  @AuraEnabled
  public static BoardContextDto getBoardContext() {
    BoardContextDto context = new BoardContextDto();
    context.canOrder = ContractPermissionUtil.has(ContractPermissionUtil.ORDER);
    context.selectAllConfirmThreshold = SELECT_ALL_CONFIRM_THRESHOLD;
    context.listLimit = LIST_LIMIT;
    return context;
  }

  @AuraEnabled
  public static List<EstimateRowDto> listEstimates(
    String historyType,
    Date termStartFrom,
    Date termStartTo,
    String searchText
  ) {
    String typeFilter = String.isBlank(historyType) ? null : historyType.trim();
    String likeSearch = buildLikeSearch(searchText);
    String soql =
      'SELECT Id, Name, Type__c, Version__c, CurrentTermStartDate__c, CurrentTermEndDate__c, ' +
      'ApplicationDate__c, DeltaAmountSum__c, ContractService__r.Name, ContractService__r.Account__r.Name ' +
      'FROM ContractHistory__c WHERE historystatus__c = :HISTORY_STATUS_ESTIMATE';
    if (typeFilter != null) {
      soql += ' AND Type__c = :typeFilter';
    }
    if (termStartFrom != null) {
      soql += ' AND CurrentTermStartDate__c >= :termStartFrom';
    }
    if (termStartTo != null) {
      soql += ' AND CurrentTermStartDate__c <= :termStartTo';
    }
    if (likeSearch != null) {
      soql +=
        ' AND (Name LIKE :likeSearch OR ContractService__r.Name LIKE :likeSearch' +
        ' OR ContractService__r.Account__r.Name LIKE :likeSearch)';
    }
    soql +=
      ' WITH SYSTEM_MODE ORDER BY CurrentTermStartDate__c ASC NULLS LAST, Name ASC LIMIT :LIST_LIMIT';
    List<ContractHistory__c> histories = Database.query(soql);

    List<EstimateRowDto> rows = new List<EstimateRowDto>();
    for (ContractHistory__c history : histories) {
      EstimateRowDto row = new EstimateRowDto();
      row.contractHistoryId = history.Id;
      row.historyName = history.Name;
      row.historyType = history.Type__c;
      row.accountName = history.ContractService__r == null ||
        history.ContractService__r.Account__r == null
        ? ''
        : history.ContractService__r.Account__r.Name;
      row.contractServiceName = history.ContractService__r == null
        ? ''
        : history.ContractService__r.Name;
      row.termStartDate = history.CurrentTermStartDate__c;
      row.termEndDate = history.CurrentTermEndDate__c;
      row.amount = history.DeltaAmountSum__c;
      row.applicationDate = history.ApplicationDate__c;
      row.version = history.Version__c;
      rows.add(row);
    }
    return rows;
  }

  private static String buildLikeSearch(String searchText) {
    if (String.isBlank(searchText)) {
      return null;
    }
    String escaped = searchText.trim().replace('%', '\\%').replace('_', '\\_');
    return '%' + escaped + '%';
  }
}
