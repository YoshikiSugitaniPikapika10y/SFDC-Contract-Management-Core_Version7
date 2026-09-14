import { createElement } from "lwc";
import EstimateEditRecordAction from "c/estimateEditRecordAction";

jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ default: false }),
  { virtual: true }
);
jest.mock("lightning/uiRecordApi", () => ({ getRecord: jest.fn() }), {
  virtual: true
});
jest.mock("c/estimateWizardClose", () => ({
  closeEstimateWizard: jest.fn(),
  markEstimateRecordForRefresh: jest.fn(),
  refreshOnEstimateRecordActionUnmount: jest.fn()
}));
jest.mock(
  "c/quickActionPanelResize",
  () => ({ resizeQuickActionPanel: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/estimateCreateWizard",
  () => {
    const { LightningElement } = require("lwc");
    return class EstimateCreateWizard extends LightningElement {};
  },
  { virtual: true }
);

describe("estimateEditRecordAction without Loop_03 (共通基盤 10.4)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("does not open the edit wizard without 03", async () => {
    const element = createElement("c-estimate-edit-record-action", {
      is: EstimateEditRecordAction
    });
    element.recordId = "a01000000000001AAA";
    element.historyStatus = "Ordered";
    document.body.appendChild(element);
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-estimate-create-wizard")
    ).toBeNull();
    expect(element.shadowRoot.textContent).toContain(
      "この操作の権限がありません。"
    );
  });
});
