import EstimateCreateWizard from "c/estimateCreateWizard";
import {
  BILLING_TYPE_ONE_TIME,
  INVOICE_SETTING_PREPAID_START,
  REVENUE_BASIS_OVER_TIME
} from "c/estimateLineItemUtils";

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

describe("estimateCreateWizard Spot Change Step2 (Core 4.3.5 / 4.5.2)", () => {
  const proto = EstimateCreateWizard.prototype;

  function spotChangeCtx(products) {
    return {
      isOrderedCustomFieldsOnlyEdit: false,
      validateTaxPercent: proto.validateTaxPercent,
      validateProductCustomFields: () => null,
      renewEligibleFalseMessage: proto.renewEligibleFalseMessage,
      serviceFieldDefinitions: [],
      historyFieldDefinitions: [],
      wizardData: {
        selectedType: "Change",
        serviceLifecycle: "Spot",
        contractHistoryName: "履歴",
        taxPercent: 10,
        selectedProducts: products
      }
    };
  }

  const baseLine = {
    productId: "01tAAA",
    quantity: 1,
    unitPrice: 1000,
    billingType: BILLING_TYPE_ONE_TIME,
    invoiceType: INVOICE_SETTING_PREPAID_START,
    revenueRecognitionBasis: REVENUE_BASIS_OVER_TIME,
    startDate: "2026-04-01",
    endDate: "2026-04-30",
    recordType: "New",
    typeLabel: "New",
    amount: 1000
  };

  it("rejects Spot Change line without invoice setting like Type=New", () => {
    const error = proto.validateStep2.call(
      spotChangeCtx([{ ...baseLine, invoiceType: "" }])
    );
    expect(error).toMatch(/請求設定を選択してください/);
  });

  it("rejects Spot Change line with quantity below 0.01 like Type=New", () => {
    const error = proto.validateStep2.call(
      spotChangeCtx([{ ...baseLine, quantity: 0 }])
    );
    expect(error).toMatch(/数量は0\.01以上/);
  });

  it("accepts Spot Change one-time New line with required fields", () => {
    expect(proto.validateStep2.call(spotChangeCtx([baseLine]))).toBeNull();
  });
});
