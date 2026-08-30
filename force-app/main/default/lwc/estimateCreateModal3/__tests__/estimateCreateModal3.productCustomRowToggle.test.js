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

describe("estimateCreateModal3 product custom row toggle (Core 4.3.4)", () => {
  const proto = EstimateCreateModal3.prototype;

  function ctx(overrides) {
    return {
      productCustomFieldsExpanded: true,
      productCustomRowExpanded: {},
      itemList: [],
      decorateAllRows: (rows) => rows,
      isProductCustomRowExpanded: proto.isProductCustomRowExpanded,
      handleToggleAllProductCustomFields:
        proto.handleToggleAllProductCustomFields,
      handleToggleRowProductCustomFields:
        proto.handleToggleRowProductCustomFields,
      ...overrides
    };
  }

  it("一括が開なら行別未指定は開く", () => {
    expect(proto.isProductCustomRowExpanded.call(ctx({}), "r1")).toBe(true);
  });

  it("行別閉は一括開と独立する", () => {
    const state = ctx({ productCustomRowExpanded: { r1: false } });
    expect(proto.isProductCustomRowExpanded.call(state, "r1")).toBe(false);
    expect(proto.isProductCustomRowExpanded.call(state, "r2")).toBe(true);
  });

  it("行別トグルは対象行だけ反転する", () => {
    const state = ctx({});
    proto.handleToggleRowProductCustomFields.call(state, {
      currentTarget: { dataset: { id: "r1" } }
    });
    expect(state.productCustomRowExpanded.r1).toBe(false);
    expect(proto.isProductCustomRowExpanded.call(state, "r2")).toBe(true);
  });

  it("一括開閉は行別状態を保存しない", () => {
    const state = ctx({ productCustomRowExpanded: { r1: false } });
    proto.handleToggleAllProductCustomFields.call(state);
    expect(state.productCustomFieldsExpanded).toBe(false);
    expect(state.productCustomRowExpanded).toEqual({});
  });
});
