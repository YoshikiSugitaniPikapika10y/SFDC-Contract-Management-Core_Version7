import {
  buildConfirmValidationAlert,
  buildWizardValidationAlert
} from "c/estimateValidationAlertUtils";

describe("estimateValidationAlertUtils (Core 4.3.6)", () => {
  it("builds a 確認 alert with actions for close / overwrite / same-product", () => {
    const alert = buildConfirmValidationAlert(
      "入力の有無にかかわらず破棄確認を表示する。"
    );
    expect(alert.title).toBe("確認");
    expect(alert.variant).toBe("confirm");
    expect(alert.showActions).toBe(true);
    expect(alert.messages.map((row) => row.text)).toEqual([
      "入力の有無にかかわらず破棄確認を表示する。"
    ]);
  });

  it("keeps validation error body text without 確認 actions", () => {
    const alert = buildWizardValidationAlert("請求アカウントは必須です。");
    expect(alert.title).not.toBe("確認");
    expect(alert.showActions).toBe(false);
    expect(alert.messages.map((row) => row.text)).toEqual([
      "請求アカウントは必須です。"
    ]);
  });
});
