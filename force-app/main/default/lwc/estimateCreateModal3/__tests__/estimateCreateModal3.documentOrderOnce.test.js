import EstimateCreateModal3 from "c/estimateCreateModal3";

jest.mock(
  "@salesforce/apex/EstimateCreateController.getProductDefaults",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getRecurringContractProducts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getRenewContractProducts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getContractHistoryInfo",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getEstimateRemarkMasterText",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getInvoiceSettingOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getDefaultInvoiceSettingLabel",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const proto = EstimateCreateModal3.prototype;

function line(id, documentSortOrder) {
  return {
    id,
    documentSortOrder,
    startDate: "2026-04-01",
    recordType: "New",
    lineName: id
  };
}

function createContext(itemList) {
  const ctx = {
    itemList,
    _wizardData: { selectedType: "New" },
    _detailOrderApplied: false,
    hasProductCustomFields: false,
    productModalRowId: null,
    amountModalRowId: null,
    productFieldDefinitions: []
  };
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (
      name === "constructor" ||
      Object.prototype.hasOwnProperty.call(ctx, name)
    ) {
      return;
    }
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    if (desc.get && !desc.set) {
      Object.defineProperty(ctx, name, {
        get: desc.get,
        configurable: true
      });
    } else if (typeof desc.value === "function") {
      ctx[name] = desc.value;
    }
  });
  return ctx;
}

describe("estimateCreateModal3 document order once (Core 4.5.3)", () => {
  it("sorts on first entry and keeps that order when the sort key changes", () => {
    const ctx = createContext([line("later", 20), line("earlier", 5)]);

    expect(ctx.displayItemList.map((row) => row.id)).toEqual([
      "earlier",
      "later"
    ]);
    expect(ctx.itemList.map((row) => row.id)).toEqual(["later", "earlier"]);

    ctx.applyDocumentOrderOnce();
    expect(ctx.itemList.map((row) => row.id)).toEqual(["earlier", "later"]);

    ctx.itemList = ctx.itemList.map((row) => ({
      ...row,
      documentSortOrder: row.id === "earlier" ? 30 : 1,
      startDate: row.id === "earlier" ? "2026-08-01" : "2026-01-01"
    }));
    ctx.itemList = [...ctx.itemList, line("added", 0)];

    expect(ctx.displayItemList.map((row) => row.id)).toEqual([
      "earlier",
      "later",
      "added"
    ]);
    ctx.applyDocumentOrderOnce();
    expect(ctx.itemList.map((row) => row.id)).toEqual([
      "earlier",
      "later",
      "added"
    ]);
  });

  it("does not glue a remake under its original when another original sorts between them (Core 4.5.3)", () => {
    const ctx = createContext([
      changeLine("a-remake", "Remake", 1, "2026-03-01", "pair-a"),
      changeLine("b-original", "Original", 1, "2026-02-01", "pair-b"),
      changeLine("a-original", "Original", 1, "2026-01-01", "pair-a")
    ]);
    ctx._wizardData = { selectedType: "Change" };

    const productIds = (rows) =>
      rows.filter((row) => !row.isGroupHeader).map((row) => row.id);

    expect(productIds(ctx.displayItemList)).toEqual([
      "a-original",
      "b-original",
      "a-remake"
    ]);

    ctx.applyDocumentOrderOnce();
    expect(ctx.itemList.map((row) => row.id)).toEqual([
      "a-original",
      "b-original",
      "a-remake"
    ]);
    expect(productIds(ctx.displayItemList)).toEqual([
      "a-original",
      "b-original",
      "a-remake"
    ]);

    ctx.itemList = ctx.itemList.map((row) =>
      row.id === "a-remake" ? { ...row, startDate: "2026-01-15" } : row
    );
    expect(ctx.itemList.map((row) => row.id)).toEqual([
      "a-original",
      "b-original",
      "a-remake"
    ]);
  });
});

function changeLine(id, recordType, documentSortOrder, startDate, pairId) {
  return {
    id,
    recordType,
    documentSortOrder,
    startDate,
    pairId,
    sourceContractProductId: `${pairId}-source`,
    productName: pairId,
    lineName: id
  };
}
