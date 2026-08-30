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

describe("estimateCreateModal3 changeSourceProducts catalog (Core 4.4.3)", () => {
  const proto = EstimateCreateModal3.prototype;

  it("buildChangeSourceProductsFromLoaded includes revenueRecognitionBasis", () => {
    const catalog = proto.buildChangeSourceProductsFromLoaded.call({}, [
      {
        contractProductId: "a0pAAA",
        productId: "01tAAA",
        quantity: 2,
        unitPrice: 1000,
        amount: 24000,
        startDate: "2026-04-01",
        endDate: "2027-03-31",
        invoiceType: "前受（開始日）",
        billingType: "継続課金",
        revenueRecognitionBasis: "月次計上",
        customFields: {}
      }
    ]);
    expect(catalog).toEqual([
      {
        contractProductId: "a0pAAA",
        productId: "01tAAA",
        quantity: 2,
        unitPrice: 1000,
        amount: 24000,
        startDate: "2026-04-01",
        endDate: "2027-03-31",
        invoiceType: "前受（開始日）",
        billingType: "継続課金",
        revenueRecognitionBasis: "月次計上",
        customFields: {}
      }
    ]);
  });

  it("buildChangeSourceProductsFromOriginals includes revenueRecognitionBasis", () => {
    const catalog = proto.buildChangeSourceProductsFromOriginals.call({}, [
      {
        recordType: "Original",
        sourceContractProductId: "a0pBBB",
        productId: "01tBBB",
        quantity: 1,
        unitPrice: 500,
        amount: -6000,
        startDate: "2026-04-01",
        endDate: "2027-03-31",
        invoiceType: "後払い（終了日）",
        billingType: "継続課金",
        revenueRecognitionBasis: "一括計上"
      },
      {
        recordType: "Remake",
        sourceContractProductId: "a0pBBB",
        productId: "01tBBB",
        quantity: 1,
        unitPrice: 500,
        revenueRecognitionBasis: "一括計上"
      }
    ]);
    expect(catalog).toEqual([
      {
        contractProductId: "a0pBBB",
        productId: "01tBBB",
        quantity: 1,
        unitPrice: 500,
        amount: 6000,
        startDate: "2026-04-01",
        endDate: "2027-03-31",
        invoiceType: "後払い（終了日）",
        billingType: "継続課金",
        revenueRecognitionBasis: "一括計上",
        customFields: {}
      }
    ]);
  });
});
