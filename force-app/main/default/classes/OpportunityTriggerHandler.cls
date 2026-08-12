/**
 * Opportunity トリガ入口。更新見積自動作成（チェック OFF→ON 更新時のみ）などへ委譲する。
 */
public without sharing class OpportunityTriggerHandler {
  public static void handle(
    List<Opportunity> newOpportunities,
    Map<Id, Opportunity> oldMap,
    System.TriggerOperation operationType
  ) {
    if (Trigger.isBefore) {
      if (
        operationType == System.TriggerOperation.BEFORE_INSERT ||
        operationType == System.TriggerOperation.BEFORE_UPDATE
      ) {
        RenewEstimateAutoCreateService.validateBeforeSave(
          newOpportunities,
          oldMap
        );
      }
      return;
    }

    if (
      operationType == System.TriggerOperation.AFTER_INSERT ||
      operationType == System.TriggerOperation.AFTER_UPDATE
    ) {
      RenewEstimateAutoCreateService.createRenewEstimates(
        newOpportunities,
        oldMap
      );
    }
  }
}
