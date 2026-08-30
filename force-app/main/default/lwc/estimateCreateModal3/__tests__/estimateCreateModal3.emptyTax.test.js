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

describe("estimateCreateModal3 empty tax (Core 4.3.4 / 4.6)", () => {
  const proto = EstimateCreateModal3.prototype;
  const missing = Object.getOwnPropertyDescriptor(
    proto,
    "isTaxPercentMissing"
  ).get;
  const formattedTax = Object.getOwnPropertyDescriptor(
    proto,
    "formattedTotalTax"
  ).get;
  const formattedIncl = Object.getOwnPropertyDescriptor(
    proto,
    "formattedTotalAmountInclTax"
  ).get;

  it("税率が空なら税・税込をエラーにする", () => {
    expect(missing.call({ resolvedTaxPercent: null })).toBe(true);
    const ctx = { isTaxPercentMissing: true };
    expect(formattedTax.call(ctx)).toBe("消費税率が空です。");
    expect(formattedIncl.call(ctx)).toBe("消費税率が空です。");
  });

  it("税率があるときは税込を金額表示する", () => {
    expect(missing.call({ resolvedTaxPercent: 10 })).toBe(false);
    const ctx = {
      isTaxPercentMissing: false,
      totalAmountInclTax: 1100
    };
    expect(formattedIncl.call(ctx)).toContain("1,100");
  });
});

describe("estimateCreateModal3 tax rounding (Core 11.9)", () => {
  const proto = EstimateCreateModal3.prototype;
  const totalTax = Object.getOwnPropertyDescriptor(proto, "totalTax").get;

  it("DOWN は 0方向切捨て", () => {
    expect(
      totalTax.call({
        totalAmount: 15,
        resolvedTaxPercent: 10,
        _wizardData: { taxRoundingMode: "DOWN" },
        roundTaxRaw: proto.roundTaxRaw
      })
    ).toBe(1);
  });

  it("HALF_UP は 0.5 を 0 から離す", () => {
    expect(
      totalTax.call({
        totalAmount: 15,
        resolvedTaxPercent: 10,
        _wizardData: { taxRoundingMode: "HALF_UP" },
        roundTaxRaw: proto.roundTaxRaw
      })
    ).toBe(2);
  });

  it("丸め設定が空なら 0方向へ落とさない", () => {
    expect(
      Number.isNaN(
        totalTax.call({
          totalAmount: 15,
          resolvedTaxPercent: 10,
          _wizardData: {},
          roundTaxRaw: proto.roundTaxRaw
        })
      )
    ).toBe(true);
  });
});
