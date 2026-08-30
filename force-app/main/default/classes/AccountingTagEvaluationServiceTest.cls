@IsTest
private class AccountingTagEvaluationServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void evaluateForInvoice_skipsWhenAccountingOff() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert GlAccountingPolicyService.newOrgDefault();
      Invoice__c invoice = insertInvoice();
      insertEnabledRule('off-missing', 'IsSplitMoved__c');
      AccountingTagEvaluationService.evaluateForInvoice(invoice.Id);
      Invoice__c stored = [
        SELECT IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        false,
        stored.IsSplitMoved__c,
        'Accounting 第7.5節: OFFでは会計タグルールを評価せず保存済みタグ値も変えない'
      );
    }
  }

  @IsTest
  static void save_rejectsMissingTargetWhenEnabled() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        insertEnabledRule('on-missing', 'Missing_Tag_Target__c');
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('保存先項目がありません'),
          'Accounting 第7.4節: 有効=Trueの保存で保存先の存在を検証する。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_rejectsDuplicateTargetsWhenEnabled() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insertEnabledRule('dup-a', 'IsSplitMoved__c');
      Boolean thrown = false;
      try {
        insertEnabledRule('dup-b', 'IsSplitMoved__c');
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('同じ保存先項目'),
          'Accounting 第7.4節: 同じ保存先を複数の有効ルールが更新してはならない。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void evaluateForInvoice_ignoresDisabledBrokenRule() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      insert new GlAccountingTagRule__c(
        Name = '無効',
        TagKey__c = 'disabled-broken',
        IsEnabled__c = false
      );
      AccountingTagEvaluationService.evaluateForInvoice(invoice.Id);
      Invoice__c stored = [
        SELECT IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        false,
        stored.IsSplitMoved__c,
        'Accounting 第7.2節: 有効=Falseのルールは保存先を検証しない'
      );
    }
  }

  @IsTest
  static void save_normalizesExpressionSpacesWhenEnabled() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new GlAccountingTagRule__c(
        Name = '正規化',
        TagKey__c = 'normalize-spaces',
        TagLabel__c = 'AR残あり',
        Expression__c = 'AR  -  DEF',
        ComparisonOperator__c = 'NE',
        ComparisonValue__c = 0,
        TargetFieldApiName__c = 'IsSplitMoved__c',
        IsEnabled__c = true
      );
      GlAccountingTagRule__c stored = [
        SELECT Expression__c
        FROM GlAccountingTagRule__c
        WHERE TagKey__c = 'normalize-spaces'
      ];
      System.assertEquals(
        'AR - DEF',
        stored.Expression__c,
        'Accounting 第7.3節: 保存時はトークン間を1個の半角スペースへ正規化する'
      );
    }
  }

  @IsTest
  static void save_rejectsUnspacedExpressionWhenEnabled() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        insert new GlAccountingTagRule__c(
          Name = '字句',
          TagKey__c = 'unspaced',
          TagLabel__c = 'AR残あり',
          Expression__c = 'AR-DEF',
          ComparisonOperator__c = 'NE',
          ComparisonValue__c = 0,
          TargetFieldApiName__c = 'IsSplitMoved__c',
          IsEnabled__c = true
        );
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('未知のトークン') ||
            ex.getMessage().contains('式が不正'),
          'Accounting 第7.3節・第7.4節: 有効時は式の字句・構文を検証する。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_rejectsNonCheckboxTargetWhenEnabled() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        insertEnabledRule('not-bool', 'Amount__c');
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('チェックボックスではありません'),
          'Accounting 第7.4節: 保存先はチェックボックス型。実際: ' + ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_skipsExpressionValidationWhenDisabled() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new GlAccountingTagRule__c(
        Name = '無効式',
        TagKey__c = 'disabled-unspaced',
        Expression__c = 'AR-DEF',
        IsEnabled__c = false
      );
      GlAccountingTagRule__c stored = [
        SELECT Expression__c, IsEnabled__c
        FROM GlAccountingTagRule__c
        WHERE TagKey__c = 'disabled-unspaced'
      ];
      System.assertEquals(
        'AR-DEF',
        stored.Expression__c,
        'Accounting 第7.4節: 有効=Falseでは式を検証しない'
      );
    }
  }

  @IsTest
  static void save_skipsTargetValidationWhenDisabled() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new GlAccountingTagRule__c(
        Name = '無効保存先',
        TagKey__c = 'disabled-bad-target',
        TargetFieldApiName__c = 'Amount__c',
        IsEnabled__c = false
      );
      GlAccountingTagRule__c stored = [
        SELECT TargetFieldApiName__c
        FROM GlAccountingTagRule__c
        WHERE TagKey__c = 'disabled-bad-target'
      ];
      System.assertEquals(
        'Amount__c',
        stored.TargetFieldApiName__c,
        'Accounting 第7.4節: 有効=Falseでは保存先項目を検証しない'
      );
    }
  }

  @IsTest
  static void delete_rejectsEnabledRule() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insertEnabledRule('del-enabled', 'IsSplitMoved__c');
      GlAccountingTagRule__c stored = [
        SELECT Id
        FROM GlAccountingTagRule__c
        WHERE TagKey__c = 'del-enabled'
      ];
      Boolean thrown = false;
      try {
        delete stored;
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('有効な会計タグルールは削除できません'),
          'Accounting 第7.2節: ルール削除は有効=Falseの場合だけ許可する。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_acceptsParenthesizedNormalExample() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new GlAccountingTagRule__c(
        Name = '括弧正常',
        TagKey__c = 'paren-ok',
        TagLabel__c = '純額',
        Expression__c = '( AR + CTA ) - ( DEF + UAC )',
        ComparisonOperator__c = 'NE',
        ComparisonValue__c = 0,
        TargetFieldApiName__c = 'IsSplitMoved__c',
        IsEnabled__c = true
      );
      GlAccountingTagRule__c stored = [
        SELECT Expression__c
        FROM GlAccountingTagRule__c
        WHERE TagKey__c = 'paren-ok'
      ];
      System.assertEquals(
        '( AR + CTA ) - ( DEF + UAC )',
        stored.Expression__c,
        'Accounting 第7.3節: 正常例の括弧つき加減算は保存できる'
      );
    }
  }

  @IsTest
  static void save_rejectsSpecInvalidExpressions() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      assertEnabledExpressionRejected(
        'bad-nospace-paren',
        '(AR + DEF)',
        '未知のトークン',
        'Accounting 第7.3節: 不正例 (AR + DEF) は字句エラー'
      );
      assertEnabledExpressionRejected(
        'bad-multiply',
        'AR * DEF',
        '式が不正',
        'Accounting 第7.3節: 掛け算は許可しない'
      );
      assertEnabledExpressionRejected(
        'bad-divide',
        'AR / DEF',
        '式が不正',
        'Accounting 第7.3節: 割り算は許可しない'
      );
      assertEnabledExpressionRejected(
        'bad-tab',
        'AR\t-\tDEF',
        '半角スペースでトークンを区切ってください',
        'Accounting 第7.3節: 隣接トークン間は半角スペース必須'
      );
      assertEnabledExpressionRejected(
        'bad-number',
        'AR + 100',
        '未知のトークン',
        'Accounting 第7.3節: 数値は式から参照できない'
      );
      assertEnabledExpressionRejected(
        'bad-invoice-field',
        'Invoice__c.Amount__c',
        '未知のトークン',
        'Accounting 第7.3節: 請求書項目は式から参照できない'
      );
      assertEnabledExpressionRejected(
        'bad-formal-key',
        'AccountsReceivable',
        '未知のトークン',
        'Accounting 第7.3節: 式は略称トークンだけ。正式キーとは区別する'
      );
      assertEnabledExpressionRejected(
        'bad-unmatched-paren',
        '( AR + CTA',
        '括弧が対応していません',
        'Accounting 第7.4節: 括弧対応を検証する'
      );
      assertEnabledExpressionRejected(
        'bad-compare-in-expr',
        'AR != 0',
        '式が不正',
        'Accounting 第7.3節: True/Falseの比較を式本文へ含めない'
      );
    }
  }

  @IsTest
  static void save_rejectsDuplicateTagKey() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insertEnabledRule('same-tag-key', 'IsSplitMoved__c');
      Boolean thrown = false;
      try {
        insert new GlAccountingTagRule__c(
          Name = 'キー重複',
          TagKey__c = 'same-tag-key',
          TagLabel__c = '別ラベル',
          Expression__c = 'AR',
          ComparisonOperator__c = 'EQ',
          ComparisonValue__c = 0,
          TargetFieldApiName__c = 'IsManuallyAdjusted__c',
          IsEnabled__c = true
        );
      } catch (DmlException ex) {
        thrown = true;
        System.assertEquals(
          StatusCode.DUPLICATE_VALUE,
          ex.getDmlType(0),
          'Accounting 第7.4節: タグキーの一意性を検証する。実際: ' + ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_rejectsEnabledWithoutTagLabel() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        insert new GlAccountingTagRule__c(
          Name = 'ラベルなし',
          TagKey__c = 'no-label',
          Expression__c = 'AR',
          ComparisonOperator__c = 'NE',
          ComparisonValue__c = 0,
          TargetFieldApiName__c = 'IsSplitMoved__c',
          IsEnabled__c = true
        );
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('タグラベル'),
          'Accounting 第7.2節: 有効時はタグラベルを必須にする。実際: ' + ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_rejectsEnablingInvalidExpression() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new GlAccountingTagRule__c(
        Name = '後から有効',
        TagKey__c = 'enable-later',
        Expression__c = 'AR-DEF',
        IsEnabled__c = false
      );
      Boolean thrown = false;
      try {
        update new GlAccountingTagRule__c(
          Id = [
            SELECT Id
            FROM GlAccountingTagRule__c
            WHERE TagKey__c = 'enable-later'
          ]
          .Id,
          TagLabel__c = 'AR残あり',
          Expression__c = 'AR-DEF',
          ComparisonOperator__c = 'NE',
          ComparisonValue__c = 0,
          TargetFieldApiName__c = 'IsSplitMoved__c',
          IsEnabled__c = true
        );
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('未知のトークン') ||
            ex.getMessage().contains('式が不正'),
          'Accounting 第7.4節: 検出可能な不備があればルールを有効にしない。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_allowsNegativeComparisonValue() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new GlAccountingTagRule__c(
        Name = '負の比較値',
        TagKey__c = 'neg-compare',
        TagLabel__c = '負残',
        Expression__c = 'AR',
        ComparisonOperator__c = 'LT',
        ComparisonValue__c = -1,
        TargetFieldApiName__c = 'IsSplitMoved__c',
        IsEnabled__c = true
      );
      GlAccountingTagRule__c stored = [
        SELECT ComparisonValue__c
        FROM GlAccountingTagRule__c
        WHERE TagKey__c = 'neg-compare'
      ];
      System.assertEquals(
        -1,
        stored.ComparisonValue__c,
        'Accounting 第7.2節: 比較値は符号付き整数円'
      );
    }
  }

  @IsTest
  static void save_allowsTwoEnabledRulesWithDifferentTargets() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insertEnabledRule('two-a', 'IsSplitMoved__c');
      insertEnabledRule('two-b', 'IsManuallyAdjusted__c');
      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM GlAccountingTagRule__c
          WHERE TagKey__c IN ('two-a', 'two-b') AND IsEnabled__c = TRUE
        ],
        'Accounting 第7.4節: 保存先が異なれば複数の有効ルールを保存できる'
      );
    }
  }

  @IsTest
  static void save_doesNotReevaluateExistingInvoice() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      invoice.IsSplitMoved__c = true;
      update invoice;

      insertEnabledRule('no-reeval', 'IsSplitMoved__c');

      Invoice__c stored = [
        SELECT IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        true,
        stored.IsSplitMoved__c,
        'Accounting 第7.5節: ルールの作成だけでは既存請求書を一括再評価しない'
      );
    }
  }

  @IsTest
  static void evaluateForInvoice_overwritesCheckboxFromComparison() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      invoice.IsSplitMoved__c = true;
      update invoice;
      insertEnabledRule('overwrite', 'IsSplitMoved__c');

      AccountingTagEvaluationService.evaluateForInvoice(invoice.Id);

      Invoice__c stored = [
        SELECT IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        false,
        stored.IsSplitMoved__c,
        'Accounting 第7.2節・第7.3節: 有効ルールは次の評価時に計算結果で上書きする（AR!=0は残高0でFalse）'
      );
    }
  }

  @IsTest
  static void disable_doesNotClearSavedCheckbox() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      insert new GlAccountingTagRule__c(
        Name = '無効化後も残す',
        TagKey__c = 'keep-after-disable',
        TagLabel__c = 'ARゼロ',
        Expression__c = 'AR',
        ComparisonOperator__c = 'EQ',
        ComparisonValue__c = 0,
        TargetFieldApiName__c = 'IsSplitMoved__c',
        IsEnabled__c = true
      );
      AccountingTagEvaluationService.evaluateForInvoice(invoice.Id);
      Invoice__c afterEval = [
        SELECT IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        true,
        afterEval.IsSplitMoved__c,
        'Accounting 第7.3節: AR=0は残高0でTrue'
      );

      update new GlAccountingTagRule__c(
        Id = [
          SELECT Id
          FROM GlAccountingTagRule__c
          WHERE TagKey__c = 'keep-after-disable'
        ]
        .Id,
        IsEnabled__c = false
      );
      Invoice__c afterDisable = [
        SELECT IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        true,
        afterDisable.IsSplitMoved__c,
        'Accounting 第7.2節: 有効=Falseにした時点で保存済みチェックボックスをFalseへ戻さない'
      );
    }
  }

  @IsTest
  static void save_allowsAllTwelveSlotAbbreviations() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new GlAccountingTagRule__c(
        Name = '12略称',
        TagKey__c = 'all-abbreviations',
        TagLabel__c = '全スロット',
        Expression__c = 'AR + CTA + CASH + DEF + TAX + UAC + SP + REV + FXG + FXL + OIN + OEX',
        ComparisonOperator__c = 'NE',
        ComparisonValue__c = 0,
        TargetFieldApiName__c = 'IsSplitMoved__c',
        IsEnabled__c = true
      );
      GlAccountingTagRule__c stored = [
        SELECT Expression__c
        FROM GlAccountingTagRule__c
        WHERE TagKey__c = 'all-abbreviations'
      ];
      System.assertEquals(
        'AR + CTA + CASH + DEF + TAX + UAC + SP + REV + FXG + FXL + OIN + OEX',
        stored.Expression__c,
        'Accounting 第7.3節: 式で使える略称は12個に固定する'
      );
    }
  }

  @IsTest
  static void save_allowsHeaderAmountAbbreviations() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new GlAccountingTagRule__c(
        Name = 'ヘッダ略称',
        TagKey__c = 'header-abbreviations',
        TagLabel__c = '税抜と税',
        Expression__c = 'REV - AMT + TAX - INVTAX + INCL',
        ComparisonOperator__c = 'NE',
        ComparisonValue__c = 0,
        TargetFieldApiName__c = 'IsSplitMoved__c',
        IsEnabled__c = true
      );
      GlAccountingTagRule__c stored = [
        SELECT Expression__c
        FROM GlAccountingTagRule__c
        WHERE TagKey__c = 'header-abbreviations'
      ];
      System.assertEquals(
        'REV - AMT + TAX - INVTAX + INCL',
        stored.Expression__c,
        'Accounting 第7.3節: AMT／INVTAX／INCL を許可トークンにする'
      );
    }
  }

  @IsTest
  static void evaluateForInvoice_usesSavedHeaderAmountsAsIntegerYen() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      insert new GlAccountingTagRule__c(
        Name = '税込一致',
        TagKey__c = 'incl-eq',
        TagLabel__c = '税込1100',
        Expression__c = 'INCL',
        ComparisonOperator__c = 'EQ',
        ComparisonValue__c = 1100,
        TargetFieldApiName__c = 'IsSplitMoved__c',
        IsEnabled__c = true
      );
      AccountingTagEvaluationService.evaluateForInvoice(invoice.Id);
      Invoice__c stored = [
        SELECT IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        true,
        stored.IsSplitMoved__c,
        'Accounting 第7.3節: INCL は保存済み TaxInclusiveAmount__c の整数円'
      );
    }
  }

  @IsTest
  static void save_rejectsDuplicateTargetsInSameDml() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      Boolean thrown = false;
      try {
        insert new List<GlAccountingTagRule__c>{
          new GlAccountingTagRule__c(
            Name = '同一DML-A',
            TagKey__c = 'batch-dup-a',
            TagLabel__c = 'A',
            Expression__c = 'AR',
            ComparisonOperator__c = 'NE',
            ComparisonValue__c = 0,
            TargetFieldApiName__c = 'IsSplitMoved__c',
            IsEnabled__c = true
          ),
          new GlAccountingTagRule__c(
            Name = '同一DML-B',
            TagKey__c = 'batch-dup-b',
            TagLabel__c = 'B',
            Expression__c = 'DEF',
            ComparisonOperator__c = 'NE',
            ComparisonValue__c = 0,
            TargetFieldApiName__c = 'IsSplitMoved__c',
            IsEnabled__c = true
          )
        };
      } catch (DmlException ex) {
        thrown = true;
        System.assert(
          ex.getMessage().contains('同じ保存先項目'),
          'Accounting 第7.4節: 同一保存の複数行でも保存先重複を検出する。実際: ' +
            ex.getMessage()
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void save_allowsUpdatingEnabledRuleWithoutRetarget() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insertEnabledRule('self-update', 'IsSplitMoved__c');
      Id ruleId = [
        SELECT Id
        FROM GlAccountingTagRule__c
        WHERE TagKey__c = 'self-update'
      ]
      .Id;
      update new GlAccountingTagRule__c(Id = ruleId, Name = '名称だけ変更');
      GlAccountingTagRule__c stored = [
        SELECT Name, TargetFieldApiName__c, IsEnabled__c
        FROM GlAccountingTagRule__c
        WHERE Id = :ruleId
      ];
      System.assertEquals(
        '名称だけ変更',
        stored.Name,
        'Accounting 第7.4節: 有効ルールの自己更新は同じ保存先のままで保存できる'
      );
      System.assertEquals('IsSplitMoved__c', stored.TargetFieldApiName__c);
    }
  }

  @IsTest
  static void evaluateForInvoice_excludesLogicallyDeleted() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      insertArDebitJournal(
        invoice.Id,
        1000,
        'LogicallyDeleted',
        false,
        Date.newInstance(2026, 6, 1),
        'tag-deleted'
      );
      insertEnabledRule('excl-deleted', 'IsSplitMoved__c');
      AccountingTagEvaluationService.evaluateForInvoice(invoice.Id);
      Invoice__c stored = [
        SELECT IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        false,
        stored.IsSplitMoved__c,
        'Accounting 第7.3節: 論理削除仕訳を除外する（AR!=0は残高0でFalse）'
      );
    }
  }

  @IsTest
  static void evaluateForInvoice_netsReversalAgainstActive() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      insertArDebitJournal(
        invoice.Id,
        1000,
        'Active',
        false,
        Date.newInstance(2026, 6, 1),
        'tag-active'
      );
      insertArDebitJournal(
        invoice.Id,
        1000,
        'Reversal',
        false,
        Date.newInstance(2026, 6, 2),
        'tag-reversal'
      );
      insertEnabledRule('net-reversal', 'IsSplitMoved__c');
      AccountingTagEvaluationService.evaluateForInvoice(invoice.Id);
      Invoice__c stored = [
        SELECT IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        false,
        stored.IsSplitMoved__c,
        'Accounting 第7.3節: 有効な元仕訳と取消仕訳をNet集計する（+1000と取消-1000でAR!=0はFalse）'
      );
    }
  }

  @IsTest
  static void evaluateForInvoice_includesLockedAndFutureDated() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      insertArDebitJournal(
        invoice.Id,
        1000,
        'Active',
        true,
        Date.newInstance(2099, 1, 1),
        'tag-future-lock'
      );
      insert new GlAccountingTagRule__c(
        Name = '将来ロック',
        TagKey__c = 'future-lock',
        TagLabel__c = 'AR正',
        Expression__c = 'AR',
        ComparisonOperator__c = 'GT',
        ComparisonValue__c = 0,
        TargetFieldApiName__c = 'IsSplitMoved__c',
        IsEnabled__c = true
      );
      AccountingTagEvaluationService.evaluateForInvoice(invoice.Id);
      Invoice__c stored = [
        SELECT IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        true,
        stored.IsSplitMoved__c,
        'Accounting 第7.3節: 計上日・将来到来・ロック状態で絞らずNet集計する'
      );
    }
  }

  @IsTest
  static void evaluateForInvoice_oppositeSideIsNegative() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      GlAccountingPolicy__c policy = GlAccountingPolicyService.newOrgDefault();
      policy.AccountingEnabled__c = true;
      insert policy;
      Invoice__c invoice = insertInvoice();
      insertSlotJournal(
        invoice.Id,
        'DeferredRevenue',
        'AccountsReceivable',
        'Liability',
        'Asset',
        1000,
        'Active',
        false,
        Date.newInstance(2026, 6, 1),
        'tag-credit-ar'
      );
      insert new GlAccountingTagRule__c(
        Name = '反対方向',
        TagKey__c = 'opposite-ar',
        TagLabel__c = 'AR負',
        Expression__c = 'AR',
        ComparisonOperator__c = 'LT',
        ComparisonValue__c = 0,
        TargetFieldApiName__c = 'IsSplitMoved__c',
        IsEnabled__c = true
      );
      AccountingTagEvaluationService.evaluateForInvoice(invoice.Id);
      Invoice__c stored = [
        SELECT IsSplitMoved__c
        FROM Invoice__c
        WHERE Id = :invoice.Id
      ];
      System.assertEquals(
        true,
        stored.IsSplitMoved__c,
        'Accounting 第7.3節: 通常残高方向を正、反対方向を負とする（AR貸方は負）'
      );
    }
  }

  @IsTest
  static void delete_allowsDisabledRule() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      insert new GlAccountingTagRule__c(
        Name = '無効削除',
        TagKey__c = 'del-disabled',
        IsEnabled__c = false
      );
      delete [
        SELECT Id
        FROM GlAccountingTagRule__c
        WHERE TagKey__c = 'del-disabled'
      ];
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM GlAccountingTagRule__c
          WHERE TagKey__c = 'del-disabled'
        ],
        'Accounting 第7.2節: 無効ルールの削除は許可する'
      );
    }
  }

  private static void assertEnabledExpressionRejected(
    String key,
    String expression,
    String messagePart,
    String specNote
  ) {
    Boolean thrown = false;
    try {
      insert new GlAccountingTagRule__c(
        Name = '式検証',
        TagKey__c = key,
        TagLabel__c = 'AR残あり',
        Expression__c = expression,
        ComparisonOperator__c = 'NE',
        ComparisonValue__c = 0,
        TargetFieldApiName__c = 'IsSplitMoved__c',
        IsEnabled__c = true
      );
    } catch (DmlException ex) {
      thrown = true;
      System.assert(
        ex.getMessage().contains(messagePart),
        specNote + ' 実際: ' + ex.getMessage()
      );
    }
    System.assertEquals(true, thrown, specNote);
  }

  private static void insertArDebitJournal(
    Id invoiceId,
    Decimal amount,
    String status,
    Boolean locked,
    Date postingDate,
    String keySuffix
  ) {
    insertSlotJournal(
      invoiceId,
      'AccountsReceivable',
      'DeferredRevenue',
      'Asset',
      'Liability',
      amount,
      status,
      locked,
      postingDate,
      keySuffix
    );
  }

  private static void insertSlotJournal(
    Id invoiceId,
    String debitSlot,
    String creditSlot,
    String debitType,
    String creditType,
    Decimal amount,
    String status,
    Boolean locked,
    Date postingDate,
    String keySuffix
  ) {
    GlAccount__c debit = new GlAccount__c(
      Name = keySuffix + ' Debit',
      AccountType__c = debitType,
      IsActive__c = true
    );
    GlAccount__c credit = new GlAccount__c(
      Name = keySuffix + ' Credit',
      AccountType__c = creditType,
      IsActive__c = true
    );
    insert new List<GlAccount__c>{ debit, credit };
    insert new GlJournal__c(
      Invoice__c = invoiceId,
      Amount__c = amount,
      IdempotencyKey__c = AccountingDiffService.hashKey(
        new List<String>{ keySuffix, String.valueOf(invoiceId) }
      ),
      DebitSlotKey__c = debitSlot,
      CreditSlotKey__c = creditSlot,
      DebitAccount__c = debit.Id,
      CreditAccount__c = credit.Id,
      PostingDate__c = postingDate,
      TransactionStatus__c = status,
      IsLocked__c = locked
    );
  }

  private static void insertEnabledRule(String key, String targetField) {
    insert new GlAccountingTagRule__c(
      Name = 'AR残',
      TagKey__c = key,
      TagLabel__c = 'AR残あり',
      Expression__c = 'AR',
      ComparisonOperator__c = 'NE',
      ComparisonValue__c = 0,
      TargetFieldApiName__c = targetField,
      IsEnabled__c = true
    );
  }

  private static Invoice__c insertInvoice() {
    Account account = ContractTestDataFactory.insertAccount(
      'Tag ' + String.valueOf(Crypto.getRandomInteger())
    );
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = ContractTestDataFactory.TENANT_BILLING_ADDRESSEE_DEFAULT,
      BillingEmailTo__c = 'tag@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 1,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;
    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      'Tag Opp'
    );
    ContractService__c service = new ContractService__c(
      Name = 'Tag Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = 0.1
    );
    insert service;
    ContractHistory__c history = new ContractHistory__c(
      Name = 'Tag History',
      ContractService__c = service.Id,
      Opportunity__c = opportunity.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1
    );
    insert history;
    Invoice__c invoice = new Invoice__c(
      ContractService__c = service.Id,
      ContractHistory__c = history.Id,
      InvoiceDate__c = Date.newInstance(2026, 6, 1),
      Amount__c = 1000,
      TaxAmount__c = 100,
      TaxInclusiveAmount__c = 1100,
      BillingAccountSnapShot__c = billingAccount.Id,
      InvoiceTransactionStatus__c = InvoiceTransactionStatusService.TX_DRAFT
    );
    insert invoice;
    return invoice;
  }
}
