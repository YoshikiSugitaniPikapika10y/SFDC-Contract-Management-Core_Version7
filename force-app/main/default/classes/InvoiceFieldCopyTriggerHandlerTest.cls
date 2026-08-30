@IsTest
private class InvoiceFieldCopyTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void invoiceBeforeInsert_fillsBlankBillingSnapshots() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Fill');
      Invoice__c invoice = new Invoice__c(
        ContractHistory__c = fixture.history.Id,
        ContractService__c = fixture.service.Id,
        InvoiceDate__c = Date.today(),
        Amount__c = 1000
      );

      Test.startTest();
      insert invoice;
      Test.stopTest();

      Invoice__c loaded = [
        SELECT
          BillingAccountSnapShot__c,
          BillingAddresseeSnapShot__c,
          BillingEmailToSnapShot__c,
          PaymentTermMethodSnapShot__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        fixture.billingAccount.Id,
        loaded.BillingAccountSnapShot__c
      );
      System.assertEquals(
        'トリガ宛名 御中',
        loaded.BillingAddresseeSnapShot__c
      );
      System.assertEquals('trig@example.com', loaded.BillingEmailToSnapShot__c);
      System.assertEquals(
        BillingScheduleService.METHOD_MONTH_OFFSET,
        loaded.PaymentTermMethodSnapShot__c
      );
    }
  }

  @IsTest
  static void invoiceBeforeInsert_keepsPrefilledSnapshot() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Keep');
      Invoice__c invoice = new Invoice__c(
        ContractHistory__c = fixture.history.Id,
        ContractService__c = fixture.service.Id,
        InvoiceDate__c = Date.today(),
        Amount__c = 1000,
        BillingAddresseeSnapShot__c = '手入力宛名'
      );

      Test.startTest();
      insert invoice;
      Test.stopTest();

      Invoice__c loaded = [
        SELECT BillingAddresseeSnapShot__c, BillingEmailToSnapShot__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals('手入力宛名', loaded.BillingAddresseeSnapShot__c);
      System.assertEquals(
        'trig@example.com',
        loaded.BillingEmailToSnapShot__c,
        '空欄だったメールだけ埋める'
      );
    }
  }

  @IsTest
  static void invoiceBeforeInsert_copiesBlankMemoFromAccount() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('CopyMemo');
      insert new FieldCopyDefinition__c(
        Name = 'Test_Inv_Memo_From_Account',
        TargetObject__c = InvoiceProductFieldCopyService.TARGET_INVOICE,
        SourceObject__c = InvoiceProductFieldCopyService.OBJECT_ACCOUNT,
        SourceFieldApiName__c = 'Name',
        TargetFieldApiName__c = 'Memo__c'
      );
      Invoice__c invoice = new Invoice__c(
        ContractHistory__c = fixture.history.Id,
        ContractService__c = fixture.service.Id,
        InvoiceDate__c = Date.today(),
        Amount__c = 1000
      );

      Test.startTest();
      insert invoice;
      Test.stopTest();

      Invoice__c loaded = [SELECT Memo__c FROM Invoice__c WHERE Id = :invoice.Id];
      System.assertEquals(
        'FieldCopy CopyMemo Acc',
        loaded.Memo__c,
        '仕様: Core 第11.4.2節 請求はinsert時だけ空欄へコピーする'
      );
    }
  }

  @IsTest
  static void invoiceLineBeforeInsert_fillsBlankProductUnit() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Line');
      Invoice__c invoice = new Invoice__c(
        ContractHistory__c = fixture.history.Id,
        ContractService__c = fixture.service.Id,
        InvoiceDate__c = Date.today(),
        Amount__c = 1000,
        BillingAccountSnapShot__c = fixture.billingAccount.Id,
        BillingAddresseeSnapShot__c = '固定宛名'
      );
      insert invoice;

      InvoiceLine__c line = new InvoiceLine__c(
        Invoice__c = invoice.Id,
        ContractProduct__c = fixture.contractProduct.Id,
        ProductName__c = 'テスト商品',
        Amount__c = 1000,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        RevenueRecognitionBasis__c = '月次計上'
      );

      Test.startTest();
      insert line;
      Test.stopTest();

      InvoiceLine__c loaded = [
        SELECT Product__c, Unit__c
        FROM InvoiceLine__c
        WHERE Id = :line.Id
      ];
      System.assertEquals(fixture.product.Id, loaded.Product__c);
      System.assertEquals(
        ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
        loaded.Unit__c
      );
    }
  }

  @IsTest
  static void periodLineBeforeInsert_runsWithoutErrorWhenNoPeriodCmdt() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Fixture fixture = createFixture('Period');
      InvoiceProduct__c periodLine = new InvoiceProduct__c(
        ContractHistory__c = fixture.history.Id,
        ContractProduct__c = fixture.contractProduct.Id,
        StartDate__c = Date.today(),
        Enddate__c = Date.today().addDays(30),
        Amount__c = 1000,
        Quantity__c = 1,
        UnitPrice__c = 1000
      );

      Test.startTest();
      insert periodLine;
      Test.stopTest();

      System.assertNotEquals(null, periodLine.Id);
    }
  }

  @IsTest
  static void handlers_acceptEmptyOrBareRecordsWithoutThrowing() {
    Boolean completed = false;
    InvoiceFieldCopyTriggerHandler.handlePeriodLineBeforeInsert(
      new List<InvoiceProduct__c>{ new InvoiceProduct__c() }
    );
    InvoiceFieldCopyTriggerHandler.handleInvoiceBeforeInsert(
      new List<Invoice__c>{ new Invoice__c() }
    );
    InvoiceFieldCopyTriggerHandler.handleInvoiceLineBeforeInsert(
      new List<InvoiceLine__c>{ new InvoiceLine__c() }
    );
    completed = true;
    System.assertEquals(
      true,
      completed,
      '空／最小レコードでもハンドラが例外なく完了すること'
    );
  }

  private class Fixture {
    BillingAccount__c billingAccount;
    ContractService__c service;
    ContractHistory__c history;
    Product2 product;
    ContractProduct__c contractProduct;
  }

  private static Fixture createFixture(String suffix) {
    Fixture fixture = new Fixture();
    Account account = ContractTestDataFactory.insertAccount(
      'FieldCopy ' + suffix + ' Acc'
    );
    fixture.billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = 'トリガ宛名 御中',
      BillingEmailTo__c = 'trig@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 1,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(fixture.billingAccount);
    insert fixture.billingAccount;

    fixture.service = new ContractService__c(
      Account__c = account.Id,
      BiilingAcccount__c = fixture.billingAccount.Id,
      Name = 'FieldCopy ' + suffix + ' Service'
    );
    ContractTestDataFactory.applyRequiredFields(fixture.service);
    insert fixture.service;

    fixture.history = new ContractHistory__c(
      ContractService__c = fixture.service.Id,
      Name = 'FieldCopy ' + suffix + ' History',
      historystatus__c = 'Ordered',
      Type__c = 'New'
    );
    ContractTestDataFactory.applyRequiredFields(fixture.history);
    insert fixture.history;

    fixture.product = new Product2(
      Name = 'FieldCopy ' + suffix + ' Product',
      ProductCode = suffix == 'Journal' ? 'FIELD-COPY-JOURNAL' : null,
      IsActive = true
    );
    ContractTestDataFactory.applyRequiredFields(fixture.product);
    insert fixture.product;

    fixture.contractProduct = new ContractProduct__c(
      ContractHistory__c = fixture.history.Id,
      Product__c = fixture.product.Id,
      Quantity__c = 1,
      UnitPrice__c = 1000,
      Unit__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
      StartDate__c = Date.today(),
      EndDate__c = Date.today().addDays(30)
    );
    ContractTestDataFactory.applyRequiredFields(fixture.contractProduct);
    insert fixture.contractProduct;
    return fixture;
  }
}
