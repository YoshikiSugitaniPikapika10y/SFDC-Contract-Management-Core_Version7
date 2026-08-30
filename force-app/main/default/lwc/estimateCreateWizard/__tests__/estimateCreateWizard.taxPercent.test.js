import EstimateCreateWizard from "c/estimateCreateWizard";

jest.mock("@salesforce/apex", () => ({ refreshApex: jest.fn() }), {
  virtual: true
});
jest.mock(
  "lightning/uiRecordApi",
  () => {
    function getRecord() {}
    return {
      getRecord,
      getFieldValue: jest.fn(),
      getRecordNotifyChange: jest.fn()
    };
  },
  { virtual: true }
);
jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);
jest.mock(
  "lightning/refresh",
  () => ({ RefreshEvent: class RefreshEvent {} }),
  { virtual: true }
);
jest.mock(
  "lightning/navigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {},
    CurrentPageReference: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.saveEstimate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.issueEstimateOperationKey",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getDocumentDefaults",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getEstimateCopyPreset",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getEstimateEditPreset",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getLatestContractHistory",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractWizardFieldService.getContractServiceFieldDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractWizardFieldService.getContractHistoryFieldDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractWizardFieldService.getContractProductFieldDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractWizardFieldService.getOpportunityDefaultContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderWizardFieldService.getDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

describe("estimateCreateWizard empty tax (Core 4.3.4 / 4.6)", () => {
  const proto = EstimateCreateWizard.prototype;
  const emptyTaxMessage =
    "消費税率を入力してください。空欄は0%になりません。";

  function continuationCtx(overrides = {}) {
    const { wizardData: wizardDataOverrides = {}, ...rest } = overrides;
    return {
      effectiveRecordId: "006000000000001AAA",
      isOrderedCustomFieldsOnlyEdit: false,
      validateTaxPercent: proto.validateTaxPercent,
      renewEligibleFalseMessage: proto.renewEligibleFalseMessage,
      wizardData: {
        selectedType: "Change",
        contractServiceId: "a00000000000001AAA",
        contractServiceName: "サービス",
        contractHistoryId: "a01000000000001AAA",
        contractHistoryName: "履歴",
        serviceLifecycle: "Term",
        renewEligible: true,
        billingAccountId: "a03BA0000000001AAA",
        taxPercent: null,
        ...wizardDataOverrides
      },
      ...rest
    };
  }

  it("ChangeのStep1は税率空を拒否する", () => {
    expect(proto.validateStep1.call(continuationCtx({}))).toBe(emptyTaxMessage);
  });

  it("Spot ChangeのStep1は税率空を拒否する", () => {
    expect(
      proto.validateStep1.call(
        continuationCtx({
          wizardData: {
            selectedType: "Change",
            contractServiceId: "a00000000000001AAA",
            contractServiceName: "サービス",
            contractHistoryId: "a01000000000001AAA",
            contractHistoryName: "履歴",
            serviceLifecycle: "Spot",
            taxPercent: ""
          }
        })
      )
    ).toBe(emptyTaxMessage);
  });

  it("Change／Renew／CancelのStep1は請求アカウント空を拒否する (Core 4.3.3 / 3.4 / 1.1.8)", () => {
    ["Change", "Renew", "Cancel"].forEach((selectedType) => {
      expect(
        proto.validateStep1.call(
          continuationCtx({
            wizardData: { selectedType, billingAccountId: "" }
          })
        )
      ).toBe("請求アカウントを選択してください。");
    });
  });

  it("Step2は税率空を拒否する", () => {
    expect(
      proto.validateStep2.call(
        continuationCtx({
          wizardData: { selectedType: "Renew", taxPercent: null }
        })
      )
    ).toBe(emptyTaxMessage);
  });

  it("NewのStep1は商談取引先空を画面で止める (Core 3.2 / 1.1.10)", () => {
    expect(
      proto.validateStep1.call(
        continuationCtx({
          wizardData: {
            selectedType: "New",
            contractServiceName: "サービス",
            contractHistoryName: "履歴",
            billingAccountId: "a03BA0000000001AAA",
            taxPercent: 10,
            accountName: ""
          }
        })
      )
    ).toBe("商談に取引先が設定されていません。");
  });
});
