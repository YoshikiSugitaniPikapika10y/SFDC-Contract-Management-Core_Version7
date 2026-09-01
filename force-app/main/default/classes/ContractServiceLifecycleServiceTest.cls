@IsTest
private class ContractServiceLifecycleServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  private static ContractService__c insertService(Id accountId, String name) {
    return ContractTestDataFactory.insertContractService(accountId, name);
  }

  private static ContractHistory__c insertEstimateHistory(
    Id serviceId,
    Id accountId,
    String name,
    Date termStart,
    Date termEnd
  ) {
    ContractHistory__c history = new ContractHistory__c(
      Name = name,
      ContractService__c = serviceId,
      Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
      historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
      Version__c = 1,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = termStart
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, accountId);
    insert history;
    return history;
  }

  private static void insertLine(
    Id historyId,
    Id accountId,
    Product2 product,
    Decimal amount,
    Date startDate,
    Date endDate,
    String billingType
  ) {
    ContractProduct__c line = new ContractProduct__c(
      ContractHistory__c = historyId,
      Account__c = accountId,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = amount,
      Amount__c = amount,
      StartDate__c = startDate,
      Enddate__c = endDate,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = billingType,
      Type__c = ContractDomainConstants.PRODUCT_TYPE_NEW,
      RevenueRecognitionBasis__c = billingType ==
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
        ? ContractMetadataService.REVENUE_BASIS_OVER_TIME
        : ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
    );
    ContractTestDataFactory.applyRequiredFields(line);
    insert line;
  }

  private static void setOrderedPointers(Id serviceId, Id historyId) {
    Boolean previous = ContractServiceWriteGuard.isPackageWriteAllowed();
    ContractServiceWriteGuard.allowPackageWrite(true);
    try {
      update new ContractService__c(
        Id = serviceId,
        FirstOrderedHistory__c = historyId,
        LatestOrderedHistory__c = historyId
      );
    } finally {
      ContractServiceWriteGuard.allowPackageWrite(previous);
    }
  }

  private static void clearOrderedPointers(Id serviceId) {
    Boolean previous = ContractServiceWriteGuard.isPackageWriteAllowed();
    ContractServiceWriteGuard.allowPackageWrite(true);
    try {
      update new ContractService__c(
        Id = serviceId,
        FirstOrderedHistory__c = null,
        LatestOrderedHistory__c = null
      );
    } finally {
      ContractServiceWriteGuard.allowPackageWrite(previous);
    }
  }

  @IsTest
  static void lifecycleHelpers_spotAndTerm() {
    System.assertEquals(
      true,
      ContractServiceLifecycleService.isSpotLifecycle(
        ContractDomainConstants.LIFECYCLE_SPOT
      )
    );
    System.assertEquals(
      true,
      ContractServiceLifecycleService.isTermLifecycle(
        ContractDomainConstants.LIFECYCLE_TERM
      )
    );
    System.assertEquals(
      false,
      ContractServiceLifecycleService.isSpotLifecycle(
        ContractDomainConstants.LIFECYCLE_TERM
      )
    );
  }

  @IsTest
  static void ensureLifecycle_setsTermFromRecurringFirstOrdered() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Lifecycle Acct');
      ContractService__c service = insertService(
        account.Id,
        'Lifecycle Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Lifecycle V1',
        termStart,
        termEnd
      );
      Product2 product = ContractTestDataFactory.buildProduct('Lifecycle Prod');
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      insertLine(
        history.Id,
        account.Id,
        product,
        12000,
        termStart,
        termEnd,
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      );
      setOrderedPointers(service.Id, history.Id);

      Test.startTest();
      ContractServiceLifecycleService.ensureLifecycleForServices(
        new Set<Id>{ service.Id }
      );
      Test.stopTest();

      service = [
        SELECT Lifecycle__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        ContractDomainConstants.LIFECYCLE_TERM,
        service.Lifecycle__c
      );
    }
  }

  @IsTest
  static void ensureLifecycle_errorsWhenBlankLifecycleAndFirstOrderedNotVersion1() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Lifecycle NonV1 Acct'
      );
      ContractService__c service = insertService(
        account.Id,
        'Lifecycle NonV1 Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c v1 = insertEstimateHistory(
        service.Id,
        account.Id,
        'Lifecycle NonV1 V1',
        termStart,
        termEnd
      );
      ContractHistory__c v2 = new ContractHistory__c(
        Name = 'Lifecycle NonV1 V2',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_CHANGE,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 2,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart,
        PreviousHistory__c = v1.Id
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(v2, account.Id);
      insert v2;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Lifecycle NonV1 Prod'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      insertLine(
        v2.Id,
        account.Id,
        product,
        12000,
        termStart,
        termEnd,
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      );
      setOrderedPointers(service.Id, v2.Id);

      Boolean thrown = false;
      String message = null;
      Test.startTest();
      try {
        ContractServiceLifecycleService.ensureLifecycleForServices(
          new Set<Id>{ service.Id }
        );
      } catch (ContractServiceLifecycleService.LifecycleException ex) {
        thrown = true;
        message = ex.getMessage();
      }
      Test.stopTest();
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Lifecycleが空のままOrderedがある契約サービスは、推測して埋められません。',
        message
      );
    }
  }

  @IsTest
  static void ensureLifecycle_setsSpotFromOneTimeFirstOrdered() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Lifecycle Spot Acct'
      );
      ContractService__c service = insertService(
        account.Id,
        'Lifecycle Spot Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Lifecycle Spot V1',
        termStart,
        termStart
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Lifecycle Spot Prod'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(product, false);
      insertLine(
        history.Id,
        account.Id,
        product,
        1000,
        termStart,
        termStart,
        ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME
      );
      setOrderedPointers(service.Id, history.Id);

      Test.startTest();
      ContractServiceLifecycleService.ensureLifecycleForServices(
        new Set<Id>{ service.Id }
      );
      Test.stopTest();

      service = [
        SELECT Lifecycle__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        ContractDomainConstants.LIFECYCLE_SPOT,
        service.Lifecycle__c
      );
    }
  }

  @IsTest
  static void ensureLifecycle_clearsWhenFirstOrderedRemoved() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Lifecycle Clear Acct'
      );
      ContractService__c service = insertService(
        account.Id,
        'Lifecycle Clear Service'
      );
      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Lifecycle Clear V1',
        termStart,
        termEnd
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Lifecycle Clear Prod'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      insertLine(
        history.Id,
        account.Id,
        product,
        12000,
        termStart,
        termEnd,
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      );
      setOrderedPointers(service.Id, history.Id);
      ContractServiceLifecycleService.ensureLifecycleForServices(
        new Set<Id>{ service.Id }
      );
      service = [
        SELECT Lifecycle__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        ContractDomainConstants.LIFECYCLE_TERM,
        service.Lifecycle__c
      );

      clearOrderedPointers(service.Id);

      Test.startTest();
      ContractServiceLifecycleService.ensureLifecycleForServices(
        new Set<Id>{ service.Id }
      );
      Test.stopTest();

      service = [
        SELECT Lifecycle__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(null, service.Lifecycle__c);
    }
  }

  @IsTest
  static void ensureLifecycle_doesNotOverwriteExistingTerm() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Lifecycle Keep Acct'
      );
      BillingAccount__c billingAccount = ContractTestDataFactory.insertBillingAccount(
        account.Id
      );
      ContractService__c service = new ContractService__c(
        Name = 'Lifecycle Keep Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10),
        Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM
      );
      ContractTestDataFactory.applyRequiredFields(service);
      insert service;
      Date termStart = ContractTestDataFactory.stableTermStart();
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Lifecycle Keep V1',
        termStart,
        termStart
      );
      Product2 product = ContractTestDataFactory.buildProduct(
        'Lifecycle Keep OneTime'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(product, false);
      insertLine(
        history.Id,
        account.Id,
        product,
        1000,
        termStart,
        termStart,
        ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME
      );
      setOrderedPointers(service.Id, history.Id);

      Test.startTest();
      ContractServiceLifecycleService.ensureLifecycleForServices(
        new Set<Id>{ service.Id }
      );
      Test.stopTest();

      service = [
        SELECT Lifecycle__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        ContractDomainConstants.LIFECYCLE_TERM,
        service.Lifecycle__c,
        'Ordered が残っている間は Term を Spot に上書きしない'
      );
    }
  }

  @IsTest
  static void backfillAllBlankLifecycles_isRejected() {
    try {
      ContractServiceLifecycleService.backfillAllBlankLifecycles();
      System.assert(false, '一括補完は拒否する');
    } catch (ContractServiceLifecycleService.LifecycleException ex) {
      System.assert(
        ex.getMessage().contains('Lifecycleの一括補完は持たない。導入作業で直してください。'),
        ex.getMessage()
      );
    }
  }
}
