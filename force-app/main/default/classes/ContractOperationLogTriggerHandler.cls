/**
 * 仕様: 共通基盤.md 第12章。作成は write の静的フラグだけ。更新は常に拒否。削除は 104 だけ通す。
 */
public without sharing class ContractOperationLogTriggerHandler {
  public static void assertInsertAllowed(List<ContractOperationLog__c> rows) {
    if (ContractOperationLogService.allowInsert == true) {
      return;
    }
    if (rows == null) {
      return;
    }
    for (ContractOperationLog__c row : rows) {
      row.addError('操作ログの作成は ContractOperationLogService.write だけです。');
    }
  }

  public static void rejectMutation(List<ContractOperationLog__c> rows) {
    if (rows == null) {
      return;
    }
    for (ContractOperationLog__c row : rows) {
      row.addError('操作ログは更新できません。');
    }
  }

  public static void assertDeleteAllowed(List<ContractOperationLog__c> rows) {
    if (ContractPermissionUtil.hasMigrateAll()) {
      return;
    }
    if (rows == null) {
      return;
    }
    for (ContractOperationLog__c row : rows) {
      row.addError('操作ログの削除は 104 だけです。');
    }
  }
}
