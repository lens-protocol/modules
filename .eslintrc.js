module.exports = {
  env: {
    browser: false,
    es2021: true,
    mocha: true,
    node: true,
  },
  plugins: ['@typescript-eslint'],
  extends: ['standard', 'plugin:prettier/recommended', 'plugin:node/recommended'],
  parser: '@typescript-eslint/parser',
  parserOptions: {
    ecmaVersion: 12,
  },
  rules: {
    'node/no-unsupported-features/es-syntax': ['error', { ignores: ['modules'] }],
    'no-unused-vars': 'warn',
    'prefer-const': 'warn',
    eqeqeq: 'warn',
    camelcase: 'warn',
    'spaced-comment': 'warn',
    'node/no-unpublished-import': 'warn',
    'node/no-unpublished-require': 'warn',
    'eol-last': 'error',
  },
  overrides: [
    {
      files: ['*.test.ts', '*.spec.ts'],
      rules: {
        'no-unused-expressions': 'off',
      },
    },
    {
      files: ['*.ts'],
      rules: {
        'node/no-extraneous-import': 'off',
      },
    },
  ],
  settings: {
    node: {
      tryExtensions: ['.js', '.json', '.node', '.ts', '.d.ts'],
    },
  },
};
