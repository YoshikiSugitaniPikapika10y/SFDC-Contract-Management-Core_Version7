@IsTest
private class EstimateArchiveControllerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  @IsTest
  static void getArchiveContext_returnsEstimateToken() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Context Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Archive Context Service'
      );
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Archive Context History',
        'New',
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31),
        Date.newInstance(2026, 6, 1),
        null
      );

      Test.startTest();
      EstimateArchiveController.ArchiveContext context = EstimateArchiveController.getArchiveContext(
        history.Id
      );
      Test.stopTest();

      System.assertEquals(history.Id, context.contractHistoryId);
      System.assertEquals('Estimate', context.historyStatus);
      System.assertEquals(
        ContractOptimisticLockUtil.toHistoryProductToken(history.Id),
        context.lastModifiedToken,
        'Core 第4.3.12節: 手動Archiveの比較値は履歴と商品'
      );
    }
  }

  @IsTest
  static void getArchiveContext_missingHistory_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Context Missing Account'
      );
      Boolean thrown = false;
      try {
        EstimateArchiveController.getArchiveContext(account.Id);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals('契約履歴が見つかりません。', ex.getMessage());
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void archiveEstimate_archivesEstimateHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Action Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Archive Action Service'
      );

      ContractHistory__c prior = insertEstimateHistory(
        service.Id,
        account.Id,
        'Archive Action Prior',
        'New',
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31),
        Date.newInstance(2026, 6, 1),
        null
      );
      insertLine(prior.Id, account.Id, 'New');
      prior.historystatus__c = 'Ordered';
      update prior;

      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Archive Action History',
        'Change',
        2,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31),
        Date.newInstance(2026, 10, 1),
        prior.Id
      );

      Test.startTest();
      EstimateArchiveController.ArchiveResult result = EstimateArchiveController.archiveEstimate(
        history.Id,
        ContractOptimisticLockUtil.toHistoryProductToken(history.Id),
        'archive-key-1'
      );
      Test.stopTest();

      System.assertEquals(history.Id, result.contractHistoryId);
      System.assertEquals('Archive', result.historyStatus);
      ContractHistory__c archived = [
        SELECT historystatus__c, PreviousHistory__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Archive', archived.historystatus__c);
      System.assertEquals(
        null,
        archived.PreviousHistory__c,
        '手動 Archive でも前回契約履歴は Null'
      );
    }
  }

  @IsTest
  static void archiveEstimate_blocksNonEstimate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Block Ordered Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Archive Block Ordered Service'
      );

      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Archive Block Ordered History',
        'New',
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31),
        Date.newInstance(2026, 6, 1),
        null
      );
      insertLine(history.Id, account.Id, 'New');
      history.historystatus__c = 'Ordered';
      update history;

      Boolean thrown = false;
      try {
        EstimateArchiveController.archiveEstimate(history.Id, null, null);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '見積状態の契約履歴のみ不採用にできます。',
          ex.getMessage()
        );
      }
      System.assertEquals(
        true,
        thrown,
        'Ordered からの Archive はエラーになるべき'
      );
      System.assertEquals(
        'Ordered',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ]
        .historystatus__c,
        '拒否時は Ordered のまま'
      );
    }
  }

  @IsTest
  static void archiveEstimate_nullId_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        EstimateArchiveController.archiveEstimate(null, null, null);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '契約履歴IDが指定されていません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void archiveEstimate_missingHistory_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Missing History Account'
      );
      Boolean thrown = false;
      try {
        EstimateArchiveController.archiveEstimate(account.Id, null, null);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '契約履歴をロックできませんでした。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void archiveEstimate_withoutPermission_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Perm Deny Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Archive Perm Deny Service'
      );
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Archive Perm Deny History',
        'New',
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31),
        Date.newInstance(2026, 6, 1),
        null
      );

      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.ESTIMATE => false
      };
      try {
        Boolean thrown = false;
        try {
          EstimateArchiveController.archiveEstimate(history.Id, null, null);
        } catch (AuraHandledException ex) {
          thrown = true;
          System.assertEquals(
            '見積アーカイブを実行する権限がありません。',
            ex.getMessage()
          );
        }
        System.assertEquals(true, thrown);
        System.assertEquals(
          'Estimate',
          [
            SELECT historystatus__c
            FROM ContractHistory__c
            WHERE Id = :history.Id
          ]
          .historystatus__c,
          '権限拒否時は Estimate のまま'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
    }
  }

  @IsTest
  static void archiveEstimate_blankToken_throwsConflict() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Blank Token Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Archive Blank Token Service'
      );
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Archive Blank Token History',
        'New',
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31),
        Date.newInstance(2026, 6, 1),
        null
      );

      Boolean thrown = false;
      try {
        EstimateArchiveController.archiveEstimate(history.Id, null, 'k1');
        System.assert(
          false,
          'Core 第4.3.12節: 手動Archiveは比較値未指定なら拒否する'
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void archiveEstimate_sameKeyRetry_returnsOneArchive() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Retry Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Archive Retry Service'
      );
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Archive Retry History',
        'New',
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31),
        Date.newInstance(2026, 6, 1),
        null
      );
      String token = ContractOptimisticLockUtil.toHistoryProductToken(
        history.Id
      );

      Test.startTest();
      EstimateArchiveController.ArchiveResult first = EstimateArchiveController.archiveEstimate(
        history.Id,
        token,
        'archive-retry-key'
      );
      EstimateArchiveController.ArchiveResult retry = EstimateArchiveController.archiveEstimate(
        history.Id,
        token,
        'archive-retry-key'
      );
      Test.stopTest();

      System.assertEquals(first.contractHistoryId, retry.contractHistoryId);
      System.assertEquals('Archive', retry.historyStatus);
      System.assertEquals(
        'archive-retry-key',
        retry.businessOperationKey,
        'Core 第4.3.12節: 同じキーの再試行は1件のままにする'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractHistory__c
          WHERE Id = :history.Id AND historystatus__c = 'Archive'
        ]
      );
    }
  }

  private static ContractHistory__c insertEstimateHistory(
    Id serviceId,
    Id accountId,
    String name,
    String historyType,
    Decimal version,
    Date termStart,
    Date termEnd,
    Date effectiveDate,
    Id previousHistoryId
  ) {
    ContractHistory__c history = new ContractHistory__c(
      Name = name,
      ContractService__c = serviceId,
      Type__c = historyType,
      historystatus__c = 'Estimate',
      Version__c = version,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = effectiveDate,
      PreviousHistory__c = previousHistoryId
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(history, accountId);
    insert history;
    return history;
  }

  private static void insertLine(Id historyId, Id accountId, String productType) {
    Product2 product = ContractTestDataFactory.buildProduct(
      'Archive Line ' + String.valueOf(Crypto.getRandomInteger())
    );
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    ContractTestDataFactory.insertProduct(product);
    ContractProduct__c line = new ContractProduct__c(
      ContractHistory__c = historyId,
      Account__c = accountId,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Amount__c = 8000,
      StartDate__c = Date.newInstance(2026, 6, 1),
      Enddate__c = Date.newInstance(2027, 5, 31),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_MONTHLY,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = productType,
      RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_OVER_TIME
    );
    ContractTestDataFactory.applyRequiredFields(line);
    line.Amount__c = 8000;
    insert line;
  }
}
