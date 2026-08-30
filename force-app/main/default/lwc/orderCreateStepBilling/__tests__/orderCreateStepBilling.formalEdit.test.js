import { NavigationMixin } from "lightning/navigation";
import OrderCreateStepBilling from "c/orderCreateStepBilling";

jest.mock(
  "@salesforce/apex/OrderWizardFieldService.getOrderBillingFieldDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getBillingAccountInvoiceSettings",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/uiRecordApi",
  () => ({ getRecordNotifyChange: jest.fn() }),
  { virtual: true }
);
jest.mock("@salesforce/apex", () => ({ refreshApex: jest.fn() }), {
  virtual: true
});
jest.mock(
  "c/estimateWizardCustomFields",
  () => ({ buildCustomFieldInputs: jest.fn(() => []) }),
  { virtual: true }
);

const Navigate = Symbol.for("NavigationMixin.Navigate");

jest.mock(
  "lightning/navigation",
  () => ({
    NavigationMixin: Object.assign(
      (Base) =>
        class extends Base {
          [Navigate]() {}
        },
      { Navigate }
    )
  }),
  { virtual: true }
);

describe("orderCreateStepBilling formal edit (Core 5.2)", () => {
  it("navigates to BillingAccount__c edit and names the formal edit screen in validation", () => {
    const navigate = jest.fn();
    const element = {
      billingAccountId: "a00BA0000000001",
      fieldDefinitions: [
        {
          apiName: "BillingAddressee__c",
          label: "請求先宛名",
          fieldType: "STRING",
          required: true
        }
      ],
      resolveBillingFieldValue:
        OrderCreateStepBilling.prototype.resolveBillingFieldValue,
      isMissingBillingFieldValue:
        OrderCreateStepBilling.prototype.isMissingBillingFieldValue,
      _billingCustomFields: {},
      [NavigationMixin.Navigate]: navigate
    };

    const opened =
      OrderCreateStepBilling.prototype.openBillingAccountFormalEdit.call(
        element
      );
    expect(opened).toBe(true);
    expect(navigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: "a00BA0000000001",
        objectApiName: "BillingAccount__c",
        actionName: "edit"
      }
    });

    const message =
      OrderCreateStepBilling.prototype.validateBillingFields.call(element);
    expect(message).toContain("正規編集画面");
    expect(message).not.toContain("関連リスト");
  });

  it("does not navigate when billing account is unset", () => {
    const navigate = jest.fn();
    const opened =
      OrderCreateStepBilling.prototype.openBillingAccountFormalEdit.call({
        billingAccountId: null,
        [NavigationMixin.Navigate]: navigate
      });
    expect(opened).toBe(false);
    expect(navigate).not.toHaveBeenCalled();
  });

  it("正規編集後の請求アカウント最新を追加項目へ載せる (Core 5.2)", () => {
    const merged =
      OrderCreateStepBilling.prototype.mergeBillingCustomFields.call(
        {},
        { BillingEmailTo__c: "old@example.com" },
        {
          billingCustomFields: {
            BillingEmailTo__c: "new@example.com",
            BillingAddressee__c: "新しい宛名"
          }
        }
      );
    expect(merged.BillingEmailTo__c).toBe("new@example.com");
    expect(merged.BillingAddressee__c).toBe("新しい宛名");
  });
});
