import { createElement } from "lwc";
import EstimateActionHubRecordAction from "c/estimateActionHubRecordAction";

jest.mock(
  "c/quickActionPanelResize",
  () => ({ resizeQuickActionPanel: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/estimateActionHub",
  () => {
    const { LightningElement } = require("lwc");
    return class EstimateActionHub extends LightningElement {};
  },
  { virtual: true }
);

describe("estimateActionHubRecordAction (Core 4.3.1)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("opens the estimate-action hub on the contract history", async () => {
    const element = createElement("c-estimate-action-hub-record-action", {
      is: EstimateActionHubRecordAction
    });
    element.recordId = "a0B000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();

    const hub = element.shadowRoot.querySelector("c-estimate-action-hub");
    expect(hub).toBeTruthy();
    expect(hub.recordId).toBe("a0B000000000001AAA");
  });

  it("does not place the estimate wizard on the hub entry", async () => {
    const element = createElement("c-estimate-action-hub-record-action", {
      is: EstimateActionHubRecordAction
    });
    element.recordId = "a0B000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelector("c-estimate-create-wizard")
    ).toBeNull();
  });
});
