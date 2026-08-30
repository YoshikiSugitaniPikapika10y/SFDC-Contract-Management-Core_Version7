public without sharing class FieldCopyDefinitionService {
  public static final String CONTEXT_AUTO_RENEW = 'AutoRenew';
  public static final String CONTEXT_NOT_AUTO_RENEW = 'NotAutoRenew';
  public static final String CONTEXT_LINE_JOURNAL = 'LineJournal';
  public static final String CONTEXT_NON_LINE_JOURNAL = 'NonLineJournal';

  public class FieldCopyException extends Exception {
  }

  private static final Set<String> TARGET_OBJECTS = new Set<String>{
    'ContractHistory__c',
    'InvoiceProduct__c',
    'Invoice__c',
    'InvoiceLine__c',
    'InvoicePayment__c',
    'GlJournal__c'
  };

  private static final Set<String> HISTORY_CONTEXTS = new Set<String>{
    CONTEXT_AUTO_RENEW,
    CONTEXT_NOT_AUTO_RENEW
  };
  private static final Set<String> JOURNAL_CONTEXTS = new Set<String>{
    CONTEXT_LINE_JOURNAL,
    CONTEXT_NON_LINE_JOURNAL
  };

  private static final Map<String, Set<String>> ALLOWED_SOURCE_BY_TARGET = new Map<String, Set<String>>{
    'ContractHistory__c' => new Set<String>{
      'Opportunity',
      'ContractHistory__c',
      'Account',
      'ContractService__c',
      'BillingAccount__c'
    },
    'InvoiceProduct__c' => new Set<String>{
      'ContractHistory__c',
      'ContractProduct__c',
      'Product2',
      'BillingAccount__c',
      'Opportunity',
      'Account'
    },
    'Invoice__c' => new Set<String>{
      'ContractHistory__c',
      'ContractProduct__c',
      'Product2',
      'BillingAccount__c',
      'Opportunity',
      'Account'
    },
    'InvoiceLine__c' => new Set<String>{
      'ContractHistory__c',
      'ContractProduct__c',
      'Product2',
      'BillingAccount__c',
      'Opportunity',
      'Account'
    },
    'InvoicePayment__c' => new Set<String>{
      'Invoice__c',
      'BillingAccount__c',
      'ContractHistory__c',
      'Opportunity',
      'Account'
    }
  };

  private static final Set<String> JOURNAL_LINE_SOURCES = new Set<String>{
    'InvoiceLine__c',
    'ContractProduct__c',
    'Product2',
    'InvoicePayment__c',
    'InvoicePaymentAllocation__c',
    'Invoice__c',
    'BillingAccount__c',
    'ContractHistory__c',
    'Opportunity',
    'Account'
  };
  private static final Set<String> JOURNAL_NON_LINE_SOURCES = new Set<String>{
    'Invoice__c',
    'BillingAccount__c',
    'ContractHistory__c',
    'Opportunity',
    'Account',
    'InvoicePayment__c'
  };

  private static final Map<String, Set<String>> DENIED_TARGET_FIELDS = new Map<String, Set<String>>{
    'ContractHistory__c' => new Set<String>{
      'Version__c',
      'Opportunity__c',
      'ContractService__c',
      'PreviousHistory__c',
      'RenewalOpportunity__c',
      'CreateRenewOpportunity__c',
      'RenewEstimateAutoCreated__c',
      'RenewOpportunityRequestCount__c',
      'PaidCount__c',
      'InvoicedCount__c',
      'InvoiceCount__c',
      'historystatus__c',
      'Type__c',
      'StatusPath__c',
      'ARR__c',
      'AveARR__c',
      'DeltaARR__c',
      'DeltaAveARR__c',
      'DeltaAmountSum__c',
      'DeltaTaxInclusiveSum__c'
    },
    'InvoiceProduct__c' => new Set<String>(),
    'Invoice__c' => new Set<String>{
      'Amount__c',
      'TaxAmount__c',
      'InvoiceTransactionStatus__c',
      'DeliveryStatus__c',
      'CollectionRefundStatus__c',
      'BillingAccountSnapShot__c',
      'InvoiceDate__c',
      'PaymentScheduledDate__c',
      'ContractHistory__c',
      'ContractService__c',
      'TaxPercent__c',
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
      'PaymentTermAdjustSnapShot__c'
    },
    'InvoiceLine__c' => new Set<String>(),
    'InvoicePayment__c' => new Set<String>{
      'Amount__c',
      'PaymentTransactionStatus__c',
      'Invoice__c',
      'BillingAccount__c',
      'BillingAccountKeySnapShot__c',
      'PaymentPurpose__c',
      'OriginalPayment__c'
    },
    'GlJournal__c' => new Set<String>{
      'Amount__c',
      'DebitSlotKey__c',
      'CreditSlotKey__c',
      'DebitAccount__c',
      'CreditAccount__c',
      'DebitAccountAssignment__c',
      'CreditAccountAssignment__c',
      'IdempotencyKey__c',
      'JournalLineKey__c',
      'GenerationUnitKey__c',
      'BusinessOperationKey__c',
      'TransactionStatus__c',
      'IsLocked__c',
      'PostingDate__c',
      'Invoice__c',
      'InvoiceLine__c',
      'InvoicePayment__c',
      'InvoicePaymentAllocation__c',
      'BillingAccount__c',
      'BillingAccountKeySnapShot__c',
      'AccountingEventKey__c',
      'JournalPatternKey__c',
      'RecognitionSequence__c',
      'OriginalJournal__c',
      'GlManualJournalHeader__c',
      'GlManualJournalSetting__c'
    }
  };

  /** 仕様: Core 第11.4.2節 */
  public static void validateDefinitions(List<FieldCopyDefinition__c> definitions) {
    if (definitions == null) {
      return;
    }
    for (FieldCopyDefinition__c definition : definitions) {
      try {
        validateDefinition(definition, definitions);
      } catch (FieldCopyException ex) {
        definition.addError(ex.getMessage());
      }
    }
  }

  /** 仕様: Core 第11.4.2節 */
  public static void validateDefinition(FieldCopyDefinition__c definition) {
    validateDefinition(definition, null);
  }

  /** 仕様: Accounting 第3.1節、Core 第11.4.2節 */
  public static void validateAllDefinitions() {
    validateAllDefinitions(
      [
        SELECT
          Name,
          TargetObject__c,
          Context__c,
          SourceObject__c,
          SourceFieldApiName__c,
          TargetFieldApiName__c
        FROM FieldCopyDefinition__c
        WITH SYSTEM_MODE
      ]
    );
  }

  @TestVisible
  static Set<String> additionalRequiredJournalFieldApiNames;

  /** 仕様: Accounting 第3.1節、Core 第11.4.2節 */
  @TestVisible
  static void validateAllDefinitions(List<FieldCopyDefinition__c> definitions) {
    if (definitions == null) {
      definitions = new List<FieldCopyDefinition__c>();
    }
    for (FieldCopyDefinition__c definition : definitions) {
      validateDefinition(definition, definitions);
    }
    assertRequiredJournalFieldsReachable(definitions);
  }

  /** 仕様: Core 第11.4.2節 */
  private static void validateDefinition(
    FieldCopyDefinition__c definition,
    List<FieldCopyDefinition__c> batch
  ) {
    if (definition == null) {
      throw new FieldCopyException('コピー定義がありません。');
    }
    String key = definitionLabel(definition);
    if (!TARGET_OBJECTS.contains(definition.TargetObject__c)) {
      throw new FieldCopyException('Toオブジェクトがありません: ' + key);
    }
    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    Schema.SObjectType targetType = globalDescribe.get(definition.TargetObject__c);
    Schema.SObjectType sourceType = globalDescribe.get(definition.SourceObject__c);
    if (targetType == null) {
      throw new FieldCopyException('Toオブジェクトがありません: ' + key);
    }
    if (sourceType == null) {
      throw new FieldCopyException('Fromオブジェクトがありません: ' + key);
    }
    assertContext(definition, key);
    assertAllowedSource(definition, key);
    Map<String, Schema.SObjectField> targetFields = targetType.getDescribe().fields.getMap();
    Map<String, Schema.SObjectField> sourceFields = sourceType.getDescribe().fields.getMap();
    if (
      String.isBlank(definition.TargetFieldApiName__c) ||
      !targetFields.containsKey(definition.TargetFieldApiName__c)
    ) {
      throw new FieldCopyException('To項目がありません: ' + key);
    }
    if (
      String.isBlank(definition.SourceFieldApiName__c) ||
      !sourceFields.containsKey(definition.SourceFieldApiName__c)
    ) {
      throw new FieldCopyException('From項目がありません: ' + key);
    }
    Schema.DescribeFieldResult targetDescribe = targetFields.get(definition.TargetFieldApiName__c)
      .getDescribe();
    Schema.DescribeFieldResult sourceDescribe = sourceFields.get(definition.SourceFieldApiName__c)
      .getDescribe();
    if (!targetDescribe.isUpdateable() || isForbiddenTargetType(targetDescribe)) {
      throw new FieldCopyException('To項目へ書けません: ' + key);
    }
    if (isDeniedTarget(definition.TargetObject__c, definition.TargetFieldApiName__c)) {
      throw new FieldCopyException('パッケージ項目はコピー先にできません: ' + key);
    }
    if (
      InvoiceProductFieldCopyService.getHardcodedTargetFieldApiNames(definition.TargetObject__c)
        .contains(definition.TargetFieldApiName__c)
    ) {
      throw new FieldCopyException('ハードコード先とTo項目が重複しています: ' + key);
    }
    if (!areTypesCompatible(sourceDescribe.getType(), targetDescribe.getType())) {
      throw new FieldCopyException('コピーできる型ではありません: ' + key);
    }
    assertReferenceMatch(sourceDescribe, targetDescribe, key);
    assertUniqueName(definition, batch, key);
    assertUniqueTarget(definition, batch, key);
  }

  /** 仕様: Core 第11.4.2節 */
  public static void apply(
    SObject target,
    String targetObjectApiName,
    String context,
    Map<String, SObject> sourceByObject
  ) {
    if (target == null || String.isBlank(targetObjectApiName)) {
      return;
    }
    if (sourceByObject == null) {
      sourceByObject = new Map<String, SObject>();
    }
    for (FieldCopyDefinition__c definition : [
      SELECT
        Name,
        TargetObject__c,
        Context__c,
        SourceObject__c,
        SourceFieldApiName__c,
        TargetFieldApiName__c
      FROM FieldCopyDefinition__c
      WHERE TargetObject__c = :targetObjectApiName
      WITH SYSTEM_MODE
    ]) {
      if (!contextMatches(definition.Context__c, context, targetObjectApiName)) {
        continue;
      }
      validateDefinition(definition);
      Object current = target.get(definition.TargetFieldApiName__c);
      if (current != null && String.valueOf(current) != '') {
        continue;
      }
      SObject source = sourceByObject.get(definition.SourceObject__c);
      if (source == null) {
        continue;
      }
      Object value = source.get(definition.SourceFieldApiName__c);
      assertValueFits(definition, value);
      target.put(definition.TargetFieldApiName__c, value);
    }
  }

  /** 仕様: Accounting 第8.7節 */
  public static List<String> targetFieldApiNames(String targetObjectApiName) {
    Set<String> names = new Set<String>();
    if (String.isBlank(targetObjectApiName)) {
      return new List<String>();
    }
    Schema.SObjectType targetType = Schema.getGlobalDescribe().get(targetObjectApiName);
    if (targetType == null) {
      return new List<String>();
    }
    Map<String, Schema.SObjectField> fields = targetType.getDescribe().fields.getMap();
    for (FieldCopyDefinition__c definition : [
      SELECT TargetFieldApiName__c
      FROM FieldCopyDefinition__c
      WHERE TargetObject__c = :targetObjectApiName
      WITH SYSTEM_MODE
    ]) {
      if (
        String.isNotBlank(definition.TargetFieldApiName__c) &&
        fields.containsKey(definition.TargetFieldApiName__c)
      ) {
        names.add(definition.TargetFieldApiName__c);
      }
    }
    return new List<String>(names);
  }

  /** 仕様: Core 第11.4.2節 */
  public static void applyOnInsert(List<SObject> records, String targetObjectApiName) {
    InvoiceProductFieldCopyService.applyOnBeforeInsert(
      records,
      targetObjectApiName
    );
  }

  private static Boolean contextMatches(
    String definitionContext,
    String requestedContext,
    String targetObjectApiName
  ) {
    if (targetObjectApiName != 'ContractHistory__c' && targetObjectApiName != 'GlJournal__c') {
      return true;
    }
    if (String.isBlank(definitionContext) || String.isBlank(requestedContext)) {
      return false;
    }
    return splitContext(definitionContext).contains(requestedContext);
  }

  /** 仕様: Accounting 第3.1節、Core 第11.4.2節 */
  private static void assertRequiredJournalFieldsReachable(
    List<FieldCopyDefinition__c> definitions
  ) {
    Map<String, Set<String>> coveredContextsByField = new Map<String, Set<String>>();
    for (FieldCopyDefinition__c definition : definitions) {
      if (definition == null || definition.TargetObject__c != 'GlJournal__c') {
        continue;
      }
      if (String.isBlank(definition.TargetFieldApiName__c)) {
        continue;
      }
      String fieldKey = definition.TargetFieldApiName__c.toLowerCase();
      Set<String> covered = coveredContextsByField.get(fieldKey);
      if (covered == null) {
        covered = new Set<String>();
        coveredContextsByField.put(fieldKey, covered);
      }
      covered.addAll(splitContext(definition.Context__c));
    }
    for (String fieldApiName : requiredJournalCustomFieldApiNames()) {
      Set<String> covered = coveredContextsByField.get(fieldApiName.toLowerCase());
      Boolean line = covered != null && covered.contains(CONTEXT_LINE_JOURNAL);
      Boolean nonLine = covered != null && covered.contains(CONTEXT_NON_LINE_JOURNAL);
      if (!line || !nonLine) {
        throw new FieldCopyException('必須項目へ届くコピー定義がありません: ' + fieldApiName);
      }
    }
  }

  private static Set<String> requiredJournalCustomFieldApiNames() {
    Set<String> names = new Set<String>();
    Schema.SObjectType journalType = Schema.getGlobalDescribe().get('GlJournal__c');
    if (journalType == null) {
      return names;
    }
    Set<String> hardcoded = InvoiceProductFieldCopyService.getHardcodedTargetFieldApiNames(
      'GlJournal__c'
    );
    for (Schema.SObjectField field : journalType.getDescribe().fields.getMap().values()) {
      Schema.DescribeFieldResult describe = field.getDescribe();
      if (
        !describe.isCustom() ||
        describe.isNillable() ||
        !describe.isCreateable() ||
        describe.getType() == Schema.DisplayType.BOOLEAN ||
        isForbiddenTargetType(describe) ||
        isDeniedTarget('GlJournal__c', describe.getName()) ||
        hardcoded.contains(describe.getName())
      ) {
        continue;
      }
      names.add(describe.getName());
    }
    if (additionalRequiredJournalFieldApiNames != null) {
      names.addAll(additionalRequiredJournalFieldApiNames);
    }
    return names;
  }

  private static void assertContext(FieldCopyDefinition__c definition, String key) {
    Set<String> selected = splitContext(definition.Context__c);
    if (definition.TargetObject__c == 'ContractHistory__c') {
      if (selected.isEmpty()) {
        throw new FieldCopyException('コンテキストが必要です: ' + key);
      }
      for (String value : selected) {
        if (!HISTORY_CONTEXTS.contains(value)) {
          throw new FieldCopyException('コンテキストが不正です: ' + key);
        }
      }
      return;
    }
    if (definition.TargetObject__c == 'GlJournal__c') {
      if (selected.isEmpty()) {
        throw new FieldCopyException('コンテキストが必要です: ' + key);
      }
      for (String value : selected) {
        if (!JOURNAL_CONTEXTS.contains(value)) {
          throw new FieldCopyException('コンテキストが不正です: ' + key);
        }
      }
      return;
    }
    if (!selected.isEmpty()) {
      throw new FieldCopyException('コンテキストは空にしてください: ' + key);
    }
  }

  private static void assertAllowedSource(FieldCopyDefinition__c definition, String key) {
    Set<String> allowed;
    if (definition.TargetObject__c == 'GlJournal__c') {
      Set<String> selected = splitContext(definition.Context__c);
      Boolean line = selected.contains(CONTEXT_LINE_JOURNAL);
      Boolean nonLine = selected.contains(CONTEXT_NON_LINE_JOURNAL);
      if (line && nonLine) {
        allowed = new Set<String>(JOURNAL_LINE_SOURCES);
        allowed.retainAll(JOURNAL_NON_LINE_SOURCES);
      } else if (line) {
        allowed = JOURNAL_LINE_SOURCES;
      } else {
        allowed = JOURNAL_NON_LINE_SOURCES;
      }
    } else {
      allowed = ALLOWED_SOURCE_BY_TARGET.get(definition.TargetObject__c);
    }
    if (allowed == null || !allowed.contains(definition.SourceObject__c)) {
      throw new FieldCopyException('Fromオブジェクトを選べません: ' + key);
    }
  }

  private static Boolean isDeniedTarget(String targetObjectApiName, String fieldApiName) {
    Set<String> denied = DENIED_TARGET_FIELDS.get(targetObjectApiName);
    return denied != null && denied.contains(fieldApiName);
  }

  private static Boolean isForbiddenTargetType(Schema.DescribeFieldResult targetDescribe) {
    if (targetDescribe.isCalculated() || targetDescribe.isAutoNumber() || targetDescribe.isEncrypted()) {
      return true;
    }
    Schema.DisplayType fieldType = targetDescribe.getType();
    return fieldType == Schema.DisplayType.BASE64 ||
      fieldType == Schema.DisplayType.ENCRYPTEDSTRING ||
      fieldType == Schema.DisplayType.ADDRESS ||
      fieldType == Schema.DisplayType.LOCATION ||
      fieldType == Schema.DisplayType.TIME;
  }

  private static Boolean areTypesCompatible(
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
      (sourceType == Schema.DisplayType.DATE || sourceType == Schema.DisplayType.DATETIME) &&
      (targetType == Schema.DisplayType.DATE || targetType == Schema.DisplayType.DATETIME)
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
      fieldType == Schema.DisplayType.URL;
  }

  private static Boolean isNumberLike(Schema.DisplayType fieldType) {
    return fieldType == Schema.DisplayType.DOUBLE ||
      fieldType == Schema.DisplayType.CURRENCY ||
      fieldType == Schema.DisplayType.PERCENT ||
      fieldType == Schema.DisplayType.INTEGER ||
      fieldType == Schema.DisplayType.LONG;
  }

  private static Boolean isIdLike(Schema.DisplayType fieldType) {
    return fieldType == Schema.DisplayType.REFERENCE || fieldType == Schema.DisplayType.ID;
  }

  private static void assertReferenceMatch(
    Schema.DescribeFieldResult sourceDescribe,
    Schema.DescribeFieldResult targetDescribe,
    String key
  ) {
    if (
      sourceDescribe.getType() != Schema.DisplayType.REFERENCE &&
      sourceDescribe.getType() != Schema.DisplayType.ID
    ) {
      return;
    }
    if (
      targetDescribe.getType() != Schema.DisplayType.REFERENCE &&
      targetDescribe.getType() != Schema.DisplayType.ID
    ) {
      throw new FieldCopyException('参照を文字へ直接コピーできません: ' + key);
    }
    List<Schema.SObjectType> sourceRefs = sourceDescribe.getReferenceTo();
    List<Schema.SObjectType> targetRefs = targetDescribe.getReferenceTo();
    if (sourceRefs.isEmpty() || targetRefs.isEmpty()) {
      return;
    }
    Set<String> targetNames = new Set<String>();
    for (Schema.SObjectType targetRef : targetRefs) {
      targetNames.add(String.valueOf(targetRef));
    }
    for (Schema.SObjectType sourceRef : sourceRefs) {
      if (targetNames.contains(String.valueOf(sourceRef))) {
        return;
      }
    }
    throw new FieldCopyException('参照の先オブジェクトが違います: ' + key);
  }

  private static void assertUniqueName(
    FieldCopyDefinition__c definition,
    List<FieldCopyDefinition__c> batch,
    String key
  ) {
    if (String.isBlank(definition.Name)) {
      return;
    }
    if (batch != null) {
      Integer sameName = 0;
      for (FieldCopyDefinition__c other : batch) {
        if (other != null && other.Name == definition.Name) {
          sameName++;
        }
      }
      if (sameName > 1) {
        throw new FieldCopyException('一意キーが重複しています: ' + key);
      }
    }
    List<FieldCopyDefinition__c> existing = [
      SELECT Id
      FROM FieldCopyDefinition__c
      WHERE Name = :definition.Name AND Id != :definition.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      throw new FieldCopyException('一意キーが重複しています: ' + key);
    }
  }

  private static void assertUniqueTarget(
    FieldCopyDefinition__c definition,
    List<FieldCopyDefinition__c> batch,
    String key
  ) {
    Set<String> ownContext = effectiveContext(definition);
    if (batch != null) {
      for (FieldCopyDefinition__c other : batch) {
        if (other == definition || other == null) {
          continue;
        }
        if (overlapsTarget(definition, ownContext, other)) {
          throw new FieldCopyException('同じTo項目の定義が重なっています: ' + key);
        }
      }
    }
    for (FieldCopyDefinition__c other : [
      SELECT Id, Name, TargetObject__c, Context__c, TargetFieldApiName__c
      FROM FieldCopyDefinition__c
      WHERE
        TargetObject__c = :definition.TargetObject__c
        AND TargetFieldApiName__c = :definition.TargetFieldApiName__c
        AND Id != :definition.Id
      WITH SYSTEM_MODE
    ]) {
      if (overlapsTarget(definition, ownContext, other)) {
        throw new FieldCopyException('同じTo項目の定義が重なっています: ' + key);
      }
    }
  }

  private static Boolean overlapsTarget(
    FieldCopyDefinition__c definition,
    Set<String> ownContext,
    FieldCopyDefinition__c other
  ) {
    if (
      other.TargetObject__c != definition.TargetObject__c ||
      other.TargetFieldApiName__c != definition.TargetFieldApiName__c
    ) {
      return false;
    }
    Set<String> otherContext = effectiveContext(other);
    if (ownContext.isEmpty() && otherContext.isEmpty()) {
      return true;
    }
    for (String value : ownContext) {
      if (otherContext.contains(value)) {
        return true;
      }
    }
    return false;
  }

  private static Set<String> effectiveContext(FieldCopyDefinition__c definition) {
    if (
      definition.TargetObject__c != 'ContractHistory__c' &&
      definition.TargetObject__c != 'GlJournal__c'
    ) {
      return new Set<String>();
    }
    return splitContext(definition.Context__c);
  }

  private static void assertValueFits(FieldCopyDefinition__c definition, Object value) {
    if (!(value instanceof String)) {
      return;
    }
    Schema.SObjectType targetType = Schema.getGlobalDescribe().get(definition.TargetObject__c);
    if (targetType == null) {
      return;
    }
    Schema.DescribeFieldResult targetDescribe = targetType.getDescribe()
      .fields.getMap()
      .get(definition.TargetFieldApiName__c)
      .getDescribe();
    Integer maxLength = targetDescribe.getLength();
    if (maxLength != null && maxLength > 0 && ((String) value).length() > maxLength) {
      throw new FieldCopyException('文字が先の桁を超えています: ' + definitionLabel(definition));
    }
  }

  private static Set<String> splitContext(String context) {
    Set<String> values = new Set<String>();
    if (String.isBlank(context)) {
      return values;
    }
    for (String part : context.split(';')) {
      if (String.isNotBlank(part)) {
        values.add(part.trim());
      }
    }
    return values;
  }

  private static String definitionLabel(FieldCopyDefinition__c definition) {
    return definition == null || String.isBlank(definition.Name) ? '(不明)' : definition.Name;
  }
}
