@IsTest
private class InvoicePaymentLockUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void resolveLockExemptFieldNames_blankIsEmpty() {
    InvoicePaymentLockUtil.testLockExemptFieldApiNames = '  ';
    Set<String> names = InvoicePaymentLockUtil.resolveLockExemptFieldNames();
    System.assertEquals(
      true,
      names.isEmpty(),
      'Core 第11.6節: 空は追加なし'
    );
    InvoicePaymentLockUtil.testLockExemptFieldApiNames = null;
  }

  @IsTest
  static void assertExemptUpdate_rejectsAmountEvenIfListed() {
    InvoicePayment__c prior = new InvoicePayment__c(
      Amount__c = 100,
      Memo__c = 'a'
    );
    InvoicePayment__c current = new InvoicePayment__c(
      Amount__c = 200,
      Memo__c = 'a'
    );
    current.Amount__c = 200;
    InvoicePaymentLockUtil.testLockExemptFieldApiNames = 'Memo__c,Amount__c';
    Boolean thrown = false;
    try {
      InvoicePaymentLockUtil.assertExemptUpdate(prior, current);
    } catch (InvoicePaymentLockUtil.LockExemptException ex) {
      thrown = true;
      System.assertEquals(
        InvoicePaymentLockUtil.NEVER_EXEMPT_MESSAGE,
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
    InvoicePaymentLockUtil.testLockExemptFieldApiNames = null;
  }

  @IsTest
  static void assertExemptUpdate_allowsMemoOnly() {
    InvoicePayment__c prior = new InvoicePayment__c(
      Amount__c = 100,
      Memo__c = 'a'
    );
    InvoicePayment__c current = new InvoicePayment__c(
      Amount__c = 100,
      Memo__c = 'b'
    );
    InvoicePaymentLockUtil.testLockExemptFieldApiNames = '';
    InvoicePaymentLockUtil.assertExemptUpdate(prior, current);
    InvoicePaymentLockUtil.testLockExemptFieldApiNames = null;
  }

  @IsTest
  static void assertExemptUpdate_rejectsDatePurposeAndUnlisted() {
    InvoicePaymentLockUtil.testLockExemptFieldApiNames = 'Memo__c,PaymentDate__c';
    InvoicePayment__c prior = new InvoicePayment__c(
      Amount__c = 100,
      PaymentDate__c = Date.newInstance(2026, 4, 1),
      PaymentPurpose__c = 'Invoice',
      Memo__c = 'a'
    );
    InvoicePayment__c dateChanged = new InvoicePayment__c(
      Amount__c = 100,
      PaymentDate__c = Date.newInstance(2026, 4, 2),
      PaymentPurpose__c = 'Invoice',
      Memo__c = 'a'
    );
    Boolean dateThrown = false;
    try {
      InvoicePaymentLockUtil.assertExemptUpdate(prior, dateChanged);
    } catch (InvoicePaymentLockUtil.LockExemptException ex) {
      dateThrown = true;
      System.assertEquals(
        InvoicePaymentLockUtil.NEVER_EXEMPT_MESSAGE,
        ex.getMessage(),
        'Core 第8.4節・第11.6節: 日付は一覧に書いても不可'
      );
    }
    System.assertEquals(true, dateThrown);

    InvoicePayment__c purposeChanged = new InvoicePayment__c(
      Amount__c = 100,
      PaymentDate__c = Date.newInstance(2026, 4, 1),
      PaymentPurpose__c = 'NonInvoice',
      Memo__c = 'a'
    );
    Boolean purposeThrown = false;
    try {
      InvoicePaymentLockUtil.assertExemptUpdate(prior, purposeChanged);
    } catch (InvoicePaymentLockUtil.LockExemptException ex) {
      purposeThrown = true;
      System.assertEquals(
        InvoicePaymentLockUtil.NEVER_EXEMPT_MESSAGE,
        ex.getMessage(),
        'Core 第8.4節: 目的は直接更新しない'
      );
    }
    System.assertEquals(true, purposeThrown);

    InvoicePaymentLockUtil.testLockExemptFieldApiNames = 'Memo__c';
    Boolean nullThrown = false;
    try {
      InvoicePaymentLockUtil.assertExemptUpdate(null, prior);
    } catch (InvoicePaymentLockUtil.LockExemptException ex) {
      nullThrown = true;
      System.assertEquals(
        InvoicePaymentLockUtil.NOT_EXEMPT_MESSAGE,
        ex.getMessage()
      );
    }
    System.assertEquals(true, nullThrown);
    InvoicePaymentLockUtil.testLockExemptFieldApiNames = null;
  }
}
