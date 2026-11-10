import { normalized } from '$lib/home/settings';
import type { AuthStatusDto } from '$lib/types';
import type { UpdaterController } from '$lib/updater/controller';

/** Mirrors Apple's SettingsSection/SettingsCategory: same raw identifiers, same grouping. */
export type SettingsSectionId = 'app' | 'content' | 'account';
export type SettingsCategoryId = 'general' | 'playback' | 'appearance' | 'shortcuts' | 'homeFeed' | 'visualProviders' | 'account';
export interface SettingsCategoryDefinition {
  id: SettingsCategoryId;
  section: SettingsSectionId;
  titleKey: string;
  subtitleKey: string;
}

export const settingsSections: readonly SettingsSectionId[] = ['app', 'content', 'account'];
export const settingsSectionKey = (section: SettingsSectionId) => `windows.settings.section.${section}`;

/** Declaration order is the Apple `allCases` order; the sidebar regroups it by section. */
export const settingsCategories: readonly SettingsCategoryDefinition[] = [
  { id: 'general', section: 'app', titleKey: 'settings.category.general', subtitleKey: 'windows.settings.subtitle.general' },
  { id: 'playback', section: 'app', titleKey: 'settings.category.playback', subtitleKey: 'windows.settings.subtitle.playback' },
  { id: 'appearance', section: 'app', titleKey: 'settings.category.appearance', subtitleKey: 'windows.settings.subtitle.appearance' },
  { id: 'shortcuts', section: 'app', titleKey: 'settings.category.shortcuts', subtitleKey: 'windows.settings.subtitle.shortcuts' },
  { id: 'homeFeed', section: 'content', titleKey: 'settings.category.homeFeed', subtitleKey: 'windows.settings.subtitle.homeFeed' },
  { id: 'visualProviders', section: 'content', titleKey: 'settings.category.visualProviders', subtitleKey: 'windows.settings.subtitle.visualProviders' },
  { id: 'account', section: 'account', titleKey: 'settings.category.account', subtitleKey: 'windows.settings.subtitle.account' },
];

/** Sidebar search: case/diacritic-insensitive match over title and subtitle, like Apple's matchingCategories. */
export function matchingCategories(query: string, translate: (key: string) => string): SettingsCategoryDefinition[] {
  const needle = normalized(query);
  if (!needle) return [...settingsCategories];
  return settingsCategories.filter(category => normalized(translate(category.titleKey)).includes(needle) || normalized(translate(category.subtitleKey)).includes(needle));
}

/** App-level services the page makes available to Settings without threading props through Home. */
export const SETTINGS_HOST_CONTEXT = Symbol('settings-host');
export interface SettingsHost {
  readonly auth: AuthStatusDto;
  readonly updater: UpdaterController;
  login(): void;
  cancelLogin(): void;
  logout(): void;
}
