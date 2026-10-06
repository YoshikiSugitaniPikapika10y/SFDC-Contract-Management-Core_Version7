const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...jestConfig.moduleNameMapper,
    "^lightning/actions$":
      "<rootDir>/force-app/test/jest-mocks/lightning/actions.js",
    "^lightning/navigation$":
      "<rootDir>/force-app/test/jest-mocks/lightning/navigation.js",
    "^lightning/uiRecordApi$":
      "<rootDir>/force-app/test/jest-mocks/lightning/uiRecordApi.js"
  },
  modulePathIgnorePatterns: [
    "<rootDir>/.localdevserver",
    "<rootDir>/org-retrieve-deploy-src"
  ]
};
