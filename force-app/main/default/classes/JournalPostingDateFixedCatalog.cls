public with sharing class JournalPostingDateFixedCatalog {
  public class Definition {
    public final String name;
    public final String key;
    public final AccountingCatalogTypes.PostingDateSourceType sourceType;
    public final String sourceField;
    public final String description;

    private Definition(
      String name,
      String key,
      AccountingCatalogTypes.PostingDateSourceType sourceType,
      String sourceField,
      String description
    ) {
      this.name = name;
      this.key = key;
      this.sourceType = sourceType;
      this.sourceField = sourceField;
      this.description = description;
    }
  }

  public static final Definition BillingDate = new Definition(
    '請求日',
    'BillingDate',
    AccountingCatalogTypes.PostingDateSourceType.BusinessObject,
    'Invoice__c.InvoiceDate__c',
    '仕訳パターン No.1～5、15、16'
  );
  public static final Definition PaymentDate = new Definition(
    '入出金日',
    'PaymentDate',
    AccountingCatalogTypes.PostingDateSourceType.BusinessObject,
    'InvoicePayment__c.PaymentDate__c',
    '仕訳パターン No.10～14'
  );
  public static final Definition RecognitionDate = new Definition(
    '売上計上日',
    'RecognitionDate',
    AccountingCatalogTypes.PostingDateSourceType.RecognitionRule,
    null,
    '一括は検収終了日、月次はバケット日から作るスケジュールの計上日'
  );
  public static final Definition ManualDate = new Definition(
    '手動入力日',
    'ManualDate',
    AccountingCatalogTypes.PostingDateSourceType.ManualInput,
    null,
    '手動仕訳設定。設定項目には持たない'
  );
  public static final Definition ReversalDate = new Definition(
    '実際の逆仕訳日',
    'ReversalDate',
    AccountingCatalogTypes.PostingDateSourceType.Automatic,
    null,
    'ロック済み元仕訳ごとにmax(取消基準日, 元仕訳日)。未ロックだけなら使用しない'
  );

  private static final Map<String, Definition> BY_KEY = new Map<String, Definition>{
    BillingDate.key => BillingDate,
    PaymentDate.key => PaymentDate,
    RecognitionDate.key => RecognitionDate,
    ManualDate.key => ManualDate,
    ReversalDate.key => ReversalDate
  };

  /** 仕様: Accounting 第4.5節 */
  public static Definition require(String key) {
    Definition found = BY_KEY.get(key);
    if (found == null) {
      throw new AccountingCatalogTypes.UnknownKeyException(
        '仕訳計上日項目キーがCatalogにありません: ' + key
      );
    }
    return found;
  }

  /** 仕様: Accounting 第4.5節 */
  public static List<Definition> values() {
    return new List<Definition>{
      BillingDate,
      PaymentDate,
      RecognitionDate,
      ManualDate,
      ReversalDate
    };
  }
}
