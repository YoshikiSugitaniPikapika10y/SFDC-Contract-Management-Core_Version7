@IsTest
private class InvoiceProductCloneFieldGuardTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void cloneInvoiceProduct_copiesExportMergeKey() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      String exportMergeKey = InvoiceProductMergeKeyUtil.buildExportInvoiceMergeKey(
        null,
        null,
        Date.newInstance(2026, 6, 1),
        Date.newInstance(2026, 7, 31)
      );

      String lineBucketKey = 'LINE|CP=|UP=8000|Q=1';
      InvoiceProduct__c source = new InvoiceProduct__c(
        StartDate__c = Date.newInstance(2026, 6, 1),
        Enddate__c = Date.newInstance(2026, 6, 30),
        InvoiceBucketKey__c = exportMergeKey,
        LineBucketKey__c = lineBucketKey,
        Amount__c = 8000
      );

      InvoiceProduct__c cloned = InvoiceProductGenerationService.cloneInvoiceProduct(
        source
      );

      System.assertEquals(8000, cloned.Amount__c);
      System.assertEquals(source.StartDate__c, cloned.StartDate__c);
      System.assertEquals(source.Enddate__c, cloned.Enddate__c);
      System.assertEquals(
        exportMergeKey,
        cloned.InvoiceBucketKey__c,
        'Core 第6.7節: 期間明細の InvoiceBucketKey はクローンに載せる'
      );
      System.assertEquals(
        lineBucketKey,
        cloned.LineBucketKey__c,
        'Core 第6.7節: 期間明細の LineBucketKey はクローンに載せる'
      );
    }
  }

  @IsTest
  static void product2_doesNotHaveRevenueCategory() {
    System.assertEquals(
      false,
      Product2.SObjectType.getDescribe().fields.getMap().containsKey('RevenueCategory__c'),
      'Core 第3.1節: 商品一覧に RevenueCategory__c は出さない。科目は割当とテナント条件'
    );
  }
}
