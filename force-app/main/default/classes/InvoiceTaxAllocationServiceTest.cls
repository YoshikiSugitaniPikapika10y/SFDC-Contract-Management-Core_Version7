@IsTest
private class InvoiceTaxAllocationServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void allocateOnConfirm_signedLargestRemainder() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Account account = ContractTestDataFactory.insertAccount('Tax Alloc Acct');
      BillingAccount__c billingAccount = new BillingAccount__c(
        Account__c = account.Id,
        BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
        BillingEmailTo__c = 'to@example.com',
              InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
              InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
              InvoiceDateDayOfMonth__c = 1,
              InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
        PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
        PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
        PaymentTermMonthOffset__c = 0,
        PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
      ContractTestDataFactory.applyRequiredFields(billingAccount);
      insert billingAccount;

      ContractService__c service = new ContractService__c(
        Name = 'Tax Alloc Service',
        Account__c = account.Id,
        BiilingAcccount__c = billingAccount.Id,
        TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
      );
      insert service;

      ContractHistory__c history = new ContractHistory__c(
        Name = 'Tax Alloc History',
        ContractService__c = service.Id,
        Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
        historystatus__c = ContractDomainConstants.HISTORY_STATUS_ORDERED,
        Version__c = 1
      );
      insert history;

      Invoice__c invoice = new Invoice__c(
        ContractService__c = service.Id,
        ContractHistory__c = history.Id,
        InvoiceDate__c = Date.newInstance(2026, 6, 1),
        Amount__c = 1000,
        TaxAmount__c = 100
      );
      insert invoice;
      insert new List<InvoiceLine__c>{
        new InvoiceLine__c(Invoice__c = invoice.Id, Amount__c = 600),
        new InvoiceLine__c(Invoice__c = invoice.Id, Amount__c = 400)
      };

      Test.startTest();
      InvoiceTaxAllocationService.allocateOnConfirm(invoice);
      Test.stopTest();

      System.assertEquals('DOWN', invoice.AppliedTaxRoundingMode__c);

      List<InvoiceLine__c> lines = [
        SELECT Amount__c, AllocatedTaxAmount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoice.Id
        ORDER BY Amount__c DESC
      ];
      System.assertEquals(2, lines.size());
      Decimal taxSum = 0;
      for (InvoiceLine__c line : lines) {
        taxSum += line.AllocatedTaxAmount__c;
      }
      System.assertEquals(100, taxSum);
      System.assertEquals(60, lines[0].AllocatedTaxAmount__c);
      System.assertEquals(40, lines[1].AllocatedTaxAmount__c);
    }
  }

  @IsTest
  static void allocateOnConfirm_distributesRemainderByLargestFraction() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertAllocationInvoice('Remainder Alloc', 10);
      insert new List<InvoiceLine__c>{
        new InvoiceLine__c(Invoice__c = invoice.Id, Amount__c = 1),
        new InvoiceLine__c(Invoice__c = invoice.Id, Amount__c = 1),
        new InvoiceLine__c(Invoice__c = invoice.Id, Amount__c = 1)
      };

      Test.startTest();
      InvoiceTaxAllocationService.allocateOnConfirm(invoice);
      Test.stopTest();

      List<InvoiceLine__c> lines = [
        SELECT AllocatedTaxAmount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoice.Id
        ORDER BY Id
      ];
      System.assertEquals(3, lines.size());
      Decimal taxSum = 0;
      Integer extraCount = 0;
      for (InvoiceLine__c line : lines) {
        taxSum += line.AllocatedTaxAmount__c;
        if (line.AllocatedTaxAmount__c == 4) {
          extraCount++;
        } else {
          System.assertEquals(3, line.AllocatedTaxAmount__c);
        }
      }
      System.assertEquals(10, taxSum);
      System.assertEquals(1, extraCount);
      System.assertEquals(4, lines[0].AllocatedTaxAmount__c);
    }
  }

  @IsTest
  static void allocateOnConfirm_signedRemainderGoesToLargerSignedFraction() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertAllocationInvoice('Signed Rem', -1);
      insert new List<InvoiceLine__c>{
        new InvoiceLine__c(Invoice__c = invoice.Id, Amount__c = -7),
        new InvoiceLine__c(Invoice__c = invoice.Id, Amount__c = -11)
      };

      Test.startTest();
      InvoiceTaxAllocationService.allocateOnConfirm(invoice);
      Test.stopTest();

      List<InvoiceLine__c> lines = [
        SELECT Amount__c, AllocatedTaxAmount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoice.Id
        ORDER BY Id
      ];
      System.assertEquals(2, lines.size());
      System.assertEquals(
        -1,
        lines[0].AllocatedTaxAmount__c + lines[1].AllocatedTaxAmount__c,
        'Core 第11.9節: 明細配分合計をヘッダ税額と一致させる'
      );
      System.assertEquals(
        -1,
        lines[0].AllocatedTaxAmount__c,
        'Core 第11.9節: 符号付き剰余の大きい行（-7）へ-1を配る'
      );
      System.assertEquals(0, lines[1].AllocatedTaxAmount__c);
    }
  }

  @IsTest
  static void allocateOnConfirm_rejectsMissingTaxAndLineAmount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c missingTax = insertAllocationInvoice('Missing Tax', null);
      insert new InvoiceLine__c(Invoice__c = missingTax.Id, Amount__c = 1000);
      Boolean taxRejected = false;
      try {
        InvoiceTaxAllocationService.allocateOnConfirm(missingTax);
      } catch (InvoiceTaxAllocationService.TaxAllocationException ex) {
        taxRejected = true;
        System.assertEquals(
          InvoiceTaxAllocationService.MISSING_TAX_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, taxRejected);

      Invoice__c missingLine = insertAllocationInvoice('Missing Line Amt', 100);
      insert new InvoiceLine__c(Invoice__c = missingLine.Id, Amount__c = null);
      Boolean lineRejected = false;
      try {
        InvoiceTaxAllocationService.allocateOnConfirm(missingLine);
      } catch (InvoiceTaxAllocationService.TaxAllocationException ex) {
        lineRejected = true;
        System.assertEquals(
          InvoiceTaxAllocationService.MISSING_LINE_AMOUNT_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, lineRejected);

      Invoice__c noLines = insertAllocationInvoice('No Lines', 100);
      Boolean emptyRejected = false;
      try {
        InvoiceTaxAllocationService.allocateOnConfirm(noLines);
      } catch (InvoiceTaxAllocationService.TaxAllocationException ex) {
        emptyRejected = true;
        System.assertEquals(
          InvoiceTaxAllocationService.EMPTY_LINES_TAX_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, emptyRejected);
    }
  }

  @IsTest
  static void allocateOnConfirm_readsTaxWhenCallerDidNotQueryIt() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = insertAllocationInvoice('Unqueried Tax', 100);
      insert new InvoiceLine__c(Invoice__c = invoice.Id, Amount__c = 1000);
      Invoice__c thin = [SELECT Id FROM Invoice__c WHERE Id = :invoice.Id];

      Test.startTest();
      InvoiceTaxAllocationService.allocateOnConfirm(thin);
      Test.stopTest();

      InvoiceLine__c line = [
        SELECT AllocatedTaxAmount__c
        FROM InvoiceLine__c
        WHERE Invoice__c = :invoice.Id
      ];
      System.assertEquals(100, line.AllocatedTaxAmount__c);
      System.assertEquals('DOWN', thin.AppliedTaxRoundingMode__c);
    }
  }

  private static Invoice__c insertAllocationInvoice(String label, Decimal tax) {
    Account account = ContractTestDataFactory.insertAccount(label + ' Acct');
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'to@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 1,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;

    ContractService__c service = new ContractService__c(
      Name = label + ' Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    insert service;

    ContractHistory__c history = new ContractHistory__c(
      Name = label + ' History',
      ContractService__c = service.Id,
      Type__c = ContractDomainConstants.HISTORY_TYPE_NEW,
      historystatus__c = ContractDomainConstants.HISTORY_STATUS_ORDERED,
      Version__c = 1
    );
    insert history;

    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = tax
    );
    insert invoice;
    return invoice;
  }
}
