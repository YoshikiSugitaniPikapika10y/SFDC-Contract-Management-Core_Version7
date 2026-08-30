@IsTest
private class BillingAccountTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void update_withoutOrderedUsage_succeeds() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createBillingAccount('No Ordered BA');

      billingAccount.BillingEmailTo__c = 'changed@example.com';
      update billingAccount;

      BillingAccount__c updated = [
        SELECT BillingEmailTo__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      System.assertEquals('changed@example.com', updated.BillingEmailTo__c);
    }
  }

  @IsTest
  static void insert_blankKey_fillsEighteenDigitId() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createBillingAccount('Blank Key BA');

      BillingAccount__c stored = [
        SELECT BillingAccountKey__c, HasReference__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      System.assertEquals(String.valueOf(stored.Id), stored.BillingAccountKey__c);
      System.assertEquals(false, stored.HasReference__c);
    }
  }

  @IsTest
  static void insert_trimsProvidedKey() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Trim Key Acct');
      BillingAccount__c billingAccount = new BillingAccount__c(
        Name = 'Trim Key BA',
        Account__c = account.Id,
        BillingAccountKey__c = '  BA-TRIM-1  ',
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
              InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
              InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
              InvoiceDateDayOfMonth__c = 25,
              InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
        PaymentTermMonthOffset__c = 0,
        PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;

      BillingAccount__c stored = [
        SELECT BillingAccountKey__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      System.assertEquals('BA-TRIM-1', stored.BillingAccountKey__c);
    }
  }

  @IsTest
  static void update_rejectsKeyChange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createBillingAccount('Key Change BA');
      billingAccount.BillingAccountKey__c = 'CHANGED';
      Boolean thrown = false;
      try {
        update billingAccount;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains(BillingAccountKeyService.KEY_CHANGE_MESSAGE)
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void update_rejectsHasReferenceChange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createBillingAccount('HasRef Change BA');
      billingAccount.HasReference__c = true;
      Boolean thrown = false;
      try {
        update billingAccount;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(BillingAccountKeyService.HAS_REFERENCE_CHANGE_MESSAGE)
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void serviceInsert_setsHasReference() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createBillingAccount('HasRef Service BA');
      insert new ContractService__c(
        Name = 'HasRef Service',
        Account__c = billingAccount.Account__c,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );

      BillingAccount__c stored = [
        SELECT HasReference__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      System.assertEquals(true, stored.HasReference__c);
    }
  }

  @IsTest
  static void update_withOrderedUsage_succeedsWithoutConfirmGate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createOrderedBillingAccount();

      billingAccount.BillingEmailTo__c = 'confirmed@example.com';
      update billingAccount;

      BillingAccount__c updated = [
        SELECT BillingEmailTo__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      System.assertEquals('confirmed@example.com', updated.BillingEmailTo__c);
    }
  }

  @IsTest
  static void insert_rejectsExtraInvoiceDateFieldsForSameDay() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('SameDay Extra Account');
      BillingAccount__c billingAccount = new BillingAccount__c(
        Name = 'SameDay Extra',
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com'
      );
      ContractTestDataFactory.applySameDayBilling(billingAccount);
      ContractTestDataFactory.applyPaymentMonthEnd(billingAccount, 0);
      billingAccount.InvoiceDateDayOfMonth__c = 15;
      Boolean rejected = false;
      try {
        insert billingAccount;
      } catch (DmlException ex) {
        rejected = true;
        System.assert(
          ex.getMessage().contains('指定日'),
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        rejected,
        'Core 第7.2節: 入らない項目は空にする。入っている場合は保存時に拒否する'
      );
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
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 25,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
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
