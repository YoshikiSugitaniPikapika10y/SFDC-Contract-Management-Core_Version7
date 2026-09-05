@IsTest
private class ContractOperationLogTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void insert_withoutWriteFlag_isRejected() {
    ContractOperationLog__c row = new ContractOperationLog__c(
      OperationType__c = 'EstimateCreate'
    );
    try {
      insert row;
      System.assert(false, '共通基盤第12章: フラグなし insert は拒否する');
    } catch (DmlException ex) {
      System.assert(
        ex.getMessage().contains('ContractOperationLogService.write'),
        '共通基盤第12章: 作成は write の静的フラグだけ'
      );
    }
  }

  @IsTest
  static void update_isAlwaysRejected() {
    ContractOperationLogService.write(
      'EstimateCreate',
      'op-log-handler-update',
      'ContractHistory__c',
      '001000000000002AAA'
    );
    ContractOperationLog__c stored = [
      SELECT Id, UnlockReason__c
      FROM ContractOperationLog__c
      WHERE BusinessOperationKey__c = 'op-log-handler-update'
      LIMIT 1
    ];
    stored.UnlockReason__c = 'x';
    try {
      update stored;
      System.assert(false, '共通基盤第12章: 更新は常に拒否する');
    } catch (DmlException ex) {
      System.assert(
        ex.getMessage().contains('更新できません'),
        '共通基盤第12章: 操作ログは更新できない'
      );
    }
  }

  @IsTest
  static void delete_isRejectedWithout101() {
    ContractOperationLogService.write(
      'EstimateCreate',
      'op-log-handler-delete',
      'ContractHistory__c',
      '001000000000003AAA'
    );
    ContractOperationLog__c stored = [
      SELECT Id
      FROM ContractOperationLog__c
      WHERE BusinessOperationKey__c = 'op-log-handler-delete'
      LIMIT 1
    ];
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.MIGRATE_ALL => false
    };
    try {
      delete stored;
      System.assert(false, '共通基盤第12章: 101無しの削除は拒否する');
    } catch (DmlException ex) {
      System.assert(
        ex.getMessage().contains('操作ログの削除は 101 だけです。'),
        '共通基盤第12章: 操作ログの削除は 101 だけ。実際: ' + ex.getMessage()
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
  }

  @IsTest
  static void delete_allows101() {
    ContractOperationLogService.write(
      'EstimateCreate',
      'op-log-handler-delete-101',
      'ContractHistory__c',
      '001000000000004AAA'
    );
    ContractOperationLog__c stored = [
      SELECT Id
      FROM ContractOperationLog__c
      WHERE BusinessOperationKey__c = 'op-log-handler-delete-101'
      LIMIT 1
    ];
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.MIGRATE_ALL => true
    };
    try {
      delete stored;
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM ContractOperationLog__c
        WHERE Id = :stored.Id
      ],
      '共通基盤第12章: 削除は 101 だけ通す'
    );
  }

  @IsTest
  static void handler_nullLists_doNotThrow() {
    ContractOperationLogTriggerHandler.assertInsertAllowed(null);
    ContractOperationLogTriggerHandler.rejectMutation(null);
    ContractOperationLogTriggerHandler.assertDeleteAllowed(null);
    ContractOperationLogService.write(
      'EstimateCreate',
      'op-log-handler-null',
      'ContractHistory__c',
      '001000000000006AAA'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ContractOperationLog__c
        WHERE BusinessOperationKey__c = 'op-log-handler-null'
      ],
      '共通基盤 第12章: 対象行が無い呼び出しのあとでも write は通る'
    );
  }

  @IsTest
  static void delete_rejects103() {
    ContractOperationLogService.write(
      'EstimateCreate',
      'op-log-handler-delete-103',
      'ContractHistory__c',
      '001000000000005AAA'
    );
    ContractOperationLog__c stored = [
      SELECT Id
      FROM ContractOperationLog__c
      WHERE BusinessOperationKey__c = 'op-log-handler-delete-103'
      LIMIT 1
    ];
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.DELETE_RECORDS => true
    };
    try {
      delete stored;
      System.assert(false, '共通基盤 第12章: 103 では操作ログを消せない');
    } catch (DmlException ex) {
      System.assertEquals(
        true,
        ex.getMessage().contains('操作ログの削除は 101 だけです。'),
        '共通基盤 第12章: 操作ログの削除は 101 だけ。103 と 22 では不可'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
  }
}
