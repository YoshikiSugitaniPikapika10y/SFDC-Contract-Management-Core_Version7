import {
  BILLING_TYPE_RECURRING,
  INVOICE_ANCHOR_DISPLAY_TITLE,
  INVOICE_SETTING_POSTPAID_NEXT_DAY,
  INVOICE_SETTING_PREPAID_START,
  INVOICE_SETTING_SPLIT_MONTHLY,
  PRODUCT_TYPE_NEW,
  PRODUCT_TYPE_ORIGINAL,
  PRODUCT_TYPE_REMAKE,
  resolveInvoiceAnchorFields
} from "c/estimateLineItemUtils";

describe("resolveInvoiceAnchorFields", () => {
  const recurringRow = {
    billingType: BILLING_TYPE_RECURRING,
    invoiceType: INVOICE_SETTING_PREPAID_START,
    startDate: "2026-04-01",
    endDate: "2027-03-31",
    recordType: PRODUCT_TYPE_REMAKE,
    sourceContractProductId: "src-1",
    quantity: 1,
    unitPrice: 1000
  };

  const unchangedOriginal = {
    ...recurringRow,
    recordType: PRODUCT_TYPE_ORIGINAL,
    id: "orig-1"
  };
  const unchangedRemake = {
    ...recurringRow,
    recordType: PRODUCT_TYPE_REMAKE,
    id: "remake-1"
  };
  const changedRemake = {
    ...unchangedRemake,
    unitPrice: 2000
  };

  it("returns empty display when invoice setting is blank", () => {
    const result = resolveInvoiceAnchorFields(
      { ...recurringRow, invoiceType: "" },
      "New",
      "2026-04-01"
    );
    expect(result.showInvoiceAnchor).toBe(false);
    expect(result.displayValue).toBe("");
  });

  it("uses start date for prepaid new", () => {
    const result = resolveInvoiceAnchorFields(
      { ...recurringRow, recordType: "New" },
      "New",
      "2026-04-01"
    );
    expect(result.displayValue).toBe("2026-04-01");
    expect(result.billingCycleCount).toBeNull();
  });

  it("uses effective date for change prepaid remake with billing event", () => {
    const products = [unchangedOriginal, changedRemake];
    const result = resolveInvoiceAnchorFields(
      changedRemake,
      "Change",
      "2026-05-01",
      { products }
    );
    expect(result.anchorDate).toBe("2026-05-01");
    expect(result.displayValue).toBe("2026-05-01");
    expect(result.showInvoiceAnchor).toBe(true);
  });

  it("hides invoice anchor for unchanged change original/remake", () => {
    const products = [unchangedOriginal, unchangedRemake];
    const originalResult = resolveInvoiceAnchorFields(
      unchangedOriginal,
      "Change",
      "2026-07-27",
      { products }
    );
    const remakeResult = resolveInvoiceAnchorFields(
      unchangedRemake,
      "Change",
      "2026-07-27",
      { products }
    );
    expect(originalResult.showInvoiceAnchor).toBe(false);
    expect(originalResult.displayValue).toBe("");
    expect(remakeResult.showInvoiceAnchor).toBe(false);
    expect(remakeResult.displayValue).toBe("");
  });

  it("still shows invoice anchor for change prepaid new", () => {
    const products = [
      unchangedOriginal,
      unchangedRemake,
      {
        ...recurringRow,
        recordType: PRODUCT_TYPE_NEW,
        sourceContractProductId: null,
        startDate: "2026-10-01",
        endDate: "2026-10-01"
      }
    ];
    const result = resolveInvoiceAnchorFields(
      {
        ...recurringRow,
        recordType: PRODUCT_TYPE_NEW,
        sourceContractProductId: null,
        startDate: "2026-10-01"
      },
      "Change",
      "2026-05-01",
      { products }
    );
    expect(result.anchorDate).toBe("2026-10-01");
    expect(result.showInvoiceAnchor).toBe(true);
  });

  it("uses start date for change prepaid new", () => {
    const result = resolveInvoiceAnchorFields(
      {
        ...recurringRow,
        recordType: PRODUCT_TYPE_NEW,
        startDate: "2026-10-01"
      },
      "Change",
      "2026-05-01"
    );
    expect(result.anchorDate).toBe("2026-10-01");
  });

  it("returns monthly range and cycle count", () => {
    const result = resolveInvoiceAnchorFields(
      {
        ...recurringRow,
        invoiceType: INVOICE_SETTING_SPLIT_MONTHLY,
        startDate: "2025-08-01",
        endDate: "2026-07-31"
      },
      "New",
      "2025-08-01"
    );
    expect(result.displayValue).toBe("2025-08-01〜2026-07-31（12回）");
    expect(result.billingCycleCount).toBe(12);
  });

  it("returns end plus one day for postpaid", () => {
    const result = resolveInvoiceAnchorFields(
      {
        ...recurringRow,
        invoiceType: INVOICE_SETTING_POSTPAID_NEXT_DAY,
        endDate: "2026-07-31"
      },
      "New",
      "2026-04-01"
    );
    expect(result.displayValue).toBe("2026-08-01");
  });

  it("exports anchor display title", () => {
    expect(INVOICE_ANCHOR_DISPLAY_TITLE).toContain("請求書の請求日ではありません");
    expect(INVOICE_ANCHOR_DISPLAY_TITLE).toContain("請求日ルール");
  });
});
