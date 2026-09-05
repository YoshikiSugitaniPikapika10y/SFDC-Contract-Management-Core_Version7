@IsTest
private class InvoiceMergeKeyConfigServiceTest {
  @IsTest
  static void buildsStaticInvoiceAndLineKeys() {
    Id billingAccountId = fakeId(BillingAccount__c.SObjectType, 1);
    Id contractHistoryId = fakeId(ContractHistory__c.SObjectType, 2);
    Id contractProductId = fakeId(ContractProduct__c.SObjectType, 3);
    Date invoiceDate = Date.newInstance(2026, 4, 1);
    Date paymentDate = Date.newInstance(2026, 4, 30);

    InvoiceMergeKeyConfigService.InvoiceKeyInput invoiceInput = new InvoiceMergeKeyConfigService.InvoiceKeyInput();
    invoiceInput.billingAccountId = billingAccountId;
    invoiceInput.contractHistoryId = contractHistoryId;
    invoiceInput.invoiceDate = invoiceDate;
    invoiceInput.paymentScheduledDate = paymentDate;

    InvoiceMergeKeyConfigService.LineKeyInput lineInput = new InvoiceMergeKeyConfigService.LineKeyInput();
    lineInput.contractProductId = contractProductId;
    lineInput.unitPrice = 1000;
    lineInput.quantity = 2;

    Test.startTest();
    String invoiceKey = InvoiceMergeKeyConfigService.buildInvoiceBucketKey(
      invoiceInput
    );
    String lineKey = InvoiceMergeKeyConfigService.buildLineBucketKey(lineInput);
    InvoiceMergeKeyConfigService.validateActiveDefinitions();
    Test.stopTest();

    System.assertEquals(
      'INV|BA=' +
        String.valueOf(billingAccountId) +
        '|CH=' +
        String.valueOf(contractHistoryId) +
        '|DT=2026-04-01|PD=2026-04-30',
      invoiceKey
    );
    System.assertEquals(
      'LINE|CP=' + String.valueOf(contractProductId) + '|UP=1000|Q=2',
      lineKey
    );
  }

  @IsTest
  static void buildLineBucketKeyFromProduct_usesProductFields() {
    Id contractProductId = fakeId(ContractProduct__c.SObjectType, 3);
    InvoiceProduct__c product = new InvoiceProduct__c(
      ContractProduct__c = contractProductId,
      UnitPrice__c = 500,
      Quantity__c = 3
    );

    String key = InvoiceMergeKeyConfigService.buildLineBucketKeyFromProduct(
      product
    );
    System.assertEquals(
      'LINE|CP=' + String.valueOf(contractProductId) + '|UP=500|Q=3',
      key
    );
    System.assertEquals(
      'LINE|CP=|UP=0|Q=0',
      InvoiceMergeKeyConfigService.buildLineBucketKeyFromProduct(null)
    );
  }

  @IsTest
  static void buildInvoiceBucketKey_doesNotCrossVersion() {
    Id billingAccountId = fakeId(BillingAccount__c.SObjectType, 1);
    Id historyA = fakeId(ContractHistory__c.SObjectType, 2);
    Id historyB = fakeId(ContractHistory__c.SObjectType, 3);
    Date invoiceDate = Date.newInstance(2026, 4, 1);
    Date paymentDate = Date.newInstance(2026, 4, 30);
    String keyA = InvoiceMergeKeyConfigService.buildInvoiceBucketKey(
      billingAccountId,
      historyA,
      invoiceDate,
      paymentDate
    );
    String keyB = InvoiceMergeKeyConfigService.buildInvoiceBucketKey(
      billingAccountId,
      historyB,
      invoiceDate,
      paymentDate
    );
    System.assertEquals(
      false,
      keyA == keyB,
      'Core 第7.3節: 契約履歴、すなわち Version をまたいで集約しない'
    );
    System.assertEquals(
      keyA,
      InvoiceMergeKeyConfigService.buildInvoiceBucketKey(
        billingAccountId,
        historyA,
        invoiceDate,
        paymentDate
      ),
      'Core 第7.3節: 請求アカウント・契約履歴・請求日・入金予定日が同じなら1枚へ集約する'
    );
  }

  @IsTest
  static void buildLineBucketKey_ignoresUnitAndTrailingZeros() {
    Id contractProductId = fakeId(ContractProduct__c.SObjectType, 3);
    Id productId = fakeId(Product2.SObjectType, 4);
    System.assertEquals(
      InvoiceMergeKeyConfigService.buildLineBucketKey(
        contractProductId,
        1000,
        2,
        'ID',
        productId
      ),
      InvoiceMergeKeyConfigService.buildLineBucketKey(
        contractProductId,
        1000.00,
        2,
        '式',
        null
      ),
      'Core 第7.3節: 同じ見積商品・単価・数量。コピー定義の顧客項目では分けない'
    );
  }

  @IsTest
  static void buildInvoiceBucketKey_nullInput_usesEmptyParts() {
    System.assertEquals(
      'INV|BA=|CH=|DT=|PD=',
      InvoiceMergeKeyConfigService.buildInvoiceBucketKey(
        (InvoiceMergeKeyConfigService.InvoiceKeyInput) null
      ),
      'Core 第7.3節: 入力が空でもキー構成は BA・CH・DT・PD の順'
    );
    System.assertEquals(
      'LINE|CP=|UP=0|Q=0',
      InvoiceMergeKeyConfigService.buildLineBucketKey(
        (InvoiceMergeKeyConfigService.LineKeyInput) null
      ),
      'Core 第7.3節: 入力が空でもキー構成は CP・単価・数量'
    );
  }

  private static Id fakeId(Schema.SObjectType typeName, Integer n) {
    String key = String.valueOf(n);
    return Id.valueOf(
      String.valueOf(typeName.getDescribe().getKeyPrefix()) +
        '0'.repeat(12 - key.length()) +
        key
    );
  }
}
