@IsTest
private class CatalogDefinitionListViewTest {
  /** ListView はテスト隔離では 0 件になる。本文の一覧有無は Org の定義を見る。 */
  @IsTest(SeeAllData=true)
  static void product2_hasAvailableForContractListView() {
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE
          SobjectType = 'Product2'
          AND DeveloperName = 'AvailableForContract'
      ],
      'Core 第3.1節: ビュー「契約管理で利用可」を1本持つ'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE SobjectType = 'Product2' AND DeveloperName = 'AllProducts'
      ],
      'Core 第3.1節: 「すべての商品」は残す'
    );
  }

  @IsTest(SeeAllData=true)
  static void definitionCatalogs_haveAllListViews() {
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE
          SobjectType = 'FieldCopyDefinition__c'
          AND DeveloperName = 'All'
      ],
      'Core 第11.4.2節: コピー定義の一覧 All'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE SobjectType = 'GlAccount__c' AND DeveloperName = 'All'
      ],
      'Accounting 第4章: 科目 All'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE SobjectType = 'GlConditionSet__c' AND DeveloperName = 'All'
      ],
      'Accounting 第4章: 条件セット All'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE SobjectType = 'GlAccountMap__c' AND DeveloperName = 'All'
      ],
      'Accounting 第4章: 割当 All'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE SobjectType = 'GlAccountingTagRule__c' AND DeveloperName = 'All'
      ],
      'Accounting 第4章: タグルール All'
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM ListView
        WHERE SobjectType = 'GlManualJournalSetting__c' AND DeveloperName = 'All'
      ],
      'Accounting 第4章: 手動仕訳 All'
    );
  }
}
