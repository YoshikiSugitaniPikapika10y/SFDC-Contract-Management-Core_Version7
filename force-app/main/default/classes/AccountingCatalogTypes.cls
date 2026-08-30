public with sharing class AccountingCatalogTypes {
  public class UnknownKeyException extends Exception {
  }

  /** 仕様: Accounting 第4.1節・第4.3節。純資産は区分に含めない。 */
  public enum AccountCategory {
    Asset,
    Liability,
    Revenue,
    Expense
  }

  public enum NormalBalance {
    Debit,
    Credit
  }

  public enum JournalAmountSource {
    InvoiceLine,
    RecognitionSchedule,
    InvoicePayment,
    InvoicePaymentAllocation,
    ManualInput
  }

  public enum GenerationUnitType {
    InvoiceLine,
    RecognitionSchedule,
    InvoicePayment,
    InvoicePaymentAllocation,
    Manual
  }

  public enum PostingDateSourceType {
    BusinessObject,
    RecognitionRule,
    ManualInput,
    Automatic
  }

  public enum SlotPriorityType {
    BillingBasisInvoiceAllocation,
    BillingBasisRecognitionAllocation,
    CashBasisRecognitionAllocation,
    InvoiceSettlementAllocation,
    HistoricalUacTransfer,
    PositiveCashTemporaryAllocation,
    NegativeCashTemporaryAllocation,
    HistoricalSpTransfer
  }

  public enum EvaluationContext {
    InvoiceLine,
    Invoice,
    InvoicePayment,
    InvoicePaymentAllocation
  }

  public enum ConditionObject {
    InvoiceLine,
    Invoice,
    InvoicePayment,
    InvoicePaymentAllocation,
    ContractProduct,
    Product2,
    ContractHistory,
    ContractService,
    Opportunity,
    BillingAccount,
    Account
  }

  public enum ConditionOperator {
    Equals,
    NotEquals,
    GreaterThan,
    GreaterOrEqual,
    LessThan,
    LessOrEqual,
    Contains,
    NotContains,
    IsNull,
    IsNotNull
  }

  public enum CompareType {
    FixedValue,
    Field
  }

  /** 仕様: Accounting 第4.7節。子側のすべて／いずれか。Any は Apex 予約語のため使わない。 */
  public enum AggregateType {
    All,
    AnyOf
  }

  public enum JournalCandidateRole {
    InvoiceBody,
    InvoiceTax,
    RevenueBody,
    RevenueTax,
    CurrentInvoicePayment,
    NonInvoicePayment,
    HistoricalInvoiceCash,
    HistoricalUacTransfer,
    HistoricalSpTransfer
  }

  public enum ExclusiveGroup {
    BodyInvoice,
    TaxInvoice,
    BodyRevenue,
    TaxRevenue
  }

  public enum ConditionSourceType {
    None,
    Fixed,
    Tenant
  }

  /** 仕様: Accounting 第4.7節 */
  public static String objectApiName(ConditionObject obj) {
    if (obj == null) {
      return null;
    }
    if (
      obj == ConditionObject.Product2 ||
      obj == ConditionObject.Opportunity ||
      obj == ConditionObject.Account
    ) {
      return String.valueOf(obj);
    }
    return String.valueOf(obj) + '__c';
  }
}
