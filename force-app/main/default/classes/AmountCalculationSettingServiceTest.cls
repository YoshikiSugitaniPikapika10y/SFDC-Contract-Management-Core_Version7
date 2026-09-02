@IsTest
private class AmountCalculationSettingServiceTest {
  @IsTest
  static void requireOrgDefault_readsSeed() {
    AmountCalculationSettingService.clearCache();
    GlAccountingSetting__mdt setting = AmountCalculationSettingService.requireOrgDefault();
    System.assertEquals(
      AmountCalculationSettingService.TAX_ROUND_DOWN,
      setting.TaxRoundingMode__c
    );
    System.assertEquals(
      AmountCalculationSettingService.TAX_LINE_SIGNED_REMAINDER,
      setting.TaxLineAllocationMethod__c
    );
    System.assertEquals(RoundingMode.DOWN, AmountCalculationSettingService.taxRoundingMode());
    System.assertEquals(
      AmountCalculationSettingService.QUANTITY_HALF_UP_2,
      setting.QuantityUnitPriceRoundingMode__c
    );
    System.assertEquals(
      AmountCalculationSettingService.AMOUNT_HALF_UP_0,
      setting.AmountRoundingMode__c
    );
    System.assertEquals(2, AmountCalculationSettingService.quantityUnitPriceScale());
    System.assertEquals(
      RoundingMode.HALF_UP,
      AmountCalculationSettingService.quantityUnitPriceRoundingMode()
    );
    System.assertEquals(0, AmountCalculationSettingService.amountScale());
    System.assertEquals(
      RoundingMode.HALF_UP,
      AmountCalculationSettingService.amountRoundingMode()
    );
    System.assertEquals(
      1.23,
      AmountCalculationSettingService.roundQuantityUnitPrice(1.234)
    );
    System.assertEquals(
      100,
      AmountCalculationSettingService.roundAmount(100.4)
    );
  }

  @IsTest
  static void requireOrgDefault_missingIsErrorAndNullRoundStaysNull() {
    AmountCalculationSettingService.clearCache();
    AmountCalculationSettingService.testMissingOrgDefault = true;
    Boolean thrown = false;
    try {
      AmountCalculationSettingService.requireOrgDefault();
    } catch (AmountCalculationSettingService.SettingException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains('OrgDefault'),
        'Core 第11.9節・第1.1.10節: レコードが無いなら四捨五入へ落とさない'
      );
    } finally {
      AmountCalculationSettingService.testMissingOrgDefault = false;
      AmountCalculationSettingService.clearCache();
    }
    System.assertEquals(true, thrown);
    System.assertEquals(
      null,
      AmountCalculationSettingService.roundQuantityUnitPrice(null)
    );
    System.assertEquals(null, AmountCalculationSettingService.roundAmount(null));
  }
}
