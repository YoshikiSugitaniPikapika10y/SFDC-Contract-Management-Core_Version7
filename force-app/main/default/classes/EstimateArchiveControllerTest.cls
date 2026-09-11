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

      history = [
        SELECT Id, LastModifiedDate, historystatus__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      Test.startTest();
      EstimateArchiveController.getArchiveContext(history.Id);
      Integer queriesBefore = Limits.getQueries();
      EstimateArchiveController.ArchiveContext context = EstimateArchiveController.getArchiveContext(
        history.Id
      );
      System.assertEquals(
        2,
        Limits.getQueries() - queriesBefore,
        'Core 第4.3.11節: 1回の取得で契約履歴を取り直さない'
      );
      Test.stopTest();

      System.assertEquals(history.Id, context.contractHistoryId);
      System.assertEquals('Estimate', context.historyStatus);
      System.assertEquals(
        ContractOptimisticLockUtil.toHistoryProductToken(
          history.Id,
          history.LastModifiedDate
        ),
        context.lastModifiedToken,
        'Core 第4.3.12節: 手動Archiveの比較値は履歴と商品'
      );
    }
  }

  @IsTest
  static void getArchiveContext_nullId_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        EstimateArchiveController.getArchiveContext(null);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '契約履歴IDが指定されていません。',
          ex.getMessage(),
          'Core 第4.3.12節: 手動Archiveの照会は契約履歴Id必須'
        );
      }
      System.assertEquals(true, thrown);
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
  static void getArchiveContext_withoutPermission_throwsKnownMessage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Context Perm Deny Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Archive Context Perm Deny Service'
      );
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Archive Context Perm Deny History',
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
          EstimateArchiveController.getArchiveContext(history.Id);
        } catch (AuraHandledException ex) {
          thrown = true;
          System.assertEquals(
            '見積アーカイブを実行する権限がありません。',
            ex.getMessage(),
            '共通基盤 第1.4節: 見積権限なしは手動Archive照会も拒否'
          );
        }
        System.assertEquals(true, thrown);
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
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
      System.assertEquals(
        'archive-key-1',
        result.businessOperationKey,
        'Core 第4.3.12節: 手動Archiveの操作キーを返す'
      );
      ContractHistory__c archived = [
        SELECT historystatus__c, PreviousHistory__c, BusinessOperationKey__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Archive', archived.historystatus__c);
      System.assertEquals(
        'archive-key-1',
        archived.BusinessOperationKey__c,
        'Core 第4.3.12節: 手動Archiveの操作キーを契約履歴へ残す'
      );
      System.assertEquals(
        null,
        archived.PreviousHistory__c,
        'Core 第5.5節: 手動・受注時自動のどちらでも Archive 遷移時に PreviousHistory を null にする'
      );
      String id18 = String.valueOf(history.Id);
      String id15 = id18.substring(0, 15);
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'EstimateArchive'
            AND (
              TargetRecordId__c = :id18
              OR TargetRecordId__c = :id15
            )
        ],
        '共通基盤第12章: 手動ArchiveはEstimateArchive 1行'
      );
    }
  }

  @IsTest
  static void archiveEstimate_doesNotWriteIrregularUpdateWith102() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Irreg Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Archive Irreg Service'
      );
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Archive Irreg History',
        'New',
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31),
        Date.newInstance(2026, 6, 1),
        null
      );
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.FIX_CONTRACT => true
      };
      try {
        Test.startTest();
        EstimateArchiveController.archiveEstimate(
          history.Id,
          ContractOptimisticLockUtil.toHistoryProductToken(history.Id),
          'archive-irreg-key'
        );
        Test.stopTest();
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }

      String id18 = String.valueOf(history.Id);
      String id15 = id18.substring(0, 15);
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'EstimateArchive'
            AND (
              TargetRecordId__c = :id18
              OR TargetRecordId__c = :id15
            )
        ],
        '共通基盤第12章: 手動ArchiveはEstimateArchive 1行'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractOperationLog__c
          WHERE
            OperationType__c = 'IrregularUpdate'
            AND (
              TargetRecordId__c = :id18
              OR TargetRecordId__c = :id15
            )
        ],
        '共通基盤第12章: 正規Archiveは102付きでもIrregularUpdateを書かない'
      );
      ContractHistory__c archived = [
        SELECT historystatus__c, PreviousHistory__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Archive', archived.historystatus__c);
      System.assertEquals(null, archived.PreviousHistory__c);
    }
  }

  @IsTest
  static void archiveEstimate_reusesLockedHistoryLastModified() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Lock Lmd Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Archive Lock Lmd Service'
      );
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Archive Lock Lmd History',
        'New',
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31),
        Date.newInstance(2026, 6, 1),
        null
      );
      history = [
        SELECT Id, LastModifiedDate
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      String token = ContractOptimisticLockUtil.toHistoryProductToken(
        history.Id,
        history.LastModifiedDate
      );
      Test.startTest();
      ContractHistory__c locked = AccountingCauseLockService.lockHistory(
        history.Id
      );
      Integer queriesBefore = Limits.getQueries();
      ContractOptimisticLockUtil.assertRequiredHistoryProductsUnchanged(
        locked.Id,
        token,
        locked.LastModifiedDate,
        locked.ContractHistoryContractProducts__r
      );
      System.assertEquals(
        0,
        Limits.getQueries() - queriesBefore,
        'Core 第12.4節: ロック照会の配下見積商品 MAX は取り直さない'
      );
      EstimateArchiveController.ArchiveResult result = EstimateArchiveController.archiveEstimate(
        history.Id,
        token,
        'archive-lock-lmd-key'
      );
      Test.stopTest();
      System.assertEquals('Archive', result.historyStatus);
      System.assertEquals(
        'archive-lock-lmd-key',
        result.businessOperationKey,
        'Core 第4.3.12節: 手動Archiveの操作キーを返す'
      );
      System.assertEquals(
        null,
        [
          SELECT PreviousHistory__c
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ]
        .PreviousHistory__c,
        'Core 第5.5節: Archive 遷移時に PreviousHistory を null にする'
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
      System.assertEquals(
        'Estimate',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ]
        .historystatus__c,
        'Core 第4.3.12節: 比較値未指定の拒否後も Estimate のまま'
      );
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
      ContractHistory__c archived = [
        SELECT historystatus__c, PreviousHistory__c, BusinessOperationKey__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Archive', archived.historystatus__c);
      System.assertEquals(
        null,
        archived.PreviousHistory__c,
        'Core 第5.5節: Archive 遷移時に PreviousHistory を null にする'
      );
      System.assertEquals(
        'archive-retry-key',
        archived.BusinessOperationKey__c,
        'Core 第4.3.12節: 同じキーの再試行でも操作キーは1件のまま'
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

  @IsTest
  static void archiveEstimate_rejectsAlreadyArchivedWithDifferentKey() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Irreversible Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Archive Irreversible Service'
      );
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Archive Irreversible History',
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
      EstimateArchiveController.archiveEstimate(
        history.Id,
        token,
        'archive-first-key'
      );

      EstimateArchiveController.ArchiveContext context = EstimateArchiveController.getArchiveContext(
        history.Id
      );
      System.assertEquals(
        'Archive',
        context.historyStatus,
        'Core 第5.5節: Archiveは参照のみ。状態はArchiveのまま返す'
      );

      Boolean thrown = false;
      try {
        EstimateArchiveController.archiveEstimate(
          history.Id,
          context.lastModifiedToken,
          'archive-other-key'
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '見積状態の契約履歴のみ不採用にできます。',
          ex.getMessage(),
          'Core 第5.5節: Archiveから他状態へ復活できない。手動ArchiveできるのはEstimateだけ'
        );
      }
      System.assertEquals(true, thrown);
      System.assertEquals(
        'Archive',
        [
          SELECT historystatus__c
          FROM ContractHistory__c
          WHERE Id = :history.Id
        ]
        .historystatus__c
      );
    }
  }

  @IsTest
  static void archiveEstimate_blankKey_issuesKeyAndKeepsOpportunity() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Blank Key Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Archive Blank Key Service'
      );
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Archive Blank Key History',
        'New',
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31),
        Date.newInstance(2026, 6, 1),
        null
      );
      Id opportunityId = [
        SELECT Opportunity__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ]
      .Opportunity__c;

      EstimateArchiveController.ArchiveResult result = EstimateArchiveController.archiveEstimate(
        history.Id,
        ContractOptimisticLockUtil.toHistoryProductToken(history.Id),
        null
      );
      System.assertEquals('Archive', result.historyStatus);
      System.assertEquals(
        false,
        String.isBlank(result.businessOperationKey),
        'Core 第4.3.12節: 手動Archiveの操作キーはサーバが発行する'
      );
      ContractHistory__c archived = [
        SELECT historystatus__c, Opportunity__c, PreviousHistory__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals('Archive', archived.historystatus__c);
      System.assertEquals(
        opportunityId,
        archived.Opportunity__c,
        'Core 第5.5節: 手動Archiveは見積を消さない。商談参照を外すのは差し戻しの更新商談削除だけ'
      );
      System.assertEquals(null, archived.PreviousHistory__c);
    }
  }

  @IsTest
  static void archiveEstimate_staleToken_throwsConflict() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Archive Stale Token Account'
      );
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Archive Stale Token Service'
      );
      ContractHistory__c history = insertEstimateHistory(
        service.Id,
        account.Id,
        'Archive Stale Token History',
        'New',
        1,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2027, 5, 31),
        Date.newInstance(2026, 6, 1),
        null
      );
      EstimateArchiveController.ArchiveContext context = EstimateArchiveController.getArchiveContext(
        history.Id
      );
      // 同一秒の LastModified でも版不一致になるよう、取得した比較値から 1ms ずらす
      String staleToken = String.valueOf(
        Long.valueOf(context.lastModifiedToken.trim()) - 1
      );

      Boolean thrown = false;
      try {
        EstimateArchiveController.archiveEstimate(
          history.Id,
          staleToken,
          'archive-stale-key'
        );
        System.assert(
          false,
          'Core 第4.3.12節: 版が一致しない比較値では手動Archiveを拒否する'
        );
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage(),
          'Core 第4.3.12節: 古い比較値は CONFLICT_MESSAGE'
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
        'Core 第4.3.12節: 古い比較値の拒否後も Estimate のまま'
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
