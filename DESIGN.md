---
name: riri-vector-search
colors:
  bg: "#0f1117"
  surface: "#1a1d27"
  surface-2: "#22263a"
  stroke: "#2e3250"
  accent: "#34a853"
  accent-2: "#00bfa5"
  muted: "#7b80a0"
  danger: "#ff5c5c"
typography:
  heading:
    fontFamily: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif
    fontSize: 1.25rem
    fontWeight: 700
  body:
    fontFamily: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif
    fontSize: 0.875rem
  label:
    fontFamily: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif
    fontSize: 0.75rem
  mono:
    fontFamily: "SF Mono", Consolas, monospace
    fontSize: 0.875rem
rounded:
  sm: 8px
  md: 12px
  lg: 16px
  full: 9999px
spacing:
  xs: 6px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
---

## Overview

Deep-space dark theme for a multimodal vector-search demo tool. The UI evokes a
developer-grade control panel — precision over decoration. Every surface is
intentionally dark to keep visual attention on search results (images and text
cards) rather than the chrome.

## Colors

The palette is split into backgrounds, structural surfaces, and two accents.

- **bg (#0f1117):** Near-black base. The canvas on which everything sits.
- **surface (#1a1d27):** Primary cards, panels, and raised areas. Slightly lighter to lift content off the base.
- **surface-2 (#22263a):** Inputs, secondary cards, and skeleton loaders. One step up from surface.
- **stroke (#2e3250):** Borders and dividers. Low-contrast by design — structure without distraction.
- **accent (#34a853):** GCP Green (Google Green). Used for active tab states, DEMO badge, and registration actions.
- **accent-2 (#00bfa5):** GCP Teal. Used for search actions, score bars, and success feedback. Signals "go / result".
- **muted (#7b80a0):** Labels, placeholders, and secondary text. Readable but visually quiet.
- **danger (#ff5c5c):** Error toasts and validation feedback only.

Use `accent-2` for the primary search CTA to distinguish it from `accent` (registration). Never use both accents on the same interactive element.

## Typography

System UI fonts keep the interface feeling native on every platform. No web font requests.

- **heading:** Bold, 1.25rem. Section titles and the app name only.
- **body:** Regular, 0.875rem. All prose, input text, and card content.
- **label:** Regular, 0.75rem. Field labels, badges, and metadata. Always `muted` color unless indicating state.
- **mono:** Monospace, 0.875rem. API keys, document IDs, and GCS URIs.

## Components

### Cards (search results)

- Background: `surface-2`, border: `stroke`
- On hover (desktop): lift `-translate-y-0.5`, border shifts to `accent`
- Aspect ratio 1:1 for the thumbnail area. Text content fills the same area with centered, truncated text.
- Score bar: full width, `stroke` background, `accent-2` fill scaled to score percentage.

### Dropzone (file upload)

- Border: 2px dashed `stroke`
- On drag-over: border and subtle `accent/5` background fill
- The `<input type="file">` must carry `z-10` to sit above icon and label elements, ensuring tappability on mobile.
- Preview image replaces the icon+label on file selection.

### Tabs

- Inactive: `surface` background, `stroke` border, `muted` text
- Active: `accent` background, `accent` border, white text, `font-semibold`
- Full-width on mobile (`flex-1`)

### Mode pills (search mode selector)

- Inactive: transparent background, `stroke` border, `muted` text
- Active: `surface-2` background, `accent-2` border, `accent-2` text
- Wrap on narrow screens

### Toast notifications

background, `stroke` border, `muted` text

background, `stroke` border, `muted` text

- Active: `surface-2` background, `accent-2` border, `accent-2` text
- Wrap on narrow screens

### Toast notifications

- Success: `accent-2` background, `bg` text
- Error: `danger` background, white text
- Info: `surface-2` background, `stroke` border, white text
- Slide-in from the right, auto-dismiss after 3.2s

## Spacing & Rounding

- Container: `max-w-5xl`, horizontal padding `px-4` (mobile) / `px-6` (md+)
- Cards: `rounded-xl` (16px). Inputs and small elements: `rounded-lg` (8px). Pills: `rounded-full`.
- Section gaps: 20px between major sections, 12px between related elements.

## Mobile Considerations

- Touch targets must be at least 44×44px. Use `min-h-[44px]` or generous padding on interactive elements.
- File input overlays must use `z-10` to receive touch events above sibling DOM elements.
- The results grid uses `auto-fill` with `minmax(150px, 1fr)` so cards remain usable on narrow screens.
- Drag-and-drop is desktop-only; on mobile, tap-to-open-file-picker is the primary affordance.
