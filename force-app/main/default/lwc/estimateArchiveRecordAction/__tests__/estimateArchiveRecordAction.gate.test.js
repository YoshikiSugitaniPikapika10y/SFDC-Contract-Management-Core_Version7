import EstimateArchiveRecordAction from "c/estimateArchiveRecordAction";

jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);
jest.mock(
  "lightning/refresh",
  () => ({ RefreshEvent: class RefreshEvent {} }),
  { virtual: true }
);
jest.mock(
  "lightning/platformShowToastEvent",
  () => ({ ShowToastEvent: class ShowToastEvent {} }),
  { virtual: true }
);
jest.mock(
  "lightning/uiRecordApi",
  () => ({ getRecordNotifyChange: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateArchiveController.archiveEstimate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateArchiveController.getArchiveContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.issueEstimateOperationKey",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ default: true }),
  { virtual: true }
);

jest.mock(
  "c/quickActionPanelResize",
  () => ({ resizeQuickActionPanel: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/estimateValidationAlertUtils",
  () => ({ resolveSaveErrorAlert: jest.fn() }),
  { virtual: true }
);

describe("estimateArchiveRecordAction gate (Core 5.5 / 1.1.10)", () => {
  const proto = EstimateArchiveRecordAction.prototype;
  const isArchiveDisabled = Object.getOwnPropertyDescriptor(
    proto,
    "isArchiveDisabled"
  ).get;

  function ctx(overrides) {
    return {
      isBusy: false,
      recordId: "a01000000000001AAA",
      hasPermission: true,
      isEstimate: true,
      ...overrides
    };
  }

  it("Estimateならアーカイブできる", () => {
    expect(isArchiveDisabled.call(ctx())).toBe(false);
  });

  it("Estimate以外なら実行できない", () => {
    expect(isArchiveDisabled.call(ctx({ isEstimate: false }))).toBe(true);
  });
});

describe("estimateArchiveRecordAction subtitle (Core 0.1 / 4.3.1 / 5.5)", () => {
  const proto = EstimateArchiveRecordAction.prototype;
  const confirmSubtitle = Object.getOwnPropertyDescriptor(
    proto,
    "confirmSubtitle"
  ).get;

  it("uses 不採用 not 破棄", () => {
    expect(confirmSubtitle.call({})).toBe(
      "見積を不採用にして編集不可にします"
    );
    expect(confirmSubtitle.call({})).not.toMatch(/破棄/);
  });
});
