const fs = require('fs');

const prettierConfig = fs.readFileSync('./.prettierrc', 'utf8');
const prettierOptions = JSON.parse(prettierConfig);
const isProduction = process.env.NODE_ENV === 'production';

module.exports = {
  extends: ['airbnb-base', 'prettier'],
  root: true,
  env: {
    node: true,
    es2020: true,
  },
  plugins: ['json', 'prettier'],
  parser: '@babel/eslint-parser',
  settings: {
    'import/resolver': {
      node: {
        extensions: ['.ts', '.js', '.json'],
        moduleDirectory: ['node_modules'],
      },
    },
  },
  reportUnusedDisableDirectives: isProduction,
  rules: {
    'import/no-extraneous-dependencies': ['off'],
    'no-debugger': 'off',
    'no-console': 'off',
    'no-plusplus': ['error', { allowForLoopAfterthoughts: true }],
    'no-underscore-dangle': 'error',
    'no-await-in-loop': 'off', // TODO: enable to improve performance
    'no-restricted-syntax': 'off', // Not critical for backend part
    'prefer-destructuring': 'off',
    'no-redeclare': [
      'error',
      {
        builtinGlobals: true,
      },
    ],
    'import/order': [
      'error',
      {
        groups: ['external', 'builtin', 'internal', 'type', 'parent', 'sibling', 'index', 'object'],
        alphabetize: {
          order: 'asc',
          caseInsensitive: true,
        },
        warnOnUnassignedImports: true,
        'newlines-between': 'always',
      },
    ],
    'prettier/prettier': ['error', prettierOptions],
    'import/prefer-default-export': 'off',
    'import/extensions': ['error', { json: 'always' }],
    'class-methods-use-this': 'off',
    'prefer-promise-reject-errors': 'off',
    'max-classes-per-file': 'off',
    'no-use-before-define': ['off'],
    'no-shadow': 'off',
  },
  overrides: [
    {
      files: ['./**/*.ts'],
      parser: '@typescript-eslint/parser',
      parserOptions: {
        project: './tsconfig.eslint.json',
        tsconfigRootDir: __dirname,
        sourceType: 'module',
      },
      extends: [
        'plugin:@typescript-eslint/eslint-recommended',
        'plugin:@typescript-eslint/recommended',
        'plugin:@typescript-eslint/recommended-requiring-type-checking',
      ],
      plugins: ['@typescript-eslint', 'prettier'],
      parserOptions: {
        project: ['./tsconfig.json'],
        warnOnUnsupportedTypeScriptVersion: true,
      },
      rules: {
        '@typescript-eslint/no-floating-promises': 'off',
        '@typescript-eslint/no-explicit-any': 'error',
        '@typescript-eslint/explicit-module-boundary-types': 'error',
        '@typescript-eslint/no-use-before-define': [
          'error',
          {
            functions: false,
            classes: false,
          },
        ],
        '@typescript-eslint/no-shadow': ['error'],
      },
    },
  ],
};
