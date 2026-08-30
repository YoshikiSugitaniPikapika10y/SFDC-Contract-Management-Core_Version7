/**
 * 仕様: 共通基盤.md 第12章。マスタとコピー定義の保存・削除。CMDTは書かない。
 */
public without sharing class ContractMasterOperationLog {
  public static void logSave(List<SObject> rows) {
    ContractOperationLogService.writeMasters('SaveAccountingMaster', rows);
  }

  public static void logDelete(List<SObject> rows) {
    ContractOperationLogService.writeMasters('DeleteAccountingMaster', rows);
  }

  public static void logFieldCopySave(List<SObject> rows) {
    ContractOperationLogService.writeMasters('SaveFieldCopyDefinition', rows);
  }

  public static void logFieldCopyDelete(List<SObject> rows) {
    ContractOperationLogService.writeMasters(
      'DeleteFieldCopyDefinition',
      rows
    );
  }

  public static void logNoteSave(List<SObject> rows) {
    ContractOperationLogService.writeMasters('SaveEstimateNoteMaster', rows);
  }

  public static void logNoteDelete(List<SObject> rows) {
    ContractOperationLogService.writeMasters(
      'DeleteEstimateNoteMaster',
      rows
    );
  }
}
