/**
 * 同時編集ガード（楽観ロック）。
 * 画面オープン時に受け取った LastModified トークンと、保存直前の実値を比較する。
 */
public with sharing class ContractOptimisticLockUtil {
  public static final String CONFLICT_MESSAGE =
    '他のユーザーが先に更新しました。画面を開き直してから再度操作してください。';

  /**
   * Aura / LWC 向けの不変トークン（ミリ秒 epoch 文字列）。
   */
  public static String toToken(Datetime value) {
    if (value == null) {
      return null;
    }
    return String.valueOf(value.getTime());
  }

  public static Datetime parseToken(String token) {
    if (String.isBlank(token)) {
      return null;
    }
    try {
      return Datetime.newInstance(Long.valueOf(token.trim()));
    } catch (Exception ex) {
      return null;
    }
  }

  /**
   * expectedToken が空のときは互換のためスキップ（Apex 直呼びテスト用）。
   * LWC からは必ずトークンを送る。
   */
  public static void assertUnchanged(
    Datetime actualLastModified,
    String expectedToken,
    String entityLabel
  ) {
    if (String.isBlank(expectedToken)) {
      return;
    }
    Datetime expected = parseToken(expectedToken);
    if (expected == null) {
      throw conflict(entityLabel);
    }
    if (actualLastModified == null) {
      return;
    }
    if (actualLastModified.getTime() != expected.getTime()) {
      throw conflict(entityLabel);
    }
  }

  public static void assertHistoryUnchanged(
    ContractHistory__c history,
    String expectedToken
  ) {
    if (history == null) {
      AuraHandledException ex = new AuraHandledException(
        '契約履歴が見つかりません。'
      );
      ex.setMessage('契約履歴が見つかりません。');
      throw ex;
    }
    assertUnchanged(history.LastModifiedDate, expectedToken, '契約履歴');
  }

  public static AuraHandledException conflict(String entityLabel) {
    // entityLabel は将来のメッセージ差し替え用。文言はユーザー向けに統一。
    // Apex テストでも getMessage() で本文が取れるよう setMessage する。
    AuraHandledException ex = new AuraHandledException(CONFLICT_MESSAGE);
    ex.setMessage(CONFLICT_MESSAGE);
    return ex;
  }
}
