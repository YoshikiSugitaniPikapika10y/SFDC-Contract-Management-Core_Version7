/**
 * 契約履歴 Version の採番。
 * Change／Renew／Cancel は「最新 Ordered の Version + 1」。
 * 未受注 Estimate は採番対象に含めない（同 Version の並存を許容）。
 */
public without sharing class ContractHistoryVersionUtil {
  private static final String HISTORY_STATUS_ORDERED = ContractDomainConstants.HISTORY_STATUS_ORDERED;

  public static Map<Id, Decimal> buildVersionAllocator(
    Set<Id> contractServiceIds
  ) {
    Map<Id, Decimal> allocator = new Map<Id, Decimal>();
    if (contractServiceIds == null || contractServiceIds.isEmpty()) {
      return allocator;
    }

    for (Id contractServiceId : contractServiceIds) {
      allocator.put(contractServiceId, 0);
    }

    for (AggregateResult result : [
      SELECT ContractService__c serviceId, MAX(Version__c) maxVersion
      FROM ContractHistory__c
      WHERE
        ContractService__c IN :contractServiceIds
        AND historystatus__c = :HISTORY_STATUS_ORDERED
      WITH SYSTEM_MODE
      GROUP BY ContractService__c
    ]) {
      Decimal maxVersion = (Decimal) result.get('maxVersion');
      allocator.put(
        (Id) result.get('serviceId'),
        maxVersion == null ? 0 : maxVersion
      );
    }
    return allocator;
  }

  /**
   * 最新 Ordered + 1 を返す。同一サービスへの連続呼出でも値は進まない
   * （Estimate 同士の Version 重複を許容するため）。
   */
  public static Decimal allocateNextVersion(
    Map<Id, Decimal> versionAllocator,
    Id contractServiceId
  ) {
    if (contractServiceId == null) {
      return 1;
    }

    Decimal currentMax = versionAllocator != null &&
      versionAllocator.containsKey(contractServiceId)
      ? versionAllocator.get(contractServiceId)
      : 0;
    return currentMax == null || currentMax == 0 ? 1 : currentMax + 1;
  }

  public static Decimal getNextHistoryVersion(Id contractServiceId) {
    if (contractServiceId == null) {
      return 1;
    }
    Map<Id, Decimal> allocator = buildVersionAllocator(
      new Set<Id>{ contractServiceId }
    );
    return allocateNextVersion(allocator, contractServiceId);
  }
}
