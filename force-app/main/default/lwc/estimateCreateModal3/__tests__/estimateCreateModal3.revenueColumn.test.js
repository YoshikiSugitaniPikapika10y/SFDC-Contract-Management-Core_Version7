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

describe("estimateCreateModal3 revenue column (Core 4.3.4 / 4.5.2 / 7.6)", () => {
  const proto = EstimateCreateModal3.prototype;
  const showColumn = Object.getOwnPropertyDescriptor(
    proto,
    "showRevenueRecognitionColumn"
  ).get;
  const colspan = Object.getOwnPropertyDescriptor(
    proto,
    "productTableColspan"
  ).get;
  const isStepReady = Object.getOwnPropertyDescriptor(proto, "isStepReady").get;

  it("hides 売上計上 when Accounting is OFF", () => {
    const ctx = { accountingEnabled: false, accountingPolicyResolved: true };
    expect(showColumn.call(ctx)).toBe(false);
    expect(colspan.call(ctx)).toBe(11);
  });

  it("shows 売上計上 when Accounting is ON", () => {
    const ctx = { accountingEnabled: true, accountingPolicyResolved: true };
    expect(showColumn.call(ctx)).toBe(true);
    expect(colspan.call(ctx)).toBe(12);
  });

  it("keeps 売上計上 undetermined and blocks step while policy loads (CHANGE-232)", () => {
    const ctx = {
      accountingEnabled: false,
      accountingPolicyResolved: false,
      _bootstrapInFlight: false,
      isLoadingChangeProducts: false,
      isLoadingRenewProducts: false,
      isLoadingDates: false,
      _productDefaultsInFlight: 0
    };
    expect(showColumn.call(ctx)).toBe(false);
    expect(isStepReady.call(ctx)).toBe(false);
  });

  it("allows step ready after policy resolves OFF", () => {
    const ctx = {
      accountingEnabled: false,
      accountingPolicyResolved: true,
      _bootstrapInFlight: false,
      isLoadingChangeProducts: false,
      isLoadingRenewProducts: false,
      isLoadingDates: false,
      _productDefaultsInFlight: 0
    };
    expect(isStepReady.call(ctx)).toBe(true);
  });

  it("does not treat accounting wire error as OFF (BUG-075)", () => {
    const ctx = {
      accountingEnabled: false,
      accountingPolicyResolved: false,
      accountingPolicyLoadError: "",
      notifyStepReadyChange() {}
    };
    proto.wiredAccountingEnabled.call(ctx, {
      data: undefined,
      error: { body: { message: "fail" } }
    });
    expect(ctx.accountingPolicyResolved).toBe(false);
    expect(ctx.accountingEnabled).toBe(false);
    expect(ctx.accountingPolicyLoadError).toMatch(/会計方針の読込に失敗/);
    expect(showColumn.call(ctx)).toBe(false);
    expect(isStepReady.call(ctx)).toBe(false);
  });

  it("shows 一括計上／月次計上 as the 計上方法 labels (Core 4.3.4 / 0.1)", () => {
    expect(proto.revenueRecognitionBasisLabel.call({}, "一括計上")).toBe(
      "一括計上"
    );
    expect(proto.revenueRecognitionBasisLabel.call({}, "月次計上")).toBe(
      "月次計上"
    );
    const options = proto.buildRevenueRecognitionBasisOptions.call(
      {},
      "月次計上"
    );
    expect(options.map((option) => option.label)).toEqual([
      "月次計上",
      "一括計上"
    ]);
    expect(options.map((option) => option.value)).toEqual([
      "月次計上",
      "一括計上"
    ]);
  });
});
