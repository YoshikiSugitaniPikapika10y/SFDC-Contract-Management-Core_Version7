public with sharing class AccountingEventFixedCatalog {
  public class Definition {
    public final String name;
    public final String key;
    public final String description;

    private Definition(String name, String key, String description) {
      this.name = name;
      this.key = key;
      this.description = description;
    }
  }

  public static final Definition BILLING_CONFIRMED = new Definition(
    '請求確定',
    'BILLING_CONFIRMED',
    '請求書の内容が確定したことを起点として、その請求書に関する仕訳と将来の売上仕訳予定を生成する'
  );
  public static final Definition BILLING_CANCELLED = new Definition(
    '請求取消',
    'BILLING_CANCELLED',
    '確定済み請求を取消済みにして有効な原因から除外する'
  );
  public static final Definition ACCEPTANCE_DATE_CHANGED = new Definition(
    '検収日変更',
    'ACCEPTANCE_DATE_CHANGED',
    '一括計上明細の保存済み検収終了日を別の日付へ変更したときの取消と再生成'
  );
  public static final Definition PAYMENT_RECORDED = new Definition(
    '請求入出金登録（Purpose=Invoice／NonInvoiceと符号付きAmountを含む）',
    'PAYMENT_RECORDED',
    'Purpose=Invoice／NonInvoiceと符号付きAmountを含む請求入出金の登録'
  );
  public static final Definition PAYMENT_CANCELLED = new Definition(
    '請求入出金取消',
    'PAYMENT_CANCELLED',
    '誤登録した請求入出金を有効なNetから外す取消'
  );
  public static final Definition MANUAL_JOURNAL = new Definition(
    '手動仕訳',
    'MANUAL_JOURNAL',
    'システムで判定できない事象を利用者が登録する仕訳'
  );

  private static final Map<String, Definition> BY_KEY = new Map<String, Definition>{
    BILLING_CONFIRMED.key => BILLING_CONFIRMED,
    BILLING_CANCELLED.key => BILLING_CANCELLED,
    ACCEPTANCE_DATE_CHANGED.key => ACCEPTANCE_DATE_CHANGED,
    PAYMENT_RECORDED.key => PAYMENT_RECORDED,
    PAYMENT_CANCELLED.key => PAYMENT_CANCELLED,
    MANUAL_JOURNAL.key => MANUAL_JOURNAL
  };

  /** 仕様: Accounting 第4.2節 */
  public static Definition require(String key) {
    Definition found = BY_KEY.get(key);
    if (found == null) {
      throw new AccountingCatalogTypes.UnknownKeyException(
        '会計イベントキーがCatalogにありません: ' + key
      );
    }
    return found;
  }

  /** 仕様: Accounting 第4.2節 */
  public static List<Definition> values() {
    return new List<Definition>{
      BILLING_CONFIRMED,
      BILLING_CANCELLED,
      ACCEPTANCE_DATE_CHANGED,
      PAYMENT_RECORDED,
      PAYMENT_CANCELLED,
      MANUAL_JOURNAL
    };
  }
}
