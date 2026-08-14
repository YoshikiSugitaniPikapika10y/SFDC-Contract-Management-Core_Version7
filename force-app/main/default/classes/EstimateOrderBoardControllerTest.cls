@IsTest
private class EstimateOrderBoardControllerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void listEstimates_returnsEstimateOnly_andFiltersByType() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture data = createFixture();

      Test.startTest();
      EstimateOrderBoardController.BoardContextDto context = EstimateOrderBoardController.getBoardContext();
      List<EstimateOrderBoardController.EstimateRowDto> allRows = EstimateOrderBoardController.listEstimates(
        null,
        null,
        null,
        null
      );
      List<EstimateOrderBoardController.EstimateRowDto> renewRows = EstimateOrderBoardController.listEstimates(
        'Renew',
        null,
        null,
        null
      );
      List<EstimateOrderBoardController.EstimateRowDto> searchRows = EstimateOrderBoardController.listEstimates(
        null,
        null,
        null,
        'Board Renew'
      );
      Test.stopTest();

      System.assertEquals(true, context.canOrder);
      System.assertEquals(100, context.selectAllConfirmThreshold);
      System.assertEquals(
        1,
        countRows(allRows, data.estimateHistory.Id),
        'Estimate は一覧に出ること'
      );
      System.assertEquals(
        0,
        countRows(allRows, data.orderedHistory.Id),
        'Ordered は一覧に出ないこと'
      );
      System.assertEquals(1, renewRows.size());
      System.assertEquals(data.estimateHistory.Id, renewRows[0].contractHistoryId);
      System.assertEquals('Board Renew Estimate', renewRows[0].historyName);
      System.assertEquals(1, searchRows.size());
    }
  }

  private class Fixture {
    public ContractHistory__c orderedHistory;
    public ContractHistory__c estimateHistory;
  }

  private static Integer countRows(
    List<EstimateOrderBoardController.EstimateRowDto> rows,
    Id historyId
  ) {
    Integer count = 0;
    for (EstimateOrderBoardController.EstimateRowDto row : rows) {
      if (row.contractHistoryId == historyId) {
        count++;
      }
    }
    return count;
  }

  private static Fixture createFixture() {
    Fixture data = new Fixture();
    Account account = ContractTestDataFactory.insertAccount('Board Account');
    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      'Board Opportunity'
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
      AdjustInvoiceDateToBusinessDay__c = false
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;

    ContractService__c service = new ContractService__c(
      Name = 'Board Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    insert service;

    Date termStart = Date.newInstance(2025, 6, 1);
    Date termEnd = Date.newInstance(2026, 5, 31);
    data.orderedHistory = new ContractHistory__c(
      Name = 'Board Ordered',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      Opportunity__c = opportunity.Id
    );
    insert data.orderedHistory;

    data.estimateHistory = new ContractHistory__c(
      Name = 'Board Renew Estimate',
      ContractService__c = service.Id,
      Type__c = 'Renew',
      historystatus__c = 'Estimate',
      Version__c = 2,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
      PreviousHistory__c = data.orderedHistory.Id
    );
    insert data.estimateHistory;
    return data;
  }
}
