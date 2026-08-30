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
}
