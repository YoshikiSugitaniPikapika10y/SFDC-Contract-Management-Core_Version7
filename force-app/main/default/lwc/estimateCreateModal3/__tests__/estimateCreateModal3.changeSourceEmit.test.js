import EstimateCreateModal3 from "c/estimateCreateModal3";

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

describe("estimateCreateModal3 changeSourceProducts emit (BUG-080)", () => {
  const proto = EstimateCreateModal3.prototype;
  const changeSourceGetter = Object.getOwnPropertyDescriptor(
    proto,
    "changeSourceProducts"
  ).get;

  function baseCtx(overrides = {}) {
    return {
      _bootstrapInFlight: true,
      _changeSourceProductsLocal: null,
      _wizardData: { changeSourceProducts: [] },
      itemList: [],
      isChangeType: true,
      isSpotChange: false,
      contractStartDate: "2026-04-01",
      decorateAllRows: (rows) => rows || [],
      serializeProducts: (rows) => rows || [],
      computeHeaderDatesFromRecurringProducts: () => null,
      computeChangeEffectiveDate: () => "",
      emitChange: jest.fn(),
      _isConnected: true,
      ...overrides
    };
  }

  it("keeps catalog locally when commitItemList uses emit:false", () => {
    const catalog = [
      {
        contractProductId: "a0pAAA",
        productId: "01tAAA",
        invoiceType: "一括前払",
        revenueRecognitionBasis: "月次計上"
      }
    ];
    const ctx = baseCtx();
    proto.commitItemList.call(ctx, [{ id: "row1" }], {
      changeSourceProducts: catalog,
      emit: false
    });
    expect(ctx._changeSourceProductsLocal).toEqual(catalog);
    expect(changeSourceGetter.call(ctx)).toEqual(catalog);
    expect(ctx.emitChange).not.toHaveBeenCalled();
  });

  it("emitProductsFromItemList sends local catalog to parent", () => {
    const catalog = [
      {
        contractProductId: "a0pBBB",
        productId: "01tBBB",
        revenueRecognitionBasis: "一括計上"
      }
    ];
    const ctx = baseCtx({
      _bootstrapInFlight: false,
      _changeSourceProductsLocal: catalog,
      itemList: [{ id: "row1", productId: "01tBBB" }]
    });
    Object.defineProperty(ctx, "changeSourceProducts", {
      get() {
        return changeSourceGetter.call(this);
      }
    });
    proto.emitProductsFromItemList.call(ctx);
    expect(ctx.emitChange).toHaveBeenCalled();
    const detail = ctx.emitChange.mock.calls[0][0];
    expect(detail.changeSourceProducts).toEqual(catalog);
  });
});
