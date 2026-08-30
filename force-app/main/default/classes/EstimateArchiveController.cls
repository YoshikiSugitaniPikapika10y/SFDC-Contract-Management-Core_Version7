/**
 * 見積（Estimate）を Archive にするレコードアクション用コントローラ。
 */
public without sharing class EstimateArchiveController {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ARCHIVE = ContractDomainConstants.HISTORY_STATUS_ARCHIVE;

  public class ArchiveContext {
    @AuraEnabled
    public Id contractHistoryId;

    @AuraEnabled
    public String historyStatus;

    @AuraEnabled
    public String lastModifiedToken;
  }

  public class ArchiveResult {
    @AuraEnabled
    public Id contractHistoryId;

    @AuraEnabled
    public String historyStatus;

    @AuraEnabled
    public String businessOperationKey;
  }

  /** 仕様: Core 第4.3.12節、第5.5節 */
  @AuraEnabled
  public static ArchiveContext getArchiveContext(Id contractHistoryId) {
    ContractPermissionUtil.assertArchiveEstimate();
    if (contractHistoryId == null) {
      throw toAuraHandled('契約履歴IDが指定されていません。');
    }
    List<ContractHistory__c> histories = [
      SELECT Id, historystatus__c
      FROM ContractHistory__c
      WHERE Id = :contractHistoryId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (histories.isEmpty()) {
      throw toAuraHandled('契約履歴が見つかりません。');
    }
    ArchiveContext context = new ArchiveContext();
    context.contractHistoryId = histories[0].Id;
    context.historyStatus = histories[0].historystatus__c;
    context.lastModifiedToken = ContractOptimisticLockUtil.toHistoryProductToken(
      histories[0].Id
    );
    return context;
  }

  /** 仕様: Core 第5.3節、第5.5節、第4.3.12節 */
  @AuraEnabled
  public static ArchiveResult archiveEstimate(
    Id contractHistoryId,
    String expectedLastModifiedToken,
    String businessOperationKey
  ) {
    ContractPermissionUtil.assertArchiveEstimate();
    if (contractHistoryId == null) {
      throw toAuraHandled('契約履歴IDが指定されていません。');
    }
    String operationKey = AccountingCauseLockService.resolveOrIssueOperationKey(
      businessOperationKey
    );
    ContractHistory__c history;
    try {
      history = AccountingCauseLockService.lockHistory(contractHistoryId);
    } catch (AccountingCauseLockService.LockException ex) {
      throw toAuraHandled(ex.getMessage());
    }
    if (
      history.historystatus__c == HISTORY_STATUS_ARCHIVE &&
      history.BusinessOperationKey__c == operationKey
    ) {
      ArchiveResult existing = new ArchiveResult();
      existing.contractHistoryId = history.Id;
      existing.historyStatus = HISTORY_STATUS_ARCHIVE;
      existing.businessOperationKey = operationKey;
      ContractOperationLogService.write(
        'EstimateArchive',
        operationKey,
        'ContractHistory__c',
        String.valueOf(history.Id)
      );
      return existing;
    }
    if (history.historystatus__c != HISTORY_STATUS_ESTIMATE) {
      throw toAuraHandled(
        '見積状態の契約履歴のみ不採用にできます。'
      );
    }
    ContractOptimisticLockUtil.assertRequiredHistoryProductsUnchanged(
      history.Id,
      expectedLastModifiedToken
    );

    history.historystatus__c = HISTORY_STATUS_ARCHIVE;
    history.BusinessOperationKey__c = operationKey;
    try {
      SystemContextAccess.updateRecords(
        new List<ContractHistory__c>{ history }
      );
    } catch (DmlException ex) {
      throw toAuraHandled(
        ex.getNumDml() > 0 ? ex.getDmlMessage(0) : ex.getMessage()
      );
    }

    ArchiveResult result = new ArchiveResult();
    result.contractHistoryId = history.Id;
    result.historyStatus = HISTORY_STATUS_ARCHIVE;
    result.businessOperationKey = operationKey;
    ContractOperationLogService.write(
      'EstimateArchive',
      operationKey,
      'ContractHistory__c',
      String.valueOf(history.Id)
    );
    return result;
  }

  private static AuraHandledException toAuraHandled(String message) {
    String resolved = String.isBlank(message)
      ? '処理中にエラーが発生しました。'
      : message;
    AuraHandledException ex = new AuraHandledException(resolved);
    ex.setMessage(resolved);
    return ex;
  }
}
