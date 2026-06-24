/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./index.html'],
  theme: {
    extend: {
      colors: {
        bg:      '#0f1117',
        surface: { DEFAULT: '#1a1d27', 2: '#22263a' },
        stroke:  '#2e3250',
        accent:  { DEFAULT: '#6c63ff', 2: '#00d4aa' },
        muted:   '#7b80a0',
        danger:  '#ff5c5c',
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', '"Segoe UI"', 'sans-serif'],
        mono: ['"SF Mono"', 'Consolas', 'monospace'],
      },
    },
  },
  plugins: [],
}
