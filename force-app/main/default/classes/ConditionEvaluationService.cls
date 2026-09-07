public without sharing class ConditionEvaluationService {
  public class EvaluationException extends Exception {
  }

  private static Map<String, Schema.SObjectType> cachedGlobalDescribe;
  private static Map<String, Map<String, Schema.SObjectField>> cachedFieldsByObject;
  private static Map<String, Schema.DescribeFieldResult> cachedFieldDescribes;

  private static final Map<String, Set<String>> REACHABLE_OBJECTS = new Map<String, Set<String>>{
    'InvoiceLine' => new Set<String>{
      'InvoiceLine__c',
      'Invoice__c',
      'ContractProduct__c',
      'Product2',
      'ContractHistory__c',
      'ContractService__c',
      'Opportunity',
      'BillingAccount__c',
      'Account'
    },
    'Invoice' => new Set<String>{
      'Invoice__c',
      'InvoiceLine__c',
      'ContractProduct__c',
      'Product2',
      'ContractHistory__c',
      'ContractService__c',
      'Opportunity',
      'BillingAccount__c',
      'Account'
    },
    'InvoicePayment' => new Set<String>{
      'InvoicePayment__c',
      'Invoice__c',
      'ContractHistory__c',
      'ContractService__c',
      'Opportunity',
      'BillingAccount__c',
      'Account'
    },
    'InvoicePaymentAllocation' => new Set<String>{
      'InvoicePaymentAllocation__c',
      'InvoicePayment__c',
      'Invoice__c',
      'InvoiceLine__c',
      'ContractProduct__c',
      'Product2',
      'ContractHistory__c',
      'ContractService__c',
      'Opportunity',
      'BillingAccount__c',
      'Account'
    }
  };

  public class Context {
    public Invoice__c invoice;
    public InvoiceLine__c invoiceLine;
    public List<InvoiceLine__c> invoiceLines;
    public InvoicePayment__c invoicePayment;
    public InvoicePaymentAllocation__c allocation;
    public ContractProduct__c contractProduct;
    public Product2 product;
    public ContractHistory__c contractHistory;
    public ContractService__c contractService;
    public Opportunity opportunity;
    public BillingAccount__c billingAccount;
    public Account account;
  }

  /** 仕様: Accounting 第4.7節 */
  public static Boolean evaluate(
    FixedConditionSetFixedCatalog.Definition conditionSet,
    Context context
  ) {
    if (conditionSet == null) {
      return true;
    }
    List<FixedConditionRuleFixedCatalog.Definition> rules = new List<FixedConditionRuleFixedCatalog.Definition>();
    for (
      FixedConditionRuleFixedCatalog.Definition rule : FixedConditionRuleFixedCatalog.values()
    ) {
      if (rule.conditionSet.key == conditionSet.key) {
        rules.add(rule);
      }
    }
    if (rules.isEmpty()) {
      return true;
    }
    for (FixedConditionRuleFixedCatalog.Definition rule : rules) {
      if (!evaluateRule(rule, context)) {
        return false;
      }
    }
    return true;
  }

  private class TenantSetDefinition {
    String conditionLogic;
    String evaluationContext;
    List<GlConditionRule__c> rules = new List<GlConditionRule__c>();
  }

  private static Boolean tenantDefinitionsLoaded;
  private static Map<Id, TenantSetDefinition> tenantSetsById;
  private static List<GlConditionRule__c> collectedRules;

  /**
   * 仕様: Accounting 第8.2節手順2。
   * 同一処理で条件セットと条件ルールを取り直さない。
   */
  public static List<GlConditionRule__c> collectedTenantRules() {
    ensureTenantDefinitionsLoaded();
    return collectedRules;
  }

  /** 仕様: Accounting 第4.7節、第6章、第8.2節。空欄なら全条件AND。番号は ConditionLogic の AND／OR／NOT・括弧。 */
  public static Boolean evaluateTenant(Id conditionSetId, Context context) {
    if (conditionSetId == null) {
      return true;
    }
    ensureTenantDefinitionsLoaded();
    TenantSetDefinition loaded = tenantSetsById.get(conditionSetId);
    if (loaded == null) {
      throw new EvaluationException('条件セットがありません。');
    }
    if (loaded.rules.isEmpty()) {
      throw new EvaluationException('条件が0件の条件セットは参照できません。');
    }
    Map<Decimal, Boolean> bySequence = new Map<Decimal, Boolean>();
    for (GlConditionRule__c rule : loaded.rules) {
      bySequence.put(
        rule.Sequence__c,
        evaluateTenantRule(rule, loaded.evaluationContext, context)
      );
    }
    if (String.isBlank(loaded.conditionLogic)) {
      for (Boolean matched : bySequence.values()) {
        if (matched != true) {
          return false;
        }
      }
      return true;
    }
    return evaluateConditionLogic(loaded.conditionLogic, bySequence);
  }

  private static void ensureTenantDefinitionsLoaded() {
    if (tenantDefinitionsLoaded == true) {
      return;
    }
    tenantSetsById = new Map<Id, TenantSetDefinition>();
    collectedRules = new List<GlConditionRule__c>();
    for (GlConditionSet__c conditionSet : [
      SELECT Id, ConditionLogic__c, EvaluationContext__c
      FROM GlConditionSet__c
      WITH SYSTEM_MODE
    ]) {
      TenantSetDefinition loaded = new TenantSetDefinition();
      loaded.conditionLogic = conditionSet.ConditionLogic__c;
      loaded.evaluationContext = conditionSet.EvaluationContext__c;
      tenantSetsById.put(conditionSet.Id, loaded);
    }
    for (GlConditionRule__c rule : [
      SELECT
        ConditionSet__c,
        Sequence__c,
        Aggregate__c,
        TargetObject__c,
        TargetField__c,
        Operator__c,
        CompareType__c,
        CompareValue__c,
        CompareObject__c,
        CompareField__c
      FROM GlConditionRule__c
      WITH SYSTEM_MODE
      ORDER BY Sequence__c
    ]) {
      collectedRules.add(rule);
      TenantSetDefinition loaded = tenantSetsById.get(rule.ConditionSet__c);
      if (loaded != null) {
        loaded.rules.add(rule);
      }
    }
    tenantDefinitionsLoaded = true;
  }

  /** 仕様: Accounting 第4.7節。請求起点の請求明細はすべて／いずれかで集約する。 */
  private static Boolean evaluateTenantRule(
    GlConditionRule__c rule,
    String evaluationContext,
    Context context
  ) {
    if (
      evaluationContext == 'Invoice' &&
      rule.TargetObject__c == 'InvoiceLine__c' &&
      (rule.Aggregate__c == 'All' ||
      rule.Aggregate__c == 'Any')
    ) {
      return evaluateInvoiceLineAggregate(rule, context);
    }
    return compareTenantRule(rule, context);
  }

  private static Boolean evaluateInvoiceLineAggregate(
    GlConditionRule__c rule,
    Context context
  ) {
    List<InvoiceLine__c> lines = context == null ? null : context.invoiceLines;
    if (lines == null || lines.isEmpty()) {
      if (context == null || context.invoiceLine == null) {
        return rule.Aggregate__c == 'All';
      }
      lines = new List<InvoiceLine__c>{ context.invoiceLine };
    }
    InvoiceLine__c saved = context.invoiceLine;
    Boolean isAll = rule.Aggregate__c == 'All';
    Boolean aggregated = isAll;
    for (InvoiceLine__c line : lines) {
      context.invoiceLine = line;
      Boolean hit = compareTenantRule(rule, context);
      if (isAll) {
        if (!hit) {
          aggregated = false;
          break;
        }
      } else if (hit) {
        aggregated = true;
        break;
      }
    }
    context.invoiceLine = saved;
    return aggregated;
  }

  private static Boolean compareTenantRule(
    GlConditionRule__c rule,
    Context context
  ) {
    Object left = readValue(context, rule.TargetObject__c, rule.TargetField__c);
    Object right = null;
    if (rule.CompareType__c == 'Field') {
      right = readValue(context, rule.CompareObject__c, rule.CompareField__c);
    } else if (
      rule.Operator__c != 'IsNull' &&
      rule.Operator__c != 'IsNotNull'
    ) {
      right = rule.CompareValue__c;
    }
    return compare(left, rule.Operator__c, right);
  }

  private static Boolean evaluateRule(
    FixedConditionRuleFixedCatalog.Definition rule,
    Context context
  ) {
    Object left = readValue(
      context,
      AccountingCatalogTypes.objectApiName(rule.targetObject),
      rule.targetField
    );
    Object right = null;
    if (rule.compareType == AccountingCatalogTypes.CompareType.Field) {
      right = readValue(
        context,
        AccountingCatalogTypes.objectApiName(rule.compareObject),
        rule.compareField
      );
    } else if (
      rule.operator != AccountingCatalogTypes.ConditionOperator.IsNull &&
      rule.operator != AccountingCatalogTypes.ConditionOperator.IsNotNull
    ) {
      right = rule.compareValue;
    }
    return compare(left, String.valueOf(rule.operator), right);
  }

  /** 仕様: Accounting 第4.7節。11種は Context の関連レコードから読む。経路は Goal が固定で持つ。 */
  private static Object readValue(
    Context context,
    String objectApiName,
    String fieldApiName
  ) {
    if (
      context == null ||
      String.isBlank(objectApiName) ||
      String.isBlank(fieldApiName)
    ) {
      return null;
    }
    SObject record;
    if (objectApiName == 'Invoice__c') {
      record = context.invoice;
    } else if (objectApiName == 'InvoiceLine__c') {
      record = context.invoiceLine;
    } else if (objectApiName == 'InvoicePayment__c') {
      record = context.invoicePayment;
    } else if (objectApiName == 'InvoicePaymentAllocation__c') {
      record = context.allocation;
    } else if (objectApiName == 'ContractProduct__c') {
      record = context.contractProduct;
    } else if (objectApiName == 'Product2') {
      record = context.product;
    } else if (objectApiName == 'ContractHistory__c') {
      record = context.contractHistory;
    } else if (objectApiName == 'ContractService__c') {
      record = context.contractService;
    } else if (objectApiName == 'Opportunity') {
      record = context.opportunity;
    } else if (objectApiName == 'BillingAccount__c') {
      record = context.billingAccount;
    } else if (objectApiName == 'Account') {
      record = context.account;
    }
    return record == null ? null : record.get(fieldApiName);
  }

  private static Boolean compare(
    Object left,
    String operatorName,
    Object right
  ) {
    if (operatorName == 'IsNull' || operatorName == '空である') {
      return left == null || String.valueOf(left) == '';
    }
    if (operatorName == 'IsNotNull' || operatorName == '空でない') {
      return left != null && String.valueOf(left) != '';
    }
    if (operatorName == 'Equals' || operatorName == '等しい') {
      return stringify(left) == stringify(right);
    }
    if (operatorName == 'NotEquals' || operatorName == '等しくない') {
      return stringify(left) != stringify(right);
    }
    Decimal leftNumber = toDecimal(left);
    Decimal rightNumber = toDecimal(right);
    if (leftNumber != null && rightNumber != null) {
      if (operatorName == 'GreaterThan' || operatorName == 'より大きい') {
        return leftNumber > rightNumber;
      }
      if (operatorName == 'GreaterOrEqual' || operatorName == '以上') {
        return leftNumber >= rightNumber;
      }
      if (operatorName == 'LessThan' || operatorName == 'より小さい') {
        return leftNumber < rightNumber;
      }
      if (operatorName == 'LessOrEqual' || operatorName == '以下') {
        return leftNumber <= rightNumber;
      }
    }
    Date leftDate = toDate(left);
    Date rightDate = toDate(right);
    if (leftDate != null && rightDate != null) {
      if (operatorName == 'GreaterThan' || operatorName == 'より大きい') {
        return leftDate > rightDate;
      }
      if (operatorName == 'GreaterOrEqual' || operatorName == '以上') {
        return leftDate >= rightDate;
      }
      if (operatorName == 'LessThan' || operatorName == 'より小さい') {
        return leftDate < rightDate;
      }
      if (operatorName == 'LessOrEqual' || operatorName == '以下') {
        return leftDate <= rightDate;
      }
    }
    String leftText = stringify(left);
    String rightText = stringify(right);
    if (operatorName == 'Contains' || operatorName == '含む') {
      return leftText != null &&
        rightText != null &&
        leftText.contains(rightText);
    }
    if (operatorName == 'NotContains' || operatorName == '含まない') {
      return leftText == null ||
        rightText == null ||
        !leftText.contains(rightText);
    }
    throw new EvaluationException('条件を評価できません: ' + operatorName);
  }

  /** 仕様: Accounting 第4.7節。選択リスト比較はラベルではなくAPI値。保存時にラベルをAPIへ直す。 */
  public static void normalizeFixedCompareValue(GlConditionRule__c rule) {
    if (
      rule == null ||
      rule.CompareType__c != 'FixedValue' ||
      String.isBlank(rule.CompareValue__c)
    ) {
      return;
    }
    Schema.DescribeFieldResult targetDescribe = describeField(
      rule.TargetObject__c,
      rule.TargetField__c
    );
    if (targetDescribe == null) {
      return;
    }
    Schema.DisplayType fieldType = targetDescribe.getType();
    if (
      fieldType != Schema.DisplayType.PICKLIST &&
      fieldType != Schema.DisplayType.MULTIPICKLIST
    ) {
      return;
    }
    Map<String, String> apiByToken = new Map<String, String>();
    for (Schema.PicklistEntry entry : targetDescribe.getPicklistValues()) {
      apiByToken.put(entry.getValue(), entry.getValue());
      if (String.isNotBlank(entry.getLabel())) {
        apiByToken.put(entry.getLabel(), entry.getValue());
      }
    }
    String resolved = apiByToken.get(rule.CompareValue__c.trim());
    if (resolved != null) {
      rule.CompareValue__c = resolved;
    }
  }

  /** 仕様: Accounting 第4.7節 */
  public static String validateRule(
    GlConditionRule__c rule,
    String evaluationContext
  ) {
    if (rule == null) {
      return '条件ルールがありません。';
    }
    Boolean isNullOp =
      rule.Operator__c == 'IsNull' ||
      rule.Operator__c == 'IsNotNull';
    if (isNullOp) {
      if (
        String.isNotBlank(rule.CompareType__c) ||
        String.isNotBlank(rule.CompareValue__c) ||
        String.isNotBlank(rule.CompareObject__c) ||
        String.isNotBlank(rule.CompareField__c)
      ) {
        return '空判定では比較関連項目を空にしてください。';
      }
    } else if (rule.CompareType__c == 'FixedValue') {
      if (String.isBlank(rule.CompareValue__c)) {
        return '固定値比較では比較値を指定してください。';
      }
      if (
        String.isNotBlank(rule.CompareObject__c) ||
        String.isNotBlank(rule.CompareField__c)
      ) {
        return '固定値比較では比較値だけを指定してください。';
      }
    } else if (rule.CompareType__c == 'Field') {
      if (
        String.isBlank(rule.CompareObject__c) ||
        String.isBlank(rule.CompareField__c)
      ) {
        return '項目比較では比較対象オブジェクトと比較対象項目を指定してください。';
      }
      if (String.isNotBlank(rule.CompareValue__c)) {
        return '項目比較では比較対象オブジェクトと比較対象項目だけを指定してください。';
      }
    } else if (!isNullOp) {
      return '比較種別を指定してください。';
    }
    Set<String> reachable = REACHABLE_OBJECTS.get(evaluationContext);
    if (reachable == null || !reachable.contains(rule.TargetObject__c)) {
      return '評価コンテキストから到達できません。';
    }
    if (
      rule.CompareType__c == 'Field' &&
      !reachable.contains(rule.CompareObject__c)
    ) {
      return '評価コンテキストから到達できません。';
    }
    if (
      evaluationContext == 'Invoice' &&
      rule.TargetObject__c == 'InvoiceLine__c' &&
      String.isBlank(rule.Aggregate__c)
    ) {
      return '子対象では集約が必要です。';
    }
    Schema.DescribeFieldResult targetDescribe = describeField(
      rule.TargetObject__c,
      rule.TargetField__c
    );
    if (targetDescribe == null) {
      return '対象項目がありません。';
    }
    if (!operatorMatchesType(rule.Operator__c, targetDescribe.getType())) {
      return '演算子と項目の型が一致しません。';
    }
    if (rule.CompareType__c == 'Field') {
      Schema.DescribeFieldResult compareDescribe = describeField(
        rule.CompareObject__c,
        rule.CompareField__c
      );
      if (compareDescribe == null) {
        return '比較対象項目がありません。';
      }
      if (!operatorMatchesType(rule.Operator__c, compareDescribe.getType())) {
        return '演算子と項目の型が一致しません。';
      }
    }
    return null;
  }

  /** 仕様: Accounting 第4.7節 */
  public static String validateConditionLogic(
    String logic,
    Set<Decimal> sequences
  ) {
    if (String.isBlank(logic)) {
      return null;
    }
    List<String> tokens = tokenizeLogic(logic);
    if (tokens == null) {
      return '条件ロジックの構文が不正です。';
    }
    Integer depth = 0;
    Map<Integer, Set<String>> junctionsByDepth = new Map<Integer, Set<String>>();
    Set<Decimal> used = sequences == null ? new Set<Decimal>() : sequences;
    for (String token : tokens) {
      if (token == '(') {
        depth++;
        continue;
      }
      if (token == ')') {
        depth--;
        if (depth < 0) {
          return '条件ロジックの括弧が対応していません。';
        }
        continue;
      }
      if (token == 'AND' || token == 'OR') {
        Set<String> junctions = junctionsByDepth.get(depth);
        if (junctions == null) {
          junctions = new Set<String>();
          junctionsByDepth.put(depth, junctions);
        }
        junctions.add(token);
        continue;
      }
      if (token == 'NOT') {
        continue;
      }
      Decimal sequence;
      try {
        sequence = Decimal.valueOf(token);
      } catch (Exception ex) {
        return '条件ロジックの構文が不正です。';
      }
      if (!used.contains(sequence)) {
        return '条件ロジックの番号がありません。';
      }
    }
    if (depth != 0) {
      return '条件ロジックの括弧が対応していません。';
    }
    for (Set<String> junctions : junctionsByDepth.values()) {
      if (junctions.contains('AND') && junctions.contains('OR')) {
        return 'ANDとORの混在時は括弧が必要です。';
      }
    }
    return null;
  }

  private static List<String> tokenizeLogic(String logic) {
    List<String> tokens = new List<String>();
    Integer index = 0;
    String source = logic.trim();
    while (index < source.length()) {
      String current = source.substring(index, index + 1);
      if (
        current == ' ' ||
        current == '\t' ||
        current == '\n' ||
        current == '\r'
      ) {
        index++;
        continue;
      }
      if (current == '(' || current == ')') {
        tokens.add(current);
        index++;
        continue;
      }
      if (current >= '0' && current <= '9') {
        Integer endIndex = index + 1;
        while (endIndex < source.length()) {
          String digit = source.substring(endIndex, endIndex + 1);
          if (digit < '0' || digit > '9') {
            break;
          }
          endIndex++;
        }
        tokens.add(source.substring(index, endIndex));
        index = endIndex;
        continue;
      }
      Integer endIndex = index + 1;
      while (endIndex < source.length()) {
        String letter = source.substring(endIndex, endIndex + 1);
        if (letter == ' ' || letter == '(' || letter == ')') {
          break;
        }
        endIndex++;
      }
      String word = source.substring(index, endIndex).toUpperCase();
      if (word != 'AND' && word != 'OR' && word != 'NOT') {
        return null;
      }
      tokens.add(word);
      index = endIndex;
    }
    return tokens;
  }

  /** 仕様: Accounting 第4.7節。保存済みの条件ロジックを評価する。 */
  private static Boolean evaluateConditionLogic(
    String logic,
    Map<Decimal, Boolean> bySequence
  ) {
    List<String> tokens = tokenizeLogic(logic);
    if (tokens == null || tokens.isEmpty()) {
      throw new EvaluationException('条件ロジックの構文が不正です。');
    }
    LogicCursor cursor = new LogicCursor();
    cursor.tokens = tokens;
    cursor.index = 0;
    cursor.bySequence = bySequence;
    Boolean value = parseLogicOr(cursor);
    if (cursor.index != cursor.tokens.size()) {
      throw new EvaluationException('条件ロジックの構文が不正です。');
    }
    return value;
  }

  private class LogicCursor {
    List<String> tokens;
    Integer index;
    Map<Decimal, Boolean> bySequence;
  }

  private static Boolean parseLogicOr(LogicCursor cursor) {
    Boolean value = parseLogicAnd(cursor);
    while (logicPeek(cursor) == 'OR') {
      cursor.index++;
      value = value || parseLogicAnd(cursor);
    }
    return value;
  }

  private static Boolean parseLogicAnd(LogicCursor cursor) {
    Boolean value = parseLogicNot(cursor);
    while (logicPeek(cursor) == 'AND') {
      cursor.index++;
      value = value && parseLogicNot(cursor);
    }
    return value;
  }

  private static Boolean parseLogicNot(LogicCursor cursor) {
    if (logicPeek(cursor) == 'NOT') {
      cursor.index++;
      return !parseLogicNot(cursor);
    }
    return parseLogicPrimary(cursor);
  }

  private static Boolean parseLogicPrimary(LogicCursor cursor) {
    String token = logicPeek(cursor);
    if (token == '(') {
      cursor.index++;
      Boolean value = parseLogicOr(cursor);
      if (logicPeek(cursor) != ')') {
        throw new EvaluationException('条件ロジックの括弧が対応していません。');
      }
      cursor.index++;
      return value;
    }
    if (String.isBlank(token)) {
      throw new EvaluationException('条件ロジックの構文が不正です。');
    }
    cursor.index++;
    Decimal sequence;
    try {
      sequence = Decimal.valueOf(token);
    } catch (Exception ex) {
      throw new EvaluationException('条件ロジックの構文が不正です。');
    }
    if (cursor.bySequence == null || !cursor.bySequence.containsKey(sequence)) {
      throw new EvaluationException('条件ロジックの番号がありません。');
    }
    return cursor.bySequence.get(sequence) == true;
  }

  private static String logicPeek(LogicCursor cursor) {
    if (
      cursor == null ||
      cursor.tokens == null ||
      cursor.index >= cursor.tokens.size()
    ) {
      return null;
    }
    return cursor.tokens[cursor.index];
  }

  /** 仕様: Accounting 第8.2節。条件の成否は変えない。同一処理の項目describeと全体describeは取り直さない。 */
  private static Schema.DescribeFieldResult describeField(
    String objectApiName,
    String fieldApiName
  ) {
    if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
      return null;
    }
    String cacheKey = objectApiName + '\n' + fieldApiName;
    if (cachedFieldDescribes != null && cachedFieldDescribes.containsKey(cacheKey)) {
      return cachedFieldDescribes.get(cacheKey);
    }
    if (cachedGlobalDescribe == null) {
      cachedGlobalDescribe = Schema.getGlobalDescribe();
    }
    Schema.SObjectType objectType = cachedGlobalDescribe.get(objectApiName);
    if (objectType == null) {
      return null;
    }
    if (cachedFieldsByObject == null) {
      cachedFieldsByObject = new Map<String, Map<String, Schema.SObjectField>>();
    }
    Map<String, Schema.SObjectField> fields = cachedFieldsByObject.get(
      objectApiName
    );
    if (fields == null) {
      fields = objectType.getDescribe().fields.getMap();
      cachedFieldsByObject.put(objectApiName, fields);
    }
    if (!fields.containsKey(fieldApiName)) {
      return null;
    }
    Schema.DescribeFieldResult described = fields.get(fieldApiName).getDescribe();
    if (cachedFieldDescribes == null) {
      cachedFieldDescribes = new Map<String, Schema.DescribeFieldResult>();
    }
    cachedFieldDescribes.put(cacheKey, described);
    return described;
  }

  private static Boolean operatorMatchesType(
    String operatorName,
    Schema.DisplayType fieldType
  ) {
    if (operatorName == 'IsNull' || operatorName == 'IsNotNull') {
      return true;
    }
    if (operatorName == 'Equals' || operatorName == 'NotEquals') {
      return true;
    }
    Boolean numeric =
      fieldType == Schema.DisplayType.DOUBLE ||
      fieldType == Schema.DisplayType.CURRENCY ||
      fieldType == Schema.DisplayType.PERCENT ||
      fieldType == Schema.DisplayType.INTEGER ||
      fieldType == Schema.DisplayType.LONG;
    Boolean dateLike =
      fieldType == Schema.DisplayType.DATE ||
      fieldType == Schema.DisplayType.DATETIME;
    Boolean textLike =
      fieldType == Schema.DisplayType.STRING ||
      fieldType == Schema.DisplayType.TEXTAREA ||
      fieldType == Schema.DisplayType.PICKLIST ||
      fieldType == Schema.DisplayType.MULTIPICKLIST ||
      fieldType == Schema.DisplayType.EMAIL ||
      fieldType == Schema.DisplayType.PHONE ||
      fieldType == Schema.DisplayType.URL;
    if (
      operatorName == 'GreaterThan' ||
      operatorName == 'GreaterOrEqual' ||
      operatorName == 'LessThan' ||
      operatorName == 'LessOrEqual'
    ) {
      return numeric || dateLike;
    }
    if (operatorName == 'Contains' || operatorName == 'NotContains') {
      return textLike;
    }
    return false;
  }

  private static String stringify(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static Decimal toDecimal(Object value) {
    if (value == null) {
      return null;
    }
    if (value instanceof Decimal) {
      return (Decimal) value;
    }
    try {
      return Decimal.valueOf(String.valueOf(value));
    } catch (Exception e) {
      return null;
    }
  }

  private static Date toDate(Object value) {
    if (value instanceof Date) {
      return (Date) value;
    }
    return null;
  }
}
