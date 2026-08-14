/**
 * 受注前提検証（請求先・必須項目・見積商品・Amount・同一 Version の Ordered 一意）。
 * 受注ウィザード／ステータス直接変更の両方で同一ルールを使う。
 */
public without sharing class ContractOrderValidationService {
  private static final String HISTORY_TYPE_CANCEL = ContractDomainConstants.HISTORY_TYPE_CANCEL;
  private static final String HISTORY_TYPE_CHANGE = ContractDomainConstants.HISTORY_TYPE_CHANGE;
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;

  public static final String BILLING_ACCOUNT_MISSING_MESSAGE = '請求アカウントが未設定のため受注できません。';
  public static final String PRODUCTS_MISSING_MESSAGE = '見積商品がないため受注できません。';
  public static final String AMOUNT_MISSING_MESSAGE = '見積商品の金額が未設定のため受注できません。見積ウィザードで保存してから受注してください。';
  public static final String DUPLICATE_ORDERED_VERSION_MESSAGE = '同一契約サービスに同じ Version の受注済み履歴が既にあるため受注できません。';
  public static final String INVOICE_SETTING_ONLY_CHANGE_MESSAGE = '請求設定だけの変更では受注できません。まだ請求していない場合は、差し戻して元の見積の請求設定を編集してください。';

  /**
   * コントローラ用。問題があれば AuraHandledException。
   */
  public static void assertReadyForOrder(ContractHistory__c history) {
    List<String> errors = resolveOrderReadinessErrors(
      new List<ContractHistory__c>{ history }
    );
    String message = errors.isEmpty() ? null : errors[0];
    if (String.isBlank(message)) {
      return;
    }
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    throw ex;
  }

  /**
   * トリガ用。対象履歴に addError する。
   */
  public static void applyOrderReadinessErrors(
    List<ContractHistory__c> histories
  ) {
    if (histories == null || histories.isEmpty()) {
      return;
    }
    List<String> errors = resolveOrderReadinessErrors(histories);
    for (Integer i = 0; i < histories.size(); i++) {
      if (histories[i] == null || String.isBlank(errors[i])) {
        continue;
      }
      histories[i].addError(errors[i]);
    }
  }

  @TestVisible
  static List<String> resolveOrderReadinessErrors(
    List<ContractHistory__c> histories
  ) {
    List<String> errors = new List<String>();
    if (histories == null || histories.isEmpty()) {
      return errors;
    }

    hydrateVersionAndServiceFields(histories);

    Set<Id> contractServiceIds = new Set<Id>();
    Set<Id> historyIdsForProducts = new Set<Id>();
    Set<Id> selfHistoryIds = new Set<Id>();
    Map<String, Integer> becomingCountByVersionKey = new Map<String, Integer>();
    for (ContractHistory__c history : histories) {
      if (history == null) {
        continue;
      }
      if (history.Id != null) {
        selfHistoryIds.add(history.Id);
      }
      if (history.ContractService__c != null) {
        contractServiceIds.add(history.ContractService__c);
      }
      String versionKey = orderedVersionKey(history);
      if (versionKey != null) {
        Integer count = becomingCountByVersionKey.containsKey(versionKey)
          ? becomingCountByVersionKey.get(versionKey)
          : 0;
        becomingCountByVersionKey.put(versionKey, count + 1);
      }
      // 商品検証は Id 確定後のみ（before insert では未採番）
      if (history.Id != null && history.Type__c != HISTORY_TYPE_CANCEL) {
        historyIdsForProducts.add(history.Id);
      }
    }

    Set<String> existingOrderedVersionKeys = loadExistingOrderedVersionKeys(
      contractServiceIds,
      selfHistoryIds
    );

    Map<Id, Id> billingAccountIdByServiceId = new Map<Id, Id>();
    if (!contractServiceIds.isEmpty()) {
      for (ContractService__c service : [
        SELECT Id, BiilingAcccount__c
        FROM ContractService__c
        WHERE Id IN :contractServiceIds
        WITH SYSTEM_MODE
      ]) {
        billingAccountIdByServiceId.put(service.Id, service.BiilingAcccount__c);
      }
    }

    Set<Id> billingAccountIds = new Set<Id>();
    for (Id billingAccountId : billingAccountIdByServiceId.values()) {
      if (billingAccountId != null) {
        billingAccountIds.add(billingAccountId);
      }
    }
    Map<Id, Map<String, Object>> billingFieldsByAccountId = loadBillingCustomFieldsById(
      billingAccountIds
    );

    Map<Id, List<ContractProduct__c>> productsByHistoryId = new Map<Id, List<ContractProduct__c>>();
    if (!historyIdsForProducts.isEmpty()) {
      for (ContractProduct__c product : [
        SELECT
          Id,
          ContractHistory__c,
          Quantity__c,
          Amount__c,
          Type__c,
          PreviousContractProduct__c,
          Product__c,
          UnitPrice__c,
          BillingType__c,
          InvoiceSetting__c,
          StartDate__c,
          Enddate__c
        FROM ContractProduct__c
        WHERE ContractHistory__c IN :historyIdsForProducts
        WITH SYSTEM_MODE
      ]) {
        if (!productsByHistoryId.containsKey(product.ContractHistory__c)) {
          productsByHistoryId.put(
            product.ContractHistory__c,
            new List<ContractProduct__c>()
          );
        }
        productsByHistoryId.get(product.ContractHistory__c).add(product);
      }
    }

    for (ContractHistory__c history : histories) {
      if (history == null) {
        errors.add(BILLING_ACCOUNT_MISSING_MESSAGE);
        continue;
      }

      Id billingAccountId = history.ContractService__c == null
        ? null
        : billingAccountIdByServiceId.get(history.ContractService__c);
      if (billingAccountId == null) {
        errors.add(BILLING_ACCOUNT_MISSING_MESSAGE);
        continue;
      }

      String billingValidationError = OrderWizardFieldService.validateBillingCustomFields(
        billingFieldsByAccountId.containsKey(billingAccountId)
          ? billingFieldsByAccountId.get(billingAccountId)
          : new Map<String, Object>()
      );
      if (String.isNotBlank(billingValidationError)) {
        errors.add(billingValidationError);
        continue;
      }

      String versionKey = orderedVersionKey(history);
      if (
        versionKey != null &&
        (existingOrderedVersionKeys.contains(versionKey) ||
        becomingCountByVersionKey.get(versionKey) > 1)
      ) {
        errors.add(DUPLICATE_ORDERED_VERSION_MESSAGE);
        continue;
      }

      if (history.Type__c == HISTORY_TYPE_CANCEL) {
        errors.add(null);
        continue;
      }

      // before insert（Id 未採番）は商品検証不可。通常受注は Estimate→Ordered 更新。
      if (history.Id == null) {
        errors.add(null);
        continue;
      }

      List<ContractProduct__c> products = productsByHistoryId.containsKey(
          history.Id
        )
        ? productsByHistoryId.get(history.Id)
        : new List<ContractProduct__c>();
      if (products.isEmpty()) {
        errors.add(PRODUCTS_MISSING_MESSAGE);
        continue;
      }

      if (
        history.Type__c == HISTORY_TYPE_CHANGE &&
        ChangeBillingEventUtil.isInvoiceSettingOnlyChange(products)
      ) {
        errors.add(INVOICE_SETTING_ONLY_CHANGE_MESSAGE);
        continue;
      }

      String amountError = null;
      for (ContractProduct__c product : products) {
        if (
          product.Quantity__c != null &&
          product.Quantity__c != 0 &&
          product.Amount__c == null
        ) {
          amountError = AMOUNT_MISSING_MESSAGE;
          break;
        }
      }
      errors.add(amountError);
    }
    return errors;
  }

  /**
   * Trigger.new / 部分 SOQL では Version__c 未取得のことがある。
   * 未取得のときだけ DB から補完する（アクセス時の SObjectException 防止）。
   */
  private static void hydrateVersionAndServiceFields(
    List<ContractHistory__c> histories
  ) {
    Set<Id> needIds = new Set<Id>();
    for (ContractHistory__c history : histories) {
      if (history == null || history.Id == null) {
        continue;
      }
      Map<String, Object> populated = history.getPopulatedFieldsAsMap();
      if (
        !populated.containsKey('Version__c') ||
        !populated.containsKey('ContractService__c')
      ) {
        needIds.add(history.Id);
      }
    }
    if (needIds.isEmpty()) {
      return;
    }
    Map<Id, ContractHistory__c> loaded = new Map<Id, ContractHistory__c>(
      [
        SELECT Id, Version__c, ContractService__c
        FROM ContractHistory__c
        WHERE Id IN :needIds
        WITH SYSTEM_MODE
      ]
    );
    for (ContractHistory__c history : histories) {
      if (history == null || history.Id == null) {
        continue;
      }
      ContractHistory__c full = loaded.get(history.Id);
      if (full == null) {
        continue;
      }
      Map<String, Object> populated = history.getPopulatedFieldsAsMap();
      if (!populated.containsKey('Version__c')) {
        history.Version__c = full.Version__c;
      }
      if (!populated.containsKey('ContractService__c')) {
        history.ContractService__c = full.ContractService__c;
      }
    }
  }

  @TestVisible
  private static String orderedVersionKey(ContractHistory__c history) {
    if (
      history == null ||
      history.ContractService__c == null ||
      history.Version__c == null
    ) {
      return null;
    }
    return String.valueOf(history.ContractService__c) +
      ':' +
      String.valueOf(history.Version__c);
  }

  private static Set<String> loadExistingOrderedVersionKeys(
    Set<Id> contractServiceIds,
    Set<Id> excludeHistoryIds
  ) {
    Set<String> keys = new Set<String>();
    if (contractServiceIds == null || contractServiceIds.isEmpty()) {
      return keys;
    }
    List<ContractHistory__c> orderedHistories;
    if (excludeHistoryIds == null || excludeHistoryIds.isEmpty()) {
      orderedHistories = [
        SELECT Id, ContractService__c, Version__c
        FROM ContractHistory__c
        WHERE
          ContractService__c IN :contractServiceIds
          AND historystatus__c = :HISTORY_STATUS_ORDERED
          AND Version__c != NULL
        WITH SYSTEM_MODE
      ];
    } else {
      orderedHistories = [
        SELECT Id, ContractService__c, Version__c
        FROM ContractHistory__c
        WHERE
          ContractService__c IN :contractServiceIds
          AND historystatus__c = :HISTORY_STATUS_ORDERED
          AND Version__c != NULL
          AND Id NOT IN :excludeHistoryIds
        WITH SYSTEM_MODE
      ];
    }
    for (ContractHistory__c ordered : orderedHistories) {
      String key = orderedVersionKey(ordered);
      if (key != null) {
        keys.add(key);
      }
    }
    return keys;
  }

  private static Map<Id, Map<String, Object>> loadBillingCustomFieldsById(
    Set<Id> billingAccountIds
  ) {
    Map<Id, Map<String, Object>> fieldsById = new Map<Id, Map<String, Object>>();
    if (billingAccountIds == null || billingAccountIds.isEmpty()) {
      return fieldsById;
    }
    for (BillingAccount__c loaded : [
      SELECT
        Id,
        BillingAddressee__c,
        BillingEmailTo__c,
        BillingEmailCc__c,
        BillingEmailBcc__c,
        PaymentTerm__c,
        BillingDayOfMonth__c,
        AdjustInvoiceDateToBusinessDay__c
      FROM BillingAccount__c
      WHERE Id IN :billingAccountIds
      WITH SYSTEM_MODE
    ]) {
      Map<String, Object> values = new Map<String, Object>();
      values.put('BillingAddressee__c', loaded.BillingAddressee__c);
      values.put('BillingEmailTo__c', loaded.BillingEmailTo__c);
      values.put('BillingEmailCc__c', loaded.BillingEmailCc__c);
      values.put('BillingEmailBcc__c', loaded.BillingEmailBcc__c);
      values.put('PaymentTerm__c', loaded.PaymentTerm__c);
      values.put('BillingDayOfMonth__c', loaded.BillingDayOfMonth__c);
      values.put(
        'AdjustInvoiceDateToBusinessDay__c',
        loaded.AdjustInvoiceDateToBusinessDay__c == true
      );
      fieldsById.put(loaded.Id, values);
    }
    return fieldsById;
  }
}
