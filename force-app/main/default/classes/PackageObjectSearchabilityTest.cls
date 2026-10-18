@IsTest
private class PackageObjectSearchabilityTest {
  /** 検索許可とタブは Org の定義を見る。共通基盤 第3.9節。 */
  @IsTest(SeeAllData=true)
  static void packageCustomObjectsAreSearchableAndTabbed() {
    List<String> names = new List<String>{
      'BillingAccount__c',
      'ContractHistory__c',
      'ContractOperationLog__c',
      'ContractProduct__c',
      'ContractService__c',
      'EstimateNoteMaster__c',
      'FieldCopyDefinition__c',
      'GlAccount__c',
      'GlAccountingPolicy__c',
      'GlAccountingTagRule__c',
      'GlAccountMap__c',
      'GlConditionRule__c',
      'GlConditionSet__c',
      'GlJournal__c',
      'GlManualJournalHeader__c',
      'GlManualJournalSetting__c',
      'Invoice__c',
      'InvoiceLine__c',
      'InvoicePayment__c',
      'InvoicePaymentAllocation__c',
      'InvoiceProduct__c'
    };
    for (Schema.DescribeSObjectResult described : Schema.describeSObjects(names)) {
      System.assertEquals(
        true,
        described.isSearchable(),
        '共通基盤 第3.9節: ' + described.getName() + ' の検索許可はオン'
      );
    }
    Set<String> tabbed = new Set<String>();
    for (PermissionSetTabSetting setting : [
      SELECT Name
      FROM PermissionSetTabSetting
      WHERE Name IN :names AND Visibility IN ('DefaultOff', 'DefaultOn')
    ]) {
      tabbed.add(setting.Name);
    }
    System.assertEquals(
      false,
      tabbed.isEmpty(),
      '共通基盤 第3.9節: タブが無いときは成功にしない'
    );
    for (String name : names) {
      System.assertEquals(
        true,
        tabbed.contains(name),
        '共通基盤 第3.9節: ' + name + ' はオブジェクトタブを置く'
      );
    }
  }
}
