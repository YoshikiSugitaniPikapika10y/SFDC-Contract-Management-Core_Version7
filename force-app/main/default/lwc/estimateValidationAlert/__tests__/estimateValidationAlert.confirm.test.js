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
  });
});
