import OrderCreateRecordAction from "c/orderCreateRecordAction";
import {
  closeOrderRecordAction,
  markOrderRecordForRefresh,
  refreshOnRecordActionUnmount
} from "c/orderWizardClose";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_06_Can_Order",
  () => ({ __esModule: true, default: true }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardNavigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {}
  }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardClose",
  () => ({
    closeOrderRecordAction: jest.fn(),
    markOrderRecordForRefresh: jest.fn(),
    refreshOnRecordActionUnmount: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "c/quickActionPanelResize",
  () => ({ resizeQuickActionPanel: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/orderCreateWizard",
  () => {
    const { LightningElement } = require("lwc");
    return class OrderCreateWizard extends LightningElement {};
  },
  { virtual: true }
);

const proto = OrderCreateRecordAction.prototype;
const recordIdDesc = Object.getOwnPropertyDescriptor(proto, "recordId");

function bind(overrides = {}) {
  const ctx = {
    _recordId: "a0H000000000001AAA",
    recordId: "a0H000000000001AAA",
    pendingRecordRefresh: undefined,
    panelSize: "large",
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
  return ctx;
}

describe("orderCreateRecordAction uncovered (Core 5.2 / 5.1)", () => {
  beforeEach(() => {
    closeOrderRecordAction.mockClear();
    markOrderRecordForRefresh.mockClear();
    refreshOnRecordActionUnmount.mockClear();
    resizeQuickActionPanel.mockClear();
  });

  it("hasPermission is true with Loop_06", () => {
    expect(bind().hasPermission).toBe(true);
  });

  it("connectedCallback / renderedCallback resize large panel", () => {
    const ctx = bind();
    ctx.connectedCallback();
    ctx.renderedCallback();
    expect(resizeQuickActionPanel).toHaveBeenCalledWith(ctx, "large");
  });

  it("panel size change accepts confirm and large only (Core 5.2)", () => {
    const ctx = bind({ panelSize: "large" });
    ctx.handlePanelSizeChange({ detail: { size: "small" } });
    expect(ctx.panelSize).toBe("large");
    expect(resizeQuickActionPanel).not.toHaveBeenCalled();

    ctx.handlePanelSizeChange({ detail: { size: "large" } });
    expect(resizeQuickActionPanel).not.toHaveBeenCalled();

    ctx.handlePanelSizeChange({ detail: { size: "confirm" } });
    expect(ctx.panelSize).toBe("confirm");
    expect(resizeQuickActionPanel).toHaveBeenCalledWith(ctx, "confirm");
  });

  it("handleRequestClose closes with refresh default true", () => {
    const ctx = bind();
    ctx.handleRequestClose({ detail: {} });
    expect(closeOrderRecordAction).toHaveBeenCalledWith(ctx, {
      refresh: true,
      recordId: "a0H000000000001AAA"
    });
  });

  it("handleRequestClose respects refresh false and detail recordId", () => {
    const ctx = bind();
    ctx.handleRequestClose({
      detail: { refresh: false, recordId: "a0H000000000099AAA" }
    });
    expect(closeOrderRecordAction).toHaveBeenCalledWith(ctx, {
      refresh: false,
      recordId: "a0H000000000099AAA"
    });
  });

  it("missing detail still closes with own recordId", () => {
    const ctx = bind();
    ctx.handleRequestClose({});
    expect(closeOrderRecordAction).toHaveBeenCalledWith(ctx, {
      refresh: true,
      recordId: "a0H000000000001AAA"
    });
  });

  it("order status change marks refresh", () => {
    const ctx = bind();
    ctx.handleOrderRecordStatusChanged({
      detail: { recordId: "a0H000000000002AAA" }
    });
    expect(markOrderRecordForRefresh).toHaveBeenCalledWith(
      ctx,
      "a0H000000000002AAA"
    );
  });

  it("disconnectedCallback refreshes on unmount", () => {
    const ctx = bind();
    ctx.disconnectedCallback();
    expect(refreshOnRecordActionUnmount).toHaveBeenCalledWith(ctx);
  });

  it("plain recordId property is used by close path", () => {
    const ctx = bind({ recordId: "a0H000000000003AAA", _recordId: "a0H000000000003AAA" });
    ctx.handleRequestClose({ detail: { refresh: true } });
    expect(closeOrderRecordAction).toHaveBeenCalledWith(
      ctx,
      expect.objectContaining({ recordId: "a0H000000000003AAA" })
    );
    expect(recordIdDesc).toBeTruthy();
  });
});
