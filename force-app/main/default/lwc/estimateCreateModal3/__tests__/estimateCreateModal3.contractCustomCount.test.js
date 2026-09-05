import EstimateCreateModal3 from "c/estimateCreateModal3";

jest.mock(
  "@salesforce/apex/EstimateCreateController.getProductDefaults",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getRecurringContractProducts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getRenewContractProducts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getContractHistoryInfo",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getEstimateRemarkMasterText",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getInvoiceSettingOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getDefaultInvoiceSettingLabel",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

describe("estimateCreateModal3 contract custom toggle (Core 4.3.4)", () => {
  const proto = EstimateCreateModal3.prototype;
  const count = Object.getOwnPropertyDescriptor(
    proto,
    "contractCustomFieldCount"
  ).get;
  const title = Object.getOwnPropertyDescriptor(
    proto,
    "contractCustomSectionTitle"
  ).get;

  it("shows total visible field count on the toggle", () => {
    const ctx = {
      isNewType: true,
      effectiveSelectedType: "New",
      serviceFieldDefinitions: [{ showOnNew: true }, { showOnNew: true }],
      historyFieldDefinitions: [{ showOnNew: true }]
    };
    expect(count.call(ctx)).toBe(3);
    expect(title.call({ contractCustomFieldCount: 3 })).toBe(
      "契約のカスタム項目（3）"
    );
  });

  it("shows visible service fields for Change (Core 4.3.4 / 11.4.1)", () => {
    const hasService = Object.getOwnPropertyDescriptor(
      proto,
      "hasServiceCustomFields"
    ).get;
    const ctx = {
      isNewType: false,
      orderedCustomFieldsOnly: false,
      effectiveSelectedType: "Change",
      serviceFieldDefinitions: [{ showOnChange: true }, { showOnNew: true }],
      historyFieldDefinitions: []
    };
    expect(hasService.call(ctx)).toBe(true);
    expect(count.call(ctx)).toBe(1);
  });

  it("Ordered見積編集は種別表示の契約サービス追加項目を出す (Core 4.3.4 / 11.4.1)", () => {
    const hasService = Object.getOwnPropertyDescriptor(
      proto,
      "hasServiceCustomFields"
    ).get;
    const ctx = {
      isNewType: true,
      orderedCustomFieldsOnly: true,
      effectiveSelectedType: "New",
      serviceFieldDefinitions: [{ showOnNew: true }, { showOnNew: true }],
      historyFieldDefinitions: [{ showOnNew: true }],
      orderFieldDefinitions: [{ showOnNew: true }]
    };
    expect(hasService.call(ctx)).toBe(true);
    expect(count.call(ctx)).toBe(4);
  });
});

describe("estimateCreateModal3 remarks (Core 4.10)", () => {
  const proto = EstimateCreateModal3.prototype;
  const showRemarks = Object.getOwnPropertyDescriptor(
    proto,
    "showRemarksSection"
  ).get;

  it("does not show a standalone remarks section", () => {
    expect(
      showRemarks.call({
        showEstimateDocumentSection: false,
        showProductTable: true,
        itemList: [{ id: "1" }]
      })
    ).toBe(false);
  });
});
