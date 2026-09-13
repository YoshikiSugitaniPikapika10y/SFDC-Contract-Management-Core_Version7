@IsTest
private class ContractHistoryArchiveServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void archiveSupersededEstimates_emptyOrInvalidRowsDoNothing() {
    ContractHistoryArchiveService.archiveSupersededEstimates(null);
    ContractHistoryArchiveService.archiveSupersededEstimates(
      new List<ContractHistory__c>()
    );
    ContractHistoryArchiveService.archiveSupersededEstimates(
      new List<ContractHistory__c>{
        null,
        new ContractHistory__c(Version__c = 1)
      }
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM ContractHistory__c],
      'Core 第4.3節: 受注したVersion以下の他のEstimateだけをArchiveする。対象が無ければ何もしない'
    );
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
        buildEstimateHistory(service.Id, account.Id, 'Estimate v1', 1),
        buildEstimateHistory(service.Id, account.Id, 'Estimate v2', 2),
        buildEstimateHistory(service.Id, account.Id, 'Estimate v4 A', 4),
        buildEstimateHistory(service.Id, account.Id, 'Estimate v4 B', 4),
        buildEstimateHistory(service.Id, account.Id, 'Estimate v5', 5)
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
            Version__c = 4,
            BusinessOperationKey__c = 'parent-order-key'
          )
        }
      );

      Map<Id, ContractHistory__c> updatedById = new Map<Id, ContractHistory__c>(
        [
          SELECT
            Id,
            Name,
            historystatus__c,
            Version__c,
            PreviousHistory__c,
            BusinessOperationKey__c
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
        'parent-order-key',
        updatedById.get(histories[0].Id).BusinessOperationKey__c,
        'Core 第4.3.12節・第5.5節: 自動Archiveは親操作のキーに含める'
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
        'parent-order-key',
        updatedById.get(histories[1].Id).BusinessOperationKey__c,
        'Core 第4.3.12節・第5.5節: 同じ処理の自動Archiveを別キーにしない'
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
        'parent-order-key',
        updatedById.get(histories[3].Id).BusinessOperationKey__c,
        'Core 第4.3.12節・第5.5節: 同Versionの他Estimateも親操作のキーに含める'
      );
      System.assertEquals(
        'Estimate',
        updatedById.get(histories[4].Id).historystatus__c
      );
    }
  }

  @IsTest
  static void archiveSupersededEstimates_doesNotPurgeBillingOnEstimateArchive() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive No Purge Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(
        account,
        'Archive No Purge Service'
      );
      ContractHistory__c estimate = buildEstimateHistory(
        service.Id,
        account.Id,
        'Estimate leftover',
        1
      );
      insert estimate;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Archive No Purge Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c contractProduct = new ContractProduct__c(
        ContractHistory__c = estimate.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Renew'
      );
      insert contractProduct;
      InvoiceProduct__c period = new InvoiceProduct__c(
        ContractHistory__c = estimate.Id,
        ContractProduct__c = contractProduct.Id,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30),
        Amount__c = 1000
      );
      insert period;
      Invoice__c invoice = new Invoice__c(
        ContractHistory__c = estimate.Id,
        ContractService__c = service.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100
      );
      insert invoice;

      Test.startTest();
      ContractHistoryArchiveService.archiveSupersededEstimates(
        new List<ContractHistory__c>{
          new ContractHistory__c(
            Id = fakeId(ContractHistory__c.SObjectType, 91),
            ContractService__c = service.Id,
            Version__c = 2
          )
        }
      );
      Test.stopTest();
      System.assertEquals(
        'Archive',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :estimate.Id
        ]
        .historystatus__c,
        'Core 第5.5節: 受注Version以下の他EstimateはArchive'
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM InvoiceProduct__c WHERE Id = :period.Id],
        'Core 第5.5節: 自動Archiveは有効な契約期間明細を物理削除しない'
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM Invoice__c WHERE Id = :invoice.Id],
        'Core 第5.5節: 自動Archiveは未確定請求を物理削除しない'
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

      insert buildEstimateHistory(service.Id, account.Id, 'Estimate v1', 1);

      Test.startTest();
      ContractHistory__c cancelOrdered = new ContractHistory__c(
        Name = 'Cancel Ordered v2',
        ContractService__c = service.Id,
        Type__c = 'Cancel',
        historystatus__c = 'Ordered',
        Version__c = 2,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 6, 1),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        cancelOrdered,
        account.Id
      );
      insert cancelOrdered;
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
      ContractHistory__c estA = buildEstimateHistory(serviceA.Id, account.Id, 'A-v1', 1);
      ContractHistory__c estB = buildEstimateHistory(serviceB.Id, account.Id, 'B-v1', 1);
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
  static void archiveSupersededEstimates_doesNotReadHigherVersionOnOtherService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Scope Account'
      );
      ContractService__c serviceA = insertServiceWithBillingAccount(
        account,
        'Archive Scope A'
      );
      ContractService__c serviceB = insertServiceWithBillingAccount(
        account,
        'Archive Scope B'
      );
      ContractHistory__c estAHigh = buildEstimateHistory(
        serviceA.Id,
        account.Id,
        'A-v3',
        3
      );
      ContractHistory__c estBLow = buildEstimateHistory(
        serviceB.Id,
        account.Id,
        'B-v1',
        1
      );
      insert new List<ContractHistory__c>{ estAHigh, estBLow };

      Test.startTest();
      ContractHistoryArchiveService.archiveSupersededEstimates(
        new List<ContractHistory__c>{
          new ContractHistory__c(
            Id = fakeId(ContractHistory__c.SObjectType, 81),
            ContractService__c = serviceA.Id,
            Version__c = 1
          ),
          new ContractHistory__c(
            Id = fakeId(ContractHistory__c.SObjectType, 82),
            ContractService__c = serviceB.Id,
            Version__c = 5
          )
        }
      );
      Test.stopTest();

      System.assertEquals(
        'Estimate',
        [SELECT historystatus__c FROM ContractHistory__c WHERE Id = :estAHigh.Id]
        .historystatus__c,
        'Core 第5.2節: 受注Version以下の他EstimateだけArchive'
      );
      System.assertEquals(
        'Archive',
        [SELECT historystatus__c FROM ContractHistory__c WHERE Id = :estBLow.Id]
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
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET, PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END, PaymentTermMonthOffset__c = 0, PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE,
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER, InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY, InvoiceDateDayOfMonth__c = 25, InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    ContractService__c service = new ContractService__c(
      Name = serviceName,
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM
    );
    ContractTestDataFactory.applyRequiredFields(service);
    insert service;
    return service;
  }

  private static ContractHistory__c buildEstimateHistory(
    Id serviceId,
    Id accountId,
    String name,
    Decimal version
  ) {
    ContractHistory__c history = new ContractHistory__c(
      Name = name,
      ContractService__c = serviceId,
      Type__c = 'Renew',
      historystatus__c = 'Estimate',
      Version__c = version,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
      EffectiveDate__c = Date.newInstance(2026, 6, 1)
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, accountId);
    return history;
  }

  private static Id fakeId(Schema.SObjectType sobjectType, Integer n) {
    String suffix = String.valueOf(n);
    while (suffix.length() < 12) {
      suffix = '0' + suffix;
    }
    return (Id) (sobjectType.getDescribe().getKeyPrefix() + suffix);
  }
}
