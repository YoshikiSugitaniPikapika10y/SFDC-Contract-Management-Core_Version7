@IsTest
private class BillingAccountTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void update_withoutOrderedUsage_doesNotRequireConfirm() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createBillingAccount('No Ordered BA');

      billingAccount.BillingEmailTo__c = 'changed@example.com';
      update billingAccount;

      BillingAccount__c updated = [
        SELECT BillingEmailTo__c, ConfirmSharedUpdate__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      System.assertEquals('changed@example.com', updated.BillingEmailTo__c);
      System.assertEquals(false, updated.ConfirmSharedUpdate__c);
    }
  }

  @IsTest
  static void update_withOrderedUsage_requiresConfirm() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createOrderedBillingAccount();

      billingAccount.BillingEmailTo__c = 'blocked@example.com';
      try {
        update billingAccount;
        System.assert(false, '確認チェックなしの更新は失敗するべき');
      } catch (DmlException ex) {
        System.assert(
          ex.getMessage().contains('受注済み契約で使用中です'),
          ex.getMessage()
        );
      }
    }
  }

  @IsTest
  static void update_withOrderedUsage_andConfirm_succeedsAndClearsFlag() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createOrderedBillingAccount();

      billingAccount.BillingEmailTo__c = 'confirmed@example.com';
      billingAccount.ConfirmSharedUpdate__c = true;
      update billingAccount;

      BillingAccount__c updated = [
        SELECT BillingEmailTo__c, ConfirmSharedUpdate__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      System.assertEquals('confirmed@example.com', updated.BillingEmailTo__c);
      System.assertEquals(false, updated.ConfirmSharedUpdate__c);
    }
  }

  private static BillingAccount__c createBillingAccount(String name) {
    Account account = ContractTestDataFactory.insertAccount(name + ' Account');
    BillingAccount__c billingAccount = new BillingAccount__c(
      Name = name,
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      BillingEmailCc__c = 'cc@example.com',
      BillingEmailBcc__c = 'bcc@example.com',
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
      AdjustInvoiceDateToBusinessDay__c = false
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    return billingAccount;
  }

  private static BillingAccount__c createOrderedBillingAccount() {
    BillingAccount__c billingAccount = createBillingAccount('Ordered BA');
    ContractService__c service = new ContractService__c(
      Name = 'Ordered BA Service',
      Account__c = billingAccount.Account__c,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    insert service;

    // Cancel Ordered は請求生成をスキップするため、使用実績フラグ検証に使いやすい
    Date cancelDate = Date.newInstance(2026, 6, 1);
    insert new ContractHistory__c(
      Name = 'Ordered BA Cancel',
      ContractService__c = service.Id,
      Type__c = ContractDomainConstants.HISTORY_TYPE_CANCEL,
      historystatus__c = ContractDomainConstants.HISTORY_STATUS_ORDERED,
      Version__c = 1,
      CurrentTermStartDate__c = cancelDate,
      CurrentTermEndDate__c = cancelDate,
      EffectiveDate__c = cancelDate,
      ApplicationDate__c = cancelDate
    );
    return billingAccount;
  }
}
