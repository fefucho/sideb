import type { HomeItemDto, HomeSectionDto } from "$lib/types";

export interface HomeItemPresentation {
  id: string;
  record: HomeItemDto;
}

export interface HomeSectionPresentation {
  id: string;
  title: string;
  style: "largeCard" | "compactSong";
  items: HomeItemPresentation[];
  moreBrowseId: string | null;
  moreParams: string | null;
}

/** Prepares Home DTOs for rendering, keeping occurrence identities stable. */
export function homeSections(
  sections: HomeSectionDto[],
  selectedChipParams: string | null,
  preserveProviderOrder = false,
): HomeSectionPresentation[] {
  const sectionOccurrences = new Map<string, number>();
  const prepared = sections.flatMap((section, index) => {
    if (section.items.length === 0) return [];

    const identity = sectionIdentity(section);
    const occurrence = sectionOccurrences.get(identity) ?? 0;
    sectionOccurrences.set(identity, occurrence + 1);
    const id = `${selectedChipParams ?? "all"}|${identity}|${occurrence}`;
    const style = sectionStyle(section);
    const itemOccurrences = new Map<string, number>();
    const items = section.items.map((record) => {
      const key = `${record.kind}|${record.id}`;
      const itemOccurrence = itemOccurrences.get(key) ?? 0;
      itemOccurrences.set(key, itemOccurrence + 1);
      return { id: `${id}|${key}|${itemOccurrence}`, record };
    });

    return [{
      id,
      title: section.title,
      moreBrowseId: section.moreBrowseId,
      moreParams: section.moreParams,
      style,
      items,
      providerIndex: index,
    }];
  });

  if (selectedChipParams !== null || preserveProviderOrder) {
    return prepared.map(({ providerIndex: _providerIndex, ...section }) => section);
  }

  return prepared
    .sort((left, right) => {
      const priorityDifference = sectionPriority(left.title) - sectionPriority(right.title);
      return priorityDifference || left.providerIndex - right.providerIndex;
    })
    .map(({ providerIndex: _providerIndex, ...section }) => section);
}

export function sectionIdentity(section: HomeSectionDto): string {
  const first = section.items[0];
  const last = section.items[section.items.length - 1];
  const endpoints = `${first?.kind ?? ""}:${first?.id ?? ""}|${last?.kind ?? ""}:${last?.id ?? ""}`;
  return section.moreBrowseId ? `more|${section.moreBrowseId}|${section.moreParams ?? ""}|${endpoints}` : `items|${endpoints}`;
}

function sectionStyle(section: HomeSectionDto): HomeSectionPresentation["style"] {
  const title = normalize(section.title);
  if (isListenAgain(title) || isForgottenFavorites(title)) return "largeCard";

  const allSongs = section.items.every((item) => item.kind === "song");
  const compactFormat = section.format === "compactSongs";
  const quickPicks = ["quick picks", "selecciones rapidas"].includes(title);
  return allSongs && (compactFormat || quickPicks) ? "compactSong" : "largeCard";
}

export function sectionPriority(title: string): number {
  const normalized = normalize(title);
  if (isListenAgain(normalized)) return 0;
  if (isForgottenFavorites(normalized)) return 1;
  if (["albums for you", "albumes para ti"].includes(normalized)) return 2;
  if (["from your library", "de tu biblioteca", "de la biblioteca"].includes(normalized)) return 3;
  if (["quick picks", "selecciones rapidas"].includes(normalized)) return 5;
  return 6;
}

function isListenAgain(title: string): boolean {
  return ["listen again", "vuelve a escucharlo", "volver a escuchar", "escuchar de nuevo"].includes(title);
}

function isForgottenFavorites(title: string): boolean {
  return ["forgotten favorites", "forgotten favourites", "favoritos olvidados"].includes(title);
}

function normalize(title: string): string {
  return title.trim().toLocaleLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}
