@IsTest
private class AccountingDiffServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void applyForInvoice_rejectsNullInvoice() {
    Boolean thrown = false;
    try {
      AccountingDiffService.applyForInvoice(
        null,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        'PAYMENT_RECORDED:TEST',
        null
      );
    } catch (Exception ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('請求が指定されていません'),
        'Accounting 第8.2節: 対象請求書が無ければGoal・Current・Diffを始めない'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void applyForInvoice_skipsGenerationWhenAccountingOff() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertConfirmedInvoice();
      AccountingDiffService.applyForInvoice(
        invoice.Id,
        AccountingEventFixedCatalog.PAYMENT_RECORDED.key,
        'PAYMENT_RECORDED:OFF',
        null
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM GlJournal__c
          WHERE Invoice__c = :invoice.Id
        ],
        'Accounting 第8.2節: OFFなら通常の生成を行わない'
      );
    }
  }

  private static Invoice__c insertConfirmedInvoice() {
    Account account = ContractTestDataFactory.insertAccount(
      'Diff ' + String.valueOf(Crypto.getRandomInteger())
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'diff@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 1,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      'Diff Opp'
    );
    ContractService__c service = new ContractService__c(
      Name = 'Diff Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Diff History',
      ContractService__c = service.Id,
      Opportunity__c = opportunity.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1
    );
    insert history;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = 100,
      TaxInclusiveAmount__c = 1100,
      BillingAccountSnapShot__c = billingAccount.Id,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      SystemIntegrationDate__c = Date.today()
    );
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    return invoice;
  }
}
