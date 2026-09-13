@IsTest
private class ContractHistoryStatusPathServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  private static ContractService__c insertServiceWithBillingAccount(
    Account account
  ) {
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'path@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 25,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE
    );
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    ContractService__c service = new ContractService__c(
      Name = 'Status Path Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10),
      Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM
    );
    ContractTestDataFactory.applyRequiredFields(service);
    insert service;
    return service;
  }

  private static void insertHistory(ContractHistory__c history, Id accountId) {
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, accountId);
    insert history;
  }

  private static Invoice__c buildDraftInvoice(
    ContractService__c service,
    Id historyId,
    Date invoiceDate,
    Decimal amount
  ) {
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = historyId,
      InvoiceDate__c = invoiceDate,
      Amount__c = amount,
      TaxAmount__c = amount != null ? (amount / 10).setScale(0) : 0,
      BillingAccountSnapShot__c = service.BiilingAcccount__c
    );
    ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
    ContractTestDataFactory.applyRequiredFields(invoice);
    return invoice;
  }

  @IsTest
  static void statusPathValues_matchTransferredSpecification() {
    Schema.DescribeFieldResult pathDescribe = ContractHistory__c.StatusPath__c.getDescribe();
    Map<String, String> actualValuesAndLabels = new Map<String, String>();
    for (Schema.PicklistEntry entry : pathDescribe.getPicklistValues()) {
      if (entry.isActive()) {
        actualValuesAndLabels.put(entry.getValue(), entry.getLabel());
      }
    }

    System.assertEquals(
      true,
      pathDescribe.isRestrictedPicklist(),
      'Core 第5.7節: StatusPathは本文の5段階だけを許す'
    );
    System.assertEquals(
      new Map<String, String>{
        'Estimate' => '01_見積',
        'Ordered' => '02_受注',
        'Invoicing' => '03_請求対応中',
        'Invoiced' => '04_入金待ち',
        'Paid' => '05_入金完了'
      },
      actualValuesAndLabels,
      'Core 第5.7節: StatusPathの内部値と利用者向け表示を完全一致させる'
    );
    System.assertEquals(
      false,
      actualValuesAndLabels.containsKey('Archive'),
      'Core 第5.7節: Archiveは進捗表示の選択肢に含めない'
    );
  }

  @IsTest
  static void resolvePath_returnsEachSpecifiedProgressResult() {
    System.assertEquals(
      'Estimate',
      ContractHistoryStatusPathService.resolvePath('Estimate', 5, 5, 5),
      'Core 第5.7節: Estimateは請求件数にかかわらず見積'
    );
    System.assertEquals(
      'Ordered',
      ContractHistoryStatusPathService.resolvePath('Ordered', null, null, null),
      'Core 第5.7節: 受注済みで請求がなければ受注'
    );
    System.assertEquals(
      'Invoicing',
      ContractHistoryStatusPathService.resolvePath('Ordered', 2, 1, 1),
      'Core 第5.7節: 未確定の請求が残れば請求対応中'
    );
    System.assertEquals(
      'Invoiced',
      ContractHistoryStatusPathService.resolvePath('Ordered', 2, 2, 1),
      'Core 第5.7節: 全請求確定後も回収未完了があれば入金待ち'
    );
    System.assertEquals(
      'Paid',
      ContractHistoryStatusPathService.resolvePath('Ordered', 2, 2, 2),
      'Core 第5.7節: 全請求の回収・返金完了後は入金完了'
    );
    System.assertEquals(
      null,
      ContractHistoryStatusPathService.resolvePath('Archive', 5, 5, 5),
      'Core 第5.7節: Archiveは進捗を表示しない'
    );
    System.assertEquals(
      'Ordered',
      ContractHistoryStatusPathService.resolvePath(
        'Ordered',
        'Cancel',
        3,
        3,
        3
      ),
      'Core 第5.7節: 請求を作らないCancel受注は受注で完了する'
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
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insertHistory(history, account.Id);

      history = [
        SELECT StatusPath__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(
        'Estimate',
        history.StatusPath__c,
        'Core 第5.7節: 見積候補の Path は Estimate'
      );
    }
  }

  @IsTest
  static void invoiceLifecycle_advancesStatusPath() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      InvoiceTransactionStatusService.allowStatusWrite = true;
      InvoiceLockUtil.allowLockedStatusWrite = true;
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
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insertHistory(history, account.Id);

      history = [
        SELECT StatusPath__c, InvoiceCount__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(
        'Ordered',
        history.StatusPath__c,
        'Core 第5.7節: 受注済みで請求がまだ無い Path は Ordered'
      );

      Invoice__c inv1 = buildDraftInvoice(
        service,
        history.Id,
        Date.newInstance(2026, 6, 1),
        1000
      );
      Invoice__c inv2 = buildDraftInvoice(
        service,
        history.Id,
        Date.newInstance(2026, 7, 1),
        1000
      );
      ContractTestDataFactory.insertAllowingInvoiceStatus(
        new List<Invoice__c>{ inv1, inv2 }
      );

      history = [
        SELECT StatusPath__c, InvoiceCount__c, InvoicedCount__c, PaidCount__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(2, history.InvoiceCount__c);
      System.assertEquals(
        'Invoicing',
        history.StatusPath__c,
        'Core 第5.7節: 未確定の請求が残れば Invoicing'
      );

      inv1.SystemIntegrationDate__c = Date.today();
      inv1.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      update inv1;

      history = [
        SELECT StatusPath__c, InvoicedCount__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(1, history.InvoicedCount__c);
      System.assertEquals(
        'Invoicing',
        history.StatusPath__c,
        'Core 第5.7節: 未確定が1件以上残れば Invoicing に留める'
      );

      inv2.SystemIntegrationDate__c = Date.today();
      inv2.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      update inv2;

      history = [
        SELECT StatusPath__c, InvoicedCount__c, PaidCount__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(2, history.InvoicedCount__c);
      System.assertEquals(
        'Invoiced',
        history.StatusPath__c,
        'Core 第5.7節: 全請求が確定済みで回収未完了なら Invoiced（入金待ち）'
      );

      inv1.PaymentClearingCompletedDate__c = Date.today();
      inv1.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      inv1.CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_COMPLETED;
      update inv1;

      history = [
        SELECT StatusPath__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(
        'Invoiced',
        history.StatusPath__c,
        'Core 第5.7節: 回収未完了の請求が残れば Invoiced に留める'
      );

      inv2.PaymentClearingCompletedDate__c = Date.today();
      inv2.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      inv2.CollectionRefundStatus__c = InvoiceTransactionStatusService.COLLECTION_COMPLETED;
      update inv2;

      history = [
        SELECT StatusPath__c, PaidCount__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(2, history.PaidCount__c);
      System.assertEquals(
        'Paid',
        history.StatusPath__c,
        'Core 第5.7節: 取消済みを除く全請求の回収・返金が完了なら Paid'
      );
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
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insertHistory(history, account.Id);
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
        'Core 第5.7節: Archive は進捗表示の対象外で Path は null'
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
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insertHistory(history, account.Id);
      Invoice__c invoice = buildDraftInvoice(
        service,
        history.Id,
        Date.newInstance(2026, 6, 1),
        1000
      );
      ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
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
        'Core 第5.7節: 請求削除後に請求が無ければ Path は Ordered'
      );
    }
  }

  @IsTest
  static void manualStatusPathChange_allowsNoChangeAndBlocksOtherResults() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Path Block Account'
      );
      ContractService__c service = insertServiceWithBillingAccount(account);

      List<String> attemptedValues = new List<String>{
        'Estimate',
        'Ordered',
        'Invoicing',
        'Invoiced',
        'Paid',
        null
      };
      List<ContractHistory__c> histories = new List<ContractHistory__c>();
      for (Integer i = 0; i < attemptedValues.size(); i++) {
        ContractHistory__c history = new ContractHistory__c(
          Name = 'Path Block ' + i,
          ContractService__c = service.Id,
          Type__c = 'New',
          historystatus__c = 'Estimate',
          Version__c = 1,
          CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
          CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
          EffectiveDate__c = Date.newInstance(2026, 6, 1)
        );
        insertHistory(history, account.Id);
        history.StatusPath__c = attemptedValues[i];
        histories.add(history);
      }

      Database.SaveResult[] results = Database.update(histories, false);
      System.assertEquals(
        true,
        results[0].isSuccess(),
        'Core 第5.7節: 自動計算値と同じ値なら直接変更には当たらない'
      );
      for (Integer i = 1; i < results.size(); i++) {
        System.assertEquals(
          false,
          results[i].isSuccess(),
          'Core 第5.7節: 利用者はStatusPathを別結果へ直接変更できない: ' +
          String.valueOf(attemptedValues[i])
        );
      }

      Set<Id> historyIds = new Map<Id, ContractHistory__c>(histories).keySet();
      List<ContractHistory__c> persisted = [
        SELECT StatusPath__c
        FROM ContractHistory__c
        WHERE Id IN :historyIds
      ];
      System.assertEquals(histories.size(), persisted.size());
      for (ContractHistory__c history : persisted) {
        System.assertEquals(
          'Estimate',
          history.StatusPath__c,
          'Core 第5.7節・第12.4節: 拒否された直接変更を一部も残さない'
        );
      }
    }
  }
}
