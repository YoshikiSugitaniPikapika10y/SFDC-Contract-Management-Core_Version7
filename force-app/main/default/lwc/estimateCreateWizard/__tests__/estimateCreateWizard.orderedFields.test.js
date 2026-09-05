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

describe("estimateCreateWizard Ordered additional fields (Core 4.3 / 11.4.3)", () => {
  const proto = EstimateCreateWizard.prototype;
  const displayed = Object.getOwnPropertyDescriptor(
    proto,
    "displayedHistoryFieldDefinitions"
  ).get;
  const displayedOrder = Object.getOwnPropertyDescriptor(
    proto,
    "displayedOrderFieldDefinitions"
  ).get;

  function instance(overrides) {
    return {
      isOrderedCustomFieldsOnlyEdit: false,
      historyFieldDefinitions: [{ apiName: "Note__c" }],
      orderHistoryFieldDefinitions: [{ apiName: "ApplicationDate__c" }],
      ...overrides
    };
  }

  it("Ordered見積編集は見積追加項目を残し受注追加項目を別見出しで足す", () => {
    const ctx = instance({ isOrderedCustomFieldsOnlyEdit: true });
    expect(displayed.call(ctx).map((field) => field.apiName)).toEqual([
      "Note__c"
    ]);
    expect(displayedOrder.call(ctx).map((field) => field.apiName)).toEqual([
      "ApplicationDate__c"
    ]);
  });

  it("見積候補の編集には受注追加項目を出さない", () => {
    const ctx = instance();
    expect(displayed.call(ctx).map((field) => field.apiName)).toEqual([
      "Note__c"
    ]);
    expect(displayedOrder.call(ctx)).toEqual([]);
  });
});

describe("estimateCreateWizard close confirm (Core 4.3.2 / 4.3.6)", () => {
  const proto = EstimateCreateWizard.prototype;

  it("asks discard confirm before save success", () => {
    const openConfirm = jest.fn();
    const performClose = jest.fn();
    proto.handleClose.call({
      isSaving: false,
      hasOpenConfirm: false,
      _saveSucceededThisSession: false,
      openConfirm,
      performClose
    });
    expect(openConfirm).toHaveBeenCalledWith(
      { kind: "close" },
      "入力内容は保存されていません。破棄してよろしいですか？"
    );
    expect(performClose).not.toHaveBeenCalled();
  });

  it("closes without confirm after save success", () => {
    const openConfirm = jest.fn();
    const performClose = jest.fn();
    proto.handleClose.call({
      isSaving: false,
      hasOpenConfirm: false,
      _saveSucceededThisSession: true,
      openConfirm,
      performClose
    });
    expect(openConfirm).not.toHaveBeenCalled();
    expect(performClose).toHaveBeenCalled();
  });
});
