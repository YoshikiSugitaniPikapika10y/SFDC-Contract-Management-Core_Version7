@IsTest
private class ContractHistoryVersionUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
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
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Ordered Version Service'
      );
      insertOrderedHistory(service, account.Id, 1, 'New');
      ContractHistory__c estimate = new ContractHistory__c(
        Name = 'Estimate v9',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 9
      );
      ContractTestDataFactory.applyRequiredFields(estimate);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        estimate,
        account.Id
      );
      insert estimate;

      System.assertEquals(
        2,
        ContractHistoryVersionUtil.getNextHistoryVersion(service.Id),
        '第1.1.1節: 未受注 Estimate の Version は採番に含めない'
      );
    }
  }

  @IsTest
  static void allocateNextVersion_reusesLatestOrderedPlusOne() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Batch Version Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Batch Version Service'
      );
      insertOrderedHistory(service, account.Id, 1, 'New');

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
        '第1.1.1節: 同一バッチでも Estimate 同士は同じ次 Version を返す'
      );
    }
  }

  private static void insertOrderedHistory(
    ContractService__c service,
    Id accountId,
    Decimal version,
    String type
  ) {
    Date termStart = Date.newInstance(2025, 6, 1);
    Date termEnd = Date.newInstance(2026, 5, 31);
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Ordered v' + String.valueOf(version),
      ContractService__c = service.Id,
      Type__c = type,
      historystatus__c = 'Estimate',
      Version__c = version,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd
    );
    ContractTestDataFactory.applyRequiredFields(history);
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, accountId);
    insert history;
    Product2 product = ContractTestDataFactory.buildProduct(
      'Version Product ' + String.valueOf(version)
    );
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Account__c = accountId,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      StartDate__c = termStart,
      Enddate__c = termEnd,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Type__c = 'New',
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
    );
    ContractTestDataFactory.applyRequiredFields(contractProduct);
    contractProduct.Amount__c = 1000;
    insert contractProduct;
    history.historystatus__c = 'Ordered';
    update history;
  }

  @IsTest
  static void contractService_isLookupNotMasterDetail() {
    Schema.DescribeFieldResult describe = ContractHistory__c.ContractService__c.getDescribe();
    System.assertEquals(Schema.DisplayType.REFERENCE, describe.getType());
    System.assertEquals(null, describe.getRelationshipOrder());
    System.assertEquals(false, describe.isCascadeDelete());
  }
}
