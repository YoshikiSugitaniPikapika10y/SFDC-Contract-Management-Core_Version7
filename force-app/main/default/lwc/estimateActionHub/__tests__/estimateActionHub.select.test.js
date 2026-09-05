import EstimateActionHub from "c/estimateActionHub";

jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ __esModule: true, default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_04_Can_IssueEstimate",
  () => ({ __esModule: true, default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_05_Can_SendEstimate",
  () => ({ __esModule: true, default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getDocumentDefaults",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/uiRecordApi",
  () => ({ getRecord: jest.fn() }),
  { virtual: true }
);
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

function hubContext(recordId) {
  const dispatched = [];
  const ctx = Object.create(EstimateActionHub.prototype);
  Object.assign(ctx, {
    recordId,
    dispatchEvent(event) {
      dispatched.push(event.type);
    }
  });
  return { ctx, dispatched };
}

describe("estimateActionHub select (Core 4.3.1)", () => {
  let hrefSetter;

  beforeEach(() => {
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

  it("closes the hub before opening the selected existing screen", () => {
    const { ctx, dispatched } = hubContext("a0H000000000001AAA");

    EstimateActionHub.prototype.handleSelect.call(ctx, {
      currentTarget: { dataset: { key: "edit" } }
    });

    expect(dispatched).toEqual(["closeActionScreen"]);
    expect(hrefSetter).not.toHaveBeenCalled();

    jest.runAllTimers();

    expect(hrefSetter).toHaveBeenCalledWith(
      "/lightning/action/quick/ContractHistory__c.EstimateEdit?recordId=a0H000000000001AAA"
    );
  });

  it("opens copy, archive, and send as existing screens after close", () => {
    const { ctx } = hubContext("a0H000000000001AAA");

    EstimateActionHub.prototype.handleSelect.call(ctx, {
      currentTarget: { dataset: { key: "copy" } }
    });
    jest.runAllTimers();
    expect(hrefSetter).toHaveBeenLastCalledWith(
      "/lightning/action/quick/ContractHistory__c.EstimateCopy?recordId=a0H000000000001AAA"
    );

    EstimateActionHub.prototype.handleSelect.call(ctx, {
      currentTarget: { dataset: { key: "archive" } }
    });
    jest.runAllTimers();
    expect(hrefSetter).toHaveBeenLastCalledWith(
      "/lightning/action/quick/ContractHistory__c.Estimate_Archive?recordId=a0H000000000001AAA"
    );

    EstimateActionHub.prototype.handleSelect.call(ctx, {
      currentTarget: { dataset: { key: "send" } }
    });
    jest.runAllTimers();
    expect(hrefSetter).toHaveBeenLastCalledWith(
      "/lightning/action/quick/ContractHistory__c.Estimate_Send?recordId=a0H000000000001AAA"
    );
  });

  it("opens issue as the existing VF screen after close", () => {
    const { ctx, dispatched } = hubContext("a0H000000000001AAA");

    EstimateActionHub.prototype.handleSelect.call(ctx, {
      currentTarget: { dataset: { key: "issue" } }
    });

    expect(dispatched).toEqual(["closeActionScreen"]);
    expect(hrefSetter).not.toHaveBeenCalled();

    jest.runAllTimers();

    expect(hrefSetter).toHaveBeenCalledWith(
      "/apex/EstimateDocumentIssue?id=a0H000000000001AAA"
    );
  });

  it("does not close or open when the row has no action", () => {
    const { ctx, dispatched } = hubContext("a0H000000000001AAA");

    EstimateActionHub.prototype.handleSelect.call(ctx, {
      currentTarget: { dataset: { key: "" } }
    });

    expect(dispatched).toEqual([]);
    jest.runAllTimers();
    expect(hrefSetter).not.toHaveBeenCalled();
  });
});
