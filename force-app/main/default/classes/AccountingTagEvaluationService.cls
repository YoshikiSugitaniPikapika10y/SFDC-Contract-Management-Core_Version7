public without sharing class AccountingTagEvaluationService {
  public class TagException extends Exception {
  }

  private static final String HEADER_AMOUNT_AMT = 'AMT';
  private static final String HEADER_AMOUNT_INVTAX = 'INVTAX';
  private static final String HEADER_AMOUNT_INCL = 'INCL';

  /** 仕様: Accounting 第7.3節、第7.5節 */
  public static void evaluateForInvoice(Id invoiceId) {
    if (invoiceId == null) {
      return;
    }
    GlAccountingPolicy__c policy = GlAccountingPolicyService.requireOrgPolicy();
    if (policy.AccountingEnabled__c != true) {
      return;
    }
    List<GlAccountingTagRule__c> rules = [
      SELECT
        Name,
        TagKey__c,
        Expression__c,
        ComparisonOperator__c,
        ComparisonValue__c,
        TargetFieldApiName__c
      FROM GlAccountingTagRule__c
      WHERE IsEnabled__c = TRUE
      WITH SYSTEM_MODE
    ];
    if (rules.isEmpty()) {
      return;
    }
    Map<String, Decimal> balances = slotBalances(invoiceId);
    putHeaderAmountTokens(balances, invoiceId);
    Invoice__c invoice = new Invoice__c(Id = invoiceId);
    Map<String, Schema.SObjectField> invoiceFields = Invoice__c.SObjectType.getDescribe()
      .fields.getMap();
    Set<String> targets = new Set<String>();
    for (GlAccountingTagRule__c rule : rules) {
      if (targets.contains(rule.TargetFieldApiName__c)) {
        throw new TagException('同じ保存先項目を複数の有効タグルールが更新しています。');
      }
      targets.add(rule.TargetFieldApiName__c);
      if (!invoiceFields.containsKey(rule.TargetFieldApiName__c)) {
        throw new TagException(
          '会計タグルール「' + rule.Name + '」の保存先項目がありません: ' + rule.TargetFieldApiName__c
        );
      }
      Schema.DescribeFieldResult field = invoiceFields.get(rule.TargetFieldApiName__c)
        .getDescribe();
      if (field.getType() != Schema.DisplayType.BOOLEAN) {
        throw new TagException(
          '会計タグルール「' + rule.Name + '」の保存先はチェックボックスではありません。'
        );
      }
      Decimal amount = evaluateExpression(rule.Expression__c, balances, rule.Name);
      invoice.put(
        rule.TargetFieldApiName__c,
        compare(amount, rule.ComparisonOperator__c, rule.ComparisonValue__c)
      );
    }
    Boolean previousExempt = InvoiceLockUtil.allowAccountingTagLockExempt;
    InvoiceLockUtil.allowAccountingTagLockExempt = true;
    try {
      update invoice;
    } finally {
      InvoiceLockUtil.allowAccountingTagLockExempt = previousExempt;
    }
  }

  /**
   * 仕様: Core 第7.9.3節手順3、Accounting 第7.1節。
   * 有効タグルールの保存先を False にする。訂正用請求へ会計タグを引き継がない。
   */
  public static void clearEnabledTagTargets(Invoice__c invoice) {
    if (invoice == null) {
      return;
    }
    Map<String, Schema.SObjectField> invoiceFields = Invoice__c.SObjectType.getDescribe()
      .fields.getMap();
    for (GlAccountingTagRule__c rule : [
      SELECT TargetFieldApiName__c
      FROM GlAccountingTagRule__c
      WHERE IsEnabled__c = TRUE
      WITH SYSTEM_MODE
    ]) {
      if (String.isBlank(rule.TargetFieldApiName__c)) {
        continue;
      }
      if (!invoiceFields.containsKey(rule.TargetFieldApiName__c)) {
        continue;
      }
      invoice.put(rule.TargetFieldApiName__c, false);
    }
  }

  /** 仕様: Accounting 第7.2節。有効ルールの削除は許可しない。 */
  public static void preventEnabledDelete(List<GlAccountingTagRule__c> oldRecords) {
    if (oldRecords == null) {
      return;
    }
    for (GlAccountingTagRule__c rule : oldRecords) {
      if (rule.IsEnabled__c == true) {
        rule.addError('有効な会計タグルールは削除できません。無効にしてから削除してください。');
      }
    }
  }

  /** 仕様: Accounting 第7.2節、第7.3節、第7.4節。有効=Trueの保存時だけ式を正規化し、字句・構文・保存先を検証する。 */
  public static void validateOnSave(List<GlAccountingTagRule__c> newRecords) {
    if (newRecords == null) {
      return;
    }
    Map<String, Schema.SObjectField> invoiceFields = Invoice__c.SObjectType.getDescribe()
      .fields.getMap();
    Map<String, Decimal> dummyBalances = emptySlotBalances();
    Set<Id> updatingIds = new Set<Id>();
    for (GlAccountingTagRule__c rule : newRecords) {
      if (rule.Id != null) {
        updatingIds.add(rule.Id);
      }
    }
    Map<String, Id> existingTargets = new Map<String, Id>();
    for (GlAccountingTagRule__c existing : [
      SELECT Id, TargetFieldApiName__c
      FROM GlAccountingTagRule__c
      WHERE IsEnabled__c = TRUE
      WITH SYSTEM_MODE
    ]) {
      if (
        updatingIds.contains(existing.Id) ||
        String.isBlank(existing.TargetFieldApiName__c)
      ) {
        continue;
      }
      existingTargets.put(existing.TargetFieldApiName__c.toLowerCase(), existing.Id);
    }
    Set<String> batchTargets = new Set<String>();
    Set<String> allowedOperators = new Set<String>{
      'EQ',
      'NE',
      'GT',
      'GTE',
      'LT',
      'LTE'
    };
    for (GlAccountingTagRule__c rule : newRecords) {
      try {
        if (rule.IsEnabled__c != true) {
          continue;
        }
        if (
          String.isBlank(rule.Expression__c) ||
          String.isBlank(rule.TargetFieldApiName__c) ||
          String.isBlank(rule.ComparisonOperator__c) ||
          rule.ComparisonValue__c == null
        ) {
          continue;
        }
        if (hasDisallowedWhitespace(rule.Expression__c)) {
          throw new TagException(
            '会計タグルール「' +
              rule.Name +
              '」の式は半角スペースでトークンを区切ってください。'
          );
        }
        rule.Expression__c = rule.Expression__c.normalizeSpace();
        evaluateExpression(rule.Expression__c, dummyBalances, rule.Name);
        if (!allowedOperators.contains(rule.ComparisonOperator__c)) {
          throw new TagException(
            '会計タグルール「' + rule.Name + '」の比較演算子が不正です。'
          );
        }
        if (!invoiceFields.containsKey(rule.TargetFieldApiName__c)) {
          throw new TagException(
            '会計タグルール「' +
              rule.Name +
              '」の保存先項目がありません: ' +
              rule.TargetFieldApiName__c
          );
        }
        Schema.DescribeFieldResult field = invoiceFields.get(rule.TargetFieldApiName__c)
          .getDescribe();
        if (field.getType() != Schema.DisplayType.BOOLEAN) {
          throw new TagException(
            '会計タグルール「' + rule.Name + '」の保存先はチェックボックスではありません。'
          );
        }
        String targetKey = rule.TargetFieldApiName__c.toLowerCase();
        if (
          existingTargets.containsKey(targetKey) ||
          batchTargets.contains(targetKey)
        ) {
          throw new TagException('同じ保存先項目を複数の有効タグルールが更新しています。');
        }
        batchTargets.add(targetKey);
      } catch (TagException ex) {
        rule.addError(ex.getMessage());
      }
    }
  }

  private static Boolean hasDisallowedWhitespace(String expression) {
    return expression.contains('\t') ||
      expression.contains('\n') ||
      expression.contains('\r') ||
      expression.contains('\u3000');
  }

  private static Map<String, Decimal> emptySlotBalances() {
    Map<String, Decimal> balances = new Map<String, Decimal>();
    for (AccountingSlotFixedCatalog.Definition slot : AccountingSlotFixedCatalog.values()) {
      balances.put(slot.abbreviation, 0);
    }
    // 仕様: Accounting 第7.3節。請求ヘッダ略称3個。保存検証は0、評価時は請求書の整数円。
    balances.put(HEADER_AMOUNT_AMT, 0);
    balances.put(HEADER_AMOUNT_INVTAX, 0);
    balances.put(HEADER_AMOUNT_INCL, 0);
    return balances;
  }

  /**
   * 仕様: Accounting 第7.3節。
   * AMT＝Amount__c、INVTAX＝TaxAmount__c、INCL＝TaxInclusiveAmount__c。保存値を円の整数で入れる。
   */
  private static void putHeaderAmountTokens(Map<String, Decimal> balances, Id invoiceId) {
    Invoice__c invoice = [
      SELECT Amount__c, TaxAmount__c, TaxInclusiveAmount__c
      FROM Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    balances.put(HEADER_AMOUNT_AMT, nvl(invoice.Amount__c));
    balances.put(HEADER_AMOUNT_INVTAX, nvl(invoice.TaxAmount__c));
    balances.put(HEADER_AMOUNT_INCL, nvl(invoice.TaxInclusiveAmount__c));
  }

  private static Map<String, Decimal> slotBalances(Id invoiceId) {
    Map<String, Decimal> balances = emptySlotBalances();
    for (GlJournal__c journal : [
      SELECT
        DebitSlotKey__c,
        CreditSlotKey__c,
        Amount__c,
        TransactionStatus__c
      FROM GlJournal__c
      WHERE Invoice__c = :invoiceId
      WITH SYSTEM_MODE
    ]) {
      if (journal.TransactionStatus__c == 'LogicallyDeleted') {
        continue;
      }
      Decimal signed = journal.TransactionStatus__c == 'Reversal'
        ? -nvl(journal.Amount__c)
        : nvl(journal.Amount__c);
      addBalance(balances, journal.DebitSlotKey__c, signed, true);
      addBalance(balances, journal.CreditSlotKey__c, signed, false);
    }
    return balances;
  }

  private static void addBalance(
    Map<String, Decimal> balances,
    String slotKey,
    Decimal amount,
    Boolean debitSide
  ) {
    if (String.isBlank(slotKey)) {
      return;
    }
    AccountingSlotFixedCatalog.Definition slot = AccountingSlotFixedCatalog.require(slotKey);
    Decimal signed = debitSide
      ? (slot.normalBalance == AccountingCatalogTypes.NormalBalance.Debit ? amount : -amount)
      : (slot.normalBalance == AccountingCatalogTypes.NormalBalance.Credit ? amount : -amount);
    balances.put(slot.abbreviation, balances.get(slot.abbreviation) + signed);
  }

  private static Decimal evaluateExpression(
    String expression,
    Map<String, Decimal> balances,
    String ruleName
  ) {
    if (String.isBlank(expression)) {
      throw new TagException('会計タグルール「' + ruleName + '」の式が空です。');
    }
    List<String> tokens = expression.normalizeSpace().split(' ');
    if (tokens.isEmpty()) {
      throw new TagException('会計タグルール「' + ruleName + '」の式が空です。');
    }
    ParseState state = new ParseState();
    state.index = 0;
    Decimal value = parseSum(tokens, state, balances, ruleName);
    if (state.index < tokens.size()) {
      throw new TagException('会計タグルール「' + ruleName + '」の式が不正です。');
    }
    return value;
  }

  private class ParseState {
    Integer index;
  }

  private static Decimal parseSum(
    List<String> tokens,
    ParseState state,
    Map<String, Decimal> balances,
    String ruleName
  ) {
    Decimal value = parseTerm(tokens, state, balances, ruleName);
    while (state.index < tokens.size()) {
      String token = tokens[state.index];
      if (token != '+' && token != '-') {
        break;
      }
      state.index++;
      Decimal right = parseTerm(tokens, state, balances, ruleName);
      value = token == '-' ? value - right : value + right;
    }
    return value;
  }

  private static Decimal parseTerm(
    List<String> tokens,
    ParseState state,
    Map<String, Decimal> balances,
    String ruleName
  ) {
    if (state.index >= tokens.size()) {
      throw new TagException('会計タグルール「' + ruleName + '」の式が不正です。');
    }
    String token = tokens[state.index];
    if (token == '(') {
      state.index++;
      Decimal value = parseSum(tokens, state, balances, ruleName);
      if (state.index >= tokens.size() || tokens[state.index] != ')') {
        throw new TagException('会計タグルール「' + ruleName + '」の括弧が対応していません。');
      }
      state.index++;
      return value;
    }
    if (token == ')' || token == '+' || token == '-') {
      throw new TagException('会計タグルール「' + ruleName + '」の式が不正です。');
    }
    if (!balances.containsKey(token)) {
      throw new TagException(
        '会計タグルール「' + ruleName + '」の式に未知のトークンがあります: ' + token
      );
    }
    state.index++;
    return balances.get(token);
  }

  /** 仕様: Accounting 第7.2節 */
  private static Boolean compare(Decimal amount, String operatorName, Decimal comparisonValue) {
    Decimal right = comparisonValue == null ? 0 : comparisonValue;
    if (operatorName == 'NE') {
      return amount != right;
    }
    if (operatorName == 'GT') {
      return amount > right;
    }
    if (operatorName == 'GTE') {
      return amount >= right;
    }
    if (operatorName == 'LT') {
      return amount < right;
    }
    if (operatorName == 'LTE') {
      return amount <= right;
    }
    return amount == right;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }
}
