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

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Archive Action History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
        CurrentTermEndDate__c = Date.newInstance(2027, 5, 31),
        EffectiveDate__c = Date.newInstance(2026, 6, 1)
      );
      insert history;

      Test.startTest();
      EstimateArchiveController.ArchiveResult result = EstimateArchiveController.archiveEstimate(
        history.Id
      );
      Test.stopTest();

      System.assertEquals(history.Id, result.contractHistoryId);
      System.assertEquals('Archive', result.historyStatus);
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
        EstimateArchiveController.archiveEstimate(history.Id);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals(
          '見積（Estimate）状態の契約履歴のみ Archive できます。',
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
        EstimateArchiveController.archiveEstimate(null);
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
        EstimateArchiveController.archiveEstimate(account.Id);
      } catch (AuraHandledException ex) {
        thrown = true;
        System.assertEquals('契約履歴が見つかりません。', ex.getMessage());
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
        ContractPermissionUtil.ARCHIVE_ESTIMATE => false
      };
      try {
        Boolean thrown = false;
        try {
          EstimateArchiveController.archiveEstimate(history.Id);
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
}
