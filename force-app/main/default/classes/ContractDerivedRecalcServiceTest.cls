@IsTest
private class ContractDerivedRecalcServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
    ContractTestDataFactory.ensureOrgAccountingPolicy();
  }

  @IsTest
  static void recalculate_blocksWithout102() {
    ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
      ContractPermissionUtil.FIX_CONTRACT => false,
      ContractPermissionUtil.MIGRATE_ALL => false
    };
    Boolean blocked = false;
    try {
      ContractDerivedRecalcService.recalculate(new Set<Id>());
    } catch (AuraHandledException ex) {
      blocked = true;
      System.assertEquals(
        '契約と見積の再計算を実行する権限がありません。',
        ex.getMessage()
      );
    } finally {
      ContractPermissionUtil.testOverrides = null;
    }
    System.assertEquals(true, blocked);
  }

  @IsTest
  static void recalculate_runsWith102() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.FIX_CONTRACT => true
      };
      Account account = ContractTestDataFactory.insertAccount('Recalc Account');
      ContractService__c service = ContractTestDataFactory.insertContractService(
        account.Id,
        'Recalc Service'
      );
      Date termStart = Date.newInstance(2026, 6, 1);
      Date termEnd = Date.newInstance(2026, 6, 30);
      ContractHistory__c history = new ContractHistory__c(
        Name = 'Recalc Ordered',
        ContractService__c = service.Id,
        Type__c = 'New',
        historystatus__c = 'Estimate',
        Version__c = 1,
        CurrentTermStartDate__c = termStart,
        CurrentTermEndDate__c = termEnd
      );
      ContractTestDataFactory.applyRequiredFields(history);
      ContractTestDataFactory.applyEstimateOrderedOpportunity(history, account.Id);
      insert history;
      Product2 product = ContractTestDataFactory.buildProduct('Recalc Product');
      product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
      ContractTestDataFactory.insertProduct(product);
      ContractProduct__c contractProduct = new ContractProduct__c(
        ContractHistory__c = history.Id,
        Account__c = account.Id,
        Product__c = product.Id,
        Quantity__c = 1,
        UnitPrice__c = 1000,
        Amount__c = 1000,
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = 'New',
        RevenueRecognitionBasis__c = ContractMetadataService.REVENUE_BASIS_POINT_IN_TIME
      );
      ContractTestDataFactory.applyRequiredFields(contractProduct);
      contractProduct.Amount__c = 1000;
      insert contractProduct;
      history.historystatus__c = 'Ordered';
      update history;

      Test.startTest();
      ContractDerivedRecalcService.recalculate(new Set<Id>{ service.Id });
      Test.stopTest();
      ContractPermissionUtil.testOverrides = null;

      ContractService__c reloaded = [
        SELECT
          FirstOrderedHistory__c,
          LatestOrderedHistory__c,
          Lifecycle__c
        FROM ContractService__c
        WHERE Id = :service.Id
      ];
      System.assertEquals(
        history.Id,
        reloaded.FirstOrderedHistory__c,
        '共通基盤 第3.6節: First を Ordered から再計算する'
      );
      System.assertEquals(
        history.Id,
        reloaded.LatestOrderedHistory__c,
        '共通基盤 第3.6節: Latest を Ordered から再計算する'
      );
      System.assertEquals(
        ContractDomainConstants.LIFECYCLE_SPOT,
        reloaded.Lifecycle__c,
        '共通基盤 第3.6節: Lifecycle を Ordered から再計算する'
      );
      System.assertEquals(
        true,
        [
            SELECT HasReference__c
            FROM BillingAccount__c
            WHERE Id = :service.BiilingAcccount__c
          ]
          .HasReference__c,
        '共通基盤 第3.6節: HasReference を再計算する'
      );
      ContractHistory__c reloadedHistory = [
        SELECT StatusPath__c, InvoiceCount__c, InvoicedCount__c, historystatus__c
        FROM ContractHistory__c
        WHERE Id = :history.Id
      ];
      System.assertEquals(
        'Ordered',
        reloadedHistory.historystatus__c,
        '共通基盤 第3.6節: 再計算は受注状態を直書きしない'
      );
      System.assert(
        reloadedHistory.InvoiceCount__c > 0,
        '受注後に取消済みを除く請求がある'
      );
      System.assertEquals(
        'Invoicing',
        reloadedHistory.StatusPath__c,
        '共通基盤 第3.6節: StatusPath を再計算する。Core 第5.7節: 未確定請求が残れば Invoicing'
      );
    }
  }
}
