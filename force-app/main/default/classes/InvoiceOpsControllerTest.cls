@IsTest
private class InvoiceOpsControllerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void markInvoicedAndExported_roundTrip() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Ops Account');
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_1,
        AdjustInvoiceDateToBusinessDay__c = false
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;

      ContractService__c service = new ContractService__c(
        Name = 'Ops Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = 0.1
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Ops History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 6, 30)
      );
      insert history;

      Invoice__c invoice = new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100
      );
      insert invoice;

      Test.startTest();
      List<InvoiceOpsController.InvoiceRowDto> rows = InvoiceOpsController.getInvoices(
        history.Id
      );
      System.assertEquals(1, rows.size());
      System.assertEquals(false, rows[0].locked);

      // 連携 → 消込（ロック中の除外項目更新）が通ること
      Integer invoiced = InvoiceOpsController.markInvoiced(
        new List<Id>{ invoice.Id },
        Date.today()
      );
      System.assertEquals(1, invoiced);
      Integer marked = InvoiceOpsController.markExported(
        new List<Id>{ invoice.Id },
        Date.today()
      );
      System.assertEquals(1, marked);
      Test.stopTest();

      Invoice__c reloaded = [
        SELECT
          SystemIntegrationDate__c,
          PaymentClearingCompletedDate__c,
          PaymentClearedAmount__c,
          Amount__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertNotEquals(null, reloaded.SystemIntegrationDate__c);
      System.assertNotEquals(null, reloaded.PaymentClearingCompletedDate__c);
      System.assertEquals(
        null,
        reloaded.PaymentClearedAmount__c,
        '消込日だけでは消込額を自動セットしない'
      );
      System.assertEquals(1000, reloaded.Amount__c);
    }
  }

  @IsTest
  static void clearExportDate_clearsDateOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Ops Clear Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
        PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
        BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_1,
        AdjustInvoiceDateToBusinessDay__c = false
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;

      ContractService__c service = new ContractService__c(
        Name = 'Ops Clear Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = 0.1
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Ops Clear History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 6, 30)
      );
      insert history;

      Invoice__c invoice = new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100,
        PaymentClearingCompletedDate__c = Date.today(),
        PaymentClearedAmount__c = 1000
      );
      insert invoice;

      Test.startTest();
      Integer cleared = InvoiceOpsController.clearExportDate(
        new List<Id>{ invoice.Id }
      );
      Test.stopTest();
      System.assertEquals(1, cleared);

      Invoice__c reloaded = [
        SELECT PaymentClearingCompletedDate__c, PaymentClearedAmount__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(null, reloaded.PaymentClearingCompletedDate__c);
      System.assertEquals(
        1000,
        reloaded.PaymentClearedAmount__c,
        '消込日クリアでも消込額は残す'
      );
    }
  }

  @IsTest
  static void clearExportDate_rejectsWhenInvoiced() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertOpsInvoice(
        'Ops Locked Clear',
        Date.today(),
        Date.today(),
        500
      );

      Boolean rejected = false;
      try {
        InvoiceOpsController.clearExportDate(new List<Id>{ invoice.Id });
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assertEquals(
          '連携済の請求の消込日はクリアできません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, rejected, '連携済請求の消込日クリアは拒否');
      Invoice__c unchanged = [
        SELECT
          SystemIntegrationDate__c,
          PaymentClearingCompletedDate__c,
          PaymentClearedAmount__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(Date.today(), unchanged.SystemIntegrationDate__c);
      System.assertEquals(
        Date.today(),
        unchanged.PaymentClearingCompletedDate__c,
        '拒否時は消込日が残る'
      );
      System.assertEquals(500, unchanged.PaymentClearedAmount__c);
    }
  }

  @IsTest
  static void getInvoices_marksLockedWhenIntegrationDateSet() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertOpsInvoice(
        'Ops Locked Dto',
        Date.today(),
        null,
        null
      );

      List<InvoiceOpsController.InvoiceRowDto> rows = InvoiceOpsController.getInvoices(
        invoice.ContractHistory__c
      );
      System.assertEquals(1, rows.size());
      System.assertEquals(true, rows[0].invoiced);
      System.assertEquals(true, rows[0].locked);
      System.assertEquals(Date.today(), rows[0].systemIntegrationDate);
    }
  }

  @IsTest
  static void getInvoices_returnsEmptyForUnknownHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      // 存在しないが形式は正しい Id（Account Id を流用して History ではない）
      Account account = ContractTestDataFactory.insertAccount('Ops Empty Hist');
      List<InvoiceOpsController.InvoiceRowDto> rows = InvoiceOpsController.getInvoices(
        account.Id
      );
      System.assertEquals(0, rows.size());
    }
  }

  @IsTest
  static void markInvoiced_emptyIds_returnsZero() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      System.assertEquals(
        0,
        InvoiceOpsController.markInvoiced(null, Date.today())
      );
      System.assertEquals(
        0,
        InvoiceOpsController.markInvoiced(new List<Id>(), Date.today())
      );
    }
  }

  @IsTest
  static void opsMethods_blockWithoutCustomPermission() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertOpsInvoice(
        'Ops Perm Deny',
        null,
        Date.today(),
        null
      );
      String denied =
        '請求の連携・消込操作を実行する権限がありません。';
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MANAGE_INVOICE_OPS => false
      };
      try {
        Boolean getBlocked = false;
        try {
          InvoiceOpsController.getInvoices(invoice.ContractHistory__c);
        } catch (AuraHandledException ex) {
          getBlocked = true;
          System.assertEquals(denied, ex.getMessage());
        }
        System.assertEquals(true, getBlocked, 'getInvoices は 13 必須');

        Boolean markBlocked = false;
        try {
          InvoiceOpsController.markInvoiced(
            new List<Id>{ invoice.Id },
            Date.today()
          );
        } catch (AuraHandledException ex) {
          markBlocked = true;
          System.assertEquals(denied, ex.getMessage());
        }
        System.assertEquals(true, markBlocked, 'markInvoiced は 13 必須');

        Boolean exportBlocked = false;
        try {
          InvoiceOpsController.markExported(
            new List<Id>{ invoice.Id },
            Date.today()
          );
        } catch (AuraHandledException ex) {
          exportBlocked = true;
          System.assertEquals(denied, ex.getMessage());
        }
        System.assertEquals(true, exportBlocked, 'markExported は 13 必須');

        Boolean clearBlocked = false;
        try {
          InvoiceOpsController.clearExportDate(new List<Id>{ invoice.Id });
        } catch (AuraHandledException ex) {
          clearBlocked = true;
          System.assertEquals(denied, ex.getMessage());
        }
        System.assertEquals(true, clearBlocked, 'clearExportDate は 13 必須');

        Invoice__c unchanged = [
          SELECT
            SystemIntegrationDate__c,
            PaymentClearingCompletedDate__c
          FROM Invoice__c
          WHERE Id = :invoice.Id
        ];
        System.assertEquals(
          null,
          unchanged.SystemIntegrationDate__c,
          '権限拒否後も連携日は付かない'
        );
        System.assertEquals(
          Date.today(),
          unchanged.PaymentClearingCompletedDate__c,
          '権限拒否後も消込日は消えない'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
    }
  }

  private static Invoice__c insertOpsInvoice(
    String label,
    Date integrationDate,
    Date clearingDate,
    Decimal clearedAmount
  ) {
    Account account = ContractTestDataFactory.insertAccount(label + ' Account');
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_1,
      AdjustInvoiceDateToBusinessDay__c = false
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;

    ContractService__c service = new ContractService__c(
      Name = label + ' Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;

    ContractHistory__c history = new ContractHistory__c(
      Name = label + ' History',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2026, 6, 30)
    );
    insert history;

    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = 100,
      SystemIntegrationDate__c = integrationDate,
      PaymentClearingCompletedDate__c = clearingDate,
      PaymentClearedAmount__c = clearedAmount
    );
    insert invoice;
    return invoice;
  }
}
