/**
 * 項目コピー（FieldCopyDefinition__c のマッピングに従う）。
 * コピー先は TargetObject__c（InvoiceProduct__c / Invoice__c / InvoiceLine__c）。
 */
public without sharing class InvoiceProductFieldCopyService {
  public static final String TARGET_INVOICE_PRODUCT = 'InvoiceProduct__c';
  public static final String TARGET_INVOICE = 'Invoice__c';
  public static final String TARGET_INVOICE_LINE = 'InvoiceLine__c';

  public static final String OBJECT_CONTRACT_HISTORY = 'ContractHistory__c';
  public static final String OBJECT_CONTRACT_PRODUCT = 'ContractProduct__c';
  public static final String OBJECT_BILLING_ACCOUNT = 'BillingAccount__c';
  public static final String OBJECT_PRODUCT = 'Product2';
  public static final String OBJECT_OPPORTUNITY = 'Opportunity';
  public static final String OBJECT_ACCOUNT = 'Account';
  public static final String OBJECT_CONTRACT_SERVICE = 'ContractService__c';
  public static final String OBJECT_INVOICE = 'Invoice__c';
  public static final String OBJECT_INVOICE_LINE = 'InvoiceLine__c';
  public static final String OBJECT_INVOICE_PAYMENT = 'InvoicePayment__c';
  public static final String OBJECT_PAYMENT_ALLOCATION = 'InvoicePaymentAllocation__c';

  /** コピー元ごとの固定リレーション（請求商品起点）。 */
  public static final String PATH_CONTRACT_HISTORY = '請求商品 → 契約履歴';
  public static final String PATH_CONTRACT_PRODUCT = '請求商品 → 見積商品';
  public static final String PATH_PRODUCT = '請求商品 → 見積商品 → 商品';
  public static final String PATH_BILLING_ACCOUNT = '請求商品 → 契約履歴 → 契約サービス → 請求アカウント';
  public static final String PATH_OPPORTUNITY = '請求商品 → 契約履歴 → 商談';
  public static final String PATH_ACCOUNT = '請求商品 → 契約履歴 → 契約サービス → 取引先';
  private static final Set<String> ALLOWED_SOURCE_OBJECTS = new Set<String>{
    OBJECT_CONTRACT_HISTORY,
    OBJECT_CONTRACT_PRODUCT,
    OBJECT_BILLING_ACCOUNT,
    OBJECT_PRODUCT,
    OBJECT_OPPORTUNITY,
    OBJECT_ACCOUNT,
    OBJECT_CONTRACT_SERVICE,
    OBJECT_INVOICE,
    OBJECT_INVOICE_LINE,
    OBJECT_INVOICE_PAYMENT,
    OBJECT_PAYMENT_ALLOCATION
  };

  private static final Set<String> ALLOWED_TARGET_OBJECTS = new Set<String>{
    TARGET_INVOICE_PRODUCT,
    TARGET_INVOICE,
    TARGET_INVOICE_LINE
  };

  /**
   * パッケージ標準でコード直書きする To 項目。
   * コピー定義の TargetFieldApiName__c と重複したら検証エラー（必須ロジックを定義行に載せない）。
   */
  private static final Map<String, Set<String>> HARDCODED_TARGET_FIELDS = new Map<String, Set<String>>{
    TARGET_INVOICE_PRODUCT => new Set<String>{
      'ContractProduct__c',
      'ContractHistory__c',
      'Quantity__c',
      'UnitPrice__c',
      'Unit__c',
      'Amount__c',
      'StartDate__c',
      'Enddate__c',
      'InvoiceBucketKey__c',
      'LineBucketKey__c'
    },
    TARGET_INVOICE => new Set<String>{
      'ContractHistory__c',
      'ContractService__c',
      'BillingAccountSnapShot__c',
      'BillingAddresseeSnapShot__c',
      'BillingEmailToSnapShot__c',
      'BillingEmailCcSnapShot__c',
      'BillingEmailBccSnapShot__c',
      'InvoiceDeliveryMethodSnapShot__c',
      'InvoiceDateMethodSnapShot__c',
      'InvoiceDateDayKindSnapShot__c',
      'InvoiceDateDayOfMonthSnapShot__c',
      'InvoiceDateMonthOffsetSnapShot__c',
      'InvoiceDateDayOffsetSnapShot__c',
      'InvoiceDateAdjustSnapShot__c',
      'PaymentTermMethodSnapShot__c',
      'PaymentTermDayKindSnapShot__c',
      'PaymentTermDayOfMonthSnapShot__c',
      'PaymentTermMonthOffsetSnapShot__c',
      'PaymentTermDayOffsetSnapShot__c',
      'PaymentTermAdjustSnapShot__c',
      'InvoiceDate__c',
      'PaymentScheduledDate__c',
      'Amount__c',
      'TaxPercent__c',
      'TaxAmount__c',
      'PeriodLineAmountTotal__c',
      'MergeKey__c',
      'SourcePeriodLineIds__c',
      'IsManuallyAdjusted__c',
      'IsAmountAdjusted__c',
      'IsSplitMoved__c',
      'SystemIntegrationDate__c',
      'PaymentClearingCompletedDate__c'
    },
    TARGET_INVOICE_LINE => new Set<String>{
      'Invoice__c',
      'ContractProduct__c',
      'Product__c',
      'Unit__c',
      'ProductName__c',
      'UnitPrice__c',
      'Quantity__c',
      'Amount__c',
      'PeriodLabel__c',
      'LineMergeKey__c',
      'HistoryVersionLabel__c',
      'SourcePeriodLineIds__c',
      'ServicePeriodStartDate__c',
      'ServicePeriodEndDate__c',
      'RevenueRecognitionBasis__c',
      'IsManuallyAdjusted__c',
      'IsAmountAdjusted__c',
      'IsSplitMoved__c'
    }
  };

  public class FieldCopyException extends Exception {
  }

  /** ハードコード To 項目（定義行との重複チェック用）。テストからも参照する。 */
  public static Set<String> getHardcodedTargetFieldApiNames(
    String targetObjectApiName
  ) {
    Set<String> fields = HARDCODED_TARGET_FIELDS.get(targetObjectApiName);
    return fields == null ? new Set<String>() : new Set<String>(fields);
  }

  @TestVisible
  private static List<FieldCopyDefinition__c> cachedDefinitions;
  private static Map<Id, ContractHistory__c> cachedHistoriesById = new Map<Id, ContractHistory__c>();
  private static Map<Id, ContractService__c> cachedServicesById = new Map<Id, ContractService__c>();
  private static Map<Id, ContractProduct__c> cachedContractProductsById = new Map<Id, ContractProduct__c>();
  private static Map<Id, Set<String>> cachedContractProductFieldsById = new Map<Id, Set<String>>();
  private static Map<Id, BillingAccount__c> cachedBillingAccountsById = new Map<Id, BillingAccount__c>();
  private static Map<Id, Set<String>> cachedBillingAccountFieldsById = new Map<Id, Set<String>>();
  private static Map<Id, Product2> cachedProductsById = new Map<Id, Product2>();
  private static Map<Id, Set<String>> cachedProductFieldsById = new Map<Id, Set<String>>();
  private static Map<Id, Opportunity> cachedOpportunitiesById = new Map<Id, Opportunity>();
  private static Map<Id, Set<String>> cachedOpportunityFieldsById = new Map<Id, Set<String>>();
  private static Map<Id, Account> cachedAccountsById = new Map<Id, Account>();
  private static Map<Id, Set<String>> cachedAccountFieldsById = new Map<Id, Set<String>>();

  @TestVisible
  static void resetCache() {
    cachedDefinitions = null;
    cachedHistoriesById = new Map<Id, ContractHistory__c>();
    cachedServicesById = new Map<Id, ContractService__c>();
    cachedContractProductsById = new Map<Id, ContractProduct__c>();
    cachedContractProductFieldsById = new Map<Id, Set<String>>();
    cachedBillingAccountsById = new Map<Id, BillingAccount__c>();
    cachedBillingAccountFieldsById = new Map<Id, Set<String>>();
    cachedProductsById = new Map<Id, Product2>();
    cachedProductFieldsById = new Map<Id, Set<String>>();
    cachedOpportunitiesById = new Map<Id, Opportunity>();
    cachedOpportunityFieldsById = new Map<Id, Set<String>>();
    cachedAccountsById = new Map<Id, Account>();
    cachedAccountFieldsById = new Map<Id, Set<String>>();
  }

  private static Boolean cacheCovers(Set<String> have, Set<String> need) {
    return have != null && need != null && have.containsAll(need);
  }

  /**
   * 同一処理で先に読んだコピー元を、Insert 時の再SOQLに使わせる。
   * 仕様: Core 第11.4.2節、第5.2節、第7.10節
   */
  public static void rememberRecords(List<SObject> records) {
    if (records == null || records.isEmpty()) {
      return;
    }
    for (SObject record : records) {
      rememberRecord(record);
    }
  }

  private static void rememberRecord(SObject record) {
    if (record == null || record.Id == null) {
      return;
    }
    Set<String> populated = new Set<String>(
      record.getPopulatedFieldsAsMap().keySet()
    );
    Schema.SObjectType sobjectType = record.getSObjectType();
    if (sobjectType == ContractHistory__c.SObjectType) {
      ContractHistory__c history = (ContractHistory__c) record;
      cachedHistoriesById.put(history.Id, history);
      if (history.getSObject('ContractService__r') != null) {
        rememberRecord(history.getSObject('ContractService__r'));
      }
      return;
    }
    if (sobjectType == ContractService__c.SObjectType) {
      cachedServicesById.put(record.Id, (ContractService__c) record);
      return;
    }
    if (sobjectType == ContractProduct__c.SObjectType) {
      ContractProduct__c contractProduct = (ContractProduct__c) record;
      cachedContractProductsById.put(contractProduct.Id, contractProduct);
      cachedContractProductFieldsById.put(contractProduct.Id, populated);
      if (contractProduct.getSObject('Product__r') != null) {
        rememberRecord(contractProduct.getSObject('Product__r'));
      }
      return;
    }
    if (sobjectType == BillingAccount__c.SObjectType) {
      cachedBillingAccountsById.put(record.Id, (BillingAccount__c) record);
      cachedBillingAccountFieldsById.put(record.Id, populated);
      return;
    }
    if (sobjectType == Product2.SObjectType) {
      cachedProductsById.put(record.Id, (Product2) record);
      cachedProductFieldsById.put(record.Id, populated);
      return;
    }
    if (sobjectType == Opportunity.SObjectType) {
      cachedOpportunitiesById.put(record.Id, (Opportunity) record);
      cachedOpportunityFieldsById.put(record.Id, populated);
      return;
    }
    if (sobjectType == Account.SObjectType) {
      cachedAccountsById.put(record.Id, (Account) record);
      cachedAccountFieldsById.put(record.Id, populated);
    }
  }

  private static SObject findCachedSource(
    String objectApiName,
    Id recordId,
    Set<String> neededFields
  ) {
    if (recordId == null || String.isBlank(objectApiName)) {
      return null;
    }
    if (objectApiName == OBJECT_CONTRACT_HISTORY) {
      return cachedHistoriesById.get(recordId);
    }
    if (objectApiName == OBJECT_CONTRACT_SERVICE) {
      return cachedServicesById.get(recordId);
    }
    if (
      objectApiName == OBJECT_CONTRACT_PRODUCT &&
      cacheCovers(cachedContractProductFieldsById.get(recordId), neededFields)
    ) {
      return cachedContractProductsById.get(recordId);
    }
    if (
      objectApiName == OBJECT_BILLING_ACCOUNT &&
      cacheCovers(cachedBillingAccountFieldsById.get(recordId), neededFields)
    ) {
      return cachedBillingAccountsById.get(recordId);
    }
    if (
      objectApiName == OBJECT_PRODUCT &&
      cacheCovers(cachedProductFieldsById.get(recordId), neededFields)
    ) {
      return cachedProductsById.get(recordId);
    }
    if (
      objectApiName == OBJECT_OPPORTUNITY &&
      cacheCovers(cachedOpportunityFieldsById.get(recordId), neededFields)
    ) {
      return cachedOpportunitiesById.get(recordId);
    }
    if (
      objectApiName == OBJECT_ACCOUNT &&
      cacheCovers(cachedAccountFieldsById.get(recordId), neededFields)
    ) {
      return cachedAccountsById.get(recordId);
    }
    return null;
  }

  /**
   * 請求項目コピー定義を Schema に対して検証する。
   * 不正な定義・型不一致がある場合は FieldCopyException を送出する。
   * TargetObject__c に応じたコピー先オブジェクトのスキーマで検証する
   * （未設定時は InvoiceProduct__c として扱う）。
   */
  public static void validateActiveDefinitions() {
    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    Map<String, Map<String, Schema.SObjectField>> targetFieldsByObject = new Map<String, Map<String, Schema.SObjectField>>();

    for (FieldCopyDefinition__c definition : getActiveDefinitions()) {
      String targetObjectApiName = resolveTargetObject(definition);
      Map<String, Schema.SObjectField> targetFields = targetFieldsByObject.get(
        targetObjectApiName
      );
      if (targetFields == null) {
        Schema.SObjectType targetType = globalDescribe.get(targetObjectApiName);
        if (targetType == null) {
          throw new FieldCopyException(
            '請求項目コピー「' +
              definitionLabel(definition) +
              '」のコピー先オブジェクト「' +
              targetObjectApiName +
              '」が組織に存在しません。'
          );
        }
        targetFields = targetType.getDescribe().fields.getMap();
        targetFieldsByObject.put(targetObjectApiName, targetFields);
      }
      validateDefinition(
        definition,
        targetObjectApiName,
        targetFields,
        globalDescribe
      );
    }
  }

  /**
   * 指定コピー先オブジェクト向けの定義だけを適用する。
   * コピー先に既に値がある項目は上書きしない（Data Loader 等で入れた値を尊重）。
   */
  public static void applyCopies(
    SObject target,
    String targetObjectApiName,
    Map<String, SObject> sourceByObjectApiName
  ) {
    applyCopies(target, targetObjectApiName, sourceByObjectApiName, false);
  }

  /**
   * @param skipMissingSources true のとき、コピー元が解決できない定義はスキップ（Insert トリガ用）
   */
  public static void applyCopies(
    SObject target,
    String targetObjectApiName,
    Map<String, SObject> sourceByObjectApiName,
    Boolean skipMissingSources
  ) {
    if (target == null) {
      return;
    }
    if (String.isBlank(targetObjectApiName)) {
      targetObjectApiName = TARGET_INVOICE_PRODUCT;
    }
    if (sourceByObjectApiName == null) {
      sourceByObjectApiName = new Map<String, SObject>();
    }

    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    Schema.SObjectType targetType = globalDescribe.get(targetObjectApiName);
    if (targetType == null) {
      throw new FieldCopyException(
        '請求項目コピーのコピー先オブジェクト「' +
          targetObjectApiName +
          '」が組織に存在しません。'
      );
    }
    Map<String, Schema.SObjectField> targetFields = targetType.getDescribe()
      .fields.getMap();

    for (
      FieldCopyDefinition__c definition : getActiveDefinitions(
        targetObjectApiName
      )
    ) {
      validateDefinition(
        definition,
        targetObjectApiName,
        targetFields,
        globalDescribe
      );

      String targetApiName = definition.TargetFieldApiName__c;
      if (!isBlankTargetValue(target.get(targetApiName))) {
        continue;
      }

      SObject source = sourceByObjectApiName.get(definition.SourceObject__c);
      if (source == null) {
        if (skipMissingSources == true) {
          continue;
        }
        throw new FieldCopyException(
          '請求項目コピー「' +
            definitionLabel(definition) +
            '」のコピー元「' +
            definition.SourceObject__c +
            '」の参照先が見つかりません（' +
            relationPathLabel(definition.SourceObject__c) +
            '）。'
        );
      }

      Schema.DescribeFieldResult targetDescribe = targetFields.get(
          targetApiName
        )
        .getDescribe();
      String sourceApiName = definition.SourceFieldApiName__c;

      Object rawValue;
      try {
        rawValue = source.get(sourceApiName);
      } catch (Exception ex) {
        throw buildException(
          definition,
          'コピー元項目「' +
            sourceApiName +
            '」の値取得に失敗しました。' +
            blankToEmpty(ex.getMessage())
        );
      }

      Object coerced;
      try {
        coerced = coerceForTarget(targetDescribe, rawValue);
      } catch (Exception ex) {
        throw buildException(
          definition,
          'コピー先項目「' +
            targetApiName +
            '」への値変換に失敗しました。' +
            blankToEmpty(ex.getMessage())
        );
      }
      if (isBlankTargetValue(coerced)) {
        continue;
      }
      target.put(targetApiName, coerced);
    }
  }

  /**
   * before insert トリガから呼ぶ一括適用。コピー元を一括取得し、空欄項目だけ埋める。
   * 仕様: Core 第11.4.2節
   */
  public static void applyOnBeforeInsert(
    List<SObject> records,
    String targetObjectApiName
  ) {
    if (records == null || records.isEmpty()) {
      return;
    }
    if (String.isBlank(targetObjectApiName)) {
      return;
    }
    InsertSourceMaps maps = loadInsertSourceMaps(records, targetObjectApiName);
    for (SObject record : records) {
      Map<String, SObject> sources = resolveInsertSources(
        record,
        targetObjectApiName,
        maps
      );
      applyHardcodedCoreFields(record, targetObjectApiName, sources);
      FieldCopyDefinitionService.apply(
        record,
        targetObjectApiName,
        null,
        sources
      );
    }
  }

  /**
   * Insert 時に必須コアをコードで埋める（空欄のみ。コピー定義より先）。
   */
  @TestVisible
  private static void applyHardcodedCoreFields(
    SObject record,
    String targetObjectApiName,
    Map<String, SObject> sources
  ) {
    if (record == null || sources == null) {
      return;
    }
    if (targetObjectApiName == TARGET_INVOICE) {
      applyHardcodedInvoiceBillingAccountSnapshot(
        (Invoice__c) record,
        (BillingAccount__c) sources.get(OBJECT_BILLING_ACCOUNT)
      );
      return;
    }
    if (targetObjectApiName == TARGET_INVOICE_LINE) {
      applyHardcodedInvoiceLineProductFields(
        (InvoiceLine__c) record,
        (ContractProduct__c) sources.get(OBJECT_CONTRACT_PRODUCT)
      );
    }
  }

  /** 仕様: Core 第3.3.5節、第3.3.7節、第5.2節 */
  public static void applyHardcodedInvoiceBillingAccountSnapshot(
    Invoice__c invoice,
    BillingAccount__c billingAccount
  ) {
    if (invoice == null || billingAccount == null) {
      return;
    }
    if (invoice.BillingAccountSnapShot__c == null) {
      invoice.BillingAccountSnapShot__c = billingAccount.Id;
    }
    if (String.isBlank(invoice.BillingAddresseeSnapShot__c)) {
      invoice.BillingAddresseeSnapShot__c = billingAccount.BillingAddressee__c;
    }
    if (String.isBlank(invoice.BillingEmailToSnapShot__c)) {
      invoice.BillingEmailToSnapShot__c = billingAccount.BillingEmailTo__c;
    }
    if (String.isBlank(invoice.BillingEmailCcSnapShot__c)) {
      invoice.BillingEmailCcSnapShot__c = billingAccount.BillingEmailCc__c;
    }
    if (String.isBlank(invoice.BillingEmailBccSnapShot__c)) {
      invoice.BillingEmailBccSnapShot__c = billingAccount.BillingEmailBcc__c;
    }
    if (String.isBlank(invoice.InvoiceDeliveryMethodSnapShot__c)) {
      invoice.InvoiceDeliveryMethodSnapShot__c = billingAccount.InvoiceDeliveryMethod__c;
    }
    BillingScheduleService.applySnapshots(invoice, billingAccount);
    if (String.isBlank(invoice.BillingAccountKeySnapShot__c)) {
      invoice.BillingAccountKeySnapShot__c = billingAccount.BillingAccountKey__c;
    }
  }

  @TestVisible
  private static void applyHardcodedInvoiceLineProductFields(
    InvoiceLine__c line,
    ContractProduct__c contractProduct
  ) {
    if (line == null || contractProduct == null) {
      return;
    }
    if (line.Product__c == null) {
      line.Product__c = contractProduct.Product__c;
    }
    if (String.isBlank(line.Unit__c)) {
      line.Unit__c = contractProduct.Unit__c;
    }
  }

  @TestVisible
  static Boolean isBlankTargetValue(Object value) {
    if (value == null) {
      return true;
    }
    if (value instanceof String) {
      return String.isBlank((String) value);
    }
    return false;
  }

  private class InsertSourceMaps {
    Map<Id, ContractProduct__c> contractProductById = new Map<Id, ContractProduct__c>();
    Map<Id, ContractHistory__c> contractHistoryById = new Map<Id, ContractHistory__c>();
    Map<Id, BillingAccount__c> billingAccountById = new Map<Id, BillingAccount__c>();
    Map<Id, Product2> productById = new Map<Id, Product2>();
    Map<Id, Opportunity> opportunityById = new Map<Id, Opportunity>();
    Map<Id, Account> accountById = new Map<Id, Account>();
    Map<Id, Id> billingAccountIdByHistoryId = new Map<Id, Id>();
    Map<Id, Id> billingAccountIdByServiceId = new Map<Id, Id>();
    Map<Id, Id> accountIdByServiceId = new Map<Id, Id>();
  }

  private static InsertSourceMaps loadInsertSourceMaps(
    List<SObject> records,
    String targetObjectApiName
  ) {
    InsertSourceMaps maps = new InsertSourceMaps();
    Set<Id> contractProductIds = new Set<Id>();
    Set<Id> contractHistoryIds = new Set<Id>();
    Set<Id> billingAccountIds = new Set<Id>();
    Set<Id> contractServiceIds = new Set<Id>();
    Set<Id> accountIds = new Set<Id>();

    for (SObject record : records) {
      if (targetObjectApiName == TARGET_INVOICE_PRODUCT) {
        Id cpId = (Id) record.get('ContractProduct__c');
        Id histId = (Id) record.get('ContractHistory__c');
        if (cpId != null) {
          contractProductIds.add(cpId);
        }
        if (histId != null) {
          contractHistoryIds.add(histId);
        }
      } else if (targetObjectApiName == TARGET_INVOICE) {
        Id histId = (Id) record.get('ContractHistory__c');
        Id serviceId = (Id) record.get('ContractService__c');
        Id baId = (Id) record.get('BillingAccountSnapShot__c');
        if (histId != null) {
          contractHistoryIds.add(histId);
        }
        if (serviceId != null) {
          contractServiceIds.add(serviceId);
        }
        if (baId != null) {
          billingAccountIds.add(baId);
        }
      } else if (targetObjectApiName == TARGET_INVOICE_LINE) {
        Id cpId = (Id) record.get('ContractProduct__c');
        if (cpId != null) {
          contractProductIds.add(cpId);
        }
      }
    }

    if (!contractHistoryIds.isEmpty()) {
      Set<Id> missingHistoryIds = new Set<Id>();
      for (Id historyId : contractHistoryIds) {
        if (cachedHistoriesById.containsKey(historyId)) {
          maps.contractHistoryById.put(historyId, cachedHistoriesById.get(historyId));
        } else {
          missingHistoryIds.add(historyId);
        }
      }
      if (!missingHistoryIds.isEmpty()) {
        for (ContractHistory__c history : [
          SELECT
            Id,
            Opportunity__c,
            ContractService__c,
            ContractService__r.BiilingAcccount__c,
            ContractService__r.Account__c
          FROM ContractHistory__c
          WHERE Id IN :missingHistoryIds
          WITH SYSTEM_MODE
        ]) {
          cachedHistoriesById.put(history.Id, history);
          maps.contractHistoryById.put(history.Id, history);
        }
      }
      for (ContractHistory__c history : maps.contractHistoryById.values()) {
        if (
          history.ContractService__r != null &&
          history.ContractService__r.BiilingAcccount__c != null
        ) {
          maps.billingAccountIdByHistoryId.put(
            history.Id,
            history.ContractService__r.BiilingAcccount__c
          );
          billingAccountIds.add(history.ContractService__r.BiilingAcccount__c);
        }
        if (
          history.ContractService__c != null &&
          history.ContractService__r != null &&
          history.ContractService__r.BiilingAcccount__c != null
        ) {
          maps.billingAccountIdByServiceId.put(
            history.ContractService__c,
            history.ContractService__r.BiilingAcccount__c
          );
        }
        if (
          history.ContractService__c != null &&
          history.ContractService__r != null &&
          history.ContractService__r.Account__c != null
        ) {
          maps.accountIdByServiceId.put(
            history.ContractService__c,
            history.ContractService__r.Account__c
          );
          accountIds.add(history.ContractService__r.Account__c);
        }
      }
    }

    if (!contractServiceIds.isEmpty()) {
      Set<Id> missingServiceIds = new Set<Id>();
      for (Id serviceId : contractServiceIds) {
        if (cachedServicesById.containsKey(serviceId)) {
          ContractService__c cached = cachedServicesById.get(serviceId);
          if (cached.BiilingAcccount__c != null) {
            maps.billingAccountIdByServiceId.put(cached.Id, cached.BiilingAcccount__c);
            billingAccountIds.add(cached.BiilingAcccount__c);
          }
          if (cached.Account__c != null) {
            maps.accountIdByServiceId.put(cached.Id, cached.Account__c);
            accountIds.add(cached.Account__c);
          }
        } else {
          missingServiceIds.add(serviceId);
        }
      }
      if (!missingServiceIds.isEmpty()) {
        for (ContractService__c service : [
          SELECT Id, BiilingAcccount__c, Account__c
          FROM ContractService__c
          WHERE Id IN :missingServiceIds
          WITH SYSTEM_MODE
        ]) {
          cachedServicesById.put(service.Id, service);
          if (service.BiilingAcccount__c != null) {
            maps.billingAccountIdByServiceId.put(
              service.Id,
              service.BiilingAcccount__c
            );
            billingAccountIds.add(service.BiilingAcccount__c);
          }
          if (service.Account__c != null) {
            maps.accountIdByServiceId.put(service.Id, service.Account__c);
            accountIds.add(service.Account__c);
          }
        }
      }
    }

    Set<String> cpFields = getSourceFieldApiNames(
      OBJECT_CONTRACT_PRODUCT,
      targetObjectApiName
    );
    cpFields.add('Id');
    cpFields.add('Product__c');
    cpFields.add('ContractHistory__c');
    cpFields.add('Unit__c');
    if (!contractProductIds.isEmpty()) {
      Set<Id> missingCpIds = new Set<Id>();
      for (Id cpId : contractProductIds) {
        if (
          cachedContractProductsById.containsKey(cpId) &&
          cacheCovers(cachedContractProductFieldsById.get(cpId), cpFields)
        ) {
          maps.contractProductById.put(cpId, cachedContractProductsById.get(cpId));
        } else {
          missingCpIds.add(cpId);
        }
      }
      if (!missingCpIds.isEmpty()) {
        String cpSoql =
          'SELECT ' +
          String.join(new List<String>(cpFields), ',') +
          ' FROM ContractProduct__c WHERE Id IN :missingCpIds WITH SYSTEM_MODE';
        for (ContractProduct__c cp : Database.query(cpSoql)) {
          cachedContractProductsById.put(cp.Id, cp);
          cachedContractProductFieldsById.put(cp.Id, new Set<String>(cpFields));
          maps.contractProductById.put(cp.Id, cp);
        }
      }
      for (ContractProduct__c cp : maps.contractProductById.values()) {
        if (
          cp.ContractHistory__c != null &&
          !maps.contractHistoryById.containsKey(cp.ContractHistory__c)
        ) {
          contractHistoryIds.add(cp.ContractHistory__c);
        }
      }
    }

    // ContractProduct 経由で履歴が増えた場合の追加ロード
    Set<Id> missingHistoryIds = new Set<Id>();
    for (Id histId : contractHistoryIds) {
      if (!maps.contractHistoryById.containsKey(histId)) {
        missingHistoryIds.add(histId);
      }
    }
    if (!missingHistoryIds.isEmpty()) {
      for (ContractHistory__c history : [
        SELECT
          Id,
          Opportunity__c,
          ContractService__c,
          ContractService__r.BiilingAcccount__c,
          ContractService__r.Account__c
        FROM ContractHistory__c
        WHERE Id IN :missingHistoryIds
        WITH SYSTEM_MODE
      ]) {
        cachedHistoriesById.put(history.Id, history);
        maps.contractHistoryById.put(history.Id, history);
        if (
          history.ContractService__r != null &&
          history.ContractService__r.BiilingAcccount__c != null
        ) {
          maps.billingAccountIdByHistoryId.put(
            history.Id,
            history.ContractService__r.BiilingAcccount__c
          );
          billingAccountIds.add(history.ContractService__r.BiilingAcccount__c);
        }
      }
    }

    Set<Id> productIds = new Set<Id>();
    Set<Id> opportunityIds = new Set<Id>();
    for (ContractProduct__c cp : maps.contractProductById.values()) {
      if (cp.Product__c != null) {
        productIds.add(cp.Product__c);
      }
    }
    for (ContractHistory__c history : maps.contractHistoryById.values()) {
      if (history.Opportunity__c != null) {
        opportunityIds.add(history.Opportunity__c);
      }
      if (
        history.ContractService__r != null &&
        history.ContractService__r.Account__c != null
      ) {
        accountIds.add(history.ContractService__r.Account__c);
      }
    }

    Set<String> baFields = getSourceFieldApiNames(
      OBJECT_BILLING_ACCOUNT,
      targetObjectApiName
    );
    baFields.add('Id');
    baFields.add('BillingAddressee__c');
    baFields.add('BillingEmailTo__c');
    baFields.add('BillingEmailCc__c');
    baFields.add('BillingEmailBcc__c');
    baFields.add('InvoiceDeliveryMethod__c');
    baFields.addAll(BillingScheduleService.BILLING_ACCOUNT_SCHEDULE_FIELDS);
    baFields.add('BillingAccountKey__c');
    if (!billingAccountIds.isEmpty()) {
      Set<Id> missingBaIds = new Set<Id>();
      for (Id baId : billingAccountIds) {
        if (
          cachedBillingAccountsById.containsKey(baId) &&
          cacheCovers(cachedBillingAccountFieldsById.get(baId), baFields)
        ) {
          maps.billingAccountById.put(baId, cachedBillingAccountsById.get(baId));
        } else {
          missingBaIds.add(baId);
        }
      }
      if (!missingBaIds.isEmpty()) {
        String baSoql =
          'SELECT ' +
          String.join(new List<String>(baFields), ',') +
          ' FROM BillingAccount__c WHERE Id IN :missingBaIds WITH SYSTEM_MODE';
        for (BillingAccount__c ba : Database.query(baSoql)) {
          cachedBillingAccountsById.put(ba.Id, ba);
          cachedBillingAccountFieldsById.put(ba.Id, new Set<String>(baFields));
          maps.billingAccountById.put(ba.Id, ba);
        }
      }
    }

    Set<String> productFields = getSourceFieldApiNames(
      OBJECT_PRODUCT,
      targetObjectApiName
    );
    productFields.add('Id');
    if (!productIds.isEmpty() && !productFields.isEmpty()) {
      Set<Id> missingProductIds = new Set<Id>();
      for (Id productId : productIds) {
        if (
          cachedProductsById.containsKey(productId) &&
          cacheCovers(cachedProductFieldsById.get(productId), productFields)
        ) {
          maps.productById.put(productId, cachedProductsById.get(productId));
        } else {
          missingProductIds.add(productId);
        }
      }
      if (!missingProductIds.isEmpty()) {
        String productSoql =
          'SELECT ' +
          String.join(new List<String>(productFields), ',') +
          ' FROM Product2 WHERE Id IN :missingProductIds WITH SYSTEM_MODE';
        for (Product2 product : Database.query(productSoql)) {
          cachedProductsById.put(product.Id, product);
          cachedProductFieldsById.put(product.Id, new Set<String>(productFields));
          maps.productById.put(product.Id, product);
        }
      }
    }

    Set<String> oppFields = getSourceFieldApiNames(
      OBJECT_OPPORTUNITY,
      targetObjectApiName
    );
    oppFields.add('Id');
    if (!opportunityIds.isEmpty() && oppFields.size() > 1) {
      Set<Id> missingOppIds = new Set<Id>();
      for (Id opportunityId : opportunityIds) {
        if (
          cachedOpportunitiesById.containsKey(opportunityId) &&
          cacheCovers(cachedOpportunityFieldsById.get(opportunityId), oppFields)
        ) {
          maps.opportunityById.put(
            opportunityId,
            cachedOpportunitiesById.get(opportunityId)
          );
        } else {
          missingOppIds.add(opportunityId);
        }
      }
      if (!missingOppIds.isEmpty()) {
        String oppSoql =
          'SELECT ' +
          String.join(new List<String>(oppFields), ',') +
          ' FROM Opportunity WHERE Id IN :missingOppIds WITH SYSTEM_MODE';
        for (Opportunity opp : Database.query(oppSoql)) {
          cachedOpportunitiesById.put(opp.Id, opp);
          cachedOpportunityFieldsById.put(opp.Id, new Set<String>(oppFields));
          maps.opportunityById.put(opp.Id, opp);
        }
      }
    }

    Set<String> accountFields = getSourceFieldApiNames(
      OBJECT_ACCOUNT,
      targetObjectApiName
    );
    accountFields.add('Id');
    if (!accountIds.isEmpty() && accountFields.size() > 1) {
      Set<Id> missingAccountIds = new Set<Id>();
      for (Id accountId : accountIds) {
        if (
          cachedAccountsById.containsKey(accountId) &&
          cacheCovers(cachedAccountFieldsById.get(accountId), accountFields)
        ) {
          maps.accountById.put(accountId, cachedAccountsById.get(accountId));
        } else {
          missingAccountIds.add(accountId);
        }
      }
      if (!missingAccountIds.isEmpty()) {
        String accountSoql =
          'SELECT ' +
          String.join(new List<String>(accountFields), ',') +
          ' FROM Account WHERE Id IN :missingAccountIds WITH SYSTEM_MODE';
        for (Account account : Database.query(accountSoql)) {
          cachedAccountsById.put(account.Id, account);
          cachedAccountFieldsById.put(account.Id, new Set<String>(accountFields));
          maps.accountById.put(account.Id, account);
        }
      }
    }

    return maps;
  }

  private static Map<String, SObject> resolveInsertSources(
    SObject record,
    String targetObjectApiName,
    InsertSourceMaps maps
  ) {
    Map<String, SObject> sources = new Map<String, SObject>();
    if (targetObjectApiName == TARGET_INVOICE_LINE) {
      Id cpId = (Id) record.get('ContractProduct__c');
      ContractProduct__c cp = maps.contractProductById.get(cpId);
      if (cp != null) {
        sources.put(OBJECT_CONTRACT_PRODUCT, cp);
        if (
          cp.Product__c != null && maps.productById.containsKey(cp.Product__c)
        ) {
          sources.put(OBJECT_PRODUCT, maps.productById.get(cp.Product__c));
        }
      }
      return sources;
    }

    if (targetObjectApiName == TARGET_INVOICE) {
      Id serviceId = (Id) record.get('ContractService__c');
      Id baId = (Id) record.get('BillingAccountSnapShot__c');
      if (baId == null) {
        baId = maps.billingAccountIdByServiceId.get(serviceId);
      }
      if (baId == null) {
        Id histIdForBa = (Id) record.get('ContractHistory__c');
        baId = maps.billingAccountIdByHistoryId.get(histIdForBa);
      }
      if (baId != null && maps.billingAccountById.containsKey(baId)) {
        sources.put(OBJECT_BILLING_ACCOUNT, maps.billingAccountById.get(baId));
      }
      Id histId = (Id) record.get('ContractHistory__c');
      if (histId != null && maps.contractHistoryById.containsKey(histId)) {
        sources.put(
          OBJECT_CONTRACT_HISTORY,
          maps.contractHistoryById.get(histId)
        );
      }
      Id accountId = maps.accountIdByServiceId.get(serviceId);
      if (
        accountId == null &&
        histId != null &&
        maps.contractHistoryById.containsKey(histId)
      ) {
        ContractHistory__c history = maps.contractHistoryById.get(histId);
        if (
          history.ContractService__r != null &&
          history.ContractService__r.Account__c != null
        ) {
          accountId = history.ContractService__r.Account__c;
        }
      }
      if (accountId != null && maps.accountById.containsKey(accountId)) {
        sources.put(OBJECT_ACCOUNT, maps.accountById.get(accountId));
      }
      return sources;
    }

    // InvoiceProduct__c
    Id cpId = (Id) record.get('ContractProduct__c');
    ContractProduct__c cp = maps.contractProductById.get(cpId);
    if (cp != null) {
      sources.put(OBJECT_CONTRACT_PRODUCT, cp);
      if (
        cp.Product__c != null && maps.productById.containsKey(cp.Product__c)
      ) {
        sources.put(OBJECT_PRODUCT, maps.productById.get(cp.Product__c));
      }
    }
    Id histId = (Id) record.get('ContractHistory__c');
    if (histId == null && cp != null) {
      histId = cp.ContractHistory__c;
    }
    if (histId != null && maps.contractHistoryById.containsKey(histId)) {
      ContractHistory__c history = maps.contractHistoryById.get(histId);
      sources.put(OBJECT_CONTRACT_HISTORY, history);
      if (
        history.Opportunity__c != null &&
        maps.opportunityById.containsKey(history.Opportunity__c)
      ) {
        sources.put(
          OBJECT_OPPORTUNITY,
          maps.opportunityById.get(history.Opportunity__c)
        );
      }
      if (
        history.ContractService__r != null &&
        history.ContractService__r.Account__c != null &&
        maps.accountById.containsKey(history.ContractService__r.Account__c)
      ) {
        sources.put(
          OBJECT_ACCOUNT,
          maps.accountById.get(history.ContractService__r.Account__c)
        );
      }
    }
    Id baId = null;
    if (histId != null) {
      baId = maps.billingAccountIdByHistoryId.get(histId);
    }
    if (baId != null && maps.billingAccountById.containsKey(baId)) {
      sources.put(OBJECT_BILLING_ACCOUNT, maps.billingAccountById.get(baId));
    }
    return sources;
  }

  /**
   * 契約期間明細向けの便宜オーバーロード。
   */
  public static void applyCopies(
    InvoiceProduct__c target,
    Map<String, SObject> sourceByObjectApiName
  ) {
    applyCopies(target, TARGET_INVOICE_PRODUCT, sourceByObjectApiName);
  }

  private static void validateDefinition(
    FieldCopyDefinition__c definition,
    String targetObjectApiName,
    Map<String, Schema.SObjectField> targetFields,
    Map<String, Schema.SObjectType> globalDescribe
  ) {
    if (definition == null) {
      throw new FieldCopyException(
        '請求項目コピーの定義が不正です（定義が空です）。'
      );
    }

    String developerName = definitionLabel(definition);
    if (
      String.isBlank(definition.SourceObject__c) ||
      String.isBlank(definition.SourceFieldApiName__c) ||
      String.isBlank(definition.TargetFieldApiName__c)
    ) {
      throw new FieldCopyException(
        '請求項目コピー「' +
          developerName +
          '」の設定が不完全です（Fromオブジェクト / From項目API名 / To項目API名は必須です）。'
      );
    }

    if (!ALLOWED_TARGET_OBJECTS.contains(targetObjectApiName)) {
      throw new FieldCopyException(
        '請求項目コピー「' +
          developerName +
          '」のコピー先オブジェクト「' +
          targetObjectApiName +
          '」は許可されていません。'
      );
    }

    if (!ALLOWED_SOURCE_OBJECTS.contains(definition.SourceObject__c)) {
      throw new FieldCopyException(
        '請求項目コピー「' +
          developerName +
          '」のコピー元オブジェクト「' +
          definition.SourceObject__c +
          '」は許可されていません。'
      );
    }

    String targetApiName = definition.TargetFieldApiName__c;
    if (!targetFields.containsKey(targetApiName)) {
      throw new FieldCopyException(
        '請求項目コピー「' +
          developerName +
          '」のコピー先項目「' +
          targetApiName +
          '」が「' +
          targetObjectApiName +
          '」に存在しません。'
      );
    }

    Set<String> hardcodedTargets = HARDCODED_TARGET_FIELDS.get(
      targetObjectApiName
    );
    if (hardcodedTargets != null && hardcodedTargets.contains(targetApiName)) {
      throw new FieldCopyException(
        '請求項目コピー「' +
          developerName +
          '」のコピー先項目「' +
          targetApiName +
          '」はパッケージ標準（ハードコード）と重複しています。必須項目はコード側、顧客拡張だけをコピー定義に置いてください。'
      );
    }

    Schema.DescribeFieldResult targetDescribe = targetFields.get(targetApiName)
      .getDescribe();
    if (targetDescribe.isCalculated()) {
      throw new FieldCopyException(
        '請求項目コピー「' +
          developerName +
          '」のコピー先項目「' +
          targetApiName +
          '」は数式項目のためコピーできません。'
      );
    }

    Schema.SObjectType sourceType = globalDescribe.get(
      definition.SourceObject__c
    );
    if (sourceType == null) {
      throw new FieldCopyException(
        '請求項目コピー「' +
          developerName +
          '」のコピー元オブジェクト「' +
          definition.SourceObject__c +
          '」が組織に存在しません。'
      );
    }

    Map<String, Schema.SObjectField> sourceFields = sourceType.getDescribe()
      .fields.getMap();
    String sourceApiName = definition.SourceFieldApiName__c;
    if (!sourceFields.containsKey(sourceApiName)) {
      throw new FieldCopyException(
        '請求項目コピー「' +
          developerName +
          '」のコピー元項目「' +
          sourceApiName +
          '」が「' +
          definition.SourceObject__c +
          '」に存在しません。'
      );
    }

    Schema.DescribeFieldResult sourceDescribe = sourceFields.get(sourceApiName)
      .getDescribe();
    if (
      !areTypesCompatible(sourceDescribe.getType(), targetDescribe.getType())
    ) {
      throw new FieldCopyException(
        '請求項目コピー「' +
          developerName +
          '」のデータ型が一致しません（' +
          definition.SourceObject__c +
          '.' +
          sourceApiName +
          ' → ' +
          targetObjectApiName +
          '.' +
          targetApiName +
          '）。'
      );
    }
  }

  private static FieldCopyException buildException(
    FieldCopyDefinition__c definition,
    String detail
  ) {
    return new FieldCopyException(
      '請求項目コピー「' + definitionLabel(definition) + '」: ' + detail
    );
  }

  private static String definitionLabel(
    FieldCopyDefinition__c definition
  ) {
    if (definition == null || String.isBlank(definition.Name)) {
      return '(不明)';
    }
    return definition.Name;
  }

  /**
   * 未設定の TargetObject__c は後方互換のため InvoiceProduct__c とみなす。
   */
  @TestVisible
  static String resolveTargetObject(FieldCopyDefinition__c definition) {
    if (definition == null || String.isBlank(definition.TargetObject__c)) {
      return TARGET_INVOICE_PRODUCT;
    }
    return definition.TargetObject__c;
  }

  private static Boolean matchesTargetObject(
    FieldCopyDefinition__c definition,
    String targetObjectApiName
  ) {
    return resolveTargetObject(definition) == targetObjectApiName;
  }

  @TestVisible
  static String relationPathLabel(String objectApiName) {
    if (objectApiName == OBJECT_CONTRACT_HISTORY) {
      return PATH_CONTRACT_HISTORY;
    }
    if (objectApiName == OBJECT_CONTRACT_PRODUCT) {
      return PATH_CONTRACT_PRODUCT;
    }
    if (objectApiName == OBJECT_PRODUCT) {
      return PATH_PRODUCT;
    }
    if (objectApiName == OBJECT_BILLING_ACCOUNT) {
      return PATH_BILLING_ACCOUNT;
    }
    if (objectApiName == OBJECT_OPPORTUNITY) {
      return PATH_OPPORTUNITY;
    }
    if (objectApiName == OBJECT_ACCOUNT) {
      return PATH_ACCOUNT;
    }
    return objectApiName;
  }

  private static String blankToEmpty(String value) {
    return String.isBlank(value) ? '' : ' ' + value;
  }

  public static Set<String> getSourceFieldApiNames(String objectApiName) {
    return getSourceFieldApiNames(objectApiName, null);
  }

  public static Set<String> getSourceFieldApiNames(
    String objectApiName,
    String targetObjectApiName
  ) {
    Set<String> fieldApiNames = new Set<String>{ 'Id' };
    if (!ALLOWED_SOURCE_OBJECTS.contains(objectApiName)) {
      return fieldApiNames;
    }
    List<FieldCopyDefinition__c> definitions = String.isBlank(
        targetObjectApiName
      )
      ? getActiveDefinitions()
      : getActiveDefinitions(targetObjectApiName);
    for (FieldCopyDefinition__c definition : definitions) {
      if (
        definition != null &&
        definition.SourceObject__c == objectApiName &&
        String.isNotBlank(definition.SourceFieldApiName__c)
      ) {
        fieldApiNames.add(definition.SourceFieldApiName__c);
      }
    }
    return fieldApiNames;
  }

  public static Set<String> getTargetFieldApiNames() {
    return getTargetFieldApiNames(null);
  }

  public static Set<String> getTargetFieldApiNames(String targetObjectApiName) {
    Set<String> fieldApiNames = new Set<String>();
    List<FieldCopyDefinition__c> definitions = String.isBlank(
        targetObjectApiName
      )
      ? getActiveDefinitions()
      : getActiveDefinitions(targetObjectApiName);
    for (FieldCopyDefinition__c definition : definitions) {
      if (
        definition != null &&
        String.isNotBlank(definition.TargetFieldApiName__c)
      ) {
        fieldApiNames.add(definition.TargetFieldApiName__c);
      }
    }
    return fieldApiNames;
  }

  public static SObject querySourceRecord(String objectApiName, Id recordId) {
    if (recordId == null || !ALLOWED_SOURCE_OBJECTS.contains(objectApiName)) {
      return null;
    }

    Set<String> neededFields = getSourceFieldApiNames(objectApiName);
    SObject cached = findCachedSource(objectApiName, recordId, neededFields);
    if (cached != null) {
      return cached;
    }

    Schema.SObjectType sobjectType = Schema.getGlobalDescribe()
      .get(objectApiName);
    if (sobjectType == null) {
      return null;
    }

    Map<String, Schema.SObjectField> fieldMap = sobjectType.getDescribe()
      .fields.getMap();
    List<String> selectFields = new List<String>();
    for (String fieldApiName : getSourceFieldApiNames(objectApiName)) {
      if (fieldMap.containsKey(fieldApiName)) {
        selectFields.add(fieldApiName);
      }
    }
    addWalkField(selectFields, fieldMap, objectApiName, OBJECT_OPPORTUNITY, 'AccountId');
    addWalkField(selectFields, fieldMap, objectApiName, OBJECT_CONTRACT_SERVICE, 'Account__c');
    addWalkField(
      selectFields,
      fieldMap,
      objectApiName,
      OBJECT_CONTRACT_SERVICE,
      'BiilingAcccount__c'
    );
    addWalkField(
      selectFields,
      fieldMap,
      objectApiName,
      OBJECT_CONTRACT_HISTORY,
      'Opportunity__c'
    );
    addWalkField(
      selectFields,
      fieldMap,
      objectApiName,
      OBJECT_CONTRACT_HISTORY,
      'ContractService__c'
    );
    addWalkField(
      selectFields,
      fieldMap,
      objectApiName,
      OBJECT_INVOICE,
      'BillingAccountSnapShot__c'
    );
    addWalkField(selectFields, fieldMap, objectApiName, OBJECT_INVOICE, 'ContractHistory__c');
    if (selectFields.isEmpty()) {
      selectFields.add('Id');
    }

    String soql =
      'SELECT ' +
      String.join(selectFields, ',') +
      ' FROM ' +
      objectApiName +
      ' WHERE Id = :recordId WITH SYSTEM_MODE LIMIT 1';
    List<SObject> rows = Database.query(soql);
    if (rows.isEmpty()) {
      return null;
    }
    rememberRecord(rows[0]);
    return rows[0];
  }

  /** 仕様: Core 第11.4.2節 */
  public static List<FieldCopyDefinition__c> getActiveDefinitions() {
    if (cachedDefinitions != null) {
      return cachedDefinitions;
    }

    List<FieldCopyDefinition__c> definitions = [
      SELECT
        Name,
        SourceObject__c,
        SourceFieldApiName__c,
        TargetFieldApiName__c,
        TargetObject__c
      FROM FieldCopyDefinition__c
      ORDER BY Name
    ];
    cachedDefinitions = definitions;
    return cachedDefinitions;
  }

  public static List<FieldCopyDefinition__c> getActiveDefinitions(
    String targetObjectApiName
  ) {
    if (String.isBlank(targetObjectApiName)) {
      return getActiveDefinitions();
    }
    List<FieldCopyDefinition__c> filtered = new List<FieldCopyDefinition__c>();
    for (FieldCopyDefinition__c definition : getActiveDefinitions()) {
      if (matchesTargetObject(definition, targetObjectApiName)) {
        filtered.add(definition);
      }
    }
    return filtered;
  }

  @TestVisible
  static Boolean areTypesCompatible(
    Schema.DisplayType sourceType,
    Schema.DisplayType targetType
  ) {
    if (sourceType == null || targetType == null) {
      return false;
    }
    if (sourceType == targetType) {
      return true;
    }
    if (isStringLike(sourceType) && isStringLike(targetType)) {
      return true;
    }
    if (isNumberLike(sourceType) && isNumberLike(targetType)) {
      return true;
    }
    if (isIdLike(sourceType) && isIdLike(targetType)) {
      return true;
    }
    if (
      (sourceType == Schema.DisplayType.DATE ||
      sourceType == Schema.DisplayType.DATETIME) &&
      (targetType == Schema.DisplayType.DATE ||
      targetType == Schema.DisplayType.DATETIME)
    ) {
      return true;
    }
    return false;
  }

  private static Boolean isStringLike(Schema.DisplayType fieldType) {
    return fieldType == Schema.DisplayType.STRING ||
      fieldType == Schema.DisplayType.TEXTAREA ||
      fieldType == Schema.DisplayType.PICKLIST ||
      fieldType == Schema.DisplayType.MULTIPICKLIST ||
      fieldType == Schema.DisplayType.EMAIL ||
      fieldType == Schema.DisplayType.PHONE ||
      fieldType == Schema.DisplayType.URL ||
      fieldType == Schema.DisplayType.COMBOBOX;
  }

  private static Boolean isNumberLike(Schema.DisplayType fieldType) {
    return fieldType == Schema.DisplayType.DOUBLE ||
      fieldType == Schema.DisplayType.CURRENCY ||
      fieldType == Schema.DisplayType.PERCENT ||
      fieldType == Schema.DisplayType.INTEGER ||
      fieldType == Schema.DisplayType.LONG;
  }

  private static Boolean isIdLike(Schema.DisplayType fieldType) {
    return fieldType == Schema.DisplayType.REFERENCE ||
      fieldType == Schema.DisplayType.ID;
  }

  private static Object coerceForTarget(
    Schema.DescribeFieldResult targetDescribe,
    Object rawValue
  ) {
    if (rawValue == null) {
      return null;
    }
    Schema.DisplayType fieldType = targetDescribe.getType();
    if (
      fieldType == Schema.DisplayType.REFERENCE ||
      fieldType == Schema.DisplayType.ID
    ) {
      if (rawValue instanceof Id) {
        return rawValue;
      }
      String text = String.valueOf(rawValue).trim();
      return String.isBlank(text) ? null : (Id) text;
    }
    if (fieldType == Schema.DisplayType.DATE && rawValue instanceof Datetime) {
      return ((Datetime) rawValue).date();
    }
    if (fieldType == Schema.DisplayType.DATETIME && rawValue instanceof Date) {
      Date dateValue = (Date) rawValue;
      return Datetime.newInstance(dateValue, Time.newInstance(0, 0, 0, 0));
    }
    return ContractWizardFieldService.coerceValue(targetDescribe, rawValue);
  }

  private static void addWalkField(
    List<String> selectFields,
    Map<String, Schema.SObjectField> fieldMap,
    String objectApiName,
    String expectedObjectApiName,
    String fieldApiName
  ) {
    if (
      objectApiName != expectedObjectApiName ||
      fieldMap == null ||
      !fieldMap.containsKey(fieldApiName)
    ) {
      return;
    }
    if (!selectFields.contains(fieldApiName)) {
      selectFields.add(fieldApiName);
    }
  }
}
