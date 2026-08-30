/** 仕様: Core 第4.9節、第11.5節 */
public without sharing class OpportunityTriggerHandler {
  public static void handle(
    List<Opportunity> newOpportunities,
    Map<Id, Opportunity> oldMap,
    System.TriggerOperation operationType
  ) {
    if (!ContractDocumentSettingService.requireRenewOpportunitySwitch()) {
      return;
    }
    if (operationType == System.TriggerOperation.BEFORE_INSERT) {
      RenewEstimateAutoCreateService.validateRenewOpportunities(
        newOpportunities
      );
    }
    if (operationType == System.TriggerOperation.AFTER_INSERT) {
      RenewEstimateAutoCreateService.createRenewEstimates(newOpportunities);
    }
  }
}
