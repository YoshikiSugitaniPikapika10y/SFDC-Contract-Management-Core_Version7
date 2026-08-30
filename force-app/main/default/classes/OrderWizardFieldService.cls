/**
 * 受注ウィザード向けの項目定義・選択肢取得。
 * 契約履歴の追加項目は OrderWizardField__mdt。請求アカウント確認はハードコード。
 */
public without sharing class OrderWizardFieldService {
  public static final String DEFAULT_SOURCE_TODAY = 'Today';
  public static final String DEFAULT_SOURCE_OPPORTUNITY = 'Opportunity';
  public static final String DEFAULT_SOURCE_ACCOUNT = 'Account';

  public enum WizardTarget {
    ContractHistory,
    BillingAccount
  }

  public class WizardFieldConfigException extends Exception {
  }

  private class FieldConfig {
    public String developerName;
    public String fieldApiName;
    public String label;
    public Boolean required;
    public Integer sortOrder;
    public String helpText;
    public String defaultValue;
    public String defaultSource;
    public Boolean showOnNew;
    public Boolean showOnChange;
    public Boolean showOnRenew;
    public Boolean showOnCancel;
  }

  private static List<OrderWizardField__mdt> cachedDefinitions;
  private static Boolean activeDefinitionsValidated = false;

  @TestVisible
  static void resetCache() {
    cachedDefinitions = null;
    activeDefinitionsValidated = false;
  }

  @TestVisible
  static void setCachedDefinitionsForTest(
    List<OrderWizardField__mdt> definitions
  ) {
    cachedDefinitions = definitions;
    activeDefinitionsValidated = false;
  }

  /** 仕様: Core 第11.4.3節 */
  @AuraEnabled(cacheable=true)
  public static List<ContractWizardFieldService.WizardFieldDefinition> getDefinitions(
    String wizardType
  ) {
    try {
      validateActiveDefinitions();
      return buildFieldDefinitions(
        ContractHistory__c.SObjectType,
        filterByWizardType(orderHistoryFields(), wizardType)
      );
    } catch (WizardFieldConfigException ex) {
      throw toAuraHandled(ex.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<ContractWizardFieldService.WizardFieldDefinition> getOrderBillingFieldDefinitions() {
    return buildFieldDefinitions(
      BillingAccount__c.SObjectType,
      orderBillingAccountFields()
    );
  }

  public static List<String> getActiveOrderHistoryFieldApiNames() {
    validateActiveDefinitions();
    List<String> apiNames = new List<String>();
    for (FieldConfig config : orderHistoryFields()) {
      if (String.isNotBlank(config.fieldApiName)) {
        apiNames.add(config.fieldApiName);
      }
    }
    return apiNames;
  }

  /** 仕様: Core 第11.4.3節。保存済みだけ。空欄へ初期値は載せない。 */
  public static Map<String, Object> querySavedHistoryFieldValues(Id historyId) {
    if (historyId == null) {
      return new Map<String, Object>();
    }
    validateActiveDefinitions();
    List<String> apiNames = getActiveOrderHistoryFieldApiNames();
    if (apiNames.isEmpty()) {
      return new Map<String, Object>();
    }
    String soql =
      'SELECT Id, ' +
      String.join(apiNames, ', ') +
      ' FROM ContractHistory__c WHERE Id = :historyId LIMIT 1';
    List<ContractHistory__c> rows = Database.queryWithBinds(
      soql,
      new Map<String, Object>{ 'historyId' => historyId },
      AccessLevel.SYSTEM_MODE
    );
    if (rows.isEmpty()) {
      return new Map<String, Object>();
    }
    return buildHistoryCustomFieldValues(rows[0]);
  }

  public static Map<String, Object> buildHistoryCustomFieldValues(
    ContractHistory__c history
  ) {
    Map<String, Object> values = new Map<String, Object>();
    if (history == null) {
      return values;
    }
    for (String apiName : getActiveOrderHistoryFieldApiNames()) {
      values.put(apiName, stringifyFieldValue(history.get(apiName)));
    }
    return values;
  }

  /** 表示中項目の保存値。空なら初期値（Today / 静的 / 商談 / 取引先）。 */
  public static Map<String, Object> buildHistoryFieldValuesForWizard(
    ContractHistory__c history
  ) {
    Map<String, Object> values = buildHistoryCustomFieldValues(history);
    if (history == null) {
      return values;
    }
    List<FieldConfig> visible = filterByWizardType(
      orderHistoryFields(),
      history.Type__c
    );
    Map<String, Object> opportunityContext = buildOpportunityDefaultContext(
      history,
      visible
    );
    for (FieldConfig config : visible) {
      if (!isMissingValue(values.get(config.fieldApiName))) {
        continue;
      }
      Object resolved = resolveDefault(config, opportunityContext);
      if (resolved != null) {
        values.put(config.fieldApiName, resolved);
      }
    }
    return values;
  }

  public static void applyHistoryFields(
    ContractHistory__c history,
    Map<String, Object> customFields
  ) {
    if (history == null) {
      return;
    }
    validateActiveDefinitions();
    Map<String, Object> source = customFields == null
      ? new Map<String, Object>()
      : customFields;
    Map<String, Object> filtered = new Map<String, Object>();
    for (
      FieldConfig config : filterByWizardType(
        orderHistoryFields(),
        history.Type__c
      )
    ) {
      filtered.put(
        config.fieldApiName,
        source.containsKey(config.fieldApiName)
          ? source.get(config.fieldApiName)
          : null
      );
    }
    applyFields(history, filtered, WizardTarget.ContractHistory);
  }

  public static String validateRequiredHistoryFields(
    Map<String, Object> customFields,
    String wizardType
  ) {
    validateActiveDefinitions();
    Map<String, Object> values = customFields == null
      ? new Map<String, Object>()
      : customFields;
    List<String> missingLabels = new List<String>();
    for (
      FieldConfig config : filterByWizardType(orderHistoryFields(), wizardType)
    ) {
      if (config.required != true) {
        continue;
      }
      if (isMissingValue(values.get(config.fieldApiName))) {
        missingLabels.add(
          String.isNotBlank(config.label) ? config.label : config.fieldApiName
        );
      }
    }
    if (missingLabels.isEmpty()) {
      return null;
    }
    return '必須のカスタム項目を入力してください: ' +
      String.join(missingLabels, '、');
  }

  public static void applyBillingFields(
    BillingAccount__c billingAccount,
    Map<String, Object> customFields
  ) {
    applyFields(billingAccount, customFields, WizardTarget.BillingAccount);
  }

  /** 仕様: Core 第5.2節 */
  public static String validateBillingCustomFields(
    Map<String, Object> customFields
  ) {
    Map<String, Object> values = customFields == null
      ? new Map<String, Object>()
      : customFields;
    List<String> missingLabels = new List<String>();
    for (FieldConfig config : orderBillingAccountFields()) {
      if (config.required != true) {
        continue;
      }
      if (
        isMissingBillingFieldValue(
          config.fieldApiName,
          values.get(config.fieldApiName)
        )
      ) {
        missingLabels.add(config.label);
      }
    }
    if (missingLabels.isEmpty()) {
      return null;
    }
    // 仕様: Core 第5.2節。画面は正規編集へ誘導。サーバ文言も同じ案内にする。
    return '請求アカウントの必須項目が未設定です。請求アカウントの正規編集画面で設定してください: ' +
      String.join(missingLabels, '、');
  }

  public static void validateActiveDefinitions() {
    if (activeDefinitionsValidated == true) {
      return;
    }
    for (OrderWizardField__mdt definition : getActiveDefinitions()) {
      validateDefinition(definition);
    }
    activeDefinitionsValidated = true;
  }

  private static List<FieldConfig> orderHistoryFields() {
    List<FieldConfig> fieldConfigs = new List<FieldConfig>();
    for (OrderWizardField__mdt definition : getActiveDefinitions()) {
      if (String.isBlank(definition.FieldApiName__c)) {
        continue;
      }
      FieldConfig config = new FieldConfig();
      config.developerName = definition.DeveloperName;
      config.fieldApiName = definition.FieldApiName__c.trim();
      config.label = definition.LabelOverride__c;
      config.required = definition.Required__c == true;
      config.sortOrder = definition.SortOrder__c == null
        ? 0
        : Integer.valueOf(definition.SortOrder__c);
      config.helpText = String.isBlank(definition.HelpText__c)
        ? null
        : definition.HelpText__c.trim();
      ResolvedDefault resolved = resolveDefaultSourceAndValue(definition);
      config.defaultSource = resolved.defaultSource;
      config.defaultValue = resolved.defaultValue;
      config.showOnNew = definition.ShowOnNew__c == true;
      config.showOnChange = definition.ShowOnChange__c == true;
      config.showOnRenew = definition.ShowOnRenew__c == true;
      config.showOnCancel = definition.ShowOnCancel__c == true;
      fieldConfigs.add(config);
    }
    fieldConfigs.sort(new FieldConfigSortComparator());
    return fieldConfigs;
  }

  private static List<FieldConfig> filterByWizardType(
    List<FieldConfig> fieldConfigs,
    String wizardType
  ) {
    List<FieldConfig> filtered = new List<FieldConfig>();
    for (FieldConfig config : fieldConfigs) {
      if (isShownForWizardType(config, wizardType)) {
        filtered.add(config);
      }
    }
    return filtered;
  }

  @TestVisible
  private static Boolean isShownForWizardType(
    FieldConfig config,
    String wizardType
  ) {
    if (config == null) {
      return false;
    }
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

  private class ResolvedDefault {
    public String defaultSource;
    public String defaultValue;
  }

  private static void validateDefinition(OrderWizardField__mdt definition) {
    if (definition == null) {
      throw new WizardFieldConfigException(
        '受注ウィザード追加項目の定義が不正です（定義が空です）。'
      );
    }
    String label = definitionLabel(definition);
    if (String.isBlank(definition.FieldApiName__c)) {
      throw new WizardFieldConfigException(
        '受注ウィザード追加項目「' + label + '」の FieldApiName が未設定です。'
      );
    }
    Map<String, Schema.SObjectField> fieldMap = ContractHistory__c.SObjectType.getDescribe()
      .fields.getMap();
    String fieldApiName = definition.FieldApiName__c.trim();
    if (!fieldMap.containsKey(fieldApiName)) {
      throw new WizardFieldConfigException(
        '受注ウィザード追加項目「' +
          label +
          '」の項目「' +
          fieldApiName +
          '」が契約履歴に存在しません。'
      );
    }
    Schema.DescribeFieldResult describe = fieldMap.get(fieldApiName)
      .getDescribe();
    if (!ContractWizardFieldService.isSupportedType(describe.getType())) {
      throw new WizardFieldConfigException(
        '受注ウィザード追加項目「' +
          label +
          '」の項目「' +
          fieldApiName +
          '」はウィザード非対応の型です。'
      );
    }
    resolveDefaultSourceAndValue(definition);
  }

  private static ResolvedDefault resolveDefaultSourceAndValue(
    OrderWizardField__mdt definition
  ) {
    ResolvedDefault resolved = new ResolvedDefault();
    String defaultSource = String.isBlank(definition.DefaultSource__c)
      ? null
      : definition.DefaultSource__c.trim();
    String defaultValue = String.isBlank(definition.DefaultValue__c)
      ? null
      : definition.DefaultValue__c.trim();
    String label = definitionLabel(definition);

    if (String.isBlank(defaultSource)) {
      resolved.defaultSource = null;
      resolved.defaultValue = defaultValue;
      return resolved;
    }

    if (defaultSource == DEFAULT_SOURCE_TODAY) {
      if (String.isNotBlank(defaultValue)) {
        throw new WizardFieldConfigException(
          '受注ウィザード追加項目「' +
            label +
            '」の DefaultSource=Today に DefaultValue は指定できません。'
        );
      }
      resolved.defaultSource = DEFAULT_SOURCE_TODAY;
      resolved.defaultValue = null;
      return resolved;
    }

    if (defaultSource == DEFAULT_SOURCE_OPPORTUNITY) {
      if (!ContractWizardFieldService.isValidOpportunityDefaultPath(defaultValue)) {
        throw new WizardFieldConfigException(
          '受注ウィザード追加項目「' +
            label +
            '」の DefaultSource=Opportunity に対する DefaultValue「' +
            blankToDisplay(defaultValue) +
            '」が不正です。商談の項目 API 名を指定してください。'
        );
      }
    } else if (defaultSource == DEFAULT_SOURCE_ACCOUNT) {
      String accountPath = normalizeAccountDefaultPath(defaultValue);
      if (!ContractWizardFieldService.isValidAccountDefaultPath(accountPath)) {
        throw new WizardFieldConfigException(
          '受注ウィザード追加項目「' +
            label +
            '」の DefaultSource=Account に対する DefaultValue「' +
            blankToDisplay(defaultValue) +
            '」が不正です。取引先の項目 API 名を指定してください。'
        );
      }
      defaultValue = accountPath;
    } else if (defaultSource == 'Product2') {
      throw new WizardFieldConfigException(
        '受注ウィザード追加項目「' +
          label +
          '」の DefaultSource=Product2 は設定できません。'
      );
    } else {
      throw new WizardFieldConfigException(
        '受注ウィザード追加項目「' +
          label +
          '」の DefaultSource「' +
          defaultSource +
          '」は未対応です。空欄（静的）/ Today / Opportunity / Account のいずれかを指定してください。'
      );
    }

    resolved.defaultSource = defaultSource;
    resolved.defaultValue = defaultValue;
    return resolved;
  }

  private static String definitionLabel(OrderWizardField__mdt definition) {
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

  private static List<OrderWizardField__mdt> getActiveDefinitions() {
    if (cachedDefinitions != null) {
      return cachedDefinitions;
    }
    cachedDefinitions = [
      SELECT
        DeveloperName,
        MasterLabel,
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
        ShowOnCancel__c
      FROM OrderWizardField__mdt
      WHERE Active__c = TRUE
      ORDER BY SortOrder__c ASC NULLS LAST, DeveloperName ASC
    ];
    return cachedDefinitions;
  }

  private static Object resolveDefault(
    FieldConfig config,
    Map<String, Object> opportunityContext
  ) {
    if (config == null) {
      return null;
    }
    if (config.defaultSource == DEFAULT_SOURCE_TODAY) {
      // 仕様: Core 第5.3節、日付仕様 第8章
      return String.valueOf(InvoiceTransactionStatusService.organizationToday());
    }
    if (String.isBlank(config.defaultSource)) {
      return String.isBlank(config.defaultValue) ? null : config.defaultValue;
    }
    if (opportunityContext == null || opportunityContext.isEmpty()) {
      return null;
    }
    if (config.defaultSource == DEFAULT_SOURCE_OPPORTUNITY) {
      return opportunityContext.get(config.defaultValue);
    }
    if (config.defaultSource == DEFAULT_SOURCE_ACCOUNT) {
      String key = config.defaultValue;
      if (String.isBlank(key)) {
        return null;
      }
      return opportunityContext.containsKey('Account.' + key)
        ? opportunityContext.get('Account.' + key)
        : opportunityContext.get(key);
    }
    return null;
  }

  private static Map<String, Object> buildOpportunityDefaultContext(
    ContractHistory__c history,
    List<FieldConfig> visible
  ) {
    Map<String, Object> context = new Map<String, Object>();
    if (history == null || history.Opportunity__c == null) {
      return context;
    }
    Set<String> opportunityFields = new Set<String>{ 'Id' };
    Set<String> accountFields = new Set<String>();
    Map<String, Schema.SObjectField> opportunityDescribe = Opportunity.SObjectType.getDescribe()
      .fields.getMap();
    Map<String, Schema.SObjectField> accountDescribe = Account.SObjectType.getDescribe()
      .fields.getMap();
    for (FieldConfig config : visible) {
      if (config.defaultSource == DEFAULT_SOURCE_OPPORTUNITY) {
        if (
          String.isNotBlank(config.defaultValue) &&
          opportunityDescribe.containsKey(config.defaultValue)
        ) {
          opportunityFields.add(config.defaultValue);
        }
      } else if (config.defaultSource == DEFAULT_SOURCE_ACCOUNT) {
        if (
          String.isNotBlank(config.defaultValue) &&
          accountDescribe.containsKey(config.defaultValue)
        ) {
          accountFields.add(config.defaultValue);
        }
      }
    }
    if (opportunityFields.size() == 1 && accountFields.isEmpty()) {
      return context;
    }
    List<String> selectFields = new List<String>(opportunityFields);
    for (String accountField : accountFields) {
      selectFields.add('Account.' + accountField);
    }
    Id opportunityId = history.Opportunity__c;
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
      context.put(fieldName, stringifyFieldValue(opportunity.get(fieldName)));
    }
    if (!accountFields.isEmpty()) {
      SObject accountRecord = opportunity.getSObject('Account');
      for (String accountField : accountFields) {
        Object raw = accountRecord == null
          ? null
          : accountRecord.get(accountField);
        context.put('Account.' + accountField, stringifyFieldValue(raw));
      }
    }
    return context;
  }

  private static Object stringifyFieldValue(Object raw) {
    if (raw == null) {
      return null;
    }
    if (raw instanceof Date) {
      return String.valueOf((Date) raw);
    }
    if (raw instanceof Datetime) {
      return String.valueOf(((Datetime) raw).date());
    }
    return raw;
  }

  private static Boolean isMissingValue(Object rawValue) {
    if (rawValue instanceof Boolean) {
      return false;
    }
    if (rawValue == null) {
      return true;
    }
    return String.isBlank(String.valueOf(rawValue).trim());
  }

  // 受注ウィザードでは Note__c（備考）を扱わない。見積の備考をそのまま引き継ぐため。
  private static List<FieldConfig> orderBillingAccountFields() {
    FieldConfig addressee = new FieldConfig();
    addressee.fieldApiName = 'BillingAddressee__c';
    addressee.label = '請求先宛名';
    addressee.required = true;
    addressee.sortOrder = 10;

    FieldConfig emailTo = new FieldConfig();
    emailTo.fieldApiName = 'BillingEmailTo__c';
    emailTo.label = '請求書送付先（To）';
    emailTo.required = true;
    emailTo.sortOrder = 20;

    FieldConfig emailCc = new FieldConfig();
    emailCc.fieldApiName = 'BillingEmailCc__c';
    emailCc.label = '請求書送付先（Cc）';
    emailCc.required = false;
    emailCc.sortOrder = 25;

    FieldConfig emailBcc = new FieldConfig();
    emailBcc.fieldApiName = 'BillingEmailBcc__c';
    emailBcc.label = '請求書送付先（Bcc）';
    emailBcc.required = false;
    emailBcc.sortOrder = 30;

    FieldConfig invoiceDateMethod = new FieldConfig();
    invoiceDateMethod.fieldApiName = 'InvoiceDateMethod__c';
    invoiceDateMethod.label = '請求日の計算方式';
    invoiceDateMethod.required = true;
    invoiceDateMethod.sortOrder = 40;

    FieldConfig invoiceDateAdjust = new FieldConfig();
    invoiceDateAdjust.fieldApiName = 'InvoiceDateAdjust__c';
    invoiceDateAdjust.label = '請求日の補正';
    invoiceDateAdjust.required = true;
    invoiceDateAdjust.sortOrder = 45;

    FieldConfig invoiceDateDayKind = new FieldConfig();
    invoiceDateDayKind.fieldApiName = 'InvoiceDateDayKind__c';
    invoiceDateDayKind.label = '請求日の日種別';
    invoiceDateDayKind.required = false;
    invoiceDateDayKind.sortOrder = 50;

    FieldConfig invoiceDateDay = new FieldConfig();
    invoiceDateDay.fieldApiName = 'InvoiceDateDayOfMonth__c';
    invoiceDateDay.label = '請求日の指定日';
    invoiceDateDay.required = false;
    invoiceDateDay.sortOrder = 51;

    FieldConfig invoiceDateMonthOffset = new FieldConfig();
    invoiceDateMonthOffset.fieldApiName = 'InvoiceDateMonthOffset__c';
    invoiceDateMonthOffset.label = '請求日の月数';
    invoiceDateMonthOffset.required = false;
    invoiceDateMonthOffset.sortOrder = 52;

    FieldConfig invoiceDateDayOffset = new FieldConfig();
    invoiceDateDayOffset.fieldApiName = 'InvoiceDateDayOffset__c';
    invoiceDateDayOffset.label = '請求日の日数';
    invoiceDateDayOffset.required = false;
    invoiceDateDayOffset.sortOrder = 53;

    FieldConfig paymentTermMethod = new FieldConfig();
    paymentTermMethod.fieldApiName = 'PaymentTermMethod__c';
    paymentTermMethod.label = '支払条件の計算方式';
    paymentTermMethod.required = true;
    paymentTermMethod.sortOrder = 60;

    FieldConfig paymentTermAdjust = new FieldConfig();
    paymentTermAdjust.fieldApiName = 'PaymentTermAdjust__c';
    paymentTermAdjust.label = '支払条件の補正';
    paymentTermAdjust.required = true;
    paymentTermAdjust.sortOrder = 61;

    FieldConfig paymentTermDayKind = new FieldConfig();
    paymentTermDayKind.fieldApiName = 'PaymentTermDayKind__c';
    paymentTermDayKind.label = '支払条件の日種別';
    paymentTermDayKind.required = false;
    paymentTermDayKind.sortOrder = 62;

    FieldConfig paymentTermDay = new FieldConfig();
    paymentTermDay.fieldApiName = 'PaymentTermDayOfMonth__c';
    paymentTermDay.label = '支払条件の指定日';
    paymentTermDay.required = false;
    paymentTermDay.sortOrder = 63;

    FieldConfig paymentTermMonthOffset = new FieldConfig();
    paymentTermMonthOffset.fieldApiName = 'PaymentTermMonthOffset__c';
    paymentTermMonthOffset.label = '支払条件の月数';
    paymentTermMonthOffset.required = false;
    paymentTermMonthOffset.sortOrder = 64;

    FieldConfig paymentTermDayOffset = new FieldConfig();
    paymentTermDayOffset.fieldApiName = 'PaymentTermDayOffset__c';
    paymentTermDayOffset.label = '支払条件の日数';
    paymentTermDayOffset.required = false;
    paymentTermDayOffset.sortOrder = 65;

    return new List<FieldConfig>{
      addressee,
      emailTo,
      emailCc,
      emailBcc,
      invoiceDateMethod,
      invoiceDateAdjust,
      invoiceDateDayKind,
      invoiceDateDay,
      invoiceDateMonthOffset,
      invoiceDateDayOffset,
      paymentTermMethod,
      paymentTermAdjust,
      paymentTermDayKind,
      paymentTermDay,
      paymentTermMonthOffset,
      paymentTermDayOffset
    };
  }

  private static Boolean isMissingBillingFieldValue(
    String fieldApiName,
    Object rawValue
  ) {
    if (rawValue instanceof Boolean) {
      return false;
    }
    if (rawValue == null) {
      return true;
    }
    return String.isBlank(String.valueOf(rawValue));
  }

  private static void applyFields(
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
      if (!describe.isUpdateable()) {
        continue;
      }
      Object rawValue = customFields.get(apiName);
      Object coerced = ContractWizardFieldService.coerceValue(
        describe,
        rawValue
      );
      if (coerced == null && rawValue instanceof Boolean) {
        coerced = rawValue;
      }
      if (coerced == null && !describe.isNillable()) {
        continue;
      }
      record.put(apiName, coerced);
    }
  }

  private static List<ContractWizardFieldService.WizardFieldDefinition> buildFieldDefinitions(
    Schema.SObjectType sobjectType,
    List<FieldConfig> fieldConfigs
  ) {
    List<ContractWizardFieldService.WizardFieldDefinition> definitions = new List<ContractWizardFieldService.WizardFieldDefinition>();
    Map<String, Schema.SObjectField> fieldMap = sobjectType.getDescribe()
      .fields.getMap();

    for (FieldConfig config : fieldConfigs) {
      String apiName = config.fieldApiName;
      if (String.isBlank(apiName) || !fieldMap.containsKey(apiName)) {
        continue;
      }
      Schema.DescribeFieldResult describe = fieldMap.get(apiName).getDescribe();
      if (!ContractWizardFieldService.isSupportedType(describe.getType())) {
        continue;
      }

      ContractWizardFieldService.WizardFieldDefinition definition = new ContractWizardFieldService.WizardFieldDefinition();
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
      definition.picklistOptions = ContractWizardFieldService.buildPicklistOptions(
        describe
      );
      definition.helpText = config.helpText;
      definition.defaultValue = config.defaultValue;
      definition.defaultSource = config.defaultSource;
      definition.showOnNew = config.showOnNew == true;
      definition.showOnChange = config.showOnChange == true;
      definition.showOnRenew = config.showOnRenew == true;
      definition.showOnCancel = config.showOnCancel == true;
      definitions.add(definition);
    }

    return definitions;
  }

  private static List<FieldConfig> getFieldConfigs(WizardTarget target) {
    if (target == WizardTarget.BillingAccount) {
      return orderBillingAccountFields();
    }
    return orderHistoryFields();
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

  private class FieldConfigSortComparator implements Comparator<FieldConfig> {
    public Integer compare(FieldConfig left, FieldConfig right) {
      Integer leftOrder = left == null || left.sortOrder == null
        ? 0
        : left.sortOrder;
      Integer rightOrder = right == null || right.sortOrder == null
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
