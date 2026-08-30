@IsTest
private class ContractOperationLogServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void write_sameKey_doesNotInsertSecondRow() {
    ContractOperationLogService.write(
      'EstimateCreate',
      'op-log-same-key',
      'ContractHistory__c',
      '001000000000001AAA'
    );
    ContractOperationLogService.write(
      'EstimateCreate',
      'op-log-same-key',
      'ContractHistory__c',
      '001000000000001AAA'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ContractOperationLog__c
        WHERE BusinessOperationKey__c = 'op-log-same-key'
      ],
      '共通基盤第12章: 同じ業務操作キーの再試行は2行目を作らない'
    );
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
      'op-log-update',
      'ContractHistory__c',
      '001000000000002AAA'
    );
    ContractOperationLog__c stored = [
      SELECT Id, UnlockReason__c
      FROM ContractOperationLog__c
      WHERE BusinessOperationKey__c = 'op-log-update'
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
  static void writeMasters_skipsWhenSkipMasterWrites() {
    ContractOperationLogService.skipMasterWrites = true;
    try {
      ContractOperationLogService.writeMasters(
        'SaveBillingAccount',
        new List<SObject>{
          new BillingAccount__c(Id = UserInfo.getUserId())
        }
      );
    } finally {
      ContractOperationLogService.skipMasterWrites = false;
    }
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM ContractOperationLog__c
        WHERE OperationType__c = 'SaveBillingAccount'
      ],
      '共通基盤第12章: キー埋め・参照ありのシステム更新はマスタログを書かない'
    );
  }

  @IsTest
  static void irregularCreate_isNotWrittenWithout104() {
    System.assertEquals(false, ContractPermissionUtil.hasMigrateAll());
    ContractIrregularOperationLog.logCreate(
      new List<SObject>{
        new Invoice__c(Id = UserInfo.getUserId())
      }
    );
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM ContractOperationLog__c
        WHERE OperationType__c = 'IrregularCreate'
      ],
      '共通基盤第12章: 104が無い正規経路はIrregularCreateを書かない'
    );
  }
}
