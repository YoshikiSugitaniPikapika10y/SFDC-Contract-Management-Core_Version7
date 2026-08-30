import EstimateCreateWizard from "c/estimateCreateWizard";

jest.mock("@salesforce/apex", () => ({ refreshApex: jest.fn() }), {
  virtual: true
});
jest.mock(
  "lightning/uiRecordApi",
  () => ({ getRecordNotifyChange: jest.fn() }),
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

describe("estimateCreateWizard Ordered additional fields (Core 4.3 / 11.4.3)", () => {
  const proto = EstimateCreateWizard.prototype;

  function instance(overrides) {
    const target = Object.create(proto);
    Object.assign(target, {
      editHistoryId: "a01000000000001AAA",
      historyFieldDefinitions: [{ apiName: "Note__c" }],
      orderHistoryFieldDefinitions: [{ apiName: "ApplicationDate__c" }],
      wizardData: { historyStatus: "Estimate" },
      ...overrides
    });
    return target;
  }

  it("Ordered見積編集は見積追加項目と受注追加項目を出す", () => {
    const target = instance({
      wizardData: { historyStatus: "Ordered" }
    });
    const names = proto.displayedHistoryFieldDefinitions
      .call(target)
      .map((field) => field.apiName);
    expect(names).toEqual(["Note__c", "ApplicationDate__c"]);
  });

  it("見積候補の編集には受注追加項目を出さない", () => {
    const target = instance({
      wizardData: { historyStatus: "Estimate" }
    });
    const names = proto.displayedHistoryFieldDefinitions
      .call(target)
      .map((field) => field.apiName);
    expect(names).toEqual(["Note__c"]);
  });
});
