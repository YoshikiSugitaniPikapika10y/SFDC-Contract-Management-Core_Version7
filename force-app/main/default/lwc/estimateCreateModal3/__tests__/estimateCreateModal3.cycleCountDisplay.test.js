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

describe("estimateCreateModal3 cycle count display", () => {
  const resolve = EstimateCreateModal3.prototype.resolveCycleCountDisplay;

  it("shows recurring cycle count in Japanese (Core 0.1)", () => {
    expect(
      resolve.call(null, {
        billingType: "継続課金",
        startDate: "2026-04-01",
        endDate: "2027-03-31"
      })
    ).toBe("12ヶ月");
    expect(
      resolve.call(null, {
        billingType: "一回課金",
        startDate: "2026-04-01",
        endDate: "2027-03-31"
      })
    ).toBe("-");
    expect(
      resolve.call(null, {
        billingType: "継続課金"
      })
    ).toBe("-");
  });
});
