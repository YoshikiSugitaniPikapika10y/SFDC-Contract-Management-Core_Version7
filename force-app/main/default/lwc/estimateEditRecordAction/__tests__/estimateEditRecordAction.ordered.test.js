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

describe("estimateEditRecordAction (Core 4.1 / 4.3.1 / 4.7 / 12.2)", () => {
  const canOpenWizard = Object.getOwnPropertyDescriptor(
    EstimateEditRecordAction.prototype,
    "canOpenWizard"
  ).get;
  const cannotEditMessage = Object.getOwnPropertyDescriptor(
    EstimateEditRecordAction.prototype,
    "cannotEditMessage"
  ).get;

  it("opens the wizard for Estimate (hub) and Ordered (highlight)", () => {
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

  it("does not open the wizard for Archive", () => {
    expect(
      canOpenWizard.call({ hasPermission: true, historyStatus: "Archive" })
    ).toBe(false);
    expect(
      cannotEditMessage.call({ hasPermission: true, historyStatus: "Archive" })
    ).toBe("見積／受注済み状態の契約履歴のみ編集できます。");
  });
});
