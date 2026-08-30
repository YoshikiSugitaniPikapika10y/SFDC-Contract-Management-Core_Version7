public with sharing class AccountingSlotFixedCatalog {
  public class Definition {
    public final String name;
    public final String key;
    public final String abbreviation;
    public final AccountingCatalogTypes.AccountCategory accountCategory;
    public final AccountingCatalogTypes.NormalBalance normalBalance;
    public final String description;

    private Definition(
      String name,
      String key,
      String abbreviation,
      AccountingCatalogTypes.AccountCategory accountCategory,
      AccountingCatalogTypes.NormalBalance normalBalance,
      String description
    ) {
      this.name = name;
      this.key = key;
      this.abbreviation = abbreviation;
      this.accountCategory = accountCategory;
      this.normalBalance = normalBalance;
      this.description = description;
    }
  }

  public static final Definition AccountsReceivable = new Definition(
    '売掛債権',
    'AccountsReceivable',
    'AR',
    AccountingCatalogTypes.AccountCategory.Asset,
    AccountingCatalogTypes.NormalBalance.Debit,
    '売掛債権。提供済みだが未入金の金額'
  );
  public static final Definition ContractAsset = new Definition(
    '契約資産',
    'ContractAsset',
    'CTA',
    AccountingCatalogTypes.AccountCategory.Asset,
    AccountingCatalogTypes.NormalBalance.Debit,
    '契約資産・未収収益。売上に近いが請求権未確定の金額'
  );
  public static final Definition Cash = new Definition(
    '現金・預金',
    'Cash',
    'CASH',
    AccountingCatalogTypes.AccountCategory.Asset,
    AccountingCatalogTypes.NormalBalance.Debit,
    '会社が実際に持つ現金・銀行口座残高'
  );
  public static final Definition DeferredRevenue = new Definition(
    '前受収益',
    'DeferredRevenue',
    'DEF',
    AccountingCatalogTypes.AccountCategory.Liability,
    AccountingCatalogTypes.NormalBalance.Credit,
    '先に受けたが未提供のサービス代金'
  );
  public static final Definition TaxPayable = new Definition(
    '仮受消費税',
    'TaxPayable',
    'TAX',
    AccountingCatalogTypes.AccountCategory.Liability,
    AccountingCatalogTypes.NormalBalance.Credit,
    '顧客から預かり後で納付する消費税'
  );
  public static final Definition UnappliedCash = new Definition(
    '仮受金',
    'UnappliedCash',
    'UAC',
    AccountingCatalogTypes.AccountCategory.Liability,
    AccountingCatalogTypes.NormalBalance.Credit,
    '入金済みだが充当先未確定のお金'
  );
  public static final Definition SuspensePayment = new Definition(
    '未解決支払',
    'SuspensePayment',
    'SP',
    AccountingCatalogTypes.AccountCategory.Asset,
    AccountingCatalogTypes.NormalBalance.Debit,
    'NonInvoice負額でUAC残高を超えて実際に支払った、回収または費用振替前の未解決金額'
  );
  public static final Definition Revenue = new Definition(
    '売上収益',
    'Revenue',
    'REV',
    AccountingCatalogTypes.AccountCategory.Revenue,
    AccountingCatalogTypes.NormalBalance.Credit,
    '商品・サービス提供による売上'
  );
  public static final Definition FxGain = new Definition(
    '為替差益',
    'FxGain',
    'FXG',
    AccountingCatalogTypes.AccountCategory.Revenue,
    AccountingCatalogTypes.NormalBalance.Credit,
    '為替変動による利益'
  );
  public static final Definition FxLoss = new Definition(
    '為替差損',
    'FxLoss',
    'FXL',
    AccountingCatalogTypes.AccountCategory.Expense,
    AccountingCatalogTypes.NormalBalance.Debit,
    '為替変動による損失'
  );
  public static final Definition OtherIncome = new Definition(
    '雑収入',
    'OtherIncome',
    'OIN',
    AccountingCatalogTypes.AccountCategory.Revenue,
    AccountingCatalogTypes.NormalBalance.Credit,
    '本業売上以外の収益'
  );
  public static final Definition OtherExpense = new Definition(
    'その他費用',
    'OtherExpense',
    'OEX',
    AccountingCatalogTypes.AccountCategory.Expense,
    AccountingCatalogTypes.NormalBalance.Debit,
    '本業売上に直接対応しない費用・損失'
  );

  private static final Map<String, Definition> BY_KEY = new Map<String, Definition>{
    AccountsReceivable.key => AccountsReceivable,
    ContractAsset.key => ContractAsset,
    Cash.key => Cash,
    DeferredRevenue.key => DeferredRevenue,
    TaxPayable.key => TaxPayable,
    UnappliedCash.key => UnappliedCash,
    SuspensePayment.key => SuspensePayment,
    Revenue.key => Revenue,
    FxGain.key => FxGain,
    FxLoss.key => FxLoss,
    OtherIncome.key => OtherIncome,
    OtherExpense.key => OtherExpense
  };

  /** 仕様: Accounting 第4.3節 */
  public static Definition require(String key) {
    Definition found = BY_KEY.get(key);
    if (found == null) {
      throw new AccountingCatalogTypes.UnknownKeyException(
        '勘定スロットキーがCatalogにありません: ' + key
      );
    }
    return found;
  }

  /** 仕様: Accounting 第4.3節 */
  public static List<Definition> values() {
    return new List<Definition>{
      AccountsReceivable,
      ContractAsset,
      Cash,
      DeferredRevenue,
      TaxPayable,
      UnappliedCash,
      SuspensePayment,
      Revenue,
      FxGain,
      FxLoss,
      OtherIncome,
      OtherExpense
    };
  }
}
