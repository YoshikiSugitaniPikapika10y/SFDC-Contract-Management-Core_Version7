const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...jestConfig.moduleNameMapper,
    "^lightning/actions$":
      "<rootDir>/force-app/test/jest-mocks/lightning/actions.js"
  },
  modulePathIgnorePatterns: [
    "<rootDir>/.localdevserver",
    "<rootDir>/org-retrieve-deploy-src"
  ]
};
