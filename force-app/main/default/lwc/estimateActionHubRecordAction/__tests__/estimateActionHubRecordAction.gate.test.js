import { createElement } from "lwc";
import EstimateActionHubRecordAction from "c/estimateActionHubRecordAction";
import { CloseActionScreenEvent } from "lightning/actions";

jest.mock(
  "lightning/actions",
  () => {
    class ScreenClose extends Event {
      constructor() {
        super("closeActionScreen");
      }
    }
    return { CloseActionScreenEvent: ScreenClose };
  },
  { virtual: true }
);
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

  it("閉じるは Quick Action 本体がパネルを閉じる (Core 4.3.1 / 5.5)", async () => {
    const element = createElement("c-estimate-action-hub-record-action", {
      is: EstimateActionHubRecordAction
    });
    element.recordId = "a0B000000000001AAA";
    document.body.appendChild(element);
    await Promise.resolve();

    const closeHandler = jest.fn();
    element.addEventListener("closeActionScreen", closeHandler);
    element.shadowRoot.querySelector("c-estimate-action-hub").dispatchEvent(
      new CustomEvent("requestclose", {
        bubbles: true,
        composed: true
      })
    );

    expect(closeHandler).toHaveBeenCalledTimes(1);
    expect(closeHandler.mock.calls[0][0]).toBeInstanceOf(
      CloseActionScreenEvent
    );
  });
});
