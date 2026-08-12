@IsTest
private class ContractOrderedHistorySyncServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }
  @IsTest
  static void syncForServices_setsFirstAndLatestOrderedHistories() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Ordered Sync Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Ordered Sync Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Ordered History Sync Service'
      );
      Date termStart = Date.today();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c firstHistory = new ContractHistory__c(
        Name = 'First Ordered History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert firstHistory;
      ContractService__c afterFirstInsert = [
        SELECT FirstOrderedHistory__c, LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        firstHistory.Id,
        afterFirstInsert.FirstOrderedHistory__c
      );
      System.assertEquals(
        firstHistory.Id,
        afterFirstInsert.LatestOrderedHistory__c
      );
      ContractHistory__c secondHistory = new ContractHistory__c(
        Name = 'Second Ordered History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id,
        PreviousHistory__c = firstHistory.Id
      );
      insert secondHistory;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Ordered Sync Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY;
      ContractTestDataFactory.insertProduct(product);
      insert new ContractProduct__c(
        ContractHistory__c = secondHistory.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      Test.startTest();
      secondHistory.historystatus__c = 'Ordered';
      update secondHistory;
      Test.stopTest();
      ContractService__c afterSecondOrdered = [
        SELECT FirstOrderedHistory__c, LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        firstHistory.Id,
        afterSecondOrdered.FirstOrderedHistory__c
      );
      System.assertEquals(
        secondHistory.Id,
        afterSecondOrdered.LatestOrderedHistory__c
      );
    }
  }
  @IsTest
  static void syncForServices_ignoresEstimateHistories() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Estimate Only Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Estimate Only Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Estimate Only Service'
      );
      insert new ContractHistory__c(
        Name = 'Estimate History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.today(),
        CurrentTermEndDate__c = ContractTestDataFactory.stableTermEnd(),
        Opportunity__c = opportunity.Id
      );
      ContractService__c updatedService = [
        SELECT FirstOrderedHistory__c, LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(null, updatedService.FirstOrderedHistory__c);
      System.assertEquals(null, updatedService.LatestOrderedHistory__c);
    }
  }
  @IsTest
  static void deleteOrderedHistory_resyncsFirstAndLatest() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Ordered Delete Sync Account'
      );
      Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
        account.Id,
        'Ordered Delete Sync Opportunity'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Ordered Delete Sync Service'
      );
      Date termStart = Date.today();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c firstHistory = new ContractHistory__c(
        Name = 'First Ordered History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id
      );
      insert firstHistory;
      ContractHistory__c secondHistory = new ContractHistory__c(
        Name = 'Second Ordered History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        Opportunity__c = opportunity.Id,
        PreviousHistory__c = firstHistory.Id
      );
      insert secondHistory;
      ContractService__c beforeDelete = [
        SELECT FirstOrderedHistory__c, LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(firstHistory.Id, beforeDelete.FirstOrderedHistory__c);
      System.assertEquals(
        secondHistory.Id,
        beforeDelete.LatestOrderedHistory__c
      );
      Test.startTest();
      delete secondHistory;
      Test.stopTest();
      ContractService__c afterDelete = [
        SELECT FirstOrderedHistory__c, LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(firstHistory.Id, afterDelete.FirstOrderedHistory__c);
      System.assertEquals(firstHistory.Id, afterDelete.LatestOrderedHistory__c);
    }
  }
}
