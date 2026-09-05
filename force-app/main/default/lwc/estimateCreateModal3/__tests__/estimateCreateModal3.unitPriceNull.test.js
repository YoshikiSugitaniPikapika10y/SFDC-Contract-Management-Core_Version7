import EstimateCreateModal3 from "c/estimateCreateModal3";
import {
  BILLING_TYPE_RECURRING,
  PRODUCT_TYPE_RENEW,
  QUANTITY_UNIT_PRICE_ROUNDING_SCALE2_HALF_UP,
  AMOUNT_ROUNDING_SCALE0_HALF_UP,
  setAmountCalculationRoundingModes
} from "c/estimateLineItemUtils";

jest.mock(
  "@salesforce/apex/EstimateCreateController.getProductDefaults",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getRecurringContractProducts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getRenewContractProducts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getContractHistoryInfo",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getEstimateRemarkMasterText",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getInvoiceSettingOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getDefaultInvoiceSettingLabel",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.isAccountingEnabled",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

describe("estimateCreateModal3 unitPrice null (BUG-076 / BUG-077)", () => {
  const proto = EstimateCreateModal3.prototype;

  beforeEach(() => {
    setAmountCalculationRoundingModes({
      quantityUnitPriceRoundingMode: QUANTITY_UNIT_PRICE_ROUNDING_SCALE2_HALF_UP,
      amountRoundingMode: AMOUNT_ROUNDING_SCALE0_HALF_UP
    });
  });

  it("applyAmount preserves null unitPrice instead of coercing to 0", () => {
    const result = proto.applyAmount.call(
      {},
      {
        unitPrice: null,
        quantity: 1,
        billingType: BILLING_TYPE_RECURRING,
        startDate: "2026-04-01",
        endDate: "2027-03-31",
        amountEntryMode: false
      }
    );
    expect(result.unitPrice).toBeNull();
    expect(result.amount).toBeNull();
  });

  it("applyAmount preserves null quantity instead of coercing to 0 (BUG-093)", () => {
    const result = proto.applyAmount.call(
      {},
      {
        unitPrice: 1000,
        quantity: null,
        billingType: BILLING_TYPE_RECURRING,
        startDate: "2026-04-01",
        endDate: "2027-03-31",
        amountEntryMode: false
      }
    );
    expect(result.quantity).toBeNull();
    expect(result.amount).toBeNull();
  });

  it("buildChangeItemList keeps null quantity through applyAmount (BUG-093)", () => {
    const ctx = {
      resolvedDefaultInvoiceType: "一括前払",
      applyAmount: proto.applyAmount,
      decorateAllRows: (rows) => rows
    };
    const items = proto.buildChangeItemList.call(ctx, [
      {
        productId: "01tQQQ",
        productName: "Change Qty Null",
        unitPrice: 1000,
        quantity: null,
        billingType: BILLING_TYPE_RECURRING,
        invoiceType: "一括前払",
        revenueRecognitionBasis: "月次計上",
        startDate: "2026-04-01",
        endDate: "2027-03-31",
        contractProductId: "a0pQQQ",
        amount: 0
      }
    ]);
    expect(items).toHaveLength(2);
    expect(items[0].quantity).toBeNull();
    expect(items[1].quantity).toBeNull();
  });

  it("buildRenewItemList keeps null quantity through applyAmount (BUG-093)", () => {
    const ctx = {
      getDefaultDates: () => ({
        startDate: "2027-04-01",
        endDate: "2028-03-31"
      }),
      resolvedDefaultInvoiceType: "一括前払",
      applyAmount: proto.applyAmount,
      decorateAllRows: (rows) => rows
    };
    const items = proto.buildRenewItemList.call(ctx, [
      {
        productId: "01tRRR",
        unitPrice: 1000,
        quantity: null,
        billingType: BILLING_TYPE_RECURRING,
        invoiceType: "一括前払",
        contractProductId: "a0pRRR"
      }
    ]);
    expect(items).toHaveLength(1);
    expect(items[0].quantity).toBeNull();
  });

  it("resolveRowInvoiceType does not fill blank for Change Remake (BUG-094)", () => {
    const ctx = {
      invoiceSettingOptions: [
        { label: "一括前払" },
        { label: "月次分割" }
      ],
      resolvedDefaultInvoiceType: "一括前払"
    };
    const remake = {
      recordType: "Remake",
      typeLabel: "Remake",
      billingType: BILLING_TYPE_RECURRING,
      invoiceType: "",
      sourceContractProductId: "a0pSRC"
    };
    expect(
      proto.resolveRowInvoiceType.call(ctx, "", BILLING_TYPE_RECURRING, remake)
    ).toBe("");
  });

  it("resolveRowInvoiceType does not fill blank for Change Original (BUG-094)", () => {
    const ctx = {
      invoiceSettingOptions: [
        { label: "一括前払" },
        { label: "月次分割" }
      ],
      resolvedDefaultInvoiceType: "一括前払"
    };
    const original = {
      recordType: "Original",
      typeLabel: "Original",
      billingType: BILLING_TYPE_RECURRING,
      invoiceType: ""
    };
    expect(
      proto.resolveRowInvoiceType.call(
        ctx,
        "",
        BILLING_TYPE_RECURRING,
        original
      )
    ).toBe("");
  });

  it("resolveRowInvoiceType still fills blank for New when options loaded", () => {
    const ctx = {
      invoiceSettingOptions: [
        { label: "一括前払" },
        { label: "月次分割" }
      ],
      resolvedDefaultInvoiceType: "一括前払"
    };
    const newRow = {
      recordType: "New",
      typeLabel: "New",
      billingType: BILLING_TYPE_RECURRING,
      invoiceType: ""
    };
    expect(
      proto.resolveRowInvoiceType.call(ctx, "", BILLING_TYPE_RECURRING, newRow)
    ).toBe("一括前払");
  });

  it("resolveRowInvoiceType does not fill blank for Renew inherited (BUG-079)", () => {
    const ctx = {
      invoiceSettingOptions: [
        { label: "一括前払" },
        { label: "月次分割" }
      ],
      resolvedDefaultInvoiceType: "一括前払"
    };
    const renewRow = {
      recordType: PRODUCT_TYPE_RENEW,
      typeLabel: "Renew",
      billingType: BILLING_TYPE_RECURRING,
      invoiceType: "",
      sourceContractProductId: "a0pSRC"
    };
    expect(
      proto.resolveRowInvoiceType.call(
        ctx,
        "",
        BILLING_TYPE_RECURRING,
        renewRow
      )
    ).toBe("");
  });

  it("buildRenewItemList keeps null unitPrice from source (BUG-077)", () => {
    const ctx = {
      getDefaultDates: () => ({
        startDate: "2027-04-01",
        endDate: "2028-03-31"
      }),
      resolvedDefaultInvoiceType: "一括前払",
      applyAmount: proto.applyAmount,
      decorateAllRows: (rows) => rows
    };
    const items = proto.buildRenewItemList.call(ctx, [
      {
        productId: "01tAAA",
        productName: "Renew Product",
        unitPrice: null,
        quantity: 2,
        billingType: BILLING_TYPE_RECURRING,
        invoiceType: "一括前払",
        revenueRecognitionBasis: "月次計上",
        contractProductId: "a0pAAA"
      }
    ]);
    expect(items).toHaveLength(1);
    expect(items[0].unitPrice).toBeNull();
    expect(items[0].recordType).toBe(PRODUCT_TYPE_RENEW);
  });

  it("buildRenewItemList keeps explicit 0 unitPrice (free renew)", () => {
    const ctx = {
      getDefaultDates: () => ({
        startDate: "2027-04-01",
        endDate: "2028-03-31"
      }),
      resolvedDefaultInvoiceType: "一括前払",
      applyAmount: proto.applyAmount,
      decorateAllRows: (rows) => rows
    };
    const items = proto.buildRenewItemList.call(ctx, [
      {
        productId: "01tBBB",
        unitPrice: 0,
        quantity: 1,
        billingType: BILLING_TYPE_RECURRING,
        invoiceType: "一括前払",
        contractProductId: "a0pBBB"
      }
    ]);
    expect(items[0].unitPrice).toBe(0);
  });

  it("buildRenewItemList does not fill blank invoiceType with org default (BUG-079)", () => {
    const ctx = {
      getDefaultDates: () => ({
        startDate: "2027-04-01",
        endDate: "2028-03-31"
      }),
      resolvedDefaultInvoiceType: "一括前払",
      applyAmount: proto.applyAmount,
      decorateAllRows: (rows) => rows
    };
    const items = proto.buildRenewItemList.call(ctx, [
      {
        productId: "01tCCC",
        unitPrice: 1000,
        quantity: 1,
        billingType: BILLING_TYPE_RECURRING,
        invoiceType: "",
        contractProductId: "a0pCCC"
      }
    ]);
    expect(items[0].invoiceType).toBe("");
  });

  it("buildChangeItemList keeps null unitPrice from source (BUG-083)", () => {
    const ctx = {
      resolvedDefaultInvoiceType: "一括前払",
      applyAmount: proto.applyAmount,
      decorateAllRows: (rows) => rows
    };
    const items = proto.buildChangeItemList.call(ctx, [
      {
        productId: "01tDDD",
        productName: "Change Product",
        unitPrice: null,
        quantity: 2,
        billingType: BILLING_TYPE_RECURRING,
        invoiceType: "一括前払",
        revenueRecognitionBasis: "月次計上",
        startDate: "2026-04-01",
        endDate: "2027-03-31",
        contractProductId: "a0pDDD",
        amount: 0
      }
    ]);
    expect(items).toHaveLength(2);
    expect(items[0].unitPrice).toBeNull();
    expect(items[1].unitPrice).toBeNull();
  });

  it("buildChangeItemList does not fill blank invoiceType with org default (BUG-084)", () => {
    const ctx = {
      resolvedDefaultInvoiceType: "一括前払",
      applyAmount: proto.applyAmount,
      decorateAllRows: (rows) => rows
    };
    const items = proto.buildChangeItemList.call(ctx, [
      {
        productId: "01tEEE",
        unitPrice: 1000,
        quantity: 1,
        billingType: BILLING_TYPE_RECURRING,
        invoiceType: "",
        revenueRecognitionBasis: "月次計上",
        startDate: "2026-04-01",
        endDate: "2027-03-31",
        contractProductId: "a0pEEE",
        amount: 12000
      }
    ]);
    expect(items[0].invoiceType).toBe("");
    expect(items[1].invoiceType).toBe("");
  });

  it("buildChangeItemList does not fill blank unit from Product2 (BUG-105)", () => {
    const ctx = {
      resolvedDefaultInvoiceType: "一括前払",
      applyAmount: proto.applyAmount,
      decorateAllRows: (rows) => rows
    };
    const items = proto.buildChangeItemList.call(ctx, [
      {
        productId: "01tUNIT",
        unitPrice: 1000,
        quantity: 1,
        unit: "",
        unitName: "ライセンス",
        billingType: BILLING_TYPE_RECURRING,
        invoiceType: "一括前払",
        revenueRecognitionBasis: "月次計上",
        startDate: "2026-04-01",
        endDate: "2027-03-31",
        contractProductId: "a0pUNIT",
        amount: 12000
      }
    ]);
    expect(items[0].unit).toBe("");
    expect(items[1].unit).toBe("");
  });

  it("buildRenewItemList does not fill blank unit from Product2 (BUG-105)", () => {
    const ctx = {
      getDefaultDates: () => ({
        startDate: "2027-04-01",
        endDate: "2028-03-31"
      }),
      resolvedDefaultInvoiceType: "一括前払",
      applyAmount: proto.applyAmount,
      decorateAllRows: (rows) => rows
    };
    const items = proto.buildRenewItemList.call(ctx, [
      {
        productId: "01tRUNIT",
        unitPrice: 1000,
        quantity: 1,
        unit: "",
        unitName: "ライセンス",
        billingType: BILLING_TYPE_RECURRING,
        invoiceType: "一括前払",
        contractProductId: "a0pRUNIT"
      }
    ]);
    expect(items[0].unit).toBe("");
  });
});
