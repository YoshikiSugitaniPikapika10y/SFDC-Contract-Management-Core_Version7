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
}
