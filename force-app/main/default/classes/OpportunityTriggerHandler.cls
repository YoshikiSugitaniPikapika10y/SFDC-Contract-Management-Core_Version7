/**
 * Opportunity トリガ入口。
 * 更新見積自動作成は契約サービス側（RenewEstimateAutoCreateService）へ移した。
 */
public without sharing class OpportunityTriggerHandler {
  public static void handle(
    List<Opportunity> newOpportunities,
    Map<Id, Opportunity> oldMap,
    System.TriggerOperation operationType
  ) {
  }
}
