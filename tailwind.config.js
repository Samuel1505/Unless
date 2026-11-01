/** @type {import('tailwindcss').Config} */
export default {
  future: {
    hoverOnlyWhenSupported: true,
  },
  content: [
    './index.html',
    './src/**/*.{js,ts,jsx,tsx}',
  ],
  theme: {
    extend: {
      colors: {
        paper: 'var(--paper)',
        ink: 'var(--ink)',
        carbon: 'var(--carbon)',
        settled: 'var(--settled)',
        objected: 'var(--objected)',
        rule: 'var(--rule)',
        muted: 'var(--muted)',
      },
      fontFamily: {
        display: ['"Bricolage Grotesque"', 'system-ui', 'sans-serif'],
        body: ['"Atkinson Hyperlegible"', 'system-ui', 'sans-serif'],
      },
      // Type scale from docs/05-FRONTEND-SPEC 5.2 (rem).
      fontSize: {
        'step--1': ['0.875rem', { lineHeight: '1.4' }],
        'step-0': ['1rem', { lineHeight: '1.5' }],
        'step-1': ['1.25rem', { lineHeight: '1.35' }],
        'step-2': ['1.563rem', { lineHeight: '1.25' }],
        'step-3': ['2.441rem', { lineHeight: '1.1' }],
        'step-4': ['3.815rem', { lineHeight: '1.02' }],
      },
      borderRadius: {
        field: '2px',
      },
    },
  },
  plugins: [],
}
