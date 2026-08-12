/**
 * 見積作成ウィザード向けの項目定義・選択肢取得。
 * 表示対象は EstimateWizardField__mdt、型は Schema.describe。
 */
public without sharing class ContractWizardFieldService {
  public class PicklistOptionDefinition {
    @AuraEnabled
    public String label;

    @AuraEnabled
    public String value;
  }

  public class WizardFieldDefinition {
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
    public List<PicklistOptionDefinition> picklistOptions;

    /** Wizard help text from EstimateWizardField__mdt.HelpText__c */
    @AuraEnabled
    public String helpText;

    /** Initial value from EstimateWizardField__mdt.DefaultValue__c */
    @AuraEnabled
    public String defaultValue;

    /** EstimateWizardField__mdt.DefaultSource__c (blank = static literal) */
    @AuraEnabled
    public String defaultSource;

    /** Product2 field API used for ContractProduct visibility. Blank = always visible. */
    @AuraEnabled
    public String visibilityFieldApiName;

    /** IN / NOT_IN / EQUALS / NOT_EQUALS / IS_BLANK / IS_NOT_BLANK */
    @AuraEnabled
    public String visibilityOperator;

    /** Comma-separated comparison values. */
    @AuraEnabled
    public String visibilityValues;

    @AuraEnabled
    public Boolean showOnNew;

    @AuraEnabled
    public Boolean showOnChange;

    @AuraEnabled
    public Boolean showOnRenew;

    @AuraEnabled
    public Boolean showOnCancel;
  }

  public enum WizardTarget {
    ContractProduct,
    ContractService,
    ContractHistory
  }

  private class FieldConfig {
    public String fieldApiName;
    public String label;
    public Boolean required;
    public Integer sortOrder;
    public String helpText;
    public String defaultValue;
    public String defaultSource;
    public String visibilityFieldApiName;
    public String visibilityOperator;
    public String visibilityValues;
    public Boolean showOnNew;
    public Boolean showOnChange;
    public Boolean showOnRenew;
    public Boolean showOnCancel;
  }

  public static final String DEFAULT_SOURCE_OPPORTUNITY = 'Opportunity';
  public static final String DEFAULT_SOURCE_ACCOUNT = 'Account';
  public static final String DEFAULT_SOURCE_PRODUCT2 = 'Product2';

  public class WizardFieldConfigException extends Exception {
  }

  private static List<EstimateWizardField__mdt> cachedDefinitions;
  private static Boolean activeDefinitionsValidated = false;

  public static void resetCache() {
    cachedDefinitions = null;
    activeDefinitionsValidated = false;
  }

  @TestVisible
  private static void setCachedDefinitionsForTest(
    List<EstimateWizardField__mdt> definitions
  ) {
    cachedDefinitions = definitions;
    activeDefinitionsValidated = false;
  }

  /**
   * Active な EstimateWizardField__mdt を検証する。
   * DefaultSource／DefaultValue／対象項目が不正なら WizardFieldConfigException。
   */
  public static void validateActiveDefinitions() {
    if (activeDefinitionsValidated == true) {
      return;
    }
    for (EstimateWizardField__mdt definition : getActiveDefinitions()) {
      validateDefinition(definition);
    }
    activeDefinitionsValidated = true;
  }

  @AuraEnabled(cacheable=true)
  public static List<WizardFieldDefinition> getContractProductFieldDefinitions() {
    try {
      validateActiveDefinitions();
      return getActiveFieldDefinitions(
        ContractProduct__c.SObjectType,
        getFieldConfigs(WizardTarget.ContractProduct)
      );
    } catch (WizardFieldConfigException ex) {
      throw toAuraHandled(ex.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<WizardFieldDefinition> getContractServiceFieldDefinitions() {
    try {
      validateActiveDefinitions();
      return getActiveFieldDefinitions(
        ContractService__c.SObjectType,
        getFieldConfigs(WizardTarget.ContractService)
      );
    } catch (WizardFieldConfigException ex) {
      throw toAuraHandled(ex.getMessage());
    }
  }

  // cacheable だが CMDT 追加後は本クラスの再デプロイでクライアントキャッシュを破棄する。
  @AuraEnabled(cacheable=true)
  public static List<WizardFieldDefinition> getContractHistoryFieldDefinitions() {
    try {
      validateActiveDefinitions();
      return getActiveFieldDefinitions(
        ContractHistory__c.SObjectType,
        getFieldConfigs(WizardTarget.ContractHistory)
      );
    } catch (WizardFieldConfigException ex) {
      throw toAuraHandled(ex.getMessage());
    }
  }

  /**
   * 商談・取引先の動的デフォルト用コンテキスト。
   * Opportunity 参照: キーは項目 API 名（例: Name）
   * Account 参照: キーは Account.<項目>（例: Account.Name）
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getOpportunityDefaultContext(
    Id opportunityId
  ) {
    try {
      return buildOpportunityDefaultContext(opportunityId);
    } catch (WizardFieldConfigException ex) {
      throw toAuraHandled(ex.getMessage());
    }
  }

  private static Map<String, Object> buildOpportunityDefaultContext(
    Id opportunityId
  ) {
    Map<String, Object> context = new Map<String, Object>();
    if (opportunityId == null) {
      return context;
    }

    validateActiveDefinitions();

    Set<String> opportunityFields = new Set<String>{ 'Id' };
    Set<String> accountFields = new Set<String>();
    Map<String, Schema.SObjectField> opportunityDescribe = Opportunity.SObjectType.getDescribe()
      .fields.getMap();
    Map<String, Schema.SObjectField> accountDescribe = Account.SObjectType.getDescribe()
      .fields.getMap();

    for (
      WizardTarget target : new List<WizardTarget>{
        WizardTarget.ContractProduct,
        WizardTarget.ContractService,
        WizardTarget.ContractHistory
      }
    ) {
      for (FieldConfig config : getFieldConfigs(target)) {
        if (config.defaultSource == DEFAULT_SOURCE_OPPORTUNITY) {
          if (
            isValidOpportunityDefaultPath(config.defaultValue) &&
            opportunityDescribe.containsKey(config.defaultValue)
          ) {
            opportunityFields.add(config.defaultValue);
          }
        } else if (config.defaultSource == DEFAULT_SOURCE_ACCOUNT) {
          String accountPath = normalizeAccountDefaultPath(config.defaultValue);
          if (
            isValidAccountDefaultPath(accountPath) &&
            accountDescribe.containsKey(accountPath)
          ) {
            accountFields.add(accountPath);
          }
        }
      }
    }

    List<String> selectFields = new List<String>(opportunityFields);
    for (String accountField : accountFields) {
      selectFields.add('Account.' + accountField);
    }

    String soql =
      'SELECT ' +
      String.join(selectFields, ',') +
      ' FROM Opportunity WHERE Id = :opportunityId LIMIT 1';
    List<Opportunity> rows = Database.query(soql);
    if (rows.isEmpty()) {
      return context;
    }

    Opportunity opportunity = rows[0];
    for (String fieldName : opportunityFields) {
      if (fieldName == 'Id') {
        continue;
      }
      context.put(
        fieldName,
        stringifyDefaultContextValue(opportunity.get(fieldName))
      );
    }

    if (!accountFields.isEmpty()) {
      SObject accountRecord = opportunity.getSObject('Account');
      for (String accountField : accountFields) {
        Object raw = accountRecord == null
          ? null
          : accountRecord.get(accountField);
        context.put(
          'Account.' + accountField,
          stringifyDefaultContextValue(raw)
        );
      }
    }
    return context;
  }

  @TestVisible
  public static Boolean isValidOpportunityDefaultPath(String path) {
    if (String.isBlank(path) || path.contains('.')) {
      return false;
    }
    return Opportunity.SObjectType.getDescribe()
      .fields.getMap()
      .containsKey(path);
  }

  @TestVisible
  public static Boolean isValidAccountDefaultPath(String path) {
    String normalized = normalizeAccountDefaultPath(path);
    if (String.isBlank(normalized) || normalized.contains('.')) {
      return false;
    }
    return Account.SObjectType.getDescribe()
      .fields.getMap()
      .containsKey(normalized);
  }

  @TestVisible
  public static Boolean isValidProduct2DefaultPath(String path) {
    if (String.isBlank(path) || path.contains('.')) {
      return false;
    }
    return Product2.SObjectType.getDescribe().fields.getMap().containsKey(path);
  }

  private static String normalizeAccountDefaultPath(String path) {
    if (String.isBlank(path)) {
      return null;
    }
    String trimmed = path.trim();
    if (trimmed.startsWith('Account.')) {
      return trimmed.substring('Account.'.length());
    }
    return trimmed;
  }

  private static Object stringifyDefaultContextValue(Object raw) {
    if (raw == null) {
      return null;
    }
    if (raw instanceof Date) {
      return String.valueOf((Date) raw);
    }
    if (raw instanceof Datetime) {
      return String.valueOf(((Datetime) raw).date());
    }
    if (
      raw instanceof Boolean ||
      raw instanceof Decimal ||
      raw instanceof Integer
    ) {
      return raw;
    }
    return String.valueOf(raw);
  }

  public static List<WizardFieldDefinition> getActiveFieldDefinitions(
    Schema.SObjectType sobjectType,
    List<FieldConfig> fieldConfigs
  ) {
    List<WizardFieldDefinition> definitions = new List<WizardFieldDefinition>();
    Map<String, Schema.SObjectField> fieldMap = sobjectType.getDescribe()
      .fields.getMap();

    for (FieldConfig config : fieldConfigs) {
      String apiName = config.fieldApiName;
      if (String.isBlank(apiName) || !fieldMap.containsKey(apiName)) {
        continue;
      }
      Schema.DescribeFieldResult describe = fieldMap.get(apiName).getDescribe();
      if (!isSupportedType(describe.getType())) {
        continue;
      }

      WizardFieldDefinition definition = new WizardFieldDefinition();
      definition.apiName = apiName;
      definition.label = String.isNotBlank(config.label)
        ? config.label
        : describe.getLabel();
      definition.fieldType = describe.getType().name();
      definition.required = config.required == true;
      definition.sortOrder = config.sortOrder == null ? 0 : config.sortOrder;
      definition.maxLength = describe.getLength();
      definition.precision = describe.getPrecision();
      definition.scale = describe.getScale();
      definition.picklistOptions = buildPicklistOptions(describe);
      definition.helpText = config.helpText;
      definition.defaultValue = config.defaultValue;
      definition.defaultSource = config.defaultSource;
      definition.visibilityFieldApiName = config.visibilityFieldApiName;
      definition.visibilityOperator = config.visibilityOperator;
      definition.visibilityValues = config.visibilityValues;
      definition.showOnNew = config.showOnNew == true;
      definition.showOnChange = config.showOnChange == true;
      definition.showOnRenew = config.showOnRenew == true;
      definition.showOnCancel = config.showOnCancel == true;
      definitions.add(definition);
    }

    return definitions;
  }

  public static Map<String, Object> extractCustomFields(
    SObject record,
    WizardTarget target
  ) {
    Map<String, Object> values = new Map<String, Object>();
    if (record == null) {
      return values;
    }

    List<FieldConfig> fieldConfigs = getFieldConfigs(target);
    Set<String> allowedFields = getConfiguredFieldApiNames(fieldConfigs);
    for (String apiName : allowedFields) {
      Object value = record.get(apiName);
      if (value == null) {
        continue;
      }
      if (value instanceof Date) {
        values.put(apiName, String.valueOf((Date) value));
      } else {
        values.put(apiName, value);
      }
    }
    return values;
  }

  public static void applyCustomFields(
    SObject record,
    Map<String, Object> customFields,
    WizardTarget target
  ) {
    if (record == null || customFields == null || customFields.isEmpty()) {
      return;
    }

    Schema.SObjectType sobjectType = record.getSObjectType();
    List<FieldConfig> fieldConfigs = getFieldConfigs(target);
    Map<String, Schema.SObjectField> fieldMap = sobjectType.getDescribe()
      .fields.getMap();
    Set<String> allowedFields = getConfiguredFieldApiNames(fieldConfigs);

    for (String apiName : customFields.keySet()) {
      if (String.isBlank(apiName) || !allowedFields.contains(apiName)) {
        continue;
      }
      if (!fieldMap.containsKey(apiName)) {
        continue;
      }
      Schema.DescribeFieldResult describe = fieldMap.get(apiName).getDescribe();
      Object coerced = coerceValue(describe, customFields.get(apiName));
      if (coerced == null && !describe.isNillable()) {
        continue;
      }
      record.put(apiName, coerced);
    }
  }

  public static String validateRequiredCustomFields(
    WizardTarget target,
    Map<String, Object> customFields
  ) {
    return validateRequiredCustomFields(target, customFields, null);
  }

  public static String validateRequiredCustomFields(
    WizardTarget target,
    Map<String, Object> customFields,
    Map<String, String> productVisibilityContext
  ) {
    return validateRequiredCustomFields(
      target,
      customFields,
      productVisibilityContext,
      null
    );
  }

  public static String validateRequiredCustomFields(
    WizardTarget target,
    Map<String, Object> customFields,
    Map<String, String> productVisibilityContext,
    String wizardType
  ) {
    Map<String, Object> values = customFields == null
      ? new Map<String, Object>()
      : customFields;
    List<String> missingLabels = new List<String>();
    Map<String, Schema.SObjectField> fieldMap = resolveFieldMap(target);

    List<FieldConfig> fieldConfigs;
    try {
      fieldConfigs = getFieldConfigs(target);
    } catch (WizardFieldConfigException ex) {
      throw toAuraHandled(ex.getMessage());
    }

    for (FieldConfig config : fieldConfigs) {
      if (!isShownForWizardType(config, wizardType)) {
        continue;
      }
      if (config.required != true) {
        continue;
      }
      if (
        target == WizardTarget.ContractProduct &&
        !isVisibleForProduct(config, productVisibilityContext)
      ) {
        continue;
      }
      if (isMissingRequiredValue(values.get(config.fieldApiName))) {
        missingLabels.add(resolveFieldLabel(config, fieldMap));
      }
    }

    if (missingLabels.isEmpty()) {
      return null;
    }
    return '必須のカスタム項目を入力してください: ' +
      String.join(missingLabels, '、');
  }

  /**
   * Returns Product2 field API names referenced by ContractProduct visibility rules.
   * Only fields that exist on Product2 are included.
   */
  public static Set<String> getReferencedProduct2FieldApiNames() {
    Set<String> apiNames = new Set<String>();
    Map<String, Schema.SObjectField> productFields = Product2.SObjectType.getDescribe()
      .fields.getMap();
    for (FieldConfig config : getFieldConfigs(WizardTarget.ContractProduct)) {
      if (String.isNotBlank(config.visibilityFieldApiName)) {
        String apiName = config.visibilityFieldApiName.trim();
        if (productFields.containsKey(apiName)) {
          apiNames.add(apiName);
        }
      }
      if (
        config.defaultSource == DEFAULT_SOURCE_PRODUCT2 &&
        isValidProduct2DefaultPath(config.defaultValue)
      ) {
        apiNames.add(config.defaultValue);
      }
    }
    return apiNames;
  }

  public static List<String> getProduct2RelationshipSelectFields(
    String relationshipName
  ) {
    List<String> selectFields = new List<String>();
    if (String.isBlank(relationshipName)) {
      return selectFields;
    }
    for (String apiName : getReferencedProduct2FieldApiNames()) {
      selectFields.add(relationshipName + '.' + apiName);
    }
    return selectFields;
  }

  public static Map<String, String> buildProductVisibilityContext(
    SObject product
  ) {
    Map<String, String> context = new Map<String, String>();
    if (product == null) {
      return context;
    }
    for (String apiName : getReferencedProduct2FieldApiNames()) {
      Object raw;
      try {
        raw = product.get(apiName);
      } catch (Exception e) {
        continue;
      }
      context.put(apiName, stringifyVisibilityValue(raw));
    }
    return context;
  }

  /**
   * Prepares custom-field values for apply/save.
   * - Wizard-type (ShowOn*) hidden: omitted (existing DB values preserved)
   * - ContractProduct Product2-hidden: forced to null (cleared)
   * - Visible: source value when key present; otherwise null (explicit clear).
   *   画面で空／wipe された表示中項目が、既存 ContractService 更新時に残留しないようにする。
   */
  public static Map<String, Object> filterCustomFieldsByVisibility(
    Map<String, Object> customFields,
    WizardTarget target,
    Map<String, String> productVisibilityContext
  ) {
    return filterCustomFieldsByVisibility(
      customFields,
      target,
      productVisibilityContext,
      null
    );
  }

  public static Map<String, Object> filterCustomFieldsByVisibility(
    Map<String, Object> customFields,
    WizardTarget target,
    Map<String, String> productVisibilityContext,
    String wizardType
  ) {
    Map<String, Object> filtered = new Map<String, Object>();
    Map<String, Object> source = customFields == null
      ? new Map<String, Object>()
      : customFields;

    List<FieldConfig> fieldConfigs;
    try {
      fieldConfigs = getFieldConfigs(target);
    } catch (WizardFieldConfigException ex) {
      throw toAuraHandled(ex.getMessage());
    }

    if (target != WizardTarget.ContractProduct) {
      for (FieldConfig config : fieldConfigs) {
        if (String.isBlank(config.fieldApiName)) {
          continue;
        }
        if (!isShownForWizardType(config, wizardType)) {
          continue;
        }
        // 表示中は必ず書く。キー無し＝画面上の空／破棄 → null クリア
        filtered.put(
          config.fieldApiName,
          source.containsKey(config.fieldApiName)
            ? source.get(config.fieldApiName)
            : null
        );
      }
      return filtered;
    }

    for (FieldConfig config : fieldConfigs) {
      if (String.isBlank(config.fieldApiName)) {
        continue;
      }
      if (!isShownForWizardType(config, wizardType)) {
        continue;
      }
      if (!isVisibleForProduct(config, productVisibilityContext)) {
        filtered.put(config.fieldApiName, null);
        continue;
      }
      filtered.put(
        config.fieldApiName,
        source.containsKey(config.fieldApiName)
          ? source.get(config.fieldApiName)
          : null
      );
    }
    return filtered;
  }

  /**
   * Type-checks visible custom-field values. Blank values are skipped
   * (required is validated separately). Returns Japanese error or null.
   */
  public static String validateCustomFieldTypes(
    WizardTarget target,
    Map<String, Object> customFields
  ) {
    return validateCustomFieldTypes(target, customFields, null, null);
  }

  public static String validateCustomFieldTypes(
    WizardTarget target,
    Map<String, Object> customFields,
    Map<String, String> productVisibilityContext
  ) {
    return validateCustomFieldTypes(
      target,
      customFields,
      productVisibilityContext,
      null
    );
  }

  public static String validateCustomFieldTypes(
    WizardTarget target,
    Map<String, Object> customFields,
    Map<String, String> productVisibilityContext,
    String wizardType
  ) {
    Map<String, Object> values = customFields == null
      ? new Map<String, Object>()
      : customFields;
    Schema.SObjectType sobjectType = toSObjectType(target);
    if (sobjectType == null) {
      return null;
    }
    Map<String, Schema.SObjectField> fieldMap = sobjectType.getDescribe()
      .fields.getMap();
    List<String> typeErrors = new List<String>();

    List<FieldConfig> fieldConfigs;
    try {
      fieldConfigs = getFieldConfigs(target);
    } catch (WizardFieldConfigException ex) {
      throw toAuraHandled(ex.getMessage());
    }

    for (FieldConfig config : fieldConfigs) {
      if (!isShownForWizardType(config, wizardType)) {
        continue;
      }
      if (
        target == WizardTarget.ContractProduct &&
        !isVisibleForProduct(config, productVisibilityContext)
      ) {
        continue;
      }
      if (!fieldMap.containsKey(config.fieldApiName)) {
        continue;
      }
      Object raw = values.get(config.fieldApiName);
      if (isMissingRequiredValue(raw)) {
        continue;
      }
      Schema.DescribeFieldResult describe = fieldMap.get(config.fieldApiName)
        .getDescribe();
      if (!isSupportedType(describe.getType())) {
        continue;
      }
      String typeError = getTypeErrorMessage(describe.getType(), raw);
      if (String.isBlank(typeError)) {
        continue;
      }
      typeErrors.add(
        resolveFieldLabel(config, fieldMap) + '（' + typeError + '）'
      );
    }

    if (typeErrors.isEmpty()) {
      return null;
    }
    return 'カスタム項目の形式が不正です: ' + String.join(typeErrors, '、');
  }

  private static Map<String, Schema.SObjectField> resolveFieldMap(
    WizardTarget target
  ) {
    Schema.SObjectType sobjectType = toSObjectType(target);
    if (sobjectType == null) {
      return new Map<String, Schema.SObjectField>();
    }
    return sobjectType.getDescribe().fields.getMap();
  }

  private static String resolveFieldLabel(
    FieldConfig config,
    Map<String, Schema.SObjectField> fieldMap
  ) {
    if (config == null) {
      return null;
    }
    if (String.isNotBlank(config.label)) {
      return config.label;
    }
    if (
      fieldMap != null &&
      String.isNotBlank(config.fieldApiName) &&
      fieldMap.containsKey(config.fieldApiName)
    ) {
      return fieldMap.get(config.fieldApiName).getDescribe().getLabel();
    }
    return config.fieldApiName;
  }

  @TestVisible
  private static Boolean isShownForWizardType(
    FieldConfig config,
    String wizardType
  ) {
    if (config == null) {
      return false;
    }
    // Null/blank type: do not hide (legacy callers / incomplete context)
    if (String.isBlank(wizardType)) {
      return true;
    }
    String normalized = wizardType.trim();
    if (normalized == 'New') {
      return config.showOnNew == true;
    }
    if (normalized == 'Change') {
      return config.showOnChange == true;
    }
    if (normalized == 'Renew') {
      return config.showOnRenew == true;
    }
    if (normalized == 'Cancel') {
      return config.showOnCancel == true;
    }
    return true;
  }

  @TestVisible
  private static Boolean isVisibleForProduct(
    FieldConfig config,
    Map<String, String> productVisibilityContext
  ) {
    if (config == null || String.isBlank(config.visibilityFieldApiName)) {
      return true;
    }
    if (productVisibilityContext == null) {
      return false;
    }

    String fieldApi = config.visibilityFieldApiName.trim();
    String actual = productVisibilityContext.containsKey(fieldApi)
      ? productVisibilityContext.get(fieldApi)
      : null;
    String operator = String.isBlank(config.visibilityOperator)
      ? 'IN'
      : config.visibilityOperator.trim().toUpperCase();
    List<String> expectedValues = splitCommaSeparatedValues(
      config.visibilityValues
    );

    return evaluateVisibility(operator, actual, expectedValues);
  }

  @TestVisible
  private static Boolean evaluateVisibility(
    String operator,
    String actual,
    List<String> expectedValues
  ) {
    Boolean blank = String.isBlank(actual);
    if (operator == 'IS_BLANK') {
      return blank;
    }
    if (operator == 'IS_NOT_BLANK') {
      return !blank;
    }

    Set<String> actualTokens = splitMultiValueActual(actual);
    Set<String> expectedSet = new Set<String>(expectedValues);

    if (operator == 'IN' || operator == 'EQUALS') {
      if (actualTokens.isEmpty() || expectedSet.isEmpty()) {
        return false;
      }
      for (String token : actualTokens) {
        if (expectedSet.contains(token)) {
          return true;
        }
      }
      return false;
    }

    if (operator == 'NOT_IN' || operator == 'NOT_EQUALS') {
      if (expectedSet.isEmpty()) {
        return true;
      }
      if (actualTokens.isEmpty()) {
        return true;
      }
      for (String token : actualTokens) {
        if (expectedSet.contains(token)) {
          return false;
        }
      }
      return true;
    }

    // Unknown operator: fail closed for conditional fields
    return false;
  }

  private static List<String> splitCommaSeparatedValues(String raw) {
    List<String> values = new List<String>();
    if (String.isBlank(raw)) {
      return values;
    }
    for (String part : raw.split(',')) {
      String trimmed = part == null ? '' : part.trim();
      if (String.isNotBlank(trimmed)) {
        values.add(trimmed);
      }
    }
    return values;
  }

  private static Set<String> splitMultiValueActual(String actual) {
    Set<String> tokens = new Set<String>();
    if (String.isBlank(actual)) {
      return tokens;
    }
    // Product2 multipicklist uses ';'; single values stay as one token.
    for (String part : actual.split(';')) {
      String trimmed = part == null ? '' : part.trim();
      if (String.isNotBlank(trimmed)) {
        tokens.add(trimmed);
      }
    }
    return tokens;
  }

  private static String stringifyVisibilityValue(Object raw) {
    if (raw == null) {
      return null;
    }
    if (raw instanceof Boolean) {
      return (Boolean) raw ? 'true' : 'false';
    }
    if (raw instanceof Date) {
      return String.valueOf((Date) raw);
    }
    if (raw instanceof Datetime) {
      return String.valueOf(((Datetime) raw).date());
    }
    String text = String.valueOf(raw).trim();
    return String.isBlank(text) ? null : text;
  }

  private static Boolean isMissingRequiredValue(Object rawValue) {
    if (rawValue == null) {
      return true;
    }
    if (rawValue instanceof Boolean) {
      return false;
    }
    return String.isBlank(String.valueOf(rawValue).trim());
  }

  public static Map<String, Object> parseCustomFieldsJson(
    String customFieldsJson
  ) {
    Map<String, Object> values = new Map<String, Object>();
    if (String.isBlank(customFieldsJson)) {
      return values;
    }
    Object raw = JSON.deserializeUntyped(customFieldsJson);
    if (!(raw instanceof Map<String, Object>)) {
      return values;
    }
    return (Map<String, Object>) raw;
  }

  public static Set<String> getActiveFieldApiNames(WizardTarget target) {
    return getConfiguredFieldApiNames(getFieldConfigs(target));
  }

  /**
   * 保存時にウィザード追加項目をすべて null クリアするためのマップ。
   * Change の Original 行など、追加項目を持たせない行向け。
   */
  public static Map<String, Object> buildClearedCustomFields(
    WizardTarget target
  ) {
    Map<String, Object> cleared = new Map<String, Object>();
    for (String apiName : getActiveFieldApiNames(target)) {
      if (String.isBlank(apiName)) {
        continue;
      }
      cleared.put(apiName, null);
    }
    return cleared;
  }

  private static List<FieldConfig> getFieldConfigs(WizardTarget target) {
    validateActiveDefinitions();
    String targetObjectApiName = toTargetObjectApiName(target);
    if (String.isBlank(targetObjectApiName)) {
      return new List<FieldConfig>();
    }

    Boolean isProductTarget = target == WizardTarget.ContractProduct;
    List<FieldConfig> fieldConfigs = new List<FieldConfig>();
    for (EstimateWizardField__mdt definition : getActiveDefinitions()) {
      if (definition.TargetObject__c != targetObjectApiName) {
        continue;
      }
      if (String.isBlank(definition.FieldApiName__c)) {
        continue;
      }
      FieldConfig config = new FieldConfig();
      config.fieldApiName = definition.FieldApiName__c.trim();
      config.label = definition.LabelOverride__c;
      config.required = definition.Required__c == true;
      config.sortOrder = definition.SortOrder__c == null
        ? 0
        : Integer.valueOf(definition.SortOrder__c);
      config.helpText = String.isBlank(definition.HelpText__c)
        ? null
        : definition.HelpText__c.trim();

      ResolvedDefault resolved = resolveDefaultSourceAndValue(
        definition,
        isProductTarget
      );
      config.defaultSource = resolved.defaultSource;
      config.defaultValue = resolved.defaultValue;
      config.showOnNew = definition.ShowOnNew__c == true;
      config.showOnChange = definition.ShowOnChange__c == true;
      config.showOnRenew = definition.ShowOnRenew__c == true;
      config.showOnCancel = definition.ShowOnCancel__c == true;
      if (isProductTarget) {
        config.visibilityFieldApiName = definition.VisibilityFieldApiName__c;
        config.visibilityOperator = definition.VisibilityOperator__c;
        config.visibilityValues = definition.VisibilityValues__c;
      }
      fieldConfigs.add(config);
    }

    fieldConfigs.sort(new FieldConfigSortComparator());
    return fieldConfigs;
  }

  private class ResolvedDefault {
    public String defaultSource;
    public String defaultValue;
  }

  private static void validateDefinition(EstimateWizardField__mdt definition) {
    if (definition == null) {
      throw new WizardFieldConfigException(
        '見積ウィザードカスタム項目の定義が不正です（定義が空です）。'
      );
    }
    String label = definitionLabel(definition);
    String targetObject = definition.TargetObject__c;
    if (
      targetObject != 'ContractService__c' &&
      targetObject != 'ContractHistory__c' &&
      targetObject != 'ContractProduct__c'
    ) {
      throw new WizardFieldConfigException(
        '見積ウィザードカスタム項目「' +
          label +
          '」の対象オブジェクト「' +
          blankToDisplay(targetObject) +
          '」が不正です。ContractService__c / ContractHistory__c / ContractProduct__c のいずれかを指定してください。'
      );
    }
    if (String.isBlank(definition.FieldApiName__c)) {
      throw new WizardFieldConfigException(
        '見積ウィザードカスタム項目「' +
          label +
          '」の FieldApiName が未設定です。'
      );
    }
    Schema.SObjectType sobjectType = toSObjectTypeForTargetObject(targetObject);
    Map<String, Schema.SObjectField> fieldMap = sobjectType.getDescribe()
      .fields.getMap();
    String fieldApiName = definition.FieldApiName__c.trim();
    if (!fieldMap.containsKey(fieldApiName)) {
      throw new WizardFieldConfigException(
        '見積ウィザードカスタム項目「' +
          label +
          '」の項目「' +
          fieldApiName +
          '」が対象オブジェクトに存在しません。'
      );
    }
    Schema.DescribeFieldResult describe = fieldMap.get(fieldApiName)
      .getDescribe();
    if (!isSupportedType(describe.getType())) {
      throw new WizardFieldConfigException(
        '見積ウィザードカスタム項目「' +
          label +
          '」の項目「' +
          fieldApiName +
          '」はウィザード非対応の型です。'
      );
    }

    Boolean isProductTarget = targetObject == 'ContractProduct__c';
    // DefaultSource／DefaultValue の検証（不正なら例外）
    resolveDefaultSourceAndValue(definition, isProductTarget);
    // Visibility* の検証（不正なら例外。typo で常時非表示になるのを防ぐ）
    validateVisibilityConfig(definition, isProductTarget, label);
  }

  private static final Set<String> VISIBILITY_OPERATORS = new Set<String>{
    'IN',
    'NOT_IN',
    'EQUALS',
    'NOT_EQUALS',
    'IS_BLANK',
    'IS_NOT_BLANK'
  };

  private static void validateVisibilityConfig(
    EstimateWizardField__mdt definition,
    Boolean isProductTarget,
    String label
  ) {
    Boolean hasField = String.isNotBlank(definition.VisibilityFieldApiName__c);
    Boolean hasValues = String.isNotBlank(definition.VisibilityValues__c);
    // Operator は CMDT ピッカーのデフォルト IN が入りがちなので、
    // Field / Values が無いときは Visibility 未使用として無視する。
    if (!hasField && !hasValues) {
      return;
    }

    if (isProductTarget != true) {
      throw new WizardFieldConfigException(
        '見積ウィザードカスタム項目「' +
          label +
          '」の Visibility* は見積商品（ContractProduct__c）でのみ利用できます。'
      );
    }

    if (!hasField) {
      throw new WizardFieldConfigException(
        '見積ウィザードカスタム項目「' +
          label +
          '」の VisibilityValues を使う場合は VisibilityFieldApiName も指定してください。'
      );
    }

    String fieldApi = definition.VisibilityFieldApiName__c.trim();
    if (fieldApi.contains('.')) {
      throw new WizardFieldConfigException(
        '見積ウィザードカスタム項目「' +
          label +
          '」の VisibilityFieldApiName「' +
          fieldApi +
          '」が不正です。Product2 の項目 API 名を指定してください（ドット不可）。'
      );
    }
    Map<String, Schema.SObjectField> productFields = Product2.SObjectType.getDescribe()
      .fields.getMap();
    if (!productFields.containsKey(fieldApi)) {
      throw new WizardFieldConfigException(
        '見積ウィザードカスタム項目「' +
          label +
          '」の VisibilityFieldApiName「' +
          fieldApi +
          '」が Product2 に存在しません。'
      );
    }

    Boolean hasOperator = String.isNotBlank(definition.VisibilityOperator__c);
    String operator = hasOperator
      ? definition.VisibilityOperator__c.trim().toUpperCase()
      : 'IN';
    if (!VISIBILITY_OPERATORS.contains(operator)) {
      throw new WizardFieldConfigException(
        '見積ウィザードカスタム項目「' +
          label +
          '」の VisibilityOperator「' +
          definition.VisibilityOperator__c.trim() +
          '」は未対応です。IN / NOT_IN / EQUALS / NOT_EQUALS / IS_BLANK / IS_NOT_BLANK のいずれかを指定してください。'
      );
    }

    if (
      (operator == 'IN' ||
      operator == 'EQUALS' ||
      operator == 'NOT_IN' ||
      operator == 'NOT_EQUALS') &&
      splitCommaSeparatedValues(definition.VisibilityValues__c).isEmpty()
    ) {
      throw new WizardFieldConfigException(
        '見積ウィザードカスタム項目「' +
          label +
          '」の VisibilityOperator=' +
          operator +
          ' には VisibilityValues（カンマ区切り）が必要です。'
      );
    }
  }

  private static ResolvedDefault resolveDefaultSourceAndValue(
    EstimateWizardField__mdt definition,
    Boolean isProductTarget
  ) {
    ResolvedDefault resolved = new ResolvedDefault();
    String defaultSource = String.isBlank(definition.DefaultSource__c)
      ? null
      : definition.DefaultSource__c.trim();
    String defaultValue = String.isBlank(definition.DefaultValue__c)
      ? null
      : definition.DefaultValue__c.trim();
    String label = definitionLabel(definition);

    // 旧設定: Opportunity + Account.Name → Account + Name
    if (
      defaultSource == DEFAULT_SOURCE_OPPORTUNITY &&
      defaultValue != null &&
      defaultValue.startsWith('Account.')
    ) {
      defaultSource = DEFAULT_SOURCE_ACCOUNT;
      defaultValue = defaultValue.substring('Account.'.length());
    }

    if (String.isBlank(defaultSource)) {
      // 空欄 = 静的リテラル（DefaultValue はそのまま）
      resolved.defaultSource = null;
      resolved.defaultValue = defaultValue;
      return resolved;
    }

    if (defaultSource == DEFAULT_SOURCE_OPPORTUNITY) {
      if (!isValidOpportunityDefaultPath(defaultValue)) {
        throw new WizardFieldConfigException(
          '見積ウィザードカスタム項目「' +
            label +
            '」の DefaultSource=Opportunity に対する DefaultValue「' +
            blankToDisplay(defaultValue) +
            '」が不正です。商談の項目 API 名を指定してください。'
        );
      }
    } else if (defaultSource == DEFAULT_SOURCE_ACCOUNT) {
      String accountPath = normalizeAccountDefaultPath(defaultValue);
      if (!isValidAccountDefaultPath(accountPath)) {
        throw new WizardFieldConfigException(
          '見積ウィザードカスタム項目「' +
            label +
            '」の DefaultSource=Account に対する DefaultValue「' +
            blankToDisplay(defaultValue) +
            '」が不正です。取引先の項目 API 名を指定してください。'
        );
      }
      defaultValue = accountPath;
    } else if (defaultSource == DEFAULT_SOURCE_PRODUCT2) {
      if (isProductTarget != true) {
        throw new WizardFieldConfigException(
          '見積ウィザードカスタム項目「' +
            label +
            '」の DefaultSource=Product2 は見積商品（ContractProduct__c）でのみ利用できます。'
        );
      }
      if (!isValidProduct2DefaultPath(defaultValue)) {
        throw new WizardFieldConfigException(
          '見積ウィザードカスタム項目「' +
            label +
            '」の DefaultSource=Product2 に対する DefaultValue「' +
            blankToDisplay(defaultValue) +
            '」が不正です。商品の項目 API 名を指定してください。'
        );
      }
    } else {
      throw new WizardFieldConfigException(
        '見積ウィザードカスタム項目「' +
          label +
          '」の DefaultSource「' +
          defaultSource +
          '」は未対応です。空欄（静的）/ Opportunity / Account / Product2 のいずれかを指定してください。'
      );
    }

    resolved.defaultSource = defaultSource;
    resolved.defaultValue = defaultValue;
    return resolved;
  }

  private static String definitionLabel(EstimateWizardField__mdt definition) {
    if (definition == null) {
      return '(不明)';
    }
    if (String.isNotBlank(definition.DeveloperName)) {
      return definition.DeveloperName;
    }
    if (String.isNotBlank(definition.MasterLabel)) {
      return definition.MasterLabel;
    }
    return '(不明)';
  }

  private static String blankToDisplay(String value) {
    return String.isBlank(value) ? '(空)' : value;
  }

  private static Schema.SObjectType toSObjectTypeForTargetObject(
    String targetObjectApiName
  ) {
    if (targetObjectApiName == 'ContractProduct__c') {
      return ContractProduct__c.SObjectType;
    }
    if (targetObjectApiName == 'ContractService__c') {
      return ContractService__c.SObjectType;
    }
    if (targetObjectApiName == 'ContractHistory__c') {
      return ContractHistory__c.SObjectType;
    }
    return null;
  }

  private static List<EstimateWizardField__mdt> getActiveDefinitions() {
    if (cachedDefinitions != null) {
      return cachedDefinitions;
    }
    cachedDefinitions = [
      SELECT
        DeveloperName,
        TargetObject__c,
        FieldApiName__c,
        LabelOverride__c,
        Required__c,
        SortOrder__c,
        Active__c,
        HelpText__c,
        DefaultValue__c,
        DefaultSource__c,
        ShowOnNew__c,
        ShowOnChange__c,
        ShowOnRenew__c,
        ShowOnCancel__c,
        VisibilityFieldApiName__c,
        VisibilityOperator__c,
        VisibilityValues__c
      FROM EstimateWizardField__mdt
      WHERE Active__c = TRUE
      ORDER BY SortOrder__c ASC NULLS LAST, DeveloperName ASC
    ];
    return cachedDefinitions;
  }

  private static String toTargetObjectApiName(WizardTarget target) {
    if (target == WizardTarget.ContractProduct) {
      return 'ContractProduct__c';
    }
    if (target == WizardTarget.ContractService) {
      return 'ContractService__c';
    }
    if (target == WizardTarget.ContractHistory) {
      return 'ContractHistory__c';
    }
    return null;
  }

  private static Schema.SObjectType toSObjectType(WizardTarget target) {
    if (target == WizardTarget.ContractProduct) {
      return ContractProduct__c.SObjectType;
    }
    if (target == WizardTarget.ContractService) {
      return ContractService__c.SObjectType;
    }
    if (target == WizardTarget.ContractHistory) {
      return ContractHistory__c.SObjectType;
    }
    return null;
  }

  @TestVisible
  private static String getTypeErrorMessage(
    Schema.DisplayType fieldType,
    Object rawValue
  ) {
    if (fieldType == Schema.DisplayType.BOOLEAN) {
      if (rawValue instanceof Boolean) {
        return null;
      }
      String text = String.valueOf(rawValue).trim().toLowerCase();
      if (text == 'true' || text == 'false' || text == '1' || text == '0') {
        return null;
      }
      return '真偽値で入力してください';
    }

    String text = String.valueOf(rawValue).trim();

    if (fieldType == Schema.DisplayType.DATE) {
      if (!isValidIsoDateText(text)) {
        return 'YYYY-MM-DD 形式で入力してください';
      }
      return null;
    }

    if (
      fieldType == Schema.DisplayType.INTEGER ||
      fieldType == Schema.DisplayType.LONG
    ) {
      if (!Pattern.matches('^-?\\d+$', text)) {
        return '整数で入力してください';
      }
      return null;
    }

    if (
      fieldType == Schema.DisplayType.DOUBLE ||
      fieldType == Schema.DisplayType.CURRENCY ||
      fieldType == Schema.DisplayType.PERCENT
    ) {
      if (!Pattern.matches('^-?\\d+(\\.\\d+)?$', text)) {
        return '数値で入力してください';
      }
      return null;
    }

    return null;
  }

  @TestVisible
  private static Boolean isValidIsoDateText(String text) {
    if (
      String.isBlank(text) || !Pattern.matches('^\\d{4}-\\d{2}-\\d{2}$', text)
    ) {
      return false;
    }
    try {
      Date parsed = Date.valueOf(text);
      return String.valueOf(parsed) == text;
    } catch (Exception e) {
      return false;
    }
  }

  private static Set<String> getConfiguredFieldApiNames(
    List<FieldConfig> fieldConfigs
  ) {
    Set<String> apiNames = new Set<String>();
    for (FieldConfig config : fieldConfigs) {
      if (String.isNotBlank(config.fieldApiName)) {
        apiNames.add(config.fieldApiName);
      }
    }
    return apiNames;
  }

  public static Boolean isSupportedType(Schema.DisplayType fieldType) {
    return fieldType == Schema.DisplayType.STRING ||
      fieldType == Schema.DisplayType.TEXTAREA ||
      fieldType == Schema.DisplayType.EMAIL ||
      fieldType == Schema.DisplayType.PHONE ||
      fieldType == Schema.DisplayType.URL ||
      fieldType == Schema.DisplayType.DOUBLE ||
      fieldType == Schema.DisplayType.CURRENCY ||
      fieldType == Schema.DisplayType.PERCENT ||
      fieldType == Schema.DisplayType.INTEGER ||
      fieldType == Schema.DisplayType.LONG ||
      fieldType == Schema.DisplayType.DATE ||
      fieldType == Schema.DisplayType.BOOLEAN ||
      fieldType == Schema.DisplayType.PICKLIST;
  }

  public static List<PicklistOptionDefinition> buildPicklistOptions(
    Schema.DescribeFieldResult describe
  ) {
    if (describe.getType() != Schema.DisplayType.PICKLIST) {
      return new List<PicklistOptionDefinition>();
    }

    List<PicklistOptionDefinition> options = new List<PicklistOptionDefinition>();
    for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
      if (!entry.isActive()) {
        continue;
      }
      PicklistOptionDefinition option = new PicklistOptionDefinition();
      option.label = entry.getLabel();
      option.value = entry.getValue();
      options.add(option);
    }
    return options;
  }

  public static Object coerceValue(
    Schema.DescribeFieldResult describe,
    Object rawValue
  ) {
    if (rawValue == null) {
      return null;
    }

    Schema.DisplayType fieldType = describe.getType();
    if (fieldType == Schema.DisplayType.BOOLEAN) {
      if (rawValue instanceof Boolean) {
        return rawValue;
      }
      String boolText = String.valueOf(rawValue).trim();
      if (String.isBlank(boolText)) {
        return null;
      }
      return boolText == 'true' || boolText == '1';
    }

    String text = String.valueOf(rawValue).trim();
    if (String.isBlank(text)) {
      return null;
    }

    if (fieldType == Schema.DisplayType.DATE) {
      if (!isValidIsoDateText(text)) {
        return null;
      }
      return Date.valueOf(text);
    }

    if (
      fieldType == Schema.DisplayType.INTEGER ||
      fieldType == Schema.DisplayType.LONG
    ) {
      if (!Pattern.matches('^-?\\d+$', text)) {
        return null;
      }
      return Integer.valueOf(text);
    }

    if (
      fieldType == Schema.DisplayType.DOUBLE ||
      fieldType == Schema.DisplayType.CURRENCY ||
      fieldType == Schema.DisplayType.PERCENT
    ) {
      if (!Pattern.matches('^-?\\d+(\\.\\d+)?$', text)) {
        return null;
      }
      return Decimal.valueOf(text);
    }

    return text;
  }

  private class FieldConfigSortComparator implements Comparator<FieldConfig> {
    public Integer compare(FieldConfig left, FieldConfig right) {
      Integer leftOrder = left == null ||
        left.sortOrder == null
        ? 0
        : left.sortOrder;
      Integer rightOrder = right == null ||
        right.sortOrder == null
        ? 0
        : right.sortOrder;
      if (leftOrder == rightOrder) {
        String leftName = left == null ? '' : left.fieldApiName;
        String rightName = right == null ? '' : right.fieldApiName;
        return leftName.compareTo(rightName);
      }
      return leftOrder < rightOrder ? -1 : 1;
    }
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
