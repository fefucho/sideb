import { getContext } from 'svelte';
import type { BrowseCardDto, HomeItemDto } from '../types';
import { MENU_CONTEXT, songFromHome, targetFromCard, type MenuOrigin, type MenuService, type MenuTarget } from './types';

/** Read the app-level menu dispatcher and provide mouse/keyboard handlers for one entity. */
export function createMenuHandlers() {
  const service = getContext<MenuService | undefined>(MENU_CONTEXT);
  return (target: MenuTarget | null | (() => MenuTarget | null), origin: MenuOrigin | (() => MenuOrigin) = {}) => {
    function open(event: MouseEvent | KeyboardEvent) {
      const resolvedTarget = typeof target === 'function' ? target() : target;
      if (!service || !resolvedTarget) return;
      if (event instanceof KeyboardEvent && !(event.shiftKey && (event.key === 'F10' || event.key === 'ContextMenu'))) return;
      event.preventDefault();
      service.open(event, resolvedTarget, typeof origin === 'function' ? origin() : origin);
    }
    return {
      onContextMenu: (event: MouseEvent) => open(event),
      onKeyDown: (event: KeyboardEvent) => open(event),
    };
  };
}

export function targetFromHome(item: HomeItemDto): MenuTarget | null {
  if (item.kind === 'song' || item.kind === 'video') return { kind: 'song', song: { ...songFromHome(item), isVideo: item.kind === 'video' } };
  const card: BrowseCardDto = { kind: item.kind, id: item.id, title: item.title, subtitle: item.subtitle, thumbnail: item.thumbnail, duration: item.duration };
  return targetFromCard(card);
}
