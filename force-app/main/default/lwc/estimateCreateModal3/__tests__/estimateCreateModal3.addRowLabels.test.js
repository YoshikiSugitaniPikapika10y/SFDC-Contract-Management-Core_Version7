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

describe("estimateCreateModal3 add row labels (Core 4.3.5)", () => {
  const proto = EstimateCreateModal3.prototype;
  const addRowLabel = Object.getOwnPropertyDescriptor(
    proto,
    "addRowButtonLabel"
  ).get;
  const changeNewLabel = Object.getOwnPropertyDescriptor(
    proto,
    "changeNewProductButtonLabel"
  ).get;
  const remakeLabel = Object.getOwnPropertyDescriptor(
    proto,
    "addRemakeButtonLabel"
  ).get;

  it("uses 新しい商品を追加 for Change Type=New and Spot, 変更後行を追加 for Remake", () => {
    expect(addRowLabel.call({ isSpotChange: false })).toBe("行を追加");
    expect(addRowLabel.call({ isSpotChange: true })).toBe("新しい商品を追加");
    expect(changeNewLabel.call({})).toBe("新しい商品を追加");
    expect(remakeLabel.call({})).toBe("変更後行を追加");
  });
});
