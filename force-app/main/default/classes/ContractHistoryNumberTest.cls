@IsTest
private class ContractHistoryNumberTest {
  /** 仕様: Core 第4.3.3節。契約履歴番号は契約履歴名とは別の自動番号。 */
  @IsTest
  static void historyNumberIsSeparateAutoNumber() {
    Schema.DescribeFieldResult numberField = ContractHistory__c.HistoryNumber__c.getDescribe();
    System.assertEquals(
      true,
      numberField.isAutoNumber(),
      '契約履歴番号は自動番号'
    );
    System.assertEquals('契約履歴番号', numberField.getLabel());

    Schema.DescribeFieldResult nameField = ContractHistory__c.Name.getDescribe();
    System.assertEquals(false, nameField.isAutoNumber(), '契約履歴名はテキストのまま');
    System.assertEquals('契約履歴名', nameField.getLabel());
  }
}
