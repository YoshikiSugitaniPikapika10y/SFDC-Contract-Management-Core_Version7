import EstimateEditRecordAction from "c/estimateEditRecordAction";

jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "lightning/uiRecordApi",
  () => ({ getRecord: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/estimateWizardClose",
  () => ({
    closeEstimateWizard: jest.fn(),
    markEstimateRecordForRefresh: jest.fn(),
    refreshOnEstimateRecordActionUnmount: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "c/quickActionPanelResize",
  () => ({ resizeQuickActionPanel: jest.fn() }),
  { virtual: true }
);

describe("estimateEditRecordAction (Core 4.3.1)", () => {
  const canOpenWizard = Object.getOwnPropertyDescriptor(
    EstimateEditRecordAction.prototype,
    "canOpenWizard"
  ).get;

  it("opens the wizard for Ordered as well as Estimate", () => {
    expect(
      canOpenWizard.call({ hasPermission: true, historyStatus: "Ordered" })
    ).toBe(true);
    expect(
      canOpenWizard.call({ hasPermission: true, historyStatus: "Estimate" })
    ).toBe(true);
  });

  it("does not open the wizard without status or permission", () => {
    expect(
      canOpenWizard.call({ hasPermission: true, historyStatus: "" })
    ).toBe(false);
    expect(
      canOpenWizard.call({ hasPermission: false, historyStatus: "Ordered" })
    ).toBe(false);
  });
});
