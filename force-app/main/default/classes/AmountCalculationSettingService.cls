/**
 * 金額計算の組織設定。無い・空・未知はエラー。
 */
public without sharing class AmountCalculationSettingService {
  public static final String TAX_ROUND_DOWN = 'DOWN';
  public static final String TAX_ROUND_HALF_UP = 'HALF_UP';
  public static final String TAX_ROUND_UP = 'UP';
  public static final String TAX_LINE_SIGNED_REMAINDER = 'SignedLargestRemainder';
  public static final String TIE_BREAK_LINE_ORDER = 'InvoiceLineStableOrder';
  public static final String MONTHLY_EQUAL_SPLIT = 'EqualSplit';
  public static final String TAX_SCHEDULE_SIGNED_RATIO = 'SignedRevenueRatio';
  public static final String PAYMENT_OPEN_RATIO = 'OpenInclusiveRatio';
  public static final String ACCOUNT_SAME_RATE = 'SameRate';
  public static final String DOCUMENT_EXCL_RATIO = 'ExclusiveRatioLastAbsorbs';
  public static final String QUANTITY_HALF_UP_2 = 'Scale2HalfUp';
  public static final String AMOUNT_HALF_UP_0 = 'Scale0HalfUp';

  private static GlAccountingSetting__mdt cached;
  @TestVisible
  static Boolean testMissingOrgDefault;

  /** 仕様: Core 第11.9節、第1.1.10節 */
  public static GlAccountingSetting__mdt requireOrgDefault() {
    if (testMissingOrgDefault == true) {
      throw new SettingException('金額計算設定 OrgDefault がありません。');
    }
    if (cached != null) {
      return cached;
    }
    GlAccountingSetting__mdt setting = GlAccountingSetting__mdt.getInstance(
      'OrgDefault'
    );
    if (setting == null) {
      throw new SettingException('金額計算設定 OrgDefault がありません。');
    }
    assertKnown(
      setting.TaxRoundingMode__c,
      new Set<String>{ TAX_ROUND_DOWN, TAX_ROUND_HALF_UP, TAX_ROUND_UP },
      '税額丸め'
    );
    assertKnown(
      setting.QuantityUnitPriceRoundingMode__c,
      new Set<String>{ QUANTITY_HALF_UP_2 },
      '数量・単価の丸め'
    );
    assertKnown(
      setting.AmountRoundingMode__c,
      new Set<String>{ AMOUNT_HALF_UP_0 },
      '税抜金額の丸め'
    );
    assertKnown(
      setting.TaxLineAllocationMethod__c,
      new Set<String>{ TAX_LINE_SIGNED_REMAINDER },
      'ヘッダ税の明細配分'
    );
    assertKnown(
      setting.AllocationTieBreak__c,
      new Set<String>{ TIE_BREAK_LINE_ORDER },
      '同率の決定順'
    );
    assertKnown(
      setting.MonthlyBucketAmountMethod__c,
      new Set<String>{ MONTHLY_EQUAL_SPLIT },
      '月次バケットの金額'
    );
    assertKnown(
      setting.TaxScheduleAllocationMethod__c,
      new Set<String>{ TAX_SCHEDULE_SIGNED_RATIO },
      '税のスケジュール配分'
    );
    assertKnown(
      setting.PaymentLineAllocationMethod__c,
      new Set<String>{ PAYMENT_OPEN_RATIO },
      '一部入返金の初期配分'
    );
    assertKnown(
      setting.AccountBalanceAllocationMethod__c,
      new Set<String>{ ACCOUNT_SAME_RATE },
      '複数実勘定への配分'
    );
    assertKnown(
      setting.DocumentGroupTaxAllocationMethod__c,
      new Set<String>{ DOCUMENT_EXCL_RATIO },
      '帳票グループ税込'
    );
    cached = setting;
    return cached;
  }

  /** 仕様: Core 第11.9節 */
  public static RoundingMode taxRoundingMode() {
    String raw = requireOrgDefault().TaxRoundingMode__c;
    if (raw == TAX_ROUND_HALF_UP) {
      return RoundingMode.HALF_UP;
    }
    if (raw == TAX_ROUND_UP) {
      return RoundingMode.UP;
    }
    return RoundingMode.DOWN;
  }

  /** 仕様: Core 第4.6節、第11.9節。数量・単価の小数桁。無い・空・未知は requireOrgDefault でエラー。 */
  public static Integer quantityUnitPriceScale() {
    String raw = requireOrgDefault().QuantityUnitPriceRoundingMode__c;
    if (raw == QUANTITY_HALF_UP_2) {
      return 2;
    }
    throw new SettingException('数量・単価の丸めの設定が無い、空、または不正です。');
  }

  /** 仕様: Core 第4.6節、第11.9節 */
  public static RoundingMode quantityUnitPriceRoundingMode() {
    String raw = requireOrgDefault().QuantityUnitPriceRoundingMode__c;
    if (raw == QUANTITY_HALF_UP_2) {
      return RoundingMode.HALF_UP;
    }
    throw new SettingException('数量・単価の丸めの設定が無い、空、または不正です。');
  }

  /** 仕様: Core 第4.6節、第11.9節。税抜金額の小数桁。 */
  public static Integer amountScale() {
    String raw = requireOrgDefault().AmountRoundingMode__c;
    if (raw == AMOUNT_HALF_UP_0) {
      return 0;
    }
    throw new SettingException('税抜金額の丸めの設定が無い、空、または不正です。');
  }

  /** 仕様: Core 第4.6節、第11.9節 */
  public static RoundingMode amountRoundingMode() {
    String raw = requireOrgDefault().AmountRoundingMode__c;
    if (raw == AMOUNT_HALF_UP_0) {
      return RoundingMode.HALF_UP;
    }
    throw new SettingException('税抜金額の丸めの設定が無い、空、または不正です。');
  }

  /** 仕様: Core 第4.6節、第11.9節 */
  public static Decimal roundQuantityUnitPrice(Decimal value) {
    if (value == null) {
      return null;
    }
    return value.setScale(quantityUnitPriceScale(), quantityUnitPriceRoundingMode());
  }

  /** 仕様: Core 第4.6節、第11.9節 */
  public static Decimal roundAmount(Decimal value) {
    if (value == null) {
      return null;
    }
    return value.setScale(amountScale(), amountRoundingMode());
  }

  @TestVisible
  static void clearCache() {
    cached = null;
  }

  private static void assertKnown(String value, Set<String> allowed, String label) {
    if (String.isBlank(value) || !allowed.contains(value)) {
      throw new SettingException(label + 'の設定が無い、空、または不正です。');
    }
  }

  public class SettingException extends Exception {
  }
}
