/**
 * ContractProduct__c トリガ処理。
 * 取引先の自動セットを行う。
 * Amount__c はウィザード Step3 の画面確認値を保存するため、ここでは再計算しない。
 */
public without sharing class ContractProductTriggerHandler {
  public static void handleBeforeInsertOrUpdate(
    List<ContractProduct__c> newProducts
  ) {
    populateDerivedFieldsFromContractHistory(newProducts);
  }

  /**
   * Account と請求アンカーに必要な履歴を1回で取得する。
   * 以前は同じ履歴を2回SOQLしており、複数バージョンを同一トランザクションで
   * 作るライフサイクル処理のクエリ上限を圧迫していた。
   */
  private static void populateDerivedFieldsFromContractHistory(
    List<ContractProduct__c> products
  ) {
    if (products == null || products.isEmpty()) {
      return;
    }
    Set<Id> historyIds = new Set<Id>();
    for (ContractProduct__c product : products) {
      if (product.ContractHistory__c != null) {
        historyIds.add(product.ContractHistory__c);
      }
    }
    if (historyIds.isEmpty()) {
      return;
    }
    Map<Id, ContractHistory__c> historyById = new Map<Id, ContractHistory__c>([
      SELECT Id, Type__c, EffectiveDate__c, ContractService__r.Account__c
      FROM ContractHistory__c
      WHERE Id IN :historyIds
      WITH SYSTEM_MODE
    ]);
    for (ContractProduct__c product : products) {
      ContractHistory__c history = historyById.get(product.ContractHistory__c);
      if (
        product.Account__c == null &&
        history != null &&
        history.ContractService__r != null
      ) {
        product.Account__c = history.ContractService__r.Account__c;
      }
      InvoiceAnchorDateUtil.applyToContractProduct(
        product,
        history == null ? null : history.Type__c,
        history == null ? null : history.EffectiveDate__c
      );
    }
  }

  public static void populateInvoiceAnchorFields(
    List<ContractProduct__c> products
  ) {
    if (products == null || products.isEmpty()) {
      return;
    }

    Set<Id> historyIds = new Set<Id>();
    for (ContractProduct__c product : products) {
      if (product.ContractHistory__c != null) {
        historyIds.add(product.ContractHistory__c);
      }
    }
    if (historyIds.isEmpty()) {
      return;
    }

    Map<Id, ContractHistory__c> historyById = new Map<Id, ContractHistory__c>(
      [
        SELECT Id, Type__c, EffectiveDate__c
        FROM ContractHistory__c
        WHERE Id IN :historyIds
        WITH SYSTEM_MODE
      ]
    );

    for (ContractProduct__c product : products) {
      ContractHistory__c history = historyById.get(product.ContractHistory__c);
      InvoiceAnchorDateUtil.applyToContractProduct(
        product,
        history == null ? null : history.Type__c,
        history == null ? null : history.EffectiveDate__c
      );
    }
  }

  public static void populateAccountFromContractHistory(
    List<ContractProduct__c> products
  ) {
    if (products == null || products.isEmpty()) {
      return;
    }

    Set<Id> historyIdsNeedingAccount = new Set<Id>();
    for (ContractProduct__c product : products) {
      if (product.Account__c == null && product.ContractHistory__c != null) {
        historyIdsNeedingAccount.add(product.ContractHistory__c);
      }
    }
    if (historyIdsNeedingAccount.isEmpty()) {
      return;
    }

    Map<Id, Id> accountIdByHistoryId = loadAccountIdByHistoryId(
      historyIdsNeedingAccount
    );

    for (ContractProduct__c product : products) {
      if (product.Account__c != null || product.ContractHistory__c == null) {
        continue;
      }
      product.Account__c = accountIdByHistoryId.get(product.ContractHistory__c);
    }
  }

  private static Map<Id, Id> loadAccountIdByHistoryId(Set<Id> historyIds) {
    Map<Id, Id> accountIdByHistoryId = new Map<Id, Id>();
    for (ContractHistory__c history : [
      SELECT Id, ContractService__r.Account__c
      FROM ContractHistory__c
      WHERE Id IN :historyIds
      WITH SYSTEM_MODE
    ]) {
      if (
        history.ContractService__r != null &&
        history.ContractService__r.Account__c != null
      ) {
        accountIdByHistoryId.put(
          history.Id,
          history.ContractService__r.Account__c
        );
      }
    }
    return accountIdByHistoryId;
  }

  public static void handleAfterChange(
    List<ContractProduct__c> newProducts,
    Map<Id, ContractProduct__c> oldMap
  ) {
    Set<Id> historyIds = collectHistoryIds(newProducts, oldMap);
    ContractArrCalculationService.recalculateForHistories(
      collectArrHistoryIds(newProducts, oldMap)
    );
    ContractServiceLifecycleService.ensureLifecycleForHistories(historyIds);
  }

  public static void handleAfterDelete(List<ContractProduct__c> oldProducts) {
    Set<Id> historyIds = new Set<Id>();
    for (ContractProduct__c product : oldProducts) {
      if (product.ContractHistory__c != null) {
        historyIds.add(product.ContractHistory__c);
      }
    }
    ContractArrCalculationService.recalculateForHistories(historyIds);
  }

  private static Set<Id> collectHistoryIds(
    List<ContractProduct__c> newProducts,
    Map<Id, ContractProduct__c> oldMap
  ) {
    Set<Id> historyIds = new Set<Id>();
    for (ContractProduct__c product : newProducts) {
      if (product.ContractHistory__c != null) {
        historyIds.add(product.ContractHistory__c);
      }
      if (oldMap == null) {
        continue;
      }
      ContractProduct__c oldProduct = oldMap.get(product.Id);
      if (
        oldProduct != null &&
        oldProduct.ContractHistory__c != null &&
        oldProduct.ContractHistory__c != product.ContractHistory__c
      ) {
        historyIds.add(oldProduct.ContractHistory__c);
      }
    }
    return historyIds;
  }

  private static Set<Id> collectArrHistoryIds(
    List<ContractProduct__c> newProducts,
    Map<Id, ContractProduct__c> oldMap
  ) {
    if (oldMap == null) {
      return collectHistoryIds(newProducts, null);
    }
    Set<Id> historyIds = new Set<Id>();
    for (ContractProduct__c product : newProducts) {
      ContractProduct__c oldProduct = oldMap.get(product.Id);
      if (oldProduct == null || isArrRelevantChange(product, oldProduct)) {
        if (product.ContractHistory__c != null) {
          historyIds.add(product.ContractHistory__c);
        }
        if (oldProduct != null && oldProduct.ContractHistory__c != null) {
          historyIds.add(oldProduct.ContractHistory__c);
        }
      }
    }
    return historyIds;
  }

  private static Boolean isArrRelevantChange(
    ContractProduct__c current,
    ContractProduct__c previous
  ) {
    return current.ContractHistory__c != previous.ContractHistory__c ||
      current.Product__c != previous.Product__c ||
      current.Amount__c != previous.Amount__c ||
      current.Quantity__c != previous.Quantity__c ||
      current.UnitPrice__c != previous.UnitPrice__c ||
      current.BillingType__c != previous.BillingType__c ||
      current.Type__c != previous.Type__c ||
      current.StartDate__c != previous.StartDate__c ||
      current.Enddate__c != previous.Enddate__c;
  }

}
