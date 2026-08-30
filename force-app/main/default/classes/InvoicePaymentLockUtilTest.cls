@IsTest
private class InvoicePaymentLockUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void resolveLockExemptFieldNames_blankIsError() {
    InvoicePaymentLockUtil.testLockExemptFieldApiNames = '  ';
    Boolean thrown = false;
    try {
      InvoicePaymentLockUtil.resolveLockExemptFieldNames();
    } catch (InvoicePaymentLockUtil.LockExemptException ex) {
      thrown = true;
      System.assertEquals(
        InvoicePaymentLockUtil.MISSING_LOCK_EXEMPT_MESSAGE,
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
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
    InvoicePaymentLockUtil.testLockExemptFieldApiNames = 'Memo__c';
    InvoicePaymentLockUtil.assertExemptUpdate(prior, current);
    InvoicePaymentLockUtil.testLockExemptFieldApiNames = null;
  }
}
