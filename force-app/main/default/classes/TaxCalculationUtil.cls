/**
 * 消費税率の正規化と税額計算。
 *
 * 呼び出し側の「表示％」（10＝10%）を扱う。
 * Salesforce Percent 項目は経路によって読取値が揺れる:
 * - Apex/SOQL・UI 入力由来: 10＝10%
 * - 項目初期値（メタデータ 0.1）や一部の書込: 0.1＝10%
 * 項目値は必ず fromPercentFieldStorage で表示％へ揃えてから resolveTaxPercent へ渡す。
 * null（未入力）は 0% 扱い。負数・100超を表示％として渡すのはエラー。
 */
public without sharing class TaxCalculationUtil {
  /** 未入力（null）時の税率。置換用の既定税率ではなく、0% として計算する。 */
  public static final Decimal DEFAULT_TAX_PERCENT = 0;

  public class TaxPercentException extends Exception {
  }

  /**
   * Percent 項目の読取値 → 表示％（例: 10）。
   * 既に表示％（1超〜100）ならそのまま。小数表記（0超〜1未満）なら ×100。
   * null はそのまま（resolveTaxPercent で 0% 扱い）。
   */
  public static Decimal fromPercentFieldStorage(Decimal storedValue) {
    if (storedValue == null) {
      return null;
    }
    // 項目初期値 0.1 や旧スナップショットの小数表記（0.1＝10%）
    if (storedValue > 0 && storedValue < 1) {
      return storedValue * 100;
    }
    return storedValue;
  }

  public static Decimal resolveTaxPercent(Decimal taxPercent) {
    if (taxPercent == null) {
      return DEFAULT_TAX_PERCENT;
    }
    if (taxPercent < 0) {
      throw new TaxPercentException(
        '消費税率が不正です（負の値は指定できません）: ' + taxPercent
      );
    }
    if (taxPercent > 0 && taxPercent < 1) {
      throw new TaxPercentException(
        '消費税率が不正です（0〜1の小数ではなくパーセント値を入力してください）: ' +
        taxPercent
      );
    }
    if (taxPercent > 100) {
      throw new TaxPercentException(
        '消費税率が不正です（100を超える値は指定できません）: ' + taxPercent
      );
    }
    return taxPercent;
  }

  /**
   * 表示％ → Percent 項目への Apex 書込値。
   * Apex では 10＝10% で書き込む（UI と同じ）。
   */
  public static Decimal toPercentFieldStorage(Decimal displayPercent) {
    return resolveTaxPercent(displayPercent);
  }

  public static Decimal calculateTaxAmount(
    Decimal amountExclTax,
    Decimal taxPercent
  ) {
    if (amountExclTax == null || amountExclTax == 0) {
      return 0;
    }
    Decimal rate = resolveTaxPercent(taxPercent) / 100;
    return (amountExclTax * rate).setScale(0, RoundingMode.DOWN);
  }

  public static Decimal calculateAmountInclTax(
    Decimal amountExclTax,
    Decimal taxPercent
  ) {
    Decimal excl = amountExclTax == null ? 0 : amountExclTax;
    return excl + calculateTaxAmount(excl, taxPercent);
  }

  public static String formatTaxPercentLabel(Decimal taxPercent) {
    Decimal resolved = resolveTaxPercent(taxPercent);
    if (resolved == resolved.intValue()) {
      return String.valueOf(resolved.intValue());
    }
    return String.valueOf(resolved.stripTrailingZeros());
  }
}
