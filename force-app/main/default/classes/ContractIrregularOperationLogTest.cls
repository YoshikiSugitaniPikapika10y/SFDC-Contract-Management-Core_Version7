@IsTest
private class ContractIrregularOperationLogTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void logCreate_isNotWrittenWithout104() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.MIGRATE_ALL => false
    };
    try {
      BillingAccount__c row = insertLoggedBillingAccount('Irreg No104');
      ContractIrregularOperationLog.logCreate(new List<SObject>{ row });
      System.assertEquals(
        0,
        countLogs('IrregularCreate', row.Id),
        '共通基盤第12章: 104が無い正規経路はIrregularCreateを書かない'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
  }

  @IsTest
  static void logCreate_writesOneRowPerRecordWith104() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c first = insertLoggedBillingAccount('Irreg 104 A');
      BillingAccount__c second = insertLoggedBillingAccount('Irreg 104 B');
      resetLogWriteFlags();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        System.assertEquals(
          false,
          ContractIrregularOperationLog.skipRegularPath(),
          '共通基盤第12章: 104の例外書き込みは正規フラグを立てない'
        );
        System.assertEquals(true, ContractPermissionUtil.hasMigrateAll());
        ContractIrregularOperationLog.logCreate(
          new List<SObject>{ first, second }
        );
        System.assertEquals(
          1,
          countLogs('IrregularCreate', first.Id),
          '共通基盤第12章・第3.6節: 101〜104は1件1行'
        );
        System.assertEquals(
          1,
          countLogs('IrregularCreate', second.Id),
          '共通基盤第12章・第3.6節: 101〜104は1件1行'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
    }
  }

  @IsTest
  static void logCreate_skipsWhenPackageWriteAllowed() {
    ContractServiceWriteGuard.allowPackageWrite(true);
    try {
      BillingAccount__c row = insertLoggedBillingAccount('Irreg Package');
      ContractIrregularOperationLog.logCreate(new List<SObject>{ row });
      System.assertEquals(
        0,
        countLogs('IrregularCreate', row.Id),
        '共通基盤第12章: 正規手続きの静的フラグではIrregularCreateを書かない'
      );
    } finally {
      ContractServiceWriteGuard.allowPackageWrite(false);
    }
  }

  @IsTest
  static void logUpdate_isNotWrittenWithout101102104() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.FIX_CONTRACT => false,
      ContractPermissionUtil.MIGRATE_ALL => false
    };
    try {
      BillingAccount__c row = insertLoggedBillingAccount('Irreg Upd No');
      ContractIrregularOperationLog.logUpdate(new List<SObject>{ row });
      System.assertEquals(
        0,
        countLogs('IrregularUpdate', row.Id),
        '共通基盤第12章: 101／102／104が無い更新はIrregularUpdateを書かない'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
  }

  @IsTest
  static void logDelete_writesWith104() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c row = insertLoggedBillingAccount('Irreg Del 104');
      resetLogWriteFlags();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        ContractIrregularOperationLog.logDelete(new List<SObject>{ row });
        System.assertEquals(
          1,
          countLogs('IrregularDelete', row.Id),
          '共通基盤第12章・第3.6節: 104の削除は1件1行'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
    }
  }

  private static BillingAccount__c insertLoggedBillingAccount(String name) {
    Account account = ContractTestDataFactory.insertAccount(name);
    return ContractTestDataFactory.insertBillingAccount(account.Id);
  }

  private static void resetLogWriteFlags() {
    ContractOperationLogService.skipInstallWrites = false;
    ContractOperationLogService.skipMasterWrites = false;
    ContractOperationLogService.orgSettingsWriteInProgress = false;
    ContractServiceWriteGuard.allowPackageWrite(false);
    InvoiceLockUtil.allowLockedStatusWrite = false;
    InvoicePaymentService.allowLifecycleWrite = false;
    InvoicePaymentAllocationService.allowHistoricalAmountWrite = false;
    ManualJournalService.allowLifecycleWrite = false;
    JournalLockService.allowLockWrite = false;
    GlJournalTriggerHandler.allowEngineWrite = false;
  }

  private static Integer countLogs(String operationType, Id targetId) {
    String id18 = String.valueOf(targetId);
    String id15 = id18.length() >= 15 ? id18.substring(0, 15) : id18;
    return [
      SELECT COUNT()
      FROM ContractOperationLog__c
      WHERE
        OperationType__c = :operationType
        AND (
          TargetRecordId__c = :id18
          OR TargetRecordId__c = :id15
        )
    ];
  }
}
