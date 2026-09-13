@IsTest
private class ContractServiceTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  private static ContractService__c insertService(Id accountId, String name) {
    return ContractTestDataFactory.insertContractService(accountId, name);
  }

  private static ContractHistory__c insertEstimateHistory(
    Id serviceId,
    Id accountId,
    String name,
    String historyType,
    Decimal version,
    Date termStart,
    Date termEnd
  ) {
    ContractHistory__c history = new ContractHistory__c(
      Name = name,
      ContractService__c = serviceId,
      Type__c = historyType,
      historystatus__c = 'Estimate',
      Version__c = version,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = termStart
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, accountId);
    insert history;
    return history;
  }

  private static void insertRecurringLine(
    Id historyId,
    Id accountId,
    String productName,
    Date termStart,
    Date termEnd
  ) {
    Product2 product = ContractTestDataFactory.buildProduct(productName);
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c line = new ContractProduct__c(
      ContractHistory__c = historyId,
      Account__c = accountId,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Amount__c = 96000,
      StartDate__c = termStart,
      Enddate__c = termEnd,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = 'New',
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
    );
    ContractTestDataFactory.applyRequiredFields(line);
    insert line;
  }

  private static void orderHistory(ContractHistory__c history) {
    history.historystatus__c = 'Ordered';
    update history;
  }

  @IsTest
  static void collectBillingAccountIds_returnsDistinctCurrentAndPriorReferences() {
    System.assertEquals(
      new Set<Id>(),
      ContractServiceTriggerHandler.collectBillingAccountIds(null, null),
      'Core 第3.3.3節: 入力が無いときは参照更新対象も無い'
    );

    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'CS Collect Billing Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'CS Collect Service'
      );
      ContractService__c prior = [
        SELECT Id, BiilingAcccount__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      BillingAccount__c replacement = ContractTestDataFactory.insertBillingAccount(
        account.Id
      );
      ContractService__c current = prior.clone(true, false, false, false);
      current.BiilingAcccount__c = replacement.Id;

      Set<Id> actual = ContractServiceTriggerHandler.collectBillingAccountIds(
        new List<ContractService__c>{ null, current, current },
        new Map<Id, ContractService__c>{ prior.Id => prior }
      );

      System.assertEquals(
        new Set<Id>{ prior.BiilingAcccount__c, replacement.Id },
        actual,
        'Core 第3.3.3節: 付け替えでは旧参照と新参照を重複なく再判定する'
      );
    }
  }

  @IsTest
  static void afterUpdate_refreshesOldAndNewBillingAccountReferenceFlags() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'CS Refresh Billing Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'CS Refresh Service'
      );
      Id priorBillingAccountId = service.BiilingAcccount__c;
      BillingAccount__c replacement = ContractTestDataFactory.insertBillingAccount(
        account.Id
      );
      Set<Id> billingAccountIds = new Set<Id>{
        priorBillingAccountId,
        replacement.Id
      };
      Map<Id, BillingAccount__c> beforeById = new Map<Id, BillingAccount__c>([
        SELECT Id, HasReference__c
        FROM BillingAccount__c
        WHERE Id IN :billingAccountIds
      ]);
      System.assertEquals(
        true,
        beforeById.get(priorBillingAccountId).HasReference__c
      );
      System.assertEquals(
        false,
        beforeById.get(replacement.Id).HasReference__c
      );

      Boolean previous = ContractServiceWriteGuard.isPackageWriteAllowed();
      ContractServiceWriteGuard.allowPackageWrite(true);
      try {
        Test.startTest();
        update new ContractService__c(
          Id = service.Id,
          BiilingAcccount__c = replacement.Id
        );
        Test.stopTest();
      } finally {
        ContractServiceWriteGuard.allowPackageWrite(previous);
      }

      Map<Id, BillingAccount__c> afterById = new Map<Id, BillingAccount__c>([
        SELECT Id, HasReference__c
        FROM BillingAccount__c
        WHERE Id IN :billingAccountIds
      ]);
      System.assertEquals(
        false,
        afterById.get(priorBillingAccountId).HasReference__c,
        'Core 第3.3.3節: 最後の契約サービス参照を外した請求アカウントは参照なし'
      );
      System.assertEquals(
        true,
        afterById.get(replacement.Id).HasReference__c,
        'Core 第3.3.3節: 付け替え先は参照あり'
      );
    }
  }

  @IsTest
  static void beforeDelete_blocksPhysicalDeleteWhenNotOrderedAndNoLockedInvoices() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'CS Delete Allow Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'CS Delete Allow Service'
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'CS Delete Allow History',
        'New',
        1,
        termStart,
        termEnd
      );
      insertRecurringLine(
        history.Id,
        account.Id,
        'CS Delete Allow Product',
        termStart,
        termEnd
      );
      ContractService__c handlerCandidate = [
        SELECT Id
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      ContractServiceTriggerHandler.handleBeforeDelete(
        new List<ContractService__c>{ handlerCandidate }
      );
      System.assertEquals(
        false,
        handlerCandidate.hasErrors(),
        'Core 第3.4節: Orderedもロック済み請求も無い場合、個別条件は足さず一律削除拒否に委ねる'
      );
      ContractServiceWriteGuard.enforceInTest = true;
      Boolean thrown = false;
      String message = null;
      try {
        Test.startTest();
        delete service;
        Test.stopTest();
      } catch (DmlException ex) {
        thrown = true;
        message = ex.getNumDml() > 0 ? ex.getDmlMessage(0) : ex.getMessage();
      }
      System.assertEquals(
        true,
        thrown,
        'Core 第3.4節: 契約サービスは物理削除しない'
      );
      System.assertEquals(
        ContractServiceWriteGuard.DELETE_BLOCK_MESSAGE,
        message
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM ContractService__c WHERE Id = :service.Id]
      );
    }
  }

  @IsTest
  static void beforeDelete_blocksDeleteWhenLatestOrderedHistoryExists() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'CS Delete Ordered Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'CS Delete Ordered Service'
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'CS Delete Ordered History',
        'Cancel',
        1,
        termStart,
        termStart
      );
      orderHistory(history);
      ContractService__c synced = [
        SELECT LatestOrderedHistory__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertNotEquals(null, synced.LatestOrderedHistory__c);
      ContractServiceTriggerHandler.handleBeforeDelete(
        new List<ContractService__c>{ synced }
      );
      System.assertEquals(true, synced.hasErrors());
      System.assertEquals(1, synced.getErrors().size());
      System.assertEquals(
        ContractServiceTriggerHandler.ORDERED_DELETE_BLOCK_MESSAGE,
        synced.getErrors()[0].getMessage(),
        'Core 第3.4節: Ordered履歴がある契約サービスの削除理由を明示する'
      );

      ContractServiceWriteGuard.enforceInTest = true;
      Boolean thrown = false;
      String message = null;
      try {
        Test.startTest();
        delete service;
        Test.stopTest();
      } catch (DmlException ex) {
        thrown = true;
        message = ex.getMessage();
      }
      System.assertEquals(true, thrown);
      System.assert(
        message.contains(
          ContractServiceTriggerHandler.ORDERED_DELETE_BLOCK_MESSAGE
        ),
        message
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM ContractService__c WHERE Id = :service.Id]
      );
    }
  }

  @IsTest
  static void beforeDelete_blocksDeleteWhenOrderedExistsEvenIfLatestPointerCleared() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'CS Delete Pointer Gap Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'CS Delete Pointer Gap Service'
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'CS Delete Pointer Gap History',
        'Cancel',
        1,
        termStart,
        termStart
      );
      orderHistory(history);
      Boolean previous = ContractServiceWriteGuard.isPackageWriteAllowed();
      ContractServiceWriteGuard.allowPackageWrite(true);
      try {
        update new ContractService__c(
          Id = service.Id,
          LatestOrderedHistory__c = null,
          FirstOrderedHistory__c = null
        );
      } finally {
        ContractServiceWriteGuard.allowPackageWrite(previous);
      }

      ContractService__c handlerCandidate = [
        SELECT Id
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      ContractServiceTriggerHandler.handleBeforeDelete(
        new List<ContractService__c>{ handlerCandidate }
      );
      System.assertEquals(true, handlerCandidate.hasErrors());
      System.assertEquals(1, handlerCandidate.getErrors().size());
      System.assertEquals(
        ContractServiceTriggerHandler.ORDERED_DELETE_BLOCK_MESSAGE,
        handlerCandidate.getErrors()[0].getMessage(),
        'Core 第3.4節: Latestポインタが空でも実Ordered履歴を根拠に拒否する'
      );

      ContractServiceWriteGuard.enforceInTest = true;
      Boolean thrown = false;
      String message = null;
      try {
        Test.startTest();
        delete service;
        Test.stopTest();
      } catch (DmlException ex) {
        thrown = true;
        message = ex.getMessage();
      }
      System.assertEquals(true, thrown);
      System.assert(
        message.contains(
          ContractServiceTriggerHandler.ORDERED_DELETE_BLOCK_MESSAGE
        ),
        message
      );
    }
  }

  @IsTest
  static void beforeDelete_blocksDeleteWhenLockedInvoiceProductsExist() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'CS Delete Locked IP Account'
      );
      ContractService__c service = insertService(
        account.Id,
        'CS Delete Locked IP Service'
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2027, 5, 31);
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'CS Delete Locked IP History',
        'New',
        1,
        termStart,
        termEnd
      );
      insertRecurringLine(
        history.Id,
        account.Id,
        'CS Delete Locked IP Product',
        termStart,
        termEnd
      );
      Invoice__c invoice = new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = termStart,
        Amount__c = 96000,
        TaxAmount__c = 9600,
        BillingAccountSnapShot__c = service.BiilingAcccount__c,
        InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
        SystemIntegrationDate__c = Date.today()
      );
      ContractTestDataFactory.applyRequiredFields(invoice);
      invoice.InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED;
      ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);

      ContractService__c handlerCandidate = [
        SELECT Id
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      ContractServiceTriggerHandler.handleBeforeDelete(
        new List<ContractService__c>{ handlerCandidate }
      );
      System.assertEquals(true, handlerCandidate.hasErrors());
      System.assertEquals(1, handlerCandidate.getErrors().size());
      System.assertEquals(
        ContractServiceTriggerHandler.LOCKED_INVOICE_DELETE_BLOCK_MESSAGE,
        handlerCandidate.getErrors()[0].getMessage(),
        'Core 第3.4節: ロック済み請求を持つ契約サービスの削除理由を明示する'
      );

      ContractServiceWriteGuard.enforceInTest = true;
      Boolean thrown = false;
      String message = null;
      try {
        Test.startTest();
        delete service;
        Test.stopTest();
      } catch (DmlException ex) {
        thrown = true;
        message = ex.getMessage();
      }
      System.assertEquals(true, thrown);
      System.assert(
        message.contains(
          ContractServiceTriggerHandler.LOCKED_INVOICE_DELETE_BLOCK_MESSAGE
        ),
        message
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM ContractService__c WHERE Id = :service.Id]
      );
    }
  }

  @IsTest
  static void serviceEndDate_helpUsesJapaneseOrderedCancelNames() {
    String helpText = ContractService__c.ServiceEndDate__c.getDescribe()
      .getInlineHelpText();
    System.assertNotEquals(null, helpText);
    System.assert(
      helpText.contains('受注済み'),
      'Core 第0.1節: Ordered の画面表示は受注済み'
    );
    System.assert(
      helpText.contains('解約'),
      'Core 第0.1節: Cancel の画面表示は解約'
    );
    System.assert(
      !helpText.contains('Ordered'),
      'Core 第0.1節: ヘルプに Ordered と出さない'
    );
    System.assert(
      !helpText.contains('Cancel'),
      'Core 第0.1節: ヘルプに Cancel と出さない'
    );
  }

  @IsTest
  static void lifecycle_helpUsesJapaneseTermSpotDisplayNames() {
    String helpText = ContractService__c.Lifecycle__c.getDescribe()
      .getInlineHelpText();
    System.assertNotEquals(null, helpText);
    System.assert(
      helpText.contains('期間契約'),
      'Core 第0.1節: Lifecycle の画面表示は期間契約'
    );
    System.assert(
      helpText.contains('都度契約'),
      'Core 第0.1節: Lifecycle の画面表示は都度契約'
    );
    System.assert(
      !helpText.contains('Term'),
      'Core 第0.1節: ヘルプに Term と出さない'
    );
    System.assert(
      !helpText.contains('Spot'),
      'Core 第0.1節: ヘルプに Spot と出さない'
    );
  }
}
