/**
 * 仕様: 共通基盤.md 第12章。操作ログは成功した1回の書き込みの時系列である。
 */
public without sharing class ContractOperationLogService {
  public static Boolean allowInsert;
  public static Boolean skipInstallWrites;
  public static Boolean orgSettingsWriteInProgress;
  public static Boolean suppressIssueLog;
  public static Boolean suppressJournalMemoWrites;
  public static Boolean skipMasterWrites;

  public static void write(
    String operationType,
    String businessOperationKey,
    String targetObject,
    String targetRecordId
  ) {
    write(
      operationType,
      businessOperationKey,
      targetObject,
      targetRecordId,
      null,
      null,
      null,
      null
    );
  }

  public static void write(
    String operationType,
    String businessOperationKey,
    String targetObject,
    String targetRecordId,
    String cancellationReason,
    String cancellationReasonText,
    String unlockReason,
    String permissionSetApiName
  ) {
    if (skipInstallWrites == true) {
      return;
    }
    if (suppressJournalMemoWrites == true && operationType == 'JournalMemo') {
      return;
    }
    if (String.isBlank(operationType)) {
      return;
    }
    if (String.isNotBlank(businessOperationKey)) {
      Integer existing = [
        SELECT COUNT()
        FROM ContractOperationLog__c
        WHERE BusinessOperationKey__c = :businessOperationKey
        WITH SYSTEM_MODE
      ];
      if (existing > 0) {
        return;
      }
    }
    ContractOperationLog__c row = new ContractOperationLog__c();
    row.OperationType__c = operationType;
    row.BusinessOperationKey__c = businessOperationKey;
    row.TargetObject__c = targetObject;
    row.TargetRecordId__c = abbreviateId(targetRecordId);
    row.CancellationReason__c = cancellationReason;
    row.CancellationReasonText__c = cancellationReasonText;
    row.UnlockReason__c = unlockReason;
    row.PermissionSetApiName__c = permissionSetApiName;
    Boolean previous = allowInsert;
    allowInsert = true;
    try {
      SystemContextAccess.insertRecords(
        new List<SObject>{ row }
      );
    } finally {
      allowInsert = previous;
    }
  }

  public static void writeMasters(String operationType, List<SObject> rows) {
    if (
      skipInstallWrites == true ||
      orgSettingsWriteInProgress == true ||
      skipMasterWrites == true ||
      rows == null ||
      rows.isEmpty()
    ) {
      return;
    }
    for (SObject row : rows) {
      if (row == null || row.Id == null) {
        continue;
      }
      write(
        operationType,
        null,
        String.valueOf(row.getSObjectType()),
        String.valueOf(row.Id)
      );
    }
  }

  private static String abbreviateId(String value) {
    if (String.isBlank(value)) {
      return value;
    }
    return value.length() > 18 ? value.substring(0, 18) : value;
  }
}
