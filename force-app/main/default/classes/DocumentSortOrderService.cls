/**
 * 帳票表示順の写しと並び。
 */
public with sharing class DocumentSortOrderService {
  /** 仕様: Core 第4.5.3節。挿入の直前、番号が空の契約商品だけ商品の帳票表示順を書く。 */
  public static void fillContractProducts(List<ContractProduct__c> rows) {
    if (rows == null || rows.isEmpty()) {
      return;
    }
    Set<Id> productIds = new Set<Id>();
    for (ContractProduct__c row : rows) {
      if (needsProductOrder(row)) {
        productIds.add(row.Product__c);
      }
    }
    if (productIds.isEmpty()) {
      return;
    }
    Map<Id, Product2> products = new Map<Id, Product2>([
      SELECT Id, DocumentSortOrder__c
      FROM Product2
      WHERE Id IN :productIds
      WITH SYSTEM_MODE
    ]);
    for (ContractProduct__c row : rows) {
      if (!needsProductOrder(row)) {
        continue;
      }
      Product2 product = products.get(row.Product__c);
      if (product == null) {
        continue;
      }
      row.DocumentSortOrder__c = product.DocumentSortOrder__c;
    }
  }

  /** 仕様: Core 第4.5.3節。挿入の直前、番号が空の請求明細だけ元の契約商品の番号をコピーする。 */
  public static void fillInvoiceLines(List<InvoiceLine__c> rows) {
    if (rows == null || rows.isEmpty()) {
      return;
    }
    Set<Id> contractProductIds = new Set<Id>();
    for (InvoiceLine__c row : rows) {
      if (needsContractProductOrder(row)) {
        contractProductIds.add(row.ContractProduct__c);
      }
    }
    if (contractProductIds.isEmpty()) {
      return;
    }
    Map<Id, ContractProduct__c> contractProducts = new Map<Id, ContractProduct__c>([
      SELECT Id, DocumentSortOrder__c
      FROM ContractProduct__c
      WHERE Id IN :contractProductIds
      WITH SYSTEM_MODE
    ]);
    for (InvoiceLine__c row : rows) {
      if (!needsContractProductOrder(row)) {
        continue;
      }
      ContractProduct__c source = contractProducts.get(row.ContractProduct__c);
      if (source == null) {
        continue;
      }
      row.DocumentSortOrder__c = source.DocumentSortOrder__c;
    }
  }

  /** 仕様: Core 第4.5.3節 */
  public static void sortContractProducts(List<ContractProduct__c> rows) {
    if (rows == null || rows.size() < 2) {
      return;
    }
    rows.sort(new ContractProductOrder());
  }

  /** 仕様: Core 第4.5.3節。請求明細は変更前／変更後の段を使わない。 */
  public static void sortInvoiceLines(List<InvoiceLine__c> rows) {
    if (rows == null || rows.size() < 2) {
      return;
    }
    rows.sort(new InvoiceLineOrder());
  }

  private static Boolean needsProductOrder(ContractProduct__c row) {
    return row != null &&
      row.DocumentSortOrder__c == null &&
      row.Product__c != null;
  }

  private static Boolean needsContractProductOrder(InvoiceLine__c row) {
    return row != null &&
      row.DocumentSortOrder__c == null &&
      row.ContractProduct__c != null;
  }

  @TestVisible
  private static Integer compareKeys(
    Decimal leftOrder,
    String leftType,
    Date leftStart,
    String leftName,
    Decimal rightOrder,
    String rightType,
    Date rightStart,
    String rightName,
    Boolean applyTypeStage
  ) {
    Integer orderCompare = compareOrder(leftOrder, rightOrder);
    if (orderCompare != 0) {
      return orderCompare;
    }
    if (applyTypeStage == true) {
      Integer typeCompare = compareOriginalRemake(leftType, rightType);
      if (typeCompare != 0) {
        return typeCompare;
      }
    }
    Integer startCompare = compareStart(leftStart, rightStart);
    if (startCompare != 0) {
      return startCompare;
    }
    return compareLineName(leftName, rightName);
  }

  private static Integer compareOrder(Decimal left, Decimal right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    if (left == right) {
      return 0;
    }
    return left < right ? -1 : 1;
  }

  private static Integer compareOriginalRemake(String leftType, String rightType) {
    Boolean leftPair = isOriginalOrRemake(leftType);
    Boolean rightPair = isOriginalOrRemake(rightType);
    if (leftPair != true || rightPair != true) {
      return 0;
    }
    Integer leftRank = leftType == ContractDomainConstants.PRODUCT_TYPE_ORIGINAL
      ? 0
      : 1;
    Integer rightRank = rightType == ContractDomainConstants.PRODUCT_TYPE_ORIGINAL
      ? 0
      : 1;
    if (leftRank == rightRank) {
      return 0;
    }
    return leftRank < rightRank ? -1 : 1;
  }

  private static Boolean isOriginalOrRemake(String typeValue) {
    return typeValue == ContractDomainConstants.PRODUCT_TYPE_ORIGINAL ||
      typeValue == ContractDomainConstants.PRODUCT_TYPE_REMAKE;
  }

  private static Integer compareStart(Date left, Date right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    if (left == right) {
      return 0;
    }
    return left < right ? -1 : 1;
  }

  private static Integer compareLineName(String left, String right) {
    if (String.isBlank(left) && String.isBlank(right)) {
      return 0;
    }
    if (String.isBlank(left)) {
      return 1;
    }
    if (String.isBlank(right)) {
      return -1;
    }
    return left.compareTo(right);
  }

  private class ContractProductOrder implements System.Comparator<ContractProduct__c> {
    public Integer compare(ContractProduct__c left, ContractProduct__c right) {
      if (left == right) {
        return 0;
      }
      if (left == null) {
        return 1;
      }
      if (right == null) {
        return -1;
      }
      return compareKeys(
        left.DocumentSortOrder__c,
        left.Type__c,
        left.StartDate__c,
        left.Name,
        right.DocumentSortOrder__c,
        right.Type__c,
        right.StartDate__c,
        right.Name,
        true
      );
    }
  }

  private class InvoiceLineOrder implements System.Comparator<InvoiceLine__c> {
    public Integer compare(InvoiceLine__c left, InvoiceLine__c right) {
      if (left == right) {
        return 0;
      }
      if (left == null) {
        return 1;
      }
      if (right == null) {
        return -1;
      }
      return compareKeys(
        left.DocumentSortOrder__c,
        null,
        left.ServicePeriodStartDate__c,
        left.Name,
        right.DocumentSortOrder__c,
        null,
        right.ServicePeriodStartDate__c,
        right.Name,
        false
      );
    }
  }
}
