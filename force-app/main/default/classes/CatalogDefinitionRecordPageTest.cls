@IsTest
private class CatalogDefinitionRecordPageTest {
  @IsTest
  static void estimateWizardVisibility_helpIsProductOnly() {
    System.assertEquals(
      'Visibilityは見積商品だけである。',
      EstimateWizardField__mdt.VisibilityFieldApiName__c.getDescribe()
        .getInlineHelpText(),
      'Core 第11.4.1節: Visibilityは見積商品だけである'
    );
  }

  @IsTest
  static void fieldCopy_helpMatchesProhibitions() {
    System.assertEquals(
      '空欄だけコピーする。',
      FieldCopyDefinition__c.TargetObject__c.getDescribe().getInlineHelpText(),
      'Core 第11.4.2節: 空欄だけコピーする'
    );
    System.assertEquals(
      '届かない相手へ空埋めしない。',
      FieldCopyDefinition__c.Context__c.getDescribe().getInlineHelpText(),
      'Core 第11.4.2節: 届かない相手へ空埋めしない'
    );
  }
}
