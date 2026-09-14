import { createElement } from "lwc";
import EstimateEditRecordAction from "c/estimateEditRecordAction";
import { getRecord } from "lightning/uiRecordApi";

const mockNavigate = jest.fn();

jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "lightning/uiRecordApi",
  () => {
    const {
      createLdsTestWireAdapter
    } = require("@salesforce/wire-service-jest-util");
    return {
      getRecord: createLdsTestWireAdapter(),
      getRecordNotifyChange: jest.fn()
    };
  },
  { virtual: true }
);
jest.mock(
  "lightning/refresh",
  () => ({
    RefreshEvent: class RefreshEvent extends Event {
      constructor() {
        super("refresh");
      }
    }
  }),
  { virtual: true }
);
jest.mock(
  "lightning/navigation",
  () => {
    const NavigationMixin = (Base) =>
      class extends Base {
        Navigate(pageReference) {
          mockNavigate(pageReference);
        }
      };
    NavigationMixin.Navigate = "Navigate";
    return { NavigationMixin };
  },
  { virtual: true }
);
jest.mock(
  "c/quickActionPanelResize",
  () => ({ resizeQuickActionPanel: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/estimateCreateWizard",
  () => {
    const { LightningElement } = require("lwc");
    return class EstimateCreateWizard extends LightningElement {};
  },
  { virtual: true }
);

function flushPromises() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe("estimateEditRecordAction (Core 4.1 / 4.3.1 / 4.7 / 12.2)", () => {
  afterEach(() => {
    mockNavigate.mockClear();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  const canOpenWizard = Object.getOwnPropertyDescriptor(
    EstimateEditRecordAction.prototype,
    "canOpenWizard"
  ).get;
  const cannotEditMessage = Object.getOwnPropertyDescriptor(
    EstimateEditRecordAction.prototype,
    "cannotEditMessage"
  ).get;

  it("opens the wizard for Estimate (hub) and Ordered (highlight)", () => {
    expect(
      canOpenWizard.call({ hasPermission: true, historyStatus: "Ordered" })
    ).toBe(true);
    expect(
      canOpenWizard.call({ hasPermission: true, historyStatus: "Estimate" })
    ).toBe(true);
  });

  it("does not open the wizard without status or permission", () => {
    expect(canOpenWizard.call({ hasPermission: true, historyStatus: "" })).toBe(
      false
    );
    expect(
      canOpenWizard.call({ hasPermission: false, historyStatus: "Ordered" })
    ).toBe(false);
  });

  it("does not open the wizard for Archive", () => {
    expect(
      canOpenWizard.call({ hasPermission: true, historyStatus: "Archive" })
    ).toBe(false);
    expect(
      cannotEditMessage.call({ hasPermission: true, historyStatus: "Archive" })
    ).toBe("見積／受注済み状態の契約履歴のみ編集できます。");
  });

  it("renders the edit wizard from the Ordered highlight entry", async () => {
    const element = createElement("c-estimate-edit-record-action", {
      is: EstimateEditRecordAction
    });
    element.recordId = "a01000000000001AAA";
    document.body.appendChild(element);
    getRecord.emit({
      fields: { historystatus__c: { value: "Ordered" } }
    });
    await flushPromises();

    expect(
      element.shadowRoot.querySelector("c-estimate-create-wizard")
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
  });

  it("navigates to the requested history after the Ordered wizard closes", async () => {
    const element = createElement("c-estimate-edit-record-action", {
      is: EstimateEditRecordAction
    });
    element.recordId = "a01000000000001AAA";
    document.body.appendChild(element);
    getRecord.emit({
      fields: { historystatus__c: { value: "Ordered" } }
    });
    await flushPromises();

    element.shadowRoot.querySelector("c-estimate-create-wizard").dispatchEvent(
      new CustomEvent("requestclose", {
        detail: {
          refresh: false,
          navigateToContractHistoryId: "a01000000000002AAA"
        }
      })
    );

    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: "a01000000000002AAA",
        objectApiName: "ContractHistory__c",
        actionName: "view"
      }
    });
  });
});
