import { createElement } from "lwc";
import EstimateIssueRecordAction from "c/estimateIssueRecordAction";
import { CloseActionScreenEvent } from "lightning/actions";

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

function createAction(recordId) {
  const element = createElement("c-estimate-issue-record-action", {
    is: EstimateIssueRecordAction
  });
  if (recordId !== undefined) {
    element.recordId = recordId;
  }
  document.body.appendChild(element);
  return element;
}

describe("estimateIssueRecordAction (Core 4.3.1 / 4.8 / 7.10)", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("keeps the existing issue page inside the record Quick Action overlay", () => {
    const element = createAction("a0H A&B");
    const frame = element.shadowRoot.querySelector("iframe");

    expect(frame).not.toBeNull();
    expect(frame.getAttribute("src")).toBe(
      "/apex/EstimateDocumentIssue?id=a0H%20A%26B"
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
});
