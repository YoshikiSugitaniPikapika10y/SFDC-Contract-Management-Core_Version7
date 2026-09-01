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
        afterSecondOrdered.FirstOrderedHistory__c,
        'Core 第5.4節: First は Version 最小の Ordered'
      );
      System.assertEquals(
        secondHistory.Id,
        afterSecondOrdered.LatestOrderedHistory__c,
        'Core 第5.4節: Latest は Version 最大の Ordered'
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
      insertEstimateHistory(
        service.Id,
        account.Id,
        'Estimate History',
        1,
        null
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
        'Core 第5.4節: Estimate は First に入れない'
      );
      System.assertEquals(
        null,
        updatedService.LatestOrderedHistory__c,
        'Core 第5.4節: Estimate は Latest に入れない'
      );
    }
  }

  @IsTest
  static void deleteOrderedHistory_resyncsFirstAndLatest() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Ordered Delete Sync Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'Ordered Delete Sync Service'
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
      ContractHistory__c secondHistory = insertEstimateHistory(
        service.Id,
        account.Id,
        'Second Estimate History',
        2,
        firstHistory.Id
      );
      ContractOrderedHistorySyncService.syncForServices(
        new Set<Id>{ service.Id }
      );
      ContractService__c beforeDelete = [
        SELECT FirstOrderedHistory__c, LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(firstHistory.Id, beforeDelete.FirstOrderedHistory__c);
      System.assertEquals(
        firstHistory.Id,
        beforeDelete.LatestOrderedHistory__c,
        'Core 第5.4節: Estimate の Version は Latest に入れない'
      );
      Boolean thrown = false;
      String message = null;
      Test.startTest();
      try {
        delete secondHistory;
      } catch (DmlException ex) {
        thrown = true;
        message = ex.getNumDml() > 0 ? ex.getDmlMessage(0) : ex.getMessage();
      }
      Test.stopTest();
      System.assertEquals(
        true,
        thrown,
        'Core 第3.4節: 契約履歴は物理削除しない'
      );
      System.assertEquals(
        '契約履歴は物理削除できません。見積を閉じる場合はArchiveしてください。',
        message
      );
      ContractService__c afterDelete = [
        SELECT FirstOrderedHistory__c, LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        firstHistory.Id,
        afterDelete.FirstOrderedHistory__c,
        'Core 第5.4節: 削除拒否後も First は変わらない'
      );
      System.assertEquals(
        firstHistory.Id,
        afterDelete.LatestOrderedHistory__c,
        'Core 第5.4節: 削除拒否後も Latest は変わらない'
      );
    }
  }
}
