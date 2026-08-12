/**
 * 受注ウィザード向けの項目定義・選択肢取得。
 */
public without sharing class OrderWizardFieldService {
  public enum WizardTarget {
    ContractHistory,
    BillingAccount
  }

  private class FieldConfig {
    public String fieldApiName;
    public String label;
    public Boolean required;
    public Integer sortOrder;
  }

  @TestVisible
  static void resetCache() {
  }

  @AuraEnabled(cacheable=true)
  public static List<ContractWizardFieldService.WizardFieldDefinition> getOrderHistoryFieldDefinitions() {
    return buildFieldDefinitions(
      ContractHistory__c.SObjectType,
      orderHistoryFields()
    );
  }

  @AuraEnabled(cacheable=true)
  public static List<ContractWizardFieldService.WizardFieldDefinition> getOrderBillingFieldDefinitions() {
    return buildFieldDefinitions(
      BillingAccount__c.SObjectType,
      orderBillingAccountFields()
    );
  }

  public static List<String> getActiveOrderHistoryFieldApiNames() {
    List<String> apiNames = new List<String>();
    for (FieldConfig config : orderHistoryFields()) {
      if (String.isNotBlank(config.fieldApiName)) {
        apiNames.add(config.fieldApiName);
      }
    }
    return apiNames;
  }

  public static Map<String, Object> buildHistoryCustomFieldValues(
    ContractHistory__c history
  ) {
    Map<String, Object> values = new Map<String, Object>();
    if (history == null) {
      return values;
    }
    for (String apiName : getActiveOrderHistoryFieldApiNames()) {
      values.put(apiName, history.get(apiName));
    }
    return values;
  }

  public static void applyHistoryFields(
    ContractHistory__c history,
    Map<String, Object> customFields
  ) {
    applyFields(history, customFields, WizardTarget.ContractHistory);
  }

  public static void applyBillingFields(
    BillingAccount__c billingAccount,
    Map<String, Object> customFields
  ) {
    applyFields(billingAccount, customFields, WizardTarget.BillingAccount);
  }

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
    return '請求アカウントの必須項目が未設定です。取引先の関連リストで請求アカウントを編集するか、新規作成して見積で付け替えてください: ' +
      String.join(missingLabels, '、');
  }

  // 受注ウィザードでは Note__c（備考）を扱わない。見積の備考をそのまま引き継ぐため。
  private static List<FieldConfig> orderHistoryFields() {
    return new List<FieldConfig>();
  }

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

    FieldConfig paymentTerm = new FieldConfig();
    paymentTerm.fieldApiName = 'PaymentTerm__c';
    paymentTerm.label = '支払サイト';
    paymentTerm.required = true;
    paymentTerm.sortOrder = 40;

    FieldConfig billingDay = new FieldConfig();
    billingDay.fieldApiName = 'BillingDayOfMonth__c';
    billingDay.label = '請求日ルール';
    billingDay.required = true;
    billingDay.sortOrder = 50;

    FieldConfig adjustBusinessDay = new FieldConfig();
    adjustBusinessDay.fieldApiName = 'AdjustInvoiceDateToBusinessDay__c';
    adjustBusinessDay.label = '土日を営業日にずらす';
    adjustBusinessDay.required = false;
    adjustBusinessDay.sortOrder = 60;

    return new List<FieldConfig>{
      addressee,
      emailTo,
      emailCc,
      emailBcc,
      paymentTerm,
      billingDay,
      adjustBusinessDay
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
      if (!isSupportedType(describe.getType())) {
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
      definition.picklistOptions = buildPicklistOptions(describe);
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

  private static Boolean isSupportedType(Schema.DisplayType fieldType) {
    return ContractWizardFieldService.isSupportedType(fieldType);
  }

  private static List<ContractWizardFieldService.PicklistOptionDefinition> buildPicklistOptions(
    Schema.DescribeFieldResult describe
  ) {
    return ContractWizardFieldService.buildPicklistOptions(describe);
  }
}
