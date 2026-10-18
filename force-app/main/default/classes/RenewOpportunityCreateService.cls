/** 更新商談の作成・名前・リンク参照・削除。受注と同じ処理で作る。 */
public without sharing class RenewOpportunityCreateService {
  public class RenewOpportunityException extends Exception {
  }

  @TestVisible
  private static final String KIND_RENEW = '更新';
  @TestVisible
  private static final String KIND_CANCEL = '解約';
  private static final Integer NAME_LIMIT = 120;
  private static final List<String> COPY_FIELD_NAMES = new List<String>{
    'CostCenter__c',
    'InternalOrderNo__c'
  };

  public static final String MISSING_RENEW_OPPORTUNITY_MESSAGE = '更新商談が作成されなかったため、受注を取り消しました。';
  public static final String MISMATCH_RENEW_OPPORTUNITY_MESSAGE = '更新商談の元契約履歴・契約サービス・取引先が一致しないため、受注を取り消しました。';

  /** 仕様: Core 第11.5節 */
  public static void assertCreatedForHistory(
    ContractHistory__c history,
    Id opportunityId
  ) {
    if (history == null || opportunityId == null) {
      throw new RenewOpportunityException(MISSING_RENEW_OPPORTUNITY_MESSAGE);
    }
    List<Opportunity> rows = [
      SELECT Id, SourceContractHistory__c, ContractService__c, AccountId
      FROM Opportunity
      WHERE Id = :opportunityId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new RenewOpportunityException(MISSING_RENEW_OPPORTUNITY_MESSAGE);
    }
    Opportunity created = rows[0];
    Id serviceAccountId = history.ContractService__r == null
      ? null
      : history.ContractService__r.Account__c;
    if (
      created.SourceContractHistory__c != history.Id ||
      created.ContractService__c != history.ContractService__c ||
      created.AccountId != serviceAccountId
    ) {
      throw new RenewOpportunityException(MISMATCH_RENEW_OPPORTUNITY_MESSAGE);
    }
  }

  /** 仕様: Core 第12.4節。同一処理でロック済み契約履歴を取り直さない。 */
  @TestVisible
  static Integer historySelectCount = 0;
  /** 仕様: Core 第12.4節。Lookup がある Source 商談は取り直さない。 */
  @TestVisible
  static Integer sourceOpportunitySelectCount = 0;

  /**
   * 仕様: Core 第5.2節、第11.5節。受注と同じ処理で更新商談を1件にし、名前を付ける。
   * 既にあれば作り直さず、名前だけ次の版と期間に直す。
   */
  public static Id ensureForOrderedHistory(Id contractHistoryId) {
    ContractHistory__c history = queryHistory(contractHistoryId);
    if (
      history == null ||
      history.historystatus__c != ContractDomainConstants.HISTORY_STATUS_ORDERED
    ) {
      throw new RenewOpportunityException(MISSING_RENEW_OPPORTUNITY_MESSAGE);
    }
    String dealName = renewalName(history);
    if (history.RenewalOpportunity__c == null) {
      return insertRenewalOpportunity(history, dealName);
    }
    SystemContextAccess.updateRecords(
      new List<SObject>{
        new Opportunity(Id = history.RenewalOpportunity__c, Name = dealName)
      }
    );
    return history.RenewalOpportunity__c;
  }

  /**
   * 解約見積を保存した商談名を、版と日付が読める解約名にする。
   * 受注済みや、すでに解約の見積の再保存では変えない。
   */
  public static void applyCancelNames(
    List<ContractHistory__c> histories,
    Map<Id, ContractHistory__c> oldMap
  ) {
    if (histories == null || histories.isEmpty()) {
      return;
    }
    List<ContractHistory__c> targets = new List<ContractHistory__c>();
    Set<Id> serviceIds = new Set<Id>();
    for (ContractHistory__c history : histories) {
      if (!isNewCancelEstimate(history, oldMap)) {
        continue;
      }
      targets.add(history);
      if (history.ContractService__c != null) {
        serviceIds.add(history.ContractService__c);
      }
    }
    if (targets.isEmpty()) {
      return;
    }
    Map<Id, ContractService__c> services = serviceIds.isEmpty()
      ? new Map<Id, ContractService__c>()
      : new Map<Id, ContractService__c>([
          SELECT Id, Account__r.Name
          FROM ContractService__c
          WHERE Id IN :serviceIds
          WITH SYSTEM_MODE
        ]);
    Map<Id, Opportunity> updates = new Map<Id, Opportunity>();
    for (ContractHistory__c history : targets) {
      ContractService__c service = services.get(history.ContractService__c);
      String accountName = service == null || service.Account__r == null
        ? null
        : service.Account__r.Name;
      Date mark = history.EffectiveDate__c != null
        ? history.EffectiveDate__c
        : history.CurrentTermEndDate__c;
      updates.put(
        history.Opportunity__c,
        new Opportunity(
          Id = history.Opportunity__c,
          Name = buildDealName(
            KIND_CANCEL,
            accountName,
            history.Version__c,
            mark,
            null
          )
        )
      );
    }
    SystemContextAccess.updateRecords(updates.values());
  }

  /** 商談名。版と期間で Version3 と Version4、更新と解約を並べて読める。 */
  @TestVisible
  static String buildDealName(
    String kindLabel,
    String accountName,
    Decimal version,
    Date startDate,
    Date endDate
  ) {
    String accountPart = String.isBlank(accountName) ? '' : accountName.trim();
    List<String> parts = new List<String>();
    parts.add('【' + kindLabel + '】' + accountPart);
    if (version != null && version > 0) {
      parts.add('Version' + String.valueOf(version.intValue()));
    }
    if (startDate != null && endDate != null) {
      parts.add(formatDate(startDate) + '〜' + formatDate(endDate));
    } else if (startDate != null) {
      parts.add(formatDate(startDate));
    } else if (endDate != null) {
      parts.add(formatDate(endDate));
    }
    String dealName = String.join(parts, '｜');
    return dealName.length() <= NAME_LIMIT
      ? dealName
      : dealName.substring(0, NAME_LIMIT);
  }

  /**
   * 仕様: Core 第5.2節、第11.5節。元契約履歴から作成した更新商談 Id を返す。
   */
  public static Id findBySourceHistory(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return null;
    }
    sourceOpportunitySelectCount++;
    List<Opportunity> rows = [
      SELECT Id
      FROM Opportunity
      WHERE SourceContractHistory__c = :contractHistoryId
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].Id;
  }

  /** 仕様: Core 第4.9節、第5.3節、第5.6節、第11.5節 */
  public static void deleteBySourceHistory(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return;
    }
    if (!ContractDocumentSettingService.requireRenewOpportunitySwitch()) {
      return;
    }
    historySelectCount++;
    List<ContractHistory__c> sources = [
      SELECT Id, RenewalOpportunity__c, RenewOpportunityRequestCount__c
      FROM ContractHistory__c
      WHERE Id = :contractHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (sources.isEmpty()) {
      return;
    }
    deleteByLockedHistory(sources[0]);
  }

  /**
   * 仕様: Core 第4.9節、第5.3節、第5.6節、第11.5節、第12.4節。
   * ロック済み契約履歴の Lookup とカウントは取り直さない。
   */
  public static void deleteByLockedHistory(ContractHistory__c locked) {
    if (locked == null || locked.Id == null) {
      return;
    }
    if (!ContractDocumentSettingService.requireRenewOpportunitySwitch()) {
      return;
    }
    ContractHistory__c source = new ContractHistory__c(Id = locked.Id);
    Decimal currentCount = locked.RenewOpportunityRequestCount__c;
    if (currentCount != null && currentCount > 0) {
      source.RenewOpportunityRequestCount__c = currentCount - 1;
    }
    source.RenewalOpportunity__c = null;

    Id opportunityId = locked.RenewalOpportunity__c;
    if (opportunityId == null) {
      opportunityId = findBySourceHistory(locked.Id);
    }
    try {
      if (opportunityId != null) {
        List<ContractHistory__c> archivedLinked = [
          SELECT Id
          FROM ContractHistory__c
          WHERE
            Opportunity__c = :opportunityId
            AND historystatus__c = :ContractDomainConstants.HISTORY_STATUS_ARCHIVE
          WITH SYSTEM_MODE
        ];
        if (!archivedLinked.isEmpty()) {
          for (ContractHistory__c archived : archivedLinked) {
            archived.Opportunity__c = null;
          }
          SystemContextAccess.updateRecords(archivedLinked);
        }
      }
      SystemContextAccess.updateRecords(new List<SObject>{ source });
      if (opportunityId != null) {
        SystemContextAccess.deleteRecords(
          new List<SObject>{ new Opportunity(Id = opportunityId) }
        );
      }
    } catch (Exception ex) {
      throw new RenewOpportunityException(
        '更新商談の削除に失敗しました。' + dmlDetailSuffix(ex)
      );
    }
  }

  private static Id insertRenewalOpportunity(
    ContractHistory__c history,
    String dealName
  ) {
    Opportunity created = new Opportunity(
      Name = dealName,
      AccountId = history.ContractService__r.Account__c,
      ContractService__c = history.ContractService__c,
      SourceContractHistory__c = history.Id,
      StageName = resolveOpenStageName(),
      CloseDate = history.CurrentTermEndDate__c == null
        ? Date.today().addMonths(1)
        : history.CurrentTermEndDate__c,
      OwnerId = UserInfo.getUserId()
    );
    Map<String, Schema.SObjectField> opportunityFields = Schema.SObjectType.Opportunity.fields.getMap();
    if (
      history.Opportunity__c != null &&
      opportunityFields.containsKey('previousopportunity__c')
    ) {
      created.put('PreviousOpportunity__c', history.Opportunity__c);
    }
    copyCarryFields(history, created, opportunityFields);
    SystemContextAccess.insertRecords(new List<SObject>{ created });
    SystemContextAccess.updateRecords(
      new List<SObject>{
        new ContractHistory__c(
          Id = history.Id,
          RenewalOpportunity__c = created.Id
        )
      }
    );
    return created.Id;
  }

  private static String renewalName(ContractHistory__c history) {
    Decimal nextVersion = history.Version__c == null
      ? 1
      : history.Version__c + 1;
    Date startDate = history.CurrentTermEndDate__c == null
      ? null
      : history.CurrentTermEndDate__c.addDays(1);
    Date endDate = startDate == null
      ? null
      : MonthlyBillingPeriodUtil.endDateForMonthlyCycles(
          startDate,
          ContractDocumentSettingService.requireDefaultCycles()
        );
    String accountName = history.ContractService__r == null ||
      history.ContractService__r.Account__r == null
      ? null
      : history.ContractService__r.Account__r.Name;
    return buildDealName(
      KIND_RENEW,
      accountName,
      nextVersion,
      startDate,
      endDate
    );
  }

  private static ContractHistory__c queryHistory(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return null;
    }
    List<String> fields = new List<String>{
      'Id',
      'Type__c',
      'Version__c',
      'historystatus__c',
      'Opportunity__c',
      'RenewalOpportunity__c',
      'ContractService__c',
      'CurrentTermEndDate__c',
      'ContractService__r.Account__c',
      'ContractService__r.Account__r.Name'
    };
    Map<String, Schema.SObjectField> historyFields = Schema.SObjectType.ContractHistory__c.fields.getMap();
    for (String apiName : COPY_FIELD_NAMES) {
      if (historyFields.containsKey(apiName.toLowerCase())) {
        fields.add(apiName);
      }
    }
    List<ContractHistory__c> rows = Database.query(
      'SELECT ' +
        String.join(fields, ',') +
        ' FROM ContractHistory__c WHERE Id = :contractHistoryId WITH SYSTEM_MODE LIMIT 1'
    );
    return rows.isEmpty() ? null : rows[0];
  }

  private static void copyCarryFields(
    ContractHistory__c history,
    Opportunity opportunity,
    Map<String, Schema.SObjectField> opportunityFields
  ) {
    Map<String, Schema.SObjectField> historyFields = Schema.SObjectType.ContractHistory__c.fields.getMap();
    for (String apiName : COPY_FIELD_NAMES) {
      String key = apiName.toLowerCase();
      if (!historyFields.containsKey(key) || !opportunityFields.containsKey(key)) {
        continue;
      }
      opportunity.put(apiName, history.get(apiName));
    }
  }

  private static Boolean isNewCancelEstimate(
    ContractHistory__c history,
    Map<Id, ContractHistory__c> oldMap
  ) {
    if (
      history == null ||
      history.Opportunity__c == null ||
      history.Type__c != ContractDomainConstants.HISTORY_TYPE_CANCEL ||
      history.historystatus__c != ContractDomainConstants.HISTORY_STATUS_ESTIMATE
    ) {
      return false;
    }
    if (oldMap == null) {
      return true;
    }
    ContractHistory__c previous = oldMap.get(history.Id);
    return previous == null ||
      previous.Type__c != ContractDomainConstants.HISTORY_TYPE_CANCEL;
  }

  private static String resolveOpenStageName() {
    List<OpportunityStage> stages = [
      SELECT ApiName
      FROM OpportunityStage
      WHERE IsActive = TRUE AND IsClosed = FALSE
      WITH SYSTEM_MODE
      ORDER BY SortOrder ASC
      LIMIT 1
    ];
    if (!stages.isEmpty() && String.isNotBlank(stages[0].ApiName)) {
      return stages[0].ApiName;
    }
    for (
      Schema.PicklistEntry entry : Opportunity.StageName.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive() && String.isNotBlank(entry.getValue())) {
        return entry.getValue();
      }
    }
    return 'Prospecting';
  }

  private static String formatDate(Date value) {
    return String.valueOf(value.year()) +
      '/' +
      String.valueOf(value.month()).leftPad(2, '0') +
      '/' +
      String.valueOf(value.day()).leftPad(2, '0');
  }

  private static String dmlDetailSuffix(Exception ex) {
    if (ex instanceof DmlException) {
      DmlException dml = (DmlException) ex;
      if (dml.getNumDml() > 0 && String.isNotBlank(dml.getDmlMessage(0))) {
        return ' ' + dml.getDmlMessage(0);
      }
    }
    return String.isBlank(ex.getMessage()) ? '' : ' ' + ex.getMessage();
  }
}
