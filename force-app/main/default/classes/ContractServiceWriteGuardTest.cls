@IsTest
private class ContractServiceWriteGuardTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void rejectDirectCreateUpdateAndDelete() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Write Guard Acct'
      );
      ContractServiceWriteGuard.enforceInTest = true;
      Boolean createRejected = false;
      try {
        insert new ContractService__c(
          Name = 'Direct Create',
          Account__c = account.Id
        );
      } catch (DmlException ex) {
        createRejected = true;
        System.assertEquals(
          ContractServiceWriteGuard.CREATE_BLOCK_MESSAGE,
          ex.getDmlMessage(0),
          'Core 第3.4節・第3.4.2節: 単体作成は所定の理由で拒否する'
        );
      }
      System.assertEquals(
        true,
        createRejected,
        'Core 第3.4節: Newの見積保存以外の単体作成を拒否する'
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM ContractService__c
          WHERE Name = 'Direct Create'
        ],
        'Core 第3.4節: 拒否した単体作成を保存しない'
      );

      ContractService__c service = new ContractService__c(
        Name = 'Package Create',
        Account__c = account.Id
      );
      ContractServiceWriteGuard.allowPackageWrite(true);
      try {
        insert service;
      } finally {
        ContractServiceWriteGuard.allowPackageWrite(false);
      }
      System.assertEquals(
        'Package Create',
        [
          SELECT Name
          FROM ContractService__c
          WHERE Id = :service.Id
        ]
        .Name,
        'Core 第3.4.2節: 正規手続きのパッケージ書込は保存する'
      );

      Boolean updateRejected = false;
      try {
        service.Name = 'Direct Update';
        update service;
      } catch (DmlException ex) {
        updateRejected = true;
        System.assertEquals(
          ContractServiceWriteGuard.UPDATE_BLOCK_MESSAGE,
          ex.getDmlMessage(0),
          'Core 第3.4.2節: 直書き更新は所定の理由で拒否する'
        );
      }
      System.assertEquals(
        true,
        updateRejected,
        'Core 第3.4.2節: 正規手続き以外の更新を拒否する'
      );
      System.assertEquals(
        'Package Create',
        [
          SELECT Name
          FROM ContractService__c
          WHERE Id = :service.Id
        ]
        .Name,
        'Core 第3.4.2節: 拒否した更新で保存済み値を変えない'
      );

      Boolean deleteRejected = false;
      try {
        delete service;
      } catch (DmlException ex) {
        deleteRejected = true;
        System.assertEquals(
          ContractServiceWriteGuard.DELETE_BLOCK_MESSAGE,
          ex.getDmlMessage(0),
          'Core 第3.4節: 通常削除は所定の理由で拒否する'
        );
      }
      System.assertEquals(
        true,
        deleteRejected,
        'Core 第3.4節・共通基盤 第3.6節: 101／103以外の削除を拒否する'
      );
      System.assertEquals(
        1,
        [SELECT COUNT() FROM ContractService__c WHERE Id = :service.Id],
        'Core 第3.4節: 拒否した削除後も契約サービスを保持する'
      );
    }
  }

  @IsTest
  static void migrateAll101_allowsPhysicalDeleteAfterChildDelete() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Delete 101 Acct'
      );
      ContractServiceWriteGuard.allowPackageWrite(true);
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Delete 101 Ordered'
      );
      service.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
      update service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Delete 101 Ordered History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1
      );
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        account.Id
      );
      insert history;
      ContractServiceWriteGuard.allowPackageWrite(false);
      ContractServiceWriteGuard.enforceInTest = true;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        delete history;
        delete service;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        0,
        [SELECT COUNT() FROM ContractService__c WHERE Id = :service.Id],
        '共通基盤 第3.6節: 101 単独で契約サービスの物理削除を通す'
      );
    }
  }

  @IsTest
  static void fixContract_allowsNameAndRejectsAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account first = ContractTestDataFactory.insertAccount(
        'Fix Contract First'
      );
      Account second = ContractTestDataFactory.insertAccount(
        'Fix Contract Second'
      );
      ContractServiceWriteGuard.allowPackageWrite(true);
      ContractService__c service = new ContractService__c(
        Name = 'Fix Contract Service',
        Account__c = first.Id
      );
      insert service;
      ContractServiceWriteGuard.allowPackageWrite(false);
      ContractServiceWriteGuard.enforceInTest = true;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.FIX_CONTRACT => true
      };
      try {
        Boolean createRejected = false;
        try {
          insert new ContractService__c(
            Name = 'Fix Contract Direct Create',
            Account__c = first.Id
          );
        } catch (DmlException ex) {
          createRejected = true;
          System.assertEquals(
            ContractServiceWriteGuard.CREATE_BLOCK_MESSAGE,
            ex.getDmlMessage(0),
            '共通基盤 第3.6節: 102は契約サービスの作成を通さない'
          );
        }
        System.assertEquals(
          true,
          createRejected,
          '共通基盤 第3.6節: 102は項目更新だけを通す'
        );
        System.assertEquals(
          0,
          [
            SELECT COUNT()
            FROM ContractService__c
            WHERE Name = 'Fix Contract Direct Create'
          ],
          '共通基盤 第3.6節: 102で拒否した作成を保存しない'
        );

        service.Name = 'Fix Contract Renamed';
        update service;
        System.assertEquals(
          'Fix Contract Renamed',
          [
            SELECT Name
            FROM ContractService__c
            WHERE Id = :service.Id
          ]
          .Name,
          'Core 第3.4節・共通基盤 第3.6節: 102 はシステム項目以外の更新を通す'
        );
        Boolean accountRejected = false;
        try {
          service.Account__c = second.Id;
          update service;
        } catch (DmlException ex) {
          accountRejected = true;
          System.assertEquals(
            ContractServiceWriteGuard.SYSTEM_FIELD_BLOCK_MESSAGE,
            ex.getDmlMessage(0),
            'Core 第3.4節: 102でも取引先の直書きを所定の理由で拒否する'
          );
        }
        System.assertEquals(
          true,
          accountRejected,
          'Core 第3.4節: 102 でも取引先は利用者が変更できない'
        );
        ContractService__c persisted = [
          SELECT Name, Account__c
          FROM ContractService__c
          WHERE Id = :service.Id
        ];
        System.assertEquals(
          first.Id,
          persisted.Account__c,
          'Core 第3.4節: 拒否した取引先変更で保存済み値を変えない'
        );
        System.assertEquals(
          'Fix Contract Renamed',
          persisted.Name,
          '共通基盤 第3.6節: 先に許可した通常項目更新は保持する'
        );

        Boolean deleteRejected = false;
        try {
          delete service;
        } catch (DmlException ex) {
          deleteRejected = true;
          System.assertEquals(
            ContractServiceWriteGuard.DELETE_BLOCK_MESSAGE,
            ex.getDmlMessage(0),
            '共通基盤 第3.6節: 102は物理削除を所定の理由で拒否する'
          );
        }
        System.assertEquals(
          true,
          deleteRejected,
          '共通基盤 第3.6節: 102は物理削除を通さない'
        );
        System.assertEquals(
          1,
          [SELECT COUNT() FROM ContractService__c WHERE Id = :service.Id],
          '共通基盤 第3.6節: 102で拒否した削除後もレコードを保持する'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
    }
  }

  @IsTest
  static void migrateAll101_allowsDirectCreateAndUpdate() {
    ContractServiceWriteGuard.enforceInTest = true;
    ContractServiceWriteGuard.allowPackageWrite(false);
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Write Guard 101 Acct'
      );
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        ContractService__c service = new ContractService__c(
          Name = 'Write Guard 101',
          Account__c = account.Id
        );
        insert service;
        System.assertEquals(
          'Write Guard 101',
          [
            SELECT Name
            FROM ContractService__c
            WHERE Id = :service.Id
          ]
          .Name,
          '共通基盤 第3.6節: 101は契約サービスの直接作成を通す'
        );

        service.Name = 'Write Guard 101 Renamed';
        update service;
        System.assertEquals(
          'Write Guard 101 Renamed',
          [
            SELECT Name
            FROM ContractService__c
            WHERE Id = :service.Id
          ]
          .Name,
          '共通基盤 第3.6節: 101 は契約サービスの更新を通す'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
        ContractServiceWriteGuard.enforceInTest = false;
      }
    }
  }

  @IsTest
  static void fixContract_rejectsLifecycleAndOrderedPointers() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Write Guard Sys Acct'
      );
      ContractServiceWriteGuard.allowPackageWrite(true);
      ContractService__c service = new ContractService__c(
        Name = 'Write Guard Sys',
        Account__c = account.Id
      );
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Write Guard Sys History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1
      );
      ContractTestDataFactory.applyRequiredFields(history);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        account.Id
      );
      insert history;
      ContractServiceWriteGuard.allowPackageWrite(false);
      ContractServiceWriteGuard.enforceInTest = true;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.FIX_CONTRACT => true
      };
      try {
        Boolean lifecycleRejected = false;
        try {
          service.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
          update service;
        } catch (DmlException ex) {
          lifecycleRejected = true;
          System.assertEquals(
            ContractServiceWriteGuard.SYSTEM_FIELD_BLOCK_MESSAGE,
            ex.getDmlMessage(0),
            'Core 第3.4節・第3.4.2節: Lifecycle直書きを所定の理由で拒否する'
          );
        }
        System.assertEquals(
          true,
          lifecycleRejected,
          'Core 第3.4節: Lifecycleは利用者が変更できない'
        );
        service = [
          SELECT
            Id,
            Lifecycle__c,
            FirstOrderedHistory__c,
            LatestOrderedHistory__c
          FROM ContractService__c
          WHERE Id = :service.Id
        ];
        System.assertEquals(
          null,
          service.Lifecycle__c,
          'Core 第3.4.2節: 拒否したLifecycle変更で保存済み値を変えない'
        );
        Boolean firstRejected = false;
        try {
          service.FirstOrderedHistory__c = history.Id;
          update service;
        } catch (DmlException ex) {
          firstRejected = true;
          System.assertEquals(
            ContractServiceWriteGuard.SYSTEM_FIELD_BLOCK_MESSAGE,
            ex.getDmlMessage(0),
            'Core 第3.4節: First Ordered直書きを所定の理由で拒否する'
          );
        }
        System.assertEquals(
          true,
          firstRejected,
          'Core 第3.4節: First Orderedは利用者が変更できない'
        );
        service = [
          SELECT Id, FirstOrderedHistory__c, LatestOrderedHistory__c
          FROM ContractService__c
          WHERE Id = :service.Id
        ];
        System.assertEquals(
          null,
          service.FirstOrderedHistory__c,
          'Core 第3.4節: 拒否したFirst Ordered変更で保存済み値を変えない'
        );
        Boolean latestRejected = false;
        try {
          service.LatestOrderedHistory__c = history.Id;
          update service;
        } catch (DmlException ex) {
          latestRejected = true;
          System.assertEquals(
            ContractServiceWriteGuard.SYSTEM_FIELD_BLOCK_MESSAGE,
            ex.getDmlMessage(0),
            'Core 第3.4節: Latest Ordered直書きを所定の理由で拒否する'
          );
        }
        System.assertEquals(
          true,
          latestRejected,
          'Core 第3.4節: Latest Orderedは利用者が変更できない'
        );
        System.assertEquals(
          null,
          [
            SELECT LatestOrderedHistory__c
            FROM ContractService__c
            WHERE Id = :service.Id
          ]
          .LatestOrderedHistory__c,
          'Core 第3.4節: 拒否したLatest Ordered変更で保存済み値を変えない'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
        ContractServiceWriteGuard.enforceInTest = false;
      }
    }
  }

  @IsTest
  static void delete_allows103_andCreateWithEmptyOldMapIsCreate() {
    ContractServiceWriteGuard.enforceInTest = true;
    ContractServiceWriteGuard.allowPackageWrite(false);
    ContractService__c missingPrior = new ContractService__c(Name = 'No Prior');
    ContractServiceWriteGuard.assertAllowedWrite(
      new List<ContractService__c>{ null, missingPrior },
      new Map<Id, ContractService__c>()
    );
    System.assertEquals(
      1,
      missingPrior.getErrors().size(),
      'Core 第3.4.2節: oldMapに既存行が無ければ作成拒否を1件だけ付ける'
    );
    System.assertEquals(
      ContractServiceWriteGuard.CREATE_BLOCK_MESSAGE,
      missingPrior.getErrors()[0].getMessage(),
      'Core 第3.4節: 新規見積以外の作成は拒否する'
    );
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Write Guard 103 Acct'
      );
      ContractServiceWriteGuard.allowPackageWrite(true);
      ContractService__c service = new ContractService__c(
        Name = 'Write Guard 103',
        Account__c = account.Id
      );
      insert service;
      ContractServiceWriteGuard.allowPackageWrite(false);
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.DELETE_RECORDS => true
      };
      try {
        Boolean updateRejected = false;
        try {
          service.Name = 'Write Guard 103 Updated';
          update service;
        } catch (DmlException ex) {
          updateRejected = true;
          System.assertEquals(
            ContractServiceWriteGuard.UPDATE_BLOCK_MESSAGE,
            ex.getDmlMessage(0),
            '共通基盤 第3.6節: 103は項目更新を所定の理由で拒否する'
          );
        }
        System.assertEquals(
          true,
          updateRejected,
          '共通基盤 第3.6節: 103は削除だけを通す'
        );
        System.assertEquals(
          'Write Guard 103',
          [
            SELECT Name
            FROM ContractService__c
            WHERE Id = :service.Id
          ]
          .Name,
          '共通基盤 第3.6節: 103で拒否した更新で保存済み値を変えない'
        );

        delete service;
        System.assertEquals(
          0,
          [SELECT COUNT() FROM ContractService__c WHERE Id = :service.Id],
          '共通基盤 第3.6節: 103 は契約サービスの物理削除を通す'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
        ContractServiceWriteGuard.enforceInTest = false;
      }
    }
  }
}
