public with sharing class JournalAmountItemFixedCatalog {
  public class Definition {
    public final String name;
    public final String key;
    public final String description;
    public final AccountingCatalogTypes.JournalAmountSource source;
    public final AccountingCatalogTypes.GenerationUnitType generationUnit;

    private Definition(
      String name,
      String key,
      String description,
      AccountingCatalogTypes.JournalAmountSource source,
      AccountingCatalogTypes.GenerationUnitType generationUnit
    ) {
      this.name = name;
      this.key = key;
      this.description = description;
      this.source = source;
      this.generationUnit = generationUnit;
    }
  }

  public static final Definition InvoiceSubtotal = new Definition(
    '請求額税抜き',
    'InvoiceSubtotal',
    'InvoiceLine__c.Amount__c',
    AccountingCatalogTypes.JournalAmountSource.InvoiceLine,
    AccountingCatalogTypes.GenerationUnitType.InvoiceLine
  );
  public static final Definition AllocatedInvoiceTax = new Definition(
    '明細配分税額',
    'AllocatedInvoiceTax',
    'InvoiceLine__c.AllocatedTaxAmount__c',
    AccountingCatalogTypes.JournalAmountSource.InvoiceLine,
    AccountingCatalogTypes.GenerationUnitType.InvoiceLine
  );
  public static final Definition InvoiceBodyCtaTransfer = new Definition(
    '請求時本体CTA振替額',
    'InvoiceBodyCtaTransfer',
    '請求日時点で認識済み・未請求の税抜CTA業務容量',
    AccountingCatalogTypes.JournalAmountSource.InvoiceLine,
    AccountingCatalogTypes.GenerationUnitType.InvoiceLine
  );
  public static final Definition InvoiceTaxCtaTransfer = new Definition(
    '請求時税CTA振替額',
    'InvoiceTaxCtaTransfer',
    '請求日時点で認識済み・未請求の税CTA業務容量',
    AccountingCatalogTypes.JournalAmountSource.InvoiceLine,
    AccountingCatalogTypes.GenerationUnitType.InvoiceLine
  );
  public static final Definition RecognizedRevenue = new Definition(
    '売上計上額',
    'RecognizedRevenue',
    '売上計上ルール',
    AccountingCatalogTypes.JournalAmountSource.RecognitionSchedule,
    AccountingCatalogTypes.GenerationUnitType.RecognitionSchedule
  );
  public static final Definition RecognizedTax = new Definition(
    '税額計上額',
    'RecognizedTax',
    '売上計上ルール',
    AccountingCatalogTypes.JournalAmountSource.RecognitionSchedule,
    AccountingCatalogTypes.GenerationUnitType.RecognitionSchedule
  );
  public static final Definition PaymentAmount = new Definition(
    '入出金額',
    'PaymentAmount',
    'InvoicePayment__c.Amount__c',
    AccountingCatalogTypes.JournalAmountSource.InvoicePayment,
    AccountingCatalogTypes.GenerationUnitType.InvoicePayment
  );
  public static final Definition PaymentAllocationAmount = new Definition(
    '明細別割当額',
    'PaymentAllocationAmount',
    'InvoicePaymentAllocation__c.Amount__c',
    AccountingCatalogTypes.JournalAmountSource.InvoicePaymentAllocation,
    AccountingCatalogTypes.GenerationUnitType.InvoicePaymentAllocation
  );
  public static final Definition HistoricalUacAmount = new Definition(
    '過去日UAC振替額',
    'HistoricalUacAmount',
    'InvoicePaymentAllocation__c.HistoricalUacAmount__c',
    AccountingCatalogTypes.JournalAmountSource.InvoicePaymentAllocation,
    AccountingCatalogTypes.GenerationUnitType.InvoicePaymentAllocation
  );
  public static final Definition HistoricalSpAmount = new Definition(
    '過去日SP振替額',
    'HistoricalSpAmount',
    'InvoicePaymentAllocation__c.HistoricalSpAmount__c',
    AccountingCatalogTypes.JournalAmountSource.InvoicePaymentAllocation,
    AccountingCatalogTypes.GenerationUnitType.InvoicePaymentAllocation
  );
  public static final Definition ManualAmount = new Definition(
    '手動入力金額',
    'ManualAmount',
    '手動入力',
    AccountingCatalogTypes.JournalAmountSource.ManualInput,
    AccountingCatalogTypes.GenerationUnitType.Manual
  );

  private static final Map<String, Definition> BY_KEY = new Map<String, Definition>{
    InvoiceSubtotal.key => InvoiceSubtotal,
    AllocatedInvoiceTax.key => AllocatedInvoiceTax,
    InvoiceBodyCtaTransfer.key => InvoiceBodyCtaTransfer,
    InvoiceTaxCtaTransfer.key => InvoiceTaxCtaTransfer,
    RecognizedRevenue.key => RecognizedRevenue,
    RecognizedTax.key => RecognizedTax,
    PaymentAmount.key => PaymentAmount,
    PaymentAllocationAmount.key => PaymentAllocationAmount,
    HistoricalUacAmount.key => HistoricalUacAmount,
    HistoricalSpAmount.key => HistoricalSpAmount,
    ManualAmount.key => ManualAmount
  };

  /** 仕様: Accounting 第4.4節 */
  public static Definition require(String key) {
    Definition found = BY_KEY.get(key);
    if (found == null) {
      throw new AccountingCatalogTypes.UnknownKeyException(
        '仕訳金額項目キーがCatalogにありません: ' + key
      );
    }
    return found;
  }

  /** 仕様: Accounting 第4.4節 */
  public static List<Definition> values() {
    return new List<Definition>{
      InvoiceSubtotal,
      AllocatedInvoiceTax,
      InvoiceBodyCtaTransfer,
      InvoiceTaxCtaTransfer,
      RecognizedRevenue,
      RecognizedTax,
      PaymentAmount,
      PaymentAllocationAmount,
      HistoricalUacAmount,
      HistoricalSpAmount,
      ManualAmount
    };
  }
}
