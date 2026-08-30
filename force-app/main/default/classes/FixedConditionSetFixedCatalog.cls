public with sharing class FixedConditionSetFixedCatalog {
  public class Definition {
    public final String name;
    public final String key;
    public final AccountingCatalogTypes.EvaluationContext evaluationContext;
    public final String conditionLogic;
    public final String description;

    private Definition(
      String name,
      String key,
      AccountingCatalogTypes.EvaluationContext evaluationContext,
      String conditionLogic,
      String description
    ) {
      this.name = name;
      this.key = key;
      this.evaluationContext = evaluationContext;
      this.conditionLogic = conditionLogic;
      this.description = description;
    }
  }

  public static final Definition PAY_INVOICE_CURRENT = new Definition(
    '通常日Invoice',
    'PAY_INVOICE_CURRENT',
    AccountingCatalogTypes.EvaluationContext.InvoicePaymentAllocation,
    null,
    'Purpose=Invoice、入出金日が請求日以後'
  );
  public static final Definition PAY_NON_INVOICE_POSITIVE = new Definition(
    'NonInvoice正額',
    'PAY_NON_INVOICE_POSITIVE',
    AccountingCatalogTypes.EvaluationContext.InvoicePayment,
    null,
    'Purpose=NonInvoice、Amount>0'
  );
  public static final Definition PAY_NON_INVOICE_NEGATIVE = new Definition(
    'NonInvoice負額',
    'PAY_NON_INVOICE_NEGATIVE',
    AccountingCatalogTypes.EvaluationContext.InvoicePayment,
    null,
    'Purpose=NonInvoice、Amount<0'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_POSITIVE_CASH = new Definition(
    '過去日Invoice正額現預金',
    'PAY_INVOICE_HISTORICAL_POSITIVE_CASH',
    AccountingCatalogTypes.EvaluationContext.InvoicePaymentAllocation,
    null,
    'Purpose=Invoice、入出金日が請求日より前、明細別割当額>0'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_NEGATIVE_CASH = new Definition(
    '過去日Invoice負額現預金',
    'PAY_INVOICE_HISTORICAL_NEGATIVE_CASH',
    AccountingCatalogTypes.EvaluationContext.InvoicePaymentAllocation,
    null,
    'Purpose=Invoice、入出金日が請求日より前、明細別割当額<0'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_UAC_TRANSFER = new Definition(
    '過去日Invoice UAC振替',
    'PAY_INVOICE_HISTORICAL_UAC_TRANSFER',
    AccountingCatalogTypes.EvaluationContext.InvoicePaymentAllocation,
    null,
    'Purpose=Invoice、入出金日が請求日より前'
  );
  public static final Definition PAY_INVOICE_HISTORICAL_SP_TRANSFER = new Definition(
    '過去日Invoice SP振替',
    'PAY_INVOICE_HISTORICAL_SP_TRANSFER',
    AccountingCatalogTypes.EvaluationContext.InvoicePaymentAllocation,
    null,
    'Purpose=Invoice、入出金日が請求日より前'
  );

  private static final Map<String, Definition> BY_KEY = new Map<String, Definition>{
    PAY_INVOICE_CURRENT.key => PAY_INVOICE_CURRENT,
    PAY_NON_INVOICE_POSITIVE.key => PAY_NON_INVOICE_POSITIVE,
    PAY_NON_INVOICE_NEGATIVE.key => PAY_NON_INVOICE_NEGATIVE,
    PAY_INVOICE_HISTORICAL_POSITIVE_CASH.key => PAY_INVOICE_HISTORICAL_POSITIVE_CASH,
    PAY_INVOICE_HISTORICAL_NEGATIVE_CASH.key => PAY_INVOICE_HISTORICAL_NEGATIVE_CASH,
    PAY_INVOICE_HISTORICAL_UAC_TRANSFER.key => PAY_INVOICE_HISTORICAL_UAC_TRANSFER,
    PAY_INVOICE_HISTORICAL_SP_TRANSFER.key => PAY_INVOICE_HISTORICAL_SP_TRANSFER
  };

  /** 仕様: Accounting 第4.7節 */
  public static Definition require(String key) {
    Definition found = BY_KEY.get(key);
    if (found == null) {
      throw new AccountingCatalogTypes.UnknownKeyException(
        '固定条件セットキーがCatalogにありません: ' + key
      );
    }
    return found;
  }

  /** 仕様: Accounting 第4.7節 */
  public static List<Definition> values() {
    return new List<Definition>{
      PAY_INVOICE_CURRENT,
      PAY_NON_INVOICE_POSITIVE,
      PAY_NON_INVOICE_NEGATIVE,
      PAY_INVOICE_HISTORICAL_POSITIVE_CASH,
      PAY_INVOICE_HISTORICAL_NEGATIVE_CASH,
      PAY_INVOICE_HISTORICAL_UAC_TRANSFER,
      PAY_INVOICE_HISTORICAL_SP_TRANSFER
    };
  }
}
