import { createElement } from "lwc";
import OrderRevertWizard from "c/orderRevertWizard";
import getOrderContext from "@salesforce/apex/OrderCreateController.getOrderContext";
import hasManualInvoiceAdjustment from "@salesforce/apex/OrderCreateController.hasManualInvoiceAdjustment";

jest.mock(
  "@salesforce/customPermission/Loop_07_Can_Revert",
  () => ({ __esModule: true, default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.getOrderContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.revertOrder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.issueOrderOperationKey",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.hasManualInvoiceAdjustment",
  () => ({ default: jest.fn() }),
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
  "lightning/platformShowToastEvent",
  () => ({ ShowToastEvent: class ShowToastEvent {} }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardNavigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {},
    closeOrderWizardTab: jest.fn(),
    initializeOrderWizardFromUrl: jest.fn(),
    isOrderWizardTabView: () => false,
    readOrderWizardRecordId: () => null
  }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardClose",
  () => ({
    HISTORY_STATUS_ARCHIVE: "Archive",
    isOrderActionBootstrapping: (component) => component.isLoading === true,
    notifyOrderRecordStatusChanged: jest.fn(),
    requestOrderWizardClose: jest.fn(),
    scheduleRecordActionLoad: (component, loadFn) => {
      if (
        !component.recordId ||
        component._loadedOrderActionRecordId === component.recordId
      ) {
        return;
      }
      component._loadedOrderActionRecordId = component.recordId;
      loadFn();
    },
    resetRecordActionLoadState: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "c/estimateValidationAlertUtils",
  () => ({
    resolveSaveErrorAlert: () => ({ messages: [] })
  }),
  { virtual: true }
);
jest.mock(
  "c/estimateWizardCustomFields",
  () => ({
    buildCustomFieldInputs: (definitions) =>
      (definitions || []).map((field) => ({
        ...field,
        key: field.apiName
      }))
  }),
  { virtual: true }
);

const ORDERED = {
  historyStatus: "Ordered",
  isOrdered: true,
  canRevert: true,
  hasRenewOpportunity: true,
  lastModifiedToken: "tok",
  historySavedFields: { OrderDate__c: "2026-01-15", Extra__c: "残す" },
  historyFieldDefinitions: [
    { apiName: "OrderDate__c", label: "受注日" },
    { apiName: "Extra__c", label: "追加A" }
  ],
  historyType: "New"
};

async function flushApex() {
  await Promise.resolve();
  const contextCall = getOrderContext.mock.results[0];
  if (contextCall?.value) {
    await contextCall.value;
  }
  const adjustCall = hasManualInvoiceAdjustment.mock.results[0];
  if (adjustCall?.value) {
    await adjustCall.value;
  }
  await Promise.resolve();
}

async function mount() {
  const element = createElement("c-order-revert-wizard", {
    is: OrderRevertWizard
  });
  element.recordId = "a0H000000000001AAA";
  document.body.appendChild(element);
  await flushApex();
  return element;
}

describe("orderRevertWizard (Core 5.3 / 4.3.1)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    getOrderContext.mockReset();
    hasManualInvoiceAdjustment.mockReset();
  });

  it("shows revert confirmation copy and keeps the submit enabled", async () => {
    getOrderContext.mockResolvedValue(ORDERED);
    hasManualInvoiceAdjustment.mockResolvedValue(false);
    const element = await mount();
    const text = element.shadowRoot.textContent;
    expect(element.shadowRoot.querySelector(".confirm-title").textContent).toBe(
      "差し戻し"
    );
    expect(text).toContain("受注済みを見積に戻します");
    expect(text).toContain("この契約履歴を見積に差し戻します。よろしいですか？");
    expect(text).toContain("請求正本が削除されます");
    expect(text).toContain("契約期間明細が削除されます");
    const submit = [...element.shadowRoot.querySelectorAll("button")].find(
      (node) => node.textContent.trim() === "見積に差し戻す"
    );
    expect(submit).toBeTruthy();
    expect(submit.disabled).toBe(false);
    const extraFields = Object.getOwnPropertyDescriptor(
      OrderRevertWizard.prototype,
      "revertHistoryFieldDefinitions"
    ).get.call({ context: ORDERED });
    expect(extraFields.map((field) => field.apiName)).toEqual([
      "OrderDate__c",
      "Extra__c"
    ]);
    expect(extraFields.every((field) => field.required === false)).toBe(true);
    expect(element.historyCustomFields.OrderDate__c).toBe("2026-01-15");
  });

  it("warns that manual invoice adjustments are deleted, and defaults renew-opportunity delete on", async () => {
    getOrderContext.mockResolvedValue(ORDERED);
    hasManualInvoiceAdjustment.mockResolvedValue(true);
    const element = await mount();
    const text = element.shadowRoot.textContent;
    expect(text).toContain(
      "端数調整・分割・移動・請求情報の手直しがある請求があります。差し戻すとそれらも削除されます。"
    );
    const box = element.shadowRoot.querySelector('input[type="checkbox"]');
    expect(box).toBeTruthy();
    expect(box.checked).toBe(true);
    expect(text).toContain("更新商談を削除する");
  });

  it("refuses Archive histories", async () => {
    getOrderContext.mockResolvedValue({
      historyStatus: "Archive",
      isOrdered: false
    });
    const archived = await mount();
    expect(archived.shadowRoot.textContent).toContain(
      "アーカイブ済みの契約履歴では差し戻しは利用できません。"
    );
    const submit = [...archived.shadowRoot.querySelectorAll("button")].find(
      (node) => node.textContent.trim() === "見積に差し戻す"
    );
    expect(submit.disabled).toBe(true);
  });
});
