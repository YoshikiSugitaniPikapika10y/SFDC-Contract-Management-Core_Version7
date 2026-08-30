@IsTest
private class ContractOptimisticLockUtilTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void toToken_and_assert_roundTrip() {
    Datetime stamp = Datetime.newInstance(2026, 8, 10, 1, 2, 3);
    String token = ContractOptimisticLockUtil.toToken(stamp);
    System.assertEquals(String.valueOf(stamp.getTime()), token);
    ContractOptimisticLockUtil.assertUnchanged(stamp, token, 'テスト');
  }

  @IsTest
  static void toToken_null_returnsNull() {
    System.assertEquals(null, ContractOptimisticLockUtil.toToken(null));
    System.assertEquals(null, ContractOptimisticLockUtil.parseToken(null));
    System.assertEquals(null, ContractOptimisticLockUtil.parseToken(''));
  }

  @IsTest
  static void assertUnchanged_blankToken_skips() {
    ContractOptimisticLockUtil.assertUnchanged(Datetime.now(), null, 'テスト');
    ContractOptimisticLockUtil.assertUnchanged(Datetime.now(), '', 'テスト');
  }

  @IsTest
  static void assertUnchanged_nullActual_skipsCompare() {
    ContractOptimisticLockUtil.assertUnchanged(
      null,
      ContractOptimisticLockUtil.toToken(Datetime.now()),
      'テスト'
    );
  }

  @IsTest
  static void assertHistoryUnchanged_nullHistory_throws() {
    try {
      ContractOptimisticLockUtil.assertHistoryUnchanged(null, '1');
      System.assert(false, 'Expected missing history');
    } catch (AuraHandledException ex) {
      System.assertEquals('契約履歴が見つかりません。', ex.getMessage());
    }
  }

  @IsTest
  static void assertUnchanged_mismatch_throws() {
    Datetime actual = Datetime.newInstance(2026, 8, 10, 1, 2, 3);
    String stale = ContractOptimisticLockUtil.toToken(actual.addSeconds(-10));
    try {
      ContractOptimisticLockUtil.assertUnchanged(actual, stale, '契約履歴');
      System.assert(false, 'Expected conflict');
    } catch (AuraHandledException ex) {
      System.assertEquals(
        ContractOptimisticLockUtil.CONFLICT_MESSAGE,
        ex.getMessage()
      );
    }
  }

  @IsTest
  static void assertUnchanged_invalidToken_throws() {
    try {
      ContractOptimisticLockUtil.assertUnchanged(
        Datetime.now(),
        'not-a-number',
        '契約履歴'
      );
      System.assert(false, 'Expected conflict');
    } catch (AuraHandledException ex) {
      System.assertEquals(
        ContractOptimisticLockUtil.CONFLICT_MESSAGE,
        ex.getMessage()
      );
    }
  }

  @IsTest
  static void assertRequiredUnchanged_blankOrMissingActual_throws() {
    for (Integer scenario = 0; scenario < 2; scenario++) {
      try {
        ContractOptimisticLockUtil.assertRequiredUnchanged(
          scenario == 0 ? Datetime.now() : null,
          scenario == 0
            ? null
            : ContractOptimisticLockUtil.toToken(Datetime.now()),
          'テスト'
        );
        System.assert(false, 'Expected required optimistic lock conflict');
      } catch (AuraHandledException ex) {
        System.assertEquals(
          ContractOptimisticLockUtil.CONFLICT_MESSAGE,
          ex.getMessage()
        );
      }
    }
  }
}
