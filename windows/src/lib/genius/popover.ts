export interface AnchorRect { left: number; top: number; right: number; bottom: number; width: number; height: number; }
export interface AnnotationPlacement { left: number; top: number; width: number; maxHeight: number; arrowSide: 'left' | 'right' | 'top' | 'bottom'; arrowOffset: number; }
const clamp = (value: number, minimum: number, maximum: number) => Math.min(Math.max(value, minimum), Math.max(minimum, maximum));

/** Prefer Apple's trailing arrow; keep the arrow aligned to the actual clicked line. */
export function annotationPlacement(anchor: AnchorRect, height: number, viewport: { width: number; height: number }): AnnotationPlacement {
  const margin = 16, gap = 10;
  const width = Math.min(400, Math.max(0, viewport.width - margin * 2));
  const maxHeight = Math.min(520, Math.max(0, viewport.height - margin * 2));
  const actualHeight = Math.min(height, maxHeight);
  const centerX = (anchor.left + anchor.right) / 2;
  const centerY = (anchor.top + anchor.bottom) / 2;
  let left: number, top: number, arrowSide: AnnotationPlacement['arrowSide'];
  if (anchor.left - gap - width >= margin) {
    left = anchor.left - gap - width; top = clamp(centerY - actualHeight / 2, margin, viewport.height - margin - actualHeight); arrowSide = 'right';
  } else if (anchor.right + gap + width <= viewport.width - margin) {
    left = anchor.right + gap; top = clamp(centerY - actualHeight / 2, margin, viewport.height - margin - actualHeight); arrowSide = 'left';
  } else {
    left = clamp(centerX - width / 2, margin, viewport.width - margin - width);
    const below = viewport.height - margin - anchor.bottom - gap;
    const above = anchor.top - gap - margin;
    const useBelow = below >= Math.min(actualHeight, 160) || below >= above;
    const available = Math.max(0, useBelow ? below : above);
    const boundedHeight = Math.min(actualHeight, available);
    top = useBelow ? anchor.bottom + gap : anchor.top - gap - boundedHeight;
    arrowSide = useBelow ? 'top' : 'bottom';
    return { left, top, width, maxHeight: Math.min(maxHeight, available), arrowSide, arrowOffset: clamp(centerX - left, 18, width - 18) };
  }
  return { left, top, width, maxHeight, arrowSide, arrowOffset: clamp(centerY - top, 18, actualHeight - 18) };
}

export function annotationVisibleRect(anchor: AnchorRect, viewport: { width: number; height: number }, clip?: AnchorRect): AnchorRect | null {
  const left = Math.max(0, clip?.left ?? 0), top = Math.max(0, clip?.top ?? 0);
  const right = Math.min(viewport.width, clip?.right ?? viewport.width), bottom = Math.min(viewport.height, clip?.bottom ?? viewport.height);
  const visible = { left: Math.max(anchor.left, left), top: Math.max(anchor.top, top), right: Math.min(anchor.right, right), bottom: Math.min(anchor.bottom, bottom) };
  const width = visible.right - visible.left, height = visible.bottom - visible.top;
  return anchor.width > 0 && anchor.height > 0 && width > 0 && height > 0 ? { ...visible, width, height } : null;
}
export function annotationAnchorVisible(anchor: AnchorRect, viewport: { width: number; height: number }, clip?: AnchorRect): boolean {
  return annotationVisibleRect(anchor, viewport, clip) !== null;
}
