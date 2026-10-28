/** Apply the existing dislike policy to the identity captured at the click. */
export async function dislikeCurrentTrack(options: {
  videoId: string;
  entryId?: string;
  session: number;
  currentSession: () => number;
  rate: (song: {videoId: string}) => Promise<boolean>;
  removeRecommendation: (videoId: string) => void;
  filterRecommendations: (videoId: string) => Promise<unknown>;
  removeEntry: (entryId: string) => Promise<unknown>;
}) {
  const {videoId, entryId, session} = options;
  const changed = await options.rate({videoId});
  if (!changed || options.currentSession() !== session) return;
  options.removeRecommendation(videoId);
  await options.filterRecommendations(videoId);
  if (entryId && options.currentSession() === session) await options.removeEntry(entryId);
}
