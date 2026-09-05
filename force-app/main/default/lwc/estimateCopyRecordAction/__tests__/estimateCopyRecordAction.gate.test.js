import { createElement } from "lwc";
import EstimateCopyRecordAction from "c/estimateCopyRecordAction";
import { closeEstimateWizard } from "c/estimateWizardClose";

jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ __esModule: true, default: true }),
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

describe("estimateCopyRecordAction (Core 4.3.1 / 4.3)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    closeEstimateWizard.mockClear();
  });

  it("opens the copy-preset wizard when Loop_03 is present", async () => {
    const element = createElement("c-estimate-copy-record-action", {
      is: EstimateCopyRecordAction
    });
    element.recordId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();

    const wizard = element.shadowRoot.querySelector("c-estimate-create-wizard");
    expect(wizard).toBeTruthy();
    expect(wizard.copySourceHistoryId).toBe("a0H000000000001AAA");
    expect(wizard.modalMode).toBe(true);
  });

  it("does not show 商談向け文 while Quick Action recordId is empty (Core 4.3.1 / 4.7)", async () => {
    const element = createElement("c-estimate-copy-record-action", {
      is: EstimateCopyRecordAction
    });
    document.body.appendChild(element);
    await Promise.resolve();

    expect(element.shadowRoot.querySelector("c-estimate-create-wizard")).toBeNull();
    expect(element.shadowRoot.textContent).not.toContain(
      "商談IDが指定されていません"
    );

    element.recordId = "a0H000000000001AAA";
    await Promise.resolve();

    const wizard = element.shadowRoot.querySelector("c-estimate-create-wizard");
    expect(wizard).toBeTruthy();
    expect(wizard.copySourceHistoryId).toBe("a0H000000000001AAA");
  });

  it("closes after save success without a same-turn record Navigate (Core 4.3.2 / 4.3.6)", async () => {
    const element = createElement("c-estimate-copy-record-action", {
      is: EstimateCopyRecordAction
    });
    element.recordId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();

    const wizard = element.shadowRoot.querySelector("c-estimate-create-wizard");
    wizard.dispatchEvent(
      new CustomEvent("requestclose", {
        bubbles: true,
        composed: true,
        detail: {
          refresh: true,
          opportunityId: "006000000000001AAA",
          contractHistoryId: "a0HNEW000000001AAA",
          navigateToContractHistoryId: "a0HNEW000000001AAA"
        }
      })
    );

    expect(closeEstimateWizard).toHaveBeenCalledTimes(1);
    expect(closeEstimateWizard.mock.calls[0][1]).toEqual({
      refresh: true,
      opportunityId: "006000000000001AAA",
      contractHistoryId: "a0HNEW000000001AAA",
      navigateToContractHistoryId: "a0HNEW000000001AAA"
    });
  });
});
