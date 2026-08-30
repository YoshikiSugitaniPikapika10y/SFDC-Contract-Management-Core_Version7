/**
 * 請求操作追加項目定義。
 * 仕様: Core 第11.4.4節。定義からロック除外へ自動では書かない。
 */
public without sharing class InvoiceOpsFieldService {
  public class ConfigException extends Exception {
  }

  public class FieldDefinition {
    @AuraEnabled
    public String developerName;
    @AuraEnabled
    public String targetObject;
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String fieldType;
    @AuraEnabled
    public Boolean required;
    @AuraEnabled
    public Integer sortOrder;
    @AuraEnabled
    public Integer maxLength;
    @AuraEnabled
    public Integer precision;
    @AuraEnabled
    public Integer scale;
    @AuraEnabled
    public List<ContractWizardFieldService.PicklistOptionDefinition> picklistOptions;
    @AuraEnabled
    public String referenceObjectApiName;
    @AuraEnabled
    public String helpText;
    @AuraEnabled
    public String defaultValue;
    @AuraEnabled
    public Boolean showOnInvoicePurpose;
    @AuraEnabled
    public Boolean showOnNonInvoicePurpose;
  }

  private static List<InvoiceOpsField__mdt> cachedRows;
  private static Boolean validated;

  public static void resetCache() {
    cachedRows = null;
    validated = false;
  }

  @TestVisible
  private static void setCachedRowsForTest(List<InvoiceOpsField__mdt> rows) {
    cachedRows = rows;
    validated = false;
  }

  /** 仕様: Core 第11.4.4節。CMDT変更後は本クラス再デプロイで cacheable を更新する。 */
  @AuraEnabled(cacheable=true)
  public static List<FieldDefinition> getDefinitions() {
    try {
      return buildDefinitions();
    } catch (ConfigException ex) {
      throw toAuraHandled(ex.getMessage());
    }
  }

  /** 仕様: Accounting 第8.7節。画面定義の仕訳追加項目 API 名。 */
  public static Set<String> journalScreenFieldApiNames() {
    Set<String> names = new Set<String>();
    for (FieldDefinition definition : buildDefinitions()) {
      if (definition.targetObject == 'GlJournal__c') {
        names.add(definition.apiName);
      }
    }
    return names;
  }

  private static List<FieldDefinition> buildDefinitions() {
    validateActive();
    List<FieldDefinition> result = new List<FieldDefinition>();
    for (InvoiceOpsField__mdt row : activeRows()) {
      result.add(toDefinition(row));
    }
    return result;
  }

  private static void validateActive() {
    if (validated == true) {
      return;
    }
    for (InvoiceOpsField__mdt row : activeRows()) {
      validateRow(row);
    }
    validated = true;
  }

  private static List<InvoiceOpsField__mdt> activeRows() {
    if (cachedRows != null) {
      List<InvoiceOpsField__mdt> active = new List<InvoiceOpsField__mdt>();
      for (InvoiceOpsField__mdt row : cachedRows) {
        if (row != null && row.Active__c == true) {
          active.add(row);
        }
      }
      return active;
    }
    cachedRows = [
      SELECT
        DeveloperName,
        Active__c,
        TargetObject__c,
        FieldApiName__c,
        LabelOverride__c,
        HelpText__c,
        SortOrder__c,
        Required__c,
        DefaultValue__c,
        ShowOnInvoicePurpose__c,
        ShowOnNonInvoicePurpose__c
      FROM InvoiceOpsField__mdt
      WHERE Active__c = TRUE
      ORDER BY SortOrder__c ASC NULLS LAST, DeveloperName ASC
    ];
    return cachedRows;
  }

  private static void validateRow(InvoiceOpsField__mdt row) {
    String name = developerName(row);
    String target = row.TargetObject__c;
    if (
      target != 'Invoice__c' &&
      target != 'InvoicePayment__c' &&
      target != 'GlJournal__c'
    ) {
      throw new ConfigException(
        '請求操作追加項目「' +
          name +
          '」の対象オブジェクト「' +
          blankToDisplay(target) +
          '」が不正です。Invoice__c / InvoicePayment__c / GlJournal__c のいずれかを指定してください。'
      );
    }
    if (
      target != 'InvoicePayment__c' &&
      (row.ShowOnInvoicePurpose__c == true ||
      row.ShowOnNonInvoicePurpose__c == true)
    ) {
      throw new ConfigException(
        '請求操作追加項目「' +
          name +
          '」は請求書・仕訳に Purpose 表示旗を立てられません。'
      );
    }
    if (String.isBlank(row.FieldApiName__c)) {
      throw new ConfigException(
        '請求操作追加項目「' + name + '」の FieldApiName が未設定です。'
      );
    }
    Schema.SObjectType sobjectType = toSObjectType(target);
    Map<String, Schema.SObjectField> fieldMap = sobjectType.getDescribe()
      .fields.getMap();
    String fieldApiName = row.FieldApiName__c.trim();
    if (!fieldMap.containsKey(fieldApiName)) {
      throw new ConfigException(
        '請求操作追加項目「' +
          name +
          '」の項目「' +
          fieldApiName +
          '」が対象オブジェクトに存在しません。'
      );
    }
    Schema.DescribeFieldResult describe = fieldMap.get(fieldApiName)
      .getDescribe();
    if (!ContractWizardFieldService.isSupportedType(describe.getType())) {
      throw new ConfigException(
        '請求操作追加項目「' +
          name +
          '」の項目「' +
          fieldApiName +
          '」は非対応の型です。'
      );
    }
  }

  private static FieldDefinition toDefinition(InvoiceOpsField__mdt row) {
    Schema.SObjectType sobjectType = toSObjectType(row.TargetObject__c);
    Map<String, Schema.SObjectField> fieldMap = sobjectType.getDescribe()
      .fields.getMap();
    String fieldApiName = row.FieldApiName__c.trim();
    Schema.DescribeFieldResult describe = fieldMap.get(fieldApiName)
      .getDescribe();
    FieldDefinition dto = new FieldDefinition();
    dto.developerName = developerName(row);
    dto.targetObject = row.TargetObject__c;
    dto.apiName = describe.getName();
    dto.label = String.isBlank(row.LabelOverride__c)
      ? describe.getLabel()
      : row.LabelOverride__c;
    dto.fieldType = String.valueOf(describe.getType());
    dto.required = row.Required__c == true;
    dto.sortOrder = row.SortOrder__c == null
      ? null
      : Integer.valueOf(row.SortOrder__c);
    dto.maxLength = describe.getLength();
    dto.precision = describe.getPrecision();
    dto.scale = describe.getScale();
    dto.picklistOptions = ContractWizardFieldService.buildPicklistOptions(
      describe
    );
    dto.helpText = row.HelpText__c;
    dto.defaultValue = row.DefaultValue__c;
    dto.showOnInvoicePurpose = row.ShowOnInvoicePurpose__c == true;
    dto.showOnNonInvoicePurpose = row.ShowOnNonInvoicePurpose__c == true;
    if (describe.getType() == Schema.DisplayType.REFERENCE) {
      List<Schema.SObjectType> refs = describe.getReferenceTo();
      dto.referenceObjectApiName = refs.isEmpty()
        ? null
        : refs[0].getDescribe().getName();
    }
    return dto;
  }

  private static Schema.SObjectType toSObjectType(String target) {
    if (target == 'Invoice__c') {
      return Invoice__c.SObjectType;
    }
    if (target == 'InvoicePayment__c') {
      return InvoicePayment__c.SObjectType;
    }
    if (target == 'GlJournal__c') {
      return GlJournal__c.SObjectType;
    }
    return null;
  }

  private static String developerName(InvoiceOpsField__mdt row) {
    if (row == null || String.isBlank(row.DeveloperName)) {
      return '(不明)';
    }
    return row.DeveloperName;
  }

  private static String blankToDisplay(String value) {
    return String.isBlank(value) ? '(空)' : value;
  }

  /** 仕様: Core 第11.4.4節。対象オブジェクトの画面定義 API 名。 */
  public static Set<String> fieldApiNames(String targetObject) {
    Set<String> names = new Set<String>();
    for (FieldDefinition definition : buildDefinitions()) {
      if (definition.targetObject == targetObject) {
        names.add(definition.apiName);
      }
    }
    return names;
  }

  /** 仕様: Core 第11.4.4節。入出金は Purpose ごとに表示中の項目だけ必須判定する。 */
  public static Set<String> paymentDisplayedFieldApiNames(String purpose) {
      Boolean invoicePurpose = purpose == 'Invoice';
    Set<String> names = new Set<String>();
    for (FieldDefinition definition : buildDefinitions()) {
      if (definition.targetObject != 'InvoicePayment__c') {
        continue;
      }
      if (
        invoicePurpose
          ? definition.showOnInvoicePurpose == true
          : definition.showOnNonInvoicePurpose == true
      ) {
        names.add(definition.apiName);
      }
    }
    return names;
  }

  /** 仕様: Core 第11.4.4節。表示中の必須だけ見る。 */
  public static void applyDisplayedValues(
    SObject record,
    String targetObject,
    Map<String, Object> values,
    Set<String> allowedApiNames
  ) {
    if (record == null || String.isBlank(targetObject) || values == null) {
      return;
    }
    Map<String, Object> incoming = values;
    Schema.SObjectType sobjectType = record.getSObjectType();
    Map<String, Schema.SObjectField> fieldMap = sobjectType.getDescribe()
      .fields.getMap();
    for (FieldDefinition definition : buildDefinitions()) {
      if (definition.targetObject != targetObject) {
        continue;
      }
      if (
        allowedApiNames != null &&
        !allowedApiNames.contains(definition.apiName)
      ) {
        continue;
      }
      if (!incoming.containsKey(definition.apiName)) {
        if (definition.required == true) {
          throw toAuraHandled(
            '請求操作追加項目「' + definition.label + '」は必須です。'
          );
        }
        continue;
      }
      Object raw = incoming.get(definition.apiName);
      if (definition.required == true && isBlankValue(raw)) {
        throw toAuraHandled(
          '請求操作追加項目「' + definition.label + '」は必須です。'
        );
      }
      Schema.SObjectField token = fieldMap.get(definition.apiName);
      if (token == null) {
        continue;
      }
      record.put(
        token,
        ContractWizardFieldService.coerceValue(token.getDescribe(), raw)
      );
    }
  }

  /** 仕様: Core 第11.4.4節。 */
  public static Map<String, Object> readValues(
    SObject record,
    String targetObject
  ) {
    Map<String, Object> values = new Map<String, Object>();
    if (record == null) {
      return values;
    }
    for (String apiName : fieldApiNames(targetObject)) {
      values.put(apiName, record.get(apiName));
    }
    return values;
  }

  /** 仕様: Core 第11.4.4節。 */
  public static Map<Id, Map<String, Object>> readValuesById(
    String targetObject,
    Set<Id> recordIds
  ) {
    Map<Id, Map<String, Object>> result = new Map<Id, Map<String, Object>>();
    if (recordIds == null || recordIds.isEmpty()) {
      return result;
    }
    Set<String> apiNames = fieldApiNames(targetObject);
    Schema.SObjectType sobjectType = toSObjectType(targetObject);
    if (sobjectType == null) {
      return result;
    }
    List<String> selectFields = new List<String>{ 'Id' };
    selectFields.addAll(apiNames);
    String soql =
      'SELECT ' +
      String.join(selectFields, ',') +
      ' FROM ' +
      String.escapeSingleQuotes(targetObject) +
      ' WHERE Id IN :recordIds WITH SYSTEM_MODE';
    for (SObject row : Database.query(soql)) {
      result.put(row.Id, readValues(row, targetObject));
    }
    return result;
  }

  private static Boolean isBlankValue(Object raw) {
    if (raw == null) {
      return true;
    }
    if (raw instanceof Boolean) {
      return false;
    }
    return String.isBlank(String.valueOf(raw));
  }

  private static AuraHandledException toAuraHandled(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
