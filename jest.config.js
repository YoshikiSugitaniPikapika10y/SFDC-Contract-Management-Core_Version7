const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: [
        '<rootDir>/.localdevserver',
        '<rootDir>/org-retrieve-deploy-src'
    ]
};
