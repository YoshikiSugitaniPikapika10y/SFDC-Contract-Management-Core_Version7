import {
  resolveSavedContractStartDate,
  resolveSavedContractEndDate
} from "../contractDateInit";
import {
  buildProductsFingerprint,
  shouldSyncProductsFromParent
} from "../productDisplaySync";
import {
  createConfirmRequestId,
  hasEstimateRemarksText
} from "../remarksConfirm";
import { serializeBusinessProduct } from "../businessProduct";
import {
  WIZARD_ACTIONS,
  createInitialWizardState,
  reduceWizardState
} from "c/estimateWizardState";

const dispatch = (state, action) => reduceWizardState(state, action);

describe("contractDateInit", () => {
  it("contractEndDate を優先し endDate をフォールバックする", () => {
    expect(
      resolveSavedContractEndDate({
        contractEndDate: "2027-03-31",
        endDate: "2099-01-01"
      })
    ).toBe("2027-03-31");
    expect(resolveSavedContractEndDate({ endDate: "2027-03-31" })).toBe(
      "2027-03-31"
    );
    expect(resolveSavedContractEndDate({})).toBe("");
    expect(
      resolveSavedContractStartDate({ contractStartDate: "2026-04-01" })
    ).toBe("2026-04-01");
  });
});

describe("productDisplaySync", () => {
  it("自 emit と同じ fingerprint なら同期しない", () => {
    const products = [
      serializeBusinessProduct({
        id: "r1",
        productId: "p1",
        productName: "A",
        quantity: 1,
        startDate: "2026-04-01",
        endDate: "2027-03-31"
      })
    ];
    const fingerprint = buildProductsFingerprint(products);
    expect(shouldSyncProductsFromParent(products, fingerprint, "")).toBe(false);
    expect(shouldSyncProductsFromParent(products, "", fingerprint)).toBe(false);
    expect(shouldSyncProductsFromParent(products, "", "")).toBe(true);
  });

  it("親の商品内容が変わったら同期する", () => {
    const before = [
      serializeBusinessProduct({
        id: "r1",
        productId: "p1",
        quantity: 1
      })
    ];
    const after = [
      serializeBusinessProduct({
        id: "r1",
        productId: "p1",
        quantity: 2
      })
    ];
    const emitted = buildProductsFingerprint(before);
    expect(shouldSyncProductsFromParent(after, emitted, emitted)).toBe(true);
  });
});

describe("remarksConfirm", () => {
  it("requestId を発行し備考テキスト有無を判定する", () => {
    expect(createConfirmRequestId(0)).toMatch(/^confirm-\d+-0$/);
    expect(hasEstimateRemarksText("  hello ")).toBe(true);
    expect(hasEstimateRemarksText("   ")).toBe(false);
  });
});

describe("wizard confirm + date merge integration", () => {
  it("MERGE_STEP3 は contractEndDate のみでも終了日を保持する", () => {
    let state = createInitialWizardState();
    state = dispatch(state, {
      type: WIZARD_ACTIONS.MERGE_STEP3,
      fields: {
        contractStartDate: "2026-04-01",
        contractEndDate: "2027-03-31"
      }
    });
    expect(state.data.contractEndDate).toBe("2027-03-31");
    expect(resolveSavedContractEndDate(state.data)).toBe("2027-03-31");
  });

  it("Apex 互換 endDate のみでも init 用ヘルパが終了日を返す", () => {
    let state = createInitialWizardState();
    state = dispatch(state, {
      type: WIZARD_ACTIONS.MERGE_STEP3,
      fields: { endDate: "2027-12-31" }
    });
    expect(state.data.contractEndDate).toBe("2027-12-31");
    expect(resolveSavedContractEndDate(state.data)).toBe("2027-12-31");
    // state に endDate キーは残らない
    expect(Object.prototype.hasOwnProperty.call(state.data, "endDate")).toBe(
      false
    );
  });
});
