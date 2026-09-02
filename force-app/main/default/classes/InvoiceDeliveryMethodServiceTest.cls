@IsTest
private class InvoiceDeliveryMethodServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void assertRequiredOnBillingAccount_pdfOnlyAllowsBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfOnly';
      update setting;
      ContractDocumentSettingService.clearCache();

      Account account = ContractTestDataFactory.insertAccount('Delivery PdfOnly');
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'pdfonly@example.com',
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
        InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
        InvoiceDateDayOfMonth__c = 1,
        InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
        PaymentTermMonthOffset__c = 0,
        PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;
      System.assertEquals(
        null,
        [
          SELECT InvoiceDeliveryMethod__c
          FROM BillingAccount__c
          WHERE Id = :billingAccount.Id
        ]
        .InvoiceDeliveryMethod__c,
        'Core 第3.3.7節: PDFのみは届け方空でよい'
      );
    }
  }

  @IsTest
  static void assertRequiredOnBillingAccount_pdfAndEmailRejectsBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.InvoiceSendMode__c = 'PdfAndEmail';
      update setting;
      ContractDocumentSettingService.clearCache();

      Account account = ContractTestDataFactory.insertAccount('Delivery PdfMail');
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'pdfmail@example.com',
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
        InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
        InvoiceDateDayOfMonth__c = 1,
        InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
        PaymentTermMonthOffset__c = 0,
        PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      Boolean thrown = false;
      try {
        insert billingAccount;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(
              InvoiceDeliveryMethodService.REQUIRED_ON_BILLING_ACCOUNT_MESSAGE
            ),
          'Core 第3.3.7節: PdfAndEmail の請求アカウント保存は届け方空を拒否する'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void allowsEmailSend_requiresOrgModeAndEmailSnapshot() {
    Invoice__c invoice = new Invoice__c(
      InvoiceDeliveryMethodSnapShot__c = InvoiceDeliveryMethodService.EMAIL
    );
    ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
    setting.InvoiceSendMode__c = 'PdfOnly';
    update setting;
    ContractDocumentSettingService.clearCache();
    System.assertEquals(
      false,
      InvoiceDeliveryMethodService.allowsEmailSend(invoice),
      'Core 第7.10節: PDFのみでは送付しない'
    );

    setting.InvoiceSendMode__c = 'PdfAndEmail';
    update setting;
    ContractDocumentSettingService.clearCache();
    System.assertEquals(
      true,
      InvoiceDeliveryMethodService.allowsEmailSend(invoice),
      'Core 第7.10節: PdfAndEmail かつ Email なら送付可'
    );

    invoice.InvoiceDeliveryMethodSnapShot__c = InvoiceDeliveryMethodService.POST;
    System.assertEquals(
      false,
      InvoiceDeliveryMethodService.allowsEmailSend(invoice),
      'Core 第7.10節: 郵送では送付しない'
    );
    invoice.InvoiceDeliveryMethodSnapShot__c = null;
    System.assertEquals(
      false,
      InvoiceDeliveryMethodService.allowsEmailSend(invoice),
      'Core 第7.10節: 空をメールとみなさない'
    );
  }

  @IsTest
  static void assertRequiredOnConfirm_pdfAndEmailRejectsBlankSnapshot() {
    ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
    setting.InvoiceSendMode__c = 'PdfAndEmail';
    update setting;
    ContractDocumentSettingService.clearCache();
    Boolean thrown = false;
    try {
      InvoiceDeliveryMethodService.assertRequiredOnConfirm(new Invoice__c());
    } catch (InvoiceDeliveryMethodService.DeliveryMethodException ex) {
      thrown = true;
      System.assertEquals(
        InvoiceDeliveryMethodService.REQUIRED_ON_CONFIRM_MESSAGE,
        ex.getMessage(),
        'Core 第7.9.1節: PdfAndEmail の確定は届け方スナップショット空を拒否する'
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void confirmAndSend_emailSnapshotOnlyWhenPdfAndEmail() {
    InvoiceDeliveryMethodService.assertRequiredOnBillingAccount(null);
    System.assertEquals(
      false,
      InvoiceDeliveryMethodService.allowsEmailSend(null),
      'Core 第7.10節: 請求が無ければ送付しない'
    );

    ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
    setting.InvoiceSendMode__c = 'PdfAndEmail';
    update setting;
    ContractDocumentSettingService.clearCache();

    Invoice__c emailInvoice = new Invoice__c(
      InvoiceDeliveryMethodSnapShot__c = InvoiceDeliveryMethodService.EMAIL
    );
    InvoiceDeliveryMethodService.assertRequiredOnConfirm(emailInvoice);
    System.assertEquals(
      true,
      InvoiceDeliveryMethodService.allowsEmailSend(emailInvoice)
    );

    Invoice__c noneInvoice = new Invoice__c(
      InvoiceDeliveryMethodSnapShot__c = InvoiceDeliveryMethodService.NONE
    );
    InvoiceDeliveryMethodService.assertRequiredOnConfirm(noneInvoice);
    System.assertEquals(
      false,
      InvoiceDeliveryMethodService.allowsEmailSend(noneInvoice),
      'Core 第7.10節: 送付なしでは送付しない'
    );
  }
}
