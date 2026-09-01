/**
 * Estimate・Ordered の商談空欄と、Change・Renew・Cancel の取引先一致を全保存経路で見る。
 */
public without sharing class ContractHistoryOpportunityGuard {
  public static final String REQUIRED_MESSAGE = '見積・受注済みの契約履歴は商談を空にできません。';
  public static final String ACCOUNT_MISMATCH_MESSAGE = '契約サービスの取引先と商談の取引先が一致しません。';

  private static Map<Id, Id> opportunityAccountById = new Map<Id, Id>();
  private static Map<Id, Id> serviceAccountById = new Map<Id, Id>();

  /** 仕様: Core 第3.2節 */
  public static void assertRequired(List<ContractHistory__c> histories) {
    if (histories == null || histories.isEmpty()) {
      return;
    }
    for (ContractHistory__c history : histories) {
      if (history == null) {
        continue;
      }
      String status = history.historystatus__c;
      if (
        status != ContractDomainConstants.HISTORY_STATUS_ESTIMATE &&
        status != ContractDomainConstants.HISTORY_STATUS_ORDERED
      ) {
        continue;
      }
      if (history.Opportunity__c == null) {
        history.addError(REQUIRED_MESSAGE);
      }
    }
    assertAccountMatches(histories);
  }

  /** 仕様: Core 第3.2節 */
  public static void assertAccountMatches(List<ContractHistory__c> histories) {
    if (histories == null || histories.isEmpty()) {
      return;
    }
    Set<Id> opportunityIds = new Set<Id>();
    Set<Id> serviceIds = new Set<Id>();
    List<ContractHistory__c> targets = new List<ContractHistory__c>();
    for (ContractHistory__c history : histories) {
      if (history == null || !isFollowOnType(history.Type__c)) {
        continue;
      }
      if (history.Opportunity__c == null || history.ContractService__c == null) {
        continue;
      }
      targets.add(history);
      if (!opportunityAccountById.containsKey(history.Opportunity__c)) {
        opportunityIds.add(history.Opportunity__c);
      }
      if (!serviceAccountById.containsKey(history.ContractService__c)) {
        serviceIds.add(history.ContractService__c);
      }
    }
    if (targets.isEmpty()) {
      return;
    }
    if (!opportunityIds.isEmpty()) {
      for (Opportunity opportunity : [
        SELECT Id, AccountId
        FROM Opportunity
        WHERE Id IN :opportunityIds
        WITH SYSTEM_MODE
      ]) {
        opportunityAccountById.put(opportunity.Id, opportunity.AccountId);
      }
      for (Id opportunityId : opportunityIds) {
        if (!opportunityAccountById.containsKey(opportunityId)) {
          opportunityAccountById.put(opportunityId, null);
        }
      }
    }
    if (!serviceIds.isEmpty()) {
      for (ContractService__c service : [
        SELECT Id, Account__c
        FROM ContractService__c
        WHERE Id IN :serviceIds
        WITH SYSTEM_MODE
      ]) {
        serviceAccountById.put(service.Id, service.Account__c);
      }
      for (Id serviceId : serviceIds) {
        if (!serviceAccountById.containsKey(serviceId)) {
          serviceAccountById.put(serviceId, null);
        }
      }
    }
    for (ContractHistory__c history : targets) {
      Id opportunityAccountId = opportunityAccountById.get(history.Opportunity__c);
      Id serviceAccountId = serviceAccountById.get(history.ContractService__c);
      if (opportunityAccountId == null || serviceAccountId == null) {
        history.addError(ACCOUNT_MISMATCH_MESSAGE);
        continue;
      }
      if (opportunityAccountId != serviceAccountId) {
        history.addError(ACCOUNT_MISMATCH_MESSAGE);
      }
    }
  }

  private static Boolean isFollowOnType(String historyType) {
    return historyType == ContractDomainConstants.HISTORY_TYPE_CHANGE ||
      historyType == ContractDomainConstants.HISTORY_TYPE_RENEW ||
      historyType == ContractDomainConstants.HISTORY_TYPE_CANCEL;
  }
}
