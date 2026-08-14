/**
 * @deprecated テナント固有設定は ContractTestDataFactory に集約済み。
 * 互換のため委譲のみ残す（新規テストからは DataFactory を直接呼ぶこと）。
 * 選択リスト値も ContractTestDataFactory.TENANT_* を参照すること。
 */
@IsTest
public class ContractTenantTestConfig {
  public static final List<String> OPPORTUNITY_INSERT_STAGE_CANDIDATES = ContractTestDataFactory.TENANT_OPPORTUNITY_INSERT_STAGE_CANDIDATES;

  public static final List<String> OPPORTUNITY_RECORD_TYPE_DEV_NAME_CANDIDATES = ContractTestDataFactory.TENANT_OPPORTUNITY_RECORD_TYPE_DEV_NAME_CANDIDATES;

  public static void applyExtraOpportunityFields(Opportunity opportunity) {
    ContractTestDataFactory.applyTenantExtraOpportunityFields(opportunity);
  }

  public static void prepareRenewEstimateAutoCreate(Id contractServiceId) {
    ContractTestDataFactory.prepareRenewEstimateAutoCreate(contractServiceId);
  }
}
