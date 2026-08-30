import ContractCrossWork from "c/contractCrossWork";

describe("contractCrossWork journal lock UI (Accounting 9.5 / 共通基盤 10.4)", () => {
  const proto = ContractCrossWork.prototype;
  const showCheckColumn = Object.getOwnPropertyDescriptor(
    proto,
    "showCheckColumn"
  ).get;
  const showUnlockReason = Object.getOwnPropertyDescriptor(
    proto,
    "showUnlockReason"
  ).get;
  const showJournalSave = Object.getOwnPropertyDescriptor(
    proto,
    "showJournalSave"
  ).get;
  const showJournalLockSelection = Object.getOwnPropertyDescriptor(
    proto,
    "showJournalLockSelection"
  ).get;
  const canLockJournalsNow = Object.getOwnPropertyDescriptor(
    proto,
    "canLockJournalsNow"
  ).get;
  const canUnlockJournalsNow = Object.getOwnPropertyDescriptor(
    proto,
    "canUnlockJournalsNow"
  ).get;

  function ctx(overrides) {
    const merged = {
      isJournalMenu: true,
      jouLock: "Unlocked",
      canLockJournalOp: false,
      canUnlockJournalOp: false,
      canEditJournalMemoOp: false,
      ...overrides
    };
    Object.defineProperty(merged, "isLockUnlocked", {
      get() {
        return this.jouLock === "Unlocked";
      }
    });
    Object.defineProperty(merged, "canLockJournalsNow", {
      get: canLockJournalsNow
    });
    Object.defineProperty(merged, "canUnlockJournalsNow", {
      get: canUnlockJournalsNow
    });
    Object.defineProperty(merged, "showJournalLockSelection", {
      get: showJournalLockSelection
    });
    return merged;
  }

  it("hides check, Unlock reason, and lock save without 16/17", () => {
    const state = ctx({ jouLock: "Unlocked" });
    expect(showJournalLockSelection.call(state)).toBe(false);
    expect(showCheckColumn.call(state)).toBe(false);
    expect(showUnlockReason.call(state)).toBe(false);
    expect(showJournalSave.call(state)).toBe(false);
  });

  it("hides memo and extra edit without 10 (共通基盤 1.4 / 10.4)", () => {
    const proto = ContractCrossWork.prototype;
    const cells = proto.journalCells.call(
      {
        journalGroups: [],
        canEditJournalMemoOp: false,
        journalColumnMode: true,
        extraDrafts: {},
        journalLockExemptFieldApiNames: [],
        journalExtraDefinitions: [
          { apiName: "Custom__c", label: "追加", fieldType: "STRING" }
        ]
      },
      { invoiceCancelled: false, invoiceName: "INV", isLocked: false },
      "メモ"
    );
    expect(cells.find((cell) => cell.isMemo === true).canEditMemo).toBe(false);
    expect(cells.find((cell) => cell.isExtra === true).disabled).toBe(true);
  });

  it("keeps memo save with 10 when Lock/Unlock are absent", () => {
    const state = ctx({ canEditJournalMemoOp: true });
    expect(showJournalLockSelection.call(state)).toBe(false);
    expect(showJournalSave.call(state)).toBe(true);
  });

  it("shows Lock selection with 16 on Unlocked filter and does not let 17 stand in", () => {
    const unlockOnly = ctx({
      jouLock: "Unlocked",
      canLockJournalOp: false,
      canUnlockJournalOp: true
    });
    expect(showJournalLockSelection.call(unlockOnly)).toBe(false);
    const withLock = ctx({
      jouLock: "Unlocked",
      canLockJournalOp: true,
      canUnlockJournalOp: false
    });
    expect(showJournalLockSelection.call(withLock)).toBe(true);
    expect(showCheckColumn.call(withLock)).toBe(true);
  });

  it("shows Unlock reason with 17 on Locked filter and does not let 16 stand in", () => {
    const withoutUnlock = ctx({
      jouLock: "Locked",
      canLockJournalOp: true,
      canUnlockJournalOp: false
    });
    expect(showUnlockReason.call(withoutUnlock)).toBe(false);
    expect(showJournalLockSelection.call(withoutUnlock)).toBe(false);
    const withUnlock = ctx({
      jouLock: "Locked",
      canLockJournalOp: false,
      canUnlockJournalOp: true
    });
    expect(showUnlockReason.call(withUnlock)).toBe(true);
    expect(showJournalLockSelection.call(withUnlock)).toBe(true);
  });
});
