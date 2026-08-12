@IsTest
private class InvoiceMergeKeyConfigServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void buildKeys_withDefaultParts_matchesLegacyFormat() {
    InvoiceMergeKeyConfigService.resetCache();
    try {
      InvoiceMergeKeyConfigService.cachedDefinitions = defaultDefinitions();

      Id billingAccountId = fakeId(BillingAccount__c.SObjectType, 1);
      Id contractHistoryId = fakeId(ContractHistory__c.SObjectType, 2);
      Id contractProductId = fakeId(ContractProduct__c.SObjectType, 3);
      Date invoiceDate = Date.newInstance(2026, 6, 5);
      Date paymentDate = Date.newInstance(2026, 7, 31);

      String invoiceKey = InvoiceMergeKeyConfigService.buildInvoiceBucketKey(
        billingAccountId,
        contractHistoryId,
        invoiceDate,
        paymentDate
      );
      System.assertEquals(
        'INV|BA=' +
          String.valueOf(billingAccountId) +
          '|CH=' +
          String.valueOf(contractHistoryId) +
          '|DT=2026-06-05|PD=2026-07-31',
        invoiceKey
      );

      String lineKey = InvoiceMergeKeyConfigService.buildLineBucketKey(
        contractProductId,
        10000,
        1,
        'ID',
        fakeId(Product2.SObjectType, 4)
      );
      System.assertEquals(
        'LINE|CP=' + String.valueOf(contractProductId) + '|UP=10000|Q=1',
        lineKey
      );
    } finally {
      InvoiceMergeKeyConfigService.resetCache();
    }
  }

  @IsTest
  static void validate_requiresBillingAccountContractHistoryAndInvoiceDate() {
    InvoiceMergeKeyConfigService.resetCache();
    try {
      // BillingAccount だけ欠落（CH / InvoiceDate は揃える）
      InvoiceMergeKeyConfigService.cachedDefinitions = new List<InvoiceMergeKeyPart__mdt>{
        part('Inv_CH', 'Invoice', 'ContractHistory', 10),
        part('Inv_DT', 'Invoice', 'InvoiceDate', 20),
        part('Line_CP', 'InvoiceLine', 'ContractProduct', 10)
      };

      Boolean failed = false;
      try {
        InvoiceMergeKeyConfigService.validateActiveDefinitions();
      } catch (InvoiceMergeKeyConfigService.MergeKeyConfigException ex) {
        failed = true;
        System.assertEquals(
          '請求マージキー部品（請求書）に必須部品「BillingAccount」がありません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, failed, '必須部品欠落で失敗すること');
    } finally {
      InvoiceMergeKeyConfigService.resetCache();
    }
  }

  @IsTest
  static void validate_requiresContractHistoryPart() {
    InvoiceMergeKeyConfigService.resetCache();
    try {
      // BA + InvoiceDate だけでは不可（別履歴の請求衝突を防ぐ）
      InvoiceMergeKeyConfigService.cachedDefinitions = new List<InvoiceMergeKeyPart__mdt>{
        part('Inv_BA', 'Invoice', 'BillingAccount', 10),
        part('Inv_DT', 'Invoice', 'InvoiceDate', 20),
        part('Line_CP', 'InvoiceLine', 'ContractProduct', 10)
      };

      Boolean failed = false;
      try {
        InvoiceMergeKeyConfigService.buildInvoiceBucketKey(
          fakeId(BillingAccount__c.SObjectType, 1),
          fakeId(ContractHistory__c.SObjectType, 2),
          Date.newInstance(2026, 1, 1),
          Date.newInstance(2026, 2, 1)
        );
      } catch (InvoiceMergeKeyConfigService.MergeKeyConfigException ex) {
        failed = true;
        System.assertEquals(
          '請求マージキー部品（請求書）に必須部品「ContractHistory」がありません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, failed, 'ContractHistory 必須欠落で失敗すること');
    } finally {
      InvoiceMergeKeyConfigService.resetCache();
    }
  }

  @IsTest
  static void validate_rejectsEmptyDuplicateAndUnknownParts() {
    InvoiceMergeKeyConfigService.resetCache();
    try {
      InvoiceMergeKeyConfigService.cachedDefinitions = new List<InvoiceMergeKeyPart__mdt>();
      Boolean emptyFailed = false;
      try {
        InvoiceMergeKeyConfigService.validateActiveDefinitions();
      } catch (InvoiceMergeKeyConfigService.MergeKeyConfigException ex) {
        emptyFailed = true;
        System.assertEquals(
          '請求マージキー部品（請求書）が1件も有効ではありません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, emptyFailed);

      InvoiceMergeKeyConfigService.cachedDefinitions = new List<InvoiceMergeKeyPart__mdt>{
        part('Inv_BA', 'Invoice', 'BillingAccount', 10),
        part('Inv_CH', 'Invoice', 'ContractHistory', 20),
        part('Inv_DT', 'Invoice', 'InvoiceDate', 30),
        part('Inv_BA2', 'Invoice', 'BillingAccount', 40),
        part('Line_CP', 'InvoiceLine', 'ContractProduct', 10)
      };
      Boolean dupFailed = false;
      try {
        InvoiceMergeKeyConfigService.validateActiveDefinitions();
      } catch (InvoiceMergeKeyConfigService.MergeKeyConfigException ex) {
        dupFailed = true;
        System.assertEquals(
          '請求マージキー部品（請求書）の部品「BillingAccount」が重複しています。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, dupFailed);

      InvoiceMergeKeyConfigService.cachedDefinitions = new List<InvoiceMergeKeyPart__mdt>{
        part('Inv_BA', 'Invoice', 'BillingAccount', 10),
        part('Inv_CH', 'Invoice', 'ContractHistory', 20),
        part('Inv_DT', 'Invoice', 'InvoiceDate', 30),
        part('Inv_BAD', 'Invoice', 'UnitPrice', 40),
        part('Line_CP', 'InvoiceLine', 'ContractProduct', 10)
      };
      Boolean unknownFailed = false;
      try {
        InvoiceMergeKeyConfigService.validateActiveDefinitions();
      } catch (InvoiceMergeKeyConfigService.MergeKeyConfigException ex) {
        unknownFailed = true;
        System.assertEquals(
          '請求マージキー部品「Inv_BAD」の部品「UnitPrice」は 請求書 では使えません。',
          ex.getMessage()
        );
      }
      System.assertEquals(true, unknownFailed);
    } finally {
      InvoiceMergeKeyConfigService.resetCache();
    }
  }

  @IsTest
  static void buildKeys_nullInputAndOptionalLineParts_andFromProduct() {
    InvoiceMergeKeyConfigService.resetCache();
    try {
      InvoiceMergeKeyConfigService.cachedDefinitions = new List<InvoiceMergeKeyPart__mdt>{
        part('Inv_BA', 'Invoice', 'BillingAccount', 10),
        part('Inv_CH', 'Invoice', 'ContractHistory', 20),
        part('Inv_DT', 'Invoice', 'InvoiceDate', 30),
        part('Line_CP', 'InvoiceLine', 'ContractProduct', 10),
        part('Line_UP', 'InvoiceLine', 'UnitPrice', 20),
        part('Line_Q', 'InvoiceLine', 'Quantity', 30),
        part('Line_U', 'InvoiceLine', 'Unit', 40),
        part('Line_P', 'InvoiceLine', 'Product', 50)
      };

      String emptyInvoice = InvoiceMergeKeyConfigService.buildInvoiceBucketKey(
        (InvoiceMergeKeyConfigService.InvoiceKeyInput) null
      );
      System.assertEquals('INV|BA=|CH=|DT=', emptyInvoice);

      Id contractProductId = fakeId(ContractProduct__c.SObjectType, 3);
      Id productId = fakeId(Product2.SObjectType, 4);
      String lineKey = InvoiceMergeKeyConfigService.buildLineBucketKey(
        (InvoiceMergeKeyConfigService.LineKeyInput) null
      );
      System.assertEquals('LINE|CP=|UP=0|Q=0|U=|P=', lineKey);

      InvoiceProduct__c product = new InvoiceProduct__c(
        ContractProduct__c = contractProductId,
        UnitPrice__c = 2500.50,
        Quantity__c = 2,
        Unit__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT
      );
      product.ContractProduct__r = new ContractProduct__c(Product__c = productId);
      String fromProduct = InvoiceMergeKeyConfigService.buildLineBucketKeyFromProduct(
        product
      );
      System.assert(
        fromProduct.contains('CP=' + String.valueOf(contractProductId)),
        fromProduct
      );
      System.assert(fromProduct.contains('UP=2500.5'), fromProduct);
      System.assert(fromProduct.contains('Q=2'), fromProduct);
      System.assert(fromProduct.contains('U=式'), fromProduct);
      System.assert(fromProduct.contains('P=' + String.valueOf(productId)), fromProduct);

      System.assertEquals(
        'LINE|CP=|UP=0|Q=0|U=|P=',
        InvoiceMergeKeyConfigService.buildLineBucketKeyFromProduct(null)
      );
    } finally {
      InvoiceMergeKeyConfigService.resetCache();
    }
  }

  @IsTest
  static void getActiveParts_skipsInactiveAndSortsByOrder() {
    InvoiceMergeKeyConfigService.resetCache();
    try {
      InvoiceMergeKeyPart__mdt inactive = part(
        'Inv_PD',
        'Invoice',
        'PaymentScheduledDate',
        5
      );
      inactive.Active__c = false;
      InvoiceMergeKeyConfigService.cachedDefinitions = new List<InvoiceMergeKeyPart__mdt>{
        part('Inv_DT', 'Invoice', 'InvoiceDate', 30),
        part('Inv_BA', 'Invoice', 'BillingAccount', 10),
        part('Inv_CH', 'Invoice', 'ContractHistory', 20),
        inactive,
        part('Line_CP', 'InvoiceLine', 'ContractProduct', 10)
      };

      List<InvoiceMergeKeyPart__mdt> invoiceParts = InvoiceMergeKeyConfigService.getActiveParts(
        'Invoice'
      );
      System.assertEquals(3, invoiceParts.size());
      System.assertEquals('BillingAccount', invoiceParts[0].Part__c);
      System.assertEquals('ContractHistory', invoiceParts[1].Part__c);
      System.assertEquals('InvoiceDate', invoiceParts[2].Part__c);

      InvoiceMergeKeyConfigService.InvoiceKeyInput input = new InvoiceMergeKeyConfigService.InvoiceKeyInput();
      input.billingAccountId = fakeId(BillingAccount__c.SObjectType, 1);
      input.contractHistoryId = fakeId(ContractHistory__c.SObjectType, 2);
      input.invoiceDate = Date.newInstance(2026, 3, 1);
      String key = InvoiceMergeKeyConfigService.buildInvoiceBucketKey(input);
      System.assert(!key.contains('|PD='), key);
      System.assert(key.contains('|CH='), key);
    } finally {
      InvoiceMergeKeyConfigService.resetCache();
    }
  }

  private static List<InvoiceMergeKeyPart__mdt> defaultDefinitions() {
    return new List<InvoiceMergeKeyPart__mdt>{
      part('Inv_BA', 'Invoice', 'BillingAccount', 10),
      part('Inv_CH', 'Invoice', 'ContractHistory', 20),
      part('Inv_DT', 'Invoice', 'InvoiceDate', 30),
      part('Inv_PD', 'Invoice', 'PaymentScheduledDate', 40),
      part('Line_CP', 'InvoiceLine', 'ContractProduct', 10),
      part('Line_UP', 'InvoiceLine', 'UnitPrice', 20),
      part('Line_Q', 'InvoiceLine', 'Quantity', 30)
    };
  }

  private static InvoiceMergeKeyPart__mdt part(
    String developerName,
    String scope,
    String partName,
    Integer sortOrder
  ) {
    return new InvoiceMergeKeyPart__mdt(
      DeveloperName = developerName,
      MasterLabel = developerName,
      Active__c = true,
      Scope__c = scope,
      Part__c = partName,
      SortOrder__c = sortOrder
    );
  }

  private static Id fakeId(Schema.SObjectType sobjectType, Integer n) {
    String suffix = String.valueOf(n);
    while (suffix.length() < 12) {
      suffix = '0' + suffix;
    }
    return (Id) (sobjectType.getDescribe().getKeyPrefix() + suffix);
  }
}
