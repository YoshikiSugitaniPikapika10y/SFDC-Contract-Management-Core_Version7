@IsTest
private class BillingAccountKeyServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void assignOnInsert_trimsKey() {
    BillingAccount__c account = new BillingAccount__c(
      BillingAccountKey__c = '  BA-TRIM  '
    );
    BillingAccountKeyService.assignOnInsert(
      new List<BillingAccount__c>{ account }
    );
    System.assertEquals(
      'BA-TRIM',
      account.BillingAccountKey__c,
      'Core 第3.3.1節: 保存時に前後空白を除く'
    );
  }

  @IsTest
  static void rejectKeyChange_blocksOnceSet() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c stored = insertBillingAccount('Reject Key BA');
      BillingAccount__c next = new BillingAccount__c(
        Id = stored.Id,
        BillingAccountKey__c = 'CHANGED'
      );
      BillingAccountKeyService.rejectKeyChange(
        new List<BillingAccount__c>{ next },
        new Map<Id, BillingAccount__c>{ stored.Id => stored }
      );
      System.assertEquals(
        true,
        next.hasErrors(),
        'Core 第3.3.1節: 一度入ったキーは変更しない'
      );
    }
  }

  @IsTest
  static void contractServiceInsert_setsHasReferenceTrue() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c stored = insertBillingAccount('HasRef BA');
      System.assertEquals(
        false,
        stored.HasReference__c,
        'Core 第3.3.3節: 参照0件なら OFF'
      );
      Account account = [
        SELECT Id
        FROM Account
        WHERE Id = :stored.Account__c
      ];
      ContractService__c service = new ContractService__c(
        Name = 'HasRef Service',
        Account__c = account.Id,
        BiilingAcccount__c = stored.Id
      );
      ContractTestDataFactory.applyRequiredFields(service);
      Test.startTest();
      insert service;
      Test.stopTest();
      BillingAccount__c afterInsert = [
        SELECT HasReference__c
        FROM BillingAccount__c
        WHERE Id = :stored.Id
      ];
      System.assertEquals(
        true,
        afterInsert.HasReference__c,
        'Core 第3.3.3節: 契約サービスから1件でも参照していれば ON'
      );
    }
  }

  @IsTest
  static void fillBlankKeys_putsEighteenDigitId() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c stored = insertBillingAccount('Blank Key BA');
      stored.BillingAccountKey__c = null;
      BillingAccountKeyService.fillBlankKeys(
        new List<BillingAccount__c>{ stored }
      );
      BillingAccount__c afterFill = [
        SELECT BillingAccountKey__c
        FROM BillingAccount__c
        WHERE Id = :stored.Id
      ];
      System.assertEquals(
        String.valueOf(stored.Id),
        afterFill.BillingAccountKey__c,
        'Core 第3.3.1節: 空で保存したあとは18桁 Id を入れる'
      );
    }
  }

  @IsTest
  static void rejectKeyChange_blocksUserHasReferenceAndTrimsUnchangedKey() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c stored = insertBillingAccount('HasRef Guard BA');
      BillingAccount__c nextRef = new BillingAccount__c(
        Id = stored.Id,
        HasReference__c = true
      );
      BillingAccountKeyService.rejectKeyChange(
        new List<BillingAccount__c>{ nextRef },
        new Map<Id, BillingAccount__c>{ stored.Id => stored }
      );
      System.assertEquals(
        true,
        nextRef.hasErrors(),
        'Core 第3.3.3節: 参照ありは表示用であり利用者が変更できない'
      );

      BillingAccount__c nextSame = new BillingAccount__c(
        Id = stored.Id,
        BillingAccountKey__c = stored.BillingAccountKey__c + '  '
      );
      BillingAccountKeyService.rejectKeyChange(
        new List<BillingAccount__c>{ nextSame },
        new Map<Id, BillingAccount__c>{ stored.Id => stored }
      );
      System.assertEquals(
        false,
        nextSame.hasErrors(),
        'Core 第3.3.1節: 前後空白を除いた値が同じなら変更ではない'
      );
      System.assertEquals(
        stored.BillingAccountKey__c,
        nextSame.BillingAccountKey__c
      );
    }
  }

  @IsTest
  static void emptyInputs_andMarkHasReferenceTrue_followKeyRules() {
    BillingAccountKeyService.assignOnInsert(null);
    BillingAccountKeyService.assignOnInsert(new List<BillingAccount__c>{ null });
    BillingAccountKeyService.fillBlankKeys(null);
    BillingAccountKeyService.fillBlankKeys(new List<BillingAccount__c>());
    BillingAccountKeyService.fillBlankKeys(
      new List<BillingAccount__c>{ new BillingAccount__c() }
    );
    BillingAccountKeyService.rejectKeyChange(null, null);
    BillingAccountKeyService.markHasReferenceTrue(null);
    BillingAccountKeyService.markHasReferenceTrue(new Set<Id>());
    BillingAccountKeyService.refreshHasReference(null);
    BillingAccountKeyService.refreshHasReference(new Set<Id>());

    System.runAs(ContractTestDataFactory.getAdminUser()) {
      BillingAccount__c stored = insertBillingAccount('Mark Ref BA');
      BillingAccountKeyService.beginReferenceRefreshDefer();
      BillingAccountKeyService.markHasReferenceTrue(new Set<Id>{ stored.Id });
      BillingAccountKeyService.endReferenceRefreshDefer();
      BillingAccount__c afterDefer = [
        SELECT HasReference__c
        FROM BillingAccount__c
        WHERE Id = :stored.Id
      ];
      System.assertEquals(
        false,
        afterDefer.HasReference__c,
        'Core 第3.3.3節: 契約サービスも請求書も0件なら OFF'
      );
    }
  }

  private static BillingAccount__c insertBillingAccount(String name) {
    Account account = ContractTestDataFactory.insertAccount(name + ' Account');
    BillingAccount__c billingAccount = new BillingAccount__c(
      Name = name,
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'key@example.com',
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
    return [
      SELECT Id, Account__c, BillingAccountKey__c, HasReference__c
      FROM BillingAccount__c
      WHERE Id = :billingAccount.Id
    ];
  }
}
