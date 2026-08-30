@IsTest
private class InvoicePaymentTriggerHandlerTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  private static Invoice__c createInvoice(String collectionStatus) {
    Account account = ContractTestDataFactory.insertAccount(
      'Payment ' + String.valueOf(Crypto.getRandomInteger())
    );
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
      Name = 'Payment Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;

    ContractHistory__c history = new ContractHistory__c(
      Name = 'Payment History',
      ContractService__c = service.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 6, 1),
      CurrentTermEndDate__c = Date.newInstance(2026, 6, 30)
    );
    insert history;

    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = 100,
      InvoiceTransactionStatus__c = collectionStatus == 'Draft'
        ? InvoiceTransactionStatusService.TX_DRAFT
        : InvoiceTransactionStatusService.TX_CONFIRMED,
      SystemIntegrationDate__c = collectionStatus == 'Draft'
        ? null
        : Date.today()
    );
    ContractTestDataFactory.insertAllowingInvoiceStatus(invoice);
    return invoice;
  }

  private static void insertInvoicePurpose(InvoicePayment__c payment) {
    Boolean previous = InvoicePaymentService.allowLifecycleWrite;
    InvoicePaymentService.allowLifecycleWrite = true;
    try {
      insert payment;
    } finally {
      InvoicePaymentService.allowLifecycleWrite = previous;
    }
  }

  @IsTest
  static void draftInvoice_blocksPayment() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice('Draft');
      Test.startTest();
      try {
        insert new InvoicePayment__c(
          Invoice__c = invoice.Id,
          Amount__c = 1100,
          PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
          PaymentDate__c = Date.today()
        );
        System.assert(false, '未確定請求への入金は失敗するはず');
      } catch (DmlException ex) {
        System.assert(
          ex.getMessage()
            .contains(InvoicePaymentTriggerHandler.DRAFT_PAYMENT_BLOCK_MESSAGE),
          ex.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void zeroAmount_blocksPayment() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice('Confirmed');
      Test.startTest();
      try {
        insert new InvoicePayment__c(
          Invoice__c = invoice.Id,
          Amount__c = 0,
          PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
          PaymentDate__c = Date.today()
        );
        System.assert(false, '0円入金は失敗するはず');
      } catch (DmlException ex) {
        System.assert(
          ex.getMessage()
            .contains(InvoicePaymentTriggerHandler.ZERO_AMOUNT_BLOCK_MESSAGE),
          ex.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void insert_appliesInvoicePaymentCopy() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new FieldCopyDefinition__c(
        Name = 'Test_Payment_Memo',
        TargetObject__c = 'InvoicePayment__c',
        SourceObject__c = 'Invoice__c',
        SourceFieldApiName__c = 'Memo__c',
        TargetFieldApiName__c = 'Memo__c'
      );
      Invoice__c invoice = createInvoice('Confirmed');
      InvoiceOpsController.updateInvoiceMemo(invoice.Id, '請求メモ');

      Test.startTest();
      InvoicePayment__c payment = new InvoicePayment__c(
        Invoice__c = invoice.Id,
        Amount__c = 500,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_NON_INVOICE,
        PaymentDate__c = Date.today()
      );
      insert payment;
      Test.stopTest();

      InvoicePayment__c stored = [
        SELECT Memo__c
        FROM InvoicePayment__c
        WHERE Id = :payment.Id
      ];
      System.assertEquals(
        '請求メモ',
        stored.Memo__c,
        '仕様: Core 第11.4.2節 入出金はinsert時'
      );
    }
  }

  @IsTest
  static void payment_movesToOpenPaymentUntilCleared() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice('Confirmed');

      Test.startTest();
      InvoicePayment__c partial = new InvoicePayment__c(
        Invoice__c = invoice.Id,
        Amount__c = 500,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.today(),
        Memo__c = 'partial'
      );
      insertInvoicePurpose(partial);

      Invoice__c afterPartial = [
        SELECT
          CollectionRefundStatus__c,
          InvoicePaymentNet__c,
          PaymentInclusiveTotal__c,
          PaymentClearingCompletedDate__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        InvoiceTransactionStatusService.COLLECTION_IN_PROGRESS,
        afterPartial.CollectionRefundStatus__c
      );
      System.assertEquals(500, afterPartial.InvoicePaymentNet__c);
      System.assertEquals(500, afterPartial.PaymentInclusiveTotal__c);
      System.assertEquals(null, afterPartial.PaymentClearingCompletedDate__c);

      insertInvoicePurpose(new InvoicePayment__c(
        Invoice__c = invoice.Id,
        Amount__c = 600,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.today(),
        Memo__c = 'rest'
      ));
      Test.stopTest();

      Invoice__c afterFull = [
        SELECT
          CollectionRefundStatus__c,
          InvoicePaymentNet__c,
          PaymentInclusiveTotal__c,
          PaymentClearingCompletedDate__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        InvoiceTransactionStatusService.COLLECTION_COMPLETED,
        afterFull.CollectionRefundStatus__c
      );
      System.assertEquals(1100, afterFull.InvoicePaymentNet__c);
      System.assertEquals(1100, afterFull.PaymentInclusiveTotal__c);
      System.assertEquals(Date.today(), afterFull.PaymentClearingCompletedDate__c);
    }
  }

  @IsTest
  static void signedAmount_keepsNegative() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice('Confirmed');
      insertInvoicePurpose(new InvoicePayment__c(
        Invoice__c = invoice.Id,
        Amount__c = 100,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.today()
      ));

      Test.startTest();
      InvoicePayment__c refund = new InvoicePayment__c(
        Invoice__c = invoice.Id,
        Amount__c = -100,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.today(),
        Memo__c = 'refund'
      );
      insertInvoicePurpose(refund);
      InvoicePayment__c reloaded = [
        SELECT Amount__c, PaymentPurpose__c
        FROM InvoicePayment__c
        WHERE Id = :refund.Id
      ];
      System.assertEquals(-100, reloaded.Amount__c);
      System.assertEquals(
        InvoicePaymentService.PURPOSE_INVOICE,
        reloaded.PaymentPurpose__c
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void permissionDenied_blocksPayment() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice('Confirmed');
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.INVOICE_PAYMENT => false
      };
      Test.startTest();
      try {
        insert new InvoicePayment__c(
          Invoice__c = invoice.Id,
          Amount__c = 1100,
          PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
          PaymentDate__c = Date.today()
        );
        System.assert(false, '権限なしは失敗するはず');
      } catch (DmlException ex) {
        System.assert(
          ex.getMessage()
            .contains(InvoicePaymentTriggerHandler.PERMISSION_REQUIRED_MESSAGE),
          ex.getMessage()
        );
      }
      Test.stopTest();
      ContractPermissionUtil.testOverrides = null;
    }
  }

  @IsTest
  static void directUpdateBlocked_deleteRecalculatesStatus() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice('Confirmed');
      InvoicePayment__c payment = new InvoicePayment__c(
        Invoice__c = invoice.Id,
        Amount__c = 1100,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.today()
      );
      insertInvoicePurpose(payment);

      Invoice__c cleared = [
        SELECT CollectionRefundStatus__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        InvoiceTransactionStatusService.COLLECTION_COMPLETED,
        cleared.CollectionRefundStatus__c
      );

      Test.startTest();
      try {
        payment.Amount__c = 400;
        update payment;
        System.assert(false, '未ロックでも直接更新は禁止');
      } catch (DmlException ex) {
        System.assert(
          ex.getMessage().contains(
            InvoicePaymentLockUtil.NEVER_EXEMPT_MESSAGE
          ),
          'Core 第11.6節: 金額は除外一覧に書いても不可。実際: ' + ex.getMessage()
        );
      }

      payment.Memo__c = 'メモ更新';
      update payment;
      System.assertEquals(
        'メモ更新',
        [SELECT Memo__c FROM InvoicePayment__c WHERE Id = :payment.Id].Memo__c,
        'Core 第8.4節: 登録後はメモを更新できる'
      );

      try {
        delete payment;
        System.assert(false, '入出金の物理削除は禁止');
      } catch (DmlException ex) {
        System.assert(
          ex.getMessage()
            .contains(InvoicePaymentTriggerHandler.DELETE_BLOCK_MESSAGE),
          ex.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void delete_allows104Alone() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice('Confirmed');
      InvoicePayment__c payment = new InvoicePayment__c(
        Invoice__c = invoice.Id,
        Amount__c = 1100,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.today()
      );
      insertInvoicePurpose(payment);
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.MIGRATE_ALL => true
      };
      try {
        delete payment;
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
      System.assertEquals(
        0,
        [SELECT COUNT() FROM InvoicePayment__c WHERE Id = :payment.Id],
        '共通基盤 第3.6節: 104 単独で入出金の物理削除を通す'
      );
    }
  }

  @IsTest
  static void refundToZero_returnsConfirmed() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice('Confirmed');
      insertInvoicePurpose(new InvoicePayment__c(
        Invoice__c = invoice.Id,
        Amount__c = 300,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.today()
      ));

      Test.startTest();
      insertInvoicePurpose(new InvoicePayment__c(
        Invoice__c = invoice.Id,
        Amount__c = -300,
        PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
        PaymentDate__c = Date.today(),
        Memo__c = 'refund'
      ));
      Test.stopTest();

      Invoice__c reloaded = [
        SELECT CollectionRefundStatus__c, InvoicePaymentNet__c, PaymentInclusiveTotal__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        InvoiceTransactionStatusService.COLLECTION_IN_PROGRESS,
        reloaded.CollectionRefundStatus__c
      );
      System.assertEquals(0, reloaded.InvoicePaymentNet__c);
      System.assertEquals(0, reloaded.PaymentInclusiveTotal__c);
    }
  }

  @IsTest
  static void invoicePurpose_withoutAllocations_isRejected() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice('Confirmed');
      Test.startTest();
      try {
        insert new InvoicePayment__c(
          Invoice__c = invoice.Id,
          Amount__c = 1100,
          PaymentPurpose__c = InvoicePaymentService.PURPOSE_INVOICE,
          PaymentDate__c = Date.today()
        );
        System.assert(false, '割当なしの請求金額入出金は失敗するはず');
      } catch (DmlException ex) {
        System.assert(
          ex.getMessage()
            .contains(
              InvoicePaymentTriggerHandler.INVOICE_ALLOCATION_REQUIRED_MESSAGE
            ),
          ex.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void unknownPurpose_blocksPayment() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Invoice__c invoice = createInvoice('Confirmed');
      Test.startTest();
      try {
        insert new InvoicePayment__c(
          Invoice__c = invoice.Id,
          Amount__c = 100,
          PaymentPurpose__c = 'Collection',
          PaymentDate__c = Date.today()
        );
        System.assert(false, '旧4種別の目的は失敗するはず');
      } catch (DmlException ex) {
        System.assert(
          ex.getMessage()
            .contains(InvoicePaymentTriggerHandler.PURPOSE_BLOCK_MESSAGE) ||
            ex.getMessage().contains('PaymentPurpose'),
          ex.getMessage()
        );
      }
      Test.stopTest();
    }
  }

}
