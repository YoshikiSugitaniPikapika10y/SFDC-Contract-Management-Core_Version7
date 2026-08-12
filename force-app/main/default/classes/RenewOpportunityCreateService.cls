/**
 * 更新商談（Opportunity）作成 API。
 * 項目セットは RenewOpportunityField__mdt。リレーション（AccountId /
 * PreviousOpportunity__c / SourceContractHistory__c）はコード固定。
 * 呼び出し元（受注ウィザード等）は別途。
 */
public without sharing class RenewOpportunityCreateService {
  public class RenewOpportunityException extends Exception {
  }

  public static final String VALUE_TYPE_CONSTANT = 'Constant';
  public static final String VALUE_TYPE_FIELD = 'Field';
  public static final String VALUE_TYPE_TEMPLATE = 'Template';

  public static final String OBJECT_OPPORTUNITY = 'Opportunity';
  public static final String OBJECT_ACCOUNT = 'Account';
  public static final String OBJECT_CONTRACT_HISTORY = 'ContractHistory__c';
  public static final String OBJECT_CONTRACT_SERVICE = 'ContractService__c';

  private static final String FIELD_ACCOUNT_ID = 'AccountId';
  private static final String FIELD_PREVIOUS_OPPORTUNITY = 'PreviousOpportunity__c';
  private static final String FIELD_SOURCE_CONTRACT_HISTORY = 'SourceContractHistory__c';
  private static final String FIELD_OWNER_ID = 'OwnerId';
  private static final String FIELD_ID = 'Id';

  private static final Set<String> FORBIDDEN_TARGETS = new Set<String>{
    FIELD_ACCOUNT_ID,
    FIELD_PREVIOUS_OPPORTUNITY,
    FIELD_SOURCE_CONTRACT_HISTORY,
    FIELD_ID
  };

  private static final Set<String> ALLOWED_SOURCE_OBJECTS = new Set<String>{
    OBJECT_OPPORTUNITY,
    OBJECT_ACCOUNT,
    OBJECT_CONTRACT_HISTORY,
    OBJECT_CONTRACT_SERVICE
  };

  private static final Set<String> ALLOWED_DATE_FORMATS = new Set<String>{
    'yyyyMM',
    'yyyy-MM-dd',
    'yyyy/MM/dd',
    'yyyy/MM',
    'yy/MM'
  };

  private static final String DEFAULT_DATE_FORMAT = 'yyyy-MM-dd';

  private static final Pattern FIELD_PATH_PATTERN = Pattern.compile(
    '^([A-Za-z][A-Za-z0-9_]*)\\.([A-Za-z][A-Za-z0-9_]*)$'
  );
  private static final Pattern TEMPLATE_TOKEN_PATTERN = Pattern.compile(
    '\\{([A-Za-z][A-Za-z0-9_]*)\\.([A-Za-z][A-Za-z0-9_]*)(?::([^}]+))?\\}'
  );

  @TestVisible
  private static List<RenewOpportunityField__mdt> cachedDefinitions;

  @TestVisible
  static void resetCache() {
    cachedDefinitions = null;
  }

  /**
   * 受注済み契約履歴から更新商談を1件作成する。
   * 同一履歴に既に紐づく更新商談がある場合はエラーにせず、
   * 旧商談の SourceContractHistory__c を外してから新規作成する（紐づけは新しい方のみ）。
   * @return 作成した Opportunity Id
   */
  public static Id createFromOrderedHistory(Id contractHistoryId) {
    if (contractHistoryId == null) {
      throw new RenewOpportunityException('契約履歴 Id が指定されていません。');
    }

    List<RenewOpportunityField__mdt> definitions = getActiveDefinitions();
    validateActiveDefinitions(definitions);

    CreateContext context = loadContext(contractHistoryId, definitions);
    validateContext(context);

    unlinkExistingSourceHistories(contractHistoryId);

    Opportunity renewOpportunity = new Opportunity();
    renewOpportunity.put(FIELD_ACCOUNT_ID, context.opportunity.AccountId);
    renewOpportunity.put(FIELD_PREVIOUS_OPPORTUNITY, context.opportunity.Id);
    renewOpportunity.put(FIELD_SOURCE_CONTRACT_HISTORY, context.history.Id);

    Map<String, SObject> sourcesByObject = new Map<String, SObject>{
      OBJECT_OPPORTUNITY => context.opportunity,
      OBJECT_ACCOUNT => context.account,
      OBJECT_CONTRACT_HISTORY => context.history,
      OBJECT_CONTRACT_SERVICE => context.service
    };
    applyDefinitions(renewOpportunity, definitions, sourcesByObject);

    SystemContextAccess.insertRecords(
      new List<SObject>{ renewOpportunity }
    );
    return renewOpportunity.Id;
  }

  /**
   * 元契約履歴から作成済みの更新商談 Id を返す（無ければ null）。
   * 複数ある場合は作成日が新しい方（紐づけの正）。
   */
  public static Id findBySourceHistory(Id contractHistoryId) {
    if (contractHistoryId == null) {
      return null;
    }
    List<Opportunity> rows = [
      SELECT Id
      FROM Opportunity
      WHERE SourceContractHistory__c = :contractHistoryId
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].Id;
  }

  /**
   * 同一契約履歴に紐づく更新商談の SourceContractHistory__c を外す（商談自体は残す）。
   */
  private static void unlinkExistingSourceHistories(Id contractHistoryId) {
    List<Opportunity> rows = [
      SELECT Id
      FROM Opportunity
      WHERE SourceContractHistory__c = :contractHistoryId
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty()) {
      return;
    }
    for (Opportunity row : rows) {
      row.SourceContractHistory__c = null;
    }
    try {
      SystemContextAccess.updateRecords(rows);
    } catch (Exception ex) {
      throw new RenewOpportunityException(
        '既存の更新商談の紐づけ解除に失敗しました。' +
          dmlDetailSuffix(ex)
      );
    }
  }

  private static String dmlDetailSuffix(Exception ex) {
    if (ex instanceof DmlException) {
      DmlException dml = (DmlException) ex;
      if (dml.getNumDml() > 0 && String.isNotBlank(dml.getDmlMessage(0))) {
        return ' ' + dml.getDmlMessage(0);
      }
    }
    return String.isBlank(ex.getMessage()) ? '' : ' ' + ex.getMessage();
  }

  /**
   * 元契約履歴から作成した更新商談を削除する（無ければ何もしない）。
   */
  public static void deleteBySourceHistory(Id contractHistoryId) {
    Id opportunityId = findBySourceHistory(contractHistoryId);
    if (opportunityId == null) {
      return;
    }
    try {
      SystemContextAccess.deleteRecords(
        new List<SObject>{ new Opportunity(Id = opportunityId) }
      );
    } catch (Exception ex) {
      throw new RenewOpportunityException(
        '更新商談の削除に失敗しました。' + dmlDetailSuffix(ex)
      );
    }
  }

  public static void validateActiveDefinitions() {
    validateActiveDefinitions(getActiveDefinitions());
  }

  @TestVisible
  static List<RenewOpportunityField__mdt> getActiveDefinitions() {
    if (cachedDefinitions != null) {
      return cachedDefinitions;
    }
    cachedDefinitions = [
      SELECT
        DeveloperName,
        MasterLabel,
        Active__c,
        TargetFieldApiName__c,
        ValueType__c,
        Value__c,
        DateFormat__c
      FROM RenewOpportunityField__mdt
      WHERE Active__c = TRUE
      ORDER BY DeveloperName
    ];
    return cachedDefinitions;
  }

  private class CreateContext {
    public ContractHistory__c history;
    public Opportunity opportunity;
    public Account account;
    public ContractService__c service;
  }

  private class FieldPath {
    public String objectApiName;
    public String fieldApiName;
  }

  private static void validateActiveDefinitions(
    List<RenewOpportunityField__mdt> definitions
  ) {
    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    Map<String, Schema.SObjectField> opportunityFields = describeFields(
      OBJECT_OPPORTUNITY,
      globalDescribe
    );
    Set<String> seenTargets = new Set<String>();

    for (RenewOpportunityField__mdt definition : definitions) {
      validateDefinition(definition, opportunityFields, globalDescribe, seenTargets);
    }
  }

  private static void validateDefinition(
    RenewOpportunityField__mdt definition,
    Map<String, Schema.SObjectField> opportunityFields,
    Map<String, Schema.SObjectType> globalDescribe,
    Set<String> seenTargets
  ) {
    if (definition == null) {
      throw new RenewOpportunityException(
        '更新商談項目の定義が不正です（定義が空です）。'
      );
    }

    String label = definitionLabel(definition);
    String targetApiName = blankToNull(definition.TargetFieldApiName__c);
    if (targetApiName == null) {
      throw buildException(definition, 'セット先項目API名は必須です。');
    }
    if (FORBIDDEN_TARGETS.contains(targetApiName)) {
      throw buildException(
        definition,
        'セット先項目「' +
          targetApiName +
          '」はコード固定のためカスタムメタデータでは指定できません。'
      );
    }
    if (seenTargets.contains(targetApiName)) {
      throw buildException(
        definition,
        'セット先項目「' + targetApiName + '」の Active 定義が重複しています。'
      );
    }
    seenTargets.add(targetApiName);

    if (!opportunityFields.containsKey(targetApiName)) {
      throw buildException(
        definition,
        'セット先項目「' + targetApiName + '」が Opportunity に存在しません。'
      );
    }
    Schema.DescribeFieldResult targetDescribe = opportunityFields.get(targetApiName)
      .getDescribe();
    if (targetDescribe.isCalculated()) {
      throw buildException(
        definition,
        'セット先項目「' + targetApiName + '」は数式のためセットできません。'
      );
    }

    String valueType = blankToNull(definition.ValueType__c);
    if (
      valueType != VALUE_TYPE_CONSTANT &&
      valueType != VALUE_TYPE_FIELD &&
      valueType != VALUE_TYPE_TEMPLATE
    ) {
      throw buildException(
        definition,
        '値タイプ「' + String.valueOf(definition.ValueType__c) + '」は不正です。'
      );
    }

    String valueText = blankToNull(definition.Value__c);
    if (valueText == null) {
      throw buildException(definition, '値は必須です。');
    }

    String dateFormat = blankToNull(definition.DateFormat__c);
    if (dateFormat != null && !ALLOWED_DATE_FORMATS.contains(dateFormat)) {
      throw buildException(
        definition,
        '日付書式「' + dateFormat + '」は許可されていません。'
      );
    }

    if (valueType == VALUE_TYPE_FIELD) {
      FieldPath path = parseFieldPath(definition, valueText);
      validateSourceFieldExists(definition, path, globalDescribe);
    } else if (valueType == VALUE_TYPE_TEMPLATE) {
      validateTemplate(definition, valueText, globalDescribe);
    }
  }

  private static void validateTemplate(
    RenewOpportunityField__mdt definition,
    String template,
    Map<String, Schema.SObjectType> globalDescribe
  ) {
    Matcher matcher = TEMPLATE_TOKEN_PATTERN.matcher(template);
    while (matcher.find()) {
      String objectApiName = matcher.group(1);
      String fieldApiName = matcher.group(2);
      String tokenFormat = blankToNull(matcher.group(3));
      if (!ALLOWED_SOURCE_OBJECTS.contains(objectApiName)) {
        throw buildException(
          definition,
          'テンプレートの参照元オブジェクト「' +
            objectApiName +
            '」は許可されていません。'
        );
      }
      if (tokenFormat != null && !ALLOWED_DATE_FORMATS.contains(tokenFormat)) {
        throw buildException(
          definition,
          'テンプレートの日付書式「' + tokenFormat + '」は許可されていません。'
        );
      }
      FieldPath path = new FieldPath();
      path.objectApiName = objectApiName;
      path.fieldApiName = fieldApiName;
      validateSourceFieldExists(definition, path, globalDescribe);
    }

    String remainder = template;
    Matcher probe = TEMPLATE_TOKEN_PATTERN.matcher(template);
    while (probe.find()) {
      remainder = remainder.replace(probe.group(0), '');
    }
    if (remainder.contains('{') || remainder.contains('}')) {
      throw buildException(
        definition,
        'テンプレートのトークン形式が不正です（{ObjectApiName.FieldApiName} または {ObjectApiName.FieldApiName:日付書式}）。'
      );
    }
  }

  private static void validateSourceFieldExists(
    RenewOpportunityField__mdt definition,
    FieldPath path,
    Map<String, Schema.SObjectType> globalDescribe
  ) {
    if (!ALLOWED_SOURCE_OBJECTS.contains(path.objectApiName)) {
      throw buildException(
        definition,
        '参照元オブジェクト「' +
          path.objectApiName +
          '」は許可されていません。'
      );
    }
    Schema.SObjectType sourceType = globalDescribe.get(path.objectApiName);
    if (sourceType == null) {
      throw buildException(
        definition,
        '参照元オブジェクト「' +
          path.objectApiName +
          '」が組織に存在しません。'
      );
    }
    Map<String, Schema.SObjectField> sourceFields = sourceType.getDescribe()
      .fields.getMap();
    if (!sourceFields.containsKey(path.fieldApiName)) {
      throw buildException(
        definition,
        '参照元項目「' +
          path.objectApiName +
          '.' +
          path.fieldApiName +
          '」が存在しません。'
      );
    }
  }

  private static CreateContext loadContext(
    Id contractHistoryId,
    List<RenewOpportunityField__mdt> definitions
  ) {
    Map<String, Set<String>> fieldsByObject = collectSourceFields(definitions);

    fieldsByObject.get(OBJECT_CONTRACT_HISTORY)
      .addAll(
        new Set<String>{
          'Id',
          'Opportunity__c',
          'ContractService__c',
          'Type__c',
          'historystatus__c',
          'CurrentTermEndDate__c',
          'Name'
        }
      );
    fieldsByObject.get(OBJECT_OPPORTUNITY)
      .addAll(new Set<String>{ 'Id', 'AccountId', 'Name' });
    fieldsByObject.get(OBJECT_ACCOUNT).addAll(new Set<String>{ 'Id', 'Name' });
    fieldsByObject.get(OBJECT_CONTRACT_SERVICE)
      .addAll(new Set<String>{ 'Id', 'Name', 'Lifecycle__c' });

    ContractHistory__c history = (ContractHistory__c) queryRecord(
      OBJECT_CONTRACT_HISTORY,
      contractHistoryId,
      fieldsByObject.get(OBJECT_CONTRACT_HISTORY)
    );
    if (history == null) {
      throw new RenewOpportunityException(
        '契約履歴が見つかりません。'
      );
    }
    if (history.Opportunity__c == null) {
      throw new RenewOpportunityException(
        '契約履歴に商談が紐づいていません。'
      );
    }

    Opportunity opportunity = (Opportunity) queryRecord(
      OBJECT_OPPORTUNITY,
      history.Opportunity__c,
      fieldsByObject.get(OBJECT_OPPORTUNITY)
    );
    if (opportunity == null) {
      throw new RenewOpportunityException('元商談が見つかりません。');
    }
    if (opportunity.AccountId == null) {
      throw new RenewOpportunityException(
        '元商談に取引先が設定されていません。'
      );
    }

    Account account = (Account) queryRecord(
      OBJECT_ACCOUNT,
      opportunity.AccountId,
      fieldsByObject.get(OBJECT_ACCOUNT)
    );
    if (account == null) {
      throw new RenewOpportunityException('取引先が見つかりません。');
    }

    ContractService__c service = null;
    if (history.ContractService__c != null) {
      service = (ContractService__c) queryRecord(
        OBJECT_CONTRACT_SERVICE,
        history.ContractService__c,
        fieldsByObject.get(OBJECT_CONTRACT_SERVICE)
      );
    }

    CreateContext context = new CreateContext();
    context.history = history;
    context.opportunity = opportunity;
    context.account = account;
    context.service = service;
    return context;
  }

  private static void validateContext(CreateContext context) {
    if (
      context.history.historystatus__c !=
      ContractDomainConstants.HISTORY_STATUS_ORDERED
    ) {
      throw new RenewOpportunityException(
        '更新商談は受注済み（Ordered）の契約履歴からのみ作成できます。'
      );
    }
    if (
      context.history.Type__c == ContractDomainConstants.HISTORY_TYPE_CANCEL
    ) {
      throw new RenewOpportunityException(
        'Cancel の契約履歴からは更新商談を作成できません。'
      );
    }
    if (
      context.history.Type__c == ContractDomainConstants.HISTORY_TYPE_ADD ||
      (context.service != null &&
      ContractServiceLifecycleService.isSpotLifecycle(
          context.service.Lifecycle__c
        ))
    ) {
      throw new RenewOpportunityException(
        'Spot（都度契約）の契約サービスでは更新商談を作成できません。'
      );
    }
  }

  private static Map<String, Set<String>> collectSourceFields(
    List<RenewOpportunityField__mdt> definitions
  ) {
    Map<String, Set<String>> fieldsByObject = new Map<String, Set<String>>{
      OBJECT_OPPORTUNITY => new Set<String>(),
      OBJECT_ACCOUNT => new Set<String>(),
      OBJECT_CONTRACT_HISTORY => new Set<String>(),
      OBJECT_CONTRACT_SERVICE => new Set<String>()
    };

    for (RenewOpportunityField__mdt definition : definitions) {
      String valueType = definition.ValueType__c;
      String valueText = definition.Value__c;
      if (valueType == VALUE_TYPE_FIELD) {
        FieldPath path = parseFieldPath(definition, valueText);
        fieldsByObject.get(path.objectApiName).add(path.fieldApiName);
      } else if (valueType == VALUE_TYPE_TEMPLATE) {
        Matcher matcher = TEMPLATE_TOKEN_PATTERN.matcher(valueText);
        while (matcher.find()) {
          fieldsByObject.get(matcher.group(1)).add(matcher.group(2));
        }
      }
    }
    return fieldsByObject;
  }

  private static SObject queryRecord(
    String objectApiName,
    Id recordId,
    Set<String> fieldApiNames
  ) {
    if (recordId == null) {
      return null;
    }
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
      .get(objectApiName)
      .getDescribe()
      .fields.getMap();
    List<String> selectFields = new List<String>();
    for (String fieldApiName : fieldApiNames) {
      if (fieldMap.containsKey(fieldApiName)) {
        selectFields.add(fieldApiName);
      }
    }
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
    return rows.isEmpty() ? null : rows[0];
  }

  private static void applyDefinitions(
    Opportunity target,
    List<RenewOpportunityField__mdt> definitions,
    Map<String, SObject> sourcesByObject
  ) {
    Map<String, Schema.SObjectField> opportunityFields = Schema.SObjectType.Opportunity.fields.getMap();

    for (RenewOpportunityField__mdt definition : definitions) {
      String targetApiName = definition.TargetFieldApiName__c;
      Schema.DescribeFieldResult targetDescribe = opportunityFields.get(targetApiName)
        .getDescribe();
      Object rawValue;
      try {
        rawValue = resolveValue(definition, sourcesByObject, targetDescribe);
      } catch (RenewOpportunityException ex) {
        throw ex;
      } catch (Exception ex) {
        throw buildException(
          definition,
          '値の解決に失敗しました。' + blankToEmpty(ex.getMessage())
        );
      }

      if (targetApiName == FIELD_OWNER_ID) {
        if (rawValue == null || String.isBlank(String.valueOf(rawValue))) {
          throw buildException(
            definition,
            'OwnerId にセットするユーザIDが空です。'
          );
        }
      }

      Object coerced;
      try {
        coerced = coerceForTarget(targetDescribe, rawValue);
      } catch (Exception ex) {
        throw buildException(
          definition,
          'セット先項目「' +
            targetApiName +
            '」への値変換に失敗しました。' +
            blankToEmpty(ex.getMessage())
        );
      }

      if (targetApiName == FIELD_OWNER_ID && coerced == null) {
        throw buildException(
          definition,
          'OwnerId にセットするユーザIDが不正です。'
        );
      }

      target.put(targetApiName, coerced);
    }
  }

  private static Object resolveValue(
    RenewOpportunityField__mdt definition,
    Map<String, SObject> sourcesByObject,
    Schema.DescribeFieldResult targetDescribe
  ) {
    String valueType = definition.ValueType__c;
    String valueText = definition.Value__c;

    if (valueType == VALUE_TYPE_CONSTANT) {
      return valueText;
    }
    if (valueType == VALUE_TYPE_FIELD) {
      FieldPath path = parseFieldPath(definition, valueText);
      SObject source = sourcesByObject.get(path.objectApiName);
      if (source == null) {
        throw buildException(
          definition,
          '参照元「' + path.objectApiName + '」のレコードがありません。'
        );
      }
      Object raw = source.get(path.fieldApiName);
      if (shouldFormatDateAsText(targetDescribe, raw)) {
        return formatDateValue(
          raw,
          resolveDateFormat(definition, null)
        );
      }
      return raw;
    }
    if (valueType == VALUE_TYPE_TEMPLATE) {
      return expandTemplate(definition, valueText, sourcesByObject);
    }
    throw buildException(definition, '値タイプが不正です。');
  }

  private static String expandTemplate(
    RenewOpportunityField__mdt definition,
    String template,
    Map<String, SObject> sourcesByObject
  ) {
    Matcher matcher = TEMPLATE_TOKEN_PATTERN.matcher(template);
    String result = '';
    Integer lastEnd = 0;
    while (matcher.find()) {
      result += template.substring(lastEnd, matcher.start());
      String objectApiName = matcher.group(1);
      String fieldApiName = matcher.group(2);
      String tokenFormat = blankToNull(matcher.group(3));
      SObject source = sourcesByObject.get(objectApiName);
      if (source == null) {
        throw buildException(
          definition,
          '参照元「' + objectApiName + '」のレコードがありません。'
        );
      }
      Object raw = source.get(fieldApiName);
      if (raw instanceof Date || raw instanceof Datetime) {
        result += formatDateValue(
          raw,
          resolveDateFormat(definition, tokenFormat)
        );
      } else {
        result += raw == null ? '' : String.valueOf(raw);
      }
      lastEnd = matcher.end();
    }
    result += template.substring(lastEnd);
    return result;
  }

  private static Boolean shouldFormatDateAsText(
    Schema.DescribeFieldResult targetDescribe,
    Object raw
  ) {
    if (!(raw instanceof Date || raw instanceof Datetime)) {
      return false;
    }
    Schema.DisplayType targetType = targetDescribe.getType();
    return targetType == Schema.DisplayType.STRING ||
      targetType == Schema.DisplayType.TEXTAREA ||
      targetType == Schema.DisplayType.PICKLIST ||
      targetType == Schema.DisplayType.COMBOBOX;
  }

  private static String resolveDateFormat(
    RenewOpportunityField__mdt definition,
    String tokenFormat
  ) {
    if (tokenFormat != null) {
      return tokenFormat;
    }
    String rowFormat = blankToNull(definition.DateFormat__c);
    return rowFormat == null ? DEFAULT_DATE_FORMAT : rowFormat;
  }

  private static String formatDateValue(Object raw, String format) {
    Date dateValue;
    if (raw instanceof Date) {
      dateValue = (Date) raw;
    } else if (raw instanceof Datetime) {
      dateValue = ((Datetime) raw).date();
    } else {
      return raw == null ? '' : String.valueOf(raw);
    }
    if (dateValue == null) {
      return '';
    }
    if (!ALLOWED_DATE_FORMATS.contains(format)) {
      format = DEFAULT_DATE_FORMAT;
    }

    String yyyy = String.valueOf(dateValue.year());
    String yy = yyyy.right(2);
    String mm = dateValue.month() < 10
      ? '0' + String.valueOf(dateValue.month())
      : String.valueOf(dateValue.month());
    String dd = dateValue.day() < 10
      ? '0' + String.valueOf(dateValue.day())
      : String.valueOf(dateValue.day());

    if (format == 'yyyyMM') {
      return yyyy + mm;
    }
    if (format == 'yyyy-MM-dd') {
      return yyyy + '-' + mm + '-' + dd;
    }
    if (format == 'yyyy/MM/dd') {
      return yyyy + '/' + mm + '/' + dd;
    }
    if (format == 'yyyy/MM') {
      return yyyy + '/' + mm;
    }
    if (format == 'yy/MM') {
      return yy + '/' + mm;
    }
    return yyyy + '-' + mm + '-' + dd;
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
      if (String.isBlank(text)) {
        return null;
      }
      return (Id) text;
    }
    if (fieldType == Schema.DisplayType.DATE && rawValue instanceof Datetime) {
      return ((Datetime) rawValue).date();
    }
    if (fieldType == Schema.DisplayType.DATETIME && rawValue instanceof Date) {
      Date dateValue = (Date) rawValue;
      return Datetime.newInstance(dateValue, Time.newInstance(0, 0, 0, 0));
    }
    if (
      (fieldType == Schema.DisplayType.DATE ||
      fieldType == Schema.DisplayType.DATETIME) &&
      !(rawValue instanceof Date) &&
      !(rawValue instanceof Datetime) &&
      !(rawValue instanceof String)
    ) {
      return rawValue;
    }
    return ContractWizardFieldService.coerceValue(targetDescribe, rawValue);
  }

  private static FieldPath parseFieldPath(
    RenewOpportunityField__mdt definition,
    String valueText
  ) {
    Matcher matcher = FIELD_PATH_PATTERN.matcher(valueText.trim());
    if (!matcher.matches()) {
      throw buildException(
        definition,
        '参照パス「' +
          valueText +
          '」は ObjectApiName.FieldApiName 形式（ドット1つ）である必要があります。'
      );
    }
    FieldPath path = new FieldPath();
    path.objectApiName = matcher.group(1);
    path.fieldApiName = matcher.group(2);
    return path;
  }

  private static Map<String, Schema.SObjectField> describeFields(
    String objectApiName,
    Map<String, Schema.SObjectType> globalDescribe
  ) {
    Schema.SObjectType sobjectType = globalDescribe.get(objectApiName);
    if (sobjectType == null) {
      throw new RenewOpportunityException(
        'オブジェクト「' + objectApiName + '」が組織に存在しません。'
      );
    }
    return sobjectType.getDescribe().fields.getMap();
  }

  private static RenewOpportunityException buildException(
    RenewOpportunityField__mdt definition,
    String detail
  ) {
    return new RenewOpportunityException(
      '更新商談項目「' + definitionLabel(definition) + '」: ' + detail
    );
  }

  private static String definitionLabel(RenewOpportunityField__mdt definition) {
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

  private static String blankToNull(String value) {
    return String.isBlank(value) ? null : value.trim();
  }

  private static String blankToEmpty(String value) {
    return String.isBlank(value) ? '' : ' ' + value;
  }
}
