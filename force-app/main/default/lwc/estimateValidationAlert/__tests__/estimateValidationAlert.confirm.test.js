import { createElement } from "lwc";
import EstimateValidationAlert from "c/estimateValidationAlert";

describe("estimateValidationAlert confirm (Core 4.3.6)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("確認の実行ボタンは続行で、キャンセルと対にする", () => {
    const element = createElement("c-estimate-validation-alert", {
      is: EstimateValidationAlert
    });
    element.variant = "confirm";
    element.showActions = true;
    element.messages = [{ key: "1", text: "破棄確認" }];
    document.body.appendChild(element);

    const labels = [...element.shadowRoot.querySelectorAll("button")].map(
      (button) => button.textContent.trim()
    );
    expect(labels).toContain("続行");
    expect(labels).toContain("キャンセル");
    expect(labels).not.toContain("了解");
    expect(
      element.shadowRoot.querySelector(".est-alert").getAttribute("role")
    ).toBe("status");
  });

  it("error variant has no proceed/cancel and uses alert role (Core 4.3.6)", () => {
    const element = createElement("c-estimate-validation-alert", {
      is: EstimateValidationAlert
    });
    element.variant = "error";
    element.showActions = true;
    element.messages = [{ key: "1", text: "入力エラー" }];
    document.body.appendChild(element);

    const labels = [...element.shadowRoot.querySelectorAll("button")].map(
      (button) => button.textContent.trim()
    );
    expect(labels).not.toContain("続行");
    expect(labels).not.toContain("キャンセル");
    expect(
      element.shadowRoot.querySelector(".est-alert").getAttribute("role")
    ).toBe("alert");
  });

  it("fires proceed and cancel (Core 4.3.6)", () => {
    const element = createElement("c-estimate-validation-alert", {
      is: EstimateValidationAlert
    });
    element.variant = "confirm";
    element.showActions = true;
    element.messages = [{ key: "1", text: "破棄確認" }];
    document.body.appendChild(element);

    const proceed = jest.fn();
    const cancel = jest.fn();
    element.addEventListener("proceed", proceed);
    element.addEventListener("cancel", cancel);

    const buttons = [...element.shadowRoot.querySelectorAll("button")];
    buttons.find((button) => button.textContent.trim() === "キャンセル").click();
    buttons.find((button) => button.textContent.trim() === "続行").click();

    expect(cancel).toHaveBeenCalledTimes(1);
    expect(proceed).toHaveBeenCalledTimes(1);
  });
});
