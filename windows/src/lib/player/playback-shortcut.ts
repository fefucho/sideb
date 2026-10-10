type SpaceEvent = Pick<KeyboardEvent, 'key' | 'code' | 'altKey' | 'ctrlKey' | 'metaKey' | 'shiftKey' | 'repeat' | 'isComposing' | 'defaultPrevented' | 'preventDefault'>;
export interface PlaybackSpaceFocus {
  hasTrack: boolean;
  editing: boolean;
  nativeControl: boolean;
  ownsSpace: boolean;
}

/** Native controls keep their activation/scroll behavior; background pages and track lists toggle audio. */
export function dispatchPlaybackSpace(event: SpaceEvent, focus: PlaybackSpaceFocus, toggle: () => void): boolean {
  if ((event.key !== ' ' && event.code !== 'Space') || event.defaultPrevented || event.isComposing ||
      event.altKey || event.ctrlKey || event.metaKey || event.shiftKey || !focus.hasTrack ||
      focus.editing || focus.nativeControl || focus.ownsSpace) return false;
  event.preventDefault();
  // Holding Space consumes repeats without flipping playback repeatedly or scrolling the page.
  if (!event.repeat) toggle();
  return true;
}

export function playbackSpaceFocus(element: Element | null, hasTrack: boolean): PlaybackSpaceFocus {
  return {
    hasTrack,
    editing: Boolean(element?.closest('input, textarea, select, [contenteditable]:not([contenteditable="false"]), [role="textbox"], iframe')),
    nativeControl: Boolean(element?.closest('button, a[href], summary, [role="button"], [role="checkbox"], [role="radio"], [role="switch"], [role="slider"], [role="combobox"], [role="listbox"], [role="menuitem"], [role="tab"]')),
    ownsSpace: Boolean(element?.closest('[data-native-space], .lyrics-scroll, [data-tauri-drag-region]')),
  };
}
