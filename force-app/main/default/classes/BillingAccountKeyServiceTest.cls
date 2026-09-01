@IsTest
private class BillingAccountKeyServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void assignOnInsert_trimsKey() {
    BillingAccount__c account = new BillingAccount__c(
      BillingAccountKey__c = '  BA-TRIM  '
    );
    BillingAccountKeyService.assignOnInsert(
      new List<BillingAccount__c>{ account }
    );
    System.assertEquals(
      'BA-TRIM',
      account.BillingAccountKey__c,
      'Core 第3.3.1節: 保存時に前後空白を除く'
    );
  }

  @IsTest
  static void rejectKeyChange_blocksOnceSet() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c stored = insertBillingAccount('Reject Key BA');
      BillingAccount__c next = new BillingAccount__c(
        Id = stored.Id,
        BillingAccountKey__c = 'CHANGED'
      );
      BillingAccountKeyService.rejectKeyChange(
        new List<BillingAccount__c>{ next },
        new Map<Id, BillingAccount__c>{ stored.Id => stored }
      );
      System.assertEquals(
        true,
        next.hasErrors(),
        'Core 第3.3.1節: 一度入ったキーは変更しない'
      );
    }
  }

  @IsTest
  static void contractServiceInsert_setsHasReferenceTrue() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c stored = insertBillingAccount('HasRef BA');
      System.assertEquals(
        false,
        stored.HasReference__c,
        'Core 第3.3.3節: 参照0件なら OFF'
      );
      Account account = [
        SELECT Id
        FROM Account
        WHERE Id = :stored.Account__c
      ];
      ContractService__c service = new ContractService__c(
        Name = 'HasRef Service',
        Account__c = account.Id,
        BiilingAcccount__c = stored.Id
      );
      ContractTestDataFactory.applyRequiredFields(service);
      Test.startTest();
      insert service;
      Test.stopTest();
      BillingAccount__c afterInsert = [
        SELECT HasReference__c
        FROM BillingAccount__c
        WHERE Id = :stored.Id
      ];
      System.assertEquals(
        true,
        afterInsert.HasReference__c,
        'Core 第3.3.3節: 契約サービスから1件でも参照していれば ON'
      );
    }
  }

  private static BillingAccount__c insertBillingAccount(String name) {
    Account account = ContractTestDataFactory.insertAccount(name + ' Account');
    BillingAccount__c billingAccount = new BillingAccount__c(
      Name = name,
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'key@example.com',
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
    return [
      SELECT Id, BillingAccountKey__c, HasReference__c
      FROM BillingAccount__c
      WHERE Id = :billingAccount.Id
    ];
  }
}
