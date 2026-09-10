@IsTest
private class TaxCalculationUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void resolveTaxPercent_nullIsError() {
    Boolean thrown = false;
    try {
      TaxCalculationUtil.resolveTaxPercent(null);
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('空'),
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown, '税率空はエラー');
    System.assertEquals(8, TaxCalculationUtil.resolveTaxPercent(8));
    System.assertEquals(0, TaxCalculationUtil.resolveTaxPercent(0));
    System.assertEquals(1, TaxCalculationUtil.resolveTaxPercent(1));
  }

  @IsTest
  static void calculateTaxAmount_floorsTax() {
    System.assertEquals(0, TaxCalculationUtil.calculateTaxAmount(null, 10));
    System.assertEquals(0, TaxCalculationUtil.calculateTaxAmount(0, 10));
    Boolean zeroAmountEmptyRate = false;
    try {
      TaxCalculationUtil.calculateTaxAmount(0, null);
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      zeroAmountEmptyRate = true;
      System.assert(ex.getMessage().contains('空'), ex.getMessage());
    }
    System.assertEquals(
      true,
      zeroAmountEmptyRate,
      'Core 第7.4節: 税抜0でも税率空は0%にせずエラー'
    );
    System.assertEquals(1200, TaxCalculationUtil.calculateTaxAmount(12000, 10));
    System.assertEquals(800, TaxCalculationUtil.calculateTaxAmount(8000, 10));
    System.assertEquals(-100, TaxCalculationUtil.calculateTaxAmount(-1000, 10));
    Boolean thrown = false;
    try {
      TaxCalculationUtil.calculateTaxAmount(12000, null);
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      thrown = true;
      System.assert(ex.getMessage().contains('空'), ex.getMessage());
    }
    System.assertEquals(
      true,
      thrown,
      'Core 第1.4節・第1.1.10節: 税率の空欄は 0% にせずエラー'
    );
  }

  @IsTest
  static void calculateAmountInclTax_addsTaxAmount() {
    System.assertEquals(
      13200,
      TaxCalculationUtil.calculateAmountInclTax(12000, 10)
    );
    Boolean thrown = false;
    try {
      TaxCalculationUtil.calculateAmountInclTax(12000, null);
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      thrown = true;
      System.assert(ex.getMessage().contains('空'), ex.getMessage());
    }
    System.assertEquals(
      true,
      thrown,
      'Core 第1.4節・第1.1.10節: 税率の空欄は 0% にせずエラー'
    );
  }

  @IsTest
  static void toPercentFieldStorage_writesDisplayPercent() {
    System.assertEquals(10, TaxCalculationUtil.toPercentFieldStorage(10));
    System.assertEquals(8, TaxCalculationUtil.toPercentFieldStorage(8));
    Boolean thrown = false;
    try {
      TaxCalculationUtil.toPercentFieldStorage(null);
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      thrown = true;
      System.assert(ex.getMessage().contains('空'), ex.getMessage());
    }
    System.assertEquals(
      true,
      thrown,
      'Core 第1.1.10節: Percent 未入力は 0% にせずエラー'
    );
  }

  @IsTest
  static void fromPercentFieldStorage_normalizesFractionAndDisplay() {
    System.assertEquals(null, TaxCalculationUtil.fromPercentFieldStorage(null));
    System.assertEquals(
      10,
      TaxCalculationUtil.fromPercentFieldStorage(0.1),
      '項目初期値などの小数表記 0.1＝10%'
    );
    System.assertEquals(
      8,
      TaxCalculationUtil.fromPercentFieldStorage(0.08),
      '小数表記 0.08＝8%'
    );
    System.assertEquals(
      10,
      TaxCalculationUtil.fromPercentFieldStorage(10),
      'Apex/UI 由来の表示％ 10＝10% はそのまま'
    );
    System.assertEquals(
      1,
      TaxCalculationUtil.fromPercentFieldStorage(1),
      '1＝1%（小数表記と区別）'
    );
    System.assertEquals(
      10,
      TaxCalculationUtil.resolveTaxPercent(
        TaxCalculationUtil.fromPercentFieldStorage(0.1)
      )
    );
    System.assertEquals(
      10,
      TaxCalculationUtil.resolveTaxPercent(
        TaxCalculationUtil.fromPercentFieldStorage(10)
      )
    );
    Boolean thrown = false;
    try {
      TaxCalculationUtil.resolveTaxPercent(
        TaxCalculationUtil.fromPercentFieldStorage(null)
      );
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      thrown = true;
      System.assert(ex.getMessage().contains('空'), ex.getMessage());
    }
    System.assertEquals(
      true,
      thrown,
      'Core 第1.1.10節: Percent 未入力は 0% にせずエラー'
    );
  }

  @IsTest
  static void resolveTaxPercent_rejectsValueOverOneHundred() {
    Boolean thrown = false;
    try {
      TaxCalculationUtil.resolveTaxPercent(1000);
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      thrown = true;
    }
    System.assertEquals(true, thrown, '100超の値はエラーにすること');
  }

  @IsTest
  static void resolveTaxPercent_rejectsFractionLikeValue() {
    Boolean thrown = false;
    try {
      TaxCalculationUtil.resolveTaxPercent(0.08);
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      thrown = true;
    }
    System.assertEquals(
      true,
      thrown,
      '表示％として 0<x<1 を渡すのはエラー（fromPercentFieldStorage 経由で正規化すること）'
    );
  }

  @IsTest
  static void resolveTaxPercent_rejectsNegativeValue() {
    Boolean thrown = false;
    try {
      TaxCalculationUtil.resolveTaxPercent(-5);
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      thrown = true;
    }
    System.assertEquals(true, thrown, '負の値はエラーにすること');
  }

  @IsTest
  static void formatTaxPercentLabel_formatsResolvedPercent() {
    Boolean thrown = false;
    try {
      TaxCalculationUtil.formatTaxPercentLabel(null);
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      thrown = true;
      System.assert(ex.getMessage().contains('空'), ex.getMessage());
    }
    System.assertEquals(
      true,
      thrown,
      'Core 第1.1.10節: 税率空のラベルは 0 にせずエラー'
    );
    System.assertEquals('8', TaxCalculationUtil.formatTaxPercentLabel(8));
    System.assertEquals('10', TaxCalculationUtil.formatTaxPercentLabel(10));
    System.assertEquals('0', TaxCalculationUtil.formatTaxPercentLabel(0));
  }

  @IsTest
  static void resolveTaxPercent_rejectsWithExactMessagesAndAllowsOneHundred() {
    try {
      TaxCalculationUtil.resolveTaxPercent(null);
      System.assert(false, '空は例外になる');
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      System.assertEquals(
        '消費税率が空です。',
        ex.getMessage(),
        'Core 第1.1.10節: 税率の空欄は 0% にせずエラー'
      );
    }
    try {
      TaxCalculationUtil.resolveTaxPercent(-5);
      System.assert(false, '負数は例外になる');
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      System.assertEquals(
        '消費税率が不正です（負の値は指定できません）: -5',
        ex.getMessage(),
        'Core 第1.1.10節: 負の税率は推測して進めない'
      );
    }
    try {
      TaxCalculationUtil.resolveTaxPercent(0.08);
      System.assert(false, '小数は例外になる');
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      System.assertEquals(
        '消費税率が不正です（0〜1の小数ではなくパーセント値を入力してください）: 0.08',
        ex.getMessage(),
        'Core 第1.1.10節: 0〜1の小数はパーセント値ではない'
      );
    }
    try {
      TaxCalculationUtil.resolveTaxPercent(1000);
      System.assert(false, '100超は例外になる');
    } catch (TaxCalculationUtil.TaxPercentException ex) {
      System.assertEquals(
        '消費税率が不正です（100を超える値は指定できません）: 1000',
        ex.getMessage(),
        'Core 第1.1.10節: 100超は不正'
      );
    }
    System.assertEquals(
      100,
      TaxCalculationUtil.resolveTaxPercent(100),
      'Core 第1.1.10節: 100はパーセント値として受け付ける'
    );
  }

  @IsTest
  static void calculateTaxAmount_roundsTowardZeroPerOrgSetting() {
    System.assertEquals(
      100,
      TaxCalculationUtil.calculateTaxAmount(1001, 10),
      'Core 第7.4節・第11.9節: シードの税額丸めは0方向切捨て。1001×10%は100'
    );
    System.assertEquals(
      0,
      TaxCalculationUtil.calculateAmountInclTax(null, 10),
      'Core 第7.4節: 税抜空は0として税0を足す。税率空にはしない'
    );
    System.assertEquals(
      '10.5',
      TaxCalculationUtil.formatTaxPercentLabel(10.5),
      'Core 第1.1.10節: 端数のある税率はゼロ埋めせず表示％のまま'
    );
    System.assertEquals(
      0,
      TaxCalculationUtil.fromPercentFieldStorage(0),
      '0は小数表記ではなく表示％の0%'
    );
  }
}
