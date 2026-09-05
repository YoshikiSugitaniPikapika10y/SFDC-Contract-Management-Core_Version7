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

describe("estimateCreateModal3 product custom header toggle (Core 4.3.4)", () => {
  const proto = EstimateCreateModal3.prototype;

  function ctx(overrides) {
    return {
      productCustomFieldsExpanded: true,
      itemList: [],
      decorateAllRows: (rows) => rows,
      isProductCustomRowExpanded: proto.isProductCustomRowExpanded,
      handleToggleAllProductCustomFields:
        proto.handleToggleAllProductCustomFields,
      ...overrides
    };
  }

  it("ヘッダ開なら該当行はすべてグリッド", () => {
    expect(proto.isProductCustomRowExpanded.call(ctx({}))).toBe(true);
  });

  it("ヘッダ閉ならすべて出さない", () => {
    expect(
      proto.isProductCustomRowExpanded.call(
        ctx({ productCustomFieldsExpanded: false })
      )
    ).toBe(false);
  });

  it("ヘッダトグルは一括状態を保存しない", () => {
    const state = ctx({});
    proto.handleToggleAllProductCustomFields.call(state);
    expect(state.productCustomFieldsExpanded).toBe(false);
    proto.handleToggleAllProductCustomFields.call(state);
    expect(state.productCustomFieldsExpanded).toBe(true);
  });
});
