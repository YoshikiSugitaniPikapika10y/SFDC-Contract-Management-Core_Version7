import { closeEstimateWizard } from "c/estimateWizardClose";

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

  it("closes the action before opening the saved history, without confirm", () => {
    const dispatched = [];
    const component = {
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

    expect(dispatched).toEqual(["refresh", "closeActionScreen"]);
    expect(hrefSetter).not.toHaveBeenCalled();

    jest.runAllTimers();

    expect(hrefSetter).toHaveBeenCalledWith(
      "https://example.my.salesforce.com/lightning/r/ContractHistory__c/a0HNEW000000001AAA/view"
    );
  });
});
