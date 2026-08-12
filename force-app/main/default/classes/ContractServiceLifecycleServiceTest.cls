@IsTest
private class ContractServiceLifecycleServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
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
      ContractService__c service = new ContractService__c(
        Name = 'Lifecycle Service',
        Account__c = account.Id
      );
      insert service;

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      // Ordered トリガの受注検証を避けるため Estimate で作成し、First ポインタだけ渡す
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Lifecycle V1',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct('Lifecycle Prod');
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = ContractDomainConstants.PRODUCT_TYPE_NEW
      );

      service.FirstOrderedHistory__c = history.Id;
      service.LatestOrderedHistory__c = history.Id;
      update service;

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
  static void ensureLifecycle_setsTermFromProduct2WhenLineBillingTypeBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Lifecycle Prod2 Acct'
      );
      ContractService__c service = new ContractService__c(
        Name = 'Lifecycle Prod2 Service',
        Account__c = account.Id
      );
      insert service;

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Lifecycle Prod2 V1',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Lifecycle Prod2 Recurring'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        Type__c = ContractDomainConstants.PRODUCT_TYPE_NEW
      );

      service.FirstOrderedHistory__c = history.Id;
      service.LatestOrderedHistory__c = history.Id;
      update service;

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
  static void ensureLifecycle_setsSpotFromOneTimeFirstOrdered() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Lifecycle Spot Acct');
      ContractService__c service = new ContractService__c(
        Name = 'Lifecycle Spot Service',
        Account__c = account.Id
      );
      insert service;

      Date termStart = ContractTestDataFactory.stableTermStart();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Lifecycle Spot V1',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct('Lifecycle Spot Prod');
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(product, false);

      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        StartDate__c = termStart,
        Enddate__c = termStart,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = ContractDomainConstants.PRODUCT_TYPE_NEW
      );

      service.FirstOrderedHistory__c = history.Id;
      service.LatestOrderedHistory__c = history.Id;
      update service;

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
      ContractService__c service = new ContractService__c(
        Name = 'Lifecycle Clear Service',
        Account__c = account.Id
      );
      insert service;

      Date termStart = ContractTestDataFactory.stableTermStart();
      Date termEnd = ContractTestDataFactory.stableTermEnd();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Lifecycle Clear V1',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd,
        EffectiveDate__c = termStart
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Lifecycle Clear Prod'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);

      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 12000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = ContractDomainConstants.PRODUCT_TYPE_NEW
      );

      service.FirstOrderedHistory__c = history.Id;
      service.LatestOrderedHistory__c = history.Id;
      update service;
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

      service.FirstOrderedHistory__c = null;
      service.LatestOrderedHistory__c = null;
      update service;

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
      ContractService__c service = new ContractService__c(
        Name = 'Lifecycle Keep Service',
        Account__c = account.Id,
        Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM
      );
      insert service;

      Date termStart = ContractTestDataFactory.stableTermStart();
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Lifecycle Keep V1',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1
      );
      insert history;

      Product2 product = ContractTestDataFactory.buildProduct(
        'Lifecycle Keep OneTime'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(product, false);

      insert new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        StartDate__c = termStart,
        Enddate__c = termStart,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = ContractDomainConstants.PRODUCT_TYPE_NEW
      );

      service.FirstOrderedHistory__c = history.Id;
      service.LatestOrderedHistory__c = history.Id;
      update service;

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
  static void backfillAllBlankLifecycles_runs() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Integer processed = ContractServiceLifecycleService.backfillAllBlankLifecycles();
      System.assert(processed >= 0);
    }
  }
}
