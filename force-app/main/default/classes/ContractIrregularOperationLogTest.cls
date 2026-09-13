@IsTest
private class ContractIrregularOperationLogTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void logCreate_isNotWrittenWithout101() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.MIGRATE_ALL => false
    };
    try {
      BillingAccount__c row = insertLoggedBillingAccount('Irreg No101');
      ContractIrregularOperationLog.logCreate(new List<SObject>{ row });
      System.assertEquals(
        0,
        countLogs('IrregularCreate', row.Id),
        '共通基盤第12章: 101が無い経路はIrregularCreateを書かない'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
  }

  @IsTest
  static void logCreate_writesExactRowsWith101() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c first = insertLoggedBillingAccount('Irreg 101 A');
      BillingAccount__c second = insertLoggedBillingAccount('Irreg 101 B');
      resetLogWriteFlags();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        System.assertEquals(
          false,
          ContractIrregularOperationLog.skipRegularPath(),
          '共通基盤第12章: 101の例外書き込みは正規フラグを立てない'
        );
        System.assertEquals(true, ContractPermissionUtil.hasMigrateAll());
        Datetime startedAt = System.now();
        ContractIrregularOperationLog.logCreate(
          new List<SObject>{ first, second }
        );
        Datetime finishedAt = System.now();
        assertIrregularLog(
          'IrregularCreate',
          first.Id,
          UserInfo.getUserId(),
          startedAt,
          finishedAt
        );
        assertIrregularLog(
          'IrregularCreate',
          second.Id,
          UserInfo.getUserId(),
          startedAt,
          finishedAt
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
    }
  }

  @IsTest
  static void logCreate_skipsWhenPackageWriteAllowed() {
    ContractServiceWriteGuard.allowPackageWrite(true);
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.MIGRATE_ALL => true
    };
    try {
      BillingAccount__c row = insertLoggedBillingAccount('Irreg Package');
      ContractIrregularOperationLog.logCreate(new List<SObject>{ row });
      System.assertEquals(
        0,
        countLogs('IrregularCreate', row.Id),
        '共通基盤第12章: 正規手続きの静的フラグではIrregularCreateを書かない'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
      ContractServiceWriteGuard.allowPackageWrite(false);
    }
  }

  @IsTest
  static void logCreate_skipsWhenEstimateSavePath() {
    ContractIrregularOperationLog.skipEstimateSavePath = true;
    try {
      BillingAccount__c row = insertLoggedBillingAccount('Irreg Estimate');
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      ContractIrregularOperationLog.logCreate(new List<SObject>{ row });
      System.assertEquals(
        0,
        countLogs('IrregularCreate', row.Id),
        '共通基盤第12章: 見積保存の正規手続きはIrregularCreateを書かない'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
      ContractIrregularOperationLog.skipEstimateSavePath = false;
    }
  }

  @IsTest
  static void logCreate_skipsWhenEstimateArchivePath() {
    ContractIrregularOperationLog.skipEstimateArchivePath = true;
    try {
      BillingAccount__c row = insertLoggedBillingAccount('Irreg Archive');
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      ContractIrregularOperationLog.logCreate(new List<SObject>{ row });
      System.assertEquals(
        0,
        countLogs('IrregularCreate', row.Id),
        '共通基盤第12章: 手動Archiveの正規手続きはIrregularCreateを書かない'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
      ContractIrregularOperationLog.skipEstimateArchivePath = false;
    }
  }

  @IsTest
  static void logCreate_skipsWhenRevertOrderPath() {
    ContractIrregularOperationLog.skipRevertOrderPath = true;
    try {
      BillingAccount__c row = insertLoggedBillingAccount('Irreg Revert');
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      ContractIrregularOperationLog.logCreate(new List<SObject>{ row });
      System.assertEquals(
        0,
        countLogs('IrregularCreate', row.Id),
        '共通基盤第12章: 差し戻しの正規手続きはIrregularCreateを書かない'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
      ContractIrregularOperationLog.skipRevertOrderPath = false;
    }
  }

  @IsTest
  static void logUpdate_isNotWrittenWithout101Or102() {
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
        '共通基盤第12章: 101／102が無い更新はIrregularUpdateを書かない'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
  }

  @IsTest
  static void logUpdate_writesExactRowsWith101And102() {
    BillingAccount__c with102 = insertLoggedBillingAccount('Irreg Upd 102');
    BillingAccount__c with101 = insertLoggedBillingAccount('Irreg Upd 101');
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.FIX_CONTRACT => true,
      ContractPermissionUtil.MIGRATE_ALL => false
    };
    try {
      Datetime startedAt = System.now();
      ContractIrregularOperationLog.logUpdate(new List<SObject>{ with102 });
      assertIrregularLog(
        'IrregularUpdate',
        with102.Id,
        UserInfo.getUserId(),
        startedAt,
        System.now()
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }

    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.FIX_CONTRACT => false,
      ContractPermissionUtil.MIGRATE_ALL => true
    };
    try {
      Datetime startedAt = System.now();
      ContractIrregularOperationLog.logUpdate(new List<SObject>{ with101 });
      assertIrregularLog(
        'IrregularUpdate',
        with101.Id,
        UserInfo.getUserId(),
        startedAt,
        System.now()
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
  }

  @IsTest
  static void logDelete_isNotWrittenWithout101Or103() {
    BillingAccount__c row = insertLoggedBillingAccount('Irreg Del No');
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.FIX_CONTRACT => true,
      ContractPermissionUtil.DELETE_RECORDS => false,
      ContractPermissionUtil.MIGRATE_ALL => false
    };
    try {
      ContractIrregularOperationLog.logDelete(new List<SObject>{ row });
      System.assertEquals(
        0,
        countLogs('IrregularDelete', row.Id),
        '共通基盤第3.6節・第12章: 102だけではIrregularDeleteを書かない'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
  }

  @IsTest
  static void logDelete_writesExactRowsWith101And103() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c with101 = insertLoggedBillingAccount('Irreg Del 101');
      BillingAccount__c with103 = insertLoggedBillingAccount('Irreg Del 103');
      resetLogWriteFlags();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        Datetime startedAt = System.now();
        ContractIrregularOperationLog.logDelete(new List<SObject>{ with101 });
        assertIrregularLog(
          'IrregularDelete',
          with101.Id,
          UserInfo.getUserId(),
          startedAt,
          System.now()
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }

      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.DELETE_RECORDS => true,
        ContractPermissionUtil.MIGRATE_ALL => false
      };
      try {
        Datetime startedAt = System.now();
        ContractIrregularOperationLog.logDelete(new List<SObject>{ with103 });
        assertIrregularLog(
          'IrregularDelete',
          with103.Id,
          UserInfo.getUserId(),
          startedAt,
          System.now()
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
    }
  }

  @IsTest
  static void logCreate_rollsBackWithCauseTransaction() {
    BillingAccount__c row = insertLoggedBillingAccount('Irreg Rollback');
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.MIGRATE_ALL => true
    };
    Savepoint causeTransaction = Database.setSavepoint();
    try {
      ContractIrregularOperationLog.logCreate(new List<SObject>{ row });
      System.assertEquals(
        1,
        countLogs('IrregularCreate', row.Id),
        '共通基盤第12章: 原因操作と同じトランザクション中はログが存在する'
      );
      Database.rollback(causeTransaction);
      System.assertEquals(
        0,
        countLogs('IrregularCreate', row.Id),
        '共通基盤第12章: 原因操作が失敗してロールバックされればログも消える'
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
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
    ContractIrregularOperationLog.skipEstimateSavePath = false;
    ContractIrregularOperationLog.skipEstimateArchivePath = false;
    ContractIrregularOperationLog.skipRevertOrderPath = false;
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

  private static void assertIrregularLog(
    String expectedOperationType,
    Id expectedTargetId,
    Id expectedActorId,
    Datetime startedAt,
    Datetime finishedAt
  ) {
    String targetId = String.valueOf(expectedTargetId);
    List<ContractOperationLog__c> stored = [
      SELECT
        OperationType__c,
        BusinessOperationKey__c,
        TargetObject__c,
        TargetRecordId__c,
        CancellationReason__c,
        CancellationReasonText__c,
        UnlockReason__c,
        CreatedById,
        CreatedDate
      FROM ContractOperationLog__c
      WHERE
        OperationType__c = :expectedOperationType
        AND TargetRecordId__c = :targetId
    ];
    System.assertEquals(
      1,
      stored.size(),
      '共通基盤第12章: Irregular*は対象レコード1件につき1行'
    );
    ContractOperationLog__c actual = stored[0];
    System.assertEquals(expectedOperationType, actual.OperationType__c);
    System.assertEquals(
      null,
      actual.BusinessOperationKey__c,
      '共通基盤第12章: Irregular*は業務操作キーなし'
    );
    System.assertEquals(
      'BillingAccount__c',
      actual.TargetObject__c,
      '共通基盤第12章: 主対象は操作したレコードのオブジェクトAPI名'
    );
    System.assertEquals(
      targetId,
      actual.TargetRecordId__c,
      '共通基盤第12章: 主対象レコードは操作したレコードのId'
    );
    System.assertEquals(null, actual.CancellationReason__c);
    System.assertEquals(null, actual.CancellationReasonText__c);
    System.assertEquals(null, actual.UnlockReason__c);
    System.assertEquals(
      expectedActorId,
      actual.CreatedById,
      '共通基盤第12章: CreatedByが実行者'
    );
    System.assert(
      actual.CreatedDate >= startedAt.addSeconds(-1) &&
        actual.CreatedDate <= finishedAt.addSeconds(1),
      '共通基盤第12章: CreatedDateが実行日時'
    );
  }
}
