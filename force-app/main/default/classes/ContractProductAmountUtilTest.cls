@IsTest
private class ContractProductAmountUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void calculateUnsignedAmount_recurringMultipliesByMonthlyCycles() {
    Decimal amount = ContractProductAmountUtil.calculateUnsignedAmount(
      1,
      12000,
      ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Date.newInstance(2026, 4, 1),
      Date.newInstance(2027, 3, 31)
    );

    System.assertEquals(144000, amount);
  }

  @IsTest
  static void calculateUnsignedAmount_oneTimeUsesQuantityTimesUnitPrice() {
    Decimal amount = ContractProductAmountUtil.calculateUnsignedAmount(
      2,
      5000,
      ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
      Date.newInstance(2026, 4, 1),
      Date.newInstance(2027, 3, 31)
    );

    System.assertEquals(10000, amount);
  }

  @IsTest
  static void yenFromQuantityUnitPrice_matchesIntegerScaleHalfUp() {
    // FE: toScaledInt(1.15,2)=115, toScaledInt(1.15,2)=115 → 13225/10000 → 1
    System.assertEquals(
      1,
      ContractProductAmountUtil.yenFromQuantityUnitPrice(1.15, 1.15, 1)
    );
    // FE: 3333*3333*12 / 10000 = 13330.6668 → 13331
    System.assertEquals(
      13331,
      ContractProductAmountUtil.yenFromQuantityUnitPrice(33.33, 33.33, 12)
    );
    // FE: 123*568*7 / 10000 = 48.9288 → 49（入力は第2位へ丸めてから）
    System.assertEquals(
      49,
      ContractProductAmountUtil.yenFromQuantityUnitPrice(1.234, 5.678, 7)
    );
  }

  @IsTest
  static void calculateUnsignedAmount_recurringUsesIntegerScaleNotBulkDecimal() {
    Decimal amount = ContractProductAmountUtil.calculateUnsignedAmount(
      33.33,
      33.33,
      ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Date.newInstance(2026, 4, 1),
      Date.newInstance(2027, 3, 31)
    );

    System.assertEquals(13331, amount);
  }

  @IsTest
  static void applyProductTypeSign_originalIsNegative() {
    System.assertEquals(
      -144000,
      ContractProductAmountUtil.applyProductTypeSign(144000, 'Original')
    );
  }

  @IsTest
  static void applyProductTypeSign_originalNegatesDiscountToPositive() {
    System.assertEquals(
      36000,
      ContractProductAmountUtil.applyProductTypeSign(-36000, 'Original')
    );
  }

  @IsTest
  static void applyProductTypeSign_remakeKeepsSignedAmount() {
    System.assertEquals(
      -36000,
      ContractProductAmountUtil.applyProductTypeSign(-36000, 'Remake')
    );
  }

  @IsTest
  static void calculateSignedAmount_originalIsNegative() {
    ContractProduct__c product = new ContractProduct__c(
      Quantity__c = 1,
      UnitPrice__c = 12000,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      Type__c = 'Original'
    );

    System.assertEquals(
      -144000,
      ContractProductAmountUtil.calculateSignedAmount(
        product,
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      )
    );
  }

  @IsTest
  static void calculateSignedAmount_originalDiscountBecomesPositive() {
    ContractProduct__c product = new ContractProduct__c(
      Quantity__c = 1,
      UnitPrice__c = -3000,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      Type__c = 'Original'
    );

    System.assertEquals(
      36000,
      ContractProductAmountUtil.calculateSignedAmount(
        product,
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      )
    );
  }

  @IsTest
  static void calculateSignedAmount_remakeDiscountStaysNegative() {
    ContractProduct__c product = new ContractProduct__c(
      Quantity__c = 1,
      UnitPrice__c = -3000,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      Type__c = 'Remake',
      Amount__c = -36000
    );

    System.assertEquals(
      -36000,
      ContractProductAmountUtil.calculateSignedAmount(
        product,
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING
      ),
      '値引き Remake は Amount が負でも符号を強制しない'
    );
  }

  @IsTest
  static void unsignedAndSigned_rejectUncomputableAndFlipOriginal() {
    System.assertEquals(
      null,
      ContractProductAmountUtil.calculateSignedAmount(null, null),
      'Core 第4.6節: 行が無ければ金額を計算できない'
    );
    System.assertEquals(
      null,
      ContractProductAmountUtil.yenFromQuantityUnitPrice(1, null, 1)
    );
    System.assertEquals(
      0,
      ContractProductAmountUtil.calculateUnsignedAmount(
        0,
        12000,
        ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Date.newInstance(2026, 4, 1),
        Date.newInstance(2027, 3, 31)
      ),
      'Core 第4.6節: 数量が0なら税抜は0'
    );
    System.assertEquals(
      null,
      ContractProductAmountUtil.calculateUnsignedAmount(
        1,
        12000,
        ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Date.newInstance(2026, 4, 1),
        null
      ),
      'Core 第4.6節: 継続課金は期間からサイクル数を取る。期間が無ければ計算できない'
    );
    System.assertEquals(
      null,
      ContractProductAmountUtil.applyProductTypeSign(null, 'Original')
    );
    ContractProduct__c product = new ContractProduct__c(
      Quantity__c = 2,
      UnitPrice__c = 5000,
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      Type__c = 'New'
    );
    System.assertEquals(
      10000,
      ContractProductAmountUtil.calculateSignedAmount(
        product,
        ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME
      ),
      'Core 第4.6節: 一回課金は数量×単価。行の課金形態が空なら引数を使う'
    );
  }
}
