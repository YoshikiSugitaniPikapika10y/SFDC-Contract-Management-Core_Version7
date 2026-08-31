@IsTest
private class InvoiceOpsControllerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void markInvoiced_roundTrip() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Account account = ContractTestDataFactory.insertAccount('Ops Account');
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
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

      Product2 product = ContractTestDataFactory.buildProduct('Ops Prod');
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c contractProduct = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Account__c = account.Id,
        Product__c = product.Id,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30)
      );
      ContractTestDataFactory.applyRequiredFields(contractProduct);
      insert contractProduct;

      Invoice__c invoice = new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert invoice;
      insert new InvoiceLine__c(Invoice__c = invoice.Id, Amount__c = 1000);

      Test.startTest();
      Integer invoiced = InvoiceOpsController.markInvoiced(
        history.Id,
        new List<Id>{ invoice.Id },
        Date.today()
      );
      System.assertEquals(1, invoiced);
      Test.stopTest();

      Invoice__c reloaded = [
        SELECT
          SystemIntegrationDate__c,
          PaymentClearingCompletedDate__c,
          CollectionRefundStatus__c,
          Amount__c,
          AppliedTaxRoundingMode__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertNotEquals(null, reloaded.SystemIntegrationDate__c);
      System.assertEquals(
        null,
        reloaded.PaymentClearingCompletedDate__c,
        'Core 第7.11節: 請求金額Netと税込が不一致なら完了日を書かない'
      );
      System.assertEquals(
        InvoiceTransactionStatusService.COLLECTION_NOT_STARTED,
        reloaded.CollectionRefundStatus__c,
        'Core 第7.11節: 0件かつ不一致は未対応。Completedへ直書きしない'
      );
      System.assertEquals(1000, reloaded.Amount__c);
      System.assertEquals('DOWN', reloaded.AppliedTaxRoundingMode__c);
      System.assertEquals(
        100,
        [
          SELECT AllocatedTaxAmount__c
          FROM InvoiceLine__c
          WHERE Invoice__c = :invoice.Id
        ]
        .AllocatedTaxAmount__c
      );
    }
  }

  @IsTest
  static void updateInvoiceMemo_writesMemoOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Memo Account');
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'memo@example.com',
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
      ContractService__c service = new ContractService__c(
        Name = 'Memo Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = 0.1
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1
      );
      ContractTestDataFactory.applyRequiredFields(history);
      insert history;
      Invoice__c invoice = new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.today(),
        Amount__c = 1000,
        TaxAmount__c = 100,
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT
      );
      ContractTestDataFactory.applyRequiredFields(invoice);
      insert invoice;

      InvoiceOpsController.updateInvoiceMemo(invoice.Id, '??E???');
      Invoice__c stored = [
        SELECT Memo__c, Amount__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals('??E???', stored.Memo__c);
      System.assertEquals(1000, stored.Amount__c);
    }
  }

  @IsTest
  static void updateInvoiceMemo_withoutEditPermission_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.EDIT_DRAFT_INVOICE => false
      };
      Boolean thrown = false;
      try {
        InvoiceOpsController.updateInvoiceMemo(
          UserInfo.getUserId(),
          'x',
          UserInfo.getUserId()
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '未確定請求を直す権限がありません。',
          ex.getMessage(),
          '共通基盤 第3.2節・第10.4節: 請求書メモ保存は 10'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void updateInvoiceMemo_rejectsInvoiceOutsideContractService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c own = insertOpsInvoice('Memo Scope Own', null, null, null);
      Invoice__c other = insertOpsInvoice('Memo Scope Other', null, null, null);

      Boolean rejected = false;
      try {
        InvoiceOpsController.updateInvoiceMemo(
          other.Id,
          '他契約サービス',
          own.ContractHistory__c
        );
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        rejected,
        'Core 第7.7.3節: 契約サービスをまたいで請求書メモを書けない'
      );
      System.assertEquals(
        null,
        [SELECT Memo__c FROM Invoice__c WHERE Id = :other.Id].Memo__c
      );

      InvoiceOpsController.updateInvoiceMemo(
        own.Id,
        '同一契約サービス',
        own.ContractHistory__c
      );
      System.assertEquals(
        '同一契約サービス',
        [SELECT Memo__c FROM Invoice__c WHERE Id = :own.Id].Memo__c
      );
    }
  }

  @IsTest
  static void markInvoiced_rejectsWrongPerInvoiceTax() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertOpsInvoice('Wrong Tax', null, null, null);
      insert new InvoiceLine__c(Invoice__c = invoice.Id, Amount__c = 1000);
      invoice.TaxAmount__c = 99;
      update invoice;

      Boolean rejected = false;
      try {
        InvoiceOpsController.markInvoiced(
          invoice.ContractHistory__c,
          new List<Id>{ invoice.Id },
          Date.today()
        );
      } catch (AuraHandledException ex) {
        rejected = ex.getMessage().contains('??');
      }
      System.assertEquals(true, rejected);
      System.assertEquals(
        null,
        [
          SELECT SystemIntegrationDate__c
          FROM Invoice__c
          WHERE Id = :invoice.Id
        ]
        .SystemIntegrationDate__c
      );
    }
  }

  @IsTest
  static void markInvoiced_freezesPolicyBeforeConfirmed() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertOpsInvoice('Freeze First', null, null, null);
      insert new InvoiceLine__c(Invoice__c = invoice.Id, Amount__c = 1000);

      Test.startTest();
      InvoiceOpsController.markInvoiced(
        invoice.ContractHistory__c,
        new List<Id>{ invoice.Id },
        Date.today()
      );
      Test.stopTest();

      GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
      System.assertNotEquals(
        null,
        policy.FrozenAt__c,
        'Accounting 第3.1節: 最初の確定と同じTXで方針を固定する'
      );
      System.assertEquals(
        InvoiceTransactionStatusService.TX_CONFIRMED,
        [
          SELECT InvoiceTransactionStatus__c
          FROM Invoice__c
          WHERE Id = :invoice.Id
        ]
        .InvoiceTransactionStatus__c
      );
    }
  }

  @IsTest
  static void markInvoiced_rejectsMissingPolicyWithoutConfirming() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertOpsInvoice('No Policy', null, null, null);
      insert new InvoiceLine__c(Invoice__c = invoice.Id, Amount__c = 1000);

      Boolean thrown = false;
      try {
        InvoiceOpsController.markInvoiced(
          invoice.ContractHistory__c,
          new List<Id>{ invoice.Id },
          Date.today()
        );
      } catch (Exception ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('Accounting会計方針がありません'),
          'Core 第1.1.10節: 方針0件をOrgDefaultで埋めない'
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        InvoiceTransactionStatusService.TX_DRAFT,
        [
          SELECT InvoiceTransactionStatus__c
          FROM Invoice__c
          WHERE Id = :invoice.Id
        ]
        .InvoiceTransactionStatus__c,
        'Accounting 第3.1節: 固定できない確定は保存しない'
      );
      System.assertEquals(0, [SELECT COUNT() FROM GlAccountingPolicy__c]);
    }
  }

  @IsTest
  static void markInvoiced_emptyIds_returnsZero() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      System.assertEquals(
        0,
        InvoiceOpsController.markInvoiced(null, null, Date.today())
      );
      System.assertEquals(
        0,
        InvoiceOpsController.markInvoiced(null, new List<Id>(), Date.today())
      );
    }
  }

  @IsTest
  static void opsMethods_rejectInvoiceOutsideContractService() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c own = insertOpsInvoice('Ops Scope Own', null, null, null);
      Invoice__c other = insertOpsInvoice('Ops Scope Other', null, null, null);

      Boolean rejected = false;
      try {
        InvoiceOpsController.markInvoiced(
          own.ContractHistory__c,
          new List<Id>{ other.Id },
          Date.today()
        );
      } catch (AuraHandledException ex) {
        rejected = true;
        System.assertEquals(
          InvoiceOpsController.SCOPE_MISMATCH_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, rejected, 'Core 第7.7.3節: 契約サービス外の請求は確定できない');

      System.assertEquals(
        null,
        [
          SELECT SystemIntegrationDate__c
          FROM Invoice__c
          WHERE Id = :other.Id
        ]
        .SystemIntegrationDate__c
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
      String denied = '請求を確定する権限がありません。';
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.CONFIRM_INVOICE => false
      };
      try {
        Boolean markBlocked = false;
        try {
          InvoiceOpsController.markInvoiced(
            invoice.ContractHistory__c,
            new List<Id>{ invoice.Id },
            Date.today()
          );
        } catch (AuraHandledException ex) {
          markBlocked = true;
          System.assertEquals(denied, ex.getMessage());
        }
        System.assertEquals(true, markBlocked, 'markInvoiced ? 13 ?E??E');

        Invoice__c unchanged = [
          SELECT SystemIntegrationDate__c, PaymentClearingCompletedDate__c
          FROM Invoice__c
          WHERE Id = :invoice.Id
        ];
        System.assertEquals(
          null,
          unchanged.SystemIntegrationDate__c,
          '??????????????E'
        );
        System.assertEquals(
          Date.today(),
          unchanged.PaymentClearingCompletedDate__c,
          '??????????????E'
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

    Product2 product = ContractTestDataFactory.buildProduct(label + ' Prod');
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Account__c = account.Id,
      Product__c = product.Id,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Amount__c = 1000,
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2026, 6, 30)
    );
    ContractTestDataFactory.applyRequiredFields(contractProduct);
    insert contractProduct;

    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = 100,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10),
      InvoiceTransactionStatus__c = integrationDate != null
        ? InvoiceTransactionStatusService.TX_CONFIRMED
        : InvoiceTransactionStatusService.TX_DRAFT,
      CollectionRefundStatus__c = clearingDate != null
        ? InvoiceTransactionStatusService.COLLECTION_COMPLETED
        : null,
      SystemIntegrationDate__c = integrationDate,
      PaymentClearingCompletedDate__c = clearingDate
    );
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    return invoice;
  }
}
