/**
 * 同時編集ガード（楽観ロック）。
 * 画面オープン時に受け取った LastModified トークンと、保存直前の実値を比較する。
 */
public with sharing class ContractOptimisticLockUtil {
  public static final String CONFLICT_MESSAGE = '他のユーザーが先に更新しました。画面を開き直してから再度操作してください。';
  @TestVisible
  static Integer historySelectCount = 0;
  @TestVisible
  static Integer productMaxSelectCount = 0;

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

  /**
   * Aura / LWC の更新入口向け。トークン欠落や比較対象日時の欠落も
   * 「競合を検知できない状態」として安全側に拒否する。
   */
  public static void assertRequiredUnchanged(
    Datetime actualLastModified,
    String expectedToken,
    String entityLabel
  ) {
    if (String.isBlank(expectedToken) || actualLastModified == null) {
      throw conflict(entityLabel);
    }
    assertUnchanged(actualLastModified, expectedToken, entityLabel);
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

  public static void assertRequiredHistoryUnchanged(
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
    assertRequiredUnchanged(
      history.LastModifiedDate,
      expectedToken,
      '契約履歴'
    );
  }

  /** 仕様: Core 第4.3.12節。版は契約履歴と配下の見積商品。 */
  public static Datetime resolveHistoryProductDatetime(Id historyId) {
    return resolveHistoryProductDatetime(historyId, null);
  }

  /**
   * 仕様: Core 第5.2節、第12.4節。
   * 同一処理でロック済み契約履歴の更新日時があれば取り直さない。
   */
  public static Datetime resolveHistoryProductDatetime(
    Id historyId,
    Datetime knownHistoryModified
  ) {
    return resolveHistoryProductDatetime(historyId, knownHistoryModified, null);
  }

  /**
   * 仕様: Core 第4.3.12節・第12.4節。
   * ロック照会で読んだ見積商品の更新日時があれば MAX を取り直さない。
   */
  public static Datetime resolveHistoryProductDatetime(
    Id historyId,
    Datetime knownHistoryModified,
    List<ContractProduct__c> knownProducts
  ) {
    if (historyId == null) {
      return null;
    }
    Datetime maxLm = knownHistoryModified;
    if (maxLm == null) {
      historySelectCount++;
      for (ContractHistory__c history : [
        SELECT LastModifiedDate
        FROM ContractHistory__c
        WHERE Id = :historyId
        WITH SYSTEM_MODE
        LIMIT 1
      ]) {
        maxLm = history.LastModifiedDate;
      }
    }
    if (knownProducts != null) {
      for (ContractProduct__c product : knownProducts) {
        if (
          product != null &&
          product.LastModifiedDate != null &&
          (maxLm == null || product.LastModifiedDate > maxLm)
        ) {
          maxLm = product.LastModifiedDate;
        }
      }
      return maxLm;
    }
    productMaxSelectCount++;
    for (AggregateResult row : [
      SELECT MAX(LastModifiedDate) maxLm
      FROM ContractProduct__c
      WHERE ContractHistory__c = :historyId
      WITH SYSTEM_MODE
    ]) {
      Datetime productMax = (Datetime) row.get('maxLm');
      if (productMax != null && (maxLm == null || productMax > maxLm)) {
        maxLm = productMax;
      }
    }
    return maxLm;
  }

  /** 仕様: Core 第4.3.12節 */
  public static String toHistoryProductToken(Id historyId) {
    return toHistoryProductToken(historyId, null);
  }

  /** 仕様: Core 第4.3.11節、第4.3.12節、第12.4節。読んだ契約履歴の更新日時は取り直さない。 */
  public static String toHistoryProductToken(
    Id historyId,
    Datetime knownHistoryModified
  ) {
    return toToken(resolveHistoryProductDatetime(historyId, knownHistoryModified));
  }

  /** 仕様: Core 第4.3.12節、第5.2節、第12.4節 */
  public static void assertRequiredHistoryProductsUnchanged(
    Id historyId,
    String expectedToken
  ) {
    assertRequiredHistoryProductsUnchanged(historyId, expectedToken, null);
  }

  /** 仕様: Core 第5.2節、第12.4節。ロック済み契約履歴の更新日時は取り直さない。 */
  public static void assertRequiredHistoryProductsUnchanged(
    Id historyId,
    String expectedToken,
    Datetime knownHistoryModified
  ) {
    assertRequiredHistoryProductsUnchanged(
      historyId,
      expectedToken,
      knownHistoryModified,
      null
    );
  }

  /** 仕様: Core 第4.3.12節・第12.4節。ロック照会の見積商品 MAX は取り直さない。 */
  public static void assertRequiredHistoryProductsUnchanged(
    Id historyId,
    String expectedToken,
    Datetime knownHistoryModified,
    List<ContractProduct__c> knownProducts
  ) {
    assertRequiredUnchanged(
      resolveHistoryProductDatetime(
        historyId,
        knownHistoryModified,
        knownProducts
      ),
      expectedToken,
      '契約履歴'
    );
  }

  public static AuraHandledException conflict(String entityLabel) {
    // entityLabel は将来のメッセージ差し替え用。文言はユーザー向けに統一。
    // Apex テストでも getMessage() で本文が取れるよう setMessage する。
    AuraHandledException ex = new AuraHandledException(CONFLICT_MESSAGE);
    ex.setMessage(CONFLICT_MESSAGE);
    return ex;
  }
}
