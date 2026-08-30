public with sharing class FixedConditionRuleFixedCatalog {
  public class Definition {
    public final String key;
    public final FixedConditionSetFixedCatalog.Definition conditionSet;
    public final Integer sequence;
    public final AccountingCatalogTypes.AggregateType aggregate;
    public final AccountingCatalogTypes.ConditionObject targetObject;
    public final String targetField;
    public final AccountingCatalogTypes.ConditionOperator operator;
    public final AccountingCatalogTypes.CompareType compareType;
    public final String compareValue;
    public final AccountingCatalogTypes.ConditionObject compareObject;
    public final String compareField;
    public final String description;

    private Definition(
      FixedConditionSetFixedCatalog.Definition conditionSet,
      Integer sequence,
      AccountingCatalogTypes.ConditionObject targetObject,
      String targetField,
      AccountingCatalogTypes.ConditionOperator operator,
      AccountingCatalogTypes.CompareType compareType,
      String compareValue,
      AccountingCatalogTypes.ConditionObject compareObject,
      String compareField
    ) {
      this.key = conditionSet.key + '_' + String.valueOf(sequence);
      this.conditionSet = conditionSet;
      this.sequence = sequence;
      this.aggregate = null;
      this.targetObject = targetObject;
      this.targetField = targetField;
      this.operator = operator;
      this.compareType = compareType;
      this.compareValue = compareValue;
      this.compareObject = compareObject;
      this.compareField = compareField;
      this.description = null;
    }
  }

  public static final Definition PAY_INVOICE_CURRENT_1 = fixedValue(
    FixedConditionSetFixedCatalog.PAY_INVOICE_CURRENT,
    1,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'PaymentPurpose__c',
    AccountingCatalogTypes.ConditionOperator.Equals,
    'Invoice'
  );
  public static final Definition PAY_INVOICE_CURRENT_2 = fieldCompare(
    FixedConditionSetFixedCatalog.PAY_INVOICE_CURRENT,
    2,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'PaymentDate__c',
    AccountingCatalogTypes.ConditionOperator.GreaterOrEqual,
    AccountingCatalogTypes.ConditionObject.Invoice,
    'InvoiceDate__c'
  );
  public static final Definition PAY_NON_INVOICE_POSITIVE_1 = fixedValue(
    FixedConditionSetFixedCatalog.PAY_NON_INVOICE_POSITIVE,
    1,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'PaymentPurpose__c',
    AccountingCatalogTypes.ConditionOperator.Equals,
    'NonInvoice'
  );
  public static final Definition PAY_NON_INVOICE_POSITIVE_2 = fixedValue(
    FixedConditionSetFixedCatalog.PAY_NON_INVOICE_POSITIVE,
    2,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'Amount__c',
    AccountingCatalogTypes.ConditionOperator.GreaterThan,
    '0'
  );
  public static final Definition PAY_NON_INVOICE_NEGATIVE_1 = fixedValue(
    FixedConditionSetFixedCatalog.PAY_NON_INVOICE_NEGATIVE,
    1,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'PaymentPurpose__c',
    AccountingCatalogTypes.ConditionOperator.Equals,
    'NonInvoice'
  );
  public static final Definition PAY_NON_INVOICE_NEGATIVE_2 = fixedValue(
    FixedConditionSetFixedCatalog.PAY_NON_INVOICE_NEGATIVE,
    2,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'Amount__c',
    AccountingCatalogTypes.ConditionOperator.LessThan,
    '0'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_POSITIVE_CASH_1 = fixedValue(
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_POSITIVE_CASH,
    1,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'PaymentPurpose__c',
    AccountingCatalogTypes.ConditionOperator.Equals,
    'Invoice'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_POSITIVE_CASH_2 = fieldCompare(
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_POSITIVE_CASH,
    2,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'PaymentDate__c',
    AccountingCatalogTypes.ConditionOperator.LessThan,
    AccountingCatalogTypes.ConditionObject.Invoice,
    'InvoiceDate__c'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_POSITIVE_CASH_3 = fixedValue(
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_POSITIVE_CASH,
    3,
    AccountingCatalogTypes.ConditionObject.InvoicePaymentAllocation,
    'Amount__c',
    AccountingCatalogTypes.ConditionOperator.GreaterThan,
    '0'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_NEGATIVE_CASH_1 = fixedValue(
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_NEGATIVE_CASH,
    1,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'PaymentPurpose__c',
    AccountingCatalogTypes.ConditionOperator.Equals,
    'Invoice'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_NEGATIVE_CASH_2 = fieldCompare(
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_NEGATIVE_CASH,
    2,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'PaymentDate__c',
    AccountingCatalogTypes.ConditionOperator.LessThan,
    AccountingCatalogTypes.ConditionObject.Invoice,
    'InvoiceDate__c'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_NEGATIVE_CASH_3 = fixedValue(
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_NEGATIVE_CASH,
    3,
    AccountingCatalogTypes.ConditionObject.InvoicePaymentAllocation,
    'Amount__c',
    AccountingCatalogTypes.ConditionOperator.LessThan,
    '0'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_UAC_TRANSFER_1 = fixedValue(
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_UAC_TRANSFER,
    1,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'PaymentPurpose__c',
    AccountingCatalogTypes.ConditionOperator.Equals,
    'Invoice'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_UAC_TRANSFER_2 = fieldCompare(
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_UAC_TRANSFER,
    2,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'PaymentDate__c',
    AccountingCatalogTypes.ConditionOperator.LessThan,
    AccountingCatalogTypes.ConditionObject.Invoice,
    'InvoiceDate__c'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_SP_TRANSFER_1 = fixedValue(
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_SP_TRANSFER,
    1,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'PaymentPurpose__c',
    AccountingCatalogTypes.ConditionOperator.Equals,
    'Invoice'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_SP_TRANSFER_2 = fieldCompare(
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_SP_TRANSFER,
    2,
    AccountingCatalogTypes.ConditionObject.InvoicePayment,
    'PaymentDate__c',
    AccountingCatalogTypes.ConditionOperator.LessThan,
    AccountingCatalogTypes.ConditionObject.Invoice,
    'InvoiceDate__c'
  );
  private static Definition fixedValue(
    FixedConditionSetFixedCatalog.Definition conditionSet,
    Integer sequence,
    AccountingCatalogTypes.ConditionObject targetObject,
    String targetField,
    AccountingCatalogTypes.ConditionOperator operator,
    String compareValue
  ) {
    return new Definition(
      conditionSet,
      sequence,
      targetObject,
      targetField,
      operator,
      AccountingCatalogTypes.CompareType.FixedValue,
      compareValue,
      null,
      null
    );
  }

  private static Definition fieldCompare(
    FixedConditionSetFixedCatalog.Definition conditionSet,
    Integer sequence,
    AccountingCatalogTypes.ConditionObject targetObject,
    String targetField,
    AccountingCatalogTypes.ConditionOperator operator,
    AccountingCatalogTypes.ConditionObject compareObject,
    String compareField
  ) {
    return new Definition(
      conditionSet,
      sequence,
      targetObject,
      targetField,
      operator,
      AccountingCatalogTypes.CompareType.Field,
      null,
      compareObject,
      compareField
    );
  }

  private static final Map<String, Definition> BY_KEY = new Map<String, Definition>{
    PAY_INVOICE_CURRENT_1.key => PAY_INVOICE_CURRENT_1,
    PAY_INVOICE_CURRENT_2.key => PAY_INVOICE_CURRENT_2,
    PAY_NON_INVOICE_POSITIVE_1.key => PAY_NON_INVOICE_POSITIVE_1,
    PAY_NON_INVOICE_POSITIVE_2.key => PAY_NON_INVOICE_POSITIVE_2,
    PAY_NON_INVOICE_NEGATIVE_1.key => PAY_NON_INVOICE_NEGATIVE_1,
    PAY_NON_INVOICE_NEGATIVE_2.key => PAY_NON_INVOICE_NEGATIVE_2,
    PAY_INVOICE_HISTORICAL_POSITIVE_CASH_1.key => PAY_INVOICE_HISTORICAL_POSITIVE_CASH_1,
    PAY_INVOICE_HISTORICAL_POSITIVE_CASH_2.key => PAY_INVOICE_HISTORICAL_POSITIVE_CASH_2,
    PAY_INVOICE_HISTORICAL_POSITIVE_CASH_3.key => PAY_INVOICE_HISTORICAL_POSITIVE_CASH_3,
    PAY_INVOICE_HISTORICAL_NEGATIVE_CASH_1.key => PAY_INVOICE_HISTORICAL_NEGATIVE_CASH_1,
    PAY_INVOICE_HISTORICAL_NEGATIVE_CASH_2.key => PAY_INVOICE_HISTORICAL_NEGATIVE_CASH_2,
    PAY_INVOICE_HISTORICAL_NEGATIVE_CASH_3.key => PAY_INVOICE_HISTORICAL_NEGATIVE_CASH_3,
    PAY_INVOICE_HISTORICAL_UAC_TRANSFER_1.key => PAY_INVOICE_HISTORICAL_UAC_TRANSFER_1,
    PAY_INVOICE_HISTORICAL_UAC_TRANSFER_2.key => PAY_INVOICE_HISTORICAL_UAC_TRANSFER_2,
    PAY_INVOICE_HISTORICAL_SP_TRANSFER_1.key => PAY_INVOICE_HISTORICAL_SP_TRANSFER_1,
    PAY_INVOICE_HISTORICAL_SP_TRANSFER_2.key => PAY_INVOICE_HISTORICAL_SP_TRANSFER_2
  };

  /** 仕様: Accounting 第4.7節 */
  public static Definition require(String key) {
    Definition found = BY_KEY.get(key);
    if (found == null) {
      throw new AccountingCatalogTypes.UnknownKeyException(
        '固定条件ルールキーがCatalogにありません: ' + key
      );
    }
    return found;
  }

  /** 仕様: Accounting 第4.7節 */
  public static List<Definition> values() {
    return new List<Definition>{
      PAY_INVOICE_CURRENT_1,
      PAY_INVOICE_CURRENT_2,
      PAY_NON_INVOICE_POSITIVE_1,
      PAY_NON_INVOICE_POSITIVE_2,
      PAY_NON_INVOICE_NEGATIVE_1,
      PAY_NON_INVOICE_NEGATIVE_2,
      PAY_INVOICE_HISTORICAL_POSITIVE_CASH_1,
      PAY_INVOICE_HISTORICAL_POSITIVE_CASH_2,
      PAY_INVOICE_HISTORICAL_POSITIVE_CASH_3,
      PAY_INVOICE_HISTORICAL_NEGATIVE_CASH_1,
      PAY_INVOICE_HISTORICAL_NEGATIVE_CASH_2,
      PAY_INVOICE_HISTORICAL_NEGATIVE_CASH_3,
      PAY_INVOICE_HISTORICAL_UAC_TRANSFER_1,
      PAY_INVOICE_HISTORICAL_UAC_TRANSFER_2,
      PAY_INVOICE_HISTORICAL_SP_TRANSFER_1,
      PAY_INVOICE_HISTORICAL_SP_TRANSFER_2
    };
  }
}
