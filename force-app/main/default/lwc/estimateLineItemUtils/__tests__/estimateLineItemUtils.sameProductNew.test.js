import {
  buildChangeSameProductNewConfirmMessage,
  findChangeNewLinesWithSameProductAsRemake
} from "c/estimateLineItemUtils";

describe("findChangeNewLinesWithSameProductAsRemake", () => {
  const original = {
    productId: "01tAAA",
    productName: "プランA",
    recordType: "Original",
    sourceContractProductId: "a0xSRC",
    quantity: 1
  };
  const remake = {
    productId: "01tAAA",
    productName: "プランA",
    recordType: "Remake",
    sourceContractProductId: "a0xSRC",
    quantity: 1
  };

  it("returns New lines whose Product2 matches Original/Remake", () => {
    const matched = findChangeNewLinesWithSameProductAsRemake([
      original,
      remake,
      {
        productId: "01tAAA",
        productName: "プランA",
        recordType: "New",
        sourceContractProductId: null,
        quantity: 1
      }
    ]);
    expect(matched).toHaveLength(1);
    expect(matched[0].productId).toBe("01tAAA");
  });

  it("does not warn when New uses a different Product2", () => {
    const matched = findChangeNewLinesWithSameProductAsRemake([
      original,
      remake,
      {
        productId: "01tBBB",
        productName: "プランB",
        recordType: "New",
        sourceContractProductId: null,
        quantity: 1
      }
    ]);
    expect(matched).toHaveLength(0);
  });

  it("dedupes by Product2 Id across multiple New rows", () => {
    const matched = findChangeNewLinesWithSameProductAsRemake([
      original,
      remake,
      {
        productId: "01tAAA",
        productName: "プランA",
        recordType: "New",
        sourceContractProductId: null,
        quantity: 1
      },
      {
        productId: "01tAAA",
        productName: "プランA",
        recordType: "New",
        sourceContractProductId: null,
        quantity: 2
      }
    ]);
    expect(matched).toHaveLength(1);
  });
});

describe("buildChangeSameProductNewConfirmMessage", () => {
  it("returns null when no same-product New exists", () => {
    expect(
      buildChangeSameProductNewConfirmMessage([
        {
          productId: "01tAAA",
          recordType: "Original",
          sourceContractProductId: "a0xSRC",
          quantity: 1
        },
        {
          productId: "01tAAA",
          recordType: "Remake",
          sourceContractProductId: "a0xSRC",
          quantity: 1
        }
      ])
    ).toBeNull();
  });

  it("includes guidance and product name when same Product2 New exists", () => {
    const message = buildChangeSameProductNewConfirmMessage([
      {
        productId: "01tAAA",
        productName: "プランA",
        recordType: "Original",
        sourceContractProductId: "a0xSRC",
        quantity: 1
      },
      {
        productId: "01tAAA",
        productName: "プランA",
        recordType: "Remake",
        sourceContractProductId: "a0xSRC",
        quantity: 1
      },
      {
        productId: "01tAAA",
        productName: "プランA",
        recordType: "New",
        sourceContractProductId: null,
        quantity: 1
      }
    ]);
    expect(message).toContain("既存契約と同じ商品が新規明細に含まれています");
    expect(message).toContain("対象商品: プランA");
    expect(message).toContain("既存明細を編集してください");
    expect(message).toContain("追加購入の場合はそのまま続行できます");
    expect(message).not.toContain("Remake");
    expect(message).not.toContain("続行しますか？");
  });
});
