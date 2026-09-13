@IsTest
private class ContractOperationLogServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void write_sameKey_preservesFirstPersistedResult() {
    Datetime startedAt = System.now();
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
    List<ContractOperationLog__c> stored = [
      SELECT
        OperationType__c,
        BusinessOperationKey__c,
        TargetObject__c,
        TargetRecordId__c,
        CreatedById,
        CreatedDate
      FROM ContractOperationLog__c
      WHERE BusinessOperationKey__c = 'op-log-same-key'
    ];
    System.assertEquals(
      1,
      stored.size(),
      '共通基盤第12章: 同じ業務操作キーの再試行は2行目を作らない'
    );
    System.assertEquals(
      'EstimateCreate',
      stored[0].OperationType__c,
      '共通基盤第12章: 再試行後も最初に成功した操作種別を保持する'
    );
    System.assertEquals(
      'op-log-same-key',
      stored[0].BusinessOperationKey__c,
      '共通基盤第12章: キーがある操作はそのキーを保存する'
    );
    System.assertEquals(
      'ContractHistory__c',
      stored[0].TargetObject__c,
      '共通基盤第12章: 主対象オブジェクトを保存する'
    );
    System.assertEquals(
      '001000000000001AAA',
      stored[0].TargetRecordId__c,
      '共通基盤第12章: 主対象レコードIdを保存する'
    );
    System.assertEquals(
      UserInfo.getUserId(),
      stored[0].CreatedById,
      '共通基盤第12章: CreatedByを実行者として保存する'
    );
    System.assert(
      stored[0].CreatedDate >= startedAt.addSeconds(-1) &&
        stored[0].CreatedDate <= System.now().addSeconds(1),
      '共通基盤第12章: CreatedDateを実行日時として保存する'
    );
  }

  @IsTest
  static void write_withoutBusinessKey_writesEachSuccessfulResult() {
    ContractOperationLogService.write(
      'EstimatePdfIssue',
      null,
      'ContractHistory__c',
      '001000000000003AAA'
    );
    ContractOperationLogService.write(
      'EstimatePdfIssue',
      null,
      'ContractHistory__c',
      '001000000000003AAA'
    );
    List<ContractOperationLog__c> stored = [
      SELECT
        OperationType__c,
        BusinessOperationKey__c,
        TargetObject__c,
        TargetRecordId__c
      FROM ContractOperationLog__c
      WHERE
        OperationType__c = 'EstimatePdfIssue'
        AND TargetRecordId__c = '001000000000003AAA'
    ];
    System.assertEquals(
      2,
      stored.size(),
      '共通基盤第12章: キーが空の操作は成功のたび1行を保存する'
    );
    for (ContractOperationLog__c row : stored) {
      System.assertEquals(
        null,
        row.BusinessOperationKey__c,
        '共通基盤第12章: 個別発行には業務操作キーを置かない'
      );
      System.assertEquals(
        'ContractHistory__c',
        row.TargetObject__c,
        '共通基盤第12章: 見積書発行の主対象は契約履歴'
      );
    }
  }

  @IsTest
  static void insert_withoutWriteFlag_isRejected() {
    Integer beforeCount = [
      SELECT COUNT()
      FROM ContractOperationLog__c
      WHERE OperationType__c = 'EstimateCreate'
    ];
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
    System.assertEquals(
      beforeCount,
      [
        SELECT COUNT()
        FROM ContractOperationLog__c
        WHERE OperationType__c = 'EstimateCreate'
      ],
      '共通基盤第12章: フラグなしinsertの失敗結果を保存しない'
    );
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
    ContractOperationLog__c persisted = [
      SELECT
        OperationType__c,
        BusinessOperationKey__c,
        TargetObject__c,
        TargetRecordId__c,
        UnlockReason__c
      FROM ContractOperationLog__c
      WHERE BusinessOperationKey__c = 'op-log-update'
      LIMIT 1
    ];
    System.assertEquals(
      'EstimateCreate',
      persisted.OperationType__c,
      '共通基盤第12章: 拒否した更新で操作種別を変えない'
    );
    System.assertEquals(
      'ContractHistory__c',
      persisted.TargetObject__c,
      '共通基盤第12章: 拒否した更新で主対象を変えない'
    );
    System.assertEquals(
      '001000000000002AAA',
      persisted.TargetRecordId__c,
      '共通基盤第12章: 拒否した更新で主対象Idを変えない'
    );
    System.assertEquals(
      null,
      persisted.UnlockReason__c,
      '共通基盤第12章: 拒否した更新結果を永続化しない'
    );
  }

  @IsTest
  static void writeMasters_persistsOneRowForTheTargetRecord() {
    Account account = ContractTestDataFactory.insertAccount('OpLog Skip BA');
    BillingAccount__c billingAccount = ContractTestDataFactory.insertBillingAccount(
      account.Id
    );
    String billingAccountId = String.valueOf(billingAccount.Id);
    Integer beforeCount = [
      SELECT COUNT()
      FROM ContractOperationLog__c
      WHERE
        OperationType__c = 'SaveBillingAccount'
        AND TargetRecordId__c = :billingAccountId
    ];
    ContractOperationLogService.writeMasters(
      'SaveBillingAccount',
      new List<SObject>{ billingAccount }
    );
    System.assertEquals(
      beforeCount + 1,
      [
        SELECT COUNT()
        FROM ContractOperationLog__c
        WHERE
          OperationType__c = 'SaveBillingAccount'
          AND TargetRecordId__c = :billingAccountId
      ],
      '共通基盤第12章: 請求アカウント保存は対象レコードごとに1行を保存する'
    );
    ContractOperationLog__c stored = [
      SELECT
        BusinessOperationKey__c,
        TargetObject__c,
        TargetRecordId__c
      FROM ContractOperationLog__c
      WHERE
        OperationType__c = 'SaveBillingAccount'
        AND TargetRecordId__c = :billingAccountId
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    System.assertEquals(
      null,
      stored.BusinessOperationKey__c,
      '共通基盤第12章: 請求アカウント保存はキーなし'
    );
    System.assertEquals(
      'BillingAccount__c',
      stored.TargetObject__c,
      '共通基盤第12章: 請求アカウント保存の主対象を保存する'
    );
    System.assertEquals(
      billingAccountId,
      stored.TargetRecordId__c,
      '共通基盤第12章: 主対象レコードIdをテキストで保存する'
    );
  }

  @IsTest
  static void write_persistsCancellationDetails() {
    ContractOperationLogService.write(
      'CancelInvoice',
      'op-log-cancel',
      'Invoice__c',
      '001000000000004AAA',
      'Other',
      '契約先からの取消依頼',
      null,
      null
    );
    ContractOperationLog__c stored = [
      SELECT
        OperationType__c,
        BusinessOperationKey__c,
        TargetObject__c,
        TargetRecordId__c,
        CancellationReason__c,
        CancellationReasonText__c,
        UnlockReason__c
      FROM ContractOperationLog__c
      WHERE BusinessOperationKey__c = 'op-log-cancel'
      LIMIT 1
    ];
    System.assertEquals(
      'CancelInvoice',
      stored.OperationType__c,
      '共通基盤第12章: 請求取消の操作種別を保存する'
    );
    System.assertEquals(
      'Invoice__c',
      stored.TargetObject__c,
      '共通基盤第12章: 請求取消の主対象は元請求'
    );
    System.assertEquals(
      '001000000000004AAA',
      stored.TargetRecordId__c,
      '共通基盤第12章: 請求取消の元請求Idを保存する'
    );
    System.assertEquals(
      'Other',
      stored.CancellationReason__c,
      '共通基盤第12章: 請求取消の取消理由を保存する'
    );
    System.assertEquals(
      '契約先からの取消依頼',
      stored.CancellationReasonText__c,
      '共通基盤第12章: Otherの取消理由テキストを保存する'
    );
    System.assertEquals(
      null,
      stored.UnlockReason__c,
      '共通基盤第12章: 請求取消にはUnlock理由を保存しない'
    );
  }

  @IsTest
  static void write_persistsUnlockReason() {
    ContractOperationLogService.write(
      'UnlockJournal',
      'op-log-unlock',
      'GlJournal__c',
      '001000000000005AAA',
      null,
      null,
      '再確認が必要なため',
      null
    );
    ContractOperationLog__c stored = [
      SELECT
        OperationType__c,
        BusinessOperationKey__c,
        TargetObject__c,
        TargetRecordId__c,
        UnlockReason__c
      FROM ContractOperationLog__c
      WHERE BusinessOperationKey__c = 'op-log-unlock'
      LIMIT 1
    ];
    System.assertEquals(
      'UnlockJournal',
      stored.OperationType__c,
      '共通基盤第12章・Accounting第9.5節: Unlockの操作種別を保存する'
    );
    System.assertEquals(
      'GlJournal__c',
      stored.TargetObject__c,
      '共通基盤第12章: 1件のUnlockは仕訳を主対象にする'
    );
    System.assertEquals(
      '001000000000005AAA',
      stored.TargetRecordId__c,
      '共通基盤第12章: Unlock対象の仕訳Idを保存する'
    );
    System.assertEquals(
      '再確認が必要なため',
      stored.UnlockReason__c,
      '共通基盤第12章・Accounting第9.5節: その操作のUnlock理由を保存する'
    );
  }
}
