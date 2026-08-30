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

      // アーカイブ対象に前回契約履歴を付け、遷移後に Null 化されることを検証する
      histories[0].PreviousHistory__c = histories[4].Id;
      histories[1].PreviousHistory__c = histories[4].Id;
      histories[3].PreviousHistory__c = histories[4].Id;
      update new List<ContractHistory__c>{
        histories[0],
        histories[1],
        histories[3]
      };

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
          SELECT Id, Name, historystatus__c, Version__c, PreviousHistory__c
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
        null,
        updatedById.get(histories[0].Id).PreviousHistory__c,
        '自動 Archive でも前回契約履歴は Null'
      );
      System.assertEquals(
        'Archive',
        updatedById.get(histories[1].Id).historystatus__c
      );
      System.assertEquals(
        null,
        updatedById.get(histories[1].Id).PreviousHistory__c
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
        null,
        updatedById.get(histories[3].Id).PreviousHistory__c
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

  @IsTest
  static void archiveSupersededEstimates_copiesParentOperationKey() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Key Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Archive Key Service'
      );
      ContractHistory__c estimate = buildEstimateHistory(
        service.Id,
        'Estimate v1',
        1
      );
      insert estimate;
      ContractHistory__c ordered = buildEstimateHistory(
        service.Id,
        'Ordered v2',
        2
      );
      ordered.historystatus__c = 'Ordered';
      ordered.BusinessOperationKey__c = 'parent-order-key';
      insert ordered;

      Test.startTest();
      ContractHistoryArchiveService.archiveSupersededEstimates(
        new List<ContractHistory__c>{
          new ContractHistory__c(
            Id = ordered.Id,
            ContractService__c = service.Id,
            Version__c = 2,
            BusinessOperationKey__c = 'parent-order-key'
          )
        }
      );
      Test.stopTest();

      System.assertEquals(
        'parent-order-key',
        [
          SELECT BusinessOperationKey__c
          FROM ContractHistory__c
          WHERE Id = :estimate.Id
        ]
        .BusinessOperationKey__c,
        'Core 第4.3.12節: 自動Archiveは親操作のキーに含め、別キーにしない'
      );
    }
  }

  @IsTest
  static void archiveSupersededEstimates_copiesParentOperationKey() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Key Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Archive Key Service'
      );
      ContractHistory__c older = buildEstimateHistory(
        service.Id,
        'Estimate older',
        1
      );
      ContractHistory__c ordered = buildEstimateHistory(
        service.Id,
        'Ordered newer',
        2
      );
      insert new List<ContractHistory__c>{ older, ordered };

      ContractHistoryArchiveService.archiveSupersededEstimates(
        new List<ContractHistory__c>{
          new ContractHistory__c(
            Id = ordered.Id,
            ContractService__c = service.Id,
            Version__c = 2,
            BusinessOperationKey__c = 'parent-order-key'
          )
        }
      );

      System.assertEquals(
        'parent-order-key',
        [
          SELECT BusinessOperationKey__c
          FROM ContractHistory__c
          WHERE Id = :older.Id
        ]
        .BusinessOperationKey__c,
        'Core 第4.3.12節: 自動Archiveは親操作のキーに含め、別キーにしない'
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
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END, PaymentTermMonthOffset__c = 0, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER, InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY, InvoiceDateDayOfMonth__c = 25, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE
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
