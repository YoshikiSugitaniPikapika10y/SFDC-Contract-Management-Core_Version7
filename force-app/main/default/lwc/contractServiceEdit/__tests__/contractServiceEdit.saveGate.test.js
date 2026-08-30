import ContractServiceEdit from "c/contractServiceEdit";
import save from "@salesforce/apex/ContractServiceEditController.save";

jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractServiceEditController.getContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractServiceEditController.save",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractServiceEditController.issueContractServiceOperationKey",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractWizardFieldService.getContractServiceFieldDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_08_Can_EditService",
  () => ({ default: true }),
  { virtual: true }
);

describe("contractServiceEdit save gate (Core 3.4.1 / 4.6 / 1.1.10)", () => {
  const proto = ContractServiceEdit.prototype;

  function ctx(overrides) {
    return {
      saving: false,
      name: "契約サービス",
      billingAccountId: "a00BA0000000001",
      taxPercent: 10,
      originalTaxPercent: 10,
      fieldDefinitions: [],
      customFields: {},
      toast: jest.fn(),
      taxChanged: proto.taxChanged,
      validateDisplayTaxPercent: proto.validateDisplayTaxPercent,
      ...overrides
    };
  }

  afterEach(() => {
    save.mockClear();
  });

  it("必須追加項目が空なら保存しない", async () => {
    const c = ctx({
      fieldDefinitions: [
        {
          apiName: "Memo__c",
          label: "メモ",
          fieldType: "STRING",
          required: true
        }
      ],
      customFields: { Memo__c: "  " }
    });
    await proto.handleSave.call(c);
    expect(c.toast).toHaveBeenCalledWith(
      "エラー",
      expect.stringContaining("メモ"),
      "error"
    );
    expect(save).not.toHaveBeenCalled();
  });

  it("表示用税率の0超〜1未満を画面で止める", async () => {
    const c = ctx({ taxPercent: 0.5 });
    await proto.handleSave.call(c);
    expect(c.toast).toHaveBeenCalledWith(
      "エラー",
      "消費税率は0〜100のパーセント値で入力してください。",
      "error"
    );
    expect(save).not.toHaveBeenCalled();
  });

  it("表示用税率の負数を画面で止める", async () => {
    const c = ctx({ taxPercent: -1 });
    await proto.handleSave.call(c);
    expect(c.toast).toHaveBeenCalledWith(
      "エラー",
      "消費税率が不正です（負の値は指定できません）。",
      "error"
    );
    expect(save).not.toHaveBeenCalled();
  });

  it("表示用税率の100超を画面で止める", async () => {
    const c = ctx({ taxPercent: 101 });
    await proto.handleSave.call(c);
    expect(c.toast).toHaveBeenCalledWith(
      "エラー",
      "消費税率が不正です（100を超える値は指定できません）。",
      "error"
    );
    expect(save).not.toHaveBeenCalled();
  });

  it("空欄の税率は本手続きでは形式不正にしない", () => {
    expect(proto.validateDisplayTaxPercent(null)).toBeNull();
    expect(proto.validateDisplayTaxPercent("")).toBeNull();
  });

  it("空の名前を画面で止める (Core 3.4.1 / 1.1.10)", async () => {
    const c = ctx({ name: "   " });
    await proto.handleSave.call(c);
    expect(c.toast).toHaveBeenCalledWith(
      "エラー",
      "名前を入力してください。",
      "error"
    );
    expect(save).not.toHaveBeenCalled();
  });

  it("空の請求アカウントを画面で止める (Core 3.4.1 / 1.1.10)", async () => {
    const c = ctx({ billingAccountId: "" });
    await proto.handleSave.call(c);
    expect(c.toast).toHaveBeenCalledWith(
      "エラー",
      "請求アカウントを入力してください。",
      "error"
    );
    expect(save).not.toHaveBeenCalled();
  });

  it("空欄の税率を画面で止める (Core 3.4.1 / 1.1.10)", async () => {
    const c = ctx({ taxPercent: null });
    await proto.handleSave.call(c);
    expect(c.toast).toHaveBeenCalledWith(
      "エラー",
      "税率を入力してください。",
      "error"
    );
    expect(save).not.toHaveBeenCalled();
  });
});
