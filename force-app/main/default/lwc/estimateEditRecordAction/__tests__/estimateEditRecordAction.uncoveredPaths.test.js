import EstimateEditRecordAction from "c/estimateEditRecordAction";
import {
  closeEstimateWizard,
  markEstimateRecordForRefresh,
  refreshOnEstimateRecordActionUnmount
} from "c/estimateWizardClose";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "lightning/navigation",
  () => {
    const NavigationMixin = (Base) => class extends Base {};
    NavigationMixin.Navigate = "Navigate";
    return { NavigationMixin };
  },
  { virtual: true }
);
jest.mock("lightning/uiRecordApi", () => ({ getRecord: jest.fn() }), {
  virtual: true
});
jest.mock(
  "@salesforce/schema/ContractHistory__c.historystatus__c",
  () => ({ default: "ContractHistory__c.historystatus__c" }),
  { virtual: true }
);
jest.mock("c/estimateWizardClose", () => ({
  closeEstimateWizard: jest.fn(),
  markEstimateRecordForRefresh: jest.fn(),
  refreshOnEstimateRecordActionUnmount: jest.fn()
}));
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

const proto = EstimateEditRecordAction.prototype;

function bind(overrides = {}) {
  const navigate = jest.fn();
  const ctx = {
    recordId: "a01000000000001AAA",
    pendingRecordRefresh: undefined,
    historyStatus: "Estimate",
    Navigate: navigate,
    ...overrides
  };
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (name === "constructor") {
      return;
    }
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    if (!desc || (desc.get && desc.set)) {
      return;
    }
    if (Object.prototype.hasOwnProperty.call(ctx, name)) {
      return;
    }
    if (desc.get && !desc.set) {
      Object.defineProperty(ctx, name, { get: desc.get, configurable: true });
    } else if (typeof desc.value === "function") {
      ctx[name] = desc.value;
    }
  });
  ctx.__navigate = navigate;
  return ctx;
}

describe("estimateEditRecordAction uncovered (Core 4.1 / 4.3.1 / 4.7)", () => {
  beforeEach(() => {
    closeEstimateWizard.mockClear();
    markEstimateRecordForRefresh.mockClear();
    refreshOnEstimateRecordActionUnmount.mockClear();
    resizeQuickActionPanel.mockClear();
  });

  it("hasPermission true with Loop_03", () => {
    expect(bind().hasPermission).toBe(true);
  });

  it("canOpenWizard for Estimate and Ordered only (Core 4.1 / 4.7)", () => {
    expect(bind({ historyStatus: "Estimate" }).canOpenWizard).toBe(true);
    expect(bind({ historyStatus: "Ordered" }).canOpenWizard).toBe(true);
    expect(bind({ historyStatus: "Archive" }).canOpenWizard).toBe(false);
  });

  it("cannotEditMessage for Archive; empty for Estimate/Ordered (Core 4.7)", () => {
    expect(bind({ historyStatus: "Archive" }).cannotEditMessage).toBe(
      "見積／受注済み状態の契約履歴のみ編集できます。"
    );
    expect(bind({ historyStatus: "Estimate" }).cannotEditMessage).toBe("");
    expect(bind({ historyStatus: "Ordered" }).cannotEditMessage).toBe("");
    expect(bind({ historyStatus: "" }).cannotEditMessage).toBe("");
  });

  it("wiredHistory sets status from getRecord data", () => {
    const ctx = bind({ historyStatus: "" });
    ctx.wiredHistory({
      data: { fields: { historystatus__c: { value: "Ordered" } } }
    });
    expect(ctx.historyStatus).toBe("Ordered");
  });

  it("wiredHistory clears status on error or missing value", () => {
    const ctx = bind({ historyStatus: "Estimate" });
    ctx.wiredHistory({ error: { body: { message: "fail" } } });
    expect(ctx.historyStatus).toBe("");
    ctx.wiredHistory({ data: { fields: {} } });
    expect(ctx.historyStatus).toBe("");
  });

  it("connectedCallback / renderedCallback resize panel", () => {
    const ctx = bind();
    ctx.connectedCallback();
    ctx.renderedCallback();
    expect(resizeQuickActionPanel).toHaveBeenCalledWith(ctx);
  });

  it("handleRequestClose closes with default refresh and own history id", () => {
    const ctx = bind();
    ctx.handleRequestClose({ detail: {} });
    expect(closeEstimateWizard).toHaveBeenCalledWith(ctx, {
      refresh: true,
      opportunityId: undefined,
      contractHistoryId: "a01000000000001AAA"
    });
    expect(ctx.__navigate).not.toHaveBeenCalled();
  });

  it("handleRequestClose navigates when navigateToContractHistoryId set", () => {
    const ctx = bind();
    ctx.handleRequestClose({
      detail: {
        refresh: false,
        opportunityId: "006AAA",
        contractHistoryId: "a01000000000002AAA",
        navigateToContractHistoryId: "a01000000000003AAA"
      }
    });
    expect(closeEstimateWizard).toHaveBeenCalledWith(ctx, {
      refresh: false,
      opportunityId: "006AAA",
      contractHistoryId: "a01000000000002AAA"
    });
    expect(ctx.__navigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: "a01000000000003AAA",
        objectApiName: "ContractHistory__c",
        actionName: "view"
      }
    });
  });

  it("handleEstimateSaved marks refresh from opportunity or history", () => {
    const ctx = bind();
    ctx.handleEstimateSaved({
      detail: { opportunityId: "006BBB", contractHistoryId: "a01X" }
    });
    expect(markEstimateRecordForRefresh).toHaveBeenCalledWith(ctx, "006BBB");
    ctx.handleEstimateSaved({ detail: { contractHistoryId: "a01Y" } });
    expect(markEstimateRecordForRefresh).toHaveBeenCalledWith(ctx, "a01Y");
  });

  it("disconnectedCallback refreshes on unmount", () => {
    const ctx = bind();
    ctx.disconnectedCallback();
    expect(refreshOnEstimateRecordActionUnmount).toHaveBeenCalledWith(ctx);
  });
});
