/**
 * 見積（Estimate）を Archive にするレコードアクション用コントローラ。
 */
public without sharing class EstimateArchiveController {
  private static final String HISTORY_STATUS_ESTIMATE = ContractDomainConstants.HISTORY_STATUS_ESTIMATE;
  private static final String HISTORY_STATUS_ARCHIVE = ContractDomainConstants.HISTORY_STATUS_ARCHIVE;

  public class ArchiveResult {
    @AuraEnabled
    public Id contractHistoryId;

    @AuraEnabled
    public String historyStatus;
  }

  @AuraEnabled
  public static ArchiveResult archiveEstimate(Id contractHistoryId) {
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

    ContractHistory__c history = histories[0];
    if (history.historystatus__c != HISTORY_STATUS_ESTIMATE) {
      throw toAuraHandled(
        '見積（Estimate）状態の契約履歴のみ Archive できます。'
      );
    }

    history.historystatus__c = HISTORY_STATUS_ARCHIVE;
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
    return result;
  }

  private static AuraHandledException toAuraHandled(String message) {
    String resolved = String.isNotBlank(message)
      ? message
      : '処理中にエラーが発生しました。';
    AuraHandledException ex = new AuraHandledException(resolved);
    ex.setMessage(resolved);
    return ex;
  }
}
