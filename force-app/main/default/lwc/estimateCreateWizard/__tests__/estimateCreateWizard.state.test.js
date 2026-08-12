import {
  WIZARD_ACTIONS,
  createInitialWizardState,
  reduceWizardState,
  canLeaveCurrentStep,
  formatHistoryVersion
} from "c/estimateWizardState";

const dispatch = (state, action) => reduceWizardState(state, action);

/**
 * estimateCreateWizard が依存する状態遷移の結合テスト。
 * コンポーネント自体より、次へ可否と Step3 許可リストを中心に検証する。
 */
describe("estimateCreateWizard state integration", () => {
  it("契約履歴読込中は次へ進めない", () => {
    let state = createInitialWizardState();
    state = dispatch(state, {
      type: WIZARD_ACTIONS.SET_TYPE,
      selectedType: "Change"
    });
    state = dispatch(state, { type: WIZARD_ACTIONS.SET_STEP, step: 2 });
    expect(canLeaveCurrentStep(state)).toBe(true);

    state = dispatch(state, {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_START,
      contractServiceId: "svc1"
    });
    expect(state.async.loadingContractHistory).toBe(true);
    expect(canLeaveCurrentStep(state)).toBe(false);

    state = dispatch(state, {
      type: WIZARD_ACTIONS.SELECT_CONTRACT_SERVICE_SUCCESS,
      requestId: state.async.serviceRequestId,
      result: {
        historyId: "his1",
        historyName: "履歴1",
        version: 1,
        nextVersion: 2,
        renewEligible: true
      }
    });
    expect(canLeaveCurrentStep(state)).toBe(true);
  });

  it("詳細情報の明細読込中は次へ・保存できない", () => {
    let state = createInitialWizardState();
    state = dispatch(state, { type: WIZARD_ACTIONS.SET_STEP, step: 2 });
    expect(canLeaveCurrentStep(state)).toBe(true);

    state = dispatch(state, {
      type: WIZARD_ACTIONS.SET_STEP3_LOADING,
      loading: true
    });
    expect(state.async.loadingStep3).toBe(true);
    expect(canLeaveCurrentStep(state)).toBe(false);

    state = dispatch(state, {
      type: WIZARD_ACTIONS.SET_STEP3_LOADING,
      loading: false
    });
    expect(canLeaveCurrentStep(state)).toBe(true);
  });

  it("MERGE_STEP3 は許可リスト外のキーを無視し endDate を contractEndDate へ正規化する", () => {
    let state = createInitialWizardState();
    state = dispatch(state, {
      type: WIZARD_ACTIONS.MERGE_STEP3,
      fields: {
        contractStartDate: "2026-04-01",
        endDate: "2027-03-31",
        selectedProducts: [{ id: "r1", productId: "p1" }],
        invoiceTypeOptions: [{ label: "x", value: "y" }],
        unknownUiFlag: true
      }
    });

    expect(state.data.contractStartDate).toBe("2026-04-01");
    expect(state.data.contractEndDate).toBe("2027-03-31");
    expect(state.data.selectedProducts).toHaveLength(1);
    expect(state.data.invoiceTypeOptions).toBeUndefined();
    expect(state.data.unknownUiFlag).toBeUndefined();
    expect(Object.prototype.hasOwnProperty.call(state.data, "endDate")).toBe(
      false
    );
  });

  it("Modal3 が contractEndDate のみ emit しても親 state に反映される", () => {
    let state = createInitialWizardState();
    state = dispatch(state, {
      type: WIZARD_ACTIONS.MERGE_STEP3,
      fields: {
        contractEndDate: "2028-03-31",
        estimateRemarks: "備考"
      }
    });
    expect(state.data.contractEndDate).toBe("2028-03-31");
    expect(state.data.estimateRemarks).toBe("備考");
  });

  it("formatHistoryVersion は数値 Version だけを表示する", () => {
    expect(formatHistoryVersion(3)).toBe("3");
    expect(formatHistoryVersion("4")).toBe("4");
    expect(formatHistoryVersion(null)).toBe("");
    expect(formatHistoryVersion("abc")).toBe("");
  });
});
