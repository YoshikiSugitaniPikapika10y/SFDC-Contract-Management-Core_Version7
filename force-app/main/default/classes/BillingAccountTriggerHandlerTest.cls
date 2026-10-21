@IsTest
private class BillingAccountTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void update_withoutOrderedUsage_succeeds() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createBillingAccount('No Ordered BA');

      billingAccount.BillingEmailTo__c = ContractTestDataFactory.TENANT_BILLING_EMAIL_CC;
      update billingAccount;

      BillingAccount__c updated = [
        SELECT BillingEmailTo__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      System.assertEquals(
        ContractTestDataFactory.TENANT_BILLING_EMAIL_CC,
        updated.BillingEmailTo__c,
        'Core 第3.3節: 受注参照が無い請求アカウントは保存できる'
      );
    }
  }

  @IsTest
  static void insert_blankKey_fillsEighteenDigitId() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createBillingAccount('Blank Key BA');

      BillingAccount__c stored = [
        SELECT BillingAccountKey__c, HasReference__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      System.assertEquals(
        String.valueOf(stored.Id),
        stored.BillingAccountKey__c,
        'Core 第3.3.1節: キーが空なら Id を入れる'
      );
      System.assertEquals(false, stored.HasReference__c);
    }
  }

  @IsTest
  static void insert_trimsProvidedKey() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Trim Key Acct');
      BillingAccount__c billingAccount = new BillingAccount__c(
        Name = 'Trim Key BA',
        Account__c = account.Id,
        BillingAccountKey__c = '  BA-TRIM-1  ',
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = ContractTestDataFactory.TENANT_BILLING_EMAIL_TO,
        InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
        InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
        InvoiceDateDayOfMonth__c = 25,
        InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
        PaymentTermMonthOffset__c = 0,
        PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE
      );
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;

      BillingAccount__c stored = [
        SELECT BillingAccountKey__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      System.assertEquals('BA-TRIM-1', stored.BillingAccountKey__c);
    }
  }

  @IsTest
  static void update_rejectsKeyChange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createBillingAccount('Key Change BA');
      billingAccount.BillingAccountKey__c = 'CHANGED';
      Boolean thrown = false;
      try {
        update billingAccount;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains(BillingAccountKeyService.KEY_CHANGE_MESSAGE),
          'Core 第3.3.1節: 請求アカウントキーは作成後に変更できない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void update_rejectsHasReferenceChange() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createBillingAccount(
        'HasRef Change BA'
      );
      billingAccount.HasReference__c = true;
      Boolean thrown = false;
      try {
        update billingAccount;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage()
            .contains(BillingAccountKeyService.HAS_REFERENCE_CHANGE_MESSAGE),
          'Core 第3.3節: 参照ありは利用者が変更できない'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void serviceInsert_setsHasReference() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createBillingAccount(
        'HasRef Service BA'
      );
      insert new ContractService__c(
        Name = 'HasRef Service',
        Account__c = billingAccount.Account__c,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );

      BillingAccount__c stored = [
        SELECT HasReference__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      System.assertEquals(true, stored.HasReference__c);
    }
  }

  @IsTest
  static void update_withOrderedUsage_succeedsWithoutConfirmGate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createOrderedBillingAccount();

      billingAccount.BillingEmailTo__c = ContractTestDataFactory.TENANT_BILLING_EMAIL_BCC;
      update billingAccount;

      BillingAccount__c updated = [
        SELECT BillingEmailTo__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      System.assertEquals(
        ContractTestDataFactory.TENANT_BILLING_EMAIL_BCC,
        updated.BillingEmailTo__c,
        'Core 第3.3節: 受注で使っていてもマスタの宛先は保存できる'
      );
    }
  }

  @IsTest
  static void update_leavesExistingInvoiceSnapshot() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c billingAccount = createBillingAccount(
        'Snapshot Stay BA'
      );
      billingAccount = [
        SELECT
          Id,
          Account__c,
          BillingAccountKey__c,
          BillingAddressee__c,
          BillingEmailTo__c,
          BillingEmailCc__c,
          BillingEmailBcc__c,
          InvoiceDeliveryMethod__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      ContractService__c service = new ContractService__c(
        Name = 'Snapshot Stay Service',
        Account__c = billingAccount.Account__c,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      ContractTestDataFactory.applyRequiredFields(service);
      insert service;
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Snapshot Stay History',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ESTIMATE,
        Version__c = 1
      );
      ContractTestDataFactory.applyRequiredFields(history);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(
        history,
        billingAccount.Account__c
      );
      insert history;

      Invoice__c invoice = new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        BillingAccountSnapShot__c = billingAccount.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        PaymentScheduledDate__c = Date.newInstance(2026, 6, 30),
        BillingAddresseeSnapShot__c = billingAccount.BillingAddressee__c,
        BillingEmailToSnapShot__c = billingAccount.BillingEmailTo__c,
        BillingEmailCcSnapShot__c = billingAccount.BillingEmailCc__c,
        BillingEmailBccSnapShot__c = billingAccount.BillingEmailBcc__c,
        InvoiceDeliveryMethodSnapShot__c = billingAccount.InvoiceDeliveryMethod__c,
        BillingAccountKeySnapShot__c = billingAccount.BillingAccountKey__c
      );
      ContractTestDataFactory.applyRequiredFields(invoice);
      ContractTestDataFactory.applyInvoiceInsertSeedStatuses(invoice);
      insert invoice;

      String addressee = billingAccount.BillingAddressee__c;
      String emailTo = billingAccount.BillingEmailTo__c;
      String emailCc = billingAccount.BillingEmailCc__c;
      String emailBcc = billingAccount.BillingEmailBcc__c;
      String delivery = billingAccount.InvoiceDeliveryMethod__c;
      String key = billingAccount.BillingAccountKey__c;

      billingAccount.BillingAddressee__c = '更新後の宛名';
      billingAccount.BillingEmailTo__c = 'moved-to@example.com';
      billingAccount.BillingEmailCc__c = 'moved-cc@example.com';
      billingAccount.BillingEmailBcc__c = 'moved-bcc@example.com';
      billingAccount.InvoiceDeliveryMethod__c = InvoiceDeliveryMethodService.POST;
      update billingAccount;

      BillingAccount__c master = [
        SELECT BillingAddressee__c, BillingEmailTo__c, InvoiceDeliveryMethod__c
        FROM BillingAccount__c
        WHERE Id = :billingAccount.Id
      ];
      System.assertEquals('更新後の宛名', master.BillingAddressee__c);
      System.assertEquals('moved-to@example.com', master.BillingEmailTo__c);
      System.assertEquals(
        InvoiceDeliveryMethodService.POST,
        master.InvoiceDeliveryMethod__c
      );

      Invoice__c stored = [
        SELECT
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c,
          BillingEmailCcSnapShot__c,
          BillingEmailBccSnapShot__c,
          InvoiceDeliveryMethodSnapShot__c,
          BillingAccountKeySnapShot__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        addressee,
        stored.BillingAddresseeSnapShot__c,
        'Core 第3.3.5節: 反映していない既存請求の宛名はマスタ更新後も残る'
      );
      System.assertEquals(
        emailTo,
        stored.BillingEmailToSnapShot__c,
        'Core 第3.3.5節: 反映していない既存請求のToはマスタ更新後も残る'
      );
      System.assertEquals(emailCc, stored.BillingEmailCcSnapShot__c);
      System.assertEquals(emailBcc, stored.BillingEmailBccSnapShot__c);
      System.assertEquals(
        delivery,
        stored.InvoiceDeliveryMethodSnapShot__c,
        'Core 第3.3.5節・第3.3.7節: 反映していない既存請求の届け方はマスタ更新後も残る'
      );
      System.assertEquals(key, stored.BillingAccountKeySnapShot__c);
    }
  }

  @IsTest
  static void insert_rejectsExtraInvoiceDateFieldsForSameDay() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount(
        'SameDay Extra Account'
      );
      BillingAccount__c billingAccount = new BillingAccount__c(
        Name = 'SameDay Extra',
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = ContractTestDataFactory.TENANT_BILLING_EMAIL_TO
      );
      ContractTestDataFactory.applySameDayBilling(billingAccount);
      ContractTestDataFactory.applyPaymentMonthEnd(billingAccount, 0);
      billingAccount.InvoiceDateDayOfMonth__c = 15;
      Boolean rejected = false;
      try {
        insert billingAccount;
      } catch (DmlException ex) {
        rejected = true;
        System.assert(ex.getMessage().contains('指定日'), ex.getMessage());
      }
      System.assertEquals(
        true,
        rejected,
        'Core 第7.2節: 入らない項目は空にする。入っている場合は保存時に拒否する'
      );
    }
  }

  private static BillingAccount__c createBillingAccount(String name) {
    Account account = ContractTestDataFactory.insertAccount(name + ' Account');
    BillingAccount__c billingAccount = ContractTestDataFactory.insertBillingAccount(
      account.Id
    );
    return billingAccount;
  }

  private static BillingAccount__c createOrderedBillingAccount() {
    BillingAccount__c billingAccount = createBillingAccount('Ordered BA');
    ContractService__c service = new ContractService__c(
      Name = 'Ordered BA Service',
      Account__c = billingAccount.Account__c,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    ContractTestDataFactory.applyRequiredFields(service);
    insert service;

    Date cancelDate = Date.newInstance(2026, 6, 1);
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Ordered BA Cancel',
      ContractService__c = service.Id,
      Type__c = ContractDomainConstants.HISTORY_TYPE_CANCEL,
      historystatus__c = ContractDomainConstants.HISTORY_STATUS_ORDERED,
      Version__c = 1,
      CurrentTermStartDate__c = cancelDate,
      CurrentTermEndDate__c = cancelDate,
      EffectiveDate__c = cancelDate,
      ApplicationDate__c = cancelDate
    );
    ContractTestDataFactory.applyEstimateOrderedOpportunity(
      history,
      billingAccount.Account__c
    );
    ContractTestDataFactory.applyRequiredFields(history);
    insert history;
    return billingAccount;
  }
}
