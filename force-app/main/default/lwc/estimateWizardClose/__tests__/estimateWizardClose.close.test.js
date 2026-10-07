import {
  closeEstimateWizard,
  refreshOnEstimateRecordActionUnmount
} from "c/estimateWizardClose";

const mockGetRecordNotifyChange = jest.fn();
const mockGetLightningBase = jest.fn(() => "https://example.my.salesforce.com");

jest.mock(
  "lightning/actions",
  () => ({
    CloseActionScreenEvent: class CloseActionScreenEvent extends Event {
      constructor() {
        super("closeActionScreen");
      }
    }
  }),
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
  "lightning/uiRecordApi",
  () => ({
    getRecordNotifyChange: (...args) => mockGetRecordNotifyChange(...args)
  }),
  { virtual: true }
);
jest.mock(
  "c/estimateWizardNavigation",
  () => ({ getLightningBase: (...args) => mockGetLightningBase(...args) }),
  { virtual: true }
);

describe("estimateWizardClose (Core 4.3.2 / 4.3.6)", () => {
  let hrefSetter;

  beforeEach(() => {
    mockGetRecordNotifyChange.mockClear();
    mockGetLightningBase.mockClear();
    jest.useFakeTimers();
    hrefSetter = jest.fn();
    Object.defineProperty(window, "location", {
      configurable: true,
      value: {
        get href() {
          return "https://example.my.salesforce.com/lightning/r/ContractHistory__c/a0HSRC/view";
        },
        set href(value) {
          hrefSetter(value);
        }
      }
    });
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it("closes before any record refresh, then opens the saved history", () => {
    const dispatched = [];
    const component = {
      recordId: "006000000000001AAA",
      dispatchEvent: (event) => {
        dispatched.push(event.type);
      }
    };

    closeEstimateWizard(component, {
      refresh: true,
      opportunityId: "006000000000001AAA",
      contractHistoryId: "a0HNEW000000001AAA",
      navigateToContractHistoryId: "a0HNEW000000001AAA"
    });

    expect(dispatched).toEqual(["closeActionScreen"]);
    expect(mockGetRecordNotifyChange).not.toHaveBeenCalled();
    expect(component.pendingRecordRefresh).toBe("a0HNEW000000001AAA");
    expect(component.pendingRelatedRefresh).toEqual({
      opportunityId: "006000000000001AAA",
      contractHistoryId: "a0HNEW000000001AAA"
    });
    expect(hrefSetter).not.toHaveBeenCalled();

    jest.runAllTimers();

    expect(hrefSetter).toHaveBeenCalledWith(
      "https://example.my.salesforce.com/lightning/r/ContractHistory__c/a0HNEW000000001AAA/view"
    );
    expect(mockGetRecordNotifyChange).not.toHaveBeenCalled();

    refreshOnEstimateRecordActionUnmount(component);

    expect(dispatched).toEqual(["closeActionScreen", "refresh"]);
    expect(mockGetRecordNotifyChange).toHaveBeenCalledWith([
      { recordId: "006000000000001AAA" },
      { recordId: "a0HNEW000000001AAA" }
    ]);
  });

  it("does not mark a refresh when closing without one", () => {
    const component = {
      recordId: "006000000000001AAA",
      dispatchEvent: () => {}
    };

    closeEstimateWizard(component, {
      refresh: false,
      navigateToContractHistoryId: "a0HNEW000000001AAA"
    });

    expect(component.pendingRecordRefresh).toBeUndefined();
    expect(component.pendingRelatedRefresh).toBeUndefined();
    jest.runAllTimers();
    expect(hrefSetter).toHaveBeenCalledWith(
      "https://example.my.salesforce.com/lightning/r/ContractHistory__c/a0HNEW000000001AAA/view"
    );
  });
});
