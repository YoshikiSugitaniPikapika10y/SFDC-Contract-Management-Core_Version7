public with sharing class SlotPriorityRuleFixedCatalog {
  public class Definition {
    public final String name;
    public final String key;
    public final AccountingCatalogTypes.SlotPriorityType priorityType;
    public final AccountingSlotFixedCatalog.Definition sourceSlot;
    public final AccountingSlotFixedCatalog.Definition targetSlot;
    public final Integer priority;
    public final String description;

    private Definition(
      String name,
      String key,
      AccountingCatalogTypes.SlotPriorityType priorityType,
      AccountingSlotFixedCatalog.Definition sourceSlot,
      AccountingSlotFixedCatalog.Definition targetSlot,
      Integer priority,
      String description
    ) {
      this.name = name;
      this.key = key;
      this.priorityType = priorityType;
      this.sourceSlot = sourceSlot;
      this.targetSlot = targetSlot;
      this.priority = priority;
      this.description = description;
    }
  }

  public static final Definition BILLING_BASIS_INVOICE_CTA = rule(
    '請求基準・請求確定',
    'BILLING_BASIS_INVOICE_CTA',
    AccountingCatalogTypes.SlotPriorityType.BillingBasisInvoiceAllocation,
    AccountingSlotFixedCatalog.AccountsReceivable,
    AccountingSlotFixedCatalog.ContractAsset,
    1
  );
  public static final Definition BILLING_BASIS_INVOICE_DEF = rule(
    '請求基準・請求確定',
    'BILLING_BASIS_INVOICE_DEF',
    AccountingCatalogTypes.SlotPriorityType.BillingBasisInvoiceAllocation,
    AccountingSlotFixedCatalog.AccountsReceivable,
    AccountingSlotFixedCatalog.DeferredRevenue,
    2
  );
  public static final Definition BILLING_BASIS_REVENUE_DEF = rule(
    '請求基準・売上本体',
    'BILLING_BASIS_REVENUE_DEF',
    AccountingCatalogTypes.SlotPriorityType.BillingBasisRecognitionAllocation,
    AccountingSlotFixedCatalog.Revenue,
    AccountingSlotFixedCatalog.DeferredRevenue,
    1
  );
  public static final Definition BILLING_BASIS_REVENUE_CTA = rule(
    '請求基準・売上本体',
    'BILLING_BASIS_REVENUE_CTA',
    AccountingCatalogTypes.SlotPriorityType.BillingBasisRecognitionAllocation,
    AccountingSlotFixedCatalog.Revenue,
    AccountingSlotFixedCatalog.ContractAsset,
    2
  );
  public static final Definition BILLING_BASIS_TAX_DEF = rule(
    '請求基準・税計上',
    'BILLING_BASIS_TAX_DEF',
    AccountingCatalogTypes.SlotPriorityType.BillingBasisRecognitionAllocation,
    AccountingSlotFixedCatalog.TaxPayable,
    AccountingSlotFixedCatalog.DeferredRevenue,
    1
  );
  public static final Definition BILLING_BASIS_TAX_CTA = rule(
    '請求基準・税計上',
    'BILLING_BASIS_TAX_CTA',
    AccountingCatalogTypes.SlotPriorityType.BillingBasisRecognitionAllocation,
    AccountingSlotFixedCatalog.TaxPayable,
    AccountingSlotFixedCatalog.ContractAsset,
    2
  );
  public static final Definition CASH_BASIS_REVENUE_DEF = rule(
    '入金連動前受基準・売上本体',
    'CASH_BASIS_REVENUE_DEF',
    AccountingCatalogTypes.SlotPriorityType.CashBasisRecognitionAllocation,
    AccountingSlotFixedCatalog.Revenue,
    AccountingSlotFixedCatalog.DeferredRevenue,
    1
  );
  public static final Definition CASH_BASIS_REVENUE_AR = rule(
    '入金連動前受基準・売上本体',
    'CASH_BASIS_REVENUE_AR',
    AccountingCatalogTypes.SlotPriorityType.CashBasisRecognitionAllocation,
    AccountingSlotFixedCatalog.Revenue,
    AccountingSlotFixedCatalog.AccountsReceivable,
    2
  );
  public static final Definition CASH_BASIS_REVENUE_CTA = rule(
    '入金連動前受基準・売上本体',
    'CASH_BASIS_REVENUE_CTA',
    AccountingCatalogTypes.SlotPriorityType.CashBasisRecognitionAllocation,
    AccountingSlotFixedCatalog.Revenue,
    AccountingSlotFixedCatalog.ContractAsset,
    3
  );
  public static final Definition CASH_BASIS_TAX_DEF = rule(
    '入金連動前受基準・税計上',
    'CASH_BASIS_TAX_DEF',
    AccountingCatalogTypes.SlotPriorityType.CashBasisRecognitionAllocation,
    AccountingSlotFixedCatalog.TaxPayable,
    AccountingSlotFixedCatalog.DeferredRevenue,
    1
  );
  public static final Definition CASH_BASIS_TAX_AR = rule(
    '入金連動前受基準・税計上',
    'CASH_BASIS_TAX_AR',
    AccountingCatalogTypes.SlotPriorityType.CashBasisRecognitionAllocation,
    AccountingSlotFixedCatalog.TaxPayable,
    AccountingSlotFixedCatalog.AccountsReceivable,
    2
  );
  public static final Definition CASH_BASIS_TAX_CTA = rule(
    '入金連動前受基準・税計上',
    'CASH_BASIS_TAX_CTA',
    AccountingCatalogTypes.SlotPriorityType.CashBasisRecognitionAllocation,
    AccountingSlotFixedCatalog.TaxPayable,
    AccountingSlotFixedCatalog.ContractAsset,
    3
  );
  public static final Definition INVOICE_SETTLEMENT_ALLOCATION_AR = rule(
    'Invoice決済充当',
    'INVOICE_SETTLEMENT_ALLOCATION_AR',
    AccountingCatalogTypes.SlotPriorityType.InvoiceSettlementAllocation,
    AccountingSlotFixedCatalog.Cash,
    AccountingSlotFixedCatalog.AccountsReceivable,
    1
  );
  public static final Definition INVOICE_SETTLEMENT_ALLOCATION_DEF = rule(
    'Invoice決済充当',
    'INVOICE_SETTLEMENT_ALLOCATION_DEF',
    AccountingCatalogTypes.SlotPriorityType.InvoiceSettlementAllocation,
    AccountingSlotFixedCatalog.Cash,
    AccountingSlotFixedCatalog.DeferredRevenue,
    2
  );
  public static final Definition HISTORICAL_UAC_TRANSFER_AR = rule(
    '過去日Invoice UAC振替',
    'HISTORICAL_UAC_TRANSFER_AR',
    AccountingCatalogTypes.SlotPriorityType.HistoricalUacTransfer,
    AccountingSlotFixedCatalog.UnappliedCash,
    AccountingSlotFixedCatalog.AccountsReceivable,
    1
  );
  public static final Definition HISTORICAL_UAC_TRANSFER_DEF = rule(
    '過去日Invoice UAC振替',
    'HISTORICAL_UAC_TRANSFER_DEF',
    AccountingCatalogTypes.SlotPriorityType.HistoricalUacTransfer,
    AccountingSlotFixedCatalog.UnappliedCash,
    AccountingSlotFixedCatalog.DeferredRevenue,
    2
  );
  public static final Definition POSITIVE_CASH_TEMPORARY_SP = rule(
    '正額現預金の仮残高充当',
    'POSITIVE_CASH_TEMPORARY_SP',
    AccountingCatalogTypes.SlotPriorityType.PositiveCashTemporaryAllocation,
    AccountingSlotFixedCatalog.Cash,
    AccountingSlotFixedCatalog.SuspensePayment,
    1
  );
  public static final Definition POSITIVE_CASH_TEMPORARY_UAC = rule(
    '正額現預金の仮残高充当',
    'POSITIVE_CASH_TEMPORARY_UAC',
    AccountingCatalogTypes.SlotPriorityType.PositiveCashTemporaryAllocation,
    AccountingSlotFixedCatalog.Cash,
    AccountingSlotFixedCatalog.UnappliedCash,
    2
  );
  public static final Definition NEGATIVE_CASH_TEMPORARY_UAC = rule(
    '負額現預金の仮残高充当',
    'NEGATIVE_CASH_TEMPORARY_UAC',
    AccountingCatalogTypes.SlotPriorityType.NegativeCashTemporaryAllocation,
    AccountingSlotFixedCatalog.Cash,
    AccountingSlotFixedCatalog.UnappliedCash,
    1
  );
  public static final Definition NEGATIVE_CASH_TEMPORARY_SP = rule(
    '負額現預金の仮残高充当',
    'NEGATIVE_CASH_TEMPORARY_SP',
    AccountingCatalogTypes.SlotPriorityType.NegativeCashTemporaryAllocation,
    AccountingSlotFixedCatalog.Cash,
    AccountingSlotFixedCatalog.SuspensePayment,
    2
  );
  public static final Definition HISTORICAL_SP_TRANSFER_AR = rule(
    '過去日Invoice SP振替',
    'HISTORICAL_SP_TRANSFER_AR',
    AccountingCatalogTypes.SlotPriorityType.HistoricalSpTransfer,
    AccountingSlotFixedCatalog.SuspensePayment,
    AccountingSlotFixedCatalog.AccountsReceivable,
    1
  );
  public static final Definition HISTORICAL_SP_TRANSFER_DEF = rule(
    '過去日Invoice SP振替',
    'HISTORICAL_SP_TRANSFER_DEF',
    AccountingCatalogTypes.SlotPriorityType.HistoricalSpTransfer,
    AccountingSlotFixedCatalog.SuspensePayment,
    AccountingSlotFixedCatalog.DeferredRevenue,
    2
  );

  private static Definition rule(
    String name,
    String key,
    AccountingCatalogTypes.SlotPriorityType priorityType,
    AccountingSlotFixedCatalog.Definition sourceSlot,
    AccountingSlotFixedCatalog.Definition targetSlot,
    Integer priority
  ) {
    return new Definition(
      name,
      key,
      priorityType,
      sourceSlot,
      targetSlot,
      priority,
      '起点 ' +
        sourceSlot.abbreviation +
        ' / 相手 ' +
        targetSlot.abbreviation +
        ' / 優先順位 ' +
        String.valueOf(priority)
    );
  }

  private static final Map<String, Definition> BY_KEY = new Map<String, Definition>{
    BILLING_BASIS_INVOICE_CTA.key => BILLING_BASIS_INVOICE_CTA,
    BILLING_BASIS_INVOICE_DEF.key => BILLING_BASIS_INVOICE_DEF,
    BILLING_BASIS_REVENUE_DEF.key => BILLING_BASIS_REVENUE_DEF,
    BILLING_BASIS_REVENUE_CTA.key => BILLING_BASIS_REVENUE_CTA,
    BILLING_BASIS_TAX_DEF.key => BILLING_BASIS_TAX_DEF,
    BILLING_BASIS_TAX_CTA.key => BILLING_BASIS_TAX_CTA,
    CASH_BASIS_REVENUE_DEF.key => CASH_BASIS_REVENUE_DEF,
    CASH_BASIS_REVENUE_AR.key => CASH_BASIS_REVENUE_AR,
    CASH_BASIS_REVENUE_CTA.key => CASH_BASIS_REVENUE_CTA,
    CASH_BASIS_TAX_DEF.key => CASH_BASIS_TAX_DEF,
    CASH_BASIS_TAX_AR.key => CASH_BASIS_TAX_AR,
    CASH_BASIS_TAX_CTA.key => CASH_BASIS_TAX_CTA,
    INVOICE_SETTLEMENT_ALLOCATION_AR.key => INVOICE_SETTLEMENT_ALLOCATION_AR,
    INVOICE_SETTLEMENT_ALLOCATION_DEF.key => INVOICE_SETTLEMENT_ALLOCATION_DEF,
    HISTORICAL_UAC_TRANSFER_AR.key => HISTORICAL_UAC_TRANSFER_AR,
    HISTORICAL_UAC_TRANSFER_DEF.key => HISTORICAL_UAC_TRANSFER_DEF,
    POSITIVE_CASH_TEMPORARY_SP.key => POSITIVE_CASH_TEMPORARY_SP,
    POSITIVE_CASH_TEMPORARY_UAC.key => POSITIVE_CASH_TEMPORARY_UAC,
    NEGATIVE_CASH_TEMPORARY_UAC.key => NEGATIVE_CASH_TEMPORARY_UAC,
    NEGATIVE_CASH_TEMPORARY_SP.key => NEGATIVE_CASH_TEMPORARY_SP,
    HISTORICAL_SP_TRANSFER_AR.key => HISTORICAL_SP_TRANSFER_AR,
    HISTORICAL_SP_TRANSFER_DEF.key => HISTORICAL_SP_TRANSFER_DEF
  };

  /** 仕様: Accounting 第4.6節 */
  public static Definition require(String key) {
    Definition found = BY_KEY.get(key);
    if (found == null) {
      throw new AccountingCatalogTypes.UnknownKeyException(
        'スロット優先ルールキーがCatalogにありません: ' + key
      );
    }
    return found;
  }

  /** 仕様: Accounting 第4.6節 */
  public static List<Definition> values() {
    return new List<Definition>{
      BILLING_BASIS_INVOICE_CTA,
      BILLING_BASIS_INVOICE_DEF,
      BILLING_BASIS_REVENUE_DEF,
      BILLING_BASIS_REVENUE_CTA,
      BILLING_BASIS_TAX_DEF,
      BILLING_BASIS_TAX_CTA,
      CASH_BASIS_REVENUE_DEF,
      CASH_BASIS_REVENUE_AR,
      CASH_BASIS_REVENUE_CTA,
      CASH_BASIS_TAX_DEF,
      CASH_BASIS_TAX_AR,
      CASH_BASIS_TAX_CTA,
      INVOICE_SETTLEMENT_ALLOCATION_AR,
      INVOICE_SETTLEMENT_ALLOCATION_DEF,
      HISTORICAL_UAC_TRANSFER_AR,
      HISTORICAL_UAC_TRANSFER_DEF,
      POSITIVE_CASH_TEMPORARY_SP,
      POSITIVE_CASH_TEMPORARY_UAC,
      NEGATIVE_CASH_TEMPORARY_UAC,
      NEGATIVE_CASH_TEMPORARY_SP,
      HISTORICAL_SP_TRANSFER_AR,
      HISTORICAL_SP_TRANSFER_DEF
    };
  }
}
