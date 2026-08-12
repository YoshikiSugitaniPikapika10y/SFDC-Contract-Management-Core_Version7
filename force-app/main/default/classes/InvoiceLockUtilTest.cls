@IsTest
private class InvoiceLockUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void lockHelpers_andAsserts() {
    Invoice__c unlocked = new Invoice__c();
    System.assertEquals(false, InvoiceLockUtil.isLocked(unlocked));
    System.assertEquals(false, InvoiceLockUtil.isInvoiced(unlocked));
    System.assertEquals(false, InvoiceLockUtil.isExported(unlocked));

    Invoice__c invoiced = new Invoice__c(SystemIntegrationDate__c = Date.today());
    System.assertEquals(true, InvoiceLockUtil.isInvoiced(invoiced));
    System.assertEquals(true, InvoiceLockUtil.isLocked(invoiced));

    Invoice__c exported = new Invoice__c(
      PaymentClearingCompletedDate__c = Date.today()
    );
    System.assertEquals(true, InvoiceLockUtil.isExported(exported));
    System.assertEquals(true, InvoiceLockUtil.isLocked(exported));

    Id fakeInvoiceId = Invoice__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000002AAA';
    Invoice__c priorLocked = new Invoice__c(
      Id = fakeInvoiceId,
      Amount__c = 1000,
      SystemIntegrationDate__c = Date.today(),
      PaymentClearedAmount__c = null
    );
    Invoice__c paymentOnly = new Invoice__c(
      Id = fakeInvoiceId,
      SystemIntegrationDate__c = Date.today(),
      PaymentClearedAmount__c = 400
    );
    InvoiceLockUtil.testCanBypassLockedDml = false;
    InvoiceLockUtil.testLockExemptFieldApiNames = null;
    InvoiceLockUtil.blockLockedRowDml(
      new List<Invoice__c>{ paymentOnly },
      new Map<Id, Invoice__c>{ fakeInvoiceId => priorLocked }
    );
    System.assertEquals(
      false,
      paymentOnly.hasErrors(),
      'ロック中の入金消込額のみ更新は許可'
    );

    Invoice__c amountChange = new Invoice__c(
      Id = fakeInvoiceId,
      Amount__c = 2000,
      SystemIntegrationDate__c = Date.today()
    );
    InvoiceLockUtil.blockLockedRowDml(
      new List<Invoice__c>{ amountChange },
      new Map<Id, Invoice__c>{ fakeInvoiceId => priorLocked }
    );
    System.assertEquals(
      true,
      amountChange.hasErrors(),
      '除外リスト外の金額変更は拒否'
    );

    InvoiceLockUtil.testCanBypassLockedDml = true;
    System.assertEquals(true, InvoiceLockUtil.canBypassLockedDml());
    InvoiceLockUtil.testCanBypassLockedDml = false;
    System.assertEquals(false, InvoiceLockUtil.canBypassLockedDml());
    InvoiceLockUtil.testCanBypassLockedDml = null;

    Invoice__c row = new Invoice__c();
    InvoiceLockUtil.testCanBypassLockedDml = false;
    InvoiceLockUtil.blockLockedRowDml(
      new List<Invoice__c>{ row },
      new Map<Id, Invoice__c>{
        UserInfo.getUserId() => new Invoice__c(
          SystemIntegrationDate__c = Date.today()
        )
      }
    );
    // oldMap に無い ID のときは自身で判定（未ロック）
    InvoiceLockUtil.blockLockedRowDml(new List<Invoice__c>{ row }, null);

    InvoiceLockUtil.assertNoLockedInvoices(new Set<Id>());
    System.assertEquals(
      false,
      InvoiceLockUtil.hasLockedInvoices(new Set<Id>())
    );

    Set<String> defaults = InvoiceLockUtil.resolveLockExemptFieldNames();
    System.assertEquals(true, defaults.contains('PaymentClearedAmount__c'));
    System.assertEquals(
      true,
      defaults.contains('PaymentClearingCompletedDate__c')
    );
  }

  @IsTest
  static void assertVersionEditable_blocksWhenInvoiceLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Lock Util Account');
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
        Name = 'Lock Util Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = 0.1
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Lock Util History',
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
        SystemIntegrationDate__c = Date.today()
      );
      insert invoice;

      Boolean thrown = false;
      try {
        InvoiceLockUtil.assertVersionEditable(history.Id);
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.VERSION_EDIT_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);

      thrown = false;
      try {
        InvoiceLockUtil.assertNoLockedInvoices(new Set<Id>{ history.Id });
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        true,
        InvoiceLockUtil.hasLockedInvoices(new Set<Id>{ history.Id })
      );

      InvoiceLockUtil.testCanBypassLockedDml = false;
      Invoice__c lockedUpdate = [
        SELECT Id, Amount__c, SystemIntegrationDate__c, PaymentClearingCompletedDate__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      lockedUpdate.Amount__c = 2000;
      Database.SaveResult[] results = Database.update(
        new List<Invoice__c>{ lockedUpdate },
        false
      );
      System.assertEquals(false, results[0].isSuccess());

      Boolean invoiceThrown = false;
      try {
        InvoiceLockUtil.assertInvoiceEditable(invoice.Id);
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        invoiceThrown = true;
        System.assertEquals(
          InvoiceLockUtil.INVOICE_EDIT_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, invoiceThrown, 'ロック請求は編集不可');

      Invoice__c unlockedSibling = new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2026, 7, 1),
        Amount__c = 500,
        TaxAmount__c = 50
      );
      insert unlockedSibling;
      InvoiceLockUtil.assertInvoiceEditable(unlockedSibling.Id);
      InvoiceLockUtil.assertInvoicesEditable(new Set<Id>{ unlockedSibling.Id });

      Database.DeleteResult[] lockedDelete = Database.delete(
        new List<Invoice__c>{ invoice },
        false
      );
      System.assertEquals(
        false,
        lockedDelete[0].isSuccess(),
        'ロック請求の削除は拒否'
      );

      delete unlockedSibling;
    }
  }

  @IsTest
  static void blockLockedRowDml_allowsClearingExportWhenNotIntegrated() {
    Id fakeInvoiceId = Invoice__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000003AAA';
    Invoice__c priorExportedOnly = new Invoice__c(
      Id = fakeInvoiceId,
      SystemIntegrationDate__c = null,
      PaymentClearingCompletedDate__c = Date.today()
    );
    Invoice__c clearExport = new Invoice__c(
      Id = fakeInvoiceId,
      SystemIntegrationDate__c = null,
      PaymentClearingCompletedDate__c = null
    );

    InvoiceLockUtil.testCanBypassLockedDml = false;
    InvoiceLockUtil.blockLockedRowDml(
      new List<Invoice__c>{ clearExport },
      new Map<Id, Invoice__c>{ fakeInvoiceId => priorExportedOnly }
    );
    System.assertEquals(
      false,
      clearExport.hasErrors(),
      '連携未済の消込完了日クリアは許可'
    );
  }

  @IsTest
  static void resolveLockExemptFieldNames_honorsTestOverride() {
    InvoiceLockUtil.testLockExemptFieldApiNames = 'Amount__c, TaxAmount__c';
    Set<String> names = InvoiceLockUtil.resolveLockExemptFieldNames();
    System.assertEquals(true, names.contains('Amount__c'));
    System.assertEquals(true, names.contains('TaxAmount__c'));
    System.assertEquals(false, names.contains('PaymentClearedAmount__c'));

    InvoiceLockUtil.testLockExemptFieldApiNames = ' , Amount__c ,  ';
    names = InvoiceLockUtil.resolveLockExemptFieldNames();
    System.assertEquals(new Set<String>{ 'Amount__c' }, names);

    InvoiceLockUtil.testLockExemptFieldApiNames = null;
  }

  @IsTest
  static void assertNoLockedInvoices_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Lock Message Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Lock Message Service'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Lock Message History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 6, 30)
      );
      insert history;
      insert new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100,
        PaymentClearingCompletedDate__c = Date.today()
      );

      InvoiceLockUtil.testCanBypassLockedDml = false;
      Boolean thrown = false;
      try {
        InvoiceLockUtil.assertNoLockedInvoices(new Set<Id>{ history.Id });
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.LOCKED_HISTORY_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);

      thrown = false;
      try {
        InvoiceLockUtil.assertVersionEditable(history.Id);
      } catch (InvoiceLockUtil.InvoiceLockException ex) {
        thrown = true;
        System.assertEquals(
          InvoiceLockUtil.VERSION_EDIT_BLOCK_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void nullInvoice_helpersReturnFalseAndSkipAsserts() {
    System.assertEquals(false, InvoiceLockUtil.isLocked(null));
    System.assertEquals(false, InvoiceLockUtil.isInvoiced(null));
    System.assertEquals(false, InvoiceLockUtil.isExported(null));
    InvoiceLockUtil.assertInvoiceEditable((Id) null);
    InvoiceLockUtil.assertInvoiceEditable((Invoice__c) null);
    InvoiceLockUtil.assertVersionEditable(null);
    InvoiceLockUtil.assertInvoicesEditable(null);
    InvoiceLockUtil.assertInvoicesEditable(new Set<Id>());
    System.assertEquals(
      true,
      InvoiceLockUtil.queryHistoryIdsWithLockedInvoices(null).isEmpty()
    );
  }

  @IsTest
  static void invoiceProductUpdate_allowedWhenParentInvoiceLocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Period Line Lock Abolish Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Period Line Lock Abolish Service'
      );
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Period Line Lock Abolish History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2026, 6, 30)
      );
      insert history;
      Product2 product = ContractTestDataFactory.buildProduct(
        'Period Line Lock Abolish Product'
      );
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c cp = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      );
      insert cp;
      String bucket = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
        null,
        history.Id,
        Date.newInstance(2026, 6, 1),
        null
      );
      InvoiceProduct__c periodLine = new InvoiceProduct__c(
        ContractHistory__c = history.Id,
        ContractProduct__c = cp.Id,
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30),
        InvoiceBucketKey__c = bucket,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000
      );
      insert periodLine;
      insert new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100,
        SystemIntegrationDate__c = Date.today()
      );

      periodLine.Amount__c = 1100;
      update periodLine;

      System.assertEquals(
        1100,
        [
          SELECT Amount__c
          FROM InvoiceProduct__c
          WHERE Id = :periodLine.Id
        ]
        .Amount__c,
        '期間明細ロック廃止: 請求ロックでも期間明細更新は拒否されない'
      );
    }
  }
}
