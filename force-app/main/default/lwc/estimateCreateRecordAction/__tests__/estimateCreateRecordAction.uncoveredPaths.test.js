import EstimateCreateRecordAction from "c/estimateCreateRecordAction";
import {
  closeEstimateWizard,
  markEstimateRecordForRefresh,
  refreshOnEstimateRecordActionUnmount
} from "c/estimateWizardClose";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ __esModule: true, default: true }),
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
jest.mock(
  "c/estimateWizardClose",
  () => ({
    closeEstimateWizard: jest.fn(),
    markEstimateRecordForRefresh: jest.fn(),
    refreshOnEstimateRecordActionUnmount: jest.fn()
  }),
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

const proto = EstimateCreateRecordAction.prototype;

function bind(overrides = {}) {
  const navigate = jest.fn();
  const ctx = {
    recordId: "006000000000001AAA",
    pendingRecordRefresh: undefined,
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

describe("estimateCreateRecordAction uncovered (Core 4.3.1)", () => {
  beforeEach(() => {
    closeEstimateWizard.mockClear();
    markEstimateRecordForRefresh.mockClear();
    refreshOnEstimateRecordActionUnmount.mockClear();
    resizeQuickActionPanel.mockClear();
  });

  it("hasPermission true with Loop_03", () => {
    expect(bind().hasPermission).toBe(true);
  });

  it("connectedCallback / renderedCallback resize panel", () => {
    const ctx = bind();
    ctx.connectedCallback();
    ctx.renderedCallback();
    expect(resizeQuickActionPanel).toHaveBeenCalledWith(ctx);
  });

  it("handleRequestClose uses opportunity from detail or recordId (Core 4.3.1)", () => {
    const ctx = bind();
    ctx.handleRequestClose({ detail: {} });
    expect(closeEstimateWizard).toHaveBeenCalledWith(ctx, {
      refresh: true,
      opportunityId: "006000000000001AAA",
      contractHistoryId: undefined
    });
    expect(ctx.__navigate).not.toHaveBeenCalled();
  });

  it("handleRequestClose respects refresh false and navigates to history", () => {
    const ctx = bind();
    ctx.handleRequestClose({
      detail: {
        refresh: false,
        opportunityId: "006BBB",
        contractHistoryId: "a01000000000002AAA",
        navigateToContractHistoryId: "a01000000000003AAA"
      }
    });
    expect(closeEstimateWizard).toHaveBeenCalledWith(ctx, {
      refresh: false,
      opportunityId: "006BBB",
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

  it("handleEstimateSaved marks refresh from opportunity or own record", () => {
    const ctx = bind();
    ctx.handleEstimateSaved({ detail: { opportunityId: "006CCC" } });
    expect(markEstimateRecordForRefresh).toHaveBeenCalledWith(ctx, "006CCC");
    ctx.handleEstimateSaved({ detail: {} });
    expect(markEstimateRecordForRefresh).toHaveBeenCalledWith(
      ctx,
      "006000000000001AAA"
    );
  });

  it("disconnectedCallback refreshes on unmount", () => {
    const ctx = bind();
    ctx.disconnectedCallback();
    expect(refreshOnEstimateRecordActionUnmount).toHaveBeenCalledWith(ctx);
  });
});
