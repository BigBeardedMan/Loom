// Mirrors animation curves from the macOS app. Use these so timing stays
// consistent across components and matches SwiftUI .animation() calls.

export const motion = {
  blockDrag: "180ms cubic-bezier(0.0, 0.0, 0.2, 1)",
  dropIndicator: "120ms cubic-bezier(0.0, 0.0, 0.2, 1)",
  updatePill: "180ms cubic-bezier(0.4, 0.0, 0.2, 1)",
  reorderSpring: "320ms cubic-bezier(0.4, 0.0, 0.2, 1)",
  scrollSettle: "150ms cubic-bezier(0.0, 0.0, 0.2, 1)",
};

export const durationMs = {
  blockDrag: 180,
  dropIndicator: 120,
  updatePill: 180,
  reorderSpring: 320,
  scrollSettle: 150,
};
