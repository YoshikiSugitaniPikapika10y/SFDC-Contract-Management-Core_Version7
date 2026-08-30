public with sharing class JournalPatternFixedCatalog {
  public class Definition {
    public final String name;
    public final String key;
    public final AccountingCatalogTypes.JournalCandidateRole candidateRole;
    public final AccountingEventFixedCatalog.Definition event;
    public final JournalPostingDateFixedCatalog.Definition postingDateItem;
    public final AccountingSlotFixedCatalog.Definition debitSlot;
    public final AccountingSlotFixedCatalog.Definition creditSlot;
    public final JournalAmountItemFixedCatalog.Definition amountItem;
    public final AccountingCatalogTypes.SlotPriorityType slotPriorityType;
    public final AccountingCatalogTypes.ExclusiveGroup exclusiveGroup;
    public final Integer sortOrder;
    public final Integer sameDayOrder;
    public final FixedConditionSetFixedCatalog.Definition conditionSet;
    public final String description;

    private Definition(
      String name,
      String key,
      AccountingCatalogTypes.JournalCandidateRole candidateRole,
      AccountingEventFixedCatalog.Definition event,
      JournalPostingDateFixedCatalog.Definition postingDateItem,
      AccountingSlotFixedCatalog.Definition debitSlot,
      AccountingSlotFixedCatalog.Definition creditSlot,
      JournalAmountItemFixedCatalog.Definition amountItem,
      AccountingCatalogTypes.SlotPriorityType slotPriorityType,
      AccountingCatalogTypes.ExclusiveGroup exclusiveGroup,
      Integer sortOrder,
      Integer sameDayOrder,
      FixedConditionSetFixedCatalog.Definition conditionSet,
      String description
    ) {
      this.name = name;
      this.key = key;
      this.candidateRole = candidateRole;
      this.event = event;
      this.postingDateItem = postingDateItem;
      this.debitSlot = debitSlot;
      this.creditSlot = creditSlot;
      this.amountItem = amountItem;
      this.slotPriorityType = slotPriorityType;
      this.exclusiveGroup = exclusiveGroup;
      this.sortOrder = sortOrder;
      this.sameDayOrder = sameDayOrder;
      this.conditionSet = conditionSet;
      this.description = description;
    }
  }

  public static final Definition BILLING_BASIS_INVOICE_BODY = new Definition(
    '請求基準：請求本体',
    'BILLING_BASIS_INVOICE_BODY',
    AccountingCatalogTypes.JournalCandidateRole.InvoiceBody,
    AccountingEventFixedCatalog.BILLING_CONFIRMED,
    JournalPostingDateFixedCatalog.BillingDate,
    AccountingSlotFixedCatalog.AccountsReceivable,
    null,
    JournalAmountItemFixedCatalog.InvoiceSubtotal,
    AccountingCatalogTypes.SlotPriorityType.BillingBasisInvoiceAllocation,
    AccountingCatalogTypes.ExclusiveGroup.BodyInvoice,
    10,
    10,
    null,
    '請求基準で請求本体の税抜額を売掛へ載せ、相手をCTAまたはDEFへ優先解決する'
  );
  public static final Definition CASH_BASIS_INVOICE_BODY_CTA_TRANSFER = new Definition(
    '入金連動前受基準：請求時CTA振替',
    'CASH_BASIS_INVOICE_BODY_CTA_TRANSFER',
    AccountingCatalogTypes.JournalCandidateRole.InvoiceBody,
    AccountingEventFixedCatalog.BILLING_CONFIRMED,
    JournalPostingDateFixedCatalog.BillingDate,
    AccountingSlotFixedCatalog.AccountsReceivable,
    AccountingSlotFixedCatalog.ContractAsset,
    JournalAmountItemFixedCatalog.InvoiceBodyCtaTransfer,
    null,
    AccountingCatalogTypes.ExclusiveGroup.BodyInvoice,
    20,
    10,
    null,
    '入金連動前受基準で、請求日前に認識済みの税抜CTAだけを請求日に売掛へ振り替える'
  );
  public static final Definition BILLING_TAX_AT_INVOICE = new Definition(
    '請求時：仮受消費税',
    'BILLING_TAX_AT_INVOICE',
    AccountingCatalogTypes.JournalCandidateRole.InvoiceTax,
    AccountingEventFixedCatalog.BILLING_CONFIRMED,
    JournalPostingDateFixedCatalog.BillingDate,
    AccountingSlotFixedCatalog.AccountsReceivable,
    AccountingSlotFixedCatalog.TaxPayable,
    JournalAmountItemFixedCatalog.AllocatedInvoiceTax,
    null,
    AccountingCatalogTypes.ExclusiveGroup.TaxInvoice,
    10,
    20,
    null,
    '請求時に明細配分税額を売掛と仮受消費税へ載せる'
  );
  public static final Definition BILLING_BASIS_INVOICE_TAX_DEFERRED = new Definition(
    '請求基準：請求時税繰延',
    'BILLING_BASIS_INVOICE_TAX_DEFERRED',
    AccountingCatalogTypes.JournalCandidateRole.InvoiceTax,
    AccountingEventFixedCatalog.BILLING_CONFIRMED,
    JournalPostingDateFixedCatalog.BillingDate,
    AccountingSlotFixedCatalog.AccountsReceivable,
    null,
    JournalAmountItemFixedCatalog.AllocatedInvoiceTax,
    AccountingCatalogTypes.SlotPriorityType.BillingBasisInvoiceAllocation,
    AccountingCatalogTypes.ExclusiveGroup.TaxInvoice,
    20,
    20,
    null,
    '請求基準で明細配分税額を売掛へ載せ、相手をCTAまたはDEFへ優先解決する'
  );
  public static final Definition CASH_BASIS_INVOICE_TAX_CTA_TRANSFER = new Definition(
    '入金連動前受基準：請求時税CTA振替',
    'CASH_BASIS_INVOICE_TAX_CTA_TRANSFER',
    AccountingCatalogTypes.JournalCandidateRole.InvoiceTax,
    AccountingEventFixedCatalog.BILLING_CONFIRMED,
    JournalPostingDateFixedCatalog.BillingDate,
    AccountingSlotFixedCatalog.AccountsReceivable,
    AccountingSlotFixedCatalog.ContractAsset,
    JournalAmountItemFixedCatalog.InvoiceTaxCtaTransfer,
    null,
    AccountingCatalogTypes.ExclusiveGroup.TaxInvoice,
    30,
    20,
    null,
    '入金連動前受基準で、請求日前に認識済みの税CTAだけを請求日に売掛へ振り替える'
  );
  public static final Definition BILLING_BASIS_REVENUE_BODY = new Definition(
    '請求基準：売上本体',
    'BILLING_BASIS_REVENUE_BODY',
    AccountingCatalogTypes.JournalCandidateRole.RevenueBody,
    AccountingEventFixedCatalog.BILLING_CONFIRMED,
    JournalPostingDateFixedCatalog.RecognitionDate,
    null,
    AccountingSlotFixedCatalog.Revenue,
    JournalAmountItemFixedCatalog.RecognizedRevenue,
    AccountingCatalogTypes.SlotPriorityType.BillingBasisRecognitionAllocation,
    AccountingCatalogTypes.ExclusiveGroup.BodyRevenue,
    10,
    30,
    null,
    '請求基準で売上本体を計上し、借方をDEFまたはCTAへ優先解決する'
  );
  public static final Definition CASH_BASIS_REVENUE_BODY = new Definition(
    '入金連動前受基準：売上本体',
    'CASH_BASIS_REVENUE_BODY',
    AccountingCatalogTypes.JournalCandidateRole.RevenueBody,
    AccountingEventFixedCatalog.BILLING_CONFIRMED,
    JournalPostingDateFixedCatalog.RecognitionDate,
    null,
    AccountingSlotFixedCatalog.Revenue,
    JournalAmountItemFixedCatalog.RecognizedRevenue,
    AccountingCatalogTypes.SlotPriorityType.CashBasisRecognitionAllocation,
    AccountingCatalogTypes.ExclusiveGroup.BodyRevenue,
    20,
    30,
    null,
    '入金連動前受基準で売上本体を計上し、借方をDEF・AR・CTAへ優先解決する'
  );
  public static final Definition BILLING_BASIS_REVENUE_TAX = new Definition(
    '請求基準：売上時税',
    'BILLING_BASIS_REVENUE_TAX',
    AccountingCatalogTypes.JournalCandidateRole.RevenueTax,
    AccountingEventFixedCatalog.BILLING_CONFIRMED,
    JournalPostingDateFixedCatalog.RecognitionDate,
    null,
    AccountingSlotFixedCatalog.TaxPayable,
    JournalAmountItemFixedCatalog.RecognizedTax,
    AccountingCatalogTypes.SlotPriorityType.BillingBasisRecognitionAllocation,
    AccountingCatalogTypes.ExclusiveGroup.TaxRevenue,
    10,
    40,
    null,
    '請求基準で売上時に税を認識し、借方をDEFまたはCTAへ優先解決する'
  );
  public static final Definition CASH_BASIS_REVENUE_TAX = new Definition(
    '入金連動前受基準：売上時税',
    'CASH_BASIS_REVENUE_TAX',
    AccountingCatalogTypes.JournalCandidateRole.RevenueTax,
    AccountingEventFixedCatalog.BILLING_CONFIRMED,
    JournalPostingDateFixedCatalog.RecognitionDate,
    null,
    AccountingSlotFixedCatalog.TaxPayable,
    JournalAmountItemFixedCatalog.RecognizedTax,
    AccountingCatalogTypes.SlotPriorityType.CashBasisRecognitionAllocation,
    AccountingCatalogTypes.ExclusiveGroup.TaxRevenue,
    20,
    40,
    null,
    '入金連動前受基準で売上時に税を認識し、借方をDEF・AR・CTAへ優先解決する'
  );
  public static final Definition PAYMENT_INVOICE_CURRENT = new Definition(
    '請求入出金：通常日Invoice決済',
    'PAYMENT_INVOICE_CURRENT',
    AccountingCatalogTypes.JournalCandidateRole.CurrentInvoicePayment,
    AccountingEventFixedCatalog.PAYMENT_RECORDED,
    JournalPostingDateFixedCatalog.PaymentDate,
    AccountingSlotFixedCatalog.Cash,
    null,
    JournalAmountItemFixedCatalog.PaymentAllocationAmount,
    AccountingCatalogTypes.SlotPriorityType.InvoiceSettlementAllocation,
    null,
    10,
    60,
    FixedConditionSetFixedCatalog.PAY_INVOICE_CURRENT,
    '入出金日が請求日以後のInvoice目的を、明細別割当額で現預金からARまたはDEFへ充当する'
  );
  public static final Definition PAYMENT_NON_INVOICE_POSITIVE = new Definition(
    '請求入出金：NonInvoice正額',
    'PAYMENT_NON_INVOICE_POSITIVE',
    AccountingCatalogTypes.JournalCandidateRole.NonInvoicePayment,
    AccountingEventFixedCatalog.PAYMENT_RECORDED,
    JournalPostingDateFixedCatalog.PaymentDate,
    AccountingSlotFixedCatalog.Cash,
    null,
    JournalAmountItemFixedCatalog.PaymentAmount,
    AccountingCatalogTypes.SlotPriorityType.PositiveCashTemporaryAllocation,
    null,
    10,
    70,
    FixedConditionSetFixedCatalog.PAY_NON_INVOICE_POSITIVE,
    'NonInvoice正額を現預金からSPまたはUACへ優先解決する'
  );
  public static final Definition PAYMENT_NON_INVOICE_NEGATIVE = new Definition(
    '請求入出金：NonInvoice負額',
    'PAYMENT_NON_INVOICE_NEGATIVE',
    AccountingCatalogTypes.JournalCandidateRole.NonInvoicePayment,
    AccountingEventFixedCatalog.PAYMENT_RECORDED,
    JournalPostingDateFixedCatalog.PaymentDate,
    AccountingSlotFixedCatalog.Cash,
    null,
    JournalAmountItemFixedCatalog.PaymentAmount,
    AccountingCatalogTypes.SlotPriorityType.NegativeCashTemporaryAllocation,
    null,
    10,
    70,
    FixedConditionSetFixedCatalog.PAY_NON_INVOICE_NEGATIVE,
    'NonInvoice負額を現預金からUACまたはSPへ優先解決する'
  );
  public static final Definition PAYMENT_INVOICE_HISTORICAL_POSITIVE_CASH = new Definition(
    '過去日Invoice正額：現預金段階',
    'PAYMENT_INVOICE_HISTORICAL_POSITIVE_CASH',
    AccountingCatalogTypes.JournalCandidateRole.HistoricalInvoiceCash,
    AccountingEventFixedCatalog.PAYMENT_RECORDED,
    JournalPostingDateFixedCatalog.PaymentDate,
    AccountingSlotFixedCatalog.Cash,
    null,
    JournalAmountItemFixedCatalog.PaymentAllocationAmount,
    AccountingCatalogTypes.SlotPriorityType.PositiveCashTemporaryAllocation,
    null,
    10,
    60,
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_POSITIVE_CASH,
    '過去日Invoice正額の現預金段階を、明細別割当額でSPまたはUACへ載せる'
  );
  public static final Definition PAYMENT_INVOICE_HISTORICAL_NEGATIVE_CASH = new Definition(
    '過去日Invoice負額：現預金段階',
    'PAYMENT_INVOICE_HISTORICAL_NEGATIVE_CASH',
    AccountingCatalogTypes.JournalCandidateRole.HistoricalInvoiceCash,
    AccountingEventFixedCatalog.PAYMENT_RECORDED,
    JournalPostingDateFixedCatalog.PaymentDate,
    AccountingSlotFixedCatalog.Cash,
    null,
    JournalAmountItemFixedCatalog.PaymentAllocationAmount,
    AccountingCatalogTypes.SlotPriorityType.NegativeCashTemporaryAllocation,
    null,
    10,
    60,
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_NEGATIVE_CASH,
    '過去日Invoice負額の現預金段階を、明細別割当額でUACまたはSPへ載せる'
  );
  public static final Definition PAYMENT_INVOICE_HISTORICAL_UAC_TRANSFER = new Definition(
    '過去日Invoice：UAC振替',
    'PAYMENT_INVOICE_HISTORICAL_UAC_TRANSFER',
    AccountingCatalogTypes.JournalCandidateRole.HistoricalUacTransfer,
    AccountingEventFixedCatalog.PAYMENT_RECORDED,
    JournalPostingDateFixedCatalog.BillingDate,
    AccountingSlotFixedCatalog.UnappliedCash,
    null,
    JournalAmountItemFixedCatalog.HistoricalUacAmount,
    AccountingCatalogTypes.SlotPriorityType.HistoricalUacTransfer,
    null,
    10,
    50,
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_UAC_TRANSFER,
    '過去日InvoiceのUACを請求日にARまたはDEFへ振り替える'
  );
  public static final Definition PAYMENT_INVOICE_HISTORICAL_SP_TRANSFER = new Definition(
    '過去日Invoice：SP振替',
    'PAYMENT_INVOICE_HISTORICAL_SP_TRANSFER',
    AccountingCatalogTypes.JournalCandidateRole.HistoricalSpTransfer,
    AccountingEventFixedCatalog.PAYMENT_RECORDED,
    JournalPostingDateFixedCatalog.BillingDate,
    null,
    AccountingSlotFixedCatalog.SuspensePayment,
    JournalAmountItemFixedCatalog.HistoricalSpAmount,
    AccountingCatalogTypes.SlotPriorityType.HistoricalSpTransfer,
    null,
    10,
    51,
    FixedConditionSetFixedCatalog.PAY_INVOICE_HISTORICAL_SP_TRANSFER,
    '過去日InvoiceのSPを請求日に対象明細のARまたはDEF（借方）とSP（貸方）で振り替える'
  );

  private static final Map<String, Definition> BY_KEY = new Map<String, Definition>{
    BILLING_BASIS_INVOICE_BODY.key => BILLING_BASIS_INVOICE_BODY,
    CASH_BASIS_INVOICE_BODY_CTA_TRANSFER.key => CASH_BASIS_INVOICE_BODY_CTA_TRANSFER,
    BILLING_TAX_AT_INVOICE.key => BILLING_TAX_AT_INVOICE,
    BILLING_BASIS_INVOICE_TAX_DEFERRED.key => BILLING_BASIS_INVOICE_TAX_DEFERRED,
    CASH_BASIS_INVOICE_TAX_CTA_TRANSFER.key => CASH_BASIS_INVOICE_TAX_CTA_TRANSFER,
    BILLING_BASIS_REVENUE_BODY.key => BILLING_BASIS_REVENUE_BODY,
    CASH_BASIS_REVENUE_BODY.key => CASH_BASIS_REVENUE_BODY,
    BILLING_BASIS_REVENUE_TAX.key => BILLING_BASIS_REVENUE_TAX,
    CASH_BASIS_REVENUE_TAX.key => CASH_BASIS_REVENUE_TAX,
    PAYMENT_INVOICE_CURRENT.key => PAYMENT_INVOICE_CURRENT,
    PAYMENT_NON_INVOICE_POSITIVE.key => PAYMENT_NON_INVOICE_POSITIVE,
    PAYMENT_NON_INVOICE_NEGATIVE.key => PAYMENT_NON_INVOICE_NEGATIVE,
    PAYMENT_INVOICE_HISTORICAL_POSITIVE_CASH.key => PAYMENT_INVOICE_HISTORICAL_POSITIVE_CASH,
    PAYMENT_INVOICE_HISTORICAL_NEGATIVE_CASH.key => PAYMENT_INVOICE_HISTORICAL_NEGATIVE_CASH,
    PAYMENT_INVOICE_HISTORICAL_UAC_TRANSFER.key => PAYMENT_INVOICE_HISTORICAL_UAC_TRANSFER,
    PAYMENT_INVOICE_HISTORICAL_SP_TRANSFER.key => PAYMENT_INVOICE_HISTORICAL_SP_TRANSFER
  };

  /** 仕様: Accounting 第5.1節、第5.2節 */
  public static Definition require(String key) {
    Definition found = BY_KEY.get(key);
    if (found == null) {
      throw new AccountingCatalogTypes.UnknownKeyException(
        '仕訳パターンキーがCatalogにありません: ' + key
      );
    }
    return found;
  }

  /** 仕様: Accounting 第5.1節、第5.2節 */
  public static List<Definition> values() {
    return new List<Definition>{
      BILLING_BASIS_INVOICE_BODY,
      CASH_BASIS_INVOICE_BODY_CTA_TRANSFER,
      BILLING_TAX_AT_INVOICE,
      BILLING_BASIS_INVOICE_TAX_DEFERRED,
      CASH_BASIS_INVOICE_TAX_CTA_TRANSFER,
      BILLING_BASIS_REVENUE_BODY,
      CASH_BASIS_REVENUE_BODY,
      BILLING_BASIS_REVENUE_TAX,
      CASH_BASIS_REVENUE_TAX,
      PAYMENT_INVOICE_CURRENT,
      PAYMENT_NON_INVOICE_POSITIVE,
      PAYMENT_NON_INVOICE_NEGATIVE,
      PAYMENT_INVOICE_HISTORICAL_POSITIVE_CASH,
      PAYMENT_INVOICE_HISTORICAL_NEGATIVE_CASH,
      PAYMENT_INVOICE_HISTORICAL_UAC_TRANSFER,
      PAYMENT_INVOICE_HISTORICAL_SP_TRANSFER
    };
  }
}
