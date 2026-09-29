const fs = require("fs");
const path = require("path");

const issuePage = fs.readFileSync(
  path.join(__dirname, "../../../pages/EstimateDocumentIssue.page"),
  "utf8"
);

describe("EstimateDocumentIssue success navigation (Core 4.8 / 4.3.1 / 7.10)", () => {
  it("keeps preview and send on the issue surface without a page redirect", () => {
    expect(issuePage).not.toMatch(/sforce\.one\.navigateToURL/);
    expect(issuePage).not.toMatch(/window\.location\.href/);
    expect(issuePage).not.toMatch(/\/lightning\/page\/filePreview/);
    expect(issuePage).not.toMatch(
      /\/lightning\/action\/quick\/ContractHistory__c\.Estimate_Send/
    );
    expect(issuePage).toMatch(/source:\s*"cmc-estimate-issue"/);
    expect(issuePage).toMatch(/postIssueAction\("preview"\)/);
    expect(issuePage).toMatch(/postIssueAction\("send"\)/);
    expect(issuePage).toMatch(/window\.parent\.postMessage/);
    expect(issuePage).toMatch(/onclick="openIssuedPreviewIfAny\(\)"/);
    expect(issuePage).toMatch(/このファイルを送る/);
    expect(issuePage).not.toMatch(/\(function\s*\(\)\s*\{/);
  });
});
