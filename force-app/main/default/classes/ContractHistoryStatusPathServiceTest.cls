@IsTest
private class ContractHistoryStatusPathServiceTest {
  private static ContractService__c insertServiceWithBillingAccount(
    Account account
  ) {
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'path@example.com',
      PaymentTerm__c = ContractTestDataFactory.TENANT_PAYMENT_TERM_MONTH_END,
      BillingDayOfMonth__c = ContractTestDataFactory.TENANT_BILLING_DAY_25,
      AdjustInvoiceDateToBusinessDay__c = false
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    ContractService__c service = new ContractService__c(
      Name = 'Status Path Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id
    );
    insert service;
    return service;
  }

  @IsTest
  static void resolvePath_coversEstimateOrderedInvoicingInvoicedPaidArchive() {
    System.assertEquals(
      'Estimate',
      ContractHistoryStatusPathService.resolvePath('Estimate', 0, 0, 0)
    );
    System.assertEquals(
      'Ordered',
      ContractHistoryStatusPathService.resolvePath('Ordered', 0, 0, 0)
    );
    System.assertEquals(
      'Invoicing',
      ContractHistoryStatusPathService.resolvePath('Ordered', 2, 1, 0)
    );
    System.assertEquals(
      'Invoiced',
      ContractHistoryStatusPathService.resolvePath('Ordered', 2, 2, 1)
    );
    System.assertEquals(
      'Paid',
      ContractHistoryStatusPathService.resolvePath('Ordered', 2, 2, 2)
    );
    System.assertEquals(
      null,
      ContractHistoryStatusPathService.resolvePath('Archive', 5, 5, 5)
    );
  }

  @IsTest
  static void insertEstimate_setsStatusPathEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Path Estimate Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(account);

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Path Estimate',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1
      );
      insert history;

      history = [
        SELECT StatusPath__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Estimate', history.StatusPath__c);
    }
  }

  @IsTest
  static void invoiceLifecycle_advancesStatusPath() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Path Invoice Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(account);

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Path Ordered',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        ApplicationDate__c = Date.today(),
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
      );
      insert history;

      history = [
        SELECT StatusPath__c, InvoiceCount__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Ordered', history.StatusPath__c);

      Invoice__c inv1 = new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100
      );
      Invoice__c inv2 = new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2026, 7, 1),
        Amount__c = 1000,
        TaxAmount__c = 100
      );
      insert new List<Invoice__c>{ inv1, inv2 };

      history = [
        SELECT StatusPath__c, InvoiceCount__c, InvoicedCount__c, PaidCount__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(2, history.InvoiceCount__c);
      System.assertEquals('Invoicing', history.StatusPath__c);

      inv1.SystemIntegrationDate__c = Date.today();
      update inv1;

      history = [
        SELECT StatusPath__c, InvoicedCount__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(1, history.InvoicedCount__c);
      System.assertEquals('Invoicing', history.StatusPath__c);

      inv2.SystemIntegrationDate__c = Date.today();
      update inv2;

      history = [
        SELECT StatusPath__c, InvoicedCount__c, PaidCount__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(2, history.InvoicedCount__c);
      System.assertEquals('Invoiced', history.StatusPath__c);

      inv1.PaymentClearingCompletedDate__c = Date.today();
      update inv1;

      history = [
        SELECT StatusPath__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Invoiced', history.StatusPath__c);

      inv2.PaymentClearingCompletedDate__c = Date.today();
      update inv2;

      history = [
        SELECT StatusPath__c, PaidCount__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(2, history.PaidCount__c);
      System.assertEquals('Paid', history.StatusPath__c);
    }
  }

  @IsTest
  static void archiveHistory_clearsStatusPathToNull() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Path Archive Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(account);
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Path Archive',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1
      );
      insert history;
      history.historystatus__c = 'Archive';
      update history;

      history = [
        SELECT StatusPath__c, historystatus__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Archive', history.historystatus__c);
      System.assertEquals(
        null,
        history.StatusPath__c,
        'Archive は Path 本線外（null）'
      );
    }
  }

  @IsTest
  static void invoiceDelete_rollsStatusPathBackToOrdered() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Path Invoice Delete Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(account);
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Path Invoice Delete',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        ApplicationDate__c = Date.today(),
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31)
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
      history = [
        SELECT StatusPath__c, InvoiceCount__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Invoicing', history.StatusPath__c);
      System.assertEquals(1, history.InvoiceCount__c);

      delete invoice;

      history = [
        SELECT StatusPath__c, InvoiceCount__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(0, history.InvoiceCount__c);
      System.assertEquals(
        'Ordered',
        history.StatusPath__c,
        '請求削除で Path は Ordered に戻る'
      );
    }
  }

  @IsTest
  static void manualStatusPathChange_isBlocked() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Path Block Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(account);

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Path Block',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1
      );
      insert history;

      Boolean thrown = false;
      String message = null;
      try {
        history.StatusPath__c = 'Paid';
        update history;
      } catch (DmlException e) {
        thrown = true;
        message = e.getNumDml() > 0 ? e.getDmlMessage(0) : e.getMessage();
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        ContractHistoryStatusPathService.MANUAL_CHANGE_BLOCK_MESSAGE,
        message
      );
      ContractHistory__c still = [
        SELECT StatusPath__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertNotEquals(
        'Paid',
        still.StatusPath__c,
        '手動変更拒否時は StatusPath が変わらない'
      );
    }
  }
}
