@IsTest
private class EstimateArchiveControllerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
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

      ContractHistory__c prior = new ContractHistory__c(
        Name = 'Archive Action Prior',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insert prior;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Archive Action History',
        ContractService__c = service.Id,
        Type__c = 'Change',
        historystatus__c = 'Estimate',
        Version__c = 2,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 10, 1),
        PreviousHistory__c = prior.Id
      );
      insert history;

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

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Archive Block Ordered History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1),
        ApplicationDate__c = Date.newInstance(2026, 6, 1)
      );
      insert history;

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
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Archive Perm Deny History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insert history;

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
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Archive Blank Token History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insert history;

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
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Archive Retry History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insert history;
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
}
