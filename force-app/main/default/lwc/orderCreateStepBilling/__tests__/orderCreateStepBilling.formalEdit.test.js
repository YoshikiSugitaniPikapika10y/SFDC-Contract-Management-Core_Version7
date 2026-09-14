import { createElement } from "lwc";

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
  "@salesforce/apex/ContractPermissionUtil.hasBillingAccountSet",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/uiRecordApi",
  () => {
    class GetRecordAdapter {}
    return {
      getRecord: GetRecordAdapter,
      getFieldValue: jest.fn(),
      getRecordNotifyChange: jest.fn()
    };
  },
  { virtual: true }
);
jest.mock(
  "lightning/uiObjectInfoApi",
  () => {
    class GetObjectInfoAdapter {}
    return { getObjectInfo: GetObjectInfoAdapter };
  },
  { virtual: true }
);
jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
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

jest.mock(
  "lightning/navigation",
  () => {
    const Navigate = Symbol.for("NavigationMixin.Navigate");
    return {
      NavigationMixin: Object.assign(
        (Base) =>
          class extends Base {
            [Navigate]() {}
          },
        { Navigate }
      ),
      CurrentPageReference: class CurrentPageReference {}
    };
  },
  { virtual: true }
);

const OrderCreateStepBilling = require("c/orderCreateStepBilling").default;
const navigationPrototype = Object.getPrototypeOf(
  OrderCreateStepBilling.prototype
);
const navigateSymbol = Object.getOwnPropertySymbols(navigationPrototype).find(
  (symbol) => symbol.description === "NavigationMixin.Navigate"
);

describe("orderCreateStepBilling formal edit (Core 5.2)", () => {
  it("navigates to BillingAccount__c edit and names the formal edit screen in validation", () => {
    const navigate = jest.fn();
    const element = {
      billingAccountId: "a00BA0000000001",
      context: { contractHistoryId: "a0H000000000001AAA" },
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
      [navigateSymbol]: navigate
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
      },
      state: {
        c__returnTo: "order",
        c__returnRecordId: "a0H000000000001AAA"
      }
    });

    const message =
      OrderCreateStepBilling.prototype.validateBillingFields.call(element);
    expect(message).toBe(
      "請求アカウントの必須項目が未設定です。請求アカウントの正規編集画面で設定してください: 請求先宛名"
    );
    expect(message).not.toContain("関連リスト");
  });

  it("does not navigate when billing account is unset", () => {
    const navigate = jest.fn();
    const opened =
      OrderCreateStepBilling.prototype.openBillingAccountFormalEdit.call({
        billingAccountId: null,
        [navigateSymbol]: navigate
      });
    expect(opened).toBe(false);
    expect(navigate).not.toHaveBeenCalled();
  });

  it("does not navigate when 19 cannot update the billing account (共通基盤 10.4)", () => {
    const navigate = jest.fn();
    const opened =
      OrderCreateStepBilling.prototype.openBillingAccountFormalEdit.call({
        billingAccountId: "a00BA0000000001",
        canUpdateBillingAccount: false,
        [navigateSymbol]: navigate
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

  it("shows billing as reference-only and sends unset estimates back to the wizard (Core 5.2)", async () => {
    const proto = OrderCreateStepBilling.prototype;
    const hasBilling = Object.getOwnPropertyDescriptor(
      proto,
      "hasBillingAccount"
    ).get;
    const accountName = Object.getOwnPropertyDescriptor(
      proto,
      "billingAccountName"
    ).get;
    expect(hasBilling.call({ context: { billingAccountId: "a00" } })).toBe(
      true
    );
    expect(hasBilling.call({ context: {} })).toBe(false);
    expect(accountName.call({ context: {} })).toBe("—");

    const element = createElement("c-order-create-step-billing", {
      is: OrderCreateStepBilling
    });
    element.context = {};
    document.body.appendChild(element);
    await Promise.resolve();

    expect(element.shadowRoot.textContent).toContain(
      "請求アカウントはこの画面では参照のみです。必須値が不足している場合は正規編集画面で設定してください。"
    );
    expect(element.shadowRoot.textContent).toContain(
      "請求アカウントが未設定です。見積作成画面で請求アカウントを設定してから受注してください。"
    );
  });

  it("受注処理中は正規編集を開かない (Core 5.2 / 4.3.12)", () => {
    const proto = OrderCreateStepBilling.prototype;
    const ctx = {
      busy: true,
      openBillingAccountFormalEdit: jest.fn()
    };
    proto.handleOpenFormalEdit.call(ctx);
    expect(ctx.openBillingAccountFormalEdit).not.toHaveBeenCalled();
  });

  it("受注確認は識別・送付・請求日ルール・支払条件の4束ねで専用LWCを埋め込まない (Core 5.2 / 3.3.2)", async () => {
    const element = createElement("c-order-create-step-billing", {
      is: OrderCreateStepBilling
    });
    element.context = {
      billingAccountId: "a00BA0000000001",
      billingAccountName: "BA-1",
      billingAccountKey: "KEY-1",
      billingCustomerAccountName: "取引先A"
    };
    document.body.appendChild(element);
    await Promise.resolve();
    const titles = Array.from(
      element.shadowRoot.querySelectorAll(".ba-bundle-title")
    ).map((node) => node.textContent.trim());
    expect(titles).toEqual([
      "識別",
      "送付",
      "請求日ルール",
      "支払条件"
    ]);
    expect(element.shadowRoot.querySelector("c-billing-account-form")).toBeFalsy();
    expect(element.shadowRoot.querySelector("lightning-input-field")).toBeFalsy();
  });
});
