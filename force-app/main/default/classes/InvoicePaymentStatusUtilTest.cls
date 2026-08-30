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
}
