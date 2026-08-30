public without sharing class ConditionEvaluationService {
  public class EvaluationException extends Exception {
  }

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
    public InvoicePayment__c invoicePayment;
    public InvoicePaymentAllocation__c allocation;
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
    for (FixedConditionRuleFixedCatalog.Definition rule : FixedConditionRuleFixedCatalog.values()) {
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

  /** 仕様: Accounting 第4.7節、第6章 */
  public static Boolean evaluateTenant(Id conditionSetId, Context context) {
    if (conditionSetId == null) {
      return true;
    }
    List<GlConditionRule__c> rules = [
      SELECT
        TargetObject__c,
        TargetField__c,
        Operator__c,
        CompareType__c,
        CompareValue__c,
        CompareObject__c,
        CompareField__c
      FROM GlConditionRule__c
      WHERE ConditionSet__c = :conditionSetId
      WITH SYSTEM_MODE
      ORDER BY Sequence__c
    ];
    if (rules.isEmpty()) {
      throw new EvaluationException('条件が0件の条件セットは参照できません。');
    }
    for (GlConditionRule__c rule : rules) {
      Object left = readValue(context, rule.TargetObject__c, rule.TargetField__c);
      Object right = null;
      if (rule.CompareType__c == 'Field') {
        right = readValue(context, rule.CompareObject__c, rule.CompareField__c);
      } else if (rule.Operator__c != 'IsNull' && rule.Operator__c != 'IsNotNull') {
        right = rule.CompareValue__c;
      }
      if (!compare(left, rule.Operator__c, right)) {
        return false;
      }
    }
    return true;
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

  private static Object readValue(Context context, String objectApiName, String fieldApiName) {
    if (context == null || String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
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
    }
    return record == null ? null : record.get(fieldApiName);
  }

  private static Boolean compare(Object left, String operatorName, Object right) {
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
      return leftText != null && rightText != null && leftText.contains(rightText);
    }
    if (operatorName == 'NotContains' || operatorName == '含まない') {
      return leftText == null || rightText == null || !leftText.contains(rightText);
    }
    throw new EvaluationException('条件を評価できません: ' + operatorName);
  }

  /** 仕様: Accounting 第4.7節 */
  public static String validateRule(
    GlConditionRule__c rule,
    String evaluationContext
  ) {
    if (rule == null) {
      return '条件ルールがありません。';
    }
    Boolean isNullOp = rule.Operator__c == 'IsNull' || rule.Operator__c == 'IsNotNull';
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
      if (String.isNotBlank(rule.CompareObject__c) || String.isNotBlank(rule.CompareField__c)) {
        return '固定値比較では比較値だけを指定してください。';
      }
    } else if (rule.CompareType__c == 'Field') {
      if (String.isBlank(rule.CompareObject__c) || String.isBlank(rule.CompareField__c)) {
        return '項目比較では比較対象オブジェクトと比較対象項目を指定してください。';
      }
      if (String.isNotBlank(rule.CompareValue__c)) {
        return '項目比較では比較対象オブジェクトと比較対象項目だけを指定してください。';
      }
    } else if (!isNullOp) {
      return '比較種別を指定してください。';
    }
    Set<String> reachable = REACHABLE_OBJECTS.get(evaluationContext);
    if (
      reachable == null ||
      !reachable.contains(rule.TargetObject__c)
    ) {
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
  public static String validateConditionLogic(String logic, Set<Decimal> sequences) {
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
      if (current == ' ' || current == '\t' || current == '\n' || current == '\r') {
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

  private static Schema.DescribeFieldResult describeField(
    String objectApiName,
    String fieldApiName
  ) {
    if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
      return null;
    }
    Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
    if (objectType == null) {
      return null;
    }
    Map<String, Schema.SObjectField> fields = objectType.getDescribe().fields.getMap();
    if (!fields.containsKey(fieldApiName)) {
      return null;
    }
    return fields.get(fieldApiName).getDescribe();
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
