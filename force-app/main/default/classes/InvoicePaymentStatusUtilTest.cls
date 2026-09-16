@IsTest
private class InvoicePaymentStatusUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void resolveStatusAmounts_exclusiveBuckets() {
    Decimal amount = 1000;

    Invoice__c openInvoice = new Invoice__c(
      Amount__c = amount,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT
    );
    InvoicePaymentStatusUtil.StatusAmounts openStatus = InvoicePaymentStatusUtil.resolveStatusAmounts(
      openInvoice,
      amount
    );
    System.assertEquals(1000, openStatus.openAmount);
    System.assertEquals(0, openStatus.integratedAmount);
    System.assertEquals(0, openStatus.clearedAmount);

    Invoice__c invoiced = new Invoice__c(
      Amount__c = amount,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED
    );
    InvoicePaymentStatusUtil.StatusAmounts invoicedStatus = InvoicePaymentStatusUtil.resolveStatusAmounts(
      invoiced,
      amount
    );
    System.assertEquals(0, invoicedStatus.openAmount);
    System.assertEquals(1000, invoicedStatus.integratedAmount);
    System.assertEquals(0, invoicedStatus.clearedAmount);

    Invoice__c partial = (Invoice__c) JSON.deserialize(
      '{"Amount__c":1000,"TaxAmount__c":100,"TaxInclusiveAmount__c":1100,' +
        '"InvoicePaymentNet__c":440,"InvoiceTransactionStatus__c":"Confirmed"}',
      Invoice__c.class
    );
    InvoicePaymentStatusUtil.StatusAmounts partialStatus = InvoicePaymentStatusUtil.resolveStatusAmounts(
      partial,
      amount
    );
    System.assertEquals(0, partialStatus.openAmount);
    System.assertEquals(600, partialStatus.integratedAmount);
    System.assertEquals(400, partialStatus.clearedAmount);

    // ??????????????
    Invoice__c dateOnly = new Invoice__c(
      Amount__c = amount,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_CONFIRMED,
      PaymentClearingCompletedDate__c = Date.today()
    );
    InvoicePaymentStatusUtil.StatusAmounts dateOnlyStatus = InvoicePaymentStatusUtil.resolveStatusAmounts(
      dateOnly,
      amount
    );
    System.assertEquals(0, dateOnlyStatus.openAmount);
    System.assertEquals(1000, dateOnlyStatus.integratedAmount);
    System.assertEquals(0, dateOnlyStatus.clearedAmount);

    Invoice__c cleared = (Invoice__c) JSON.deserialize(
      '{"Amount__c":1000,"TaxAmount__c":100,"TaxInclusiveAmount__c":1100,' +
        '"InvoicePaymentNet__c":1100,"InvoiceTransactionStatus__c":"Confirmed","CollectionRefundStatus__c":"Completed"}',
      Invoice__c.class
    );
    InvoicePaymentStatusUtil.StatusAmounts clearedStatus = InvoicePaymentStatusUtil.resolveStatusAmounts(
      cleared,
      amount
    );
    System.assertEquals(0, clearedStatus.openAmount);
    System.assertEquals(0, clearedStatus.integratedAmount);
    System.assertEquals(1000, clearedStatus.clearedAmount);
  }

  @IsTest
  static void allocateLineStatusAmounts_scalesBuckets() {
    InvoicePaymentStatusUtil.StatusAmounts invoiceStatus = new InvoicePaymentStatusUtil.StatusAmounts(
      0,
      600,
      400
    );
    InvoicePaymentStatusUtil.StatusAmounts lineStatus = InvoicePaymentStatusUtil.allocateLineStatusAmounts(
      500,
      1000,
      invoiceStatus
    );
    System.assertEquals(0, lineStatus.openAmount);
    System.assertEquals(300, lineStatus.integratedAmount);
    System.assertEquals(200, lineStatus.clearedAmount);
  }

  @IsTest
  static void clearedAmount_completedUsesFull_andLineKeepsExclusiveSum() {
    Invoice__c completed = (Invoice__c) JSON.deserialize(
      '{"Amount__c":1000,"TaxInclusiveAmount__c":1100,' +
        '"InvoicePaymentNet__c":1100,"InvoiceTransactionStatus__c":"Confirmed","CollectionRefundStatus__c":"Completed"}',
      Invoice__c.class
    );
    System.assertEquals(
      1000,
      InvoicePaymentStatusUtil.resolveClearedAmount(completed, 1000),
      'Core 第8.7節: 請求金額Netと税込が一致すれば回収完了として税抜全額を消込'
    );
    System.assertEquals(
      0,
      InvoicePaymentStatusUtil.resolveClearedAmount(null, 1000)
    );
    Invoice__c zeroTaxInclusive = (Invoice__c) JSON.deserialize(
      '{"Amount__c":0,"TaxAmount__c":0,"TaxInclusiveAmount__c":0,' +
        '"InvoicePaymentNet__c":10,"InvoiceTransactionStatus__c":"Confirmed"}',
      Invoice__c.class
    );
    System.assertEquals(
      0,
      InvoicePaymentStatusUtil.resolveClearedAmount(zeroTaxInclusive, 1000),
      'Core 第8.7節: 税込0円は入出金無しでも完了側。比例配分の分母0は消込0'
    );
    InvoicePaymentStatusUtil.StatusAmounts noParent = InvoicePaymentStatusUtil.allocateLineStatusAmounts(
      500,
      0,
      new InvoicePaymentStatusUtil.StatusAmounts(0, 0, 0)
    );
    System.assertEquals(0, noParent.openAmount);
    System.assertEquals(0, noParent.integratedAmount);
    System.assertEquals(0, noParent.clearedAmount);
    InvoicePaymentStatusUtil.StatusAmounts missingInvoice = InvoicePaymentStatusUtil.allocateLineStatusAmounts(
      500,
      1000,
      null
    );
    System.assertEquals(
      500,
      missingInvoice.openAmount,
      'Core 第8.10節: 親バケットが無ければ明細税抜は請求前'
    );
  }

  @IsTest
  static void clearedAmount_nullInclusiveUsesAmountPlusTax_andClampsSigned() {
    Invoice__c emptyInclusive = (Invoice__c) JSON.deserialize(
      '{"Amount__c":1000,"TaxAmount__c":100,' +
        '"InvoicePaymentNet__c":550,"InvoiceTransactionStatus__c":"Confirmed"}',
      Invoice__c.class
    );
    System.assertEquals(
      500,
      InvoicePaymentStatusUtil.resolveClearedAmount(emptyInclusive, 1000),
      'Core 第8.7節: 税込空の分母は税抜＋税。550/1100を税抜へ比例'
    );
    InvoicePaymentStatusUtil.StatusAmounts emptyStatus = InvoicePaymentStatusUtil.resolveStatusAmounts(
      emptyInclusive,
      1000
    );
    System.assertEquals(0, emptyStatus.openAmount);
    System.assertEquals(500, emptyStatus.integratedAmount);
    System.assertEquals(500, emptyStatus.clearedAmount);

    Invoice__c overCleared = (Invoice__c) JSON.deserialize(
      '{"Amount__c":1000,"TaxAmount__c":100,"TaxInclusiveAmount__c":1100,' +
        '"InvoicePaymentNet__c":2000,"InvoiceTransactionStatus__c":"Confirmed"}',
      Invoice__c.class
    );
    System.assertEquals(
      1000,
      InvoicePaymentStatusUtil.resolveClearedAmount(overCleared, 1000),
      'Core 第8.7節: 比例結果が税抜を超えても消込は税抜までにclamp'
    );

    Invoice__c negativeOver = (Invoice__c) JSON.deserialize(
      '{"Amount__c":-1000,"TaxAmount__c":-100,"TaxInclusiveAmount__c":-1100,' +
        '"InvoicePaymentNet__c":-2000,"InvoiceTransactionStatus__c":"Confirmed"}',
      Invoice__c.class
    );
    System.assertEquals(
      -1000,
      InvoicePaymentStatusUtil.resolveClearedAmount(negativeOver, -1000),
      'Core 第8.7節: 負額は消込が税抜より負に振れても税抜までにclamp'
    );
    InvoicePaymentStatusUtil.StatusAmounts negativeStatus = InvoicePaymentStatusUtil.resolveStatusAmounts(
      negativeOver,
      -1000
    );
    System.assertEquals(0, negativeStatus.openAmount);
    System.assertEquals(0, negativeStatus.integratedAmount);
    System.assertEquals(-1000, negativeStatus.clearedAmount);
  }

  @IsTest
  static void allocateLineStatusAmounts_absorbsRoundingIntoOpen() {
    InvoicePaymentStatusUtil.StatusAmounts invoiceStatus = new InvoicePaymentStatusUtil.StatusAmounts(
      334,
      333,
      333
    );
    InvoicePaymentStatusUtil.StatusAmounts lineStatus = InvoicePaymentStatusUtil.allocateLineStatusAmounts(
      100,
      1000,
      invoiceStatus
    );
    System.assertEquals(
      34,
      lineStatus.openAmount,
      'Core 第8.10節: 明細按分の端数は請求前へ吸収する'
    );
    System.assertEquals(33, lineStatus.integratedAmount);
    System.assertEquals(33, lineStatus.clearedAmount);
    System.assertEquals(
      100,
      lineStatus.openAmount +
        lineStatus.integratedAmount +
        lineStatus.clearedAmount,
      'Core 第8.10節: 請求前＋請求済＋消込は明細税抜と一致'
    );
  }
}
