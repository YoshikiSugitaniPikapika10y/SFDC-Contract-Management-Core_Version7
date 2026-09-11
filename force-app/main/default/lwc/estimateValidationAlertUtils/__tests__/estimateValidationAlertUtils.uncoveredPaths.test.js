import {
  buildConfirmValidationAlert,
  buildValidationAlert,
  buildWizardValidationAlert,
  isValidationRuleMessage,
  resolveSaveErrorAlert,
  VALIDATION_SOURCE
} from "c/estimateValidationAlertUtils";

describe("estimateValidationAlertUtils uncovered (Core 4.3.6)", () => {
  it("確認 alert keeps 確認 title and actions (Core 4.3.6)", () => {
    const alert = buildConfirmValidationAlert("破棄しますか？");
    expect(alert.source).toBe(VALIDATION_SOURCE.CONFIRM);
    expect(alert.title).toBe("確認");
    expect(alert.variant).toBe("confirm");
    expect(alert.showActions).toBe(true);
  });

  it("wizard / save validation titles stay empty (入力チェックは本文だけ)", () => {
    expect(buildWizardValidationAlert("必須です").title).toBe("");
    expect(buildValidationAlert("必須です", VALIDATION_SOURCE.SAVE).title).toBe(
      ""
    );
    expect(
      buildValidationAlert("必須です", VALIDATION_SOURCE.VALIDATION_RULE).title
    ).toBe("");
  });

  it("normalizes multiline and array messages; empty falls back", () => {
    const multi = buildWizardValidationAlert("一行目\n\n 二行目 \n");
    expect(multi.messages.map((row) => row.text)).toEqual(["一行目", "二行目"]);
    const fromArray = buildWizardValidationAlert([" A ", "", "B"]);
    expect(fromArray.messages.map((row) => row.text)).toEqual(["A", "B"]);
    const empty = buildWizardValidationAlert("");
    expect(empty.messages.map((row) => row.text)).toEqual([
      "入力内容を確認してください。"
    ]);
    const nil = buildWizardValidationAlert(null);
    expect(nil.messages.map((row) => row.text)).toEqual([
      "入力内容を確認してください。"
    ]);
  });

  it("detects 入力規則 / FIELD_CUSTOM_VALIDATION_EXCEPTION as validation rule", () => {
    expect(isValidationRuleMessage("")).toBe(false);
    expect(isValidationRuleMessage(null)).toBe(false);
    expect(
      isValidationRuleMessage("FIELD_CUSTOM_VALIDATION_EXCEPTION, 税率必須")
    ).toBe(true);
    expect(isValidationRuleMessage("入力規則により保存できません。")).toBe(
      true
    );
    expect(isValidationRuleMessage("Validation Formula failed")).toBe(true);
    expect(isValidationRuleMessage("validation rule blocked")).toBe(true);
    expect(isValidationRuleMessage("エラートリガーで拒否")).toBe(true);
    expect(isValidationRuleMessage("レコードを保存できません")).toBe(true);
    expect(isValidationRuleMessage("ただの保存失敗")).toBe(false);
  });

  it("resolveSaveErrorAlert cleans FIELD_CUSTOM prefix and keeps body text", () => {
    const alert = resolveSaveErrorAlert({
      body: [
        {
          message:
            "FIELD_CUSTOM_VALIDATION_EXCEPTION, 見積候補のみ編集できます。"
        }
      ]
    });
    expect(alert.messages.map((row) => row.text)).toEqual([
      "見積候補のみ編集できます。"
    ]);
    expect(alert.title).toBe("");
    expect(alert.showActions).toBe(false);
  });

  it("resolveSaveErrorAlert marks 入力規則 as validation_rule source", () => {
    const alert = resolveSaveErrorAlert({
      body: { message: "入力規則により保存できません。" }
    });
    expect(alert.source).toBe(VALIDATION_SOURCE.VALIDATION_RULE);
    expect(alert.messages.map((row) => row.text)).toEqual([
      "入力規則により保存できません。"
    ]);
  });

  it("resolveSaveErrorAlert reads pageErrors / fieldErrors / output.errors", () => {
    const alert = resolveSaveErrorAlert({
      body: {
        pageErrors: [{ message: "ページエラー" }],
        fieldErrors: {
          Name: [{ message: "名前必須" }],
          Empty: null
        },
        output: { errors: [{ message: "出力エラー" }] },
        message: "本体メッセージ"
      }
    });
    expect(alert.messages.map((row) => row.text)).toEqual([
      "ページエラー",
      "名前必須",
      "出力エラー",
      "本体メッセージ"
    ]);
    expect(alert.source).toBe(VALIDATION_SOURCE.WIZARD);
  });

  it("resolveSaveErrorAlert falls back to error.message then default", () => {
    expect(
      resolveSaveErrorAlert({
        message: "AuraHandledException: サーバ拒否"
      }).messages.map((row) => row.text)
    ).toEqual(["サーバ拒否"]);
    expect(
      resolveSaveErrorAlert({
        message: "Script-thrown exception 一時失敗"
      }).messages.map((row) => row.text)
    ).toEqual(["一時失敗"]);
    expect(
      resolveSaveErrorAlert({}).messages.map((row) => row.text)
    ).toEqual(["保存中にエラーが発生しました。"]);
    expect(resolveSaveErrorAlert(null).messages.map((row) => row.text)).toEqual(
      ["保存中にエラーが発生しました。"]
    );
  });

  it("cleanErrorMessage empty string stays empty via resolve path", () => {
    const alert = resolveSaveErrorAlert({
      body: { message: "" },
      message: "最終メッセージ"
    });
    expect(alert.messages.map((row) => row.text)).toEqual(["最終メッセージ"]);
  });
});
