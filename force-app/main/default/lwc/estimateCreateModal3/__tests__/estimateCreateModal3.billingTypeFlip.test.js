import EstimateCreateModal3 from "c/estimateCreateModal3";
import {
  BILLING_TYPE_ONE_TIME,
  BILLING_TYPE_RECURRING,
  PRODUCT_TYPE_NEW,
  PRODUCT_TYPE_RENEW
} from "c/estimateLineItemUtils";

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
jest.mock(
  "@salesforce/apex/EstimateCreateController.isAccountingEnabled",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

describe("estimateCreateModal3 billing type flip (Core 第0章)", () => {
  it("uses 一回課金 not 1回課金 on New flip link", () => {
    const view = EstimateCreateModal3.prototype.buildBillingTypeFlipView.call(
      { isNewType: true },
      { productMasterBillingType: BILLING_TYPE_RECURRING },
      BILLING_TYPE_RECURRING,
      false
    );
    expect(view.billingTypeFlipTitle).toBe("一回課金に切り替え");
    expect(view.billingTypeFlipTitle).not.toMatch(/1回課金/);
    expect(view.billingTypeFlipTarget).toBe(BILLING_TYPE_ONE_TIME);
  });

  it("shows flip link on Renew inherited rows when master is 継続課金", () => {
    const view = EstimateCreateModal3.prototype.buildBillingTypeFlipView.call(
      { isNewType: false, isRenewType: true },
      { productMasterBillingType: BILLING_TYPE_RECURRING },
      BILLING_TYPE_RECURRING,
      false
    );
    expect(view.showBillingTypeFlipLink).toBe(true);
    expect(view.billingTypeFlipTarget).toBe(BILLING_TYPE_ONE_TIME);
    expect(view.billingTypeFlipTitle).toBe("一回課金に切り替え");
  });

  it("does not show flip link on Remake", () => {
    const view = EstimateCreateModal3.prototype.buildBillingTypeFlipView.call(
      { isNewType: false, isRenewType: false },
      { recordType: "Remake", productMasterBillingType: BILLING_TYPE_RECURRING },
      BILLING_TYPE_RECURRING,
      false
    );
    expect(view.showBillingTypeFlipLink).toBe(false);
  });

  it("does not write Product2 unit onto Renew inherited flip (Core 第4.5.2節 / 第1.1.10節)", () => {
    const updateRow = jest.fn();
    EstimateCreateModal3.prototype.handleBillingTypeFlip.call(
      {
        isNewType: false,
        isRenewType: true,
        itemList: [
          {
            id: "r1",
            recordType: PRODUCT_TYPE_RENEW,
            sourceContractProductId: "a00CP000000001",
            billingType: BILLING_TYPE_RECURRING,
            productMasterBillingType: BILLING_TYPE_RECURRING,
            unit: "ライセンス",
            unitName: "式",
            invoiceType: "月次分割"
          }
        ],
        invoiceSettingOptions: [],
        resolvedDefaultInvoiceType: "",
        updateRow,
        resolveRowInvoiceType:
          EstimateCreateModal3.prototype.resolveRowInvoiceType
      },
      {
        currentTarget: {
          dataset: {
            rowId: "r1",
            nextBillingType: BILLING_TYPE_ONE_TIME
          }
        }
      }
    );
    expect(updateRow).toHaveBeenCalledTimes(1);
    const patch = updateRow.mock.calls[0][1];
    expect(patch.billingType).toBe(BILLING_TYPE_ONE_TIME);
    expect(patch).not.toHaveProperty("unit");
  });

  it("writes Product2 unit on Type=New flip even in a Renew estimate (Core 第4.5.2節)", () => {
    const updateRow = jest.fn();
    EstimateCreateModal3.prototype.handleBillingTypeFlip.call(
      {
        isNewType: false,
        isRenewType: true,
        itemList: [
          {
            id: "n1",
            recordType: PRODUCT_TYPE_NEW,
            sourceContractProductId: null,
            billingType: BILLING_TYPE_RECURRING,
            productMasterBillingType: BILLING_TYPE_RECURRING,
            unit: "旧単位",
            unitName: "式",
            invoiceType: "月次分割"
          }
        ],
        invoiceSettingOptions: [],
        resolvedDefaultInvoiceType: "",
        updateRow,
        resolveRowInvoiceType:
          EstimateCreateModal3.prototype.resolveRowInvoiceType
      },
      {
        currentTarget: {
          dataset: {
            rowId: "n1",
            nextBillingType: BILLING_TYPE_ONE_TIME
          }
        }
      }
    );
    expect(updateRow).toHaveBeenCalledTimes(1);
    expect(updateRow.mock.calls[0][1].unit).toBe("式");
  });
});
