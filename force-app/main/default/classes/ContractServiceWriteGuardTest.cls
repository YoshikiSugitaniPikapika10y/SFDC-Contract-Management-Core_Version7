@IsTest
private class ContractServiceWriteGuardTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void rejectDirectCreateUpdateAndDelete() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Write Guard Acct');
      ContractServiceWriteGuard.enforceInTest = true;
      Boolean createRejected = false;
      try {
        insert new ContractService__c(
          Name = 'Direct Create',
          Account__c = account.Id
        );
      } catch (DmlException ex) {
        createRejected = ex.getMessage()
          .contains(ContractServiceWriteGuard.CREATE_BLOCK_MESSAGE);
      }
      System.assertEquals(true, createRejected);

      ContractServiceWriteGuard.allowPackageWrite(true);
      ContractService__c service = new ContractService__c(
        Name = 'Package Create',
        Account__c = account.Id
      );
      insert service;
      ContractServiceWriteGuard.allowPackageWrite(false);

      Boolean updateRejected = false;
      try {
        service.Name = 'Direct Update';
        update service;
      } catch (DmlException ex) {
        updateRejected = ex.getMessage()
          .contains(ContractServiceWriteGuard.UPDATE_BLOCK_MESSAGE);
      }
      System.assertEquals(true, updateRejected);

      Boolean deleteRejected = false;
      try {
        delete service;
      } catch (DmlException ex) {
        deleteRejected = ex.getMessage()
          .contains(ContractServiceWriteGuard.DELETE_BLOCK_MESSAGE);
      }
      System.assertEquals(true, deleteRejected);
    }
  }

  @IsTest
  static void delete_allows104AloneEvenWithOrdered() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Delete 104 Acct');
      ContractServiceWriteGuard.allowPackageWrite(true);
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Delete 104 Ordered'
      );
      service.Lifecycle__c = ContractDomainConstants.LIFECYCLE_TERM;
      update service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Delete 104 Ordered History',
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
        '共通基盤 第3.6節: 101 単独で契約サービス（Ordered 含む）の物理削除を通す'
      );
    }
  }

  @IsTest
  static void fixContract_allowsNameAndRejectsAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account first = ContractTestDataFactory.insertAccount('Fix Contract First');
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
          accountRejected = ex.getMessage()
            .contains(ContractServiceWriteGuard.SYSTEM_FIELD_BLOCK_MESSAGE);
        }
        System.assertEquals(
          true,
          accountRejected,
          'Core 第3.4節: 102 でも取引先は利用者が変更できない'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
    }
  }

  @IsTest
  static void assertAllowedWrite_nullAndPackageAnd101_doNotBlock() {
    ContractServiceWriteGuard.enforceInTest = true;
    ContractServiceWriteGuard.allowPackageWrite(false);
    ContractServiceWriteGuard.assertAllowedWrite(null, null);
    System.assertEquals(
      false,
      ContractServiceWriteGuard.isPackageWriteAllowed(),
      'Core 第3.4.2節: パッケージ書込フラグが無い直書きは通さない'
    );
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'Write Guard 101 Acct'
      );
      ContractServiceWriteGuard.allowPackageWrite(true);
      ContractService__c service = new ContractService__c(
        Name = 'Write Guard 101',
        Account__c = account.Id
      );
      insert service;
      ContractServiceWriteGuard.allowPackageWrite(false);
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
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
          lifecycleRejected = ex.getMessage()
            .contains(ContractServiceWriteGuard.SYSTEM_FIELD_BLOCK_MESSAGE);
        }
        System.assertEquals(
          true,
          lifecycleRejected,
          'Core 第3.4節: Lifecycleは利用者が変更できない'
        );
        service = [
          SELECT Id, FirstOrderedHistory__c, LatestOrderedHistory__c
          FROM ContractService__c
          WHERE Id = :service.Id
        ];
        Boolean firstRejected = false;
        try {
          service.FirstOrderedHistory__c = history.Id;
          update service;
        } catch (DmlException ex) {
          firstRejected = ex.getMessage()
            .contains(ContractServiceWriteGuard.SYSTEM_FIELD_BLOCK_MESSAGE);
        }
        System.assertEquals(
          true,
          firstRejected,
          'Core 第3.4節: First Orderedは利用者が変更できない'
        );
        service = [
          SELECT Id, LatestOrderedHistory__c
          FROM ContractService__c
          WHERE Id = :service.Id
        ];
        Boolean latestRejected = false;
        try {
          service.LatestOrderedHistory__c = history.Id;
          update service;
        } catch (DmlException ex) {
          latestRejected = ex.getMessage()
            .contains(ContractServiceWriteGuard.SYSTEM_FIELD_BLOCK_MESSAGE);
        }
        System.assertEquals(
          true,
          latestRejected,
          'Core 第3.4節: Latest Orderedは利用者が変更できない'
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
    ContractServiceWriteGuard.assertNoDelete(null);
    ContractService__c missingPrior = new ContractService__c(Name = 'No Prior');
    ContractServiceWriteGuard.assertAllowedWrite(
      new List<ContractService__c>{ null, missingPrior },
      new Map<Id, ContractService__c>()
    );
    System.assertEquals(
      true,
      missingPrior.getErrors()[0]
        .getMessage()
        .contains(ContractServiceWriteGuard.CREATE_BLOCK_MESSAGE),
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
