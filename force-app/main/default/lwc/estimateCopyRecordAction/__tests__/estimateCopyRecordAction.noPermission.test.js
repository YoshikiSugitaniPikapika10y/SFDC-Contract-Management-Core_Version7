import { createElement } from "lwc";
import EstimateCopyRecordAction from "c/estimateCopyRecordAction";

jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ __esModule: true, default: false }),
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
jest.mock(
  "c/estimateCreateWizard",
  () => {
    const { LightningElement } = require("lwc");
    return class EstimateCreateWizard extends LightningElement {};
  },
  { virtual: true }
);

describe("estimateCopyRecordAction without Loop_03 (共通基盤 10.4)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("does not open the copy wizard without 03", async () => {
    const element = createElement("c-estimate-copy-record-action", {
      is: EstimateCopyRecordAction
    });
    element.recordId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-estimate-create-wizard")
    ).toBeNull();
  });
});
