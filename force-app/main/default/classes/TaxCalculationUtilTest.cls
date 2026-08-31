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
}
