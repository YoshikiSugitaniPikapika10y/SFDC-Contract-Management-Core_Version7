import { serializeBusinessProduct } from "c/estimateCreateModal3";

describe("serializeBusinessProduct", () => {
  it("strips UI-only decorate fields and keeps business fields", () => {
    const serialized = serializeBusinessProduct({
      id: "row-1",
      productId: "01tAAA",
      productName: "プランA",
      quantity: 2,
      unit: "式",
      unitName: "式",
      billingType: "継続課金",
      billingCycle: "月次",
      unitPrice: 1000,
      amount: 24000,
      startDate: "2026-04-01",
      endDate: "2027-03-31",
      invoiceType: "月次前受",
      recordType: "New",
      typeLabel: "New",
      sourceContractProductId: null,
      pairId: null,
      isReadonly: false,
      customFields: { Memo__c: "x" },
      productVisibilityContext: { Family: "SaaS" },
      invoiceTypeOptions: [{ label: "月次前受", value: "月次前受" }],
      isInvoiceTypeDisabled: false,
      gridRowClass: "est-line",
      tableRowClass: "est-table-row",
      rowIndex: 3,
      canDelete: true,
      canDuplicate: true,
      displayAmount: "24,000",
      amountInvalid: false,
      unitPriceInvalid: false,
      typeBadgeLabel: "New",
      typeBadgeClass: "est-type-badge_new",
      isEditable: true,
      isCustomExpanded: true
    });

    expect(serialized.id).toBe("row-1");
    expect(serialized.productId).toBe("01tAAA");
    expect(serialized.customFields).toEqual({ Memo__c: "x" });
    expect(serialized.productVisibilityContext).toEqual({ Family: "SaaS" });
    expect(serialized.invoiceTypeOptions).toBeUndefined();
    expect(serialized.gridRowClass).toBeUndefined();
    expect(serialized.tableRowClass).toBeUndefined();
    expect(serialized.canDelete).toBeUndefined();
    expect(serialized.displayAmount).toBeUndefined();
    expect(serialized.typeBadgeLabel).toBeUndefined();
    expect(serialized.isEditable).toBeUndefined();
    expect(serialized.rowIndex).toBeUndefined();
  });

  it("returns null for falsy rows", () => {
    expect(serializeBusinessProduct(null)).toBeNull();
    expect(serializeBusinessProduct(undefined)).toBeNull();
  });
});
