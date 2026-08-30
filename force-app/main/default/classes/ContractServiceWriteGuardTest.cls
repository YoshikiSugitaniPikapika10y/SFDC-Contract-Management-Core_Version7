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
      ContractService__c service = new ContractService__c(
        Name = 'Delete 104 Ordered',
        Account__c = account.Id
      );
      insert service;
      insert new ContractHistory__c(
        Name = 'Delete 104 Ordered History',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Ordered',
        Version__c = 1
      );
      ContractServiceWriteGuard.allowPackageWrite(false);
      ContractServiceWriteGuard.enforceInTest = true;
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        delete service;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        0,
        [SELECT COUNT() FROM ContractService__c WHERE Id = :service.Id],
        '共通基盤 第3.6節: 104 単独で契約サービス（Ordered 含む）の物理削除を通す'
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
}
