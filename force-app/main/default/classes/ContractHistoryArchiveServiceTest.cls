@IsTest
private class ContractHistoryArchiveServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void archiveSupersededEstimates_archivesSameOrLowerVersionEstimates() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Archive Service'
      );

      List<ContractHistory__c> histories = new List<ContractHistory__c>{
        buildEstimateHistory(service.Id, 'Estimate v1', 1),
        buildEstimateHistory(service.Id, 'Estimate v2', 2),
        buildEstimateHistory(service.Id, 'Estimate v4 A', 4),
        buildEstimateHistory(service.Id, 'Estimate v4 B', 4),
        buildEstimateHistory(service.Id, 'Estimate v5', 5)
      };
      insert histories;

      // サービスメソッドを直接呼び、バルク1クエリ経路を検証（受注トリガの商品必須は別テスト）
      ContractHistoryArchiveService.archiveSupersededEstimates(
        new List<ContractHistory__c>{
          new ContractHistory__c(
            Id = histories[2].Id,
            ContractService__c = service.Id,
            Version__c = 4
          )
        }
      );

      Map<Id, ContractHistory__c> updatedById = new Map<Id, ContractHistory__c>(
        [
          SELECT Id, Name, historystatus__c, Version__c
          FROM ContractHistory__c
          WHERE ContractService__c = :service.Id
          ORDER BY Version__c ASC, Name ASC
        ]
      );

      System.assertEquals(
        'Archive',
        updatedById.get(histories[0].Id).historystatus__c
      );
      System.assertEquals(
        'Archive',
        updatedById.get(histories[1].Id).historystatus__c
      );
      System.assertEquals(
        'Estimate',
        updatedById.get(histories[2].Id).historystatus__c
      );
      System.assertEquals(
        'Archive',
        updatedById.get(histories[3].Id).historystatus__c
      );
      System.assertEquals(
        'Estimate',
        updatedById.get(histories[4].Id).historystatus__c
      );
    }
  }

  @IsTest
  static void archiveSupersededEstimates_runsOnInsertAsOrderedCancel() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Insert Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Archive Insert Service'
      );

      insert buildEstimateHistory(service.Id, 'Estimate v1', 1);

      Test.startTest();
      insert new ContractHistory__c(
        Name = 'Cancel Ordered v2',
        ContractService__c = service.Id,
        Type__c = 'Cancel',
        historystatus__c = 'Ordered',
        Version__c = 2,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 6, 1),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      Test.stopTest();

      System.assertEquals(
        'Archive',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE ContractService__c = :service.Id AND Version__c = 1
        ]
        .historystatus__c
      );
    }
  }

  @IsTest
  static void archiveSupersededEstimates_bulkAcrossServices_singlePass() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Bulk Account'
      );
      ContractService__c serviceA = insertServiceWithBillingAccount(
        account,
        'Archive Bulk A'
      );
      ContractService__c serviceB = insertServiceWithBillingAccount(
        account,
        'Archive Bulk B'
      );
      ContractHistory__c estA = buildEstimateHistory(serviceA.Id, 'A-v1', 1);
      ContractHistory__c estB = buildEstimateHistory(serviceB.Id, 'B-v1', 1);
      insert new List<ContractHistory__c>{ estA, estB };

      ContractHistoryArchiveService.archiveSupersededEstimates(
        new List<ContractHistory__c>{
          new ContractHistory__c(
            Id = fakeId(ContractHistory__c.SObjectType, 91),
            ContractService__c = serviceA.Id,
            Version__c = 2
          ),
          new ContractHistory__c(
            Id = fakeId(ContractHistory__c.SObjectType, 92),
            ContractService__c = serviceB.Id,
            Version__c = 2
          )
        }
      );

      System.assertEquals(
        'Archive',
        [SELECT historystatus__c FROM ContractHistory__c WHERE Id = :estA.Id]
        .historystatus__c
      );
      System.assertEquals(
        'Archive',
        [SELECT historystatus__c FROM ContractHistory__c WHERE Id = :estB.Id]
        .historystatus__c
      );
    }
  }

  private static ContractService__c insertServiceWithBillingAccount(
    Account account,
    String serviceName
  ) {
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    ContractService__c service = new ContractService__c(
      Name = serviceName,
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id
    );
    insert service;
    return service;
  }

  private static ContractHistory__c buildEstimateHistory(
    Id serviceId,
    String name,
    Decimal version
  ) {
    return new ContractHistory__c(
      Name = name,
      ContractService__c = serviceId,
      Type__c = 'Renew',
      historystatus__c = 'Estimate',
      Version__c = version,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
      EffectiveDate__c = Date.newInstance(2026, 6, 1)
    );
  }

  private static Id fakeId(Schema.SObjectType sobjectType, Integer n) {
    String suffix = String.valueOf(n);
    while (suffix.length() < 12) {
      suffix = '0' + suffix;
    }
    return (Id) (sobjectType.getDescribe().getKeyPrefix() + suffix);
  }
}
