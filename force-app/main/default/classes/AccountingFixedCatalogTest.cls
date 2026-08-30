@IsTest
private class AccountingFixedCatalogTest {
  @IsTest
  static void catalogsHaveSpecifiedCountsAndUniqueKeys() {
    System.assertEquals(6, AccountingEventFixedCatalog.values().size());
    System.assertEquals(12, AccountingSlotFixedCatalog.values().size());
    System.assertEquals(11, JournalAmountItemFixedCatalog.values().size());
    System.assertEquals(5, JournalPostingDateFixedCatalog.values().size());
    System.assertEquals(22, SlotPriorityRuleFixedCatalog.values().size());
    System.assertEquals(7, FixedConditionSetFixedCatalog.values().size());
    System.assertEquals(16, FixedConditionRuleFixedCatalog.values().size());
    System.assertEquals(16, JournalPatternFixedCatalog.values().size());

    assertUniqueKeys(toKeys(AccountingEventFixedCatalog.values()));
    assertUniqueKeys(toKeys(AccountingSlotFixedCatalog.values()));
    assertUniqueKeys(toSlotAbbreviations());
    assertUniqueKeys(toKeys(JournalAmountItemFixedCatalog.values()));
    assertUniqueKeys(toKeys(JournalPostingDateFixedCatalog.values()));
    assertUniqueKeys(toKeys(SlotPriorityRuleFixedCatalog.values()));
    assertUniqueKeys(toKeys(FixedConditionSetFixedCatalog.values()));
    assertUniqueKeys(toKeys(FixedConditionRuleFixedCatalog.values()));
    assertUniqueKeys(toKeys(JournalPatternFixedCatalog.values()));
  }

  @IsTest
  static void requireReturnsSameInstanceAndRejectsUnknown() {
    System.assertEquals(
      AccountingEventFixedCatalog.BILLING_CONFIRMED,
      AccountingEventFixedCatalog.require('BILLING_CONFIRMED')
    );
    System.assertEquals(
      AccountingSlotFixedCatalog.SuspensePayment,
      AccountingSlotFixedCatalog.require('SuspensePayment')
    );
    System.assertEquals(
      JournalPatternFixedCatalog.PAYMENT_INVOICE_CURRENT,
      JournalPatternFixedCatalog.require('PAYMENT_INVOICE_CURRENT')
    );

    Boolean eventFailed = false;
    try {
      AccountingEventFixedCatalog.require('PAYMENT_DELETED');
    } catch (AccountingCatalogTypes.UnknownKeyException e) {
      eventFailed = true;
    }
    System.assert(eventFailed, '廃止イベントはCatalogに残さない');
  }

  @IsTest
  static void patternsReferenceCatalogInstances() {
    JournalPatternFixedCatalog.Definition body = JournalPatternFixedCatalog.BILLING_BASIS_INVOICE_BODY;
    System.assertEquals(
      AccountingEventFixedCatalog.BILLING_CONFIRMED,
      body.event
    );
    System.assertEquals(
      JournalAmountItemFixedCatalog.InvoiceSubtotal,
      body.amountItem
    );
    System.assertEquals(
      JournalPostingDateFixedCatalog.BillingDate,
      body.postingDateItem
    );
    System.assertEquals(
      AccountingSlotFixedCatalog.AccountsReceivable,
      body.debitSlot
    );
    System.assertEquals(null, body.creditSlot);
    System.assertEquals(
      AccountingCatalogTypes.SlotPriorityType.BillingBasisInvoiceAllocation,
      body.slotPriorityType
    );
    System.assertEquals(
      FixedConditionSetFixedCatalog.PAY_INVOICE_CURRENT,
      JournalPatternFixedCatalog.PAYMENT_INVOICE_CURRENT.conditionSet
    );
    System.assertEquals(
      null,
      JournalPatternFixedCatalog.BILLING_TAX_AT_INVOICE.slotPriorityType
    );
  }

  @IsTest
  static void aggregateType_allAndAnyOf_notReservedAny() {
    Set<String> names = new Set<String>();
    for (
      AccountingCatalogTypes.AggregateType t : AccountingCatalogTypes.AggregateType.values()
    ) {
      names.add(t.name());
    }
    System.assertEquals(
      true,
      names.contains('All'),
      'Accounting 第4.7節: 集約のすべては All'
    );
    System.assertEquals(
      true,
      names.contains('AnyOf'),
      'Accounting 第4.7節: 集約のいずれは AnyOf'
    );
    System.assertEquals(
      false,
      names.contains('Any'),
      'Apex予約語 Any は AggregateType に使わない'
    );
  }

  @IsTest
  static void conditionRulesBelongToSevenSets() {
    Map<String, Integer> counts = new Map<String, Integer>();
    for (
      FixedConditionRuleFixedCatalog.Definition rule : FixedConditionRuleFixedCatalog.values()
    ) {
      Integer current = counts.containsKey(rule.conditionSet.key)
        ? counts.get(rule.conditionSet.key)
        : 0;
      counts.put(rule.conditionSet.key, current + 1);
      System.assertEquals(
        rule.conditionSet.key + '_' + String.valueOf(rule.sequence),
        rule.key
      );
    }
    System.assertEquals(2, counts.get('PAY_INVOICE_CURRENT'));
    System.assertEquals(2, counts.get('PAY_NON_INVOICE_POSITIVE'));
    System.assertEquals(2, counts.get('PAY_NON_INVOICE_NEGATIVE'));
    System.assertEquals(3, counts.get('PAY_INVOICE_HISTORICAL_POSITIVE_CASH'));
    System.assertEquals(3, counts.get('PAY_INVOICE_HISTORICAL_NEGATIVE_CASH'));
    System.assertEquals(2, counts.get('PAY_INVOICE_HISTORICAL_UAC_TRANSFER'));
    System.assertEquals(2, counts.get('PAY_INVOICE_HISTORICAL_SP_TRANSFER'));
  }

  @IsTest
  static void slotPriorityRulesKeepUniquePairsAndPriorities() {
    Set<String> typeSourceTarget = new Set<String>();
    Set<String> typeSourcePriority = new Set<String>();
    for (
      SlotPriorityRuleFixedCatalog.Definition rule : SlotPriorityRuleFixedCatalog.values()
    ) {
      System.assert(rule.priority >= 1);
      System.assertNotEquals(rule.sourceSlot.key, rule.targetSlot.key);
      System.assert(String.isNotBlank(rule.description));
      System.assert(
        typeSourceTarget.add(
          String.valueOf(rule.priorityType) +
            ':' +
            rule.sourceSlot.key +
            ':' +
            rule.targetSlot.key
        )
      );
      System.assert(
        typeSourcePriority.add(
          String.valueOf(rule.priorityType) +
            ':' +
            rule.sourceSlot.key +
            ':' +
            String.valueOf(rule.priority)
        )
      );
    }
  }

  @IsTest
  static void patternsKeepInvariantsAndSameDayOrder() {
    Map<String, Integer> expectedSameDay = new Map<String, Integer>{
      'BILLING_BASIS_INVOICE_BODY' => 10,
      'CASH_BASIS_INVOICE_BODY_CTA_TRANSFER' => 10,
      'BILLING_TAX_AT_INVOICE' => 20,
      'BILLING_BASIS_INVOICE_TAX_DEFERRED' => 20,
      'CASH_BASIS_INVOICE_TAX_CTA_TRANSFER' => 20,
      'BILLING_BASIS_REVENUE_BODY' => 30,
      'CASH_BASIS_REVENUE_BODY' => 30,
      'BILLING_BASIS_REVENUE_TAX' => 40,
      'CASH_BASIS_REVENUE_TAX' => 40,
      'PAYMENT_INVOICE_HISTORICAL_UAC_TRANSFER' => 50,
      'PAYMENT_INVOICE_HISTORICAL_SP_TRANSFER' => 51,
      'PAYMENT_INVOICE_CURRENT' => 60,
      'PAYMENT_INVOICE_HISTORICAL_POSITIVE_CASH' => 60,
      'PAYMENT_INVOICE_HISTORICAL_NEGATIVE_CASH' => 60,
      'PAYMENT_NON_INVOICE_POSITIVE' => 70,
      'PAYMENT_NON_INVOICE_NEGATIVE' => 70
    };
    for (
      JournalPatternFixedCatalog.Definition pattern : JournalPatternFixedCatalog.values()
    ) {
      System.assertNotEquals(null, pattern.event);
      System.assertNotEquals(null, pattern.amountItem);
      System.assertNotEquals(
        JournalAmountItemFixedCatalog.ManualAmount,
        pattern.amountItem
      );
      System.assert(
        pattern.debitSlot != null || pattern.creditSlot != null,
        '両方空は許さない'
      );
      if (pattern.debitSlot != null && pattern.creditSlot != null) {
        System.assertNotEquals(pattern.debitSlot.key, pattern.creditSlot.key);
        System.assertEquals(null, pattern.slotPriorityType);
      } else {
        System.assertNotEquals(null, pattern.slotPriorityType);
      }
      System.assertEquals(
        expectedSameDay.get(pattern.key),
        pattern.sameDayOrder
      );
    }

    Boolean prepaidFailed = false;
    try {
      JournalPatternFixedCatalog.require('PREPAID');
    } catch (AccountingCatalogTypes.UnknownKeyException e) {
      prepaidFailed = true;
    }
    System.assert(prepaidFailed, '旧条件キーはCatalogに残さない');
  }

  @IsTest
  static void eventNameAndConditionObjectApiMatchSpec() {
    System.assertEquals(
      '請求入出金登録（Purpose=Invoice／NonInvoiceと符号付きAmountを含む）',
      AccountingEventFixedCatalog.PAYMENT_RECORDED.name
    );
    System.assertEquals(
      'InvoicePayment__c',
      AccountingCatalogTypes.objectApiName(
        AccountingCatalogTypes.ConditionObject.InvoicePayment
      )
    );
    System.assertEquals(
      'InvoicePaymentAllocation__c',
      AccountingCatalogTypes.objectApiName(
        AccountingCatalogTypes.ConditionObject.InvoicePaymentAllocation
      )
    );
    System.assertEquals(
      'Product2',
      AccountingCatalogTypes.objectApiName(
        AccountingCatalogTypes.ConditionObject.Product2
      )
    );
    System.assertEquals(
      'Opportunity',
      AccountingCatalogTypes.objectApiName(
        AccountingCatalogTypes.ConditionObject.Opportunity
      )
    );
    System.assertEquals(
      'Account',
      AccountingCatalogTypes.objectApiName(
        AccountingCatalogTypes.ConditionObject.Account
      )
    );

    Boolean abbreviationFailed = false;
    try {
      AccountingSlotFixedCatalog.require('AR');
    } catch (AccountingCatalogTypes.UnknownKeyException e) {
      abbreviationFailed = true;
    }
    System.assert(abbreviationFailed, '略称はスロットキーではない');
  }

  @IsTest
  static void restrictedPicklistsMatchCatalogKeysAndNames() {
    assertPicklistMatchesCatalog(
      GlAccountMap__c.SlotKey__c.getDescribe().getPicklistValues(),
      AccountingSlotFixedCatalog.values()
    );
    assertPicklistMatchesConditionSets(
      GlAccountMap__c.FixedConditionSetKey__c.getDescribe().getPicklistValues()
    );
    Set<String> targetObjects = picklistValues(
      GlConditionRule__c.TargetObject__c.getDescribe().getPicklistValues()
    );
    System.assertEquals(11, targetObjects.size());
    System.assert(targetObjects.contains('InvoiceLine__c'));
    System.assert(targetObjects.contains('ContractProduct__c'));
    System.assert(targetObjects.contains('Product2'));
  }

  private static void assertPicklistMatchesCatalog(
    List<Schema.PicklistEntry> entries,
    List<AccountingSlotFixedCatalog.Definition> rows
  ) {
    Map<String, String> expected = new Map<String, String>();
    for (AccountingSlotFixedCatalog.Definition row : rows) {
      expected.put(row.key, row.name);
    }
    Map<String, String> actual = new Map<String, String>();
    for (Schema.PicklistEntry entry : entries) {
      if (entry.isActive()) {
        actual.put(entry.getValue(), entry.getLabel());
      }
    }
    System.assertEquals(expected.keySet(), actual.keySet());
    for (String key : expected.keySet()) {
      System.assertEquals(expected.get(key), actual.get(key));
    }
  }

  private static void assertPicklistMatchesConditionSets(
    List<Schema.PicklistEntry> entries
  ) {
    Map<String, String> expected = new Map<String, String>();
    for (
      FixedConditionSetFixedCatalog.Definition row : FixedConditionSetFixedCatalog.values()
    ) {
      expected.put(row.key, row.name);
    }
    Map<String, String> actual = new Map<String, String>();
    for (Schema.PicklistEntry entry : entries) {
      if (entry.isActive()) {
        actual.put(entry.getValue(), entry.getLabel());
      }
    }
    System.assertEquals(expected.keySet(), actual.keySet());
    for (String key : expected.keySet()) {
      System.assertEquals(expected.get(key), actual.get(key));
    }
  }

  private static Set<String> picklistValues(
    List<Schema.PicklistEntry> entries
  ) {
    Set<String> values = new Set<String>();
    for (Schema.PicklistEntry entry : entries) {
      if (entry.isActive()) {
        values.add(entry.getValue());
      }
    }
    return values;
  }

  private static List<String> toKeys(
    List<AccountingEventFixedCatalog.Definition> rows
  ) {
    List<String> keys = new List<String>();
    for (AccountingEventFixedCatalog.Definition row : rows) {
      keys.add(row.key);
    }
    return keys;
  }

  private static List<String> toKeys(
    List<AccountingSlotFixedCatalog.Definition> rows
  ) {
    List<String> keys = new List<String>();
    for (AccountingSlotFixedCatalog.Definition row : rows) {
      keys.add(row.key);
    }
    return keys;
  }

  private static List<String> toKeys(
    List<JournalAmountItemFixedCatalog.Definition> rows
  ) {
    List<String> keys = new List<String>();
    for (JournalAmountItemFixedCatalog.Definition row : rows) {
      keys.add(row.key);
    }
    return keys;
  }

  private static List<String> toKeys(
    List<JournalPostingDateFixedCatalog.Definition> rows
  ) {
    List<String> keys = new List<String>();
    for (JournalPostingDateFixedCatalog.Definition row : rows) {
      keys.add(row.key);
    }
    return keys;
  }

  private static List<String> toKeys(
    List<SlotPriorityRuleFixedCatalog.Definition> rows
  ) {
    List<String> keys = new List<String>();
    for (SlotPriorityRuleFixedCatalog.Definition row : rows) {
      keys.add(row.key);
    }
    return keys;
  }

  private static List<String> toKeys(
    List<FixedConditionSetFixedCatalog.Definition> rows
  ) {
    List<String> keys = new List<String>();
    for (FixedConditionSetFixedCatalog.Definition row : rows) {
      keys.add(row.key);
    }
    return keys;
  }

  private static List<String> toKeys(
    List<FixedConditionRuleFixedCatalog.Definition> rows
  ) {
    List<String> keys = new List<String>();
    for (FixedConditionRuleFixedCatalog.Definition row : rows) {
      keys.add(row.key);
    }
    return keys;
  }

  private static List<String> toKeys(
    List<JournalPatternFixedCatalog.Definition> rows
  ) {
    List<String> keys = new List<String>();
    for (JournalPatternFixedCatalog.Definition row : rows) {
      keys.add(row.key);
    }
    return keys;
  }

  private static List<String> toSlotAbbreviations() {
    List<String> keys = new List<String>();
    for (
      AccountingSlotFixedCatalog.Definition row : AccountingSlotFixedCatalog.values()
    ) {
      keys.add(row.abbreviation);
    }
    return keys;
  }

  private static void assertUniqueKeys(List<String> keys) {
    Set<String> unique = new Set<String>(keys);
    System.assertEquals(keys.size(), unique.size());
    for (String key : keys) {
      System.assert(String.isNotBlank(key));
    }
  }
}
