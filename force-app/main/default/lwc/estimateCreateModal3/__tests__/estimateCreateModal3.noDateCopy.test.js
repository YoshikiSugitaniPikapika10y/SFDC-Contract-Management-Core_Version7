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

describe("estimateCreateModal3 date copy removal (Core 4.3.5)", () => {
  const proto = EstimateCreateModal3.prototype;

    it("does not copy dates from the row above or fill from header period", () => {
    expect(proto.handleCopyDateFromAbove).toBeUndefined();
    expect(proto.handleFillLineStartFromContract).toBeUndefined();
    expect(proto.handleFillLineEndFromContract).toBeUndefined();
    expect(proto.findPreviousEditableRow).toBeUndefined();
    expect(typeof proto.handleFillLineStartOneYear).toBe("function");
    expect(typeof proto.handleFillLineEndOneMonth).toBe("function");
  });

  it("does not fill an empty start or end date from the opposite side or header", () => {
    const row = { startDate: "", endDate: "2026-06-30" };
    expect(proto.resolveLineStartAdjustBase(row)).toBe("");
    expect(
      proto.resolveLineEndAdjustBase({ startDate: "2026-06-01", endDate: "" })
    ).toBe("");
  });

  it("does not fill empty 切替日 from start date on Renew copy (Core 1.1.10 / 4.7)", () => {
    const applied = [];
    const ctx = {
      _wizardData: {
        contractEffectiveDate: "",
        previousTermStartDate: "2025-04-01",
        previousTermEndDate: "2026-03-31"
      },
      isChangeType: false,
      isRenewType: true,
      isCancelType: false,
      contractStartDate: "2026-04-01",
      applyBusinessFields(fields) {
        applied.push(fields);
      },
      syncFixedEffectiveDate() {}
    };
    proto.initHistoryMetaDates.call(ctx);
    expect(applied[0].contractEffectiveDate).toBe("");
  });
});
