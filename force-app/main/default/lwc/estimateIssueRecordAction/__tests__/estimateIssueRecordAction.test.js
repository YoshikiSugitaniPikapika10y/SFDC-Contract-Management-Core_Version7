import { createElement } from "lwc";
import EstimateIssueRecordAction from "c/estimateIssueRecordAction";
import { CloseActionScreenEvent } from "lightning/actions";
import { openContentDocumentFilePreview } from "c/orderWizardNavigation";

jest.mock(
  "lightning/actions",
  () => ({
    CloseActionScreenEvent: class CloseActionScreenEvent extends Event {
      constructor() {
        super("closeActionScreen");
      }
    }
  }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardNavigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {},
    openContentDocumentFilePreview: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "lightning/refresh",
  () => ({ RefreshEvent: class RefreshEvent {} }),
  { virtual: true }
);
jest.mock(
  "lightning/confirm",
  () => ({ default: { open: jest.fn() } }),
  { virtual: true }
);
jest.mock(
  "lightning/platformShowToastEvent",
  () => ({ ShowToastEvent: class ShowToastEvent {} }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateSendBoardController.getBoardContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateSendBoardController.getRecordActionEstimate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateSendBoardController.previewEstimateFromRecordPage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateSendBoardController.sendEstimateFromRecordPage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.getEstimateSendBoardContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.getEstimateSendRecord",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.previewEstimateFromRecordPage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.sendEstimateFromRecordPage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_05_Can_SendEstimate",
  () => ({ default: false }),
  { virtual: true }
);

let issueListeners = [];

function createAction(recordId) {
  const realAdd = window.addEventListener.bind(window);
  const spy = jest
    .spyOn(window, "addEventListener")
    .mockImplementation((type, handler, options) => {
      if (type === "message") {
        issueListeners.push(handler);
      }
      return realAdd(type, handler, options);
    });
  const element = createElement("c-estimate-issue-record-action", {
    is: EstimateIssueRecordAction
  });
  if (recordId !== undefined) {
    element.recordId = recordId;
  }
  document.body.appendChild(element);
  spy.mockRestore();
  return element;
}

function postIssue(action, contentDocumentId, origin, contentVersionId) {
  const event = {
    origin: origin || "https://customer.vf.force.com",
    data: {
      source: "cmc-estimate-issue",
      action,
      contentDocumentId,
      contentVersionId
    }
  };
  issueListeners.forEach((handler) => handler(event));
}

describe("estimateIssueRecordAction (Core 4.3.1 / 4.8 / 7.10)", () => {
  afterEach(() => {
    document.body.innerHTML = "";
    sessionStorage.clear();
    issueListeners = [];
    openContentDocumentFilePreview.mockClear();
  });

  it("keeps the existing issue page inside the record Quick Action overlay", () => {
    const element = createAction("a0H A&B");
    const frame = element.shadowRoot.querySelector("iframe");

    expect(frame).not.toBeNull();
    expect(frame.getAttribute("src")).toBe(
      `/apex/EstimateDocumentIssue?id=a0H%20A%26B&parentOrigin=${encodeURIComponent(window.location.origin)}`
    );
    expect(frame.getAttribute("title")).toBe("見積書発行");
    expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
  });

  it("does not open an unscoped issue page when recordId is missing", () => {
    const element = createAction();

    expect(element.shadowRoot.querySelector("iframe")).toBeNull();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent.trim()
    ).toBe("契約履歴IDが指定されていません。");
  });

  it("closes only when the user selects the explicit close action", () => {
    const element = createAction("a0H000000000001AAA");
    const closeHandler = jest.fn();
    element.addEventListener("closeActionScreen", closeHandler);

    element.shadowRoot.querySelector("button").click();

    expect(closeHandler).toHaveBeenCalledTimes(1);
    expect(closeHandler.mock.calls[0][0]).toBeInstanceOf(
      CloseActionScreenEvent
    );
  });

  it("opens standard file preview over the issue surface without closing it", async () => {
    const element = createAction("a0H000000000001AAA");
    const closeHandler = jest.fn();
    element.addEventListener("closeActionScreen", closeHandler);

    postIssue(
      "preview",
      "069000000000001AAA",
      undefined,
      "068000000000001AAA"
    );
    await Promise.resolve();

    expect(openContentDocumentFilePreview).toHaveBeenCalledTimes(1);
    expect(openContentDocumentFilePreview.mock.calls[0][1]).toBe(
      "069000000000001AAA"
    );
    expect(closeHandler).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector(".issue-frame")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".preview-frame")).toBeNull();
    expect(element.shadowRoot.innerHTML).not.toContain("shepherd");
    expect(
      element.shadowRoot.querySelector("c-estimate-send-record-action")
    ).toBeNull();
  });

  it("キャンセルは送付だけを閉じ、発行面に戻る (Core 0.3 / 4.8)", async () => {
    const element = createAction("a0H000000000001AAA");
    const closeHandler = jest.fn();
    element.addEventListener("closeActionScreen", closeHandler);
    const issueFrame = element.shadowRoot.querySelector(".issue-frame");

    postIssue("send", "069000000000002AAA");
    await Promise.resolve();

    const send = element.shadowRoot.querySelector(
      "c-estimate-send-record-action"
    );
    send.dispatchEvent(
      new CustomEvent("panelclose", {
        bubbles: true,
        composed: true,
        detail: { sent: false }
      })
    );
    await Promise.resolve();

    expect(closeHandler).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector("c-estimate-send-record-action")
    ).toBeNull();
    expect(element.shadowRoot.querySelector(".issue-frame")).toBe(issueFrame);
    expect(element.shadowRoot.querySelector(".issue-surface_held")).toBeNull();
    expect(element.shadowRoot.querySelector(".issue-complete")).toBeNull();
  });

  it("送付成功は見積を送付しました。を発行面に残す (Core 0.3 / 4.8)", async () => {
    const element = createAction("a0H000000000001AAA");
    const closeHandler = jest.fn();
    element.addEventListener("closeActionScreen", closeHandler);

    postIssue("send", "069000000000002AAA");
    await Promise.resolve();

    const send = element.shadowRoot.querySelector(
      "c-estimate-send-record-action"
    );
    send.dispatchEvent(
      new CustomEvent("panelclose", {
        bubbles: true,
        composed: true,
        detail: { sent: true }
      })
    );
    await Promise.resolve();

    expect(closeHandler).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector(".issue-frame")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".issue-complete").textContent).toBe(
      "見積を送付しました。"
    );
  });

  it("ignores preview and send messages that are not from the issue page", () => {
    const element = createAction("a0H000000000001AAA");

    postIssue(
      "preview",
      "069000000000001AAA",
      "https://example.lightning.force.com",
      "068000000000001AAA"
    );
    postIssue("send", "069000000000002AAA", "https://evil.example");

    expect(element.shadowRoot.querySelector(".preview-frame")).toBeNull();
    expect(
      element.shadowRoot.querySelector("c-estimate-send-record-action")
    ).toBeNull();
    expect(sessionStorage.getItem("cmc.estimateSend.initialContentDocumentId")).toBeNull();
  });

  it("shows the send screen in the same popup for the issued file", async () => {
    const element = createAction("a0H000000000001AAA");

    postIssue("send", "069000000000002AAA");
    await Promise.resolve();

    expect(sessionStorage.getItem("cmc.estimateSend.initialContentDocumentId")).toBe(
      "069000000000002AAA"
    );
    expect(element.shadowRoot.querySelector("iframe")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".issue-surface_held")).not.toBeNull();
    expect(
      element.shadowRoot.querySelector("c-estimate-send-record-action")
    ).not.toBeNull();
    expect(openContentDocumentFilePreview).not.toHaveBeenCalled();
  });
});
