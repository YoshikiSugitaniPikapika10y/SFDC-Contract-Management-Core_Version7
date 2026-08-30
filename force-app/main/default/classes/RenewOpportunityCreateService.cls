/** 更新商談と契約履歴のリンク参照・削除を提供する。作成ロジックは顧客専用 Flow。 */
public without sharing class RenewOpportunityCreateService {
  public class RenewOpportunityException extends Exception {
  }

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

  /**
   * 仕様: Core 第5.2節、第11.5節。元契約履歴から作成した更新商談 Id を返す。
   */
  public static Id findBySourceHistory(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return null;
    }
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
    ContractHistory__c source = sources[0];
    Decimal currentCount = source.RenewOpportunityRequestCount__c;
    if (currentCount != null && currentCount > 0) {
      source.RenewOpportunityRequestCount__c = currentCount - 1;
    }
    source.RenewalOpportunity__c = null;

    Id opportunityId = findBySourceHistory(contractHistoryId);
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
