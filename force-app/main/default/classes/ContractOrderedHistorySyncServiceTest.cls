@IsTest
private class ContractOrderedHistorySyncServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  private static ContractService__c insertService(Id accountId, String name) {
    BillingAccount__c billingAccount = ContractTestDataFactory.insertBillingAccount(
      accountId
    );
    ContractService__c service = new ContractService__c(
      Name = name,
      Account__c = accountId,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10),
      Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM
    );
    ContractTestDataFactory.applyRequiredFields(service);
    insert service;
    return service;
  }

  private static ContractHistory__c insertEstimateHistory(
    Id serviceId,
    Id accountId,
    String name,
    Decimal version,
    Id previousHistoryId
  ) {
    Date termStart = Date.newInstance(2026, 6, 1);
    Date termEnd = Date.newInstance(2027, 5, 31);
    ContractHistory__c history = new ContractHistory__c(
      Name = name,
      ContractService__c = serviceId,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = version,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = termStart,
      PreviousHistory__c = previousHistoryId
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, accountId);
    insert history;
    return history;
  }

  private static void addOneTimeProduct(Id historyId, Id accountId) {
    Product2 product = ContractTestDataFactory.buildProduct('Ordered Sync Product');
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c line = new ContractProduct__c(
      ContractHistory__c = historyId,
      Account__c = accountId,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1,
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2026, 6, 30),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Type__c = 'New'
    );
    ContractTestDataFactory.applyRequiredFields(line);
    insert line;
  }

  private static void setOrderedHistoryPointers(
    Id serviceId,
    Id firstHistoryId,
    Id latestHistoryId
  ) {
    Boolean previousWrite = ContractServiceWriteGuard.isPackageWriteAllowed();
    ContractServiceWriteGuard.allowPackageWrite(true);
    try {
      update new ContractService__c(
        Id = serviceId,
        FirstOrderedHistory__c = firstHistoryId,
        LatestOrderedHistory__c = latestHistoryId
      );
    } finally {
      ContractServiceWriteGuard.allowPackageWrite(previousWrite);
    }
  }

  @IsTest
  static void syncForHistories_nullOrEmpty_doesNotChangeServices() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractOrderedHistorySyncService.syncForHistories(null);
      ContractOrderedHistorySyncService.syncForHistories(
        new List<ContractHistory__c>()
      );
      ContractOrderedHistorySyncService.syncForServices(null);
      ContractOrderedHistorySyncService.syncForServices(new Set<Id>());
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractService__c
          WHERE Name = 'Ordered History Sync Service'
        ],
        'Core 第3.4.2節: 対象の契約サービスが無ければ同期しない'
      );
    }
  }

  @IsTest
  static void syncForServices_setsFirstAndLatestOrderedHistories() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Ordered Sync Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'Ordered History Sync Service'
      );
      ContractHistory__c firstHistory = insertEstimateHistory(
        service.Id,
        account.Id,
        'First Ordered History',
        1,
        null
      );
      addOneTimeProduct(firstHistory.Id, account.Id);
      firstHistory.historystatus__c = 'Ordered';
      update firstHistory;
      ContractService__c afterFirstInsert = [
        SELECT FirstOrderedHistory__c, LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        firstHistory.Id,
        afterFirstInsert.FirstOrderedHistory__c,
        'Core 第5.4節: 最初の Ordered が FirstOrderedHistory'
      );
      System.assertEquals(
        firstHistory.Id,
        afterFirstInsert.LatestOrderedHistory__c,
        'Core 第5.4節: Ordered が1件なら Latest も同じ'
      );
      ContractHistory__c secondHistory = insertEstimateHistory(
        service.Id,
        account.Id,
        'Second Ordered History',
        2,
        firstHistory.Id
      );
      addOneTimeProduct(secondHistory.Id, account.Id);
      secondHistory.historystatus__c = 'Ordered';
      update secondHistory;
      ContractHistory__c higherEstimate = insertEstimateHistory(
        service.Id,
        account.Id,
        'Higher Estimate History',
        99,
        secondHistory.Id
      );
      setOrderedHistoryPointers(
        service.Id,
        secondHistory.Id,
        higherEstimate.Id
      );
      Test.startTest();
      ContractOrderedHistorySyncService.syncForServices(
        new Set<Id>{ service.Id }
      );
      Test.stopTest();
      ContractService__c afterSecondOrdered = [
        SELECT FirstOrderedHistory__c, LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        firstHistory.Id,
        afterSecondOrdered.FirstOrderedHistory__c,
        'Core 第5.4節: First Ordered は実際の Ordered のうち Version 最小'
      );
      System.assertEquals(
        secondHistory.Id,
        afterSecondOrdered.LatestOrderedHistory__c,
        'Core 第5.4節: Latest Ordered は高Versionの Estimateを除く実際の Ordered のうち Version 最大'
      );
    }
  }

  @IsTest
  static void syncForServices_ignoresEstimateHistories() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Estimate Only Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'Estimate Only Service'
      );
      ContractHistory__c estimateHistory = insertEstimateHistory(
        service.Id,
        account.Id,
        'Estimate History',
        1,
        null
      );
      setOrderedHistoryPointers(
        service.Id,
        estimateHistory.Id,
        estimateHistory.Id
      );
      Test.startTest();
      ContractOrderedHistorySyncService.syncForServices(
        new Set<Id>{ service.Id }
      );
      Test.stopTest();
      ContractService__c updatedService = [
        SELECT FirstOrderedHistory__c, LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        null,
        updatedService.FirstOrderedHistory__c,
        'Core 第5.4節: Ordered が0件なら Estimateを First Ordered として保持しない'
      );
      System.assertEquals(
        null,
        updatedService.LatestOrderedHistory__c,
        'Core 第5.4節: Ordered が0件なら Estimateを Latest Ordered として保持しない'
      );
    }
  }
}
