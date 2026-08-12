@IsTest
private class ContractHistoryVersionUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void getNextHistoryVersion_returnsOneForNewService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Version Account'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Version Service'
      );

      System.assertEquals(
        1,
        ContractHistoryVersionUtil.getNextHistoryVersion(service.Id)
      );
    }
  }

  @IsTest
  static void getNextHistoryVersion_ignoresEstimateVersions() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Ordered Version Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Ordered Version Opportunity'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Ordered Version Service'
      );

      insert new List<ContractHistory__c>{
        new ContractHistory__c(
          Name = 'Ordered v1',
          ContractService__c = service.Id,
          Type__c = 'New',
          historystatus__c = 'Ordered',
          Version__c = 1,
          Opportunity__c = opportunity.Id
        ),
        new ContractHistory__c(
          Name = 'Ordered v2',
          ContractService__c = service.Id,
          Type__c = 'New',
          historystatus__c = 'Ordered',
          Version__c = 2,
          Opportunity__c = opportunity.Id
        ),
        new ContractHistory__c(
          Name = 'Estimate v9',
          ContractService__c = service.Id,
          Type__c = 'Change',
          historystatus__c = 'Estimate',
          Version__c = 9,
          Opportunity__c = opportunity.Id
        )
      };

      System.assertEquals(
        3,
        ContractHistoryVersionUtil.getNextHistoryVersion(service.Id),
        '未受注 Estimate の Version は採番に含めない'
      );
    }
  }

  @IsTest
  static void allocateNextVersion_reusesLatestOrderedPlusOne() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Batch Version Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Batch Version Opportunity'
      );

      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Batch Version Service'
      );

      insert new ContractHistory__c(
        Name = 'History v1',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        Opportunity__c = opportunity.Id
      );

      Map<Id, Decimal> allocator = ContractHistoryVersionUtil.buildVersionAllocator(
        new Set<Id>{ service.Id }
      );

      System.assertEquals(
        2,
        ContractHistoryVersionUtil.allocateNextVersion(allocator, service.Id)
      );
      System.assertEquals(
        2,
        ContractHistoryVersionUtil.allocateNextVersion(allocator, service.Id),
        '同一バッチでも Estimate 同士は同じ次 Version を返す'
      );
    }
  }
}
