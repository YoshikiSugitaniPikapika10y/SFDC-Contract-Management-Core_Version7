@IsTest
private class CatalogDefinitionListViewTest {
  @IsTest
  static void product2_hasAvailableForContractListView() {
    List<ListView> available = [
      SELECT Name
      FROM ListView
      WHERE SobjectType = 'Product2' AND Name = 'AvailableForContract'
    ];
    System.assertEquals(
      1,
      available.size(),
      'Core 第3.1節: ビュー「契約管理で利用可」を1本持つ'
    );
    List<ListView> allProducts = [
      SELECT Name
      FROM ListView
      WHERE SobjectType = 'Product2' AND Name = 'AllProducts'
    ];
    System.assertEquals(
      1,
      allProducts.size(),
      'Core 第3.1節: 「すべての商品」は残す'
    );
  }

  @IsTest
  static void definitionCatalogs_haveAllListViews() {
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE SobjectType = 'FieldCopyDefinition__c' AND Name = 'All'
      ],
      'Core 第11.4.2節: コピー定義の一覧 All'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE SobjectType = 'GlAccount__c' AND Name = 'All'
      ],
      'Accounting 第4章: 科目 All'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE SobjectType = 'GlConditionSet__c' AND Name = 'All'
      ],
      'Accounting 第4章: 条件セット All'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE SobjectType = 'GlAccountMap__c' AND Name = 'All'
      ],
      'Accounting 第4章: 割当 All'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE SobjectType = 'GlAccountingTagRule__c' AND Name = 'All'
      ],
      'Accounting 第4章: タグルール All'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE SobjectType = 'GlManualJournalSetting__c' AND Name = 'All'
      ],
      'Accounting 第4章: 手動仕訳 All'
    );
  }
}
