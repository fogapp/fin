import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import tseslint from 'typescript-eslint'
import { defineConfig, globalIgnores } from 'eslint/config'

export default defineConfig([
  // dist/ and coverage/ are build output — linting them reports offenses in
  // vendored istanbul scripts that no one can act on.
  globalIgnores(['dist', 'coverage']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      js.configs.recommended,
      tseslint.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      globals: globals.browser,
    },
    rules: {
      // Native dialogs are unthemed and inaccessible; the app has primitives.
      'no-restricted-globals': [
        'error',
        { name: 'confirm', message: 'Use useConfirm() from @/components/ui/confirm.' },
        { name: 'alert', message: 'Use toast from @/components/ui/toast.' },
        { name: 'prompt', message: 'Use a Dialog with an Input instead.' },
      ],
      'no-restricted-properties': [
        'error',
        { object: 'window', property: 'confirm', message: 'Use useConfirm() from @/components/ui/confirm.' },
        { object: 'window', property: 'alert', message: 'Use toast from @/components/ui/toast.' },
        { object: 'window', property: 'prompt', message: 'Use a Dialog with an Input instead.' },
      ],
    },
  },
  {
    // ui/ primitives re-export Radix roots and imperative APIs (toast) beside
    // their components; fast-refresh purity doesn't apply to this leaf layer.
    files: ['src/components/ui/**/*.tsx'],
    rules: {
      'react-refresh/only-export-components': 'off',
    },
  },
])
