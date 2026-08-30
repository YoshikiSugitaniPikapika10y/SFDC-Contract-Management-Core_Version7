/**
 * Cancel Ordered を契約サービスの終端 Version として強制する。
 * ウィザードだけでなく API／直接 DML にも適用する。
 */
public without sharing class ContractHistoryTerminalService {
  private static final String HISTORY_STATUS_ORDERED =
    ContractDomainConstants.HISTORY_STATUS_ORDERED;
  private static final String HISTORY_TYPE_CANCEL =
    ContractDomainConstants.HISTORY_TYPE_CANCEL;

  public static final String VERSION_AFTER_CANCEL_BLOCK_MESSAGE =
    '解約済み（Cancel）の契約サービスには後続 Version を追加できません。';

  public static void applyVersionAfterCancelErrors(
    List<ContractHistory__c> histories
  ) {
    List<String> errors = resolveVersionAfterCancelErrors(histories);
    for (Integer i = 0; i < errors.size(); i++) {
      if (String.isNotBlank(errors[i])) {
        histories[i].addError(errors[i]);
      }
    }
  }

  /**
   * 入力順と同じ長さのエラー一覧を返す。
   * 同一 DML 内の Cancel Ordered と、その後続 Version も検知する。
   */
  public static List<String> resolveVersionAfterCancelErrors(
    List<ContractHistory__c> histories
  ) {
    List<String> errors = new List<String>();
    if (histories == null || histories.isEmpty()) {
      return errors;
    }

    Set<Id> serviceIds = new Set<Id>();
    for (ContractHistory__c history : histories) {
      errors.add(null);
      if (history != null && history.ContractService__c != null) {
        serviceIds.add(history.ContractService__c);
      }
    }
    if (serviceIds.isEmpty()) {
      return errors;
    }

    Map<Id, Decimal> cancelVersionByServiceId = new Map<Id, Decimal>();
    for (ContractHistory__c cancelHistory : [
      SELECT ContractService__c, Version__c
      FROM ContractHistory__c
      WHERE
        ContractService__c IN :serviceIds
        AND historystatus__c = :HISTORY_STATUS_ORDERED
        AND Type__c = :HISTORY_TYPE_CANCEL
        AND Version__c != NULL
      WITH SYSTEM_MODE
    ]) {
      putMaxVersion(
        cancelVersionByServiceId,
        cancelHistory.ContractService__c,
        cancelHistory.Version__c
      );
    }

    // before insert の同一 DML 内に Cancel と後続が含まれる場合も塞ぐ。
    for (ContractHistory__c history : histories) {
      if (
        history != null &&
        history.ContractService__c != null &&
        history.Version__c != null &&
        history.historystatus__c == HISTORY_STATUS_ORDERED &&
        history.Type__c == HISTORY_TYPE_CANCEL
      ) {
        putMaxVersion(
          cancelVersionByServiceId,
          history.ContractService__c,
          history.Version__c
        );
      }
    }

    for (Integer i = 0; i < histories.size(); i++) {
      ContractHistory__c history = histories[i];
      if (
        history == null ||
        history.ContractService__c == null ||
        history.Version__c == null
      ) {
        continue;
      }
      Decimal cancelVersion = cancelVersionByServiceId.get(
        history.ContractService__c
      );
      if (cancelVersion != null && history.Version__c > cancelVersion) {
        errors[i] = VERSION_AFTER_CANCEL_BLOCK_MESSAGE;
      }
    }
    return errors;
  }

  private static void putMaxVersion(
    Map<Id, Decimal> versionByServiceId,
    Id serviceId,
    Decimal version
  ) {
    Decimal current = versionByServiceId.get(serviceId);
    if (current == null || version > current) {
      versionByServiceId.put(serviceId, version);
    }
  }
}
