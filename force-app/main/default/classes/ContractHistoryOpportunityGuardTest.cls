@IsTest
private class ContractHistoryOpportunityGuardTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void estimateWithoutOpportunityIsRejected() {
    ContractHistory__c history = new ContractHistory__c(
      historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE
    );
    ContractHistoryOpportunityGuard.assertRequired(
      new List<ContractHistory__c>{ history }
    );
    System.assertEquals(
      true,
      history.hasErrors(),
      'Estimate の商談空欄を拒否する'
    );
  }

  @IsTest
  static void archiveWithoutOpportunityIsAllowed() {
    ContractHistory__c history = new ContractHistory__c(
      historystatus__c = ContractDomainConstants.HISTORY_STATUS_ARCHIVE
    );
    ContractHistoryOpportunityGuard.assertRequired(
      new List<ContractHistory__c>{ history }
    );
    System.assertEquals(false, history.hasErrors());
  }

  @IsTest
  static void changeWithMismatchedAccountsIsRejected() {
    Id fakeOpportunityId = Opportunity.SObjectType.getDescribe().getKeyPrefix() +
      '000000000001AAA';
    Id fakeServiceId = ContractService__c.SObjectType.getDescribe()
      .getKeyPrefix() + '000000000001AAA';
    ContractHistory__c history = new ContractHistory__c(
      historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
      Type__c = ContractDomainConstants.HISTORY_TYPE_CHANGE,
      Opportunity__c = fakeOpportunityId,
      ContractService__c = fakeServiceId
    );
    ContractHistoryOpportunityGuard.assertRequired(
      new List<ContractHistory__c>{ history }
    );
    System.assertEquals(true, history.hasErrors(), '取引先不一致を拒否する');
  }

  @IsTest
  static void insertEstimateWithoutOpportunity_isRejected() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Opp Guard');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Opp Guard Service'
      );
      Test.startTest();
      try {
        insert new ContractHistory__c(
          Name = 'No Opportunity',
          ContractService__c = service.Id,
          Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
          historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
          Version__c = 1
        );
        System.assert(false, 'Estimate の商談空欄は失敗するはず');
      } catch (DmlException ex) {
        System.assert(
          ex.getMessage()
            .contains(ContractHistoryOpportunityGuard.REQUIRED_MESSAGE),
          ex.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void clearOrderedOpportunity_isRejected() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Opp Guard Ordered');
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Opp Guard Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Opp Guard Ordered Service'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'With Opportunity',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1,
        Opportunity__c = opportunity.Id
      );
      insert history;
      Test.startTest();
      try {
        history.Opportunity__c = null;
        update history;
        System.assert(false, 'Ordered/Estimate の商談クリアは失敗するはず');
      } catch (DmlException ex) {
        System.assert(
          ex.getMessage()
            .contains(ContractHistoryOpportunityGuard.REQUIRED_MESSAGE),
          ex.getMessage()
        );
      }
      Test.stopTest();
    }
  }
}
